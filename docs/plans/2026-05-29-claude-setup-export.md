# claude-setup Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export ntfy, TTS, and consolidator add-ons from `~/.claude/` into a public, modular, agent-installable repo at `~/Projects/personal/claude-setup`.

**Architecture:** By-module layout (`core/`, `ntfy/`, `tts/`, `consolidator/`). Each module ships verbatim scripts + slash-command defs + a six-section `INSTALL.md` runbook. Files install flat into `~/.claude/scripts` and `~/.claude/commands`. Hook wiring into the shared `settings.json` is done by an idempotent helper `_merge-hook.sh` (part of `core`). No `.conf` files are exported — `*-enable` scripts regenerate clean ones, so no secrets travel.

**Tech Stack:** bash, jq, macOS (`say`/`afplay`/`pbcopy`), ntfy.sh, optional Kokoro TTS server, optional Karabiner-Elements, OpenRouter/`claude -p`.

**Source of truth for copied files:** `~/.claude/scripts/` and `~/.claude/commands/` on this machine. The repo already exists with git initialized and the design spec committed.

**Genericization edits (the only content changes to copied scripts):**
1. `ntfy-enable-impl.sh`: `NTFY_TOPIC=claude-bernardo-$RAND` → `NTFY_TOPIC=claude-$RAND`
2. `tts-kokoro-install.sh` + `tts-kokoro-uninstall.sh`: `com.bernardo.claude-tts-kokoro` → `com.claude.tts-kokoro` (must match in both)
3. `consolidator-lib.sh` line ~8: replace the `-Users-bernardo` example path in the comment with a generic `-Users-you` example

The Claude-icon notifier bundle ID (`com.bernardo.claudecode.notifier` in the live bundle) is **not** a copied-file edit — the prebuilt bundle is not committed. Instead `notifier-install.sh` (authored in Task 3) builds the bundle from the user's local `terminal-notifier` and writes a generic bundle ID `com.claude.code.notifier`. `notify.sh` references the bundle by path (`~/.claude/apps/Claude Code Notifier.app/...`), not by ID, so it ships verbatim with no edit.

---

## File Structure

```
claude-setup/
├── README.md
├── .gitignore
├── docs/specs/2026-05-29-claude-setup-export-design.md   (exists)
├── docs/plans/2026-05-29-claude-setup-export.md          (this file)
├── core/
│   ├── scripts/_resolve-session-id.sh
│   ├── scripts/_validate-session-id.sh
│   ├── scripts/_merge-hook.sh        (NEW — authored here)
│   └── INSTALL.md
├── ntfy/
│   ├── scripts/{notify.sh, ntfy-push.sh, ntfy-enable-impl.sh, ntfy-disable-impl.sh, ntfy-status-impl.sh, ntfy-config-impl.sh,
│   │            notifier-install.sh, notifier-uninstall.sh}   (last two NEW — authored here)
│   ├── scripts/assets/cc.icns        (Claude icon, copied from the existing bundle)
│   ├── commands/{ntfy-enable.md, ntfy-disable.md, ntfy-status.md, ntfy-config.md}
│   └── INSTALL.md
├── tts/
│   ├── scripts/{tts-speak.sh, tts-enable-impl.sh, tts-disable-impl.sh, tts-status-impl.sh, tts-config-impl.sh,
│   │            tts-kokoro-install.sh, tts-kokoro-uninstall.sh, tts-stop-all.sh, tts-stop-current.sh,
│   │            tts-stop-install.sh, tts-stop-uninstall.sh,
│   │            tts-clean-prompt-auto.txt, tts-clean-prompt-normal.txt, tts-clean-prompt-summary.txt}
│   ├── scripts/assets/tts-stop-hotkeys.json
│   ├── commands/{tts-enable.md, tts-disable.md, tts-status.md, tts-config.md}
│   └── INSTALL.md
└── consolidator/
    ├── scripts/{consolidator-hook.sh, consolidator-lib.sh, consolidator-enable-impl.sh, consolidator-disable-impl.sh,
    │            consolidator-status-impl.sh, consolidator-now-impl.sh, consolidator-config-impl.sh,
    │            consolidator-eval-prompt.txt}
    ├── scripts/tests/consolidator/   (entire dir, verbatim)
    ├── commands/{consolidator-enable.md, consolidator-disable.md, consolidator-status.md, consolidator-now.md, consolidator-config.md}
    └── INSTALL.md
```

---

## Task 1: Repo scaffolding

**Files:**
- Create: `~/Projects/personal/claude-setup/.gitignore`
- Create dirs: all module subdirs

- [ ] **Step 1: Create directory tree**

```bash
cd ~/Projects/personal/claude-setup
mkdir -p core/scripts ntfy/scripts ntfy/commands \
         tts/scripts/assets tts/commands \
         consolidator/scripts consolidator/commands
```

- [ ] **Step 2: Write `.gitignore`**

```
# Never commit user runtime state or secrets
*.conf
*.conf.bak*
.DS_Store
*-sessions/
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: scaffold module directories and gitignore"
```

---

## Task 2: core module

**Files:**
- Copy: `~/.claude/scripts/_resolve-session-id.sh` → `core/scripts/_resolve-session-id.sh`
- Copy: `~/.claude/scripts/_validate-session-id.sh` → `core/scripts/_validate-session-id.sh`
- Create: `core/scripts/_merge-hook.sh`
- Create: `core/INSTALL.md`

- [ ] **Step 1: Copy the two shared helpers verbatim**

