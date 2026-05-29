# Install: ntfy (phone push notifications)

Pushes Claude Code events to your phone via [ntfy.sh](https://ntfy.sh). A single
`notify.sh` handles every event; per-event and per-session toggles are supported.

## Prerequisites
- **core installed** (see `../core/INSTALL.md`)
- `bash`, `jq`, `curl`
- The ntfy app on your phone (iOS: App Store "ntfy"; Android: F-Droid/Play)
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
Claude icon and the name "Claude Code" (instead of the generic terminal-notifier
icon), build the wrapper app:
```bash
bash ~/.claude/scripts/notifier-install.sh
```
This installs `terminal-notifier` via Homebrew if it's missing and builds
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
