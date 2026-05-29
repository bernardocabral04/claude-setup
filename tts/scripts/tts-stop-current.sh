#!/bin/bash
# Claude Code TTS — Stop CURRENT session's speech.
# Resolves the focused terminal window → TTY → CC pid → session id → audio pid.
# Only iTerm2 and Apple Terminal are supported; any other focused app exits 1.
# Does NOT fall through to "Stop ALL" on error.

export LC_ALL=C

SESSIONS_DIR="$HOME/.claude/sessions"
TTS_DIR="$HOME/.claude/tts-sessions"
STOP_LOG="$TTS_DIR/.stop.log"

mkdir -p "$TTS_DIR"

log() {
  echo "$(date -u +%FT%TZ) | $1" >> "$STOP_LOG"
}

# notify_done: success → loud. notify_info: noop/can't-locate → silent banner.
notify_done() {
  /usr/bin/osascript -e 'display notification "Silenced focused claude session" with title "Claude TTS" sound name "Submarine"' 2>/dev/null || true
}
notify_info() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"Claude TTS\"" 2>/dev/null || true
}

# ── Step 1: Resolve focused application's bundle id ──────────────────────────

FRONT=$(osascript -e \
  'tell application "System Events" to get bundle identifier of first application process whose frontmost is true' \
  2>/dev/null)

# ── Step 2: Get the active TTY for the supported terminal ────────────────────

case "$FRONT" in
  com.googlecode.iterm2)
    TTY_RAW=$(osascript -e \
      'tell application "iTerm2" to tell current session of current window to get tty' \
      2>/dev/null)
    ;;
  com.apple.Terminal)
    TTY_RAW=$(osascript -e \
      'tell application "Terminal" to tell front window to get tty of selected tab' \
      2>/dev/null)
    ;;
  *)
    log "STOP-CURRENT unsupported terminal: ${FRONT:-<none>}"
    notify_info "No Claude session in this terminal"
    exit 1
    ;;
esac

if [ -z "$TTY_RAW" ]; then
  log "STOP-CURRENT could not read tty from terminal: $FRONT"
  notify_info "No Claude session in this terminal"
  exit 1
fi

# Strip /dev/ prefix; ps -t accepts both forms but we normalise for log lines.
TTY="${TTY_RAW#/dev/}"

# ── Step 3: Find the CC process on this TTY ──────────────────────────────────
# For each row of `ps -t`, take basename(argv[0]) and check for an exact match
# against 'claude' or 'clausona' (the work-profile wrapper). First match wins.

CC_PID=""
while read -r pid argv0 _rest; do
  [ -z "$pid" ] && continue
  base=$(basename -- "$argv0")
  if [ "$base" = "claude" ] || [ "$base" = "clausona" ]; then
    CC_PID="$pid"
    break
  fi
done < <(ps -t "$TTY" -o pid=,command= 2>/dev/null)

if [ -z "$CC_PID" ]; then
  log "STOP-CURRENT no claude process on tty $TTY"
  notify_info "No Claude session in this terminal"
  exit 1
fi

# ── Step 4: Read sessionId from CC's session JSON ────────────────────────────

SESSION_FILE="$SESSIONS_DIR/$CC_PID.json"
if [ ! -f "$SESSION_FILE" ]; then
  log "STOP-CURRENT no session json for pid $CC_PID"
  notify_info "No Claude session in this terminal"
  exit 1
fi

SID=$(jq -r '.sessionId // empty' "$SESSION_FILE" 2>/dev/null)
if [ -z "$SID" ]; then
  log "STOP-CURRENT sessionId missing in $SESSION_FILE"
  notify_info "No Claude session in this terminal"
  exit 1
fi

# ── Step 5: Read the audio pidfile ───────────────────────────────────────────

PIDFILE="$TTS_DIR/$SID.pid"
if [ ! -f "$PIDFILE" ]; then
  log "STOP-CURRENT no live pid for $SID"
  notify_info "Nothing speaking in this session"
  exit 0
fi

AUDIO_PID=$(cat "$PIDFILE" 2>/dev/null)
if [ -z "$AUDIO_PID" ]; then
  rm -f "$PIDFILE"
  log "STOP-CURRENT no live pid for $SID"
  notify_info "Nothing speaking in this session"
  exit 0
fi

# ── Step 6: Kill the audio process and clean up ──────────────────────────────

if ! kill "$AUDIO_PID" 2>/dev/null; then
  # kill failed — only OK if the process is already gone (goal is silence).
  if kill -0 "$AUDIO_PID" 2>/dev/null; then
    log "STOP-CURRENT kill failed for pid $AUDIO_PID sid=$SID"
    notify_info "Could not silence — try ⌘⌥⇧."
    exit 1
  fi
fi
rm -f "$PIDFILE"
log "STOP-CURRENT sid=$SID"
notify_done
exit 0
