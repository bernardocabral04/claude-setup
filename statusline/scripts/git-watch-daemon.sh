#!/usr/bin/env bash
# Per-repo git-watch daemon. Detects upstream changes via `git ls-remote`
# (no object download), fetches only on SHA mismatch, listens to local
# .git/ changes via fswatch, and applies adaptive backoff. Self-GCs
# stale cache files on startup. Self-exits on heartbeat idle.

set -u

# Cache paths derived from the repo path.
CACHE_DIR="${CLAUDE_GIT_WATCH_CACHE_DIR:-$HOME/.claude/cache/git-fetch}"

# Tuning knobs (all overridable via env).
ACTIVE_INTERVAL="${CLAUDE_GIT_WATCH_ACTIVE_INTERVAL:-5}"
MAX_INTERVAL="${CLAUDE_GIT_WATCH_MAX_INTERVAL:-120}"
IDLE_EXIT="${CLAUDE_GIT_WATCH_IDLE_EXIT:-1800}"
GC_AGE="${CLAUDE_GIT_WATCH_GC_AGE:-604800}"
DEBUG="${CLAUDE_GIT_WATCH_DEBUG:-}"

# Atomic per-repo lock via `ln tmp pid` (hardlink is atomic).
# Returns 0 if we acquired the lock (writes our PID to $PID_FILE).
# Returns 1 if another live daemon already holds it.
acquire_lock() {
  local tmp="$PID_FILE.tmp.$$"
  echo "$$" > "$tmp"
  if ln "$tmp" "$PID_FILE" 2>/dev/null; then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  local pid
  pid=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    return 1  # live owner
  fi
  # Stale — owner died without trap cleanup. Best-effort reclaim.
  rm -f "$PID_FILE"
  echo "$$" > "$tmp"
  if ln "$tmp" "$PID_FILE" 2>/dev/null; then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# Adaptive backoff: 5s * 2^idle_count, capped at MAX_INTERVAL.
# idle_count=0 returns ACTIVE_INTERVAL (the reset value after any event).
compute_next_interval() {
  local idle="$1"
  local val=$(( ACTIVE_INTERVAL * (1 << idle) ))
  # Shift overflow protection — bash >64 shifts are UB; cap manually.
  if [ "$idle" -ge 30 ] || [ "$val" -gt "$MAX_INTERVAL" ] || [ "$val" -lt 0 ]; then
    val="$MAX_INTERVAL"
  fi
  echo "$val"
}

# Reads ls-remote stdout, prints just the 40-char SHA of the first line.
# Empty input → empty output (no error).
parse_ls_remote_sha() {
  awk 'NR==1 { print $1; exit }'
}

# Delete all $key.* files whose heartbeat is older than GC_AGE,
# unless $key.pid points at a live process.
# Runs in-process at daemon startup, once.
gc_sweep() {
  [ -d "$CACHE_DIR" ] || return 0
  local now hb_path key age pid_path pid
  now=$(date +%s)
  for hb_path in "$CACHE_DIR"/*.heartbeat; do
    [ -e "$hb_path" ] || continue
    key="${hb_path%.heartbeat}"
    key="${key##*/}"
    age=$(( now - $(stat -f %m "$hb_path" 2>/dev/null || echo "$now") ))
    if [ "$age" -lt "$GC_AGE" ]; then
      continue  # fresh, keep
    fi
    pid_path="$CACHE_DIR/$key.pid"
    if [ -f "$pid_path" ]; then
      pid=$(cat "$pid_path" 2>/dev/null)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        continue  # alive owner, keep
      fi
    fi
    # Delete the whole family for this key.
    rm -f "$CACHE_DIR/$key.pid" \
          "$CACHE_DIR/$key.heartbeat" \
          "$CACHE_DIR/$key.events" \
          "$CACHE_DIR/$key.last-sha" \
          "$CACHE_DIR/$key.last-check" \
          "$CACHE_DIR/$key.log"
  done
}

# Poll-mode fallback when fswatch is unavailable.
# Compares the combined mtime of .git/HEAD + .git/refs/heads/<branch>
# against the cached LAST_REFS_MTIME. Updates the cache.
# Returns 0 if changed (or first call), 1 if unchanged.
LAST_REFS_MTIME=""
check_local_refs_mtime() {
  local head_path branch ref_path stamp
  head_path="$REPO/.git/HEAD"
  branch=$(git -C "$REPO" -c gc.auto=0 symbolic-ref --short HEAD 2>/dev/null || echo "")
  ref_path=""
  [ -n "$branch" ] && ref_path="$REPO/.git/refs/heads/$branch"
  stamp=""
  [ -f "$head_path" ] && stamp="${stamp}$(stat -f %m "$head_path" 2>/dev/null):"
  [ -n "$ref_path" ] && [ -f "$ref_path" ] && stamp="${stamp}$(stat -f %m "$ref_path" 2>/dev/null):"
  if [ "$stamp" != "$LAST_REFS_MTIME" ]; then
    LAST_REFS_MTIME="$stamp"
    return 0
  fi
  return 1
}

