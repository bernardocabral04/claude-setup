#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-e2e-add:"

HOOK="$HOME/.claude/scripts/consolidator-hook.sh"
FIX="$(dirname "$0")/fixtures"

TMP=$(mktemp_home)
export HOME="$TMP"
mkdir -p "$TMP/.claude/sessions"

SID="e2e-add"
TRANSCRIPT="$TMP/transcript.jsonl"
cat "$FIX/single-fact.jsonl" > "$TRANSCRIPT"
yes "{\"type\":\"system\",\"message\":{\"role\":\"system\",\"content\":\"x\"}}" | head -n 60 >> "$TRANSCRIPT"
touch "$TMP/.claude/consolidator-sessions/$SID"

INPUT_JSON=$(jq -nc --arg sid "$SID" --arg t "$TRANSCRIPT" --arg c "/Users/foo" \
  '{session_id:$sid, transcript_path:$t, cwd:$c}')

RESP='{"decisions":[{"action":"add","type":"reference","name":"linear-ingest","description":"pipeline bugs go in INGEST","content":"Pipeline bugs are tracked in Linear project INGEST."}]}'

printf '%s' "$INPUT_JSON" | \
  CONSOLIDATOR_COOLDOWN_SEC=0 \
  CONSOLIDATOR_TEST_RESPONSE="$RESP" \
    bash "$HOOK"

MEM_DIR="$TMP/.claude/projects/-Users-foo/memory"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$MEM_DIR/linear-ingest.md" ] && break
  sleep 0.5
done

assert_file_exists "$MEM_DIR/linear-ingest.md" "memory file written"
assert_contains "$(cat "$MEM_DIR/linear-ingest.md")" "type: reference" "frontmatter type"
assert_contains "$(cat "$MEM_DIR/linear-ingest.md")" "Pipeline bugs are tracked" "body present"
assert_contains "$(cat "$MEM_DIR/MEMORY.md")" "[Linear Ingest](linear-ingest.md)" "index entry"

. "$TMP/.claude/consolidator-sessions/$SID.cursor"
assert_ne "$LAST_EVAL_OFFSET" "0" "cursor advanced"

rm -rf "$TMP"
finish
