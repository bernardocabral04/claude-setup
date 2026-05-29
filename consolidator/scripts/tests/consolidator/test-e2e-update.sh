#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-e2e-update:"

HOOK="$HOME/.claude/scripts/consolidator-hook.sh"
FIX="$(dirname "$0")/fixtures"

TMP=$(mktemp_home)
export HOME="$TMP"
mkdir -p "$TMP/.claude/sessions"

SID="e2e-update"
TRANSCRIPT="$TMP/transcript.jsonl"
cat "$FIX/single-fact.jsonl" > "$TRANSCRIPT"
yes "{\"type\":\"system\",\"message\":{\"role\":\"system\",\"content\":\"x\"}}" | head -n 60 >> "$TRANSCRIPT"
touch "$TMP/.claude/consolidator-sessions/$SID"

INPUT_JSON=$(jq -nc --arg sid "$SID" --arg t "$TRANSCRIPT" --arg c "/Users/foo" \
  '{session_id:$sid, transcript_path:$t, cwd:$c}')

# Pass 1: add.
RESP_ADD='{"decisions":[{"action":"add","type":"reference","name":"linear-ingest","description":"pipeline bugs","content":"Pipeline bugs in Linear INGEST."}]}'
printf '%s' "$INPUT_JSON" | \
  CONSOLIDATOR_COOLDOWN_SEC=0 \
  CONSOLIDATOR_TEST_RESPONSE="$RESP_ADD" \
    bash "$HOOK"

MEM_DIR="$TMP/.claude/projects/-Users-foo/memory"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$MEM_DIR/linear-ingest.md" ] && break
  sleep 0.5
done

# Pass 2: append update fixture so new_bytes ≥ min, then update.
cat "$FIX/update-fact.jsonl" >> "$TRANSCRIPT"
yes "{\"type\":\"system\",\"message\":{\"role\":\"system\",\"content\":\"x\"}}" | head -n 60 >> "$TRANSCRIPT"

RESP_UPD='{"decisions":[{"action":"update","type":"reference","name":"linear-ingest","description":"bugs + incidents","content":"Pipeline bugs AND incidents in Linear INGEST."}]}'
printf '%s' "$INPUT_JSON" | \
  CONSOLIDATOR_COOLDOWN_SEC=0 \
  CONSOLIDATOR_TEST_RESPONSE="$RESP_UPD" \
    bash "$HOOK"

sleep 2

BODY=$(cat "$MEM_DIR/linear-ingest.md")
assert_contains "$BODY" "Pipeline bugs AND incidents" "body replaced"
assert_contains "$(cat "$MEM_DIR/MEMORY.md")" "bugs + incidents" "index hook updated"

COUNT=$(ls "$MEM_DIR"/*.md | grep -v '/MEMORY\.md$' | wc -l | tr -d ' ')
assert_eq "$COUNT" "1" "no duplicate file"

rm -rf "$TMP"
finish
