#!/bin/bash
# Claude Code Stop-hook TTS handler.
#
# Flow:
#   1. Gate on per-session flag (~/.claude/tts-sessions/<id>).
#   2. Read the closing assistant text from the hook stdin JSON
#      (`last_assistant_message`), falling back to transcript parsing.
#   3. Skip if it matches the prior turn's text (idempotency guard).
#   4. Rewrite for speech via OpenRouter (free model) or `claude -p`.
#   5. Speak via macOS `say` in a detached subshell — the hook returns
#      in well under 100ms.
#
# Per-session files in ~/.claude/tts-sessions/<id>{,.last.txt,.last_raw.txt,
# .pid,.metrics.log,.debug.log}.

# Recursion guard: the cleanup `claude -p` subprocess (fallback path) would
# otherwise fire its own Stop hook and re-enter this script.
[ -n "$CLAUDE_TTS_CLEANUP" ] && exit 0

NOW() { python3 -c 'import time; print(f"{time.time():.3f}")'; }
DELTA() { python3 -c "print(f'{$2-$1:.2f}')"; }
T_HOOK_IN=$(NOW)

INPUT=$(cat 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT"   | jq -r '.session_id            // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT"   | jq -r '.transcript_path       // empty' 2>/dev/null)
HOOK_LAST_MSG=$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)

[ -z "$SESSION_ID" ] && exit 0
[ -f "$HOME/.claude/tts-sessions/$SESSION_ID" ] || exit 0

CONF="$HOME/.claude/tts.conf"
[ -f "$CONF" ] && . "$CONF"
# Per-session conf overrides global. Same file pattern as ntfy.
SESSION_CONF="$HOME/.claude/tts-sessions/$SESSION_ID.conf"
[ -f "$SESSION_CONF" ] && . "$SESSION_CONF"

TTS_VOICE="${TTS_VOICE:-Samantha}"
TTS_RATE="${TTS_RATE:-200}"
TTS_MODE="${TTS_MODE:-normal}"
TTS_CLEAN_MODEL="${TTS_CLEAN_MODEL:-haiku}"
TTS_OPENROUTER_MODEL="${TTS_OPENROUTER_MODEL:-liquid/lfm-2.5-1.2b-instruct:free}"
TTS_MAX_CHARS="${TTS_MAX_CHARS:-1200}"
TTS_KOKORO_URL="${TTS_KOKORO_URL:-http://127.0.0.1:8321}"
TTS_KOKORO_VOICE="${TTS_KOKORO_VOICE:-am_michael}"
TTS_KOKORO_SPEED="${TTS_KOKORO_SPEED:-1.0}"

if [ -n "$OPENROUTER_API_KEY" ]; then
  CLEAN_PATH="openrouter:$TTS_OPENROUTER_MODEL"
else
  CLEAN_PATH="claude-cli:$TTS_CLEAN_MODEL"
fi

# Source RAW. Fast path: hook stdin. Fallback: walk the transcript JSONL.
LAST_RAW_FILE="$HOME/.claude/tts-sessions/$SESSION_ID.last_raw.txt"
PREV_RAW=""
[ -f "$LAST_RAW_FILE" ] && PREV_RAW=$(cat "$LAST_RAW_FILE")

extract_last_assistant_text() {
  python3 - "$1" <<'PY'
import sys, json
path = sys.argv[1]
last = ""
try:
    with open(path) as f:
        for line in f:
            try:
                m = json.loads(line)
            except Exception:
                continue
            msg = m.get("message") or {}
            if msg.get("role") != "assistant":
                continue
            content = msg.get("content")
            parts = []
            if isinstance(content, str):
                parts.append(content)
            elif isinstance(content, list):
                for b in content:
                    if isinstance(b, dict) and b.get("type") == "text":
                        t = b.get("text", "")
                        if t:
                            parts.append(t)
            if parts:
                last = "\n".join(parts)
except Exception:
    pass
print(last)
PY
}

if [ -n "$HOOK_LAST_MSG" ]; then
  RAW="$HOOK_LAST_MSG"
