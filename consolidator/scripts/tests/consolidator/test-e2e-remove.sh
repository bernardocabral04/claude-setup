#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-e2e-remove:"

HOOK="$HOME/.claude/scripts/consolidator-hook.sh"
FIX="$(dirname "$0")/fixtures"

TMP=$(mktemp_home)
export HOME="$TMP"
mkdir -p "$TMP/.claude/sessions"

SID="e2e-remove"
TRANSCRIPT="$TMP/transcript.jsonl"
cat "$FIX/single-fact.jsonl" > "$TRANSCRIPT"
yes "{\"type\":\"system\",\"message\":{\"role\":\"system\",\"content\":\"x\"}}" | head -n 60 >> "$TRANSCRIPT"
touch "$TMP/.claude/consolidator-sessions/$SID"

INPUT_JSON=$(jq -nc --arg sid "$SID" --arg t "$TRANSCRIPT" --arg c "/Users/foo" \
  '{session_id:$sid, transcript_path:$t, cwd:$c}')

# Pass 1: add.
RESP_ADD='{"decisions":[{"action":"add","type":"reference","name":"linear-ingest","description":"hook","content":"body"}]}'
printf '%s' "$INPUT_JSON" | \
  CONSOLIDATOR_COOLDOWN_SEC=0 \
  CONSOLIDATOR_TEST_RESPONSE="$RESP_ADD" \
    bash "$HOOK"

MEM_DIR="$TMP/.claude/projects/-Users-foo/memory"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$MEM_DIR/linear-ingest.md" ] && break
  sleep 0.5
done

# Pass 2: remove.
cat "$FIX/remove-fact.jsonl" >> "$TRANSCRIPT"
yes "{\"type\":\"system\",\"message\":{\"role\":\"system\",\"content\":\"x\"}}" | head -n 60 >> "$TRANSCRIPT"

RESP_RM='{"decisions":[{"action":"remove","type":"reference","name":"linear-ingest","description":"removed per user request"}]}'
printf '%s' "$INPUT_JSON" | \
  CONSOLIDATOR_COOLDOWN_SEC=0 \
  CONSOLIDATOR_TEST_RESPONSE="$RESP_RM" \
    bash "$HOOK"

sleep 2

assert_file_missing "$MEM_DIR/linear-ingest.md" "active file gone"
TRASHED=$(ls "$MEM_DIR/.trash"/*-linear-ingest.md 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$TRASHED" "1" "file in .trash"
COUNT=$(grep -c "linear-ingest.md" "$MEM_DIR/MEMORY.md" || true)
assert_eq "$COUNT" "0" "index entry gone"

rm -rf "$TMP"
finish
