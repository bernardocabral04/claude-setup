#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-e2e-empty:"

HOOK="$HOME/.claude/scripts/consolidator-hook.sh"
FIX="$(dirname "$0")/fixtures"

TMP=$(mktemp_home)
export HOME="$TMP"
mkdir -p "$TMP/.claude/sessions"

SID="e2e-empty"
TRANSCRIPT="$TMP/transcript.jsonl"

# Use the existing empty.jsonl but pad it to exceed min-new-bytes.
cat "$FIX/empty.jsonl" > "$TRANSCRIPT"
yes "{\"type\":\"system\",\"message\":{\"role\":\"system\",\"content\":\"x\"}}" | head -n 60 >> "$TRANSCRIPT"

touch "$TMP/.claude/consolidator-sessions/$SID"

INPUT_JSON=$(jq -nc --arg sid "$SID" --arg t "$TRANSCRIPT" --arg c "/Users/foo" \
  '{session_id:$sid, transcript_path:$t, cwd:$c}')

printf '%s' "$INPUT_JSON" | \
  CONSOLIDATOR_COOLDOWN_SEC=0 \
  CONSOLIDATOR_TEST_RESPONSE='{"decisions":[]}' \
    bash "$HOOK"

# Wait for background.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$TMP/.claude/consolidator-sessions/$SID.cursor" ] && break
  sleep 0.5
done

assert_file_exists "$TMP/.claude/consolidator-sessions/$SID.cursor" "cursor written"
MEM_DIR="$TMP/.claude/projects/-Users-foo/memory"
assert_file_exists "$MEM_DIR/MEMORY.md" "MEMORY.md bootstrapped"
COUNT=$(grep -c '\.md)' "$MEM_DIR/MEMORY.md" || true)
assert_eq "$COUNT" "0" "no memory entries"

rm -rf "$TMP"
finish
