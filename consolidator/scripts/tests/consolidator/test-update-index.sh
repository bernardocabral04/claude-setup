#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-update-index:"

# shellcheck disable=SC1090
. "$LIB_PATH"

TMP=$(mktemp_home)
MD="$TMP/MEMORY.md"
cat > "$MD" <<'EOF'
# Memory index

EOF

# Add a fresh entry.
update_index "$MD" "user-role" "- [User Role](user-role.md) — data scientist focused on logging"
CONTENTS=$(cat "$MD")
assert_contains "$CONTENTS" "[User Role](user-role.md)" "add appended new line"

# Re-add the same name should replace.
update_index "$MD" "user-role" "- [User Role](user-role.md) — UPDATED hook text"
COUNT=$(grep -c "user-role.md" "$MD")
assert_eq "$COUNT" "1" "second add replaces, no duplicate"
assert_contains "$(cat "$MD")" "UPDATED hook text" "line content replaced"

# Remove (empty new_line).
update_index "$MD" "user-role" ""
COUNT=$(grep -c "user-role.md" "$MD")
assert_eq "$COUNT" "0" "remove drops the line"

# Operating on a name that isn't present + empty line = no-op.
BEFORE=$(cat "$MD")
update_index "$MD" "ghost" ""
AFTER=$(cat "$MD")
assert_eq "$BEFORE" "$AFTER" "remove missing = no-op"

rm -rf "$TMP"
finish
