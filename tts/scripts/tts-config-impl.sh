#!/bin/bash
# /tts-config — show or set the cleanup mode (normal | summary | auto).
# Mirrors the layered scope of /ntfy-config: session overrides global default.
set -e

GLOBAL_CONF="$HOME/.claude/tts.conf"

resolve_session_id() {
  if [ -z "$CLAUDE_SESSION_ID" ]; then
    local res
    res=$(bash "$HOME/.claude/scripts/_resolve-session-id.sh") || {
      echo "ERROR: could not determine the current session id." >&2
      exit 1
    }
    CLAUDE_SESSION_ID=$(printf '%s' "$res" | sed -n '1p')
  fi
  printf '%s' "$CLAUDE_SESSION_ID"
}

valid_mode() {
  case "$1" in
    normal|summary|auto) return 0 ;;
    *) return 1 ;;
  esac
}

# Kokoro voice catalog. Mirrors VOICES in
# ~/Projects/personal/speed-reader/speeder/kokoro-server/server.py.
KOKORO_VOICES="af_heart af_bella af_nicole af_sarah af_sky am_adam am_michael bf_emma bf_isabella bm_george bm_lewis pf_dora pm_alex pm_santa"

valid_voice() {
  local id=$1 v
  for v in $KOKORO_VOICES; do
    [ "$v" = "$id" ] && return 0
  done
  return 1
}

# Speed must be a positive float in [0.5, 2.0] (Kokoro's accepted range).
valid_speed() {
  local s=$1
  # Reject empty or non-numeric.
  case "$s" in
    ''|*[!0-9.]*) return 1 ;;
  esac
  # Use awk for the float range check — bash arithmetic is integer-only.
  awk -v s="$s" 'BEGIN { exit !(s+0 >= 0.5 && s+0 <= 2.0) }'
}

# Read a value for key $1 from file $2. Returns empty string if missing.
read_key() {
  local key=$1 file=$2
  [ -f "$file" ] || return 0
  grep -E "^$key=" "$file" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"'
}

# Set key=value in $file, replacing any prior line for that key.
set_key() {
  local key=$1 value=$2 file=$3
  mkdir -p "$(dirname "$file")"
  touch "$file"
  local tmp
  tmp=$(mktemp)
  grep -vE "^$key=" "$file" > "$tmp" || true
  echo "$key=$value" >> "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

unset_key() {
  local key=$1 file=$2
  [ -f "$file" ] || return 0
  local tmp
  tmp=$(mktemp)
  grep -vE "^$key=" "$file" > "$tmp" || true
  mv "$tmp" "$file"
}

# resolved_value_and_scope <conf-key> <default> <session-id>
# Returns "<value>|<scope>" where scope ∈ {session, global, default}.
resolved_value_and_scope() {
  local key=$1 default=$2 sid=$3
  local sess_conf="$HOME/.claude/tts-sessions/$sid.conf"
  local v
  v=$(read_key "$key" "$sess_conf")
  if [ -n "$v" ]; then printf '%s|session' "$v"; return; fi
  v=$(read_key "$key" "$GLOBAL_CONF")
  if [ -n "$v" ]; then printf '%s|global' "$v"; return; fi
  printf '%s|default' "$default"
}

show() {
  local sid=$1
  local pair val scope
  pair=$(resolved_value_and_scope "TTS_MODE"          "normal"     "$sid")
  val=${pair%|*}; scope=${pair##*|}
  printf 'TTS mode:  %-10s  (scope: %s)\n' "$val" "$scope"

  pair=$(resolved_value_and_scope "TTS_KOKORO_VOICE"  "am_michael" "$sid")
  val=${pair%|*}; scope=${pair##*|}
  printf 'TTS voice: %-10s  (scope: %s)\n' "$val" "$scope"

  pair=$(resolved_value_and_scope "TTS_KOKORO_SPEED"  "1.0"        "$sid")
  val=${pair%|*}; scope=${pair##*|}
  printf 'TTS speed: %-10s  (scope: %s)\n' "$val" "$scope"

  printf '\n'
  printf '  session conf: %s\n' "$HOME/.claude/tts-sessions/$sid.conf"
  printf '  global conf:  %s\n' "$GLOBAL_CONF"
}

# ---- argument parsing ----
SCOPE=session
ACTION=show
KEY=
NEW_VALUE=
CLEAR_KEY=
TARGET_SESSION_ID=

while [ $# -gt 0 ]; do
  case "$1" in
    --global)
      SCOPE=global; shift ;;
    --session-clear)
      ACTION=clear
      shift
      # Optional next arg picks the key to clear (mode|voice|speed). If absent,
      # default to "mode" for backward compatibility with the original command.
      case "${1:-}" in
        mode|voice|speed) CLEAR_KEY=$1; shift ;;
        *)                CLEAR_KEY=mode ;;
      esac
      ;;
    --session)
      shift
      [ $# -eq 0 ] && { echo "ERROR: --session needs a session id argument." >&2; exit 1; }
      TARGET_SESSION_ID=$1
      shift
      ;;
    mode|voice|speed)
      KEY=$1
      shift
      [ $# -eq 0 ] && { echo "ERROR: missing value for '$KEY'." >&2; exit 1; }
      NEW_VALUE=$1
      ACTION=set
      shift
      ;;
    -h|--help)
      echo "Usage:"
      echo "  /tts-config                              show resolved mode/voice/speed"
      echo "  /tts-config mode <normal|summary|auto>   set mode per-session"
      echo "  /tts-config voice <kokoro-voice-id>      set Kokoro voice per-session"
      echo "  /tts-config speed <0.5-2.0>              set Kokoro speed per-session"
      echo "  /tts-config --global <key> <value>       set the global default"
      echo "  /tts-config --session-clear [key]        drop session override (default: mode)"
      echo "  /tts-config --session <id> ...           apply to that session id instead of current"
      echo ""
      echo "Kokoro voice ids:"
      printf '%s\n' $KOKORO_VOICES | sed 's/^/    /'
      exit 0
      ;;
    *) echo "ERROR: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

