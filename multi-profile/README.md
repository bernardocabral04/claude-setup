# Multi-profile setup

Run several independent Claude Code identities — separate auth, history, settings,
and MCP config — on one machine, using Claude Code's native `CLAUDE_CONFIG_DIR`.

Two layers:
- **The mechanism** — `CLAUDE_CONFIG_DIR` points Claude Code at a different config
  directory per profile. You can drive this by hand (see *Manual*).
- **The automation** — [`clausona`](https://github.com/larcane97/clausona), a
  community profile manager, wraps the mechanism: it discovers accounts, switches
  the active profile, shares your common config across profiles via symlinks, and
  tracks per-profile usage. This is the recommended path and is documented first.

## Concept

Claude Code keeps all its state under a single config directory (default `~/.claude`).
Point `CLAUDE_CONFIG_DIR` at a *different* directory and you get a clean, isolated
profile: its own login/account, history, settings, and projects. Switching profile
is just switching that env var — which is exactly what clausona automates.

## Recommended: clausona

[`clausona`](https://github.com/larcane97/clausona) is a third-party CLI (not part of
this repo). It is **installed from upstream**, not vendored here.

### Prerequisites
- Node.js ≥ 20
- macOS with `zsh`
- Claude Code already installed and logged in to at least one account

### Install
```bash
curl -fsSL https://github.com/larcane97/clausona/releases/latest/download/install.sh | bash
```
This installs the `clausona` CLI (and a `csn` shorthand). Re-check the
[upstream README](https://github.com/larcane97/clausona) for the current command —
this repo only documents how it fits the setup, it doesn't ship it.

### One-time setup
```bash
clausona init                       # discover accounts you're already logged into
eval "$(clausona shell-init)"       # enable the shell wrapper for this session
```
Add the `shell-init` line to your `~/.zshrc` so it persists:
```bash
# ~/.zshrc
eval "$(clausona shell-init)"
```
`shell-init` wraps the `claude` command so it launches under whatever profile is
currently active (`clausona use <name>`), and records usage afterward.

### Add & configure profiles
```bash
clausona add work                   # register a new profile named "work"
clausona login work                 # authenticate it (opens the Claude login)
clausona config work                # edit that profile's settings (email, org, options)
```
`config` writes to clausona's manifest at `~/.clausona/profiles.json` (schema below).
You normally don't hand-edit it — `add`/`config` manage it for you.

### Daily use
| Command | What it does |
|---------|--------------|
| `clausona use <name>` | Set the active profile (plain `claude` then uses it) |
| `clausona run <name>` | Launch Claude under `<name>` once, without changing the active profile |
| `clausona current` | Show the active profile |
| `clausona list` | List profiles + usage |
| `clausona usage [name]` | Usage/cost summary |
| `clausona` | Open the interactive dashboard |

Quick zsh launchers for each profile (add to `~/.zshrc`). Naming convention:
`cc<profile-initial>` runs that profile; a trailing **`y`** ("yes") adds
`--dangerously-skip-permissions` for an unattended session:
```bash
# ~/.zshrc — one-keystroke profile launches via `clausona run`
ccp()  { clausona run personal "$@"; }                                   # personal
ccpy() { clausona run personal --dangerously-skip-permissions "$@"; }    # personal, skip perms
ccw()  { clausona run work "$@"; }                                       # work
ccwy() { clausona run work --dangerously-skip-permissions "$@"; }        # work, skip perms
```
Each wraps `clausona run <profile>`, so the launch goes through clausona's profile
switching (and usage tracking) rather than bypassing it. Add one pair per profile
you keep.

### Maintenance
| Command | What it does |
|---------|--------------|
| `clausona doctor` | Health-check all profiles |
| `clausona repair <name>` | Restore a profile's shared symlinks (see *Sharing model*) |
| `clausona login <name>` | Re-authenticate a profile |
| `clausona remove <name>` | Remove a profile |
| `clausona uninstall` | Remove clausona entirely |

### Sharing model (why these add-ons "just work" across profiles)
clausona keeps one profile as the **primary** (your `~/.claude`) and **symlinks the
shared parts** of every other profile back to it: `skills/`, `agents/`, `commands/`,
`scripts/`, `settings.json`, `statusline-command.sh`, and the plugin *payload*
(`plugins/cache`, `plugins/data`, …). Only these are **independent per profile**:
- auth — `.claude.json`
- sessions/history — `projects/`
- the plugin install registry — `installed_plugins.json`, `known_marketplaces.json`

Because the claude-setup add-ons live in the shared `scripts/` (and `commands/`,
`settings.json`), **installing them once into the primary profile covers every
profile.** (Caveat: per-profile *plugin enablement* isn't supported upstream —
plugins share their payload across profiles.)

## The `profiles.json` manifest

clausona stores its profiles at `~/.clausona/profiles.json`. See
[`profiles.json.example`](profiles.json.example). Schema:

| Field | Meaning |
|-------|---------|
| `activeProfile` | name of the currently selected profile |
| `primarySource` | the profile whose shared config the others symlink to (the primary) |
| `profiles.<name>.configDir` | the profile's `CLAUDE_CONFIG_DIR` (clausona stores an absolute path; the example uses `~` for readability) |
| `profiles.<name>.email` | the account email for that profile (informational) |
| `profiles.<name>.orgName` | the org/label for that profile (informational) |
| `profiles.<name>.isPrimary` | `true` on the primary profile |
| `profiles.<name>.mergeSessions` | whether to merge this profile's sessions into the primary's `/resume` view |

## Manual (without clausona)

The same isolation works by hand — clausona is convenience on top of this.

Config-dir convention:
- `~/.claude` — the default / primary profile.
- `~/.claude-<name>` — any other profile (e.g. `~/.claude-work`).

Launch Claude Code under a profile:
```bash
CLAUDE_CONFIG_DIR=~/.claude-work claude
```
A convenience function (add to `~/.zshrc`):
```bash
claude-work() { CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude "$@"; }
```
The first launch under a new config dir is a fresh Claude Code install — log in to
the account you want that profile to use. Without clausona's symlinks, each profile
is fully independent (you'd re-install skills/scripts/settings per profile, or
symlink them yourself).

## How the claude-setup add-ons behave across profiles

The add-on scripts in this repo install **once** into `~/.claude/scripts` (shared by
every profile via clausona's symlinks, or only the primary if you went manual).
Their awareness of the *active* profile varies:

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
