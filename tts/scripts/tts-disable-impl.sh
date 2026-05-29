#!/bin/bash
TARGET_SESSION_ID="${1:-}"
if [ -n "$TARGET_SESSION_ID" ]; then
  bash "$HOME/.claude/scripts/_validate-session-id.sh" "$TARGET_SESSION_ID" >/dev/null || exit 1
  CLAUDE_SESSION_ID="$TARGET_SESSION_ID"
elif [ -z "$CLAUDE_SESSION_ID" ]; then
  RES=$(bash "$HOME/.claude/scripts/_resolve-session-id.sh") || {
    echo "ERROR: could not determine the current session id." >&2
    exit 1
  }
  CLAUDE_SESSION_ID=$(printf '%s' "$RES" | sed -n '1p')
fi

FLAG="$HOME/.claude/tts-sessions/$CLAUDE_SESSION_ID"
PIDFILE="$HOME/.claude/tts-sessions/$CLAUDE_SESSION_ID.pid"

# Kill any in-flight speech for this session.
if [ -f "$PIDFILE" ]; then
  OLD_PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
  if [ -n "$OLD_PID" ]; then
    pkill -P "$OLD_PID" 2>/dev/null || true
    kill "$OLD_PID" 2>/dev/null || true
  fi
  rm -f "$PIDFILE"
fi

rm -f "$HOME/.claude/tts-sessions/$CLAUDE_SESSION_ID.last_raw.txt"
rm -f "$HOME/.claude/tts-sessions/$CLAUDE_SESSION_ID.last.txt"

if [ -f "$FLAG" ]; then
  rm -f "$FLAG"
  echo "TTS disabled for session $CLAUDE_SESSION_ID."
else
  echo "TTS was not enabled for session $CLAUDE_SESSION_ID — nothing to do."
fi
