#!/usr/bin/env bash
# Regression test: engine-error:no-api-key written by call_llm must survive
# the hook's EXIT trap so status and statusline can surface it.
#
# Approach: run the full hook background pipeline with engine=openrouter and
# no OPENROUTER_API_KEY. The hook exits quickly; we poll for the bg subshell
# to finish (state file or cursor file appears), then assert the state file
# still contains engine-error:no-api-key.
#
# No mocking of claude -p needed — the openrouter+no-key path is purely
# shell-side in call_llm and returns immediately before touching claude.
. "$(dirname "$0")/lib.sh"

echo "test-engine-error-persists:"

HOOK="$HOME/.claude/scripts/consolidator-hook.sh"
FIX="$(dirname "$0")/fixtures"

TMP=$(mktemp_home)
export HOME="$TMP"

SID="test-engine-error-session"
SESS_DIR="$TMP/.claude/consolidator-sessions"
TRANSCRIPT="$TMP/transcript.jsonl"

# Use a real fixture so extract_slice finds user/assistant content.
# Pad with system messages to exceed the min-bytes gate.
cat "$FIX/single-fact.jsonl" > "$TRANSCRIPT"
yes '{"type":"system","message":{"role":"system","content":"x"}}' \
  | head -n 100 >> "$TRANSCRIPT"

# Create the session flag file with engine=openrouter.
# Also disable cooldown/min-bytes gates so the bg pipeline runs immediately.
cat > "$SESS_DIR/$SID" <<'EOF'
CONSOLIDATOR_ENGINE=openrouter
CONSOLIDATOR_COOLDOWN_SEC=0
CONSOLIDATOR_MIN_NEW_BYTES=0
EOF

# Ensure no API key is set so the engine-error path triggers.
unset OPENROUTER_API_KEY

INPUT_JSON=$(jq -nc \
  --arg sid "$SID" \
  --arg t   "$TRANSCRIPT" \
  --arg c   "/tmp/test-cwd" \
  '{session_id:$sid, transcript_path:$t, cwd:$c}')

# Run the hook (exits fast; bg subshell does the work).
printf '%s' "$INPUT_JSON" | \
  OPENROUTER_API_KEY="" \
  bash "$HOOK"

# Poll until the state file appears with engine-error content, OR a cursor
# file is written (which would indicate the pipeline took a different path),
# OR we time out. The bg subshell finishes quickly since call_llm returns
# immediately when engine=openrouter and OPENROUTER_API_KEY is unset.
WAITED=0
STATE_SEEN=0
while [ "$WAITED" -lt 20 ]; do
  if [ -f "$SESS_DIR/$SID.state" ]; then
    CONTENT=$(cat "$SESS_DIR/$SID.state" 2>/dev/null)
    case "$CONTENT" in
      engine-error:*) STATE_SEEN=1; break ;;
    esac
  fi
  # Also stop if the cursor appeared (pipeline ended without engine-error).
  [ -f "$SESS_DIR/$SID.cursor" ] && break
  sleep 0.3
  WAITED=$((WAITED + 1))
done

# Assert the state file exists and contains engine-error:no-api-key.
assert_file_exists "$SESS_DIR/$SID.state" "engine-error state file preserved by EXIT trap"

if [ -f "$SESS_DIR/$SID.state" ]; then
  STATE_CONTENT=$(cat "$SESS_DIR/$SID.state")
  assert_eq "$STATE_CONTENT" "engine-error:no-api-key" "state file contains engine-error:no-api-key"
else
  echo "  FAIL: state file contains engine-error:no-api-key (file absent)"
  FAILS=$((FAILS + 1))
fi

rm -rf "$TMP"
finish
