#!/bin/bash
# Persist a generated session name by directly editing the session metadata file.
# Usage: ai-rename-persist.sh <name>

set -u

NAME="${1:-}"
if [ -z "$NAME" ]; then
  echo "ERROR: missing name argument." >&2
  exit 2
fi

# Namespace every session under an operator prefix so sessions are attributable.
# Source: $AI_RENAME_PREFIX if set (empty = no prefix), else the OS username.
# Sanitize to the allowed charset so the final name always validates.
RAW_PREFIX="${AI_RENAME_PREFIX-$(whoami)}"
SAFE_PREFIX=$(printf '%s' "$RAW_PREFIX" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -c 'a-z0-9-' '-' \
  | sed -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//')
if [ -n "$SAFE_PREFIX" ]; then
  case "$NAME" in
    "$SAFE_PREFIX/"*) : ;;
    *) NAME="$SAFE_PREFIX/$NAME" ;;
  esac
fi

if ! printf '%s' "$NAME" | grep -Eq '^[a-z0-9/-]{1,50}$'; then
  echo "ERROR: invalid name '$NAME'. Must match ^[a-z0-9/-]{1,50}\$." >&2
  exit 2
fi

RES=$(bash "$HOME/.claude/scripts/_resolve-session-id.sh") || exit 1
SESSION_ID=$(printf '%s' "$RES" | sed -n '1p')
if [ -z "$SESSION_ID" ]; then
  echo "ERROR: could not determine the current session id." >&2
  exit 1
fi

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

TARGET=""
for ROOT in "$CONFIG_DIR/sessions" "$HOME/.claude/sessions"; do
  [ -d "$ROOT" ] || continue
  for f in "$ROOT"/*.json; do
    [ -f "$f" ] || continue
    if [ "$(jq -r '.sessionId // empty' "$f" 2>/dev/null)" = "$SESSION_ID" ]; then
      TARGET="$f"
      break 2
    fi
  done
done

if [ -z "$TARGET" ]; then
  echo "ERROR: could not find session metadata file for $SESSION_ID under ~/.claude/sessions/." >&2
  exit 1
fi

TMP="$TARGET.tmp.$$"
if ! jq --arg n "$NAME" '.name = $n' "$TARGET" > "$TMP"; then
  rm -f "$TMP"
  echo "ERROR: jq failed to update $TARGET." >&2
  exit 1
fi
mv "$TMP" "$TARGET"

# Also append a `custom-title` entry to the transcript JSONL — same format
# /rename writes. Restored sessions and /resume picker scan this on startup.
TRANSCRIPT=""
for ROOT in "$CONFIG_DIR/projects" "$HOME/.claude/projects"; do
  [ -d "$ROOT" ] || continue
  for cand in "$ROOT"/*/"$SESSION_ID.jsonl"; do
    [ -f "$cand" ] || continue
    TRANSCRIPT="$cand"
    break 2
  done
done

TRANSCRIPT_NOTE=""
if [ -n "$TRANSCRIPT" ]; then
  # custom-title is read by the /resume picker. (agent-name was tried too but
  # the live process overwrites it on every turn, so it's not useful.)
  jq -n -c --arg n "$NAME" --arg sid "$SESSION_ID" \
    '{type:"custom-title", customTitle:$n, sessionId:$sid}' >> "$TRANSCRIPT"
  TRANSCRIPT_NOTE=" + appended custom-title to $TRANSCRIPT"
fi

echo "Renamed session $SESSION_ID -> $NAME (via $TARGET$TRANSCRIPT_NOTE)"
echo "Notifications will pick this up immediately."

# Inject `/rename <name><Enter>` into the host terminal via AppleScript so
# Claude Code's in-memory state (TUI title, /resume picker, agent-name stream)
# is mutated by the real /rename slash command — the only path that wins
# against Claude's continuous transcript overwrites.
INJECT_NOTE=""
if [ -z "${AI_RENAME_NO_KEYSTROKE:-}" ] && [ "$(uname)" = "Darwin" ]; then
  case "${TERM_PROGRAM:-}" in
    Apple_Terminal) APP="Terminal" ;;
    iTerm.app)      APP="iTerm" ;;
    WarpTerminal)   APP="Warp" ;;
    vscode)         APP="Cursor" ;;
    *)              APP="" ;;
  esac
  if [ -n "$APP" ] && command -v osascript >/dev/null 2>&1; then
    (
      sleep 1
      osascript <<EOF >/dev/null 2>&1
tell application "$APP" to activate
delay 0.2
tell application "System Events" to keystroke "/rename $NAME"
delay 0.1
tell application "System Events" to key code 36
EOF
    ) &
    INJECT_NOTE=" (also queued '/rename $NAME' keystrokes into $APP — fires in ~1s)"
  fi
fi

if [ -n "$INJECT_NOTE" ]; then
  echo "Live TUI sync$INJECT_NOTE."
  echo "If keystrokes did not appear, focus the Claude Code window and run:"
  echo "  /rename $NAME"
else
  echo "On-disk state matches /rename, but the live TUI title and /resume picker"
  echo "in this still-running session won't refresh until next process start;"
  echo "to apply now, run:"
  echo "  /rename $NAME"
fi
exit 0
