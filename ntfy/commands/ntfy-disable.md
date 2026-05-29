---
description: Disable ntfy.sh phone notifications for the current Claude Code session (or a target session by id)
allowed-tools: Bash(bash:*)
argument-hint: [session-id]
---

Disable ntfy.sh phone notifications by removing the per-session flag file. With no argument, targets the current session. With a session id argument, targets that session instead. macOS notifications continue to fire.

Run this and relay its output verbatim:

```bash
bash ~/.claude/scripts/ntfy-disable-impl.sh $ARGUMENTS
```
