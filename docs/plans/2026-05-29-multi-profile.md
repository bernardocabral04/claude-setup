# multi-profile Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan. Steps use checkbox (`- [ ]`) syntax. This is a docs-only deliverable — streamlined (one implementer + spec review).

**Goal:** Add a `multi-profile/` documentation guide + sanitized `profiles.json.example` explaining the multi-`CLAUDE_CONFIG_DIR` setup; reference `clausona` rather than vendor it.

**Architecture:** Two new files under `multi-profile/` + a one-line pointer in the README's Conventions section. No program, no installable module.

**Tech Stack:** Markdown, JSON.

**Repo:** `~/Projects/personal/claude-setup`, branch `feat/multi-profile-docs`, base `1879354`.

---

## File Structure

```
multi-profile/
├── README.md              # the guide
└── profiles.json.example  # sanitized manifest
README.md                  # +1 pointer line in Conventions
```

---

## Task 1: Guide + example

**Files:**
- Create: `multi-profile/README.md`
- Create: `multi-profile/profiles.json.example`

- [ ] **Step 1: Create `multi-profile/profiles.json.example`**

Exact content:
```json
{
  "primarySource": "personal",
  "activeProfile": "personal",
  "profiles": {
    "personal": {
      "configDir": "~/.claude",
      "email": "you@example.com",
      "orgName": "Personal",
      "isPrimary": true
    },
    "work": {
      "configDir": "~/.claude-work",
      "email": "you@company.com",
      "orgName": "Your Company",
      "mergeSessions": false
    }
  }
}
```

- [ ] **Step 2: Create `multi-profile/README.md`**

Exact content:
````markdown
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
| **ntfy / tts / consolidator** | No — their `.conf` files and `*-sessions/` state live under `~/.claude` and are effectively shared across profiles. Installing them once covers all profiles; they don't keep separate per-profile config. |

If you need fully isolated notification/TTS/consolidator config per profile, that
isn't supported today (the scripts hardcode `~/.claude` for those paths).

## clausona (optional automation)

The author manages the above with a small CLI called `clausona` (an Ink/React TUI).
It isn't included in this repo, but for context it automates:
- switching the active profile (and the shell integration to launch under it),
- backing up and restoring each profile's `~/.claude.json` (so logins/config survive
  switches),
- per-profile usage/cost tracking.

Everything in this guide works without it — `clausona` is just convenience on top of
the `CLAUDE_CONFIG_DIR` convention and the `profiles.json` manifest.
````

- [ ] **Step 3: Verify the example is valid JSON + no personal data**

```bash
cd ~/Projects/personal/claude-setup
jq . multi-profile/profiles.json.example >/dev/null && echo "JSON OK" || echo "JSON FAIL"
grep -rnI -e bernardo -e belen -e "outlook.com" multi-profile/ && echo "FAIL: personal" || echo "CLEAN"
```
Expected: `JSON OK`, `CLEAN`.

> Do NOT commit — the controller commits.

---

## Task 2: README pointer

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Append the pointer to the Conventions bullet**

Replace EXACTLY:
```markdown
- The config dir is assumed to be the default `~/.claude`. `core`'s session-id
  resolver honors `CLAUDE_CONFIG_DIR`; the rest currently hardcode `~/.claude`.
```
with:
```markdown
- The config dir is assumed to be the default `~/.claude`. `core`'s session-id
  resolver honors `CLAUDE_CONFIG_DIR`; the rest currently hardcode `~/.claude`.
  To run multiple profiles (work/personal/etc.) on one machine, see
  [`multi-profile/`](multi-profile/README.md).
```

- [ ] **Step 2: Verify**

```bash
cd ~/Projects/personal/claude-setup
grep -q "multi-profile/README.md" README.md && echo "POINTER OK" || echo "POINTER FAIL"
ls multi-profile/README.md && echo "TARGET OK"
```
Expected: `POINTER OK`, `TARGET OK`.

> Do NOT commit — the controller commits.

---

## Task 3: Verification

**Files:** none

- [ ] **Step 1: Doc-claim spot-checks against the scripts**

Confirm the behavior-matrix claims are truthful:
```bash
cd ~/Projects/personal/claude-setup
grep -q "CLAUDE_CONFIG_DIR" core/scripts/_resolve-session-id.sh && echo "core honors CLAUDE_CONFIG_DIR: PASS" || echo "FAIL"
grep -q "CLAUDE_CONFIG_DIR" statusline/statusline-command.sh && echo "statusline detects profile: PASS" || echo "FAIL"
# ntfy/tts/consolidator confs are under ~/.claude (shared): expect matches, none honoring CLAUDE_CONFIG_DIR for conf
grep -c "HOME/.claude/ntfy.conf\|HOME/.claude/tts.conf\|HOME/.claude/consolidator.conf" ntfy/scripts/*.sh tts/scripts/*.sh consolidator/scripts/*.sh 2>/dev/null | grep -v ':0' | head
```
Expected: the two `PASS` lines; the conf paths resolve under `~/.claude` (confirming the "shared" claim).

> Note: this branch is off `main`, so `statusline/` only exists if PR #1 is merged.
> If `statusline/statusline-command.sh` is absent here, that check is N/A — the
> claim is still correct (verified in the statusline PR); skip it and note so.

- [ ] **Step 2: Final sanity**

```bash
cd ~/Projects/personal/claude-setup
grep -rnI -e bernardo -e belen multi-profile/ && echo "FAIL" || echo "CLEAN"
git status --short
```
Expected: `CLEAN`; `git status` shows new `multi-profile/` + modified `README.md`.

---

## Self-Review

**Spec coverage:**
- Guide (concept, config-dir convention, manifest schema, per-profile add-on matrix, clausona note) → Task 1 Step 2. ✓
- Sanitized profiles.json.example (generic names, placeholder email/org) → Task 1 Step 1. ✓
- README Conventions pointer → Task 2. ✓
- Verification (valid JSON, grep clean, doc-claim spot-checks) → Tasks 1, 3. ✓
- Out of scope (no clausona program; add-ons unchanged) → respected. ✓

**Placeholder scan:** No TBD/TODO; full content for both files; exact old→new for the README; concrete verification commands.

**Consistency:** The manifest fields in the guide table match `profiles.json.example` exactly (`activeProfile`, `primarySource`, `configDir`, `email`, `orgName`, `isPrimary`, `mergeSessions`). The per-profile matrix matches the documented `CLAUDE_CONFIG_DIR` behavior of the shipped modules (statusline/core/ai-rename honor it; ntfy/tts/consolidator confs under `~/.claude`).
