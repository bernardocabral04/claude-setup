# ai-rename Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `ai-rename` module (the `/ai-rename` session-namer) to `claude-setup`, with the personal operator prefix genericized.

**Architecture:** Command-only module that depends on `core` (both scripts use `_resolve-session-id.sh`). Copy `ai-rename-collect.sh` verbatim; genericize `ai-rename-persist.sh` (username-default prefix + keystroke opt-out); rewrite the command's naming rules to emit prefix-less `<project>/<topic>` names. No `settings.json` wiring (commands are auto-discovered).

**Tech Stack:** bash, jq, git (optional), macOS `osascript` (optional live-TUI sync).

**Source of truth:** `~/.claude/scripts/{ai-rename-collect.sh,ai-rename-persist.sh}` and `~/.claude/commands/ai-rename.md`. Repo: `~/Projects/personal/claude-setup`, branch `feat/ai-rename-module`, base `1879354`.

---

## File Structure

```
ai-rename/
├── scripts/
│   ├── ai-rename-collect.sh    # verbatim
│   └── ai-rename-persist.sh    # genericized: prefix + keystroke opt-out
├── commands/ai-rename.md       # genericized naming rules + examples
└── INSTALL.md
README.md                       # module-table row + deps line
```

---

## Task 1: Scripts

**Files:**
- Create: `ai-rename/scripts/ai-rename-collect.sh` (verbatim)
- Create: `ai-rename/scripts/ai-rename-persist.sh` (2 edits)

- [ ] **Step 1: Copy both scripts**

```bash
cd ~/Projects/personal/claude-setup
mkdir -p ai-rename/scripts ai-rename/commands
cp ~/.claude/scripts/ai-rename-collect.sh ai-rename/scripts/
cp ~/.claude/scripts/ai-rename-persist.sh ai-rename/scripts/
chmod +x ai-rename/scripts/*.sh
```

- [ ] **Step 2: Genericize the operator prefix in `ai-rename-persist.sh`**

Replace EXACTLY:
```bash
# Shared account: namespace every session under the operator's name so
# sessions are attributable. Idempotent — skip if already prefixed.
PREFIX="bernardo/"
case "$NAME" in
  "$PREFIX"*) : ;;
  *) NAME="$PREFIX$NAME" ;;
esac
```
with:
```bash
# Namespace every session under an operator prefix so sessions are attributable.
# Source: $AI_RENAME_PREFIX if set (empty = no prefix), else the OS username.
# Sanitize to the allowed charset so the final name always validates.
RAW_PREFIX="${AI_RENAME_PREFIX-$(whoami)}"
SAFE_PREFIX=$(printf '%s' "$RAW_PREFIX" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -c 'a-z0-9-' '-' \
  | sed -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//')
if [ -n "$SAFE_PREFIX" ]; then
  case "$NAME" in
    "$SAFE_PREFIX/"*) : ;;
    *) NAME="$SAFE_PREFIX/$NAME" ;;
  esac
fi
```

- [ ] **Step 3: Add the keystroke opt-out in `ai-rename-persist.sh`**

Replace EXACTLY:
```bash
INJECT_NOTE=""
if [ "$(uname)" = "Darwin" ]; then
```
with:
```bash
INJECT_NOTE=""
if [ -z "${AI_RENAME_NO_KEYSTROKE:-}" ] && [ "$(uname)" = "Darwin" ]; then
```

- [ ] **Step 4: Syntax + no personal strings**

```bash
cd ~/Projects/personal/claude-setup
bash -n ai-rename/scripts/ai-rename-collect.sh && bash -n ai-rename/scripts/ai-rename-persist.sh && echo "SYNTAX OK"
grep -rnI bernardo ai-rename/scripts/ && echo "FAIL: personal string" || echo "CLEAN"
diff ai-rename/scripts/ai-rename-collect.sh ~/.claude/scripts/ai-rename-collect.sh >/dev/null && echo "collect: IDENTICAL" || echo "collect: DIFF"
```
Expected: `SYNTAX OK`, `CLEAN`, `collect: IDENTICAL`.

> Do NOT commit — the controller commits.

---

## Task 2: Command file

**Files:**
- Create: `ai-rename/commands/ai-rename.md`

