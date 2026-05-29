---
description: Show TTS state for the current Claude Code session, or a target session by id
allowed-tools: Bash(bash:*)
argument-hint: [session-id]
---

Show whether TTS is enabled, plus current voice/rate/model and the last cleaned narration that was spoken. With no argument, shows the current session. With a session id argument, shows that session instead. If the session id is not found in `~/.claude/sessions/`, the command aborts.

Run this and relay its output verbatim:

```bash
bash ~/.claude/scripts/tts-status-impl.sh $ARGUMENTS
```
