---
description: Show or set the TTS cleanup mode, Kokoro voice, and Kokoro speed — per-session by default, --global for defaults
allowed-tools: Bash(bash:*)
argument-hint: [--session <id>] [--global] [mode|voice|speed <value>]   |   [--session <id>] --session-clear [mode|voice|speed]
---

Show or change the TTS configuration. Layered scope:
- **session** (default) — overrides for the current session, written to `~/.claude/tts-sessions/<session_id>.conf`.
- **global** (with `--global`) — defaults for any session that has no override, written to `~/.claude/tts.conf`.

Pass `--session <id>` to target a different session id instead of the current one. If the session id is not found in `~/.claude/sessions/`, the command aborts.

Resolution order at runtime: session > global > built-in default.

**Keys**:
- `mode` — cleanup mode: `normal` (chatty ~400 chars), `summary` (1 sentence ≤20 words), `auto` (chip off noise, keep length ~600 chars). Default: `normal`.
- `voice` — Kokoro voice id. Default: `am_michael`. Full list: `/tts-config --help`.
- `speed` — Kokoro playback speed, range `[0.5, 2.0]`. Default: `1.0`.

The Apple `say` fallback voice and rate are not exposed here — edit `~/.claude/tts.conf` manually if you need them.

**Forms**:
- No args → show resolved mode + voice + speed with their scopes.
- `mode <normal|summary|auto>` → set cleanup mode for the current session.
- `voice <kokoro-voice-id>` → set the Kokoro voice for the current session.
- `speed <0.5-2.0>` → set Kokoro speed for the current session.
- `--global <key> <value>` → set the global default for any of the above keys.
- `--session-clear [key]` → drop the session override for `key` (default: `mode`). Falls back to global.
- `--session <id> ...` → apply any of the above to the given session id instead of the current one.

Run this and relay its output verbatim:

```bash
bash ~/.claude/scripts/tts-config-impl.sh $ARGUMENTS
```
