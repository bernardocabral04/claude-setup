#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-apply-decision:"

# shellcheck disable=SC1090
. "$LIB_PATH"

TMP=$(mktemp_home)
MEM_DIR="$TMP/.claude-work/projects/-test/memory"
bootstrap_mem_dir "$MEM_DIR"

# === ADD ===
apply_decision "$MEM_DIR" add reference linear-ingest "Linear project for pipeline bugs" "Pipeline bugs go in Linear project INGEST."
assert_file_exists "$MEM_DIR/linear-ingest.md" "add wrote file"
assert_contains "$(cat "$MEM_DIR/linear-ingest.md")" "type: reference" "frontmatter has type"
assert_contains "$(cat "$MEM_DIR/linear-ingest.md")" "Pipeline bugs go in Linear project INGEST." "body present"
assert_contains "$(cat "$MEM_DIR/MEMORY.md")" "[Linear Ingest](linear-ingest.md)" "index entry added"

# === ADD collision -> downgrade to update ===
apply_decision "$MEM_DIR" add reference linear-ingest "REVISED description" "Pipeline AND incident bugs go in INGEST."
assert_contains "$(cat "$MEM_DIR/linear-ingest.md")" "REVISED description" "collision downgraded to update (file body)"
assert_contains "$(cat "$MEM_DIR/MEMORY.md")" "REVISED description" "index updated on collision-downgrade"
COUNT=$(grep -c "linear-ingest.md" "$MEM_DIR/MEMORY.md")
assert_eq "$COUNT" "1" "no duplicate index line after collision"

# === UPDATE ===
apply_decision "$MEM_DIR" update reference linear-ingest "Final description" "Bugs + incidents tracked in INGEST."
assert_contains "$(cat "$MEM_DIR/linear-ingest.md")" "Final description" "update wrote description"
assert_contains "$(cat "$MEM_DIR/linear-ingest.md")" "Bugs + incidents tracked in INGEST." "update wrote body"

# === REMOVE → .trash ===
apply_decision "$MEM_DIR" remove reference linear-ingest "" ""
assert_file_missing "$MEM_DIR/linear-ingest.md" "active file gone after remove"
TRASHED=$(ls "$MEM_DIR/.trash"/*-linear-ingest.md 2>/dev/null | wc -l | tr -d ' ')
assert_eq "$TRASHED" "1" "file moved to .trash with timestamp prefix"
COUNT=$(grep -c "linear-ingest.md" "$MEM_DIR/MEMORY.md")
assert_eq "$COUNT" "0" "index line removed"

# === REMOVE missing → no-op, no error ===
apply_decision "$MEM_DIR" remove reference ghost "" ""
TRASHED=$(ls "$MEM_DIR/.trash" | wc -l | tr -d ' ')
assert_eq "$TRASHED" "1" "no spurious .trash entry for missing remove"

rm -rf "$TMP"
finish