- [ ] **Step 1: Author `ai-rename/commands/ai-rename.md`**

Full content (note: the model must emit prefix-LESS names; persist adds the prefix):

`````markdown
---
description: Generate and apply an AI-summarized name for the current Claude Code session
allowed-tools: Bash(bash:*), Read
---

Generate a project-prefixed kebab-case name for the current session and apply it by directly editing the session metadata file.

**Before anything else, output the following banner verbatim as the very first thing in your response, then continue with the steps below:**

```
⚠️  Keep this Claude Code window focused — `/rename` keystrokes will be auto-typed in a few seconds (unless AI_RENAME_NO_KEYSTROKE is set).
```

Steps:

1. Run the collect script and parse its JSON output:

   ```bash
   bash ~/.claude/scripts/ai-rename-collect.sh
   ```

   The output looks like:

   ```json
   {
     "session_id": "...",
     "project": "funouts" | null,
     "branch": "channel-detail-bookings" | null,
     "transcript_path": "/Users/.../<session_id>.jsonl" | null,
     "user_message_count": 7,
     "user_messages": ["fix the timezone bug ...", "also handle DST ...", "..."],
     "truncated": false
   }
   ```

   **`transcript_path` is always available to you — use it freely whenever the digest doesn't clearly tell you what this session is about.** `user_messages` is a curated, capped digest of user turns (slash-command/system-reminder/task-notification wrappers stripped, each message capped at 1000 chars, total capped at 8000). Whenever you are even slightly unsure of the session's intent, `Read` `transcript_path` to see the full session JSONL — there is no penalty for reading too much; there is a real penalty for picking a bad name from thin context. **Always read the transcript when:**
   - `user_messages` is empty or contains only short/generic phrases ("yes", "ok", "go ahead", "do it"),
   - `truncated` is `true` and the visible portion doesn't make the topic obvious,
   - the messages span multiple topics and you can't tell which one was the actual work,
   - you'd otherwise have to guess.

2. Synthesize a name following these rules — do not deviate:

   - Format: `<project>/<topic>`.
   - **Do NOT add an operator prefix.** `ai-rename-persist.sh` prepends one automatically (`$AI_RENAME_PREFIX`, or your OS username by default), so emit only `<project>/<topic>`.
   - `<project>`:
     - Use the JSON `project` value when non-null.
     - When `project` is `null`, use `home`.
   - `<topic>`:
     - 2–4 kebab-case words capturing the session's intent.
     - Read `user_messages` as the session **arc**. Weigh the dominant theme across messages, not just the first — sessions often pivot mid-flight, and the last few messages frequently signal the topic that was actually worked on. The opening message is a strong hint, not a verdict.
     - If anything is ambiguous, `Read` `transcript_path` before deciding (see triggers above). Treat reading as the default, not the exception.
     - If even after reading the transcript no clear topic emerges and `branch` is set (and is not `main`, `master`, `HEAD`, or empty): kebab-case the branch (replace `/` and `_` with `-`) and use that.
     - If nothing yields a useful topic, use `exploration`.
   - Keep `<project>/<topic>` to about 40 characters or fewer. Lowercase, only `[a-z0-9-/]`, no quotes, no trailing punctuation, no leading slash. The persist script prepends the operator prefix and enforces a 50-char total.

   Examples:
   - `user_messages`: ["fix timezone bug in booking confirmation email", "also handle DST edge cases"], `project`: "funouts" → `funouts/timezone-booking-fix`
   - `user_messages`: ["look at this repo", "what's wrong?", "fix it"], `truncated`: true → read `transcript_path` to find the actual topic before naming.
   - `user_messages`: [], `project`: "omninode", `branch`: "main" → `omninode/exploration`
   - `user_messages`: [], `project`: "funouts", `branch`: "feat/qr-onboarding" → `funouts/feat-qr-onboarding`
   - `project`: null, `user_messages`: ["set up phone notifications via ntfy"] → `home/phone-notifications-ntfy`

3. Run the persist script with the generated name and relay its output verbatim:

   ```bash
   bash ~/.claude/scripts/ai-rename-persist.sh "<generated-name>"
   ```

Do not print the generated name as a separate message before calling persist — the persist script's own output is the canonical confirmation.
`````

- [ ] **Step 2: Verify no personal strings**