elif [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  RAW=$(extract_last_assistant_text "$TRANSCRIPT")
else
  RAW=""
fi

METRICS_LOG="$HOME/.claude/tts-sessions/$SESSION_ID.metrics.log"
if [ -z "$RAW" ]; then
  echo "$(date -u +%FT%TZ) | SKIP: RAW empty" >> "$METRICS_LOG"
  exit 0
fi
if [ "$RAW" = "$PREV_RAW" ]; then
  echo "$(date -u +%FT%TZ) | SKIP: RAW unchanged from prior turn" >> "$METRICS_LOG"
  exit 0
fi
printf '%s' "$RAW" > "$LAST_RAW_FILE"

T_EXTRACT_DONE=$(NOW)
RAW_CHARS=${#RAW}

# Pidfile for the audio player. Kill of prior speech is deferred to after
# cleanup (inside the background subshell) so the user can keep listening
# to the previous message during the cleanup window. Synth then provides
# a deliberate silence gap as UX cue before new speech begins.
PIDFILE="$HOME/.claude/tts-sessions/$SESSION_ID.pid"

LAST_FILE="$HOME/.claude/tts-sessions/$SESSION_ID.last.txt"

# Pick the prompt file for the resolved mode. Falls back to normal, then to a
# minimal inline string if no file exists at all.
CLEAN_PROMPT_FILE="$HOME/.claude/scripts/tts-clean-prompt-$TTS_MODE.txt"
[ -f "$CLEAN_PROMPT_FILE" ] || CLEAN_PROMPT_FILE="$HOME/.claude/scripts/tts-clean-prompt-normal.txt"
CLEAN_PROMPT=$(cat "$CLEAN_PROMPT_FILE" 2>/dev/null)
[ -z "$CLEAN_PROMPT" ] && CLEAN_PROMPT="Rewrite for TTS. Speak only the closing summary, casual tone, under 400 chars. If no narratable content, output NOSPEAK."

# Background pipeline: cleanup → say. Detached so the hook returns instantly.
(
  # Statusline state file — read by statusline-command.sh to show "cleaning…"
  # / "synthesizing…" chip on line 3. Trap guarantees cleanup on any exit path.
  STATEFILE="$HOME/.claude/tts-sessions/$SESSION_ID.state"
  trap 'rm -f "$STATEFILE"' EXIT

  PAYLOAD=$(printf 'Clean the following <source> text for text-to-speech playback. Apply the rules in your system prompt. Output ONLY the narration.\n\n<source>\n%s\n</source>' "$RAW")

  echo cleaning > "$STATEFILE"
  if [ -n "$OPENROUTER_API_KEY" ]; then
    # Fast path: OpenRouter free-tier model via curl + jq. ~1-2s.
    # jq handles JSON escaping of system + user content; curl uses macOS trust store.
    CLEAN=$(jq -nc \
              --arg model "$TTS_OPENROUTER_MODEL" \
              --arg sys "$CLEAN_PROMPT" \
              --arg usr "$PAYLOAD" \
              '{model:$model, messages:[{role:"system",content:$sys},{role:"user",content:$usr}], max_tokens:400, temperature:0.3}' \
            | curl -s --max-time 30 \
                -H "Authorization: Bearer $OPENROUTER_API_KEY" \
                -H "Content-Type: application/json" \
                -H "HTTP-Referer: https://claude.com/claude-code" \
                -H "X-Title: Claude Code TTS" \
                -d @- https://openrouter.ai/api/v1/chat/completions \
            | jq -r '.choices[0].message.content // empty')
  else
    # Fallback: claude -p (cold start ~10s).
    CLEAN=$(printf '%s' "$PAYLOAD" \
      | CLAUDE_TTS_CLEANUP=1 claude -p --model "$TTS_CLEAN_MODEL" --output-format text \
          --no-session-persistence \
          --disable-slash-commands \
          --append-system-prompt "$CLEAN_PROMPT" 2>/dev/null \
      | tr -d '\r')
  fi

  # Fallback: if cleanup failed or returned empty, use a stripped-down RAW.
  if [ -z "$CLEAN" ]; then
    CLEAN=$(printf '%s' "$RAW" \
      | sed -E 's/```[^`]*```//g; s/`[^`]*`//g; s/https?:\/\/[^ ]+//g; s/[#*_>|]//g' \
      | tr -s ' \n' ' ' \
      | cut -c1-"$TTS_MAX_CHARS")
  fi

  # Skip if cleaner says nothing speakable. Old speech (if any) keeps playing —
  # we don't interrupt for empty turns. Logged to metrics for visibility so
  # silent skips don't disappear into the void.
  if [ "$CLEAN" = "NOSPEAK" ] || [ -z "$CLEAN" ]; then
    T_NOSPEAK=$(NOW)
    DT_EXTRACT=$(DELTA "$T_HOOK_IN" "$T_EXTRACT_DONE")
    DT_CLEANUP=$(DELTA "$T_EXTRACT_DONE" "$T_NOSPEAK")
    REASON="NOSPEAK"
    [ -z "$CLEAN" ] && REASON="EMPTY"
    PROMPT_BASE=$(basename "$CLEAN_PROMPT_FILE")
    printf '%s | SKIP: %s | extract=%ss | cleanup=%ss | path=%s | mode=%s | prompt=%s | %d chars raw\n' \
      "$(date -u +%FT%TZ)" "$REASON" "$DT_EXTRACT" "$DT_CLEANUP" \
      "$CLEAN_PATH" "$TTS_MODE" "$PROMPT_BASE" "$RAW_CHARS" >> "$METRICS_LOG"
    exit 0
  fi

  # Cleanup yielded speakable content → silence prior speech now, before synth.
  # The synth window (~1-2s) becomes a deliberate UX gap signalling "new message".
  if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
    if [ -n "$OLD_PID" ]; then
      pkill -P "$OLD_PID" 2>/dev/null || true
      kill "$OLD_PID" 2>/dev/null || true
    fi
  fi

  T_CLEAN_DONE=$(NOW)

  # Hard cap.
  CLEAN=$(printf '%s' "$CLEAN" | cut -c1-"$TTS_MAX_CHARS")
  CLEAN_CHARS=${#CLEAN}

  printf '%s\n' "$CLEAN" > "$LAST_FILE"

  # Per-turn debug log so we can compare what was sent vs what was spoken.
  DEBUG_LOG="$HOME/.claude/tts-sessions/$SESSION_ID.debug.log"
  {
    echo ""
    echo "========== $(date -u +%FT%TZ) =========="
    echo "--- RAW ($RAW_CHARS chars) ---"
    echo "$RAW"
    echo "--- CLEAN ($CLEAN_CHARS chars) ---"
    echo "$CLEAN"
  } >> "$DEBUG_LOG"

  T_SYNTH_START=$(NOW)

  # ----- Engine: try Kokoro first -----
  ENGINE="kokoro"
  KOKORO_VOICE_FOR_METRIC="$TTS_KOKORO_VOICE"
  WAV_FILE="/tmp/tts-$SESSION_ID-$(date +%s).wav"
  echo synthesizing > "$STATEFILE"
  SYNTH_RESP=$(jq -nc \
                 --arg text  "$CLEAN" \
                 --arg voice "$TTS_KOKORO_VOICE" \
                 --argjson speed "$TTS_KOKORO_SPEED" \
                 '{text:$text, voice:$voice, speed:$speed}' \
              | curl -fsS --max-time 30 \
                  -H "Content-Type: application/json" \
                  -d @- "$TTS_KOKORO_URL/synthesize" 2>/dev/null)
  AUDIO_B64=$(printf '%s' "$SYNTH_RESP" | jq -r '.audio // empty' 2>/dev/null)
  if [ -n "$AUDIO_B64" ]; then
    printf '%s' "$AUDIO_B64" | base64 -D > "$WAV_FILE" 2>/dev/null
  fi

  write_metric() {
    local engine=$1 voice=$2
    local T_NOW
    T_NOW=$(NOW)
    local DT_EXTRACT DT_CLEANUP DT_SYNTH DT_TOTAL PROMPT_BASE
    DT_EXTRACT=$(DELTA "$T_HOOK_IN" "$T_EXTRACT_DONE")
    DT_CLEANUP=$(DELTA "$T_EXTRACT_DONE" "$T_CLEAN_DONE")
    DT_SYNTH=$(DELTA "$T_SYNTH_START" "$T_NOW")
    DT_TOTAL=$(DELTA "$T_HOOK_IN" "$T_NOW")
    PROMPT_BASE=$(basename "$CLEAN_PROMPT_FILE")
    printf '%s | extract=%ss | cleanup=%ss | synth=%ss | total=%ss | engine=%s | voice=%s | path=%s | mode=%s | prompt=%s | %d->%d chars\n' \
      "$(date -u +%FT%TZ)" "$DT_EXTRACT" "$DT_CLEANUP" "$DT_SYNTH" "$DT_TOTAL" \
      "$engine" "$voice" "$CLEAN_PATH" "$TTS_MODE" "$PROMPT_BASE" "$RAW_CHARS" "$CLEAN_CHARS" >> "$METRICS_LOG"
  }

  if [ -s "$WAV_FILE" ]; then
    write_metric "kokoro" "$KOKORO_VOICE_FOR_METRIC"
    echo speaking > "$STATEFILE"
    # Background + $! so we record the player's actual PID. macOS bash 3.2
    # has no $BASHPID, and $$ in a subshell still expands to the parent.
    afplay "$WAV_FILE" &
    echo $! > "$PIDFILE"
    wait $!
    exit 0
  fi

  # ----- Fallback: Apple `say` -----
  ENGINE="apple-fallback"
  rm -f "$WAV_FILE" 2>/dev/null
  write_metric "apple-fallback" "$TTS_VOICE"
  echo speaking > "$STATEFILE"
  say -v "$TTS_VOICE" -r "$TTS_RATE" -- "$CLEAN" &
  echo $! > "$PIDFILE"
  wait $!
) </dev/null >/dev/null 2>&1 &
disown
exit 0
