#!/bin/bash
# Terminate all TTS-spawned audio players and clean up pidfiles.
# Idempotent: always exits 0. Appends audit log entry.

set -o pipefail
export LC_ALL=C

# Count live TTS players before killing — drives the notification outcome.
LIVE=$(($(pgrep -f "afplay /tmp/tts-" 2>/dev/null | wc -l) + $(pgrep -f "say -v " 2>/dev/null | wc -l)))

# Kill every TTS-spawned afplay (Kokoro path) and Apple fallback speaker.
pkill -f "afplay /tmp/tts-" 2>/dev/null || true
pkill -f "say -v " 2>/dev/null || true

# Walk pidfiles, clean up stale entries.
for f in "$HOME"/.claude/tts-sessions/*.pid; do
  [ -f "$f" ] || continue
  PID=$(cat "$f" 2>/dev/null)
  [ -z "$PID" ] && continue
  if ! kill -0 "$PID" 2>/dev/null; then
    rm -f "$f" 2>/dev/null || true
  fi
done

# Audit log: append stop event.
mkdir -p "$HOME"/.claude/tts-sessions
echo "$(date -u +%FT%TZ) | STOP-ALL killed=$LIVE" >> "$HOME"/.claude/tts-sessions/.stop.log

if [ "$LIVE" -gt 0 ]; then
  /usr/bin/osascript -e 'display notification "Silenced all Claude sessions" with title "Claude TTS" sound name "Submarine"' 2>/dev/null || true
else
  /usr/bin/osascript -e 'display notification "No Claude TTS playing" with title "Claude TTS"' 2>/dev/null || true
fi

exit 0
