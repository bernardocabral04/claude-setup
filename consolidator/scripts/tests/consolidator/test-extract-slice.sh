#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-extract-slice:"

# shellcheck disable=SC1090
. "$LIB_PATH"

FIX="$(dirname "$0")/fixtures"

# Empty: only system + tool_use → no text emitted.
OUT=$(extract_slice "$FIX/empty.jsonl" 0)
assert_eq "$OUT" "" "empty fixture yields nothing"

# Whole file from offset 0.
OUT=$(extract_slice "$FIX/single-fact.jsonl" 0)
assert_contains "$OUT" "USER: We track all pipeline bugs in Linear project INGEST." "user line emitted"
assert_contains "$OUT" "ASSISTANT: Got it — noted for routing." "assistant text emitted"
assert_contains "$OUT" "ASSISTANT: Confirmed." "second assistant text emitted"

# Thinking blocks must NOT leak.
case "$OUT" in
  *hidden*) echo "  FAIL: thinking content leaked"; FAILS=$((FAILS+1));;
  *)        echo "  ok: thinking content filtered" ;;
esac

# tool_use lines must NOT produce output.
case "$OUT" in
  *tool_use*) echo "  FAIL: tool_use leaked"; FAILS=$((FAILS+1));;
  *bash*)     echo "  FAIL: bash leaked";     FAILS=$((FAILS+1));;
  *)          echo "  ok: tool_use filtered" ;;
esac

# Mid-line offset: pick a byte offset inside the first line.
SIZE=$(stat -f %z "$FIX/single-fact.jsonl")
HALF=$((SIZE / 8))
OUT=$(extract_slice "$FIX/single-fact.jsonl" "$HALF")
case "$OUT" in
  *INGEST*) echo "  FAIL: mid-line offset consumed first line as partial JSON" ; FAILS=$((FAILS+1));;
  *)        echo "  ok: mid-line offset advanced to next newline" ;;
esac

finish
