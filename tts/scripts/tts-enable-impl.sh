#!/bin/bash
set -e

CONF="$HOME/.claude/tts.conf"

if [ ! -f "$CONF" ]; then
  cat > "$CONF" <<'EOF'
# TTS engine: macOS `say`. Voice list: `say -v ?`
TTS_VOICE=Samantha
# Rate in words/min. Default 175. Bump to 220 for snappier.
TTS_RATE=200

# Cleanup mode: normal | summary | auto. Change via /tts-config.
TTS_MODE=normal

# Kokoro local TTS server (primary engine).
TTS_KOKORO_URL=http://127.0.0.1:8321
TTS_KOKORO_VOICE=am_michael
TTS_KOKORO_SPEED=1.0

# Cleanup path selection:
#   - If OPENROUTER_API_KEY is set below (or already in your shell env),
#     the fast path is used: curl → OpenRouter → free model (~1-2s).
#   - Otherwise: claude -p with the alias in TTS_CLEAN_MODEL (~10s cold start).
OPENROUTER_API_KEY=
TTS_OPENROUTER_MODEL=liquid/lfm-2.5-1.2b-instruct:free

# Used only when falling back to the local `claude -p` path.
TTS_CLEAN_MODEL=haiku

# Max chars sent to `say` after cleanup. Long responses get truncated.
TTS_MAX_CHARS=1200
# When non-empty, also play this short cue before speech (path to .aiff/.wav).
# Leave empty to skip.
TTS_CUE_SOUND=
EOF
  chmod 600 "$CONF"
  echo "Created $CONF with defaults."
fi

# shellcheck disable=SC1090
. "$CONF"

TARGET_SESSION_ID="${1:-}"
if [ -n "$TARGET_SESSION_ID" ]; then
  bash "$HOME/.claude/scripts/_validate-session-id.sh" "$TARGET_SESSION_ID" >/dev/null || exit 1
  CLAUDE_SESSION_ID="$TARGET_SESSION_ID"
  SCOPE_LABEL="target session $TARGET_SESSION_ID"
elif [ -z "$CLAUDE_SESSION_ID" ]; then
  RES=$(bash "$HOME/.claude/scripts/_resolve-session-id.sh") || {
    echo "ERROR: could not determine the current session id." >&2
    exit 1
  }
  CLAUDE_SESSION_ID=$(printf '%s' "$RES" | sed -n '1p')
  SCOPE_LABEL="this session"
else
  SCOPE_LABEL="this session"
fi

mkdir -p "$HOME/.claude/tts-sessions"
touch "$HOME/.claude/tts-sessions/$CLAUDE_SESSION_ID"

TTS_KOKORO_URL="${TTS_KOKORO_URL:-http://127.0.0.1:8321}"
TTS_KOKORO_VOICE="${TTS_KOKORO_VOICE:-am_michael}"
TTS_KOKORO_SPEED="${TTS_KOKORO_SPEED:-1.0}"
TTS_OPENROUTER_MODEL="${TTS_OPENROUTER_MODEL:-liquid/lfm-2.5-1.2b-instruct:free}"
TTS_CLEAN_MODEL="${TTS_CLEAN_MODEL:-haiku}"

if [ -n "$OPENROUTER_API_KEY" ]; then
  CLEAN_DISPLAY="$TTS_OPENROUTER_MODEL (OpenRouter)"
else
  CLEAN_DISPLAY="$TTS_CLEAN_MODEL (Claude Code)"
fi

echo ""
echo "TTS enabled for $SCOPE_LABEL."
echo "  Session ID:   $CLAUDE_SESSION_ID"
echo "  Voice:        $TTS_VOICE  (Apple fallback)"
echo "  Rate:         $TTS_RATE wpm"
echo "  Kokoro voice: $TTS_KOKORO_VOICE @ ${TTS_KOKORO_SPEED}x"
echo "  Clean model:  $CLEAN_DISPLAY"
echo "  Conf:         $CONF"
echo ""
echo "Test speech firing now."

# Try Kokoro first; fall back to Apple `say` on any failure.
(
  WAV_FILE="/tmp/tts-enable-$CLAUDE_SESSION_ID-$$.wav"
  TEST_TEXT="Text-to-speech enabled."
  SYNTH_RESP=$(jq -nc \
                 --arg text  "$TEST_TEXT" \
                 --arg voice "$TTS_KOKORO_VOICE" \
                 --argjson speed "$TTS_KOKORO_SPEED" \
                 '{text:$text, voice:$voice, speed:$speed}' \
              | curl -fsS --max-time 8 \
                  -H "Content-Type: application/json" \
                  -d @- "$TTS_KOKORO_URL/synthesize" 2>/dev/null)
  AUDIO_B64=$(printf '%s' "$SYNTH_RESP" | jq -r '.audio // empty' 2>/dev/null)
  if [ -n "$AUDIO_B64" ]; then
    printf '%s' "$AUDIO_B64" | base64 -D > "$WAV_FILE" 2>/dev/null
  fi
  if [ -s "$WAV_FILE" ]; then
    afplay "$WAV_FILE"
    rm -f "$WAV_FILE"
  else
    rm -f "$WAV_FILE" 2>/dev/null
    say -v "$TTS_VOICE" -r "$TTS_RATE" "$TEST_TEXT"
  fi
) </dev/null >/dev/null 2>&1 &
disown
