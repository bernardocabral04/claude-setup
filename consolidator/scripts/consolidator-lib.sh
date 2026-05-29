#!/usr/bin/env bash
# consolidator-lib.sh — shared functions for the consolidator add-on.
# Sourced by consolidator-hook.sh and by tests.
# NEVER executed directly.

# Replace every '/' in $1 with '-'. Used to derive the memory-dir name
# from an absolute cwd path (matches existing convention at
# ~/.claude-work/projects/-Users-you).
encode_cwd() {
  printf '%s' "${1//\//-}"
}

# Return 0 if $1 is a valid memory slug:
#   - starts with lowercase letter
#   - only lowercase letters, digits, hyphens
#   - 1..64 chars total
# Returns 1 otherwise. Empty string returns 1.
validate_name() {
  # LC_ALL=C forces byte-order collation so [a-z] matches only a-z
  # (in en_US.UTF-8 dictionary collation [a-z] also matches uppercase).
  local LC_ALL=C
  local name="${1-}"
  [ -z "$name" ] && return 1
  [ ${#name} -gt 64 ] && return 1
  case "$name" in
    [a-z]*) ;;
    *) return 1 ;;
  esac
  case "$name" in
    *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

# Read cursor file into globals LAST_EVAL_OFFSET, LAST_EVAL_AT, EVAL_COUNT,
# FAILED_ATTEMPTS. Missing file or missing keys default to 0.
read_cursor() {
  local file="${1-}"
  LAST_EVAL_OFFSET=0
  LAST_EVAL_AT=0
  EVAL_COUNT=0
  FAILED_ATTEMPTS=0
  [ -f "$file" ] || return 0
  # shellcheck disable=SC1090
  . "$file"
  # Guarantee numeric defaults if the file had an unexpected key set to empty.
  : "${LAST_EVAL_OFFSET:=0}"
  : "${LAST_EVAL_AT:=0}"
  : "${EVAL_COUNT:=0}"
  : "${FAILED_ATTEMPTS:=0}"
}

# Write cursor atomically: tmp + mv.
# Usage: write_cursor <file> <offset> <at> <count> <fails>
write_cursor() {
  local file="$1" offset="$2" at="$3" count="$4" fails="$5"
  local dir tmp
  dir=$(dirname "$file")
  [ -d "$dir" ] || return 1
  tmp="$file.tmp.$$"
  {
    echo "LAST_EVAL_OFFSET=$offset"
    echo "LAST_EVAL_AT=$at"
    echo "EVAL_COUNT=$count"
    echo "FAILED_ATTEMPTS=$fails"
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$file"
}

# Ensure memory dir + subdirs + MEMORY.md exist.
# Idempotent: never overwrites an existing MEMORY.md.
bootstrap_mem_dir() {
  local dir="$1"
  mkdir -p "$dir" "$dir/.trash" "$dir/.tmp"
  if [ ! -f "$dir/MEMORY.md" ]; then
    cat > "$dir/MEMORY.md" <<'EOF'
# Memory index for this project

This file is maintained by the consolidator add-on. Entries are auto-generated
from session transcripts. You can edit by hand; the consolidator will respect
your edits and only add/update/remove based on conversation content.

EOF
  fi
}

# Add / update / remove an index line in MEMORY.md.
# - file:     path to MEMORY.md
# - name:     memory slug (must already pass validate_name)
# - new_line: the full markdown line to write; empty string = remove.
# Atomic: writes tmp + mv.
update_index() {
  local file="$1" name="$2" new_line="$3"
  local tmp="$file.tmp.$$"
  awk -v name="$name" -v line="$new_line" '
    $0 ~ "\\(" name "\\.md\\)" { if (line != "") print line; next }
    { print }
  ' "$file" > "$tmp"
  # If name was not in original AND we have a non-empty line: append.
  if ! grep -qE "\($name\.md\)" "$file" 2>/dev/null && [ -n "$new_line" ]; then
    echo "$new_line" >> "$tmp"
  fi
  # Fix 3b: truncate MEMORY.md to ≤200 lines; preserve header, keep newest entries.
  local line_count
  line_count=$(wc -l < "$tmp")
  if [ "$line_count" -gt 200 ]; then
    local tmp2="$tmp.trunc.$$"
    head -1 "$tmp" > "$tmp2"
    tail -n 199 "$tmp" >> "$tmp2"
    mv "$tmp2" "$tmp"
  fi
  mv "$tmp" "$file"
}

# title_case "kebab-name" -> "Kebab Name". Pure display.
title_case() {
  printf '%s' "$1" | awk -F- '{
    out=""
    for (i=1; i<=NF; i++) {
      w=$i
      if (length(w) > 0) {
        w=toupper(substr(w,1,1)) tolower(substr(w,2))
      }
      out = (i==1 ? w : out " " w)
    }
    print out
  }'
}

# Write a memory file body with frontmatter.
# Args: file type name description content
_render_memory() {
  local file="$1" type="$2" name="$3" description="$4" content="$5"
  # YAML-safe double-quoted description.
  local desc_q
  desc_q=$(printf '%s' "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')
  cat > "$file" <<EOF
---
name: $name
description: "$desc_q"
metadata:
  node_type: memory
  type: $type
EOF
  # Include originSessionId when caller exported one (hook does).
  if [ -n "${CONSOLIDATOR_SESSION_ID:-}" ]; then
    printf '  originSessionId: %s\n' "$CONSOLIDATOR_SESSION_ID" >> "$file"
  fi
  cat >> "$file" <<EOF
---

$content
EOF
}

# Apply a single decision against $MEM_DIR.
# Args: mem_dir action type name description content
# Logs warnings to stderr; returns 0 on success, 1 on hard failure.
# Auto-downgrade: add-on-existing -> update; update-on-missing -> add;
#                 remove-on-missing -> warn + skip.
apply_decision() {
  local mem_dir="$1" action="$2" type="$3" name="$4" description="$5" content="$6"
  local file="$mem_dir/$name.md"
  local md="$mem_dir/MEMORY.md"
  local title; title=$(title_case "$name")
  local line="- [$title]($name.md) — $description"
  # Fix 3a: truncate so the final index line is ≤150 chars.
  if [ "${#line}" -gt 150 ]; then
    local prefix_len=$(( ${#line} - ${#description} ))
    local room=$(( 150 - prefix_len - 1 ))  # -1 for ellipsis char
    description="${description:0:$room}…"
    line="- [$title]($name.md) — $description"
  fi

  case "$action" in
    add)
      if [ -f "$file" ]; then
        echo "consolidator: downgrade add->update for existing $name" >&2
        action=update
      fi
      ;;
    update)
      if [ ! -f "$file" ]; then
        echo "consolidator: downgrade update->add for missing $name" >&2
        action=add
      fi
      ;;
    remove)
      if [ ! -f "$file" ]; then
        echo "consolidator: skip remove for missing $name" >&2
        return 0
      fi
      ;;
    *)
      echo "consolidator: unknown action '$action'" >&2
      return 1
      ;;
  esac

  case "$action" in
    add|update)
      local tmp="$mem_dir/.tmp/$name.md.$$"
      _render_memory "$tmp" "$type" "$name" "$description" "$content"
      mv "$tmp" "$file"
      update_index "$md" "$name" "$line"
      ;;
    remove)
      local ts; ts=$(date -u +%Y-%m-%dT%H%M%SZ)
      mv "$file" "$mem_dir/.trash/$ts-$name.md"
      update_index "$md" "$name" ""
      ;;
  esac
  return 0
}

