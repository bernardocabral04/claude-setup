#!/usr/bin/env bash
TARGET_SESSION_ID="${1:-}"
if [ -n "$TARGET_SESSION_ID" ]; then
  bash "$HOME/.claude/scripts/_validate-session-id.sh" "$TARGET_SESSION_ID" >/dev/null || exit 1
  CLAUDE_SESSION_ID="$TARGET_SESSION_ID"
elif [ -z "${CLAUDE_SESSION_ID:-}" ]; then
  RES=$(bash "$HOME/.claude/scripts/_resolve-session-id.sh") || {
    echo "ERROR: could not determine the current session id." >&2
    exit 1
  }
  CLAUDE_SESSION_ID=$(printf '%s' "$RES" | sed -n '1p')
fi

DIR="$HOME/.claude/consolidator-sessions"
FLAG="$DIR/$CLAUDE_SESSION_ID"
if [ -f "$FLAG" ]; then
  rm -f "$FLAG" \
        "$DIR/$CLAUDE_SESSION_ID.cursor" \
        "$DIR/$CLAUDE_SESSION_ID.state" \
        "$DIR/$CLAUDE_SESSION_ID.last.json"
  echo "Consolidator disabled for session $CLAUDE_SESSION_ID."
else
  echo "Consolidator was not enabled for session $CLAUDE_SESSION_ID — nothing to do."
fi
