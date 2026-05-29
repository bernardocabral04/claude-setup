#!/bin/bash
# Show or flip per-event ntfy push toggles.
#
# Scope:
#   default: current SESSION (writes ~/.claude/ntfy-sessions/<session_id>)
#   --global: global defaults     (writes ~/.claude/ntfy.conf)
#
# Resolution at runtime: notify.sh sources global first, then per-session,
# so per-session overrides win.
#
# Usage:
#   ntfy-config-impl.sh                          # list resolved state per event
#   ntfy-config-impl.sh <event>                  # show resolved value + scope
#   ntfy-config-impl.sh <event> <on|off|toggle>  # flip in SESSION scope
#   ntfy-config-impl.sh --global <event> <on|off|toggle>
#   ntfy-config-impl.sh --session-clear <event>  # remove session override; fall back to global
#
# Events: permission stop notify toggle session_start session_end subagent_stop precompact

set -u

GLOBAL_CONF="$HOME/.claude/ntfy.conf"

EVENTS="permission stop notify toggle session_start session_end subagent_stop precompact"
DEFAULTS_permission=1
DEFAULTS_stop=1
DEFAULTS_notify=1
DEFAULTS_toggle=1
DEFAULTS_session_start=0
DEFAULTS_session_end=0
DEFAULTS_subagent_stop=0
DEFAULTS_precompact=0

resolve_session_id() {
  if [ -n "${CLAUDE_SESSION_ID:-}" ]; then
    printf '%s\n' "$CLAUDE_SESSION_ID"
    return 0
  fi
  bash "$HOME/.claude/scripts/_resolve-session-id.sh" 2>/dev/null | sed -n '1p'
}

