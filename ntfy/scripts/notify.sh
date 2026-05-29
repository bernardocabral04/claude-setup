#!/bin/bash
# Claude Code notification hook + ntfy router.
# Reads hook JSON from stdin. Fires macOS notification AND/OR ntfy push,
# gated by per-event toggle in ~/.claude/ntfy.conf.
#
# Toggle behavior (NTFY_PUSH_<EVENT>):
#   - 1: macOS notif fires; ntfy push fires if the session has opted in.
#   - 0: nothing fires for this event.
# Defaults are baked in below per event.
#
# Usage (from settings.json hook): notify.sh <event-kind>
#   event-kind: permission | stop | notify | session_start | session_end |
#               subagent_stop | precompact | toggle:enabled | toggle:disabled

EVENT="$1"

# Skip ALL notifications when the cleanup `claude -p` subprocess is running —
# its hook events are recursion noise, not user-facing.
[ -n "$CLAUDE_TTS_CLEANUP" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
HOOK_MSG=$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null)

# Per-event meta: TITLE | MESSAGE | SOUND | TOGGLE_KEY | DEFAULT_ON
case "$EVENT" in
  permission)      TITLE="Permission Required"; MESSAGE="✋ Action required";                       SOUND="Blow";  TKEY="PERMISSION";    DEFAULT_ON=1 ;;
  stop)            TITLE="Done";                MESSAGE="✅ Response complete";                     SOUND="Funk";  TKEY="STOP";          DEFAULT_ON=1 ;;
  notify)          TITLE="Attention";           MESSAGE="🔔 ${HOOK_MSG:-Claude Code needs you}";   SOUND="Glass"; TKEY="NOTIFY";        DEFAULT_ON=1 ;;
  session_start)   TITLE="Session started";     MESSAGE="🚀 Session started";                       SOUND="Tink";  TKEY="SESSION_START"; DEFAULT_ON=0 ;;
  session_end)     TITLE="Session ended";       MESSAGE="🏁 Session ended";                         SOUND="Tink";  TKEY="SESSION_END";   DEFAULT_ON=0 ;;
  subagent_stop)   TITLE="Subagent done";       MESSAGE="🤖 Subagent finished";                     SOUND="Pop";   TKEY="SUBAGENT_STOP"; DEFAULT_ON=0 ;;
  precompact)      TITLE="Compaction imminent"; MESSAGE="🗜️  Context will be compacted";            SOUND="Hero";  TKEY="PRECOMPACT";    DEFAULT_ON=0 ;;
  toggle:enabled)  TITLE="ntfy enabled";        MESSAGE="📲 Phone push enabled for this session";   SOUND="Glass"; TKEY="TOGGLE";        DEFAULT_ON=1 ;;
  toggle:disabled) TITLE="ntfy disabled";       MESSAGE="🔕 Phone push disabled for this session";  SOUND="Glass"; TKEY="TOGGLE";        DEFAULT_ON=1 ;;
  *)               TITLE="Claude Code";         MESSAGE="$EVENT";                                  SOUND="Ping";  TKEY="";              DEFAULT_ON=0 ;;
esac

# Gate the whole hook by the conf toggle (single switch for both mac + ntfy).
# Layered: global ~/.claude/ntfy.conf is sourced first, then the per-session
# override file ~/.claude/ntfy-sessions/<id> if present. Last write wins.
CONF="$HOME/.claude/ntfy.conf"
[ -f "$CONF" ] && . "$CONF"
SESS_CONF="$HOME/.claude/ntfy-sessions/$SESSION_ID"
[ -n "$SESSION_ID" ] && [ -f "$SESS_CONF" ] && . "$SESS_CONF"
if [ -n "$TKEY" ]; then
  VAR="NTFY_PUSH_$TKEY"
  VAL="${!VAR-$DEFAULT_ON}"
  [ "$VAL" != "1" ] && exit 0
fi

# Resolve a display name for the subtitle.
NAME=""
if [ -n "$SESSION_ID" ]; then
  shopt -s nullglob
  for f in "$HOME/.claude/sessions/"*.json; do
    NAME=$(jq -r --arg sid "$SESSION_ID" 'select(.sessionId == $sid) | .name // empty' "$f" 2>/dev/null)
    [ -n "$NAME" ] && break
  done
  shopt -u nullglob
fi
if [ -z "$NAME" ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  NAME=$(jq -r 'select((.type == "user") or (.operation == "enqueue")) | (.content // .message.content // empty)' "$TRANSCRIPT" 2>/dev/null \
         | grep -v '^$' | head -n 1 | tr '\n' ' ' | cut -c1-40)
fi
if [ -z "$NAME" ] && [ -n "$CWD" ]; then
  NAME=$(basename "$CWD")
fi
[ -z "$NAME" ] && NAME="session"

SUBTITLE="$NAME"

# macOS notification.
NOTIFIER="$HOME/.claude/apps/Claude Code Notifier.app/Contents/MacOS/terminal-notifier"
[ -x "$NOTIFIER" ] || NOTIFIER="terminal-notifier"

if [ "$TERM_PROGRAM" = "vscode" ]; then
  APP="Cursor"
elif [ "$TERM_PROGRAM" = "iTerm.app" ]; then
  APP="iTerm"
elif [ "$TERM_PROGRAM" = "WarpTerminal" ]; then
  APP="Warp"
else
  APP="Terminal"
fi
"$NOTIFIER" \
  -title 'Claude Code' \
  -subtitle "$SUBTITLE" \
  -message "$MESSAGE" \
  -sound "$SOUND" \
  -execute "open -a '$APP'" >/dev/null 2>&1

# Phone push: requires session to have opted in. ntfy-push.sh manages the
# statusline "sending…" chip itself when NTFY_SESSION_ID is set.
if [ -n "$SESSION_ID" ] && [ -f "$HOME/.claude/ntfy-sessions/$SESSION_ID" ]; then
  NTFY_SESSION_ID="$SESSION_ID" bash "$HOME/.claude/scripts/ntfy-push.sh" "$SUBTITLE" "$MESSAGE" &
  disown 2>/dev/null || true
fi
exit 0
