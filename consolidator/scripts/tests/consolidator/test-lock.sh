#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-lock:"

# shellcheck disable=SC1090
. "$LIB_PATH"

TMP=$(mktemp_home)
DIR="$TMP/memory"
mkdir -p "$DIR"

# First acquire succeeds.
acquire_lock "$DIR/.lock" 1 && echo "  ok: first acquire" || { echo "  FAIL: first acquire"; FAILS=$((FAILS+1)); }

# Second (no release) times out fast.
START=$(date +%s)
acquire_lock "$DIR/.lock" 1 2>/dev/null && { echo "  FAIL: second acquire should timeout"; FAILS=$((FAILS+1)); } || echo "  ok: second acquire timed out"
END=$(date +%s)
[ $((END - START)) -le 2 ] && echo "  ok: timeout was bounded" || { echo "  FAIL: timeout took too long: $((END-START))s"; FAILS=$((FAILS+1)); }

# Release + reacquire.
release_lock "$DIR/.lock"
acquire_lock "$DIR/.lock" 1 && echo "  ok: reacquire after release" || { echo "  FAIL: reacquire"; FAILS=$((FAILS+1)); }
release_lock "$DIR/.lock"

# Stale lock recovery: lock dir older than 5 min should be force-removed.
mkdir "$DIR/.lock"
# Set mtime to 10 minutes ago.
touch -t "$(date -v -10M +%Y%m%d%H%M.%S 2>/dev/null || date -d '-10 minutes' +%Y%m%d%H%M.%S)" "$DIR/.lock"
acquire_lock "$DIR/.lock" 1 && echo "  ok: stale lock force-removed" || { echo "  FAIL: stale lock not recovered"; FAILS=$((FAILS+1)); }
release_lock "$DIR/.lock"

rm -rf "$TMP"
finish
