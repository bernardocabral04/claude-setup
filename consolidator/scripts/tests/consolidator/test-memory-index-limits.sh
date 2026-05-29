#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-memory-index-limits:"

# shellcheck disable=SC1090
. "$LIB_PATH"

TMP=$(mktemp_home)
MEM_DIR="$TMP/.claude-work/projects/-test/memory"
bootstrap_mem_dir "$MEM_DIR"

# --- Fix 3a: index line truncation to ≤150 chars ---

# Build a description that would push the line well past 150 chars.
# "- [Long Name](long-name.md) — " is 31 chars, so a 130-char description
# gives a 161-char line before truncation.
LONG_DESC=$(printf '%0.s-' {1..130})  # 130 dashes
apply_decision "$MEM_DIR" add reference long-name "short stand-in" "some body content"
# Now update with the long description to exercise truncation.
apply_decision "$MEM_DIR" update reference long-name "$LONG_DESC" "some body content"

LINE=$(grep "long-name.md" "$MEM_DIR/MEMORY.md")
LINE_LEN=${#LINE}
if [ "$LINE_LEN" -le 150 ]; then
  echo "  ok: index line ≤150 chars (got $LINE_LEN)"
else
  echo "  FAIL: index line is $LINE_LEN chars (expected ≤150)"
  FAILS=$((FAILS + 1))
fi

# Also check the ellipsis is present (confirming truncation happened).
assert_contains "$LINE" "…" "ellipsis present when line was truncated"

# --- Fix 3b: MEMORY.md truncated to ≤200 lines after >200 entries ---

TMP2=$(mktemp_home)
MEM_DIR2="$TMP2/.claude-work/projects/-test2/memory"
bootstrap_mem_dir "$MEM_DIR2"

# Add 250 fake entries by direct update_index calls (avoids needing real files).
i=1
while [ $i -le 250 ]; do
  slug=$(printf 'entry-%04d' "$i")
  update_index "$MEM_DIR2/MEMORY.md" "$slug" "- [Entry $i]($slug.md) — description for entry $i"
  i=$((i + 1))
done

LINES=$(wc -l < "$MEM_DIR2/MEMORY.md")
if [ "$LINES" -le 200 ]; then
  echo "  ok: MEMORY.md has ≤200 lines after 250 inserts (got $LINES)"
else
  echo "  FAIL: MEMORY.md has $LINES lines (expected ≤200)"
  FAILS=$((FAILS + 1))
fi

# Sanity: header line should still be present.
assert_contains "$(head -1 "$MEM_DIR2/MEMORY.md")" "#" "header line preserved after truncation"

rm -rf "$TMP" "$TMP2"
finish
