---
description: Enable ntfy.sh phone notifications for the current Claude Code session (or a target session by id)
allowed-tools: Bash(bash:*)
argument-hint: [session-id]
---

Enable ntfy.sh phone notifications. With no argument, targets the current session. With a session id argument, targets that session instead (the current session is left untouched).

Bootstraps `~/.claude/ntfy.conf` with a fresh random topic on first use, sets a per-session flag file at `~/.claude/ntfy-sessions/<session-id>`, prints the subscribe URL + QR, and sends a test push.

Run this and relay its output verbatim:

```bash
bash ~/.claude/scripts/ntfy-enable-impl.sh $ARGUMENTS
```
