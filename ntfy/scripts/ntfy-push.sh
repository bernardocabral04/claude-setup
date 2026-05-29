#!/bin/bash
# Send a single push to ntfy.sh using ~/.claude/ntfy.conf.
# Usage: ntfy-push.sh <title> <message> [tags]
# Env:   NTFY_SESSION_ID — if set, writes a "sending" state file that the
#        statusline chip reads. Cleared on exit (success, failure, or kill).

TITLE="$1"
MESSAGE="$2"
TAGS="${3:-}"

CONF="$HOME/.claude/ntfy.conf"
[ -f "$CONF" ] || exit 0
# shellcheck disable=SC1090
. "$CONF"

[ -z "$NTFY_SERVER" ] && NTFY_SERVER="https://ntfy.sh"
[ -z "$NTFY_TOPIC" ] && exit 0

ARGS=(-s -H "Title: $TITLE" -d "$MESSAGE")
[ -n "$TAGS" ]       && ARGS+=(-H "Tags: $TAGS")
[ -n "$NTFY_TOKEN" ] && ARGS+=(-H "Authorization: Bearer $NTFY_TOKEN")

if [ -n "$NTFY_SESSION_ID" ]; then
  STATEFILE="$HOME/.claude/ntfy-sessions/$NTFY_SESSION_ID.state"
  trap 'rm -f "$STATEFILE"' EXIT
  echo sending > "$STATEFILE"
fi

curl --max-time 30 "${ARGS[@]}" "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null 2>&1
