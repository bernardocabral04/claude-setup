#!/usr/bin/env bash
# Claude Code Stop-hook for the consolidator add-on.
#
# Phase 1 (sync, <50ms target): cheap gates. Bail out silently if any fail.
# Phase 2 (background): full eval pipeline, see `_run_eval` below.

# Recursion guard: the fallback `claude -p` subprocess fires its own Stop
# hook; this short-circuits before doing anything.
[ "${CLAUDE_CONSOLIDATOR:-}" = "1" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

[ -z "$SESSION_ID" ] && exit 0

CONF_GLOBAL="$HOME/.claude/consolidator.conf"
SESS_DIR="$HOME/.claude/consolidator-sessions"
FLAG="$SESS_DIR/$SESSION_ID"
CURSOR="$SESS_DIR/$SESSION_ID.cursor"
STATEFILE="$SESS_DIR/$SESSION_ID.state"
METRICS_LOG="$SESS_DIR/$SESSION_ID.metrics.log"
DEBUG_LOG="$SESS_DIR/$SESSION_ID.debug.log"
LAST_JSON="$SESS_DIR/$SESSION_ID.last.json"

[ -f "$FLAG" ] || exit 0
[ -n "$TRANSCRIPT" ] || exit 0
[ -f "$TRANSCRIPT" ] || exit 0

# Layered conf: global, then per-session override file (which IS the flag).
# shellcheck disable=SC1090
[ -f "$CONF_GLOBAL" ] && . "$CONF_GLOBAL"
# shellcheck disable=SC1090
. "$FLAG"

# Defaults if neither file set them.
: "${CONSOLIDATOR_COOLDOWN_SEC:=60}"
: "${CONSOLIDATOR_MIN_NEW_BYTES:=2000}"
: "${CONSOLIDATOR_MAX_DECISIONS_PER_RUN:=3}"
: "${CONSOLIDATOR_MAX_FAILED_ATTEMPTS:=3}"
: "${CONSOLIDATOR_ENABLED_TYPES:=user,feedback,project,reference}"
: "${CONSOLIDATOR_ENGINE:=auto}"

# Source the lib for shared functions. Resolve relative to this script so
# tests can override $HOME without breaking the lib lookup.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB="$SCRIPT_DIR/consolidator-lib.sh"
# shellcheck disable=SC1090
. "$LIB"

read_cursor "$CURSOR"
TRANSCRIPT_SIZE=$(stat -f %z "$TRANSCRIPT" 2>/dev/null || echo 0)
NEW_BYTES=$((TRANSCRIPT_SIZE - LAST_EVAL_OFFSET))
NOW=$(date +%s)
ELAPSED=$((NOW - LAST_EVAL_AT))

if [ "$NEW_BYTES" -lt "$CONSOLIDATOR_MIN_NEW_BYTES" ]; then
  exit 0
fi
if [ "$ELAPSED" -lt "$CONSOLIDATOR_COOLDOWN_SEC" ]; then
  exit 0
fi

# Fork the heavy work — detached background subshell.
(
  MEM_DIR=""
  _cleanup_statefile() {
    # Preserve engine-error states so statusline + status can surface them.
    if [ -f "$STATEFILE" ] && grep -q '^engine-error:' "$STATEFILE" 2>/dev/null; then
      return 0
    fi
    rm -f "$STATEFILE"
  }
  trap 'if [ -n "$MEM_DIR" ]; then release_lock "$MEM_DIR/.lock" 2>/dev/null; fi; _cleanup_statefile' EXIT

  echo evaluating > "$STATEFILE"

  T_START=$(date +%s)

  # Resolve and bootstrap the memory dir up-front, so even an empty-slice
  # tick leaves a usable MEMORY.md scaffold behind.
  ENCODED=$(encode_cwd "$CWD")
  # Co-locate with native auto-memory; profile-aware via CLAUDE_CONFIG_DIR.
  MEM_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$ENCODED/memory"
  bootstrap_mem_dir "$MEM_DIR"

  # Slice the transcript from the cursor.
  SLICE=$(extract_slice "$TRANSCRIPT" "$LAST_EVAL_OFFSET")
  if [ -z "$SLICE" ]; then
    # Nothing user/assistant in the slice — advance cursor and exit.
    write_cursor "$CURSOR" "$TRANSCRIPT_SIZE" "$NOW" $((EVAL_COUNT + 1)) 0
    echo "$(date -u +%FT%TZ) | SKIP: empty slice | extract=$(($(date +%s) - T_START))s" >> "$METRICS_LOG"
    exit 0
  fi

  # Acquire the per-cwd lock.
  if ! acquire_lock "$MEM_DIR/.lock" 5; then
    echo "$(date -u +%FT%TZ) | SKIP: lock timeout" >> "$METRICS_LOG"
    exit 0
  fi

  # Sweep any orphaned .tmp/ files from a previous run that crashed mid-write.
  rm -f "$MEM_DIR/.tmp/"*.md.* 2>/dev/null || true

  # Build prompts.
  EVAL_PROMPT=$(cat "$SCRIPT_DIR/consolidator-eval-prompt.txt" 2>/dev/null || echo "")
  EXISTING=$(cat "$MEM_DIR/MEMORY.md" 2>/dev/null || echo "")
  TODAY=$(date -u +%Y-%m-%d)
  PAYLOAD=$(printf "Today's date: %s\nCwd: %s\n\n<existing_memories>\n%s\n</existing_memories>\n\n<new_conversation_chunk>\n%s\n</new_conversation_chunk>\n\nEvaluate the chunk against the existing memories. Apply the rules in your system prompt. Return decisions JSON only." "$TODAY" "$CWD" "$EXISTING" "$SLICE")

  # Call the LLM.
  echo writing > "$STATEFILE"
  T_LLM_START=$(date +%s)
  # Let call_llm write engine-error states (e.g., engine=openrouter + no key),
  # overwriting the "writing" state above if an error occurs.
  export CONSOLIDATOR_STATEFILE="$STATEFILE"
  RESPONSE=$(call_llm "$EVAL_PROMPT" "$PAYLOAD")
  T_LLM_END=$(date +%s)

  # Persist the raw response for /consolidator-status to surface.
  printf '%s' "$RESPONSE" > "$LAST_JSON"

  # Parse + validate.
  ROWS=$(parse_decisions "$RESPONSE")

  # Strip markdown fences before validating (claude -p often wraps JSON).
  CLEAN_RESPONSE=$(printf '%s' "$RESPONSE" | sed -e '/^[[:space:]]*```/d')

  # If the response was malformed/empty, do not advance cursor; bump fails.
  if [ -z "$CLEAN_RESPONSE" ] || ! printf '%s' "$CLEAN_RESPONSE" | jq -e '.decisions' >/dev/null 2>&1; then
    NEW_FAILS=$((FAILED_ATTEMPTS + 1))
    if [ "$NEW_FAILS" -ge "$CONSOLIDATOR_MAX_FAILED_ATTEMPTS" ]; then
      write_cursor "$CURSOR" "$TRANSCRIPT_SIZE" "$NOW" $((EVAL_COUNT + 1)) 0
      echo "$(date -u +%FT%TZ) | FORCE-ADVANCE after $NEW_FAILS failed attempts" >> "$METRICS_LOG"
    else
      write_cursor "$CURSOR" "$LAST_EVAL_OFFSET" "$LAST_EVAL_AT" "$EVAL_COUNT" "$NEW_FAILS"
      echo "$(date -u +%FT%TZ) | RETRY: malformed response (attempt $NEW_FAILS)" >> "$METRICS_LOG"
    fi
    exit 0
  fi

  # Apply decisions (capped at MAX_DECISIONS_PER_RUN).
  APPLIED=0
  SAVED_FIRST=""
  if [ -n "$ROWS" ]; then
    while IFS=$'\t' read -r action type name description content_b64; do
      [ -z "$action" ] && continue
      if [ "$APPLIED" -ge "$CONSOLIDATOR_MAX_DECISIONS_PER_RUN" ]; then
        echo "consolidator: dropped decision $name (cap reached)" >> "$DEBUG_LOG"
        continue
      fi
      content=$(printf '%s' "$content_b64" | base64 -D 2>/dev/null)
      CONSOLIDATOR_SESSION_ID="$SESSION_ID" apply_decision "$MEM_DIR" "$action" "$type" "$name" "$description" "$content"
      [ -z "$SAVED_FIRST" ] && SAVED_FIRST="$name"
      APPLIED=$((APPLIED + 1))
    done <<< "$ROWS"
  fi

  # Advance cursor (success path — even decisions==[] counts as success).
  write_cursor "$CURSOR" "$TRANSCRIPT_SIZE" "$NOW" $((EVAL_COUNT + 1)) 0

  # Append a metrics line.
  TOTAL=$(($(date +%s) - T_START))
  LLM_TIME=$((T_LLM_END - T_LLM_START))
  echo "$(date -u +%FT%TZ) | applied=$APPLIED | llm=${LLM_TIME}s | total=${TOTAL}s | slice=${NEW_BYTES}B" >> "$METRICS_LOG"

  # Debug log: full RAW + parsed rows + clausona-profile diagnostics.
  {
    echo ""
    echo "========== $(date -u +%FT%TZ) =========="
    echo "--- ENV ---"
    echo "CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-(unset → primary/personal)}"
    echo "MEM_DIR=$MEM_DIR"
    echo "CWD=$CWD"
    echo "SESSION_ID=$SESSION_ID"
    echo "PPID=$PPID"
    echo "--- SLICE ---"
    echo "$SLICE"
    echo "--- RESPONSE ---"
    echo "$RESPONSE"
    echo "--- APPLIED ($APPLIED) ---"
    echo "$ROWS"
  } >> "$DEBUG_LOG"

  # Saved chip flash.
  if [ -n "$SAVED_FIRST" ]; then
    echo "saved:$SAVED_FIRST" > "$STATEFILE"
    trap 'if [ -n "$MEM_DIR" ]; then release_lock "$MEM_DIR/.lock" 2>/dev/null; fi' EXIT
  fi
) </dev/null >/dev/null 2>&1 &
disown

exit 0
