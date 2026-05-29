#!/bin/bash
# Idempotently add or remove a Claude Code hook command in settings.json.
#
# Usage:
#   _merge-hook.sh add    <Event> <command-string> [settings-path]
#   _merge-hook.sh remove <Event> <command-string> [settings-path]
#
# <Event> is a Claude Code hook event: Stop, Notification, PermissionRequest,
# SessionStart, SessionEnd, SubagentStop, PreCompact, etc.
# Idempotent: adding a command that already exists is a no-op; removing one that
# is absent is a no-op. Other hooks are never touched. A backup of settings.json
# is written before any change.
set -e

ACTION="${1:?usage: _merge-hook.sh add|remove <Event> <command> [settings-path]}"
EVENT="${2:?event required (e.g. Stop)}"
CMD="${3:?command string required}"
SETTINGS="${4:-$HOME/.claude/settings.json}"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 1; }

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)-$RANDOM"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
case "$ACTION" in
  add)
    jq --arg e "$EVENT" --arg c "$CMD" '
      .hooks //= {} | .hooks[$e] //= []
      | (.hooks[$e] | map(.matcher == "*") | index(true)) as $i
      | if $i != null
        then .hooks[$e][$i].hooks = ((.hooks[$e][$i].hooks // [])
               + (if ((.hooks[$e][$i].hooks // []) | map(.command) | index($c))
                  then [] else [{type:"command", command:$c}] end))
        else .hooks[$e] += [{matcher:"*", hooks:[{type:"command", command:$c}]}]
        end
    ' "$SETTINGS" > "$tmp"
    ;;
  remove)
    jq --arg e "$EVENT" --arg c "$CMD" '
      if (.hooks[$e]?)
      then .hooks[$e] |= ( map(.hooks = ((.hooks // []) | map(select(.command != $c))))
                           | map(select((.hooks | length) > 0)) )
           | (if (.hooks[$e] | length) == 0 then del(.hooks[$e]) else . end)
           | (if (.hooks | length) == 0 then del(.hooks) else . end)
      else . end
    ' "$SETTINGS" > "$tmp"
    ;;
  *) echo "ERROR: unknown action '$ACTION' (use add|remove)." >&2; exit 1 ;;
esac
mv "$tmp" "$SETTINGS"
echo "$ACTION  $EVENT  ->  $CMD"