```bash
cd ~/Projects/personal/claude-setup
cp ~/.claude/scripts/_resolve-session-id.sh core/scripts/
cp ~/.claude/scripts/_validate-session-id.sh core/scripts/
chmod +x core/scripts/*.sh
```

- [ ] **Step 2: Author `core/scripts/_merge-hook.sh`**

Full content:

```bash
#!/bin/bash
# Idempotently add or remove a Claude Code hook command in settings.json.
#
# Usage:
#   _merge-hook.sh add    <Event> <command-string> [settings-path]
#   _merge-hook.sh remove <Event> <command-string> [settings-path]
#
# <Event> is a Claude Code hook event: Stop, Notification, PermissionRequest,
# SessionStart, SessionEnd, SubagentStop, PreCompact, etc.
# Idempotent: adding a command that already exists is a no-op; removing one that
# is absent is a no-op. Other hooks are never touched. A backup of settings.json
# is written before any change.
set -e

ACTION="${1:?usage: _merge-hook.sh add|remove <Event> <command> [settings-path]}"
EVENT="${2:?event required (e.g. Stop)}"
CMD="${3:?command string required}"
SETTINGS="${4:-$HOME/.claude/settings.json}"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 1; }

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)-$RANDOM"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
case "$ACTION" in
  add)
    jq --arg e "$EVENT" --arg c "$CMD" '
      .hooks //= {} | .hooks[$e] //= []
      | (.hooks[$e] | map(.matcher == "*") | index(true)) as $i
      | if $i != null
        then .hooks[$e][$i].hooks = ((.hooks[$e][$i].hooks // [])
               + (if ((.hooks[$e][$i].hooks // []) | map(.command) | index($c))
                  then [] else [{type:"command", command:$c}] end))
        else .hooks[$e] += [{matcher:"*", hooks:[{type:"command", command:$c}]}]
        end
    ' "$SETTINGS" > "$tmp"
    ;;
  remove)
    jq --arg e "$EVENT" --arg c "$CMD" '
      if (.hooks[$e]?)
      then .hooks[$e] |= ( map(.hooks = ((.hooks // []) | map(select(.command != $c))))
                           | map(select((.hooks | length) > 0)) )
           | (if (.hooks[$e] | length) == 0 then del(.hooks[$e]) else . end)
           | (if (.hooks | length) == 0 then del(.hooks) else . end)
      else . end
    ' "$SETTINGS" > "$tmp"
    ;;
  *) echo "ERROR: unknown action '$ACTION' (use add|remove)." >&2; exit 1 ;;
esac
mv "$tmp" "$SETTINGS"
echo "$ACTION  $EVENT  ->  $CMD"
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x core/scripts/_merge-hook.sh
```

- [ ] **Step 4: Verify `_merge-hook.sh` is idempotent (sandbox test)**

```bash
T=$(mktemp -d); echo '{}' > "$T/settings.json"
bash core/scripts/_merge-hook.sh add Stop "bash ~/.claude/scripts/tts-speak.sh" "$T/settings.json"
bash core/scripts/_merge-hook.sh add Stop "bash ~/.claude/scripts/consolidator-hook.sh" "$T/settings.json"
A=$(jq -S . "$T/settings.json")
bash core/scripts/_merge-hook.sh add Stop "bash ~/.claude/scripts/tts-speak.sh" "$T/settings.json"   # dup
B=$(jq -S . "$T/settings.json")
[ "$A" = "$B" ] && echo "IDEMPOTENT-ADD: PASS" || echo "IDEMPOTENT-ADD: FAIL"
jq '.hooks.Stop[0].hooks | length' "$T/settings.json"   # expect 2
bash core/scripts/_merge-hook.sh remove Stop "bash ~/.claude/scripts/tts-speak.sh" "$T/settings.json"
jq '.hooks.Stop[0].hooks | length' "$T/settings.json"   # expect 1
rm -rf "$T"
```

Expected: `IDEMPOTENT-ADD: PASS`, then `2`, then `1`.

- [ ] **Step 5: Author `core/INSTALL.md`**

Full content:

````markdown
# Install: core (shared helpers)

`core` is required by **every** module (ntfy, tts, consolidator). Install it first.
It adds three helper scripts and changes nothing else. Re-running is safe.

## Prerequisites
- `bash`, `jq`
- A Claude Code config dir at `~/.claude` (the default)

## Install
```bash
cp core/scripts/_resolve-session-id.sh ~/.claude/scripts/
cp core/scripts/_validate-session-id.sh ~/.claude/scripts/
cp core/scripts/_merge-hook.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/_resolve-session-id.sh \
         ~/.claude/scripts/_validate-session-id.sh \
         ~/.claude/scripts/_merge-hook.sh
```
(Run `mkdir -p ~/.claude/scripts` first if the directory does not exist.)

## Verify
```bash
ls ~/.claude/scripts/_resolve-session-id.sh \
   ~/.claude/scripts/_validate-session-id.sh \
   ~/.claude/scripts/_merge-hook.sh
```
All three paths should print without error.

