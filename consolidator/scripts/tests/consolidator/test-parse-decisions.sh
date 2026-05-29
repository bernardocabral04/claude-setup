#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-parse-decisions:"

# shellcheck disable=SC1090
. "$LIB_PATH"

# parse_decisions <json> → echoes one TAB-delimited row per VALID decision:
#   action TAB type TAB name TAB description TAB content_b64

# Empty decisions.
OUT=$(parse_decisions '{"decisions":[]}')
assert_eq "$OUT" "" "empty decisions → empty output"

# Malformed JSON → empty (no rows), exit code non-zero.
OUT=$(parse_decisions 'not json' 2>/dev/null) || true
assert_eq "$OUT" "" "malformed JSON → empty output"

# Missing decisions key → empty.
OUT=$(parse_decisions '{"foo":"bar"}' 2>/dev/null) || true
assert_eq "$OUT" "" "no decisions key → empty"

# One valid add.
JSON='{"decisions":[{"action":"add","type":"reference","name":"linear-ingest","description":"hook","content":"body"}]}'
OUT=$(parse_decisions "$JSON")
LINES=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
assert_eq "$LINES" "1" "single valid decision → one row"
assert_contains "$OUT" "add	reference	linear-ingest	hook	" "row fields correct"

# Mixed valid + invalid (bad name).
JSON='{"decisions":[
  {"action":"add","type":"reference","name":"OK-NAME","description":"x","content":"y"},
  {"action":"add","type":"reference","name":"ok-name","description":"x","content":"y"},
  {"action":"add","type":"reference","name":"../etc","description":"x","content":"y"},
  {"action":"weird","type":"reference","name":"third","description":"x","content":"y"}
]}'
OUT=$(parse_decisions "$JSON")
LINES=$(printf '%s\n' "$OUT" | grep -c '	' || true)
assert_eq "$LINES" "1" "only the lowercase-kebab name passes validation"
assert_contains "$OUT" "ok-name" "the valid one made it"

finish
