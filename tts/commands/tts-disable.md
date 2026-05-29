---
description: Disable TTS playback for the current Claude Code session (or a target session by id)
allowed-tools: Bash(bash:*)
argument-hint: [session-id]
---

Disable TTS and kill any in-flight speech. With no argument, targets the current session. With a session id argument, targets that session instead. If the session id is not found in `~/.claude/sessions/`, the command aborts. Other sessions are unaffected.

Run this and relay its output verbatim:

```bash
bash ~/.claude/scripts/tts-disable-impl.sh $ARGUMENTS
```
