# statusline Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fourth `statusline` module to `claude-setup` that exports `statusline-command.sh` + the git-watch and network daemons, installable via an agent runbook.

**Architecture:** Standalone module (no `core` dependency). The main script installs to `~/.claude/statusline-command.sh`; the two daemons to `~/.claude/scripts/`. Wiring is the `settings.json` `statusLine` key (jq set/`del`, not `_merge-hook.sh`). The statusline soft-integrates with tts/ntfy/consolidator by reading their per-session flag files — chips appear only when those modules are installed.

**Tech Stack:** bash, jq, git, macOS (`stat -f`, `date`, `awk`, `shasum`); optional `fswatch` (git-watch daemon), `ping` (network daemon).

**Source of truth for copied files:** `~/.claude/statusline-command.sh` and `~/.claude/scripts/{git-watch-daemon.sh,network-daemon.sh}` on this machine. Repo is at `~/Projects/personal/claude-setup`, branch `feat/statusline-module`, base `1879354` (the published `main`).

**Single content edit:** genericize the profile chip in `statusline-command.sh` (drop the hardcoded `work` / `work-belen` profiles). Both daemons are copied verbatim (already personal-data-free).

---

## File Structure

```
statusline/
├── statusline-command.sh      # main script → ~/.claude/statusline-command.sh (genericized)
├── scripts/
│   ├── git-watch-daemon.sh    # verbatim → ~/.claude/scripts/
│   └── network-daemon.sh      # verbatim → ~/.claude/scripts/
└── INSTALL.md
```
README.md gains a `statusline` row + dependency line.

---

## Task 1: statusline module files

**Files:**
- Create: `statusline/statusline-command.sh` (copy of `~/.claude/statusline-command.sh` + profile-chip edit)
- Create: `statusline/scripts/git-watch-daemon.sh` (verbatim)
- Create: `statusline/scripts/network-daemon.sh` (verbatim)

- [ ] **Step 1: Copy the three scripts**

```bash
cd ~/Projects/personal/claude-setup
mkdir -p statusline/scripts
cp ~/.claude/statusline-command.sh statusline/statusline-command.sh
cp ~/.claude/scripts/git-watch-daemon.sh statusline/scripts/
cp ~/.claude/scripts/network-daemon.sh statusline/scripts/
chmod +x statusline/statusline-command.sh statusline/scripts/*.sh
```

- [ ] **Step 2: Genericize the profile chip**

In `statusline/statusline-command.sh`, replace this block (the comment + `case`, originally ~lines 104–115):

```bash
# clausona profile — derived from CLAUDE_CONFIG_DIR (instant, no subprocess).
# settings.json/this script are shared across profiles, so detect at runtime:
#   unset or ~/.claude        → personal     (green)
#   ~/.claude-work            → work         (bright blue)
#   ~/.claude-work-belen      → work-belen   (magenta)
#   anything else             → basename of the dir (grey)
case "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" in
  "$HOME/.claude")            prof="personal";   prof_color="38;2;181;137;255" ;;
  "$HOME/.claude-work")       prof="work";       prof_color="38;2;181;137;255" ;;
  "$HOME/.claude-work-belen") prof="work-belen"; prof_color="38;2;181;137;255" ;;
  *)                          prof="$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")"; prof_color="90" ;;
esac
```

with this generic version:

```bash
# Profile chip — derived from CLAUDE_CONFIG_DIR (instant, no subprocess).
# settings.json/this script are typically shared across profiles, so detect at runtime:
#   unset or ~/.claude  → "personal" (purple)
#   anything else       → basename of the config dir (grey)
case "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" in
  "$HOME/.claude") prof="personal";   prof_color="38;2;181;137;255" ;;
  *)               prof="$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")"; prof_color="90" ;;
esac
```

- [ ] **Step 3: Verify no personal strings remain**

```bash
cd ~/Projects/personal/claude-setup
grep -rnI -e bernardo -e belen statusline/ && echo "FAIL: personal string present" || echo "CLEAN"
```
Expected: `CLEAN`.

- [ ] **Step 4: Syntax-check all three scripts**

```bash
bash -n statusline/statusline-command.sh \
  && bash -n statusline/scripts/git-watch-daemon.sh \
  && bash -n statusline/scripts/network-daemon.sh \
  && echo "SYNTAX OK"
```
Expected: `SYNTAX OK`.

