#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-cursor-io:"

# shellcheck disable=SC1090
. "$LIB_PATH"

TMP=$(mktemp_home)
CURSOR="$TMP/cursor"

# Missing file → all four keys default to 0.
read_cursor "$CURSOR"
assert_eq "$LAST_EVAL_OFFSET"  "0" "missing → offset 0"
assert_eq "$LAST_EVAL_AT"      "0" "missing → at 0"
assert_eq "$EVAL_COUNT"        "0" "missing → count 0"
assert_eq "$FAILED_ATTEMPTS"   "0" "missing → fails 0"

# Round trip.
write_cursor "$CURSOR" 1234 1700000000 5 2
read_cursor  "$CURSOR"
assert_eq "$LAST_EVAL_OFFSET"  "1234"       "round-trip offset"
assert_eq "$LAST_EVAL_AT"      "1700000000" "round-trip at"
assert_eq "$EVAL_COUNT"        "5"          "round-trip count"
assert_eq "$FAILED_ATTEMPTS"   "2"          "round-trip fails"

# Atomicity: write to a path whose parent dir doesn't exist → error, leave nothing behind.
write_cursor "$TMP/nonexistent/cursor" 1 1 1 1 2>/dev/null
assert_file_missing "$TMP/nonexistent/cursor" "no partial file on failure"

rm -rf "$TMP"
finish
