#!/bin/bash
# Validate that a given session id exists in ~/.claude/sessions/*.json.
#
# Usage:   _validate-session-id.sh <session-id>
# Output:  cwd of the matching session on stdout (may be empty).
# Exit:    0 if found, 1 if not found or arg missing.

SID="${1:-}"
if [ -z "$SID" ]; then
  echo "ERROR: session id required." >&2
  exit 1
fi

for f in "$HOME/.claude/sessions/"*.json; do
  [ -f "$f" ] || continue
  if jq -e --arg sid "$SID" '.sessionId == $sid' "$f" >/dev/null 2>&1; then
    jq -r '.cwd // ""' "$f" 2>/dev/null
    exit 0
  fi
done

echo "ERROR: session not found: $SID" >&2
echo "       (no entry matching this id under ~/.claude/sessions/)" >&2
exit 1
