# Multi-profile setup

Run several independent Claude Code identities — separate auth, history, settings,
and MCP config — on one machine, using Claude Code's native `CLAUDE_CONFIG_DIR`.
This guide describes the setup so you can reproduce it by hand; the author automates
it with a small CLI (`clausona`, see the end), but nothing here requires it.

## Concept

Claude Code keeps all its state under a single config directory (default `~/.claude`).
Point `CLAUDE_CONFIG_DIR` at a *different* directory and you get a clean, isolated
profile: its own login/account, history, settings, and projects. Switching profile
is just switching that env var.

## Config-dir convention

- `~/.claude` — the default / personal profile.
- `~/.claude-<name>` — any other profile (e.g. `~/.claude-work`).

Launch Claude Code under a profile:
```bash
CLAUDE_CONFIG_DIR=~/.claude-work claude
```
A convenience alias (add to `~/.zshrc`):
```bash
claude-work() { CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude "$@"; }
```
The first launch under a new config dir is a fresh Claude Code install — log in to
the account you want that profile to use.

## The `profiles.json` manifest

A manifest that names your profiles and records light metadata. See
[`profiles.json.example`](profiles.json.example). Schema:

| Field | Meaning |
|-------|---------|
| `activeProfile` | name of the currently selected profile |
| `primarySource` | the profile whose shared settings/overlays are treated as the source of truth |
| `profiles.<name>.configDir` | the profile's `CLAUDE_CONFIG_DIR` (the author's tool stores an absolute path; the example uses `~` for readability) |
| `profiles.<name>.email` | the account email for that profile (informational) |
| `profiles.<name>.orgName` | the org/label for that profile (informational) |
| `profiles.<name>.isPrimary` | `true` on the primary profile |
| `profiles.<name>.mergeSessions` | whether to merge this profile's sessions into the primary's `/resume` view |

This manifest is what the `clausona` CLI reads; by hand, it's simply a record of
which config dirs map to which accounts.

## How the claude-setup add-ons behave across profiles

The add-on scripts in this repo install **once** into `~/.claude/scripts` and are
shared by every profile. Their awareness of the active profile varies:

| Add-on | Per-profile aware? |
|--------|--------------------|
| **statusline** | Yes — shows a profile chip derived from `CLAUDE_CONFIG_DIR` (`~/.claude` → `personal`, else the dir's basename). |
| **core** `_resolve-session-id.sh`, **ai-rename** (collect/persist) | Yes — honor `CLAUDE_CONFIG_DIR` when resolving sessions/transcripts. |
| **ntfy / tts** | No — their `.conf` files and `*-sessions/` state live under `~/.claude` and are shared across profiles. Installing them once covers all profiles. |
| **consolidator** | Partial — its `.conf` and `consolidator-sessions/` state are shared under `~/.claude`, but the consolidated memory it writes goes to `$CLAUDE_CONFIG_DIR/projects/<project>/memory/MEMORY.md`, so **memory output is per-profile**. |

If you need fully isolated notification/TTS config per profile, that isn't supported
today (those scripts hardcode `~/.claude`). The consolidator shares its config and
session-tracking but writes consolidated memory under the active profile's config
dir, so each profile builds its own memory.

## clausona (optional automation)

The author manages the above with a small CLI called `clausona` (an Ink/React TUI).
It isn't included in this repo, but for context it automates:
- switching the active profile (and the shell integration to launch under it),
- backing up and restoring each profile's `~/.claude.json` (so logins/config survive
  switches),
- per-profile usage/cost tracking.

Everything in this guide works without it — `clausona` is just convenience on top of
the `CLAUDE_CONFIG_DIR` convention and the `profiles.json` manifest.
