#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

echo "test-config-rename:"

# shellcheck disable=SC1090
. "$LIB_PATH"

TMP=$(mktemp_home)

# --- Case 1: rename when only legacy key present ---
CONF1="$TMP/conf1"
cat > "$CONF1" <<'EOF'
CONSOLIDATOR_OPENROUTER_MODEL=openai/gpt-4o-mini
CONSOLIDATOR_CLEAN_MODEL=haiku
CONSOLIDATOR_COOLDOWN_SEC=60
EOF
COUNT=$(migrate_legacy_conf "$CONF1")
assert_eq "$COUNT" "1" "case 1: 1 key migrated"
! grep -qE '^CONSOLIDATOR_CLEAN_MODEL=' "$CONF1" && echo "  ok: legacy key removed" || { echo "  FAIL: legacy still present"; FAILS=$((FAILS+1)); }
grep -qE '^CONSOLIDATOR_CLAUDE_MODEL=haiku$' "$CONF1" && echo "  ok: new key written with preserved value" || { echo "  FAIL: new key missing or wrong value"; FAILS=$((FAILS+1)); }
grep -qE '^CONSOLIDATOR_COOLDOWN_SEC=60$' "$CONF1" && echo "  ok: unrelated keys preserved" || { echo "  FAIL: unrelated key lost"; FAILS=$((FAILS+1)); }

# --- Case 1b: value containing '/' migrates cleanly (regression for sed delimiter) ---
CONF1B="$TMP/conf1b"
cat > "$CONF1B" <<'EOF'
CONSOLIDATOR_CLEAN_MODEL=anthropic/claude-haiku-4-5
EOF
COUNT=$(migrate_legacy_conf "$CONF1B")
assert_eq "$COUNT" "1" "case 1b: value with '/' — 1 key migrated"
grep -qE '^CONSOLIDATOR_CLAUDE_MODEL=anthropic/claude-haiku-4-5$' "$CONF1B" \
  && echo "  ok: value with '/' preserved" \
  || { echo "  FAIL: value corrupted: $(grep CLAUDE_MODEL "$CONF1B")"; FAILS=$((FAILS+1)); }
! grep -qE '^CONSOLIDATOR_CLEAN_MODEL=' "$CONF1B" && echo "  ok: legacy key removed" || { echo "  FAIL: legacy still present"; FAILS=$((FAILS+1)); }

# --- Case 2: both present → new wins, legacy dropped ---
CONF2="$TMP/conf2"
cat > "$CONF2" <<'EOF'
CONSOLIDATOR_CLEAN_MODEL=haiku
CONSOLIDATOR_CLAUDE_MODEL=sonnet
EOF
COUNT=$(migrate_legacy_conf "$CONF2")
assert_eq "$COUNT" "1" "case 2: 1 key migrated (legacy dropped)"
! grep -qE '^CONSOLIDATOR_CLEAN_MODEL=' "$CONF2" && echo "  ok: legacy dropped on conflict" || { echo "  FAIL: legacy still present"; FAILS=$((FAILS+1)); }
grep -qE '^CONSOLIDATOR_CLAUDE_MODEL=sonnet$' "$CONF2" && echo "  ok: new value preserved on conflict" || { echo "  FAIL: new value lost"; FAILS=$((FAILS+1)); }

# --- Case 3: no legacy keys → no-op, count=0 ---
CONF3="$TMP/conf3"
cat > "$CONF3" <<'EOF'
CONSOLIDATOR_CLAUDE_MODEL=haiku
CONSOLIDATOR_OPENROUTER_MODEL=openai/gpt-4o-mini
EOF
BEFORE=$(cat "$CONF3")
COUNT=$(migrate_legacy_conf "$CONF3")
assert_eq "$COUNT" "0" "case 3: 0 keys migrated (no legacy)"
AFTER=$(cat "$CONF3")
assert_eq "$BEFORE" "$AFTER" "case 3: file untouched on no-op"

# --- Case 4: idempotence — second pass on already-migrated file is no-op ---
COUNT=$(migrate_legacy_conf "$CONF1")
assert_eq "$COUNT" "0" "case 4: second pass migrates 0 keys"

# --- Case 5: missing file → no-op, count=0 ---
COUNT=$(migrate_legacy_conf "$TMP/nonexistent")
assert_eq "$COUNT" "0" "case 5: missing file = 0 keys"

rm -rf "$TMP"
finish
