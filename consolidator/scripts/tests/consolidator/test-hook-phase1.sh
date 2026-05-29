#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-hook-phase1:"

HOOK="$HOME/.claude/scripts/consolidator-hook.sh"

TMP=$(mktemp_home)
export HOME="$TMP"
mkdir -p "$TMP/.claude/sessions"
SID="test-session-1"
TRANSCRIPT="$TMP/transcript.jsonl"
: > "$TRANSCRIPT"

INPUT_JSON=$(jq -nc --arg sid "$SID" --arg t "$TRANSCRIPT" --arg c "/Users/foo" \
  '{session_id:$sid, transcript_path:$t, cwd:$c}')

# 1. No flag file → exit 0, no side effects.
EXIT_CODE=0
printf '%s' "$INPUT_JSON" | bash "$HOOK" || EXIT_CODE=$?
assert_eq "$EXIT_CODE" "0" "no flag → exit 0"
assert_file_missing "$TMP/.claude/consolidator-sessions/$SID.state" "no state written"

# 2. Flag present but recursion guard set → exit 0 even with content.
echo '{"x":"y"}' > "$TRANSCRIPT"
touch "$TMP/.claude/consolidator-sessions/$SID"
EXIT_CODE=0
CLAUDE_CONSOLIDATOR=1 printf '%s' "$INPUT_JSON" | CLAUDE_CONSOLIDATOR=1 bash "$HOOK" || EXIT_CODE=$?
assert_eq "$EXIT_CODE" "0" "recursion guard → exit 0"
assert_file_missing "$TMP/.claude/consolidator-sessions/$SID.state" "no state under recursion guard"

# 3. Flag + tiny transcript (< MIN_NEW_BYTES) → exit 0, NO fork.
printf 'hi\n' > "$TRANSCRIPT"
EXIT_CODE=0
printf '%s' "$INPUT_JSON" | bash "$HOOK" || EXIT_CODE=$?
assert_eq "$EXIT_CODE" "0" "tiny transcript → exit 0"
sleep 0.2
assert_file_missing "$TMP/.claude/consolidator-sessions/$SID.state" "no state file (gate blocked fork)"

# 4. Flag + big transcript + cooldown expired → SHOULD fork. State file appears.
yes "this is filler content to exceed min-new-bytes threshold for the gate." | head -c 3000 > "$TRANSCRIPT"
export CONSOLIDATOR_TEST_RESPONSE='{"decisions":[]}'
EXIT_CODE=0
printf '%s' "$INPUT_JSON" | CONSOLIDATOR_TEST_RESPONSE="$CONSOLIDATOR_TEST_RESPONSE" bash "$HOOK" || EXIT_CODE=$?
assert_eq "$EXIT_CODE" "0" "fork case → hook still exits 0 quickly"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$TMP/.claude/consolidator-sessions/$SID.cursor" ] && break
  sleep 0.5
done
assert_file_exists "$TMP/.claude/consolidator-sessions/$SID.cursor" "bg pipeline ran and wrote cursor"

rm -rf "$TMP"
finish
