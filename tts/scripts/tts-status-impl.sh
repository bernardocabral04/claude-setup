#!/bin/bash
CONF="$HOME/.claude/tts.conf"

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

FLAG="$HOME/.claude/tts-sessions/$CLAUDE_SESSION_ID"

if [ -f "$FLAG" ]; then
  STATE="ENABLED"
else
  STATE="disabled"
fi

echo "TTS state: $STATE"
echo "  Session ID: $CLAUDE_SESSION_ID"

if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF"
  echo "  Voice:        ${TTS_VOICE:-Samantha}"
  echo "  Rate:         ${TTS_RATE:-200} wpm"
  echo "  Kokoro voice: ${TTS_KOKORO_VOICE:-am_michael}"
  echo "  Kokoro speed: ${TTS_KOKORO_SPEED:-1.0}x"
  echo "  Kokoro URL:   ${TTS_KOKORO_URL:-http://127.0.0.1:8321}"
  if curl -fsS --max-time 1 "${TTS_KOKORO_URL:-http://127.0.0.1:8321}/voices" >/dev/null 2>&1; then
    echo "  Kokoro state: reachable ✓"
  else
    echo "  Kokoro state: UNREACHABLE — will fall back to Apple say"
  fi
  if [ -n "$OPENROUTER_API_KEY" ]; then
    echo "  Cleanup path: openrouter (${TTS_OPENROUTER_MODEL:-liquid/lfm-2.5-1.2b-instruct:free})"
  else
    echo "  Cleanup path: claude -p (${TTS_CLEAN_MODEL:-haiku})  ← slow, set OPENROUTER_API_KEY for fast path"
  fi
  echo "  Max chars:    ${TTS_MAX_CHARS:-1200}"
  echo "  Conf:         $CONF"
else
  echo "  Conf:         (not created — run /tts-enable to bootstrap)"
fi

# Show last cleaned text if exists.
LAST="$HOME/.claude/tts-sessions/$CLAUDE_SESSION_ID.last.txt"
if [ -f "$LAST" ]; then
  echo ""
  echo "Last cleaned narration:"
  echo "─────"
  cat "$LAST"
  echo "─────"
fi

# Latency metrics (last 5 runs, plus rolling averages).
METRICS="$HOME/.claude/tts-sessions/$CLAUDE_SESSION_ID.metrics.log"
if [ -f "$METRICS" ]; then
  echo ""
  echo "Latency (last 5 runs):"
  tail -5 "$METRICS" | sed 's/^/  /'
  echo ""
  awk -F'[ =s|]+' '
    /extract/ {
      n++
      for (i=1;i<=NF;i++) {
        if ($i=="extract") ex+=$(i+1)
        if ($i=="cleanup") cl+=$(i+1)
        if ($i=="total")   tt+=$(i+1)
      }
    }
    END {
      if (n>0) printf "  Avg over %d runs: extract=%.2fs cleanup=%.2fs total=%.2fs\n", n, ex/n, cl/n, tt/n
    }' "$METRICS"
fi
