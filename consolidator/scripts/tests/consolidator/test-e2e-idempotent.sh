#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-e2e-idempotent:"

HOOK="$HOME/.claude/scripts/consolidator-hook.sh"
FIX="$(dirname "$0")/fixtures"

TMP=$(mktemp_home)
export HOME="$TMP"
mkdir -p "$TMP/.claude/sessions"

SID="e2e-idem"
TRANSCRIPT="$TMP/transcript.jsonl"
cat "$FIX/single-fact.jsonl" > "$TRANSCRIPT"
yes "{\"type\":\"system\",\"message\":{\"role\":\"system\",\"content\":\"x\"}}" | head -n 60 >> "$TRANSCRIPT"
touch "$TMP/.claude/consolidator-sessions/$SID"

INPUT_JSON=$(jq -nc --arg sid "$SID" --arg t "$TRANSCRIPT" --arg c "/Users/foo" \
  '{session_id:$sid, transcript_path:$t, cwd:$c}')

# First run: add.
RESP='{"decisions":[{"action":"add","type":"reference","name":"linear-ingest","description":"hook","content":"body"}]}'
printf '%s' "$INPUT_JSON" | \
  CONSOLIDATOR_COOLDOWN_SEC=0 \
  CONSOLIDATOR_TEST_RESPONSE="$RESP" \
    bash "$HOOK"

MEM_DIR="$TMP/.claude/projects/-Users-foo/memory"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$MEM_DIR/linear-ingest.md" ] && break
  sleep 0.5
done
COUNT1=$(ls "$MEM_DIR"/*.md 2>/dev/null | grep -v '/MEMORY\.md$' | wc -l | tr -d ' ')
assert_eq "$COUNT1" "1" "after first run: 1 memory"

# Second run on the SAME transcript with cooldown=0 — cursor advanced past EOF, so phase-1 gate stops it.
printf '%s' "$INPUT_JSON" | \
  CONSOLIDATOR_COOLDOWN_SEC=0 \
  CONSOLIDATOR_TEST_RESPONSE="$RESP" \
    bash "$HOOK"

sleep 1
COUNT2=$(ls "$MEM_DIR"/*.md 2>/dev/null | grep -v '/MEMORY\.md$' | wc -l | tr -d ' ')
assert_eq "$COUNT2" "1" "second run: still 1 memory (no duplicate)"

INDEX_COUNT=$(grep -c '\.md)' "$MEM_DIR/MEMORY.md" || true)
assert_eq "$INDEX_COUNT" "1" "index has one entry only"

rm -rf "$TMP"
finish