- [ ] **Step 5: Render test (behavioral)**

Run the statusline against a crafted input, with `HOME` pointed at an EMPTY temp dir so no daemons spawn (git-watch is guarded by `[ -x "$HOME/.claude/scripts/git-watch-daemon.sh" ]`, absent here; network-daemon's spawn targets a path that doesn't exist, so it silently fails). The cwd is the repo (a git repo) so the git branch path renders too.

```bash
cd ~/Projects/personal/claude-setup
SBHOME=$(mktemp -d)
IN='{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Claude Opus 4.7 (1M context)"},"session_id":"test-sess-1","context_window":{"used_percentage":3},"effort":{"level":"high"}}'
OUT=$(printf '%s' "$IN" | HOME="$SBHOME" bash statusline/statusline-command.sh); rc=$?
printf '%s\n' "$OUT"
echo "exit=$rc"
printf '%s' "$OUT" | grep -q "Opus 4.7 1M (high)" && echo "MODEL: PASS" || echo "MODEL: FAIL"
printf '%s' "$OUT" | grep -q "◷ 3%" && echo "CONTEXT: PASS" || echo "CONTEXT: FAIL"
printf '%s' "$OUT" | grep -q "▸ " && echo "CWD: PASS" || echo "CWD: FAIL"
printf '%s' "$OUT" | grep -q "⬡ personal" && echo "PROFILE: PASS" || echo "PROFILE: FAIL"
rm -rf "$SBHOME"
```
Expected: `exit=0`, then `MODEL: PASS`, `CONTEXT: PASS`, `CWD: PASS`, `PROFILE: PASS`. (Profile shows `personal` because `CLAUDE_CONFIG_DIR` is unset and `$SBHOME/.claude` ≠ the matched `$HOME/.claude` — wait: with `HOME=$SBHOME`, the case matches `"$HOME/.claude"` = `$SBHOME/.claude` and `CLAUDE_CONFIG_DIR` unset defaults to `$HOME/.claude` = `$SBHOME/.claude`, so it matches the first branch → `personal`. PASS.)

> Do NOT commit — the controller commits.

---

## Task 2: statusline/INSTALL.md

**Files:**
- Create: `statusline/INSTALL.md`

- [ ] **Step 1: Author `statusline/INSTALL.md`**

Full content:

````markdown
# Install: statusline (multi-line status bar)

A status bar for Claude Code showing: profile chip, model + context %, rate-limit
usage with reset countdowns, session id, cwd + git branch/dirty/ahead-behind, live
per-session **TTS / Ntfy / Consolidator** chips, and a network status line when the
connection degrades.

**Standalone:** unlike the other modules, statusline does **not** require `core`.
It reads the session id from Claude Code's status JSON and wires through the
`settings.json` `statusLine` key (not hooks).

**Soft integration:** the line-3 TTS/Ntfy/Consolidator chips appear automatically
when those modules are installed and enabled for the session; if they aren't, the
chips simply don't show.

## Prerequisites
- `bash`, `jq`, `git`
- macOS (uses `stat -f`, `date`, `awk`, `shasum`)
- Optional: `fswatch` (`brew install fswatch`) for the git-watch daemon
  (keeps `↑n ↓n` fresh against the remote)

## 1. Place files
```bash
mkdir -p ~/.claude/scripts
cp statusline/statusline-command.sh ~/.claude/statusline-command.sh
cp statusline/scripts/git-watch-daemon.sh ~/.claude/scripts/
cp statusline/scripts/network-daemon.sh ~/.claude/scripts/
chmod +x ~/.claude/statusline-command.sh \
         ~/.claude/scripts/git-watch-daemon.sh \
         ~/.claude/scripts/network-daemon.sh
```

## 2. Wire the statusLine setting
```bash
SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)-$RANDOM"
tmp=$(mktemp)
jq '.statusLine = {type:"command", command:"bash ~/.claude/statusline-command.sh", refreshInterval:1}' \
  "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
```
Restart Claude Code (or reload settings) to see the status bar.

## 3. Optional daemons
- **git ahead/behind freshness:** `brew install fswatch`. Nothing else to do — the
  statusline auto-spawns `git-watch-daemon.sh` per repo (it self-exits on idle).
  Without `fswatch`, `↑n ↓n` still updates whenever you fetch manually.
