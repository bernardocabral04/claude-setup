#!/usr/bin/env bash
# /consolidator-config — show or set keys, layered scope (session > global).
set -u

GLOBAL_CONF="$HOME/.claude/consolidator.conf"

VALID_KEYS="engine cooldown_sec min_new_bytes openrouter-model claude-model max_decisions_per_run enabled_types max_failed_attempts"

key_to_conf() {
  case "$1" in
    engine)                 printf 'CONSOLIDATOR_ENGINE' ;;
    cooldown_sec)           printf 'CONSOLIDATOR_COOLDOWN_SEC' ;;
    min_new_bytes)          printf 'CONSOLIDATOR_MIN_NEW_BYTES' ;;
    openrouter-model)       printf 'CONSOLIDATOR_OPENROUTER_MODEL' ;;
    claude-model)           printf 'CONSOLIDATOR_CLAUDE_MODEL' ;;
    max_decisions_per_run)  printf 'CONSOLIDATOR_MAX_DECISIONS_PER_RUN' ;;
    enabled_types)          printf 'CONSOLIDATOR_ENABLED_TYPES' ;;
    max_failed_attempts)    printf 'CONSOLIDATOR_MAX_FAILED_ATTEMPTS' ;;
  esac
}

# Helpful error for callers using the old key names.
suggest_for_legacy() {
  case "$1" in
    model)       printf 'openrouter-model' ;;
    clean_model) printf 'claude-model' ;;
    *)           printf '' ;;
  esac
}

read_key() {
  local key="$1" file="$2"
  [ -f "$file" ] || return 0
  grep -E "^$key=" "$file" 2>/dev/null | tail -1 | cut -d= -f2-
}

write_key() {
  local key="$1" val="$2" file="$3"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  local tmp="$file.tmp.$$"
  awk -v k="$key" -v v="$val" '
    $0 ~ "^"k"=" { print k"="v; found=1; next }
    { print }
    END { if (!found) print k"="v }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

del_key() {
  local key="$1" file="$2"
  [ -f "$file" ] || return 0
  local tmp="$file.tmp.$$"
  grep -v -E "^$key=" "$file" > "$tmp" || true
  mv "$tmp" "$file"
}

# Arg parsing.
SCOPE=session
ACTION=show
KEY=
NEW_VALUE=
CLEAR_KEY=
TARGET_SESSION_ID=
NAMED_FLAG_USED=0
declare -a NAMED_PAIRS=()  # parallel arrays via positional: key1 val1 key2 val2

while [ $# -gt 0 ]; do
  case "$1" in
    --global)
      SCOPE=global; shift ;;
    --session)
      shift
      [ $# -eq 0 ] && { echo "ERROR: --session needs an id." >&2; exit 1; }
      TARGET_SESSION_ID=$1; shift ;;
    --session-clear)
      shift
      CLEAR_KEY=$1; ACTION=clear; shift ;;
    --engine)
      shift
      [ $# -eq 0 ] && { echo "ERROR: --engine needs a value." >&2; exit 1; }
      NAMED_PAIRS+=("engine" "$1"); NAMED_FLAG_USED=1; ACTION=set; shift ;;
    --openrouter-model)
      shift
      [ $# -eq 0 ] && { echo "ERROR: --openrouter-model needs a value." >&2; exit 1; }
      NAMED_PAIRS+=("openrouter-model" "$1"); NAMED_FLAG_USED=1; ACTION=set; shift ;;
    --claude-model)
      shift
      [ $# -eq 0 ] && { echo "ERROR: --claude-model needs a value." >&2; exit 1; }
      NAMED_PAIRS+=("claude-model" "$1"); NAMED_FLAG_USED=1; ACTION=set; shift ;;
    -h|--help)
      echo "Usage:"
      echo "  /consolidator-config                                show all resolved values"
      echo "  /consolidator-config <key> <value>                  set per-session (positional)"
      echo "  /consolidator-config --global <key> <value>         set globally (positional)"
      echo "  /consolidator-config --engine <v> [--openrouter-model <v>] [--claude-model <v>]"
      echo "                                                      set one or more via named flags"
      echo "  /consolidator-config --session-clear <key>          clear a session override"
      echo ""
      echo "Keys: $VALID_KEYS"
      echo "engine values: auto | openrouter | claude"
      exit 0
      ;;
    --*)
      echo "ERROR: unknown flag '$1'. Valid flags: --global --session <id> --session-clear <key> --engine --openrouter-model --claude-model" >&2
      exit 1 ;;
    *)
      if [ -z "$KEY" ]; then
        KEY=$1
      else
        NEW_VALUE=$1
        ACTION=set
      fi
      shift
      ;;
  esac
done

# Mixed-mode rejection: named flags AND positional both set.
if [ "$NAMED_FLAG_USED" -eq 1 ] && [ -n "$KEY" ]; then
  echo "ERROR: named flags and positional key cannot be combined in one invocation." >&2
  exit 1
fi

# Clear action cannot combine with anything else either.
if [ -n "$CLEAR_KEY" ] && { [ "$NAMED_FLAG_USED" -eq 1 ] || [ -n "$KEY" ]; }; then
  echo "ERROR: --session-clear cannot be combined with key-setting flags." >&2
  exit 1
fi

# Resolve session id.
# Skip session resolution when writing to global scope only (no SESS_CONF needed).
_need_session=1
if [ "$SCOPE" = "global" ] && [ "$ACTION" = "set" ]; then
  _need_session=0
fi

