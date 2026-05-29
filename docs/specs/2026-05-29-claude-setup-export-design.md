# Design: `claude-setup` — modular export of ntfy / TTS / consolidator

**Date:** 2026-05-29
**Status:** Approved (design); pending spec review
**Repo:** `~/Projects/personal/claude-setup` (public, GitHub)

## Goal

Export three Claude Code add-ons from a personal `~/.claude/` setup into a public,
**genuinely reusable** repo. Each add-on must be **independently installable**
("pick and choose") by following an **agent-followable runbook** (`INSTALL.md`).
No standalone installer script — the runbook is the install mechanism.

The three subsystems:

- **ntfy** — phone push notifications via [ntfy.sh](https://ntfy.sh). A central
  `notify.sh` hooks *every* Claude Code event (Stop, Notification,
  PermissionRequest, SessionStart/End, SubagentStop, PreCompact) and pushes to a
  per-user topic. Per-event and per-session toggles.
- **tts** — speaks Claude's responses on `Stop` via macOS `say` or a local Kokoro
  TTS server; LLM-cleans the text first (OpenRouter fast-path, or `claude -p`
  fallback). Per-session/global config for voice, rate, cleanup mode.
- **consolidator** — on `Stop`, evaluates the session transcript and consolidates
  long-term memory files (the `~/.claude/projects/.../memory/` layout). Cheap
  gating pre-checks before any LLM call. Ships with a test suite.

## Key facts that shape the design

1. **No cross-module runtime dependencies.** TTS and consolidator never call
   `notify.sh` or anything ntfy — verified by grep; the only mentions are
   comments. The three modules are fully independent at runtime.
2. **The only shared code** is two session-id helpers used by all three modules'
   enable/disable/status/config scripts:
   - `_resolve-session-id.sh` — resolves the current session id from a child
     shell (env var, else walks the process tree). Already honors
     `CLAUDE_CONFIG_DIR`.
   - `_validate-session-id.sh` — validates a given session id against
     `~/.claude/sessions/*.json`.
3. **Secrets never have to travel.** The live `~/.claude/tts.conf` contains a real
   `OPENROUTER_API_KEY` and `ntfy.conf` a personal topic, but these are *user
   state*. The `*-enable` scripts **self-generate clean `.conf` files** on first
   run (`OPENROUTER_API_KEY=` empty, generic voice, fresh random ntfy topic).
   Therefore: **export the scripts, never the live `.conf` files.** No secret
   sanitization is required because no conf is committed.
4. **Hooks are wired in a single shared `settings.json`.** `Stop` is shared by all
   three modules. Installing a module means an **additive, idempotent merge** of
   hook entries — never overwrite, never duplicate.

## Approaches considered

- **(A) By-module repo — CHOSEN.** Top-level `core/`, `ntfy/`, `tts/`,
  `consolidator/`, each self-contained with its own `scripts/`, `commands/`,
  `INSTALL.md`. Maps 1:1 to "pick and choose."
- **(B) By-type, mirroring `~/.claude`.** Top-level `scripts/` + `commands/` with
  everything mixed. Mirrors install target but a module's footprint isn't visible
  at a glance; pick-and-choose is muddier. Rejected.
- **(C) Single monolithic installer doc.** Simplest to write, worst for
  modularity. Rejected.

## Repo structure

```
claude-setup/
├── README.md                  # what this is, module table, shared prereqs, pick-and-choose
├── docs/specs/                # this design doc
├── core/
│   ├── scripts/               # _resolve-session-id.sh, _validate-session-id.sh
│   └── INSTALL.md             # required by all three; idempotent
├── ntfy/
│   ├── scripts/               # notify.sh, ntfy-push.sh, ntfy-{enable,disable,status,config}-impl.sh
│   ├── commands/              # ntfy-{enable,disable,status,config}.md
│   └── INSTALL.md
├── tts/
│   ├── scripts/               # tts-speak.sh, tts-{enable,disable,status,config}-impl.sh,
│   │                          #   tts-kokoro-{install,uninstall}.sh, tts-stop-*.sh, tts-clean-prompt-*.txt
│   ├── commands/              # tts-{enable,disable,status,config}.md
│   └── INSTALL.md
└── consolidator/
    ├── scripts/               # consolidator-hook.sh, consolidator-lib.sh,
    │                          #   consolidator-{enable,disable,status,now,config}-impl.sh,
    │                          #   consolidator-eval-prompt.txt, tests/
    ├── commands/              # consolidator-{enable,disable,status,now,config}.md
    └── INSTALL.md
```

Repo subdirs are **organizational only**. Every install flattens files into
`~/.claude/scripts/` and `~/.claude/commands/`, because the scripts call each
other via hardcoded `~/.claude/scripts/...` paths.

## The `INSTALL.md` runbook contract

Every module's `INSTALL.md` is an ordered, agent-followable runbook with the same
six sections, executable top to bottom:

1. **Prerequisites** — what must exist first (e.g. `core` installed; macOS for TTS;
   `jq` for all; `qrencode` optional for ntfy). Each module runbook starts with
   "ensure `core/INSTALL.md` has been run."
2. **Place files** — `cp <module>/scripts/* ~/.claude/scripts/` and
   `cp <module>/commands/* ~/.claude/commands/`, then `chmod +x` the `.sh` files.
3. **Wire hooks** — merge this module's hook entries into `~/.claude/settings.json`
   (see merge step below). The runbook lists the exact event→command entries it
   owns.
4. **Enable** — run the `enable` impl (or the `/<module>-enable` slash command) to
   self-bootstrap the `.conf` and fire a test (test push / test speech).
5. **Verify** — concrete check (ntfy: push arrives on phone; TTS: hear test
   speech; consolidator: `/consolidator-status` shows enabled).
6. **Uninstall** — reverse: remove the hook entries, delete the
   scripts/commands/conf/session-dirs.

## The hook-merge step (the crux)

Hooks live in a single shared `settings.json`; `Stop` is shared by all three
modules. The merge must be **additive and idempotent** — never overwrite, never
duplicate. Each runbook will:

- Specify exactly which event matchers + commands it owns:
  - **ntfy** owns `notify.sh` on 7 events:
    - `SessionStart → bash ~/.claude/scripts/notify.sh session_start`
    - `SessionEnd → bash ~/.claude/scripts/notify.sh session_end`
    - `PermissionRequest → bash ~/.claude/scripts/notify.sh permission`
    - `Stop → bash ~/.claude/scripts/notify.sh stop`
    - `Notification → bash ~/.claude/scripts/notify.sh notify`
    - `SubagentStop → bash ~/.claude/scripts/notify.sh subagent_stop`
    - `PreCompact → bash ~/.claude/scripts/notify.sh precompact`
  - **tts** owns `Stop → bash ~/.claude/scripts/tts-speak.sh`.
  - **consolidator** owns `Stop → bash ~/.claude/scripts/consolidator-hook.sh`.
- Provide the agent a **jq merge recipe** that, per event, ensures a
  `matcher:"*"` group exists and appends the command hook only if that exact
  command isn't already present in its `hooks` array. Idempotent: re-running is a
  no-op. Back up `settings.json` first.

A pre-existing `SessionStart → session-start.sh` entry (not part of these modules)
must be left untouched — the merge is keyed on exact command string.

## Genericization & portability

Target audience: **genuinely reusable**, primary platform macOS.

- **One source edit:** `ntfy-enable-impl.sh` hardcodes
  `NTFY_TOPIC=claude-bernardo-$RAND` → change to `claude-$RAND`. The only personal
  string baked into the scripts.
- **README documents macOS deps:** `say`, `afplay`, `pbcopy` (TTS + ntfy clipboard
  convenience), optional Kokoro server + `qrencode`. Linux notes where trivial.
- **Config dir:** scripts assume `~/.claude`. `core`'s `_resolve-session-id.sh`
  already honors `CLAUDE_CONFIG_DIR`; the rest hardcode `~/.claude`. Documented as
  an assumption rather than rewritten (scope control). Full `CLAUDE_CONFIG_DIR`
  support noted as optional future enhancement.
- **No `.conf` files exported** — they are user state; `*-enable` regenerates clean
  ones. So no live API key or personal topic reaches the repo. README explains
  where to add an optional OpenRouter key (both TTS and consolidator fall back to
  `claude -p`).

## Out of scope (explicit)

Everything else in `~/.claude/scripts` — `ai-rename`, statusline, `open-project`,
`git-watch-daemon`, `migrate-session`, `network-daemon`, etc. Only ntfy, TTS,
consolidator, and the shared core.

## Verification plan

Dry-run each module's runbook into a throwaway config dir (temp
`CLAUDE_CONFIG_DIR` or sandbox `HOME`) to confirm: files land, jq hook-merge is
idempotent (run twice → identical settings.json), `enable` bootstraps a clean
conf, and `uninstall` fully reverses. The consolidator's existing test suite ships
with that module and is run as part of its verification.

## Open questions

None blocking. Optional future enhancement: make all scripts honor
`CLAUDE_CONFIG_DIR`.
