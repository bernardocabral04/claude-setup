#!/bin/bash
set -e

CONF="$HOME/.claude/ntfy.conf"

if [ ! -f "$CONF" ]; then
  RAND=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 12)
  cat > "$CONF" <<EOF
NTFY_SERVER=https://ntfy.sh
NTFY_TOPIC=claude-$RAND
NTFY_PUSH_PERMISSION=1
NTFY_PUSH_STOP=1
NTFY_PUSH_NOTIFY=1
NTFY_PUSH_TOGGLE=1
NTFY_PUSH_SESSION_START=0
NTFY_PUSH_SESSION_END=0
NTFY_PUSH_SUBAGENT_STOP=0
NTFY_PUSH_PRECOMPACT=0
EOF
  chmod 600 "$CONF"
  echo "Created $CONF with a fresh random topic + default toggles."
else
  # Backfill any missing toggle keys without disturbing user edits.
  for kv in NTFY_PUSH_PERMISSION=1 NTFY_PUSH_STOP=1 NTFY_PUSH_NOTIFY=1 NTFY_PUSH_TOGGLE=1 \
            NTFY_PUSH_SESSION_START=0 NTFY_PUSH_SESSION_END=0 NTFY_PUSH_SUBAGENT_STOP=0 NTFY_PUSH_PRECOMPACT=0; do
    key="${kv%%=*}"
    grep -q "^$key=" "$CONF" || echo "$kv" >> "$CONF"
  done
fi

# shellcheck disable=SC1090
. "$CONF"

TARGET_SESSION_ID="${1:-}"
if [ -n "$TARGET_SESSION_ID" ]; then
  FOUND_CWD=$(bash "$HOME/.claude/scripts/_validate-session-id.sh" "$TARGET_SESSION_ID") || exit 1
  CLAUDE_SESSION_ID="$TARGET_SESSION_ID"
  CLAUDE_SESSION_CWD="$FOUND_CWD"
  SCOPE_LABEL="target session $TARGET_SESSION_ID"
elif [ -z "$CLAUDE_SESSION_ID" ]; then
  RES=$(bash "$HOME/.claude/scripts/_resolve-session-id.sh") || {
    echo "ERROR: could not determine the current session id." >&2
    exit 1
  }
  CLAUDE_SESSION_ID=$(printf '%s' "$RES" | sed -n '1p')
  [ -z "$CLAUDE_SESSION_CWD" ] && CLAUDE_SESSION_CWD=$(printf '%s' "$RES" | sed -n '2p')
  SCOPE_LABEL="this session"
else
  SCOPE_LABEL="this session"
fi

mkdir -p "$HOME/.claude/ntfy-sessions"
touch "$HOME/.claude/ntfy-sessions/$CLAUDE_SESSION_ID"

SUB_URL="$NTFY_SERVER/$NTFY_TOPIC"

# Copy topic to clipboard so the user can paste-subscribe via Universal Clipboard.
if command -v pbcopy >/dev/null 2>&1; then
  printf '%s' "$NTFY_TOPIC" | pbcopy
  COPIED=1
else
  COPIED=0
fi

echo ""
echo "ntfy enabled for $SCOPE_LABEL."
echo "  Session ID:  $CLAUDE_SESSION_ID"
echo "  Topic:       $NTFY_TOPIC"
echo "  Server:      $NTFY_SERVER"
echo "  Subscribe:   $SUB_URL"
echo ""
echo "Setup (paste path — recommended):"
echo "  1. Install the ntfy iOS app: https://apps.apple.com/app/ntfy/id1625396347"
[ "$COPIED" = "1" ] && echo "  2. Topic was copied to your Mac clipboard. With Universal Clipboard"
[ "$COPIED" = "1" ] && echo "     enabled (iCloud + Handoff), unlock your iPhone, open ntfy → '+' →"
[ "$COPIED" = "1" ] && echo "     long-press the Topic field → Paste → Subscribe."
[ "$COPIED" = "0" ] && echo "  2. Open ntfy → '+' → type the topic: $NTFY_TOPIC → Subscribe."
echo ""
echo "Alternative (QR + Safari):"
echo "  Scan the QR below with iPhone Camera → tap the banner → Safari opens"
echo "  the topic page → tap 'Subscribe'. The ntfy app does not yet have a"
echo "  built-in QR scanner."
echo ""

if command -v qrencode >/dev/null 2>&1; then
  qrencode -t UTF8 -m 1 "$SUB_URL"
else
  echo "  (Install qrencode for an inline QR: brew install qrencode)"
fi

echo ""
# Fire structured toggle:enabled event via notify.sh so it follows the same
# routing rules as every other event (mac notif + ntfy push if NTFY_PUSH_TOGGLE=1).
if [ -n "$TARGET_SESSION_ID" ]; then
  PUSH_CWD="$CLAUDE_SESSION_CWD"
else
  PUSH_CWD="${CLAUDE_SESSION_CWD:-$PWD}"
fi
printf '{"session_id":"%s","cwd":"%s"}' "$CLAUDE_SESSION_ID" "$PUSH_CWD" \
  | bash "$HOME/.claude/scripts/notify.sh" toggle:enabled

echo "Test push sent. It should arrive after you complete the subscription."
