#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-bootstrap-memdir:"

# shellcheck disable=SC1090
. "$LIB_PATH"

TMP=$(mktemp_home)
MEM_DIR="$TMP/.claude-work/projects/-test/memory"

# First call creates everything.
bootstrap_mem_dir "$MEM_DIR"
[ -d "$MEM_DIR" ]         && echo "  ok: dir created"                 || { echo "  FAIL: dir missing"; FAILS=$((FAILS+1)); }
[ -d "$MEM_DIR/.trash" ]  && echo "  ok: .trash created"              || { echo "  FAIL: .trash missing"; FAILS=$((FAILS+1)); }
[ -d "$MEM_DIR/.tmp" ]    && echo "  ok: .tmp created"                || { echo "  FAIL: .tmp missing"; FAILS=$((FAILS+1)); }
[ -f "$MEM_DIR/MEMORY.md" ] && echo "  ok: MEMORY.md created"         || { echo "  FAIL: MEMORY.md missing"; FAILS=$((FAILS+1)); }

CONTENTS=$(cat "$MEM_DIR/MEMORY.md")
assert_contains "$CONTENTS" "Memory index for this project" "MEMORY.md has intro"

# Second call must NOT overwrite a user-edited index.
echo "- [Existing](existing.md) — keep me" > "$MEM_DIR/MEMORY.md"
bootstrap_mem_dir "$MEM_DIR"
CONTENTS=$(cat "$MEM_DIR/MEMORY.md")
assert_contains "$CONTENTS" "keep me" "second call preserves user content"

rm -rf "$TMP"
finish