# Slice the transcript JSONL between the given byte offset and EOF.
# Emits a plain-text turn-by-turn block — only role=user and role=assistant
# text content. Tool blocks, thinking blocks, and system rows are dropped.
# If the offset falls mid-line, advances to the next newline before parsing
# (defensive against in-flight transcript writes).
extract_slice() {
  local file="$1" offset="$2"
  python3 - "$file" "$offset" <<'PY'
import sys, json
path = sys.argv[1]
offset = int(sys.argv[2])

with open(path, 'rb') as f:
    f.seek(offset)
    if offset > 0:
        # Advance past any partial line at the seek point.
        f.readline()
    lines = f.readlines()

for raw in lines:
    try:
        rec = json.loads(raw.decode('utf-8', errors='replace'))
    except Exception:
        continue
    msg = rec.get('message') or {}
    role = msg.get('role')
    if role not in ('user', 'assistant'):
        continue
    content = msg.get('content')
    parts = []
    if isinstance(content, str):
        parts.append(content)
    elif isinstance(content, list):
        for blk in content:
            if isinstance(blk, dict) and blk.get('type') == 'text':
                t = blk.get('text') or ''
                if t:
                    parts.append(t)
    if not parts:
        continue
    label = 'USER' if role == 'user' else 'ASSISTANT'
    print(f"{label}: " + " ".join(parts))
PY
}