```bash
cd ~/Projects/personal/claude-setup
grep -rnI bernardo ai-rename/commands/ && echo "FAIL" || echo "CLEAN"
grep -q "Format: \`<project>/<topic>\`" ai-rename/commands/ai-rename.md && echo "FORMAT OK" || echo "FORMAT FAIL"
```
Expected: `CLEAN`, `FORMAT OK`.

> Do NOT commit — the controller commits.

---

## Task 3: INSTALL.md

**Files:**
- Create: `ai-rename/INSTALL.md`

- [ ] **Step 1: Author `ai-rename/INSTALL.md`**

Full content:

````markdown
# Install: ai-rename (AI session namer)

`/ai-rename` names the current Claude Code session from its content — a
`<project>/<topic>` slug, prefixed by your operator name. Manual, on-demand.

## Prerequisites
- **core installed** (see `../core/INSTALL.md`) — provides the session-id resolver
- `bash`, `jq`
- Optional: `git` (adds a branch-based topic fallback)
- Optional (macOS): `osascript` + Accessibility/Automation permission for the host
  terminal, so the rename also updates the **live** TUI title (see Config).

## 1. Place files
```bash
cp ai-rename/scripts/ai-rename-collect.sh ai-rename/scripts/ai-rename-persist.sh ~/.claude/scripts/
cp ai-rename/commands/ai-rename.md ~/.claude/commands/
chmod +x ~/.claude/scripts/ai-rename-collect.sh ~/.claude/scripts/ai-rename-persist.sh
```

## 2. Use
In any Claude Code session, run:
```
/ai-rename
```
It collects the session digest, synthesizes a `<project>/<topic>` name, writes it to
the session metadata + transcript, and (on macOS) auto-types `/rename <name>` so the
live title updates too.

## 3. Config (optional, via shell environment)
- `AI_RENAME_PREFIX` — operator prefix. Unset → your OS username (sanitized);
  `AI_RENAME_PREFIX=team` → `team`; `AI_RENAME_PREFIX=` (empty) → no prefix.
- `AI_RENAME_NO_KEYSTROKE=1` — skip the macOS keystroke injection (the on-disk
  rename still applies; refresh the live title by running `/rename <name>` yourself).

Set these in `~/.zshrc` (or equivalent) so the scripts inherit them.

## 4. Verify
Run `/ai-rename` in a session with a few messages; confirm the printed
`Renamed session ... -> <prefix>/<project>/<topic>` line, and that the new name
shows in the `/resume` picker (and your ntfy/statusline chips if installed).

## Uninstall
```bash
rm -f ~/.claude/scripts/ai-rename-collect.sh ~/.claude/scripts/ai-rename-persist.sh
rm -f ~/.claude/commands/ai-rename.md
```
(No `settings.json` changes were made.)
````

> Do NOT commit — the controller commits.

---

## Task 4: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add the module-table row**

Find EXACTLY:
```markdown
| [`consolidator`](consolidator/INSTALL.md) | On `Stop`, evaluates the transcript and consolidates long-term memory files. | Stop | no |
```
Add immediately after it:
```markdown
| [`ai-rename`](ai-rename/INSTALL.md) | `/ai-rename` — names the current session from its content (`<project>/<topic>`, prefixed by your username). Manual command. | — (slash command) | no (macOS only for live-TUI auto-sync) |
```

- [ ] **Step 2: Add the dependency line**

Find EXACTLY:
```markdown
- consolidator: optional OpenRouter key.
```
Add immediately after it:
```markdown
- ai-rename: `bash`, `jq`, `core`; optional `git` (branch hint), macOS + Accessibility permission for the live-TUI auto-sync.
```

- [ ] **Step 2b: Verify**

```bash
cd ~/Projects/personal/claude-setup
grep -q "ai-rename](ai-rename/INSTALL.md)" README.md && echo "ROW OK" || echo "ROW FAIL"
grep -q "^- ai-rename:" README.md && echo "DEPS OK" || echo "DEPS FAIL"
ls ai-rename/INSTALL.md && echo "LINK OK"
```
Expected: `ROW OK`, `DEPS OK`, `LINK OK`.

> Do NOT commit — the controller commits.

---

## Task 5: Verification

