#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-engine-resolution:"

# shellcheck disable=SC1090
. "$LIB_PATH"

TMP=$(mktemp_home)
STATEFILE="$TMP/state"

# All call_llm invocations short-circuit on CONSOLIDATOR_TEST_RESPONSE
# unless we explicitly test the engine gate first.

# --- Case 1: engine=auto, no key → returns empty when no key AND no test-response ---
(
  local_fails=0
  unset OPENROUTER_API_KEY
  export CONSOLIDATOR_ENGINE=auto
  unset CONSOLIDATOR_TEST_RESPONSE
  export CONSOLIDATOR_STATEFILE="$STATEFILE"
  rm -f "$STATEFILE"
  # claude binary not on test PATH stub — should return empty
  OUT=$(PATH=/usr/bin:/bin call_llm "sys" "usr" 2>/dev/null)
  [ -z "$OUT" ] && echo "  ok: auto+nokey+noclaudebin → empty" || { echo "  FAIL: expected empty, got: $OUT"; local_fails=$((local_fails+1)); }
  [ ! -f "$STATEFILE" ] && echo "  ok: auto+nokey → no engine-error written" || { echo "  FAIL: statefile written in auto mode"; local_fails=$((local_fails+1)); }
  exit $local_fails
)
rc=$?; FAILS=$((FAILS+rc))

# --- Case 2: engine=auto + test-response → returns test response (no engine gate intervention) ---
(
  local_fails=0
  unset OPENROUTER_API_KEY
  export CONSOLIDATOR_ENGINE=auto
  export CONSOLIDATOR_TEST_RESPONSE='{"decisions":[]}'
  export CONSOLIDATOR_STATEFILE="$STATEFILE"
  rm -f "$STATEFILE"
  OUT=$(call_llm "sys" "usr")
  [ "$OUT" = '{"decisions":[]}' ] && echo "  ok: auto + test-response returns canned" || { echo "  FAIL: got: $OUT"; local_fails=$((local_fails+1)); }
  exit $local_fails
)
rc=$?; FAILS=$((FAILS+rc))

# --- Case 3: engine=openrouter, no key → empty output + statefile written ---
(
  local_fails=0
  unset OPENROUTER_API_KEY
  unset CONSOLIDATOR_TEST_RESPONSE
  export CONSOLIDATOR_ENGINE=openrouter
  export CONSOLIDATOR_STATEFILE="$STATEFILE"
  rm -f "$STATEFILE"
  OUT=$(call_llm "sys" "usr" 2>/dev/null)
  [ -z "$OUT" ] && echo "  ok: openrouter+nokey → empty output" || { echo "  FAIL: expected empty, got: $OUT"; local_fails=$((local_fails+1)); }
  [ -f "$STATEFILE" ] && grep -q "^engine-error:no-api-key$" "$STATEFILE" \
    && echo "  ok: engine-error:no-api-key written to statefile" \
    || { echo "  FAIL: statefile missing or wrong content: $(cat "$STATEFILE" 2>/dev/null)"; local_fails=$((local_fails+1)); }
  exit $local_fails
)
rc=$?; FAILS=$((FAILS+rc))

# --- Case 4: engine=openrouter, no key, no statefile env → still no-op (graceful) ---
(
  local_fails=0
  unset OPENROUTER_API_KEY CONSOLIDATOR_TEST_RESPONSE CONSOLIDATOR_STATEFILE
  export CONSOLIDATOR_ENGINE=openrouter
  OUT=$(call_llm "sys" "usr" 2>/dev/null)
  [ -z "$OUT" ] && echo "  ok: openrouter+nokey+nostatefile → empty, no crash" || { echo "  FAIL: got: $OUT"; local_fails=$((local_fails+1)); }
  exit $local_fails
)
rc=$?; FAILS=$((FAILS+rc))

# --- Case 5: engine=claude — uses claude path even if OPENROUTER_API_KEY is set ---
# We assert this by setting OPENROUTER_API_KEY to a junk value and verifying
# call_llm does NOT attempt the curl path. Easiest proxy: with claude binary
# absent from PATH AND engine=claude, output is empty (would have hit openrouter
# branch if engine=auto and produced a curl error).
(
  local_fails=0
  export OPENROUTER_API_KEY="junk-should-be-ignored"
  export CONSOLIDATOR_ENGINE=claude
  unset CONSOLIDATOR_TEST_RESPONSE
  export CONSOLIDATOR_STATEFILE="$STATEFILE"
  rm -f "$STATEFILE"
  OUT=$(PATH=/usr/bin:/bin call_llm "sys" "usr" 2>/dev/null)
  [ -z "$OUT" ] && echo "  ok: engine=claude bypasses openrouter even with key set" || { echo "  FAIL: got: $OUT"; local_fails=$((local_fails+1)); }
  [ ! -f "$STATEFILE" ] && echo "  ok: engine=claude does not write engine-error" || { echo "  FAIL: spurious statefile"; local_fails=$((local_fails+1)); }
  exit $local_fails
)
rc=$?; FAILS=$((FAILS+rc))

# --- Case 6: engine=invalid → empty, warns on stderr, no crash ---
(
  local_fails=0
  unset OPENROUTER_API_KEY CONSOLIDATOR_TEST_RESPONSE
  export CONSOLIDATOR_ENGINE=garbage
  export CONSOLIDATOR_STATEFILE="$STATEFILE"
  rm -f "$STATEFILE"
  OUT=$(call_llm "sys" "usr" 2>/dev/null)
  [ -z "$OUT" ] && echo "  ok: invalid engine → empty" || { echo "  FAIL: got: $OUT"; local_fails=$((local_fails+1)); }
  exit $local_fails
)
rc=$?; FAILS=$((FAILS+rc))

rm -rf "$TMP"
finish
