#!/usr/bin/env bash

input=$(cat)

# Parse all fields in a single jq call (newline-delimited, "" for missing)
{
  IFS= read -r cwd
  IFS= read -r model
  IFS= read -r session_id
  IFS= read -r used
  IFS= read -r five_hr
  IFS= read -r week
  IFS= read -r five_hr_reset
  IFS= read -r week_reset
  IFS= read -r effort
  IFS= read -r thinking
  IFS= read -r service_tier
} < <(printf '%s' "$input" | jq -r '
  .workspace.current_dir // .cwd // "",
  .model.display_name // "",
  .session_id // "",
  .context_window.used_percentage // "",
  .rate_limits.five_hour.used_percentage // "",
  .rate_limits.seven_day.used_percentage // "",
  .rate_limits.five_hour.resets_at // "",
  .rate_limits.seven_day.resets_at // "",
  .effort.level // "",
  (.thinking.enabled // false | tostring),
  .service_tier // .service.tier // .model.service_tier // ""
')

# Derive total tokens from model name
case "$model" in
  *1M*)   total=1000000 ;;
  *250k*) total=250000 ;;
  *200k*) total=200000 ;;
  *)      total=200000 ;;
esac

fmt_remaining() {
  local secs=$(( $1 - $(date +%s) ))
  (( secs <= 0 )) && { echo "now"; return; }
  local d=$((secs/86400)) h=$(((secs%86400)/3600)) m=$(((secs%3600)/60))
  if   (( d > 0 )); then echo "${d}d${h}h"
  elif (( h > 0 )); then echo "${h}h${m}m"
  else                   echo "${m}m"
  fi
}

# Pick ANSI color escape for a percentage, escalating: base → yellow ≥70 → bold bright red ≥90
# Args: $1 = percent (float), $2 = base color code (e.g., "35")
threshold_color() {
  local pct=$1 base=$2
  if awk "BEGIN{exit !($pct >= 90)}" 2>/dev/null; then echo "1;91"
  elif awk "BEGIN{exit !($pct >= 70)}" 2>/dev/null; then echo "33"
  else echo "$base"
  fi
}

# Get git branch + dirty + ahead/behind (skip optional locks to avoid conflicts)
branch=""
dirty=""
ahead_behind=""
if git -C "$cwd" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  branch=$(git -C "$cwd" -c gc.auto=0 symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$(git -C "$cwd" -c gc.auto=0 status --porcelain 2>/dev/null)" ]; then
    dirty="*"
  fi
  ab=$(git -C "$cwd" -c gc.auto=0 rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
  if [ -n "$ab" ]; then
    a=$(printf '%s' "$ab" | awk '{print $1}')
    b=$(printf '%s' "$ab" | awk '{print $2}')
    [ "${a:-0}" -gt 0 ] 2>/dev/null && ahead_behind+="↑$a"
    [ "${b:-0}" -gt 0 ] 2>/dev/null && ahead_behind+="${ahead_behind:+ }↓$b"
  fi

  # Keep @{upstream} fresh in the background so ↑n ↓n reflects the remote,
  # not just the last manual fetch. Per-repo singleton; daemon self-exits on idle.
  GIT_WATCH_DAEMON="$HOME/.claude/scripts/git-watch-daemon.sh"
  GIT_WATCH_CACHE="$HOME/.claude/cache/git-fetch"
  if [ -x "$GIT_WATCH_DAEMON" ]; then
    mkdir -p "$GIT_WATCH_CACHE"
    repo_key=$(printf '%s' "$cwd" | shasum 2>/dev/null | awk '{print $1}')
    if [ -n "$repo_key" ]; then
      touch "$GIT_WATCH_CACHE/$repo_key.heartbeat"
      gw_pid_file="$GIT_WATCH_CACHE/$repo_key.pid"
      if [ ! -f "$gw_pid_file" ] || ! kill -0 "$(cat "$gw_pid_file" 2>/dev/null)" 2>/dev/null; then
        nohup bash "$GIT_WATCH_DAEMON" "$cwd" >/dev/null 2>&1 &
        disown 2>/dev/null || true
      fi
    fi
  fi
fi

# Build parts:
#   line 1 = model | context | limits | session
#   line 2 = path | branch
#   line 3 = per-session feature flags (TTS, ntfy)  — only shown when ≥1 active
#   line 4 = network status                          — only shown when degraded
line1=()
line2=()
line3=()

# Profile chip — derived from CLAUDE_CONFIG_DIR (instant, no subprocess).
# settings.json/this script are typically shared across profiles, so detect at runtime:
#   unset or ~/.claude  → "personal" (purple)
#   anything else       → basename of the config dir (grey)
case "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" in
  "$HOME/.claude") prof="personal";   prof_color="38;2;181;137;255" ;;
  *)               prof="$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")"; prof_color="90" ;;
