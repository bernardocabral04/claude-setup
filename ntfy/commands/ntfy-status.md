---
description: Show ntfy status for the current Claude Code session, or a target session by id
allowed-tools: Bash(bash:*)
argument-hint: [session-id]
---

Show whether ntfy phone notifications are enabled. With no argument, shows the current session. With a session id argument, shows that session instead. If enabled, also prints topic, server, subscribe URL, and an inline QR code, plus the per-event push toggles.

Run this and relay its output verbatim:

```bash
bash ~/.claude/scripts/ntfy-status-impl.sh $ARGUMENTS
```