SID=
if [ "$_need_session" -eq 1 ]; then
  if [ -n "$TARGET_SESSION_ID" ]; then
    SID="$TARGET_SESSION_ID"
  elif [ -z "${CLAUDE_SESSION_ID:-}" ]; then
    RES=$(bash "$HOME/.claude/scripts/_resolve-session-id.sh") || {
      echo "ERROR: could not determine current session id." >&2
      exit 1
    }
    SID=$(printf '%s' "$RES" | sed -n '1p')
  else
    SID="$CLAUDE_SESSION_ID"
  fi
fi
SESS_CONF="$HOME/.claude/consolidator-sessions/$SID"

valid_key() {
  case " $VALID_KEYS " in
    *" $1 "*) return 0 ;;
    *)
      local hint
      hint=$(suggest_for_legacy "$1")
      if [ -n "$hint" ]; then
        echo "ERROR: unknown key '$1' (did you mean '$hint'? The schema was renamed.)" >&2
      else
        echo "ERROR: unknown key '$1'. Valid keys: $VALID_KEYS" >&2
      fi
      return 1
      ;;
  esac
}

resolve() {
  local key="$1" conf
  conf=$(key_to_conf "$key")
  local v
  v=$(read_key "$conf" "$SESS_CONF")
  if [ -n "$v" ]; then printf '%s\tsession\n' "$v"; return; fi
  v=$(read_key "$conf" "$GLOBAL_CONF")
  if [ -n "$v" ]; then printf '%s\tglobal\n' "$v"; return; fi
  printf '%s\tdefault\n' '(unset)'
}

show_all() {
  if [ -f "$SESS_CONF" ]; then
    echo "Session: $SID (enabled)"
  else
    echo "Session: $SID (NOT enabled — run /consolidator-enable)"
  fi
  echo "Global:  $GLOBAL_CONF"
  echo ""
  echo "Resolved values:"
  for k in $VALID_KEYS; do
    IFS=$'\t' read -r v s <<< "$(resolve "$k")"
    printf "  %-25s = %-20s [%s]\n" "$k" "$v" "$s"
  done
}

# Validate a key=value pair. Returns 0 on success, 1 on validation error (with
# message printed to stderr). Defines the rules per spec §"Validation".
validate_value() {
  local key="$1" val="$2"
  case "$key" in
    engine)
      case "$val" in
        auto|openrouter|claude) return 0 ;;
        *) echo "ERROR: invalid engine '$val'. Allowed values: auto | openrouter | claude" >&2; return 1 ;;
      esac
      ;;
    cooldown_sec|min_new_bytes|max_decisions_per_run|max_failed_attempts)
      if ! printf '%s' "$val" | grep -qE '^[0-9]+$'; then
        echo "ERROR: '$key' must be a non-negative integer (got: '$val')" >&2
        return 1
      fi
      return 0
      ;;
    openrouter-model|claude-model|enabled_types)
      [ -n "$val" ] && return 0
      echo "ERROR: '$key' must be non-empty" >&2
      return 1
      ;;
  esac
}

case "$ACTION" in
  show)
    if [ -n "$KEY" ]; then
      valid_key "$KEY" || { echo "ERROR: unknown key '$KEY'."; exit 1; }
      IFS=$'\t' read -r v s <<< "$(resolve "$KEY")"
      echo "$KEY = $v [$s]"
    else
      show_all
    fi
    ;;
  set)
    if [ "$NAMED_FLAG_USED" -eq 1 ]; then
      # Iterate over NAMED_PAIRS in pairs. NOTE: this case block runs at
      # script scope (not inside a function), so `local` is not used.
      i=0
      while [ $i -lt ${#NAMED_PAIRS[@]} ]; do
        k="${NAMED_PAIRS[$i]}"
        v="${NAMED_PAIRS[$((i+1))]}"
        valid_key "$k" || exit 1
        validate_value "$k" "$v" || exit 1
        CONF_VAR=$(key_to_conf "$k")
        if [ "$SCOPE" = "global" ]; then
          write_key "$CONF_VAR" "$v" "$GLOBAL_CONF"
          echo "$k [global] set to: $v"
        else
          [ -f "$SESS_CONF" ] || { echo "ERROR: session not enabled."; exit 1; }
          write_key "$CONF_VAR" "$v" "$SESS_CONF"
          echo "$k [session] set to: $v"
        fi
        i=$((i + 2))
      done
    else
      valid_key "$KEY" || exit 1
      validate_value "$KEY" "$NEW_VALUE" || exit 1
      CONF=$(key_to_conf "$KEY")
      if [ "$SCOPE" = "global" ]; then
        write_key "$CONF" "$NEW_VALUE" "$GLOBAL_CONF"
        echo "$KEY [global] set to: $NEW_VALUE"
      else
        [ -f "$SESS_CONF" ] || { echo "ERROR: session not enabled."; exit 1; }
        write_key "$CONF" "$NEW_VALUE" "$SESS_CONF"
        echo "$KEY [session] set to: $NEW_VALUE"
      fi
    fi
    ;;
  clear)
    valid_key "$CLEAR_KEY" || { echo "ERROR: unknown key '$CLEAR_KEY'."; exit 1; }
    CONF=$(key_to_conf "$CLEAR_KEY")
    [ -f "$SESS_CONF" ] && del_key "$CONF" "$SESS_CONF"
    IFS=$'\t' read -r v s <<< "$(resolve "$CLEAR_KEY")"
    echo "$CLEAR_KEY: session override cleared. Now resolves to $v [$s]."
    ;;
esac