# Run the LLM evaluator.
# Args: system_prompt user_payload
# Echoes the model's raw text response on stdout.
# Honors $CONSOLIDATOR_TEST_RESPONSE for hermetic tests.
# Engine selection via $CONSOLIDATOR_ENGINE (auto|openrouter|claude; default auto).
# auto: prefers OpenRouter when $OPENROUTER_API_KEY is set, else falls back to
#       `claude -p` with CLAUDE_CONSOLIDATOR=1 (recursion guard).
# openrouter: requires $OPENROUTER_API_KEY; writes engine-error:no-api-key to
#             $CONSOLIDATOR_STATEFILE and returns empty when key is absent.
# claude: always uses `claude -p` regardless of key presence.
call_llm() {
  local sys="$1" usr="$2"

  if [ -n "${CONSOLIDATOR_TEST_RESPONSE:-}" ]; then
    printf '%s' "$CONSOLIDATOR_TEST_RESPONSE"
    return 0
  fi

  local model="${CONSOLIDATOR_OPENROUTER_MODEL:-openai/gpt-4o-mini}"
  # Prefer new var name; honor legacy CONSOLIDATOR_CLEAN_MODEL for one release.
  local fallback_model="${CONSOLIDATOR_CLAUDE_MODEL:-${CONSOLIDATOR_CLEAN_MODEL:-haiku}}"
  local engine="${CONSOLIDATOR_ENGINE:-auto}"
  local has_key=0; [ -n "${OPENROUTER_API_KEY:-}" ] && has_key=1

  _call_openrouter() {
    jq -nc \
        --arg model "$model" \
        --arg sys   "$sys" \
        --arg usr   "$usr" \
        '{model:$model,
          messages:[{role:"system",content:$sys},{role:"user",content:$usr}],
          max_tokens:1200,
          temperature:0.2,
          response_format:{type:"json_object"}}' \
      | curl -s --max-time 30 \
          -H "Authorization: Bearer $OPENROUTER_API_KEY" \
          -H "Content-Type: application/json" \
          -H "HTTP-Referer: https://claude.com/claude-code" \
          -H "X-Title: Claude Code Consolidator" \
          -d @- https://openrouter.ai/api/v1/chat/completions \
      | jq -r '.choices[0].message.content // empty'
  }

  _call_claude() {
    command -v claude >/dev/null 2>&1 || return 0
    printf '%s' "$usr" \
      | CLAUDE_CONSOLIDATOR=1 claude -p \
          --model "$fallback_model" \
          --output-format text \
          --no-session-persistence \
          --disable-slash-commands \
          --append-system-prompt "$sys" 2>/dev/null
  }

  case "$engine" in
    auto)
      if [ "$has_key" -eq 1 ]; then
        _call_openrouter
      else
        _call_claude
      fi
      ;;
    openrouter)
      if [ "$has_key" -eq 1 ]; then
        _call_openrouter
      else
        echo "consolidator: engine=openrouter but OPENROUTER_API_KEY unset" >&2
        if [ -n "${CONSOLIDATOR_STATEFILE:-}" ]; then
          echo "engine-error:no-api-key" > "$CONSOLIDATOR_STATEFILE"
        fi
        # Empty stdout — parser layer treats as failed eval.
        return 0
      fi
      ;;
    claude)
      _call_claude
      ;;
    *)
      echo "consolidator: invalid engine '$engine'" >&2
      return 0
      ;;
  esac
}

