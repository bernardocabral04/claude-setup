#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-e2e-failures:"

HOOK="$HOME/.claude/scripts/consolidator-hook.sh"
FIX="$(dirname "$0")/fixtures"

TMP=$(mktemp_home)
export HOME="$TMP"
mkdir -p "$TMP/.claude/sessions"

SID="e2e-fail"
TRANSCRIPT="$TMP/transcript.jsonl"
cat "$FIX/single-fact.jsonl" > "$TRANSCRIPT"
yes "{\"type\":\"system\",\"message\":{\"role\":\"system\",\"content\":\"x\"}}" | head -n 60 >> "$TRANSCRIPT"
touch "$TMP/.claude/consolidator-sessions/$SID"

INPUT_JSON=$(jq -nc --arg sid "$SID" --arg t "$TRANSCRIPT" --arg c "/Users/foo" \
  '{session_id:$sid, transcript_path:$t, cwd:$c}')

# Inject malformed JSON 3 times.
for attempt in 1 2 3; do
  printf '%s' "$INPUT_JSON" | \
    CONSOLIDATOR_COOLDOWN_SEC=0 \
    CONSOLIDATOR_MAX_FAILED_ATTEMPTS=3 \
    CONSOLIDATOR_TEST_RESPONSE='not even json' \
      bash "$HOOK"
  sleep 1
done

. "$TMP/.claude/consolidator-sessions/$SID.cursor"
SIZE=$(stat -f %z "$TRANSCRIPT")
assert_eq "$LAST_EVAL_OFFSET" "$SIZE" "after 3 failures: cursor force-advanced"
assert_eq "$FAILED_ATTEMPTS" "0" "fails reset after force-advance"

assert_contains "$(cat "$TMP/.claude/consolidator-sessions/$SID.metrics.log")" "FORCE-ADVANCE" "force-advance logged"

rm -rf "$TMP"
finish