# Pre-parse --session <id> override; strip from arg list. Position-flexible.
TARGET_SESSION_ID=""
PARSED_ARGS=()
i=1
while [ $i -le $# ]; do
  arg="${!i}"
  if [ "$arg" = "--session" ]; then
    next=$((i+1))
    if [ $next -gt $# ] || [ -z "${!next:-}" ]; then
      echo "ERROR: --session needs a session id argument." >&2
      exit 2
    fi
    TARGET_SESSION_ID="${!next}"
    i=$((i+2))
    continue
  fi
  PARSED_ARGS+=("$arg")
  i=$((i+1))
done
set -- ${PARSED_ARGS[@]+"${PARSED_ARGS[@]}"}

if [ -n "$TARGET_SESSION_ID" ]; then
  bash "$HOME/.claude/scripts/_validate-session-id.sh" "$TARGET_SESSION_ID" >/dev/null || exit 1
  SESSION_ID="$TARGET_SESSION_ID"
else
  SESSION_ID=$(resolve_session_id)
fi
SESS_CONF=""
[ -n "$SESSION_ID" ] && SESS_CONF="$HOME/.claude/ntfy-sessions/$SESSION_ID"

# Read raw value from a specific file. Empty stdout if not present.
read_raw() {
  local file="$1" key="$2"
  [ -f "$file" ] || return
  grep -E "^$key=" "$file" | tail -1 | sed -E "s/^$key=//"
}

# Resolved state: session > global > built-in default. Outputs: "<val>\t<scope>".
resolve() {
  local event="$1" key val
  key="NTFY_PUSH_$(printf '%s' "$event" | tr a-z A-Z)"
  val=$(read_raw "$SESS_CONF" "$key" 2>/dev/null)
  if [ -n "$val" ]; then
    printf '%s\tsession\n' "$val"; return
  fi
  val=$(read_raw "$GLOBAL_CONF" "$key" 2>/dev/null)
  if [ -n "$val" ]; then
    printf '%s\tglobal\n' "$val"; return
  fi
  local def_var="DEFAULTS_$event"
  printf '%s\tdefault\n' "${!def_var-0}"
}

list_all() {
  if [ -n "$SESS_CONF" ] && [ -f "$SESS_CONF" ]; then
    echo "Session: $SESSION_ID (enabled)"
  elif [ -n "$SESSION_ID" ]; then
    echo "Session: $SESSION_ID (NOT enabled — run /ntfy-enable)"
  else
    echo "Session: (could not resolve)"
  fi
  echo "Global:  $GLOBAL_CONF"
  echo
  echo "Effective toggles (event = value [scope]):"
  for e in $EVENTS; do
    IFS=$'\t' read -r v s <<< "$(resolve "$e")"
    if [ "$v" = "1" ]; then sym="on "; else sym="off"; fi
    printf "  [%s] %-15s [%s]\n" "$sym" "$e" "$s"
  done
}

# Atomic update: rewrite file, replacing the matching line if present, otherwise appending.
write_kv() {
  local file="$1" key="$2" val="$3" tmp
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$file.tmp.$$"
  awk -v k="$key" -v v="$val" '
    $0 ~ "^"k"=" { print k"="v; found=1; next }
    { print }
    END { if (!found) print k"="v }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# Atomic remove: delete the matching line if present.
del_kv() {
  local file="$1" key="$2" tmp
  [ -f "$file" ] || return 0
  tmp="$file.tmp.$$"
  grep -v -E "^$key=" "$file" > "$tmp" || true
  mv "$tmp" "$file"
}

valid_event() {
  case " $EVENTS " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- arg parsing ---
SCOPE="session"
if [ "${1:-}" = "--global" ]; then
  SCOPE="global"
  shift
fi

if [ "${1:-}" = "--session-clear" ]; then
  shift
  EVENT="${1:-}"
  if ! valid_event "$EVENT"; then
    echo "ERROR: --session-clear needs a valid event. Got '$EVENT'." >&2
    echo "Valid events: $EVENTS" >&2
    exit 2
  fi
  if [ -z "$SESS_CONF" ] || [ ! -f "$SESS_CONF" ]; then
    echo "Session is not enabled — nothing to clear."
    exit 0
  fi
  KEY="NTFY_PUSH_$(printf '%s' "$EVENT" | tr a-z A-Z)"
  del_kv "$SESS_CONF" "$KEY"
  IFS=$'\t' read -r v s <<< "$(resolve "$EVENT")"
  echo "$EVENT: session override cleared. Now resolves to $v [$s]."
  exit 0
fi

if [ $# -eq 0 ] || [ "${1:-}" = "list" ]; then
  list_all
  exit 0
fi

EVENT="$1"
ACTION="${2:-}"

if ! valid_event "$EVENT"; then
  echo "ERROR: unknown event '$EVENT'." >&2
  echo "Valid events: $EVENTS" >&2
  exit 2
fi

if [ -z "$ACTION" ]; then
  IFS=$'\t' read -r v s <<< "$(resolve "$EVENT")"
  echo "$EVENT = $v [$s]"
  echo "Usage: /ntfy-config [--global] $EVENT <on|off|toggle>"
  echo "       /ntfy-config --session-clear $EVENT   # remove session override"
  exit 0
fi

# Resolve current value for "toggle".
IFS=$'\t' read -r CUR _ <<< "$(resolve "$EVENT")"

case "$ACTION" in
  on|true|1)   NEW=1 ;;
  off|false|0) NEW=0 ;;
  toggle)      [ "$CUR" = "1" ] && NEW=0 || NEW=1 ;;
  *)
    echo "ERROR: action must be on|off|toggle (got '$ACTION')." >&2
    exit 2
    ;;
esac

KEY="NTFY_PUSH_$(printf '%s' "$EVENT" | tr a-z A-Z)"

if [ "$SCOPE" = "session" ]; then
  if [ -z "$SESS_CONF" ]; then
    echo "ERROR: could not resolve current session id." >&2
    exit 1
  fi
  if [ ! -f "$SESS_CONF" ]; then
    echo "ERROR: ntfy is not enabled for this session. Run /ntfy-enable first." >&2
    exit 1
  fi
  write_kv "$SESS_CONF" "$KEY" "$NEW"
  echo "$EVENT [session]: $CUR -> $NEW"
else
  write_kv "$GLOBAL_CONF" "$KEY" "$NEW"
  echo "$EVENT [global]: $CUR -> $NEW"
fi