- **network status line:** no setup — the statusline auto-spawns
  `network-daemon.sh`, which pings `1.1.1.1` and shows line 4 only when the
  connection is offline/slow/just-reconnected.

## 4. Verify
The status bar should appear at the bottom of Claude Code. To check rendering from
a shell:
```bash
printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Claude Opus 4.7 (1M context)"},"session_id":"x","context_window":{"used_percentage":3},"effort":{"level":"high"}}' "$PWD" \
  | bash ~/.claude/statusline-command.sh
```
You should see a line with `✳ Opus 4.7 1M (high)` and `◷ 3%`, and a second line
with `▸ <cwd>/` and the git branch.

## Uninstall
```bash
SETTINGS="$HOME/.claude/settings.json"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)-$RANDOM"
tmp=$(mktemp)
jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
rm -f ~/.claude/statusline-command.sh \
      ~/.claude/scripts/git-watch-daemon.sh \
      ~/.claude/scripts/network-daemon.sh
# The daemons stop on their own (git-watch self-exits on idle; kill any lingering
# network daemon with: pkill -f network-daemon.sh). Caches live under ~/.claude/cache/.
```
````

> Do NOT commit — the controller commits.

---

## Task 3: README update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add the statusline row to the module table**

Find the consolidator table row:
```markdown
| [`consolidator`](consolidator/INSTALL.md) | On `Stop`, evaluates the transcript and consolidates long-term memory files. | Stop | no |
```
Add this line immediately after it:
```markdown
| [`statusline`](statusline/INSTALL.md) | Multi-line status bar: profile, model + context %, rate limits, cwd + git, and live TTS/Ntfy/Consolidator chips. **Standalone — no core needed.** | — (uses the `statusLine` setting) | yes (`stat -f`) |
```

- [ ] **Step 2: Note the statusline exception in the Install steps**

Replace:
```markdown
1. Install **core** first: follow [`core/INSTALL.md`](core/INSTALL.md).
2. Install any modules you want, in any order: follow that module's `INSTALL.md`.
3. Restart Claude Code so the new hooks load.
```
with:
```markdown
1. Install **core** first: follow [`core/INSTALL.md`](core/INSTALL.md). (Every
   module needs it except `statusline`, which is standalone.)
2. Install any modules you want, in any order: follow that module's `INSTALL.md`.
3. Restart Claude Code so the new hooks / statusline load.
```

- [ ] **Step 3: Add the statusline dependency line**

Find:
```markdown
- consolidator: optional OpenRouter key.
```
Add immediately after it:
```markdown
- statusline: `bash`, `jq`, `git`, macOS (`stat -f`); optional `fswatch` for the git ahead/behind daemon.
```

- [ ] **Step 4: Verify the links resolve**

```bash
cd ~/Projects/personal/claude-setup
ls statusline/INSTALL.md && echo "LINK OK"
grep -n "statusline" README.md
```
Expected: `LINK OK` and the new table row + dependency line shown.

> Do NOT commit — the controller commits.

---

## Task 4: End-to-end sandbox verification

Verify a clean install into a throwaway config dir. VERIFICATION ONLY — no production files created.

**Files:** none

- [ ] **Step 1: Sandbox place-files**

```bash
cd ~/Projects/personal/claude-setup
SB=$(mktemp -d)/.claude; mkdir -p "$SB/scripts"
cp statusline/statusline-command.sh "$SB/statusline-command.sh"
cp statusline/scripts/git-watch-daemon.sh "$SB/scripts/"
cp statusline/scripts/network-daemon.sh "$SB/scripts/"
chmod +x "$SB/statusline-command.sh" "$SB"/scripts/*.sh
echo '{"existingKey":true}' > "$SB/settings.json"
echo "Sandbox: $SB"
```

- [ ] **Step 2: Wire statusLine twice; assert idempotent + existing keys preserved**

