#!/usr/bin/env bash
CONF="$HOME/.claude/consolidator.conf"
LIB="$HOME/.claude/scripts/consolidator-lib.sh"
# shellcheck disable=SC1090
[ -f "$LIB" ] && . "$LIB"

TARGET_SESSION_ID="${1:-}"
if [ -n "$TARGET_SESSION_ID" ]; then
  CWD=$(bash "$HOME/.claude/scripts/_validate-session-id.sh" "$TARGET_SESSION_ID") || exit 1
  CLAUDE_SESSION_ID="$TARGET_SESSION_ID"
  CLAUDE_SESSION_CWD="$CWD"
elif [ -z "${CLAUDE_SESSION_ID:-}" ]; then
  RES=$(bash "$HOME/.claude/scripts/_resolve-session-id.sh") || {
    echo "ERROR: could not determine the current session id." >&2
    exit 1
  }
  CLAUDE_SESSION_ID=$(printf '%s' "$RES" | sed -n '1p')
  [ -z "${CLAUDE_SESSION_CWD:-}" ] && CLAUDE_SESSION_CWD=$(printf '%s' "$RES" | sed -n '2p')
fi

DIR="$HOME/.claude/consolidator-sessions"
FLAG="$DIR/$CLAUDE_SESSION_ID"
CURSOR="$DIR/$CLAUDE_SESSION_ID.cursor"
METRICS="$DIR/$CLAUDE_SESSION_ID.metrics.log"
LAST_JSON="$DIR/$CLAUDE_SESSION_ID.last.json"

if [ -f "$FLAG" ]; then
  STATE="ENABLED"
else
  STATE="disabled"
fi

echo "Consolidator state: $STATE"
echo "  Session ID: $CLAUDE_SESSION_ID"
echo "  Cwd:        ${CLAUDE_SESSION_CWD:-(unknown)}"

if [ -n "${CLAUDE_SESSION_CWD:-}" ] && command -v encode_cwd >/dev/null 2>&1; then
  ENCODED=$(encode_cwd "$CLAUDE_SESSION_CWD")
  # Co-locate with native auto-memory; profile-aware via CLAUDE_CONFIG_DIR.
  MEM_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$ENCODED/memory"
  echo "  Memory dir: $MEM_DIR"
  if [ -d "$MEM_DIR" ]; then
    ACTIVE=$(ls "$MEM_DIR"/*.md 2>/dev/null | grep -v MEMORY.md | wc -l | tr -d ' ')
    TRASHED=$(ls "$MEM_DIR/.trash"/*.md 2>/dev/null | wc -l | tr -d ' ')
    echo "  Memories:   $ACTIVE active, $TRASHED trashed"
  else
    echo "  Memories:   (no memory dir yet — will be bootstrapped on first eval)"
  fi
fi

# Cursor.
if [ -f "$CURSOR" ]; then
  # shellcheck disable=SC1090
  . "$CURSOR"
  echo ""
  echo "Cursor:"
  echo "  Offset:     $LAST_EVAL_OFFSET"
  echo "  Last eval:  $(date -r "$LAST_EVAL_AT" 2>/dev/null || echo "(invalid)")"
  echo "  Eval count: $EVAL_COUNT"
  echo "  Failed:     $FAILED_ATTEMPTS"
fi

# Conf summary.
if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF"
  # Layer session-scope overrides (mirrors consolidator-hook.sh layering).
  # shellcheck disable=SC1090
  [ -f "$FLAG" ] && . "$FLAG"
  # Honor legacy var name for display continuity (one release).
  : "${CONSOLIDATOR_CLAUDE_MODEL:=${CONSOLIDATOR_CLEAN_MODEL:-}}"
  echo ""
  echo "Config:"
  echo "  Engine:           ${CONSOLIDATOR_ENGINE:-auto}"
  echo "  OpenRouter model: ${CONSOLIDATOR_OPENROUTER_MODEL:-(default)}"
  echo "  Claude model:     ${CONSOLIDATOR_CLAUDE_MODEL:-(default)}"
  echo "  Cooldown:         ${CONSOLIDATOR_COOLDOWN_SEC:-60}s"
  echo "  Min bytes:        ${CONSOLIDATOR_MIN_NEW_BYTES:-2000}"
  echo "  Max dec/run:      ${CONSOLIDATOR_MAX_DECISIONS_PER_RUN:-3}"
fi

# Surface engine-error state if it's still fresh.
STATEFILE_PATH="$DIR/$CLAUDE_SESSION_ID.state"
if [ -f "$STATEFILE_PATH" ]; then
  STATE_CONTENT=$(cat "$STATEFILE_PATH" 2>/dev/null)
  case "$STATE_CONTENT" in
    engine-error:*)
      AGE=$(( $(date +%s) - $(stat -f %m "$STATEFILE_PATH" 2>/dev/null || echo 0) ))
      if [ "$AGE" -le 300 ]; then
        echo ""
        echo "⚠  Engine error: ${STATE_CONTENT#engine-error:} (${AGE}s ago)"
      fi
      ;;
  esac
fi

# Reachability.
echo ""
echo "Reachability:"
if [ -n "${OPENROUTER_API_KEY:-}" ]; then
  if curl -fsS --max-time 1 https://openrouter.ai/api/v1/models -o /dev/null 2>&1; then
    echo "  OpenRouter: reachable ✓"
  else
    echo "  OpenRouter: UNREACHABLE"
  fi
else
  echo "  OpenRouter: not configured (no OPENROUTER_API_KEY)"
fi
if command -v claude >/dev/null 2>&1; then
  echo "  claude -p:  reachable ✓"
else
  echo "  claude -p:  not installed"
fi

# Last LLM response.
if [ -f "$LAST_JSON" ]; then
  echo ""
  echo "Last LLM response:"
  cat "$LAST_JSON" | jq -C . 2>/dev/null || cat "$LAST_JSON"
fi

# Last 5 metrics.
if [ -f "$METRICS" ]; then
  echo ""
  echo "Latency (last 5 runs):"
  tail -5 "$METRICS" | sed 's/^/  /'
fi