## Uninstall
Only remove these if **no** module (ntfy/tts/consolidator) is still installed —
they depend on these helpers.
```bash
rm -f ~/.claude/scripts/_resolve-session-id.sh \
      ~/.claude/scripts/_validate-session-id.sh \
      ~/.claude/scripts/_merge-hook.sh
```
````

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/personal/claude-setup
git add core
git commit -m "feat(core): shared session-id helpers + idempotent hook merger"
```

---

## Task 3: ntfy module

**Files:**
- Copy 6 scripts + apply genericization edit #1
- Copy the Claude icon `cc.icns` from the existing notifier bundle
- Author `notifier-install.sh` + `notifier-uninstall.sh` (build the Claude-branded macOS notifier from local terminal-notifier)
- Copy 4 command defs
- Create: `ntfy/INSTALL.md`

- [ ] **Step 1: Copy scripts, the Claude icon, and commands verbatim**

```bash
cd ~/Projects/personal/claude-setup
cp ~/.claude/scripts/notify.sh \
   ~/.claude/scripts/ntfy-push.sh \
   ~/.claude/scripts/ntfy-enable-impl.sh \
   ~/.claude/scripts/ntfy-disable-impl.sh \
   ~/.claude/scripts/ntfy-status-impl.sh \
   ~/.claude/scripts/ntfy-config-impl.sh \
   ntfy/scripts/
mkdir -p ntfy/scripts/assets
cp "$HOME/.claude/apps/Claude Code Notifier.app/Contents/Resources/cc.icns" ntfy/scripts/assets/
cp ~/.claude/commands/ntfy-enable.md \
   ~/.claude/commands/ntfy-disable.md \
   ~/.claude/commands/ntfy-status.md \
   ~/.claude/commands/ntfy-config.md \
   ntfy/commands/