# Path of the event FIFO for this repo. Set after key is computed.
FIFO_PATH=""
FSWATCH_PID=""
FSWATCH_MODE="event"  # "event" if fswatch alive, "poll" if not available/dead

# Ensure FIFO exists at FIFO_PATH; recreate if it's not a pipe.
ensure_fifo() {
  if [ -e "$FIFO_PATH" ] && [ ! -p "$FIFO_PATH" ]; then
    rm -f "$FIFO_PATH"
  fi
  [ -p "$FIFO_PATH" ] || mkfifo "$FIFO_PATH"
}

# Spawn fswatch child writing NUL-separated event records to FIFO.
# Sets FSWATCH_PID + FSWATCH_MODE. Safe to call once at startup.
# After spawning, opens the FIFO read-write on FD 3 so subsequent `read -t -u 3`
# never blocks on the FIFO-open step (only on the timed read itself).
spawn_fswatch() {
  if ! command -v fswatch >/dev/null 2>&1; then
    FSWATCH_MODE="poll"
    log_event "fswatch unavailable, using mtime-poll fallback"
    return 0
  fi
  ensure_fifo
  fswatch -0 --event Updated --event Created --event Removed \
    "$REPO/.git/HEAD" "$REPO/.git/refs" > "$FIFO_PATH" 2>>"$LOG_FILE" &
  FSWATCH_PID=$!
  disown 2>/dev/null || true
  # Open FIFO rw on FD 3 — this returns immediately even if no writer is
  # currently connected (a plain `<` open would block until a writer attached).
  exec 3<> "$FIFO_PATH"
  FSWATCH_MODE="event"
}

# Adaptive sleep that doubles as event channel. Returns 0 if interrupted by
# event (local .git/ change), 1 if the sleep elapsed without an event.
# Detects fswatch death and downgrades to poll mode for the rest of this run.
wait_or_event() {
  local secs="$1"
  # If we thought we were in event mode but fswatch died, downgrade.
  if [ "$FSWATCH_MODE" = "event" ] && [ -n "$FSWATCH_PID" ] \
     && ! kill -0 "$FSWATCH_PID" 2>/dev/null; then
    log_event "fswatch child died (pid=$FSWATCH_PID); downgrading to poll mode"
    FSWATCH_MODE="poll"
    exec 3<&-  # close the FIFO FD; not needed in poll mode
  fi
  if [ "$FSWATCH_MODE" = "event" ]; then
    # `read -t` returns 0 if it read anything (a NUL-terminated event from
    # fswatch), non-zero on timeout. Payload is discarded — presence is signal.
    if IFS= read -r -d '' -t "$secs" -u 3 _; then
      return 0
    fi
    return 1
  fi
  # Poll mode: sleep + manually check mtimes. check_local_refs_mtime returns
  # 0 only on a real change because main() captured the baseline before entry.
  sleep "$secs"
  if check_local_refs_mtime; then
    return 0
  fi
  return 1
}

# Append to log with millisecond timestamp; gated by DEBUG.
log_event() {
  [ -n "$DEBUG" ] || return 0
  printf '[%s] %s\n' "$(date +%FT%T)" "$*" >> "$LOG_FILE"
}

# Cap log size; called after every git invocation.
trim_log() {
  [ -f "$LOG_FILE" ] || return 0
  local size
  size=$(stat -f %z "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$size" -gt 65536 ]; then
    tail -c 32768 "$LOG_FILE" > "$LOG_FILE.tmp" && mv -f "$LOG_FILE.tmp" "$LOG_FILE"
  fi
}

# Resolve $REPO and derive cache key + paths. Sets:
#   REPO, KEY, PID_FILE, HEARTBEAT, LOG_FILE, FIFO_PATH,
#   LAST_SHA_FILE, LAST_CHECK_FILE
# Returns 1 if the path is not a valid git repo.
init_paths() {
  REPO="${1:-}"
  [ -z "$REPO" ] && return 1
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || return 1
  mkdir -p "$CACHE_DIR"
  KEY=$(printf '%s' "$REPO" | shasum 2>/dev/null | awk '{print $1}')
  [ -z "$KEY" ] && return 1
  PID_FILE="$CACHE_DIR/$KEY.pid"
  HEARTBEAT="$CACHE_DIR/$KEY.heartbeat"
  LOG_FILE="$CACHE_DIR/$KEY.log"
  FIFO_PATH="$CACHE_DIR/$KEY.events"
  LAST_SHA_FILE="$CACHE_DIR/$KEY.last-sha"
  LAST_CHECK_FILE="$CACHE_DIR/$KEY.last-check"
  return 0
}

