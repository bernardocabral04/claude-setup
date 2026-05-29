#!/usr/bin/env bash
# Force one consolidator eval immediately, bypassing the cooldown and
# min-new-bytes gates. Still respects the cursor (only new slice evaluated).

LIB="$HOME/.claude/scripts/consolidator-lib.sh"
# shellcheck disable=SC1090
. "$LIB"

TARGET_SESSION_ID="${1:-}"
if [ -n "$TARGET_SESSION_ID" ]; then
  CWD=$(bash "$HOME/.claude/scripts/_validate-session-id.sh" "$TARGET_SESSION_ID") || exit 1
  CLAUDE_SESSION_ID="$TARGET_SESSION_ID"
  CLAUDE_SESSION_CWD="$CWD"
elif [ -z "${CLAUDE_SESSION_ID:-}" ]; then
  RES=$(bash "$HOME/.claude/scripts/_resolve-session-id.sh") || exit 1
  CLAUDE_SESSION_ID=$(printf '%s' "$RES" | sed -n '1p')
  [ -z "${CLAUDE_SESSION_CWD:-}" ] && CLAUDE_SESSION_CWD=$(printf '%s' "$RES" | sed -n '2p')
fi

[ -z "${CLAUDE_TRANSCRIPT_PATH:-}" ] && CLAUDE_TRANSCRIPT_PATH=$(bash "$HOME/.claude/scripts/_resolve-session-id.sh" | sed -n '3p')

if [ ! -f "$HOME/.claude/consolidator-sessions/$CLAUDE_SESSION_ID" ]; then
  echo "ERROR: consolidator not enabled for session $CLAUDE_SESSION_ID. Run /consolidator-enable first." >&2
  exit 1
fi
if [ -z "$CLAUDE_TRANSCRIPT_PATH" ] || [ ! -f "$CLAUDE_TRANSCRIPT_PATH" ]; then
  echo "ERROR: transcript path not resolvable. Re-run from inside a live session." >&2
  exit 1
fi

INPUT=$(jq -nc \
  --arg sid "$CLAUDE_SESSION_ID" \
  --arg t   "$CLAUDE_TRANSCRIPT_PATH" \
  --arg c   "${CLAUDE_SESSION_CWD:-$PWD}" \
  '{session_id:$sid, transcript_path:$t, cwd:$c}')

echo "Forcing one eval for session $CLAUDE_SESSION_ID..."
printf '%s' "$INPUT" \
  | CONSOLIDATOR_COOLDOWN_SEC=0 CONSOLIDATOR_MIN_NEW_BYTES=0 bash "$HOME/.claude/scripts/consolidator-hook.sh"

# Wait for the background pipeline (up to 30s) then show the cursor + last.json.
SESS_DIR="$HOME/.claude/consolidator-sessions"
STATE="$SESS_DIR/$CLAUDE_SESSION_ID.state"
for _ in $(seq 1 60); do
  [ -f "$STATE" ] || break
  sleep 0.5
done

echo ""
bash "$HOME/.claude/scripts/consolidator-status-impl.sh"
