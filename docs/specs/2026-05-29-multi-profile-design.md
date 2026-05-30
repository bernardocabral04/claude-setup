# Design: `multi-profile` guide for `claude-setup`

**Date:** 2026-05-29
**Status:** Approved (design)
**Repo:** `~/Projects/personal/claude-setup` (public)

## Goal

Document the multi-profile (multiple `CLAUDE_CONFIG_DIR`) setup so anyone can
replicate it, plus a sanitized config example. **Docs only** — the author's
`clausona` CLI that automates it is referenced, not vendored (it is a standalone
Ink/React tool whose source is not in this repo, and its on-disk config holds
personal data + credential backups).

## Why docs-only

`clausona` ships only as a 1.9 MB esbuild bundle on the author's machine (no source
here); its runtime config (`~/.clausona/profiles.json`, `usage.json`,
`backups/*/.claude.json`) holds emails, org names, and credential backups. The
*program* is generic (reads `CLAUDE_CONFIG_DIR`), but vendoring a generated blob
into a public repo is undesirable. The reproducible, shareable part is the **setup**:
the config-dir convention, the `profiles.json` manifest schema, and how the
claude-setup add-ons behave under multiple profiles.

## Deliverables

```
multi-profile/
├── README.md              # the guide
└── profiles.json.example  # sanitized manifest example
```
Plus a one-line pointer appended to the top-level README's **Conventions &
assumptions** `CLAUDE_CONFIG_DIR` bullet. This is a guide, not an installable
module — no module-table row, no INSTALL.md.

## `multi-profile/README.md` — contents

1. **Concept** — run separate Claude Code identities (auth, history, settings) on
   one machine via the native `CLAUDE_CONFIG_DIR` env var. Each profile is a
   distinct config dir.
2. **Config-dir convention** — `~/.claude` = default/personal; `~/.claude-<name>` =
   other profiles. Launch one with `CLAUDE_CONFIG_DIR=~/.claude-work claude`; an
   optional shell alias is shown.
3. **`profiles.json` manifest** — the schema and a link to `profiles.json.example`:
   - `activeProfile` (string) — currently selected profile name.
   - `primarySource` (string) — the profile whose shared settings/overlays are the
     source of truth.
   - `profiles.<name>`: `configDir`, `email`, `orgName`, optional `isPrimary: true`,
     optional `mergeSessions: false`.
   Noted as the manifest the `clausona` CLI reads.
4. **How the claude-setup add-ons behave per-profile** (honest matrix):
   - **statusline** — shows the active profile chip (detects `CLAUDE_CONFIG_DIR`).
   - **core `_resolve-session-id.sh` + ai-rename (collect/persist)** — honor
     `CLAUDE_CONFIG_DIR`.
   - **ntfy / tts / consolidator** — installed once into `~/.claude/scripts`; their
     `.conf` files and `*-sessions/` state live under `~/.claude` and are effectively
     **shared** across profiles. Documented limitation, not changed here.
5. **clausona (optional automation)** — brief description of what it does (switch the
   active profile, back up/restore each profile's `.claude.json`, track per-profile
   usage/cost). The author's separate tool; the manual setup above works without it.

## `multi-profile/profiles.json.example` (sanitized)

```json
{
  "primarySource": "personal",
  "activeProfile": "personal",
  "profiles": {
    "personal": { "configDir": "~/.claude",      "email": "you@example.com", "orgName": "Personal",     "isPrimary": true },
    "work":     { "configDir": "~/.claude-work", "email": "you@company.com", "orgName": "Your Company", "mergeSessions": false }
  }
}
```
Generic profile names (drops `work-belen`), placeholder email/org. Tilde paths, with
a note in the guide that `clausona` stores absolute paths.

## README pointer

Append to the existing Conventions bullet
("The config dir is assumed to be the default `~/.claude`…") a sentence linking to
`multi-profile/README.md` for running multiple profiles.

## Verification

- `profiles.json.example` is valid JSON (`jq . parses`).
- `grep -rnI -e bernardo -e belen -e <real-email-domains>` in `multi-profile/` →
  clean.
- Guide's relative links resolve (`profiles.json.example`, the module `INSTALL.md`
  references it cites).
- Behavior-matrix claims spot-checked against the scripts: `_resolve-session-id.sh`
  references `CLAUDE_CONFIG_DIR`; `_validate-session-id.sh` and the
  ntfy/tts/consolidator confs use `~/.claude`.

## Out of scope

- Shipping the `clausona` program.
- Making ntfy/tts/consolidator per-profile (documented as a known limitation).
- Any change to existing modules.
