#!/usr/bin/env bash
set -e

CONF="$HOME/.claude/consolidator.conf"
LIB="$HOME/.claude/scripts/consolidator-lib.sh"
# shellcheck disable=SC1090
. "$LIB"

# Migrate legacy key names in global conf and every session flag file.
TOTAL_MIGRATED=0
if [ -f "$CONF" ]; then
  N=$(migrate_legacy_conf "$CONF")
  TOTAL_MIGRATED=$((TOTAL_MIGRATED + N))
fi
if [ -d "$HOME/.claude/consolidator-sessions" ]; then
  for f in "$HOME/.claude/consolidator-sessions"/*; do
    # Skip non-flag files (.cursor, .state, .metrics.log, .debug.log, .last.json).
    case "$f" in
      *.cursor|*.state|*.metrics.log|*.debug.log|*.last.json|*.tmp.*) continue ;;
    esac
    [ -f "$f" ] || continue
    N=$(migrate_legacy_conf "$f")
    TOTAL_MIGRATED=$((TOTAL_MIGRATED + N))
  done
fi
if [ "$TOTAL_MIGRATED" -gt 0 ]; then
  echo "Migrated $TOTAL_MIGRATED legacy config key(s)."
fi

if [ ! -f "$CONF" ]; then
  cat > "$CONF" <<'EOF'
# Consolidator config — created by /consolidator-enable on first run.

# Eval engine. Values: auto | openrouter | claude
# - auto       — use OpenRouter if OPENROUTER_API_KEY is set, else claude -p
# - openrouter — strict OpenRouter; error if API key missing (statusline shows ⚠)
# - claude     — force claude -p; ignore OPENROUTER_API_KEY entirely
CONSOLIDATOR_ENGINE=auto

# Model selection.
# OPENROUTER_API_KEY is intentionally NOT set here; uncomment to override env.
# OPENROUTER_API_KEY=sk-or-v1-...
CONSOLIDATOR_OPENROUTER_MODEL=openai/gpt-4o-mini
CONSOLIDATOR_CLAUDE_MODEL=haiku

# Gating thresholds (cheap pre-checks before any LLM call).
CONSOLIDATOR_COOLDOWN_SEC=60
CONSOLIDATOR_MIN_NEW_BYTES=2000

# Eval shape.
CONSOLIDATOR_MAX_DECISIONS_PER_RUN=3
CONSOLIDATOR_ENABLED_TYPES=user,feedback,project,reference

# Safety.
CONSOLIDATOR_MAX_FAILED_ATTEMPTS=3
EOF
  chmod 600 "$CONF"
  echo "Created $CONF with defaults."
fi

# Resolve session id.
TARGET_SESSION_ID="${1:-}"
if [ -n "$TARGET_SESSION_ID" ]; then
  CWD=$(bash "$HOME/.claude/scripts/_validate-session-id.sh" "$TARGET_SESSION_ID") || exit 1
  CLAUDE_SESSION_ID="$TARGET_SESSION_ID"
  CLAUDE_SESSION_CWD="$CWD"
  SCOPE_LABEL="target session $TARGET_SESSION_ID"
elif [ -z "${CLAUDE_SESSION_ID:-}" ]; then
  RES=$(bash "$HOME/.claude/scripts/_resolve-session-id.sh") || {
    echo "ERROR: could not determine the current session id." >&2
    exit 1
  }
  CLAUDE_SESSION_ID=$(printf '%s' "$RES" | sed -n '1p')
  [ -z "${CLAUDE_SESSION_CWD:-}" ] && CLAUDE_SESSION_CWD=$(printf '%s' "$RES" | sed -n '2p')
  SCOPE_LABEL="this session"
else
  SCOPE_LABEL="this session"
fi

mkdir -p "$HOME/.claude/consolidator-sessions"
touch "$HOME/.claude/consolidator-sessions/$CLAUDE_SESSION_ID"

# Bootstrap memory dir.
ENCODED=$(encode_cwd "${CLAUDE_SESSION_CWD:-$PWD}")
# Co-locate with native auto-memory; profile-aware via CLAUDE_CONFIG_DIR.
MEM_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$ENCODED/memory"
bootstrap_mem_dir "$MEM_DIR"

# shellcheck disable=SC1090
. "$CONF"

if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  ENGINE="OpenRouter ($CONSOLIDATOR_OPENROUTER_MODEL)"
else
  ENGINE="claude -p (${CONSOLIDATOR_CLAUDE_MODEL:-${CONSOLIDATOR_CLEAN_MODEL:-haiku}})  ← slow; set OPENROUTER_API_KEY for fast path"
fi

ACTIVE_COUNT=$(ls "$MEM_DIR"/*.md 2>/dev/null | grep -v MEMORY.md | wc -l | tr -d ' ' 2>/dev/null || echo 0)
TRASH_COUNT=$(ls "$MEM_DIR/.trash"/*.md 2>/dev/null | wc -l | tr -d ' ' 2>/dev/null || echo 0)

echo ""
echo "Consolidator enabled for $SCOPE_LABEL."
echo "  Session ID:  $CLAUDE_SESSION_ID"
echo "  Memory dir:  $MEM_DIR"
echo "  Active mems: $ACTIVE_COUNT"
echo "  Trashed:     $TRASH_COUNT"
echo "  Engine:      $ENGINE"
echo "  Cooldown:    ${CONSOLIDATOR_COOLDOWN_SEC}s · min bytes: $CONSOLIDATOR_MIN_NEW_BYTES"
echo ""
echo "It will run after each Stop event, debounced. Use /consolidator-now to force an eval."
