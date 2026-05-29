---
description: Show or set consolidator settings — per-session by default, --global for defaults
allowed-tools: Bash(bash:*)
argument-hint: [--session <id>] [--global] [key value]   |   [--session <id>] --session-clear <key>
---

Show or change consolidator settings. Layered scope mirrors `/ntfy-config` / `/tts-config`:

- **session** (default) — overrides for the current session, written to `~/.claude/consolidator-sessions/<id>`.
- **global** (`--global`) — defaults for any session, written to `~/.claude/consolidator.conf`.

**Keys:** `engine`, `cooldown_sec`, `min_new_bytes`, `openrouter-model`, `claude-model`, `max_decisions_per_run`, `enabled_types`, `max_failed_attempts`.

**`engine` values:** `auto` (default — OpenRouter if `OPENROUTER_API_KEY` set, else `claude -p`), `openrouter` (strict — error if key missing), `claude` (force `claude -p`, ignore API key).

**Two equivalent syntaxes:**

```bash
# Positional, single key:
bash ~/.claude/scripts/consolidator-config-impl.sh <key> <value>

# Named flags, multi-key in one call:
bash ~/.claude/scripts/consolidator-config-impl.sh --engine X --openrouter-model Y --claude-model Z
```

Run this and relay its output verbatim:

```bash
bash ~/.claude/scripts/consolidator-config-impl.sh $ARGUMENTS
```
