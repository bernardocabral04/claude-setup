#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-config-flags:"

IMPL="$HOME/.claude/scripts/consolidator-config-impl.sh"

TMP=$(mktemp_home)
export HOME="$TMP"
mkdir -p "$TMP/.claude/consolidator-sessions"
SID="flags-test-session"
touch "$TMP/.claude/consolidator-sessions/$SID"
SESS_CONF="$TMP/.claude/consolidator-sessions/$SID"
GLOBAL_CONF="$TMP/.claude/consolidator.conf"

# We invoke the impl with --session <id> to avoid _resolve-session-id dependency.

# --- Case 1: single named flag, session scope (default) ---
bash "$IMPL" --session "$SID" --engine claude > /dev/null
grep -qE '^CONSOLIDATOR_ENGINE=claude$' "$SESS_CONF" && echo "  ok: --engine writes to session conf" || { echo "  FAIL"; FAILS=$((FAILS+1)); }

# --- Case 2: multiple named flags in one call ---
bash "$IMPL" --session "$SID" --engine openrouter --openrouter-model openai/gpt-4o --claude-model sonnet > /dev/null
grep -qE '^CONSOLIDATOR_ENGINE=openrouter$' "$SESS_CONF" && echo "  ok: engine set" || { echo "  FAIL: engine"; FAILS=$((FAILS+1)); }
grep -qE '^CONSOLIDATOR_OPENROUTER_MODEL=openai/gpt-4o$' "$SESS_CONF" && echo "  ok: openrouter-model set" || { echo "  FAIL: openrouter-model"; FAILS=$((FAILS+1)); }
grep -qE '^CONSOLIDATOR_CLAUDE_MODEL=sonnet$' "$SESS_CONF" && echo "  ok: claude-model set" || { echo "  FAIL: claude-model"; FAILS=$((FAILS+1)); }

# --- Case 3: --global flag writes to global conf ---
bash "$IMPL" --global --engine claude > /dev/null
grep -qE '^CONSOLIDATOR_ENGINE=claude$' "$GLOBAL_CONF" && echo "  ok: --global --engine writes to global conf" || { echo "  FAIL"; FAILS=$((FAILS+1)); }

# --- Case 4: mixing named flag with positional key is rejected ---
OUT=$(bash "$IMPL" --session "$SID" --engine claude min_new_bytes 5000 2>&1; echo "RC=$?")
echo "$OUT" | grep -qE 'cannot be combined|cannot mix' && echo "  ok: mixed flag+positional rejected" || { echo "  FAIL: mixed accepted"; FAILS=$((FAILS+1)); }
echo "$OUT" | grep -qE 'RC=1$' && echo "  ok: exit code 1 on mixed" || { echo "  FAIL: wrong exit code"; FAILS=$((FAILS+1)); }

# --- Case 5: invalid engine value rejected ---
OUT=$(bash "$IMPL" --session "$SID" --engine bogus 2>&1; echo "RC=$?")
echo "$OUT" | grep -qE 'invalid|allowed values' && echo "  ok: invalid engine rejected" || { echo "  FAIL"; FAILS=$((FAILS+1)); }
echo "$OUT" | grep -qE 'RC=1$' && echo "  ok: exit 1 on invalid engine" || { echo "  FAIL: wrong exit"; FAILS=$((FAILS+1)); }

# --- Case 6: unknown named flag rejected ---
OUT=$(bash "$IMPL" --session "$SID" --unknown foo 2>&1; echo "RC=$?")
echo "$OUT" | grep -qE 'unknown|unrecognized' && echo "  ok: unknown flag rejected" || { echo "  FAIL"; FAILS=$((FAILS+1)); }
echo "$OUT" | grep -qE 'RC=1$' && echo "  ok: exit 1 on unknown flag" || { echo "  FAIL: wrong exit code"; FAILS=$((FAILS+1)); }

# --- Case 7: legacy 'model' positional key triggers hint ---
OUT=$(bash "$IMPL" --session "$SID" model openai/gpt-4o 2>&1; echo "RC=$?")
echo "$OUT" | grep -qE "did you mean 'openrouter-model'" && echo "  ok: legacy 'model' shows hint" || { echo "  FAIL: no hint"; FAILS=$((FAILS+1)); }
echo "$OUT" | grep -qE 'RC=1$' && echo "  ok: exit 1 on legacy key" || { echo "  FAIL: wrong exit"; FAILS=$((FAILS+1)); }

# --- Case 8: integer key validation — negative rejected ---
OUT=$(bash "$IMPL" --session "$SID" cooldown_sec -1 2>&1; echo "RC=$?")
echo "$OUT" | grep -qE 'integer|negative|positive' && echo "  ok: negative integer rejected" || { echo "  FAIL"; FAILS=$((FAILS+1)); }

# --- Case 9: integer key validation — non-numeric rejected ---
OUT=$(bash "$IMPL" --session "$SID" cooldown_sec foo 2>&1; echo "RC=$?")
echo "$OUT" | grep -qE 'integer' && echo "  ok: non-numeric integer rejected" || { echo "  FAIL"; FAILS=$((FAILS+1)); }

rm -rf "$TMP"
finish
