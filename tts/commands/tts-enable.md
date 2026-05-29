---
description: Enable macOS text-to-speech playback of Claude responses for the current session (or a target session by id)
allowed-tools: Bash(bash:*)
argument-hint: [session-id]
---

Enable TTS. With no argument, targets the current session. With a session id argument, targets that session instead (the current session is left untouched). If the session id is not found in `~/.claude/sessions/`, the command aborts.

On Stop, the last assistant text turn is piped through a Haiku cleanup pass (strips code/tables/markdown) and then read aloud with macOS `say`. Bootstraps `~/.claude/tts.conf` on first use.

Run this and relay its output verbatim:

```bash
bash ~/.claude/scripts/tts-enable-impl.sh $ARGUMENTS
```
