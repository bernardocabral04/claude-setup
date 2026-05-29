#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-body-structure-warn:"

# shellcheck disable=SC1090
. "$LIB_PATH"

# --- Case 1: feedback with BOTH markers → no warning ---
JSON='{"decisions":[{"action":"add","type":"feedback","name":"pr-style","description":"PR bundling preference","content":"Prefer one PR per refactor area.\n\n**Why:** User said splitting is churn.\n\n**How to apply:** Bundle related changes."}]}'
WARN=$(parse_decisions "$JSON" 2>&1 >/dev/null)
assert_eq "$WARN" "" "feedback with both markers → no warning"

# --- Case 2: feedback missing **How to apply:** → warning on stderr ---
JSON='{"decisions":[{"action":"add","type":"feedback","name":"pr-style-bad","description":"PR bundling preference","content":"Prefer one PR per refactor area.\n\n**Why:** User said splitting is churn."}]}'
WARN=$(parse_decisions "$JSON" 2>&1 >/dev/null)
assert_contains "$WARN" "warning" "feedback missing How to apply → warning emitted"
assert_contains "$WARN" "pr-style-bad" "warning names the offending slug"

# --- Case 3: feedback missing **Why:** → warning on stderr ---
JSON='{"decisions":[{"action":"add","type":"feedback","name":"pr-style-nowhy","description":"PR bundling preference","content":"Prefer one PR per refactor area.\n\n**How to apply:** Bundle related changes."}]}'
WARN=$(parse_decisions "$JSON" 2>&1 >/dev/null)
assert_contains "$WARN" "warning" "feedback missing Why → warning emitted"

# --- Case 4: user type missing markers → NO warning ---
JSON='{"decisions":[{"action":"add","type":"user","name":"user-role","description":"user role","content":"Senior Go engineer."}]}'
WARN=$(parse_decisions "$JSON" 2>&1 >/dev/null)
assert_eq "$WARN" "" "user type without markers → no warning"

# --- Case 5: reference type missing markers → NO warning ---
JSON='{"decisions":[{"action":"add","type":"reference","name":"grafana-dash","description":"latency dashboard","content":"grafana.internal/d/api-latency"}]}'
WARN=$(parse_decisions "$JSON" 2>&1 >/dev/null)
assert_eq "$WARN" "" "reference type without markers → no warning"

# --- Case 6: project type missing markers → warning ---
JSON='{"decisions":[{"action":"add","type":"project","name":"merge-freeze","description":"merge freeze date","content":"Merge freeze begins 2026-06-01."}]}'
WARN=$(parse_decisions "$JSON" 2>&1 >/dev/null)
assert_contains "$WARN" "warning" "project type without markers → warning emitted"

finish
