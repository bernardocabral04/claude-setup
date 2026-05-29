#!/bin/bash
# Show ntfy status for the current Claude Code session.
# - OFF if ~/.claude/ntfy-sessions/<session_id> is missing.
# - ON  with topic, server, subscribe URL, and QR code if present.

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

FLAG="$HOME/.claude/ntfy-sessions/$CLAUDE_SESSION_ID"
CONF="$HOME/.claude/ntfy.conf"

echo "Session: $CLAUDE_SESSION_ID"

if [ ! -f "$FLAG" ]; then
  echo "Status:  OFF"
  echo ""
  echo "Phone notifications are not enabled for this session."
  echo "Run /ntfy-enable to turn them on."
  exit 0
fi

echo "Status:  ON"

if [ ! -f "$CONF" ]; then
  echo ""
  echo "WARNING: flag file present but $CONF is missing."
  echo "Run /ntfy-enable to bootstrap the config."
  exit 0
fi

# shellcheck disable=SC1090
. "$CONF"
[ -z "$NTFY_SERVER" ] && NTFY_SERVER="https://ntfy.sh"

SUB_URL="$NTFY_SERVER/$NTFY_TOPIC"

if command -v pbcopy >/dev/null 2>&1; then
  printf '%s' "$NTFY_TOPIC" | pbcopy
  CLIP_NOTE="(topic copied to clipboard — paste in ntfy iOS 'Add subscription')"
else
  CLIP_NOTE=""
fi

echo "Topic:     $NTFY_TOPIC"
echo "Server:    $NTFY_SERVER"
echo "Subscribe: $SUB_URL"
[ -n "$CLIP_NOTE" ] && echo "$CLIP_NOTE"
echo ""

if command -v qrencode >/dev/null 2>&1; then
  qrencode -t UTF8 -m 1 "$SUB_URL"
else
  echo "(Install qrencode for an inline QR: brew install qrencode)"
fi

echo ""
echo "Per-event push toggles (session > global > default):"
# Source layered: global first, then session override (matching notify.sh).
[ -f "$CONF" ]                                       && . "$CONF"
[ -f "$HOME/.claude/ntfy-sessions/$CLAUDE_SESSION_ID" ] && . "$HOME/.claude/ntfy-sessions/$CLAUDE_SESSION_ID"

scope_of() {
  local key="$1"
  if grep -qE "^$key=" "$HOME/.claude/ntfy-sessions/$CLAUDE_SESSION_ID" 2>/dev/null; then
    echo "session"
  elif grep -qE "^$key=" "$CONF" 2>/dev/null; then
    echo "global"
  else
    echo "default"
  fi
}

print_toggle() {
  local key="$1" def="$2" var val sym scope
  var="NTFY_PUSH_$key"
  val="${!var-$def}"
  scope=$(scope_of "$var")
  if [ "$val" = "1" ]; then sym="on "; else sym="off"; fi
  printf "  [%s] %-15s [%s]\n" "$sym" "$(printf '%s' "$key" | tr A-Z a-z)" "$scope"
}
print_toggle PERMISSION     1
print_toggle STOP           1
print_toggle NOTIFY         1
print_toggle TOGGLE         1
print_toggle SESSION_START  0
print_toggle SESSION_END    0
print_toggle SUBAGENT_STOP  0
print_toggle PRECOMPACT     0

echo ""
echo "Edit with /ntfy-config, e.g.:  /ntfy-config session_start on"
echo "  Add --global to flip the default for every session."

ACTIVE_COUNT=$(ls "$HOME/.claude/ntfy-sessions/" 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "Sessions currently pushing to phone: $ACTIVE_COUNT"
