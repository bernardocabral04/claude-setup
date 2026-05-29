# Design: `statusline` module for `claude-setup`

**Date:** 2026-05-29
**Status:** Approved (design); pending spec review
**Repo:** `~/Projects/personal/claude-setup` (public)

## Goal

Add a fourth installable module to `claude-setup` that exports the existing
`statusline-command.sh` (a multi-line Claude Code status bar) plus its two
background daemons, packaged the same agent-installable way as the other modules.
The statusline is exported **as-is** — appearance and content are not redesigned,
only packaged and genericized for a public repo.

## What the statusline shows

- **Line 1:** profile chip (`⬡ personal`), model + window size + mode
  (`✳ Opus 4.7 1M (high)`), context usage (`◷ 3% (~30k)`), rate limits
  (`⧗ 5h:… 7d:…` with reset countdowns), session id (`⌗ <id>`).
- **Line 2:** cwd (`▸ ~/path/`), git branch + dirty + ahead/behind
  (`⎇ (main*) ↑1 ↓2`) or `⌀ No Git`.
- **Line 3 (only when active):** per-session chips for TTS, Ntfy, Consolidator,
  each reflecting live pipeline state (e.g. `▶ TTS (normal) · speaking 3s`,
  `⏳ Ntfy · sending…`, `💾 Consolidator · saved <slug>`).
- **Line 4 (only when degraded):** network status (`✗ Not connected`,
  `⚠ Slow connection`, `✔ Reconnected`).

Colors escalate by threshold (context/rate-limit percentages turn yellow ≥70%,
bold red ≥90%).

## Key properties

### Standalone (no `core` dependency)
The statusline reads `session_id` from its stdin JSON; it never calls
`_merge-hook.sh` or the `core` session-id helpers. So — unlike ntfy/tts/
consolidator — **statusline installs without `core`.**

### Soft integration with the other three modules
Line-3 chips are keyed on the same per-session flag files the other modules'
`*-enable` commands create:
- TTS: `~/.claude/tts-sessions/<id>` (+ `.state`, `.pid`, `.conf`, `~/.claude/tts.conf`)
- Ntfy: `~/.claude/ntfy-sessions/<id>` (+ `.state`)
- Consolidator: `~/.claude/consolidator-sessions/<id>` (+ `.state`)

If a module isn't installed/enabled, its flag files don't exist and the chip
simply doesn't render. No hard dependency; the statusline gets richer as you add
the other modules.

### Two optional background daemons (both shipped)
- `git-watch-daemon.sh` — keeps `@{upstream}` fresh via `git ls-remote` (no object
  download) + `fswatch` on `.git/`, so ahead/behind (`↑n ↓n`) reflects the remote.
  The statusline spawns it (per-repo singleton, self-exits on idle) only when the
  script is present and executable. Requires `fswatch`.
- `network-daemon.sh` — pings `1.1.1.1` and writes a state file the statusline
  reads for line 4. Self-singleton, spawned by the statusline if not running.
  Requires `ping` (universal).

Both are clean of personal data and copied verbatim. Both degrade gracefully:
without git-watch, ahead/behind still updates on manual fetch; without
network-daemon, line 4 never appears.

## Repo structure

```
statusline/
├── statusline-command.sh      # main script → installs to ~/.claude/statusline-command.sh
├── scripts/
│   ├── git-watch-daemon.sh    # → ~/.claude/scripts/  (needs fswatch)
│   └── network-daemon.sh      # → ~/.claude/scripts/
└── INSTALL.md
```

No `commands/` — there are no statusline slash commands. The main script installs
to `~/.claude/statusline-command.sh` (the conventional location settings.json
points at); the daemons install to `~/.claude/scripts/` because the statusline
references them there by absolute path.

## Wiring (the `statusLine` settings key, not hooks)

`_merge-hook.sh` does not apply — the statusline is configured via the
`settings.json` `statusLine` object. INSTALL.md sets it with a backed-up,
idempotent jq command:

```bash
SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)-$RANDOM"
tmp=$(mktemp)
jq '.statusLine = {type:"command", command:"bash ~/.claude/statusline-command.sh", refreshInterval:1}' \
  "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
```

Uninstall removes it with `del(.statusLine)` (same backup pattern). Setting is
idempotent (re-running yields identical settings.json).

## Genericization (the only content edit)

The profile chip (statusline-command.sh ~lines 110–115) hardcodes the author's
profiles `work` and `work-belen` (a person's name). Collapse to generic detection:

```bash
case "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" in
  "$HOME/.claude") prof="personal";   prof_color="38;2;181;137;255" ;;
  *)               prof="$(basename "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")"; prof_color="90" ;;
esac
```

Keeps multi-profile awareness (basename for any non-default config dir) without
shipping personal profile names. No other content changes. Both daemons ship
verbatim (already personal-data-free).

## Dependencies

- statusline: `bash`, `jq`, `git`, macOS (`stat -f %m`, `date`, `awk`, `shasum`).
- git-watch daemon (optional): `fswatch` (`brew install fswatch`).
- network daemon (optional): `ping`.

## INSTALL.md sections

1. **Prerequisites** — `bash`, `jq`, `git`, macOS. (core NOT required.)
2. **Place files** — copy `statusline-command.sh` → `~/.claude/`; copy daemons →
   `~/.claude/scripts/`; `chmod +x` all three.
3. **Wire** — jq-set the `statusLine` key (command above). Restart Claude Code.
4. **Optional daemons** — `brew install fswatch` then nothing else (statusline
   auto-spawns git-watch when present); network daemon auto-spawns, no setup.
5. **Verify** — the status bar appears; pipe a sample JSON to confirm rendering.
6. **Uninstall** — `del(.statusLine)`; remove the three scripts; note the daemons
   self-exit on idle and their caches live under `~/.claude/cache/`.

## Verification plan

- `bash -n` on all three scripts.
- **Render test:** pipe a crafted sample stdin JSON (model, context %, rate limits,
  cwd) into `statusline-command.sh` and assert it emits line 1 (model/context/
  limits/session) and line 2 (path/git) without error — a concrete behavioral check.
- jq `statusLine` set is idempotent (run twice → identical); `del` removes it and
  leaves other settings untouched.
- `grep -rnI "bernardo" statusline/` → clean (profile chip genericized; `belen`
  gone).
- No secrets (consistent with the rest of the repo — no confs shipped).

## README update

Add a `statusline` row to the module table (note: standalone, no core required;
soft-integrates with the other three) and to the Dependencies list (`fswatch`
optional for git-watch).

## Out of scope

- Redesigning the statusline's content or appearance (exported as-is).
- Any other `~/.claude` scripts (ai-rename, open-project, migrate-session, etc.).
- Making `stat`/`date` cross-platform — macOS assumption documented, consistent
  with the other modules.

## Open questions

None blocking.
