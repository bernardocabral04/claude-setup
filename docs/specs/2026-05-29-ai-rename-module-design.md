# Design: `ai-rename` module for `claude-setup`

**Date:** 2026-05-29
**Status:** Approved (design)
**Repo:** `~/Projects/personal/claude-setup` (public)

## Goal

Add a fifth module exporting the `/ai-rename` slash command — names the current
Claude Code session from its content — packaged the same agent-installable way as
the others. Genericize the personal operator prefix so it works for anyone.

## What `/ai-rename` does

Manual, on-demand. Flow:
1. `ai-rename-collect.sh` resolves the current session (via `core`'s
   `_resolve-session-id.sh`), reads the transcript, and emits JSON: `session_id`,
   `project` (basename of cwd, or null at `$HOME`), `branch`, `transcript_path`,
   and a capped digest of the user's messages (per-message 1000 chars, total 8000,
   slash-command/system wrappers stripped).
2. The model reads that digest (and the transcript if ambiguous) and synthesizes a
   `<project>/<topic>` kebab-case name.
3. `ai-rename-persist.sh "<name>"` prepends the operator prefix, validates
   `^[a-z0-9/-]{1,50}$`, writes `.name` into `~/.claude/sessions/<id>.json`,
   appends a `{type:"custom-title"}` line to the transcript JSONL (read by the
   `/resume` picker), and — on macOS — auto-types `/rename <name><Enter>` into the
   host terminal via AppleScript so the live TUI title and `/resume` picker refresh
   in the running process.

## Key properties

- **Command-only.** No hooks, no `.conf`, no daemon. Installs by copying scripts +
  the command file; commands are auto-discovered from `~/.claude/commands/` (no
  `settings.json` wiring).
- **Depends on `core`.** Both scripts call `~/.claude/scripts/_resolve-session-id.sh`.
  Documented as a prerequisite (like ntfy/tts/consolidator).
- **macOS live-sync is optional and degrades.** Off macOS, with no `osascript`, or
  when opted out, persist still writes on-disk state and tells the user to run
  `/rename <name>` manually; only the live in-process TUI title won't auto-refresh.

## Genericization (the content edits)

`ai-rename-collect.sh` is clean — copied verbatim. Two files change:

### `ai-rename-persist.sh` — operator prefix
Replace the hardcoded block:
```bash
PREFIX="bernardo/"
case "$NAME" in
  "$PREFIX"*) : ;;
  *) NAME="$PREFIX$NAME" ;;
esac
```
with a username-default, overridable, sanitized prefix:
- Source: `${AI_RENAME_PREFIX-$(whoami)}` — note the `-` (not `:-`) so an explicitly
  empty `AI_RENAME_PREFIX=` means "no prefix", while unset means "username".
- Sanitize the prefix to the allowed charset before use: lowercase, map any char
  outside `[a-z0-9-]` to `-`, collapse repeats, trim leading/trailing `-`. This
  guarantees the final name passes `^[a-z0-9/-]{1,50}$` even if the username has
  capitals/dots/spaces.
- If the sanitized prefix is empty, prepend nothing; else prepend `<prefix>/`
  (idempotent — skip if `$NAME` already starts with it).

### `ai-rename-persist.sh` — keystroke opt-out
Guard the existing AppleScript keystroke block with `AI_RENAME_NO_KEYSTROKE`: when
that env var is non-empty, skip injection (still print the "run `/rename` manually"
hint). Everything else (the macOS/TERM_PROGRAM detection, the osascript) unchanged.

### `commands/ai-rename.md` — naming rules + examples
The model can't know the runtime prefix, so it must generate a **prefix-less** name:
- Change the format to `<project>/<topic>` (drop the fixed `bernardo/` segment).
- State that `ai-rename-persist.sh` prepends the operator prefix automatically
  (`$AI_RENAME_PREFIX` or your username), so do NOT emit a prefix.
- Rewrite all examples to drop `bernardo/` (e.g.
  `bernardo/funouts/timezone-booking-fix` → `funouts/timezone-booking-fix`).
- Length budget: target `<project>/<topic>` ≤ ~40 chars (persist enforces the final
  ≤50 including the prefix). Keep the `project`=null→`home`, branch-fallback, and
  `exploration` rules, and the "read the transcript when unsure" guidance, intact.
- The "Keep this window focused — keystrokes will be auto-typed" banner stays
  (accurate when live-sync is on); note it can be disabled via `AI_RENAME_NO_KEYSTROKE`.

## Repo structure

```
ai-rename/
├── scripts/
│   ├── ai-rename-collect.sh    # verbatim
│   └── ai-rename-persist.sh    # genericized prefix + keystroke opt-out
├── commands/ai-rename.md       # genericized naming rules/examples
└── INSTALL.md
```

## INSTALL.md sections (no hook step)

1. **Prerequisites** — `core` installed; `bash`, `jq`; optional `git` (branch hint);
   macOS + `osascript` + terminal Accessibility permission for the optional live-TUI
   sync.
2. **Place files** — `cp ai-rename/scripts/* ~/.claude/scripts/`,
   `cp ai-rename/commands/* ~/.claude/commands/`, `chmod +x` the scripts.
3. **Use** — run `/ai-rename` in a session; the command collects, names, persists.
4. **Config** — `AI_RENAME_PREFIX` (default = your username; empty = no prefix);
   `AI_RENAME_NO_KEYSTROKE=1` to disable the macOS keystroke injection.
5. **Verify** — `/ai-rename` renames the session (visible in `/resume` and
   notifications); shell smoke for collect/persist.
6. **Uninstall** — remove the two scripts + the command file. (No settings changes.)

## README

Add an `ai-rename` row to the module table (manual command; needs core; macOS for
optional live-TUI sync) and a dependency line.

## Verification plan

- `bash -n` on both scripts.
- **persist prefix logic, end-to-end** in a sandbox: set `CLAUDE_CONFIG_DIR=<tmp>`,
  `CLAUDE_SESSION_ID=ttest`, create `<tmp>/sessions/ttest.json` =
  `{"sessionId":"ttest","name":"old"}`, run with `AI_RENAME_NO_KEYSTROKE=1` (no
  terminal interference) and assert the written `.name`:
  - unset `AI_RENAME_PREFIX` → `<sanitized-whoami>/home/foo`
  - `AI_RENAME_PREFIX=team` → `team/home/foo`
  - `AI_RENAME_PREFIX=` (empty) → `home/foo` (no prefix)
  (Relies on the live `~/.claude/scripts/_resolve-session-id.sh`, which returns
  `CLAUDE_SESSION_ID` directly when set.)
- **collect** emits valid JSON: `CLAUDE_SESSION_ID=ttest bash ai-rename-collect.sh | jq .`
  parses and `session_id == "ttest"`.
- `grep -rnI bernardo ai-rename/` → clean.
- `server`-style live-TUI keystroke path is NOT exercised in automated tests
  (requires a focused GUI terminal); documented as a manual check.

## Out of scope

- The naming heuristic / prompt wording (kept as-is, only de-prefixed).
- An auto-rename hook (the feature stays manual).
- Other `~/.claude` scripts.
