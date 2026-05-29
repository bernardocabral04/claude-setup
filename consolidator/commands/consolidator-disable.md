---
description: Disable the per-message memory consolidator for the current Claude Code session (or a target session by id)
allowed-tools: Bash(bash:*)
argument-hint: [session-id]
---

Disable the consolidator by removing the per-session flag file. With no argument, targets the current session. With a session id argument, targets that session instead. The project's memory directory is untouched.

Run this and relay its output verbatim:

```bash
bash ~/.claude/scripts/consolidator-disable-impl.sh $ARGUMENTS
```
