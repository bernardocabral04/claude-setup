#!/bin/bash
# Resolve the CURRENT Claude Code session id from a child shell.
# Outputs:
#   - line 1: session_id
#   - line 2: cwd (may be empty)
#   - line 3: transcript_path (may be empty)
# Exit 0 on success, 1 on failure.
#
# Resolution order:
#   1. $CLAUDE_SESSION_ID env (set by SessionStart hook).
#   2. Walk up the process tree until a PID matches ~/.claude/sessions/<pid>.json.

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

if [ -n "${CLAUDE_SESSION_ID:-}" ]; then
  printf '%s\n%s\n%s\n' "$CLAUDE_SESSION_ID" "${CLAUDE_SESSION_CWD:-}" "${CLAUDE_TRANSCRIPT_PATH:-}"
  exit 0
fi

pid=$$
for _ in $(seq 1 20); do
  f="$CONFIG_DIR/sessions/$pid.json"
  [ ! -f "$f" ] && [ "$CONFIG_DIR" != "$HOME/.claude" ] && f="$HOME/.claude/sessions/$pid.json"
  if [ -f "$f" ]; then
    jq -r '"\(.sessionId)\n\(.cwd // "")\n"' "$f" 2>/dev/null
    exit 0
  fi
  ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  if [ -z "$ppid" ] || [ "$ppid" = "0" ] || [ "$ppid" = "$pid" ]; then
    break
  fi
  pid="$ppid"
done

echo "ERROR: could not determine the current session id." >&2
exit 1