# One iteration of remote-change detection.
# Returns 0 if upstream SHA matches cache (no change),
# Returns 1 if mismatch detected and fetch attempted (success or failure).
# Returns 2 if upstream isn't configured (no @{upstream}).
check_remote_once() {
  local upstream remote_url branch remote_sha cached_sha
  if ! upstream=$(git -C "$REPO" -c gc.auto=0 rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null); then
    return 2
  fi
  # upstream is like "origin/main" — split into remote + branch
  remote_url="${upstream%%/*}"
  branch="${upstream#*/}"
  remote_sha=$(git -C "$REPO" -c gc.auto=0 ls-remote --exit-code "$remote_url" "refs/heads/$branch" 2>>"$LOG_FILE" \
    | parse_ls_remote_sha)
  date +%s > "$LAST_CHECK_FILE"
  if [ -z "$remote_sha" ]; then
    log_event "ls-remote returned empty SHA (network error?)"
    return 1  # treat as "we tried, but couldn't determine"
  fi
  cached_sha=$(cat "$LAST_SHA_FILE" 2>/dev/null || echo "")
  if [ "$remote_sha" = "$cached_sha" ]; then
    return 0  # no change
  fi
  log_event "remote SHA changed: $cached_sha → $remote_sha; fetching"
  if git -C "$REPO" -c gc.auto=0 fetch --quiet --no-tags --prune 2>>"$LOG_FILE"; then
    echo "$remote_sha" > "$LAST_SHA_FILE"
  else
    log_event "fetch failed; will retry next cycle"
  fi
  trim_log
  return 1
}

# Returns 0 if statusline has touched the heartbeat within $1 seconds.
heartbeat_recent() {
  local window="$1"
  [ -f "$HEARTBEAT" ] || return 1
  local age
  age=$(( $(date +%s) - $(stat -f %m "$HEARTBEAT" 2>/dev/null || echo 0) ))
  [ "$age" -le "$window" ]
}

# Returns 0 if heartbeat has been idle past IDLE_EXIT.
heartbeat_idle_exit() {
  [ -f "$HEARTBEAT" ] || return 1
  local age
  age=$(( $(date +%s) - $(stat -f %m "$HEARTBEAT" 2>/dev/null || echo 0) ))
  [ "$age" -gt "$IDLE_EXIT" ]
}

cleanup() {
  [ -n "$FSWATCH_PID" ] && kill "$FSWATCH_PID" 2>/dev/null || true
  rm -f "$PID_FILE"
}

main() {
  init_paths "$1" || exit 1
  acquire_lock || exit 0
  trap cleanup EXIT
  trap 'exit 0' INT TERM HUP

  # Env shields — never block on creds, pagers, or hung connections.
  export GIT_TERMINAL_PROMPT=0
  export GIT_ASKPASS=/bin/true
  export SSH_ASKPASS=/bin/true
  export GIT_PAGER=cat
  export GIT_HTTP_LOW_SPEED_LIMIT=1
  export GIT_HTTP_LOW_SPEED_TIME=10

  gc_sweep
  spawn_fswatch

  # Prime the poll-mode baseline so the first wait_or_event in poll mode
  # doesn't falsely report a change. No-op in event mode.
  if [ "$FSWATCH_MODE" = "poll" ]; then
    check_local_refs_mtime >/dev/null || true
  fi

  local idle_count=0
  local interval
  while true; do
    check_remote_once
    rc=$?
    if [ "$rc" -eq 0 ]; then
      idle_count=$(( idle_count + 1 ))
    else
      # Change detected, or upstream not configured — either way, reset.
      idle_count=0
    fi

    interval=$(compute_next_interval "$idle_count")
    log_event "sleep ${interval}s (idle_count=$idle_count, mode=$FSWATCH_MODE)"

    if wait_or_event "$interval"; then
      # Event received — reset backoff.
      idle_count=0
      log_event "event received, backoff reset"
    fi

    # Render-burst detection: if we're backed off and heartbeat moved recently,
    # treat it as activity and reset.
    if [ "$interval" -gt "$ACTIVE_INTERVAL" ] && heartbeat_recent 15; then
      idle_count=0
      log_event "render burst, backoff reset"
    fi

    if heartbeat_idle_exit; then
      log_event "heartbeat idle past IDLE_EXIT, exiting"
      exit 0
    fi
  done
}

# Source guard — when sourced from a test, return before running main.
[ "${BASH_SOURCE[0]}" = "${0}" ] || return 0

# Past this point we're the script entry.
main "$@"
