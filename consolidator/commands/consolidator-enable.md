---
description: Enable per-message memory consolidator for the current Claude Code session (or a target session by id)
allowed-tools: Bash(bash:*)
argument-hint: [session-id]
---

Enable the consolidator. With no argument, targets the current session. With a session id argument, targets that session instead (current session left untouched). Bootstraps `~/.claude/consolidator.conf` with defaults on first call, creates the per-cwd memory dir under the profile's Claude config dir (`~/.claude/projects/<cwd>/memory/` for the personal/primary profile, or the active clausona profile's equivalent), and prints a summary.

Run this and relay its output verbatim:

```bash
bash ~/.claude/scripts/consolidator-enable-impl.sh $ARGUMENTS
```