```bash
S="$SB/settings.json"
wire() { tmp=$(mktemp); jq '.statusLine = {type:"command", command:"bash ~/.claude/statusline-command.sh", refreshInterval:1}' "$S" > "$tmp" && mv "$tmp" "$S"; }
wire; A=$(jq -S . "$S"); wire; B=$(jq -S . "$S")
[ "$A" = "$B" ] && echo "IDEMPOTENT: PASS" || echo "IDEMPOTENT: FAIL"
jq -e '.statusLine.command == "bash ~/.claude/statusline-command.sh"' "$S" >/dev/null && echo "STATUSLINE SET: PASS" || echo "FAIL"
jq -e '.existingKey == true' "$S" >/dev/null && echo "EXISTING KEY PRESERVED: PASS" || echo "FAIL"
```
Expected: `IDEMPOTENT: PASS`, `STATUSLINE SET: PASS`, `EXISTING KEY PRESERVED: PASS`.

- [ ] **Step 3: Uninstall (del) leaves other settings intact**

```bash
tmp=$(mktemp); jq 'del(.statusLine)' "$S" > "$tmp" && mv "$tmp" "$S"
jq -e 'has("statusLine") | not' "$S" >/dev/null && echo "STATUSLINE REMOVED: PASS" || echo "FAIL"
jq -e '.existingKey == true' "$S" >/dev/null && echo "EXISTING KEY INTACT: PASS" || echo "FAIL"
```
Expected: both PASS.

- [ ] **Step 4: Render test against the sandbox-installed script**

```bash
IN='{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Claude Opus 4.7 (1M context)"},"session_id":"sess-x","context_window":{"used_percentage":3},"effort":{"level":"high"},"rate_limits":{"five_hour":{"used_percentage":12},"seven_day":{"used_percentage":40}}}'
SBHOME=$(mktemp -d)   # empty HOME → no daemons spawn
OUT=$(printf '%s' "$IN" | HOME="$SBHOME" bash "$SB/statusline-command.sh"); rc=$?
printf '%s\n' "$OUT"; echo "exit=$rc"
printf '%s' "$OUT" | grep -q "Opus 4.7 1M (high)" && echo "MODEL: PASS" || echo "MODEL: FAIL"
printf '%s' "$OUT" | grep -q "5h:12%" && echo "RATE: PASS" || echo "RATE: FAIL"
rm -rf "$SBHOME"
```
Expected: `exit=0`, `MODEL: PASS`, `RATE: PASS`.

- [ ] **Step 5: Confirm no daemon leaked from the sandbox**

```bash
pgrep -f "$SB/scripts/network-daemon.sh" && echo "WARN: daemon running (kill it)" || echo "NO LEAK"
```
Expected: `NO LEAK` (the render test used an empty HOME so no daemon was spawned).

- [ ] **Step 6: Cleanup + final repo sanity**

```bash
rm -rf "$(dirname "$SB")"
cd ~/Projects/personal/claude-setup
grep -rnI -e bernardo -e belen statusline && echo "FAIL: personal strings" || echo "MODULES CLEAN"
git status --short
```
Expected: `MODULES CLEAN`, and `git status` shows only the new `statusline/` (untracked) + modified `README.md` + the plan/spec docs (controller commits these).

---

## Self-Review

**Spec coverage:**
- Export statusline-command.sh + both daemons → Task 1. ✓
- Standalone (no core) → documented in INSTALL.md (Task 2) + README (Task 3). ✓
- Soft integration with tts/ntfy/consolidator → documented in INSTALL.md. ✓
- statusLine-key wiring (jq set/del, idempotent, backup) → INSTALL.md (Task 2) + verified (Task 4 Steps 2–3). ✓
- Profile-chip genericization → Task 1 Step 2 + grep gate (Step 3). ✓
- Dependencies (fswatch optional, etc.) → INSTALL.md + README. ✓
- Render test → Task 1 Step 5 + Task 4 Step 4. ✓
- No daemon leak in tests → Task 4 Step 5. ✓
- README row + deps → Task 3. ✓

**Placeholder scan:** No TBD/TODO; INSTALL.md authored in full; copied files use exact `cp`; the one content edit shows exact old→new.

**Consistency:** The `statusLine` object (`type`/`command`/`refreshInterval`) is identical across INSTALL.md (Task 2), README, and the Task 4 assertions. The render-test input JSON shape and the asserted substrings (`Opus 4.7 1M (high)`, `◷ 3%`, `5h:12%`, `⬡ personal`) match the script's actual output logic.
