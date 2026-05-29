#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-encode-and-validate:"

# shellcheck disable=SC1090
. "$LIB_PATH"

# encode_cwd: replace every '/' with '-'.
assert_eq "$(encode_cwd /Users/you)" "-Users-you" "encode_cwd home dir"
assert_eq "$(encode_cwd /Users/you/Projects/foo)" "-Users-you-Projects-foo" "encode_cwd nested"
assert_eq "$(encode_cwd /)" "-" "encode_cwd root"

# validate_name: ^[a-z][a-z0-9-]{0,63}$
validate_name "user-role"      && echo "  ok: validate_name accepts kebab"           || { echo "  FAIL: kebab rejected"; FAILS=$((FAILS+1)); }
validate_name "ok"             && echo "  ok: validate_name accepts 2-char"           || { echo "  FAIL: 2-char rejected"; FAILS=$((FAILS+1)); }
! validate_name "Ok"           && echo "  ok: validate_name rejects uppercase"        || { echo "  FAIL: uppercase accepted"; FAILS=$((FAILS+1)); }
! validate_name "../etc"       && echo "  ok: validate_name rejects path traversal"   || { echo "  FAIL: traversal accepted"; FAILS=$((FAILS+1)); }
! validate_name ".hidden"      && echo "  ok: validate_name rejects leading dot"      || { echo "  FAIL: dot accepted"; FAILS=$((FAILS+1)); }
! validate_name "with space"   && echo "  ok: validate_name rejects spaces"           || { echo "  FAIL: space accepted"; FAILS=$((FAILS+1)); }
! validate_name "$(printf '%65s' x | tr ' ' a)" && echo "  ok: validate_name rejects >64 chars" || { echo "  FAIL: long name accepted"; FAILS=$((FAILS+1)); }

finish