if [ -n "$TARGET_SESSION_ID" ]; then
  bash "$HOME/.claude/scripts/_validate-session-id.sh" "$TARGET_SESSION_ID" >/dev/null || exit 1
  SID="$TARGET_SESSION_ID"
else
  SID=$(resolve_session_id)
fi

# Map the parser's KEY to the conf-field name + validator + human label.
key_to_field() {
  case "$1" in
    mode)  printf 'TTS_MODE' ;;
    voice) printf 'TTS_KOKORO_VOICE' ;;
    speed) printf 'TTS_KOKORO_SPEED' ;;
  esac
}

validate_value() {
  # $1 = key, $2 = value. Echoes nothing on success, error message on failure.
  case "$1" in
    mode)
      valid_mode "$2" || { echo "ERROR: invalid mode '$2'. Must be one of: normal, summary, auto." >&2; return 1; } ;;
    voice)
      valid_voice "$2" || {
        echo "ERROR: invalid voice '$2'. Run '/tts-config --help' for the list." >&2
        return 1
      } ;;
    speed)
      valid_speed "$2" || { echo "ERROR: invalid speed '$2'. Must be a number in [0.5, 2.0]." >&2; return 1; } ;;
    *) echo "ERROR: unknown key '$1'." >&2; return 1 ;;
  esac
}

case "$ACTION" in
  show)
    show "$SID"
    ;;
  set)
    validate_value "$KEY" "$NEW_VALUE" || exit 1
    FIELD=$(key_to_field "$KEY")
    if [ "$SCOPE" = "global" ]; then
      set_key "$FIELD" "$NEW_VALUE" "$GLOBAL_CONF"
      echo "Global $FIELD set to '$NEW_VALUE' (written to $GLOBAL_CONF)."
    else
      set_key "$FIELD" "$NEW_VALUE" "$HOME/.claude/tts-sessions/$SID.conf"
      echo "Session $FIELD set to '$NEW_VALUE' for $SID."
    fi
    echo ""
    show "$SID"
    ;;
  clear)
    FIELD=$(key_to_field "$CLEAR_KEY")
    sess_conf="$HOME/.claude/tts-sessions/$SID.conf"
    if [ ! -f "$sess_conf" ] || ! grep -qE "^$FIELD=" "$sess_conf" 2>/dev/null; then
      echo "No session $FIELD override exists for $SID — nothing to clear."
    else
      unset_key "$FIELD" "$sess_conf"
      [ -s "$sess_conf" ] || rm -f "$sess_conf"
      echo "Session $FIELD override cleared for $SID."
    fi
    echo ""
    show "$SID"
    ;;
esac
