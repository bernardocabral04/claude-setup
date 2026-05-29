#!/usr/bin/env bash
# Shared test helpers for consolidator/ tests.

set -u

LIB_PATH="${LIB_PATH:-$HOME/.claude/scripts/consolidator-lib.sh}"
FAILS=0

assert_eq() {
  # $1=actual $2=expected $3=msg
  if [ "$1" = "$2" ]; then
    echo "  ok: $3"
  else
    echo "  FAIL: $3"
    echo "       actual:   $1"
    echo "       expected: $2"
    FAILS=$((FAILS + 1))
  fi
}

assert_ne() {
  # $1=a $2=b $3=msg
  if [ "$1" != "$2" ]; then
    echo "  ok: $3"
  else
    echo "  FAIL: $3 (expected '$1' != '$2')"
    FAILS=$((FAILS + 1))
  fi
}

assert_contains() {
  # $1=haystack $2=needle $3=msg
  case "$1" in
    *"$2"*) echo "  ok: $3" ;;
    *)
      echo "  FAIL: $3"
      echo "       haystack: $1"
      echo "       needle:   $2"
      FAILS=$((FAILS + 1))
      ;;
  esac
}

assert_file_exists() {
  # $1=path $2=msg
  if [ -f "$1" ]; then
    echo "  ok: $2"
  else
    echo "  FAIL: $2 (missing: $1)"
    FAILS=$((FAILS + 1))
  fi
}

assert_file_missing() {
  if [ ! -e "$1" ]; then
    echo "  ok: $2"
  else
    echo "  FAIL: $2 (exists: $1)"
    FAILS=$((FAILS + 1))
  fi
}

# Make a throwaway $HOME so tests don't pollute the real config.
# Echoes the path; caller exports HOME=$(mktemp_home).
mktemp_home() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/.claude/consolidator-sessions" \
           "$tmp/.claude-work/projects"
  echo "$tmp"
}

finish() {
  if [ "$FAILS" -gt 0 ]; then
    echo "  $FAILS failure(s)"
    exit 1
  fi
  echo "  all passed"
  exit 0
}
