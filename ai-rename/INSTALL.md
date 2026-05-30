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