VERIFICATION ONLY — no production files. Never touch real sessions (tests use a fake `ttest` session id + a sandbox `CLAUDE_CONFIG_DIR`, and `AI_RENAME_NO_KEYSTROKE=1` so the terminal is never typed into).

**Files:** none

- [ ] **Step 1: persist prefix logic — three cases, end-to-end**

```bash
cd ~/Projects/personal/claude-setup
P=ai-rename/scripts/ai-rename-persist.sh
mk() { local d; d=$(mktemp -d); mkdir -p "$d/sessions"; echo '{"sessionId":"ttest","name":"old"}' > "$d/sessions/ttest.json"; printf '%s' "$d"; }

SB=$(mk); CLAUDE_CONFIG_DIR="$SB" CLAUDE_SESSION_ID=ttest AI_RENAME_NO_KEYSTROKE=1 bash "$P" "home/foo-bar" >/dev/null 2>&1
echo "unset    → $(jq -r .name "$SB/sessions/ttest.json")   (expect $(whoami | tr '[:upper:]' '[:lower:]')/home/foo-bar)"; rm -rf "$SB"

SB=$(mk); CLAUDE_CONFIG_DIR="$SB" CLAUDE_SESSION_ID=ttest AI_RENAME_PREFIX=team AI_RENAME_NO_KEYSTROKE=1 bash "$P" "home/foo-bar" >/dev/null 2>&1
echo "override → $(jq -r .name "$SB/sessions/ttest.json")   (expect team/home/foo-bar)"; rm -rf "$SB"

SB=$(mk); CLAUDE_CONFIG_DIR="$SB" CLAUDE_SESSION_ID=ttest AI_RENAME_PREFIX= AI_RENAME_NO_KEYSTROKE=1 bash "$P" "home/foo-bar" >/dev/null 2>&1
echo "empty    → $(jq -r .name "$SB/sessions/ttest.json")   (expect home/foo-bar)"; rm -rf "$SB"
```
Expected: `<whoami>/home/foo-bar`, `team/home/foo-bar`, `home/foo-bar` respectively.

- [ ] **Step 2: collect emits valid JSON**

```bash
cd ~/Projects/personal/claude-setup
OUT=$(CLAUDE_SESSION_ID=ttest bash ai-rename/scripts/ai-rename-collect.sh 2>/dev/null)
printf '%s' "$OUT" | jq -e '.session_id == "ttest"' >/dev/null && echo "COLLECT JSON: PASS" || echo "COLLECT JSON: FAIL"
```
Expected: `COLLECT JSON: PASS`.

- [ ] **Step 3: final sanity**

```bash
cd ~/Projects/personal/claude-setup
grep -rnI bernardo ai-rename/ && echo "FAIL: personal" || echo "CLEAN"
git status --short
```
Expected: `CLEAN`; `git status` shows new `ai-rename/` + modified `README.md` (controller commits).

---

## Self-Review

**Spec coverage:**
- Export collect (verbatim) + persist (genericized) + command → Tasks 1–2. ✓
- Prefix → `${AI_RENAME_PREFIX-$(whoami)}` sanitized, empty=none → Task 1 Step 2 + Task 5 Step 1 (three cases). ✓
- Keystroke opt-out `AI_RENAME_NO_KEYSTROKE` → Task 1 Step 3. ✓
- Command emits prefix-less `<project>/<topic>`; examples de-prefixed → Task 2. ✓
- Depends on core; command-only (no settings wiring) → INSTALL.md (Task 3). ✓
- README row + deps → Task 4. ✓
- Verification (prefix cases, collect JSON, grep clean, bash -n) → Tasks 1, 5. ✓

**Placeholder scan:** No TBD/TODO; full file contents for the command + INSTALL.md; exact old→new for the persist edits; concrete verification commands with expected output.

**Consistency:** `AI_RENAME_PREFIX` / `AI_RENAME_NO_KEYSTROKE` names, the `<project>/<topic>` format, and the `~/.claude/scripts` install paths are consistent across persist.sh, the command, INSTALL.md, and the verification. The persist test uses `AI_RENAME_NO_KEYSTROKE=1` (matching the opt-out env added in Task 1 Step 3) and `CLAUDE_CONFIG_DIR` (matching persist's session-file scan order).
