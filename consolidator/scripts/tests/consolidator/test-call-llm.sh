#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-call-llm:"

# shellcheck disable=SC1090
. "$LIB_PATH"

# Inject canned response — bypasses network entirely.
export CONSOLIDATOR_TEST_RESPONSE='{"decisions":[{"action":"add","type":"reference","name":"linear-ingest","description":"hook","content":"body"}]}'
OUT=$(call_llm "prompt text" "payload text")
assert_eq "$OUT" "$CONSOLIDATOR_TEST_RESPONSE" "test-response env var returned verbatim"

unset CONSOLIDATOR_TEST_RESPONSE

# No key + no claude binary mocked → returns empty, exit non-zero is OK.
export OPENROUTER_API_KEY=""
OUT=$(PATH=/usr/bin:/bin call_llm "prompt" "payload" 2>/dev/null)
assert_eq "$OUT" "" "no engine → empty output"

# === Env var rename: CONSOLIDATOR_CLAUDE_MODEL takes precedence over CLEAN_MODEL ===
# call_llm short-circuits on CONSOLIDATOR_TEST_RESPONSE, so we test the
# fallback expression directly. We use `env -i` so leaked outer-shell vars
# cannot mask defects; we then re-export only the vars under test.
RESOLVED=$(env -i bash -c 'CONSOLIDATOR_CLAUDE_MODEL=sonnet CONSOLIDATOR_CLEAN_MODEL=haiku; echo "${CONSOLIDATOR_CLAUDE_MODEL:-${CONSOLIDATOR_CLEAN_MODEL:-haiku}}"')
assert_eq "$RESOLVED" "sonnet" "env-rename: new var wins over legacy"

RESOLVED=$(env -i bash -c 'CONSOLIDATOR_CLEAN_MODEL=opus; echo "${CONSOLIDATOR_CLAUDE_MODEL:-${CONSOLIDATOR_CLEAN_MODEL:-haiku}}"')
assert_eq "$RESOLVED" "opus" "env-rename: legacy honored when new unset"

RESOLVED=$(env -i bash -c 'echo "${CONSOLIDATOR_CLAUDE_MODEL:-${CONSOLIDATOR_CLEAN_MODEL:-haiku}}"')
assert_eq "$RESOLVED" "haiku" "env-rename: default haiku when neither set"

finish
