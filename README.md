# claude-setup

Modular, pick-and-choose add-ons for [Claude Code](https://claude.com/claude-code).
Three independent modules plus a small shared core. Each module installs by
following its `INSTALL.md` — an ordered runbook an agent (or you) can execute top
to bottom. Nothing is global until you install it; uninstall is documented per
module.

## Modules

| Module | What it does | Hooks | macOS-only? |
|--------|--------------|-------|-------------|
| [`core`](core/INSTALL.md) | Shared session-id helpers + idempotent `settings.json` hook merger. **Required by all others.** | — | no |
| [`ntfy`](ntfy/INSTALL.md) | Native macOS notifications (with the Claude icon, via an optional terminal-notifier wrapper) **and** phone push via [ntfy.sh](https://ntfy.sh) for every Claude Code event. | SessionStart/End, Stop, Notification, PermissionRequest, SubagentStop, PreCompact | native notif/icon are macOS; phone push is cross-platform |
| [`tts`](tts/INSTALL.md) | Speaks Claude's responses on `Stop` (Kokoro server or macOS `say`), LLM-cleaned. | Stop | yes (`say`/`afplay`) |
| [`consolidator`](consolidator/INSTALL.md) | On `Stop`, evaluates the transcript and consolidates long-term memory files. | Stop | no |
| [`statusline`](statusline/INSTALL.md) | Multi-line status bar: profile, model + context %, rate limits, cwd + git, and live TTS/Ntfy/Consolidator chips. **Standalone — no core needed.** | — (uses the `statusLine` setting) | yes (`stat -f`) |

## Install

1. Install **core** first: follow [`core/INSTALL.md`](core/INSTALL.md). (Every
   module needs it except `statusline`, which is standalone.)
2. Install any modules you want, in any order: follow that module's `INSTALL.md`.
3. Restart Claude Code so the new hooks / statusline load.

Each module runbook roughly follows: Prerequisites → Place files → Wire hook(s) →
Enable → Verify → Uninstall (some add an optional step — e.g. the tts extras or the
ntfy Claude-icon notifier).

## Conventions & assumptions

- Files install into `~/.claude/scripts/` (plus an `assets/` and/or `tests/` subdir
  for some modules) and `~/.claude/commands/` — the scripts call each other by
  absolute `~/.claude/scripts/...` path.
- The config dir is assumed to be the default `~/.claude`. `core`'s session-id
  resolver honors `CLAUDE_CONFIG_DIR`; the rest currently hardcode `~/.claude`.
- **No config files are shipped.** Each module's `*-enable` regenerates a clean
  `~/.claude/<module>.conf` on first run, so no API keys or personal topics live
  in this repo. Add an optional `OPENROUTER_API_KEY` yourself (tts + consolidator
  both fall back to `claude -p` without it).
- Hook wiring is additive and idempotent via `core/scripts/_merge-hook.sh` —
  installing one module never disturbs another's hooks, even though several share
  the `Stop` event.

## Dependencies

- All: `bash`, `jq`. ntfy/consolidator/tts also use `curl`.
- ntfy: ntfy phone app; optional `terminal-notifier` (auto-installed for the
  Claude-icon macOS notifier), `qrencode`, macOS `pbcopy`.
- tts: macOS (`say`, `afplay`), `python3`; optional Kokoro server, OpenRouter key,
  Karabiner-Elements (stop hotkeys).
- consolidator: optional OpenRouter key.
- statusline: `bash`, `jq`, `git`, macOS (`stat -f`); optional `fswatch` for the git ahead/behind daemon.

## Notices

- [`terminal-notifier`](https://github.com/julienXX/terminal-notifier) is MIT
  licensed (© Eloy Durán, Julien Blanchard). The ntfy module does not bundle it;
  `notifier-install.sh` builds a wrapper from your locally installed copy.
- `cc.icns` is the Claude logo (an Anthropic mark), included only for personal use
  to brand local notifications. Not affiliated with or endorsed by Anthropic.

## License

MIT for the scripts in this repo (see `LICENSE`). Third-party components retain
their own licenses (see Notices).
