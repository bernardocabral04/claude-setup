---
description: Show or flip per-event ntfy push toggles (per-session by default, --global for defaults)
allowed-tools: Bash(bash:*)
argument-hint: [--session <id>] [--global] [event] [on|off|toggle]   |   [--session <id>] --session-clear <event>
---

Show or flip per-event ntfy push toggles. Layered scope:
- **session** (default) — overrides for the current session, written to `~/.claude/ntfy-sessions/<session_id>`.
- **global** (with `--global`) — defaults for any session that has no override, written to `~/.claude/ntfy.conf`.

By default the session scope means the *current* session. Pass `--session <id>` to target a different session id instead.

Resolution order at runtime: session > global > built-in default.

Events: `permission`, `stop`, `notify`, `toggle`, `session_start`, `session_end`, `subagent_stop`, `precompact`.

Forms:
- No args → list resolved state per event with scope tag.
- `<event>` → show resolved value + scope.
- `<event> <on|off|toggle>` → flip in current session.
- `--global <event> <on|off|toggle>` → flip global default.
- `--session-clear <event>` → remove the session override; falls back to global.
- `--session <id> ...` → apply any of the above to the given session id instead of the current one.

Run this and relay its output verbatim:

```bash
bash ~/.claude/scripts/ntfy-config-impl.sh $ARGUMENTS
```
