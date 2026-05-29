#!/usr/bin/env bash
# Discover and run all test-*.sh in this directory.

set -u
cd "$(dirname "$0")"

total=0
failed=0
for t in test-*.sh; do
  [ -e "$t" ] || continue
  total=$((total + 1))
  echo "==> $t"
  if bash "$t"; then
    :
  else
    failed=$((failed + 1))
  fi
done

echo
echo "Ran $total test files; $failed failed"
[ "$failed" -eq 0 ]
