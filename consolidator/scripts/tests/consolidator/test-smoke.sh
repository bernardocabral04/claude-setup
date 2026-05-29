#!/usr/bin/env bash
# Smoke test — verifies the harness wires up.

. "$(dirname "$0")/lib.sh"

echo "test-smoke:"
assert_eq "ok" "ok" "assert_eq works"
assert_contains "hello world" "world" "assert_contains works"

TMP=$(mktemp_home)
[ -d "$TMP/.claude/consolidator-sessions" ] && echo "  ok: mktemp_home created session dir"
rm -rf "$TMP"

finish
