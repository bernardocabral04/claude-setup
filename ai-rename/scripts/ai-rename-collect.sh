#!/bin/bash
# Gather inputs for /ai-rename and emit a JSON object on stdout.
# Read-only. Exits non-zero only if no session_id can be resolved.

set -e

RES=$(bash "$HOME/.claude/scripts/_resolve-session-id.sh") || exit 1
SESSION_ID=$(printf '%s' "$RES" | sed -n '1p')
CWD=$(printf '%s' "$RES" | sed -n '2p')
TRANSCRIPT=$(printf '%s' "$RES" | sed -n '3p')

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Look for the transcript in both $CLAUDE_CONFIG_DIR/projects and the
# default ~/.claude/projects (sessions started under one config dir but
# referenced from another still resolve). First try the cwd-encoded
# subfolder; if that misses, scan all project subdirs by session_id.
if [ -z "$TRANSCRIPT" ] && [ -n "$SESSION_ID" ]; then
  if [ -n "$CWD" ]; then
    ENC=$(printf '%s' "$CWD" | sed 's|/|-|g')
    for ROOT in "$CONFIG_DIR/projects" "$HOME/.claude/projects"; do
      CAND="$ROOT/$ENC/$SESSION_ID.jsonl"
      if [ -f "$CAND" ]; then TRANSCRIPT="$CAND"; break; fi
    done
  fi
  if [ -z "$TRANSCRIPT" ]; then
    for ROOT in "$CONFIG_DIR/projects" "$HOME/.claude/projects"; do
      [ -d "$ROOT" ] || continue
      for CAND in "$ROOT"/*/"$SESSION_ID.jsonl"; do
        if [ -f "$CAND" ]; then TRANSCRIPT="$CAND"; break 2; fi
      done
    done
  fi
fi

# Per-message cap (chars) and total digest cap (chars).
PER_MSG_CAP=1000
TOTAL_CAP=8000

DIGEST='{"messages":[],"total_count":0,"truncated":false}'
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  RAW=$(jq -s \
    --argjson per "$PER_MSG_CAP" \
    --argjson total "$TOTAL_CAP" '
    ([ .[]
       | select(.type == "user")
       | select(.isMeta != true)
       | ((.message.content // .content // "") as $c
          | if ($c | type) == "string" then $c
            elif ($c | type) == "array" then
              ([ $c[] | select(.type == "text") | .text ] | join("\n"))
            else "" end)
       | gsub("^[\\s]+|[\\s]+$"; "")
       | select(length > 0)
       | select(test("^<(command-message|command-name|command-args|command-stdout|command-stderr|local-command-stdout|local-command-stderr|local-command-caveat|system-reminder|task-notification|tool-use-id|user-prompt-submit-hook)") | not)
       | if length > $per then .[0:$per] + "…[truncated]" else . end
    ]) as $all
    | ($all
       | reduce .[] as $m ({acc:[], used:0};
           if .used >= $total then .
           else {acc: (.acc + [$m]), used: (.used + ($m | length))}
           end)
      ) as $limited
    | {
        messages:    $limited.acc,
        total_count: ($all | length),
        truncated:   (($limited.acc | length) < ($all | length))
      }
  ' "$TRANSCRIPT" 2>/dev/null) || RAW=""
  [ -n "$RAW" ] && DIGEST="$RAW"
fi

PROJECT=""
if [ -n "$CWD" ] && [ "$CWD" != "$HOME" ]; then
  PROJECT=$(basename "$CWD")
fi

BRANCH=""
if [ -n "$CWD" ] && command -v git >/dev/null 2>&1; then
  BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fi

jq -n \
  --arg     session_id "$SESSION_ID" \
  --arg     project    "$PROJECT" \
  --arg     branch     "$BRANCH" \
  --arg     transcript "$TRANSCRIPT" \
  --argjson digest     "$DIGEST" \
  '{
     session_id:         $session_id,
     project:            (if $project    == "" then null else $project    end),
     branch:             (if $branch     == "" then null else $branch     end),
     transcript_path:    (if $transcript == "" then null else $transcript end),
     user_message_count: $digest.total_count,
     user_messages:      $digest.messages,
     truncated:          $digest.truncated
   }'