# parse_decisions <raw-llm-response>
# Emits one TAB-delimited row per VALID decision:
#   action TAB type TAB name TAB description TAB content_b64
# Content is base64-encoded so embedded newlines/tabs survive shell parsing.
# Invalid decisions are silently dropped (caller logs to debug).
# Returns 0 always; emits 0 rows on parse failure.
parse_decisions() {
  local raw="$1"
  # Strip markdown code fences if present. `claude -p` regularly wraps JSON in
  # ```json ... ``` despite the system prompt forbidding it.
  raw=$(printf '%s' "$raw" | sed -e '/^[[:space:]]*```/d')
  # If json is malformed, jq -e returns non-zero; suppress + emit nothing.
  local decisions
  decisions=$(printf '%s' "$raw" | jq -c '.decisions // empty' 2>/dev/null) || return 0
  [ -z "$decisions" ] && return 0
  [ "$decisions" = "null" ] && return 0
  [ "$decisions" = "[]" ] && return 0

  printf '%s' "$decisions" | jq -rc '
    .[] | [(.action // ""),
           (.type // ""),
           (.name // ""),
           (.description // ""),
           (.content // "")
          ] | @tsv
  ' 2>/dev/null | while IFS=$'\t' read -r action type name description content_raw; do
    # Validate.
    case "$action" in add|update|remove) ;; *) continue ;; esac
    case "$type"   in user|feedback|project|reference) ;; *) continue ;; esac
    validate_name "$name" || continue
    [ -z "$description" ] && continue
    [ ${#description} -gt 200 ] && continue
    case "$description" in *$'\n'*) continue ;; esac
    if [ "$action" != "remove" ]; then
      [ -z "$content_raw" ] && continue
    fi
    # Fix 1: soft-check body structure for feedback/project types.
    case "$type" in
      feedback|project)
        if ! { printf '%s' "$content_raw" | grep -q '\*\*Why:\*\*' && printf '%s' "$content_raw" | grep -q '\*\*How to apply:\*\*'; }; then
          echo "consolidator: warning: $type/$name body missing **Why:** or **How to apply:** lines" >&2
        fi
        ;;
    esac
    # Fix 2: CONSOLIDATOR_ENABLED_TYPES filter (additive, does not replace type validation above).
    case ",${CONSOLIDATOR_ENABLED_TYPES:-user,feedback,project,reference}," in
      *",$type,"*) ;;
      *) echo "consolidator: type '$type' disabled (enabled_types=${CONSOLIDATOR_ENABLED_TYPES:-user,feedback,project,reference}); skipping" >&2; continue ;;
    esac
    local content_b64
    content_b64=$(printf '%s' "$content_raw" | base64 | tr -d '\n')
    printf '%s\t%s\t%s\t%s\t%s\n' "$action" "$type" "$name" "$description" "$content_b64"
  done
}

# Try to acquire a mkdir-based lock at $1. Times out after $2 seconds.
# Stale-lock recovery: if existing $1 mtime > 5 min, force-remove and retry.
# Returns 0 on success, 1 on timeout.
acquire_lock() {
  local lock="$1" timeout="${2:-5}"
  local elapsed=0
  while ! mkdir "$lock" 2>/dev/null; do
    if [ -d "$lock" ]; then
      local mtime
      mtime=$(stat -f %m "$lock" 2>/dev/null || echo 0)
      if [ $(($(date +%s) - mtime)) -gt 300 ]; then
        rmdir "$lock" 2>/dev/null
        continue
      fi
    fi
    sleep 0.2
    elapsed=$(awk -v e="$elapsed" 'BEGIN{print e + 0.2}')
    awk -v e="$elapsed" -v t="$timeout" 'BEGIN{exit !(e >= t)}' && return 1
  done
  return 0
}

release_lock() {
  rmdir "$1" 2>/dev/null || true
}

# Migrate legacy env-var names in a conf or session flag file.
# Returns 0 always; echoes count of keys migrated.
# Idempotent: subsequent passes echo 0 and don't touch the file.
# Missing file: echo 0, return 0.
#
# Legacy map (old → new):
#   CONSOLIDATOR_CLEAN_MODEL → CONSOLIDATOR_CLAUDE_MODEL
#
# When both old and new exist: drop old (new wins).
migrate_legacy_conf() {
  local file="$1"
  local migrated=0
  [ -f "$file" ] || { echo 0; return 0; }
  # Map entries: "OLD:NEW" pairs. Add more pairs here as schema evolves.
  local pair old new tmp
  for pair in "CONSOLIDATOR_CLEAN_MODEL:CONSOLIDATOR_CLAUDE_MODEL"; do
    old="${pair%%:*}"
    new="${pair##*:}"
    grep -qE "^$old=" "$file" 2>/dev/null || continue
    tmp="$file.migrate.$$"
    if grep -qE "^$new=" "$file" 2>/dev/null; then
      # Both present: drop the old line.
      grep -vE "^$old=" "$file" > "$tmp" && mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
    else
      # Only old present: rename in-place.
      sed "s|^$old=|$new=|" "$file" > "$tmp" && mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
    fi
    migrated=$((migrated + 1))
  done
  echo "$migrated"
}