chmod +x ntfy/scripts/*.sh
```

- [ ] **Step 1b: Author `ntfy/scripts/notifier-install.sh`**

Full content:

```bash
#!/bin/bash
# Build a Claude-branded macOS notifier from the locally-installed terminal-notifier.
# Produces ~/.claude/apps/Claude Code Notifier.app with the Claude icon, so the
# macOS notifications fired by notify.sh show "Claude Code" + the Claude icon
# instead of the generic terminal-notifier icon. macOS only. Optional.
set -e

if [ "$(uname)" != "Darwin" ]; then
  echo "ERROR: macOS only." >&2; exit 1
fi

APPS_DIR="$HOME/.claude/apps"
DEST="$APPS_DIR/Claude Code Notifier.app"
BUNDLE_ID="com.claude.code.notifier"

# Icon: prefer the repo copy (when run from the repo), else the installed copy.
ICON_SRC="$(cd "$(dirname "$0")" && pwd)/assets/cc.icns"
[ -f "$ICON_SRC" ] || ICON_SRC="$HOME/.claude/scripts/assets/cc.icns"
[ -f "$ICON_SRC" ] || { echo "ERROR: cc.icns not found (looked in ./assets and ~/.claude/scripts/assets)." >&2; exit 1; }

# Ensure terminal-notifier is installed.
if ! command -v terminal-notifier >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing terminal-notifier via Homebrew…"
    brew install terminal-notifier
  else
    echo "ERROR: terminal-notifier not found and Homebrew unavailable." >&2
    echo "Install terminal-notifier first (brew install terminal-notifier), then re-run." >&2
    exit 1
  fi
fi

# Locate the real terminal-notifier.app.
# Homebrew installs a shell-script wrapper at .../bin/terminal-notifier that execs the
# real binary inside the .app; resolving symlinks leads to that wrapper, not a binary
# inside .app/Contents/MacOS.  Handle both cases:
#   A) BIN (after full symlink resolution) lives inside .app/Contents/MacOS  → go up two dirs.
#   B) BIN is a shell-script wrapper → parse the exec "…/terminal-notifier.app/…" line.
BIN="$(command -v terminal-notifier)"
REAL="$(realpath "$BIN" 2>/dev/null || python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$BIN")"
SRC_APP="$(cd "$(dirname "$REAL")/../.." 2>/dev/null && pwd || true)"
if [ -z "$SRC_APP" ] || [ ! -d "$SRC_APP/Contents/MacOS" ]; then
  # Wrapper script case: parse the exec line for a path ending in .app/Contents/MacOS/…
  EXEC_PATH=$(grep -oE '"[^"]+\.app/Contents/MacOS/[^"]+"' "$REAL" 2>/dev/null | head -1 | tr -d '"')
  [ -n "$EXEC_PATH" ] && SRC_APP="$(cd "$(dirname "$EXEC_PATH")/../.." 2>/dev/null && pwd || true)"
fi
if [ -z "$SRC_APP" ] || [ ! -d "$SRC_APP/Contents/MacOS" ]; then
  echo "ERROR: could not locate terminal-notifier.app from $BIN" >&2; exit 1
fi

# Build the branded bundle.
mkdir -p "$APPS_DIR"
rm -rf "$DEST"
cp -R "$SRC_APP" "$DEST"

# Swap in the Claude icon (named cc.icns; CFBundleIconFile set to "cc" below).
rm -f "$DEST/Contents/Resources/"*.icns
cp "$ICON_SRC" "$DEST/Contents/Resources/cc.icns"

# Patch Info.plist: display name, name, icon file, generic bundle id.
PLIST="$DEST/Contents/Info.plist"
PB=/usr/libexec/PlistBuddy
"$PB" -c "Set :CFBundleDisplayName Claude Code" "$PLIST" 2>/dev/null || "$PB" -c "Add :CFBundleDisplayName string Claude Code" "$PLIST"
"$PB" -c "Set :CFBundleName Claude Code"        "$PLIST" 2>/dev/null || "$PB" -c "Add :CFBundleName string Claude Code" "$PLIST"
"$PB" -c "Set :CFBundleIconFile cc"             "$PLIST" 2>/dev/null || "$PB" -c "Add :CFBundleIconFile string cc" "$PLIST"
"$PB" -c "Set :CFBundleIdentifier $BUNDLE_ID"   "$PLIST" 2>/dev/null || "$PB" -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$PLIST"

# Re-sign ad-hoc (we modified a signed bundle) and register with Launch Services.
codesign --force --deep --sign - "$DEST" >/dev/null 2>&1 || true
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREG" ] && "$LSREG" -f "$DEST" >/dev/null 2>&1 || true
touch "$DEST"

echo "Built: $DEST"
echo "Bundle id: $BUNDLE_ID"
echo "notify.sh will now show the Claude icon in macOS notifications."
echo 'Test it:  printf "{}" | bash ~/.claude/scripts/notify.sh stop'
```

- [ ] **Step 1c: Author `ntfy/scripts/notifier-uninstall.sh`**

Full content:

```bash
#!/bin/bash
# Remove the Claude-branded macOS notifier bundle built by notifier-install.sh.
set -e
DEST="$HOME/.claude/apps/Claude Code Notifier.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [ -d "$DEST" ]; then
  [ -x "$LSREG" ] && "$LSREG" -u "$DEST" >/dev/null 2>&1 || true
  rm -rf "$DEST"
  echo "Removed: $DEST"
else
  echo "Already removed: $DEST not present."
fi
```

- [ ] **Step 1d: Make the notifier scripts executable + syntax-check them**

```bash
chmod +x ntfy/scripts/notifier-install.sh ntfy/scripts/notifier-uninstall.sh
bash -n ntfy/scripts/notifier-install.sh && bash -n ntfy/scripts/notifier-uninstall.sh && echo "SYNTAX OK"
```
Expected: `SYNTAX OK`.

- [ ] **Step 2: Apply genericization edit #1 (drop personal topic prefix)**

Edit `ntfy/scripts/ntfy-enable-impl.sh`: change the line

```bash
NTFY_TOPIC=claude-bernardo-$RAND
```

to

```bash
NTFY_TOPIC=claude-$RAND
```

- [ ] **Step 3: Verify no personal strings remain** (`-I` skips the binary icon)

```bash
grep -rnI "bernardo" ntfy/ && echo "FAIL: personal string present" || echo "CLEAN"
```
Expected: `CLEAN`.

- [ ] **Step 4: Author `ntfy/INSTALL.md`**

Full content:

````markdown
# Install: ntfy (phone push notifications)

Pushes Claude Code events to your phone via [ntfy.sh](https://ntfy.sh). A single
`notify.sh` handles every event; per-event and per-session toggles are supported.

## Prerequisites
- **core installed** (see `../core/INSTALL.md`)
- `bash`, `jq`, `curl`
- The ntfy app on your phone (iOS: App Store “ntfy”; Android: F-Droid/Play)
- macOS for the clipboard convenience (`pbcopy`); optional `qrencode` for an inline QR
- Optional `terminal-notifier` (auto-installed by `notifier-install.sh`) for native
  macOS notifications with the Claude icon

## 1. Place files
```bash
mkdir -p ~/.claude/scripts/assets
cp ntfy/scripts/*.sh ~/.claude/scripts/
cp ntfy/scripts/assets/cc.icns ~/.claude/scripts/assets/
cp ntfy/commands/* ~/.claude/commands/
chmod +x ~/.claude/scripts/notify.sh ~/.claude/scripts/ntfy-*.sh ~/.claude/scripts/notifier-*.sh
```

## 1b. (Optional, macOS) Claude-icon notifications
`notify.sh` fires a native macOS notification on each event. To brand it with the
Claude icon and the name “Claude Code” (instead of the generic terminal-notifier
icon), build the wrapper app:
```bash
bash ~/.claude/scripts/notifier-install.sh
```
This installs `terminal-notifier` via Homebrew if it’s missing and builds
`~/.claude/apps/Claude Code Notifier.app`. Skipping this step is fine — if
`terminal-notifier` is already on your PATH, notifications still fire (with its
default icon); otherwise the macOS notification is silently skipped and only the
phone push remains. Remove later with `notifier-uninstall.sh`.

## 2. Wire hooks
`notify.sh` listens on seven events. Run:
```bash
M=~/.claude/scripts/_merge-hook.sh
bash $M add SessionStart      "bash ~/.claude/scripts/notify.sh session_start"
bash $M add SessionEnd        "bash ~/.claude/scripts/notify.sh session_end"
bash $M add PermissionRequest "bash ~/.claude/scripts/notify.sh permission"
bash $M add Stop              "bash ~/.claude/scripts/notify.sh stop"
bash $M add Notification      "bash ~/.claude/scripts/notify.sh notify"
bash $M add SubagentStop      "bash ~/.claude/scripts/notify.sh subagent_stop"
bash $M add PreCompact        "bash ~/.claude/scripts/notify.sh precompact"
```
Restart Claude Code (or reload settings) so the new hooks take effect.

## 3. Enable
In a Claude Code session run `/ntfy-enable`, or from a shell:
```bash
bash ~/.claude/scripts/ntfy-enable-impl.sh
```
This creates `~/.claude/ntfy.conf` with a fresh random topic, copies the topic to
your clipboard, prints the subscribe URL + QR, and sends a test push.

## 4. Verify
Subscribe to the printed topic in the ntfy app, then confirm the test push
arrives. `/ntfy-status` shows current state. Per-event toggles live in
`~/.claude/ntfy.conf` (or use `/ntfy-config`).

## Uninstall
The event→arg mapping is not a simple lowercase (e.g. `PermissionRequest`→`permission`,
`SubagentStop`→`subagent_stop`), so remove using the exact command strings added in
step 2:
```bash
M=~/.claude/scripts/_merge-hook.sh
bash $M remove SessionStart      "bash ~/.claude/scripts/notify.sh session_start"
bash $M remove SessionEnd        "bash ~/.claude/scripts/notify.sh session_end"
bash $M remove PermissionRequest "bash ~/.claude/scripts/notify.sh permission"
bash $M remove Stop              "bash ~/.claude/scripts/notify.sh stop"
bash $M remove Notification      "bash ~/.claude/scripts/notify.sh notify"
bash $M remove SubagentStop      "bash ~/.claude/scripts/notify.sh subagent_stop"
bash $M remove PreCompact        "bash ~/.claude/scripts/notify.sh precompact"

bash ~/.claude/scripts/notifier-uninstall.sh 2>/dev/null || true   # remove Claude-icon bundle
rm -f ~/.claude/scripts/notify.sh ~/.claude/scripts/ntfy-*.sh ~/.claude/scripts/notifier-*.sh
rm -f ~/.claude/scripts/assets/cc.icns
rm -f ~/.claude/commands/ntfy-*.md
rm -f ~/.claude/ntfy.conf; rm -rf ~/.claude/ntfy-sessions
```
````

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/personal/claude-setup
git add ntfy
git commit -m "feat(ntfy): scripts, commands, and install runbook"
```

---

## Task 4: tts module

**Files:**
- Copy 11 scripts + 3 prompt templates + 1 asset; apply genericization edit #2
- Copy 4 command defs
- Create: `tts/INSTALL.md`

- [ ] **Step 1: Copy scripts, prompts, asset, commands verbatim**

```bash
cd ~/Projects/personal/claude-setup
cp ~/.claude/scripts/tts-speak.sh \
   ~/.claude/scripts/tts-enable-impl.sh \
   ~/.claude/scripts/tts-disable-impl.sh \
   ~/.claude/scripts/tts-status-impl.sh \
   ~/.claude/scripts/tts-config-impl.sh \
   ~/.claude/scripts/tts-kokoro-install.sh \
   ~/.claude/scripts/tts-kokoro-uninstall.sh \
   ~/.claude/scripts/tts-stop-all.sh \
   ~/.claude/scripts/tts-stop-current.sh \
   ~/.claude/scripts/tts-stop-install.sh \
   ~/.claude/scripts/tts-stop-uninstall.sh \
   ~/.claude/scripts/tts-clean-prompt-auto.txt \
   ~/.claude/scripts/tts-clean-prompt-normal.txt \
   ~/.claude/scripts/tts-clean-prompt-summary.txt \
   tts/scripts/
cp ~/.claude/scripts/assets/tts-stop-hotkeys.json tts/scripts/assets/
cp ~/.claude/commands/tts-enable.md \
   ~/.claude/commands/tts-disable.md \
   ~/.claude/commands/tts-status.md \
   ~/.claude/commands/tts-config.md \
   tts/commands/
chmod +x tts/scripts/*.sh
```

- [ ] **Step 2: Apply genericization edit #2 (launchd label) in BOTH kokoro scripts**

In `tts/scripts/tts-kokoro-install.sh` and `tts/scripts/tts-kokoro-uninstall.sh`, change:

```bash
PLIST_LABEL="com.bernardo.claude-tts-kokoro"
```

to

```bash
PLIST_LABEL="com.claude.tts-kokoro"
```

(Both files must use the identical new label.)

- [ ] **Step 3: Verify no personal strings remain**

```bash
grep -rn "bernardo" tts/ && echo "FAIL: personal string present" || echo "CLEAN"
```
Expected: `CLEAN`.

- [ ] **Step 4: Author `tts/INSTALL.md`**

Full content:

````markdown
# Install: tts (speak Claude’s responses)

Speaks Claude’s reply when a turn ends (`Stop` hook). Cleans the text with an LLM
first (OpenRouter fast-path, else `claude -p`), then synthesizes via a local
**Kokoro** server if available, falling back to macOS `say`.

## Prerequisites
- **core installed** (see `../core/INSTALL.md`)
- macOS (`say`, `afplay`), `bash`, `jq`, `curl`
- Optional: a Kokoro TTS server for higher-quality voices (`tts-kokoro-install.sh`)
- Optional: an OpenRouter API key for fast text cleanup (else falls back to `claude -p`)
- Optional: Karabiner-Elements for global stop-speech hotkeys

## 1. Place files
```bash
mkdir -p ~/.claude/scripts/assets
cp tts/scripts/*.sh tts/scripts/*.txt ~/.claude/scripts/
cp tts/scripts/assets/tts-stop-hotkeys.json ~/.claude/scripts/assets/
cp tts/commands/* ~/.claude/commands/
chmod +x ~/.claude/scripts/tts-*.sh
```

## 2. Wire hook
TTS uses one hook on `Stop`:
```bash
bash ~/.claude/scripts/_merge-hook.sh add Stop "bash ~/.claude/scripts/tts-speak.sh"
```
Restart Claude Code (or reload settings).

## 3. Enable
`/tts-enable`, or:
```bash
bash ~/.claude/scripts/tts-enable-impl.sh
```
Creates `~/.claude/tts.conf` with defaults (Apple voice `Samantha`, empty
`OPENROUTER_API_KEY`) and plays a test phrase.

## 4. Optional extras
- **Kokoro voices:** `bash ~/.claude/scripts/tts-kokoro-install.sh` (sets up a
  launchd-managed Kokoro server at `http://127.0.0.1:8321`). Uninstall:
  `tts-kokoro-uninstall.sh`.
- **OpenRouter fast cleanup:** edit `~/.claude/tts.conf`, set `OPENROUTER_API_KEY=...`
  (get one at https://openrouter.ai/keys). Without it, cleanup uses `claude -p`.
- **Stop hotkeys (Karabiner):** `bash ~/.claude/scripts/tts-stop-install.sh`, then
  enable the rule in Karabiner → Complex Modifications. Cmd+Opt+Shift+. stops all,
  Cmd+Opt+. stops the current utterance. You can always run
  `bash ~/.claude/scripts/tts-stop-all.sh` directly.

## 5. Verify
Hear the test phrase from step 3. `/tts-status` shows current voice/rate/mode.
Tune with `/tts-config`.

## Uninstall
```bash
bash ~/.claude/scripts/_merge-hook.sh remove Stop "bash ~/.claude/scripts/tts-speak.sh"
bash ~/.claude/scripts/tts-kokoro-uninstall.sh 2>/dev/null || true
bash ~/.claude/scripts/tts-stop-uninstall.sh 2>/dev/null || true
rm -f ~/.claude/scripts/tts-*.sh ~/.claude/scripts/tts-clean-prompt-*.txt
rm -f ~/.claude/scripts/assets/tts-stop-hotkeys.json
rm -f ~/.claude/commands/tts-*.md
rm -f ~/.claude/tts.conf; rm -rf ~/.claude/tts-sessions
```
````

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/personal/claude-setup
git add tts
git commit -m "feat(tts): scripts, prompts, hotkey asset, commands, install runbook"
```

---

## Task 5: consolidator module

**Files:**
- Copy 7 scripts + eval prompt + entire tests dir; apply genericization edit #3
- Copy 5 command defs
- Create: `consolidator/INSTALL.md`

- [ ] **Step 1: Copy scripts, tests, commands verbatim**

```bash
cd ~/Projects/personal/claude-setup
cp ~/.claude/scripts/consolidator-hook.sh \
   ~/.claude/scripts/consolidator-lib.sh \
   ~/.claude/scripts/consolidator-enable-impl.sh \
   ~/.claude/scripts/consolidator-disable-impl.sh \
   ~/.claude/scripts/consolidator-status-impl.sh \
   ~/.claude/scripts/consolidator-now-impl.sh \
   ~/.claude/scripts/consolidator-config-impl.sh \
   ~/.claude/scripts/consolidator-eval-prompt.txt \
   consolidator/scripts/
mkdir -p consolidator/scripts/tests
cp -R ~/.claude/scripts/tests/consolidator consolidator/scripts/tests/
cp ~/.claude/commands/consolidator-enable.md \
   ~/.claude/commands/consolidator-disable.md \
   ~/.claude/commands/consolidator-status.md \
   ~/.claude/commands/consolidator-now.md \
   ~/.claude/commands/consolidator-config.md \
   consolidator/commands/
chmod +x consolidator/scripts/*.sh
```

- [ ] **Step 2: Apply genericization edit #3 (comment example path)**

In `consolidator/scripts/consolidator-lib.sh` (around line 8), replace any
`-Users-bernardo` example path in the comment with `-Users-you` so no personal
path appears. (Comment-only; no behavior change.)

- [ ] **Step 3: Verify no personal strings remain**

```bash
grep -rn "bernardo" consolidator/ && echo "FAIL: personal string present" || echo "CLEAN"
```
Expected: `CLEAN`.

- [ ] **Step 4: Run the consolidator test suite against the copied scripts**

The tests live beside the scripts; run them from the repo copy:
```bash
bash consolidator/scripts/tests/consolidator/run.sh
```
Expected: the suite reports all tests passing (non-zero exit = investigate before continuing).

> If the tests resolve script paths via `~/.claude/scripts`, run this step AFTER
> Task 7’s sandbox install, or temporarily install core+consolidator first. If the
> runner is self-contained (uses its own `lib.sh` + fixtures), it passes here.

- [ ] **Step 5: Author `consolidator/INSTALL.md`**

Full content:

````markdown
# Install: consolidator (auto-consolidate memory)

On `Stop`, evaluates the session transcript and consolidates your long-term
memory files (the `~/.claude/projects/<slug>/memory/` layout). Cheap gating
pre-checks run before any LLM call.

## Prerequisites
- **core installed** (see `../core/INSTALL.md`)
- `bash`, `jq`, `curl`
- A memory directory layout under `~/.claude/projects/<project>/memory/`
  (created on demand if missing)
- Optional: an OpenRouter API key for the fast eval path (else `claude -p`)

## 1. Place files
```bash
cp consolidator/scripts/*.sh consolidator/scripts/*.txt ~/.claude/scripts/
mkdir -p ~/.claude/scripts/tests
cp -R consolidator/scripts/tests/consolidator ~/.claude/scripts/tests/
cp consolidator/commands/* ~/.claude/commands/
chmod +x ~/.claude/scripts/consolidator-*.sh
```

## 2. Wire hook
Consolidator uses one hook on `Stop`:
```bash
bash ~/.claude/scripts/_merge-hook.sh add Stop "bash ~/.claude/scripts/consolidator-hook.sh"
```
Restart Claude Code (or reload settings).

## 3. Enable
`/consolidator-enable`, or:
```bash
bash ~/.claude/scripts/consolidator-enable-impl.sh
```
Creates `~/.claude/consolidator.conf` with default thresholds. `OPENROUTER_API_KEY`
is intentionally left unset (uncomment in the conf to use OpenRouter; otherwise
the eval falls back to `claude -p`).

## 4. Verify
```bash
bash ~/.claude/scripts/tests/consolidator/run.sh   # full suite
/consolidator-status                               # shows enabled + thresholds
/consolidator-now                                  # force one eval, bypassing cooldown
```

## Uninstall
```bash
bash ~/.claude/scripts/_merge-hook.sh remove Stop "bash ~/.claude/scripts/consolidator-hook.sh"
rm -f ~/.claude/scripts/consolidator-*.sh ~/.claude/scripts/consolidator-eval-prompt.txt
rm -rf ~/.claude/scripts/tests/consolidator
rm -f ~/.claude/commands/consolidator-*.md
rm -f ~/.claude/consolidator.conf; rm -rf ~/.claude/consolidator-sessions
```
````

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/personal/claude-setup
git add consolidator
git commit -m "feat(consolidator): scripts, tests, commands, install runbook"
```

---

## Task 6: Top-level README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Author `README.md`**

Full content:

````markdown
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
| [`tts`](tts/INSTALL.md) | Speaks Claude’s responses on `Stop` (Kokoro server or macOS `say`), LLM-cleaned. | Stop | yes (`say`/`afplay`) |
| [`consolidator`](consolidator/INSTALL.md) | On `Stop`, evaluates the transcript and consolidates long-term memory files. | Stop | no |

## Install

1. Install **core** first: follow [`core/INSTALL.md`](core/INSTALL.md).
2. Install any modules you want, in any order: follow that module’s `INSTALL.md`.
3. Restart Claude Code so the new hooks load.

Each runbook has six sections: Prerequisites → Place files → Wire hooks → Enable →
Verify → Uninstall.

## Conventions & assumptions

- Files install **flat** into `~/.claude/scripts/` and `~/.claude/commands/`
  (the scripts call each other by absolute `~/.claude/scripts/...` path).
- The config dir is assumed to be the default `~/.claude`. `core`’s session-id
  resolver honors `CLAUDE_CONFIG_DIR`; the rest currently hardcode `~/.claude`.
- **No config files are shipped.** Each module’s `*-enable` regenerates a clean
  `~/.claude/<module>.conf` on first run, so no API keys or personal topics live
  in this repo. Add an optional `OPENROUTER_API_KEY` yourself (tts + consolidator
  both fall back to `claude -p` without it).
- Hook wiring is additive and idempotent via `core/scripts/_merge-hook.sh` —
  installing one module never disturbs another’s hooks, even though several share
  the `Stop` event.

## Dependencies

- All: `bash`, `jq`. ntfy/consolidator also use `curl`.
- ntfy: ntfy phone app; optional `terminal-notifier` (auto-installed for the
  Claude-icon macOS notifier), `qrencode`, macOS `pbcopy`.
- tts: macOS (`say`, `afplay`); optional Kokoro server, OpenRouter key,
  Karabiner-Elements (stop hotkeys).
- consolidator: optional OpenRouter key.

## Notices

- [`terminal-notifier`](https://github.com/julienXX/terminal-notifier) is MIT
  licensed (© Eloy Durán, Julien Blanchard). The ntfy module does not bundle it;
  `notifier-install.sh` builds a wrapper from your locally installed copy.
- `cc.icns` is the Claude logo (an Anthropic mark), included only for personal use
  to brand local notifications. Not affiliated with or endorsed by Anthropic.

## License

MIT for the scripts in this repo (see `LICENSE`). Third-party components retain
their own licenses (see Notices).
````

- [ ] **Step 2: Add a LICENSE (MIT)**

```bash
cd ~/Projects/personal/claude-setup
cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2026 Bernardo Cabral

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
```

- [ ] **Step 3: Commit**

```bash
git add README.md LICENSE
git commit -m "docs: top-level README + MIT license"
```

---

## Task 7: End-to-end sandbox verification

Verify a clean machine experience by installing into a throwaway config dir, then
checking idempotency and uninstall. This does NOT fire live pushes/speech (those
need a phone/macOS audio and are a manual smoke step).

**Files:** none (verification only)

- [ ] **Step 1: Sandbox install of core + all modules**

```bash
cd ~/Projects/personal/claude-setup
SB=$(mktemp -d)/.claude; mkdir -p "$SB/scripts/assets" "$SB/commands"
cp core/scripts/* "$SB/scripts/"
cp ntfy/scripts/*.sh "$SB/scripts/"
cp ntfy/scripts/assets/* "$SB/scripts/assets/"
cp -R tts/scripts/. "$SB/scripts/"
cp consolidator/scripts/*.sh consolidator/scripts/*.txt "$SB/scripts/"
mkdir -p "$SB/scripts/tests"; cp -R consolidator/scripts/tests/consolidator "$SB/scripts/tests/"
cp ntfy/commands/* tts/commands/* consolidator/commands/* "$SB/commands/"
chmod +x "$SB"/scripts/*.sh
echo '{}' > "$SB/settings.json"
echo "Sandbox: $SB"
```

- [ ] **Step 2: Wire all hooks twice; assert idempotency**

```bash
M="$SB/scripts/_merge-hook.sh"; S="$SB/settings.json"
wire() {
  bash "$M" add SessionStart "bash ~/.claude/scripts/notify.sh session_start" "$S"
  bash "$M" add Stop "bash ~/.claude/scripts/notify.sh stop" "$S"
  bash "$M" add Stop "bash ~/.claude/scripts/tts-speak.sh" "$S"
  bash "$M" add Stop "bash ~/.claude/scripts/consolidator-hook.sh" "$S"
}
wire >/dev/null; A=$(jq -S . "$S")
wire >/dev/null; B=$(jq -S . "$S")
[ "$A" = "$B" ] && echo "IDEMPOTENT: PASS" || echo "IDEMPOTENT: FAIL"
echo "Stop hooks (expect 3):"; jq '.hooks.Stop[0].hooks | length' "$S"
```
Expected: `IDEMPOTENT: PASS` and `3`.

- [ ] **Step 3: Uninstall tts only; assert other Stop hooks survive**

```bash
bash "$M" remove Stop "bash ~/.claude/scripts/tts-speak.sh" "$S"
echo "Stop hooks after tts removal (expect 2):"; jq '.hooks.Stop[0].hooks | length' "$S"
jq -e '[.hooks.Stop[0].hooks[].command] | index("bash ~/.claude/scripts/consolidator-hook.sh")' "$S" >/dev/null \
  && echo "consolidator hook intact: PASS" || echo "FAIL"
```
Expected: `2`, then `PASS`.

- [ ] **Step 4: Run the consolidator suite in the sandbox**

```bash
bash "$SB/scripts/tests/consolidator/run.sh"
```
Expected: all tests pass.

- [ ] **Step 4b: Build the Claude-icon notifier into the sandbox (macOS)**

Skip if not on macOS. Builds into `$SB/apps` by pointing `$HOME` at the sandbox:
```bash
HOME="$(dirname "$SB")" bash "$SB/scripts/notifier-install.sh"
APP="$SB/apps/Claude Code Notifier.app"
test -f "$APP/Contents/Resources/cc.icns" && echo "icon: PASS" || echo "icon: FAIL"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier"  "$APP/Contents/Info.plist"  # expect com.claude.code.notifier
/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$APP/Contents/Info.plist"  # expect Claude Code
```
Expected: `icon: PASS`, `com.claude.code.notifier`, `Claude Code`. (No `bernardo`.)

- [ ] **Step 5: Clean up sandbox**

```bash
rm -rf "$(dirname "$SB")"
```

- [ ] **Step 6: Final repo sanity check** (`-I` skips the binary icon)

Scope the personal-string check to the **module** dirs — `docs/` legitimately quotes
the old "before" strings while documenting the genericization, and `LICENSE` carries
the author's name, so a repo-wide grep is expected to hit those.
```bash
cd ~/Projects/personal/claude-setup
grep -rnI "bernardo" core ntfy tts consolidator && echo "FAIL: personal strings in modules" || echo "MODULES CLEAN"
# Secret scan (must find NOTHING real — placeholders/empties are fine):
grep -rnI "sk-or-v1-[0-9a-f]" . --exclude-dir=.git && echo "FAIL: live key" || echo "NO LIVE SECRETS"
git status --short    # expect clean working tree (all committed)
git log --oneline
```
Expected: `MODULES CLEAN`, `NO LIVE SECRETS`, and a clean tree.

---

## Task 8: Publish to GitHub (optional, on request)

- [ ] **Step 1: Create the public repo and push**

```bash
cd ~/Projects/personal/claude-setup
gh repo create claude-setup --public --source=. --remote=origin \
  --description "Modular, pick-and-choose Claude Code add-ons: ntfy push, TTS, memory consolidator" --push
```

- [ ] **Step 2: Confirm**

```bash
gh repo view --web
```

---

## Self-Review

**Spec coverage:**
- Native macOS notification with Claude icon → `notify.sh` (ntfy, Task 3) +
  `notifier-install.sh`/`notifier-uninstall.sh` + `cc.icns` (Task 3), optional
  install sub-step in `ntfy/INSTALL.md`, build-tested in Task 7 Step 4b. Generic
  bundle id `com.claude.code.notifier` written by the builder. ✓
- By-module layout → Tasks 2–5. ✓
- Scripts-only export, no confs → `.gitignore` (Task 1) + no conf copy steps. ✓
- Six-section runbooks → Tasks 3/4/5 INSTALL.md authored in full. ✓
- Idempotent hook merge → `_merge-hook.sh` (Task 2) + idempotency tests (Tasks 2,7). ✓
- Genericization edits (3) → Tasks 3,4,5 each with a grep gate. ✓
- macOS deps / CLAUDE_CONFIG_DIR assumption documented → README (Task 6). ✓
- Consolidator tests ship + run → Task 5 + Task 7. ✓
- Verification (files land, idempotent, uninstall reverses) → Task 7. ✓
- Out-of-scope items excluded → only the four module dirs are populated. ✓

**Placeholder scan:** No TBD/TODO; all authored files (`_merge-hook.sh`, 4×INSTALL.md, README, LICENSE) are shown in full; copied files use exact `cp` commands.

**Type/string consistency:** Hook command strings are identical between each module’s add step, its INSTALL.md, and Task 7 assertions (e.g. `bash ~/.claude/scripts/tts-speak.sh`). The launchd label `com.claude.tts-kokoro` is applied to both kokoro scripts.
