#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-enabled-types-filter:"

# shellcheck disable=SC1090
. "$LIB_PATH"

TMP=$(mktemp_home)
MEM_DIR="$TMP/.claude-work/projects/-test/memory"
bootstrap_mem_dir "$MEM_DIR"

# Plant the enabled types restriction.
export CONSOLIDATOR_ENABLED_TYPES="user,feedback"

# Submit 4 decisions — one per type.
JSON='{"decisions":[
  {"action":"add","type":"user","name":"user-role","description":"Go expert","content":"Ten years of Go."},
  {"action":"add","type":"feedback","name":"fb-prs","description":"PR style","content":"Bundle PRs.\n\n**Why:** Churn.\n\n**How to apply:** Bundle."},
  {"action":"add","type":"project","name":"proj-freeze","description":"merge freeze","content":"Freeze 2026-06-01.\n\n**Why:** Release.\n\n**How to apply:** No merges."},
  {"action":"add","type":"reference","name":"ref-grafana","description":"latency dash","content":"grafana.internal/d/api-latency"}
]}'

ROWS=$(parse_decisions "$JSON" 2>/dev/null)
WARNINGS=$(parse_decisions "$JSON" 2>&1 >/dev/null)

# Apply only the rows that passed the filter.
if [ -n "$ROWS" ]; then
  while IFS=$'\t' read -r action type name description content_b64; do
    [ -z "$action" ] && continue
    content=$(printf '%s' "$content_b64" | base64 -D 2>/dev/null)
    apply_decision "$MEM_DIR" "$action" "$type" "$name" "$description" "$content"
  done <<< "$ROWS"
fi

# user and feedback should be on disk.
assert_file_exists "$MEM_DIR/user-role.md" "user type accepted when enabled"
assert_file_exists "$MEM_DIR/fb-prs.md" "feedback type accepted when enabled"

# project and reference should be absent.
assert_file_missing "$MEM_DIR/proj-freeze.md" "project type blocked when disabled"
assert_file_missing "$MEM_DIR/ref-grafana.md" "reference type blocked when disabled"

# Warnings should mention the skipped types.
assert_contains "$WARNINGS" "project" "warning mentions skipped project type"
assert_contains "$WARNINGS" "reference" "warning mentions skipped reference type"
assert_contains "$WARNINGS" "disabled" "warning uses 'disabled' keyword"

# Unset so subsequent tests are not affected.
unset CONSOLIDATOR_ENABLED_TYPES

rm -rf "$TMP"
finish
