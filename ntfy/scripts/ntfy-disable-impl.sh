#!/bin/bash
TARGET_SESSION_ID="${1:-}"
if [ -n "$TARGET_SESSION_ID" ]; then
  FOUND_CWD=$(bash "$HOME/.claude/scripts/_validate-session-id.sh" "$TARGET_SESSION_ID") || exit 1
  CLAUDE_SESSION_ID="$TARGET_SESSION_ID"
  CLAUDE_SESSION_CWD="$FOUND_CWD"
elif [ -z "$CLAUDE_SESSION_ID" ]; then
  RES=$(bash "$HOME/.claude/scripts/_resolve-session-id.sh") || {
    echo "ERROR: could not determine the current session id." >&2
    exit 1
  }
  CLAUDE_SESSION_ID=$(printf '%s' "$RES" | sed -n '1p')
  [ -z "$CLAUDE_SESSION_CWD" ] && CLAUDE_SESSION_CWD=$(printf '%s' "$RES" | sed -n '2p')
fi

FLAG="$HOME/.claude/ntfy-sessions/$CLAUDE_SESSION_ID"
if [ -f "$FLAG" ]; then
  # Fire toggle:disabled BEFORE removing the flag so the push actually goes through.
  if [ -n "$TARGET_SESSION_ID" ]; then
    PUSH_CWD="$CLAUDE_SESSION_CWD"
  else
    PUSH_CWD="${CLAUDE_SESSION_CWD:-$PWD}"
  fi
  printf '{"session_id":"%s","cwd":"%s"}' "$CLAUDE_SESSION_ID" "$PUSH_CWD" \
    | bash "$HOME/.claude/scripts/notify.sh" toggle:disabled
  rm -f "$FLAG"
  echo "ntfy disabled for session $CLAUDE_SESSION_ID."
else
  echo "ntfy was not enabled for session $CLAUDE_SESSION_ID — nothing to do."
fi