esac
line1+=("$(printf '\033[%sm⬡ %s\033[0m' "$prof_color" "$prof")")

# model — "✳ Opus 4.7 1M (high)"
# Format: <name> <window-size> (<effort or thinking>) — size as 1M / 200k.
# Falls back gracefully when effort or thinking is unset.
if [ -n "$model" ]; then
  short_model="$model"
  short_model="${short_model#Claude }"          # strip leading "Claude "
  short_model="${short_model%% (*}"              # strip any existing "(... context)" suffix
  if [ "$total" -ge 1000000 ]; then
    short_model="$short_model $((total / 1000000))M"
  else
    short_model="$short_model $((total / 1000))k"
  fi
  model_modes=()
  if [ -n "$effort" ]; then
    model_modes+=("$effort")
  elif [ "$thinking" = "true" ]; then
    model_modes+=("thinking")
  fi
  [ "$service_tier" = "fast" ] && model_modes+=("fast")
  if [ ${#model_modes[@]} -gt 0 ]; then
    joined_modes="${model_modes[0]}"
    for mode in "${model_modes[@]:1}"; do joined_modes+=", $mode"; done
    short_model="$short_model ($joined_modes)"
  fi
  line1+=("$(printf '\033[38;2;204;120;92m✳ %s\033[0m' "$short_model")")
fi

# context usage — "3% (30k)" style
if [ -n "$used" ]; then
  used_tokens=$(awk "BEGIN { printf \"%.0f\", $total * $used / 100 }")
  if [ "$used_tokens" -ge 1000000 ]; then
    human=$(awk "BEGIN { printf \"%.1fM\", $used_tokens / 1000000 }")
  elif [ "$used_tokens" -ge 1000 ]; then
    human=$(awk "BEGIN { printf \"%.0fk\", $used_tokens / 1000 }")
  else
    human="$used_tokens"
  fi
  ctx_color=$(threshold_color "$used" 32)
  line1+=("$(printf '\033[%sm◷ %.0f%% (~%s)\033[0m' "$ctx_color" "$used" "$human")")
fi

# rate limits — color each segment independently by threshold
rate_parts=()
hit_or_remaining() {
  # $1=pct, $2=reset_epoch — emits "(hit, Xh)" when ≥100, else "(Xh)"
  local pct=$1 reset=$2
  if awk "BEGIN{exit !($pct >= 100)}" 2>/dev/null; then
    [ -n "$reset" ] && printf '(hit, %s)' "$(fmt_remaining "$reset")" || printf '(hit)'
  else
    [ -n "$reset" ] && printf '(%s)' "$(fmt_remaining "$reset")"
  fi
}

if [ -n "$five_hr" ]; then
  s="5h:$(printf '%.0f' "$five_hr")%"
  paren=$(hit_or_remaining "$five_hr" "$five_hr_reset")
  [ -n "$paren" ] && s="$s $paren"
  c=$(threshold_color "$five_hr" "38;2;120;160;230")
  rate_parts+=("$(printf '\033[%sm%s\033[0m' "$c" "$s")")
fi
if [ -n "$week" ]; then
  s="7d:$(printf '%.0f' "$week")%"
  paren=$(hit_or_remaining "$week" "$week_reset")
  [ -n "$paren" ] && s="$s $paren"
  c=$(threshold_color "$week" "38;2;120;160;230")
  rate_parts+=("$(printf '\033[%sm%s\033[0m' "$c" "$s")")
fi
if [ ${#rate_parts[@]} -gt 0 ]; then
  joined="$(printf '\033[38;2;120;160;230m⧗\033[0m')"
  for r in "${rate_parts[@]}"; do joined+=" $r"; done
  line1+=("$joined")
fi

# session id (last on line 1)
if [ -n "$session_id" ]; then
  line1+=("$(printf '\033[90m⌗ %s\033[0m' "$session_id")")
fi

# directory (shortened ~, trailing /)
display_cwd="${cwd/#$HOME/~}"
[ "${display_cwd: -1}" != "/" ] && display_cwd="$display_cwd/"
line2+=("$(printf '\033[36m▸ %s\033[0m' "$display_cwd")")

# git branch (with dirty + ahead/behind), or "No Git" placeholder
if [ -n "$branch" ]; then
  branch_label="⎇  (${branch}${dirty})"
  [ -n "$ahead_behind" ] && branch_label="$branch_label $ahead_behind"
  line2+=("$(printf '\033[33m%s\033[0m' "$branch_label")")
else
  line2+=("$(printf '\033[90m⌀ No Git\033[0m')")
fi

# Per-session feature flags. Each is keyed on the same flag file the
# corresponding /enable command touches, so the chip lights up exactly when
# the feature is on for THIS session.
if [ -n "$session_id" ]; then
  if [ -f "$HOME/.claude/tts-sessions/$session_id" ]; then
    # Resolve mode: session override > global > "normal".
    tts_mode=""
    sess_conf="$HOME/.claude/tts-sessions/$session_id.conf"
    [ -f "$sess_conf" ] && tts_mode=$(grep -E '^TTS_MODE=' "$sess_conf" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"')
    if [ -z "$tts_mode" ] && [ -f "$HOME/.claude/tts.conf" ]; then
      tts_mode=$(grep -E '^TTS_MODE=' "$HOME/.claude/tts.conf" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"')
    fi
    tts_mode="${tts_mode:-normal}"

    # Pipeline state. Trust source by state:
    #   speaking → only if the player pid is alive (long playbacks are fine).
    #   cleaning / synthesizing → mtime ≤ 60s (curl caps are 15s + 30s).
    # Elapsed seconds since the state was written = now - mtime.
    tts_state_file="$HOME/.claude/tts-sessions/$session_id.state"
    tts_pidfile="$HOME/.claude/tts-sessions/$session_id.pid"
    tts_state=""
    tts_state_elapsed=0
    if [ -f "$tts_state_file" ]; then
      raw_state=$(cat "$tts_state_file" 2>/dev/null)
      mtime=$(stat -f %m "$tts_state_file" 2>/dev/null || echo 0)
      tts_state_age=$(( $(date +%s) - mtime ))
      case "$raw_state" in
        speaking)
          if [ -f "$tts_pidfile" ]; then
            spk_pid=$(cat "$tts_pidfile" 2>/dev/null)
            if [ -n "$spk_pid" ] && kill -0 "$spk_pid" 2>/dev/null; then
              tts_state="speaking"
              tts_state_elapsed="$tts_state_age"
            fi
          fi
          ;;
        cleaning|synthesizing)
          if [ "$tts_state_age" -le 60 ]; then
            tts_state="$raw_state"
            tts_state_elapsed="$tts_state_age"
          fi
          ;;
      esac
    fi

    case "$tts_state" in
      cleaning)
        line3+=("$(printf '\033[38;5;215m⏳ TTS (%s) · cleaning %ds\033[0m' "$tts_mode" "$tts_state_elapsed")")
        ;;
      synthesizing)
        line3+=("$(printf '\033[38;5;215m⏳ TTS (%s) · synthesizing %ds\033[0m' "$tts_mode" "$tts_state_elapsed")")
        ;;
      speaking)
        line3+=("$(printf '\033[38;5;81m▶ TTS (%s) · speaking %ds\033[0m' "$tts_mode" "$tts_state_elapsed")")
        ;;
      *)
        line3+=("$(printf '\033[38;5;108m♪ TTS (%s)\033[0m' "$tts_mode")")
        ;;
    esac
  fi
  if [ -f "$HOME/.claude/ntfy-sessions/$session_id" ]; then
    ntfy_state_file="$HOME/.claude/ntfy-sessions/$session_id.state"
    ntfy_state=""
    if [ -f "$ntfy_state_file" ]; then
      age=$(( $(date +%s) - $(stat -f %m "$ntfy_state_file" 2>/dev/null || echo 0) ))
      [ "$age" -le 60 ] && ntfy_state=$(cat "$ntfy_state_file" 2>/dev/null)
    fi
    case "$ntfy_state" in
      sending)
        line3+=("$(printf '\033[38;5;215m⏳ Ntfy · sending…\033[0m')")
        ;;
      *)
        line3+=("$(printf '\033[38;5;108m⏰ Ntfy\033[0m')")
        ;;
    esac
  fi
  if [ -f "$HOME/.claude/consolidator-sessions/$session_id" ]; then
    cons_state_file="$HOME/.claude/consolidator-sessions/$session_id.state"
    cons_state=""
    cons_age=0
    if [ -f "$cons_state_file" ]; then
      cons_state=$(cat "$cons_state_file" 2>/dev/null)
      cons_age=$(( $(date +%s) - $(stat -f %m "$cons_state_file" 2>/dev/null || echo 0) ))
    fi
    case "$cons_state" in
      evaluating)
        if [ "$cons_age" -le 60 ]; then
          line3+=("$(printf '\033[38;5;215m⏳ Consolidator · evaluating %ds\033[0m' "$cons_age")")
        else
          line3+=("$(printf '\033[38;5;108m🧠 Consolidator\033[0m')")
        fi
        ;;
      writing)
        if [ "$cons_age" -le 30 ]; then
          line3+=("$(printf '\033[38;5;215m⏳ Consolidator · writing %ds\033[0m' "$cons_age")")
        else
          line3+=("$(printf '\033[38;5;108m🧠 Consolidator\033[0m')")
        fi
        ;;
      saved:*)
        if [ "$cons_age" -le 10 ]; then
          line3+=("$(printf '\033[38;5;46m💾 Consolidator · saved %s\033[0m' "${cons_state#saved:}")")
        else
          line3+=("$(printf '\033[38;5;108m🧠 Consolidator\033[0m')")
        fi
        ;;
      engine-error:*)
        if [ "$cons_age" -le 300 ]; then
          line3+=("$(printf '\033[38;5;196m⚠ Consolidator · %s\033[0m' "${cons_state#engine-error:}")")
        else
          line3+=("$(printf '\033[38;5;108m🧠 Consolidator\033[0m')")
        fi
        ;;
      *)
        line3+=("$(printf '\033[38;5;108m🧠 Consolidator\033[0m')")
        ;;
    esac
  fi
fi

# Network status (from background daemon)
DAEMON_SCRIPT="$HOME/.claude/scripts/network-daemon.sh"
DAEMON_PID_FILE="$HOME/.claude/cache/network-daemon.pid"
NET_STATE_FILE="$HOME/.claude/cache/network-status"

# Spawn daemon if installed and not already running
if [ -x "$DAEMON_SCRIPT" ] && { [ ! -f "$DAEMON_PID_FILE" ] || ! kill -0 "$(cat "$DAEMON_PID_FILE" 2>/dev/null)" 2>/dev/null; }; then
  nohup bash "$DAEMON_SCRIPT" &>/dev/null &
  disown
fi

# Read state file for network indicator (right-aligned)
net_label=""
net_label_len=0
if [ -f "$NET_STATE_FILE" ]; then
  source "$NET_STATE_FILE"
  file_age=$(( $(date +%s) - ${TIMESTAMP:-0} ))
  if [ "$file_age" -le 30 ]; then
    case "$STATE" in
      offline)      net_label="$(printf '\033[31m✗ Not connected\033[0m')"; net_label_len=15 ;;
      slow)         net_label="$(printf '\033[33m⚠ Slow connection\033[0m')"; net_label_len=17 ;;
      reconnected)  net_label="$(printf '\033[32m✔ Reconnected\033[0m')"; net_label_len=13 ;;
    esac
  fi
fi

# Output: line 1 (session info), line 2 (path/branch),
#         line 3 (feature flags — only if any), line 4 (network — only if degraded)
if [ ${#line1[@]} -gt 0 ]; then
  out="${line1[0]}"
  for p in "${line1[@]:1}"; do out+=$(printf ' \033[90m|\033[0m %s' "$p"); done
  printf '%s\n' "$out"
fi
if [ ${#line2[@]} -gt 0 ]; then
  out="${line2[0]}"
  for p in "${line2[@]:1}"; do out+=$(printf ' \033[90m|\033[0m %s' "$p"); done
  printf '%s\n' "$out"
fi
if [ ${#line3[@]} -gt 0 ]; then
  out="${line3[0]}"
  for p in "${line3[@]:1}"; do out+=$(printf ' \033[90m|\033[0m %s' "$p"); done
  printf '%s\n' "$out"
fi
[ -n "$net_label" ] && printf '%s\n' "$net_label"
exit 0
