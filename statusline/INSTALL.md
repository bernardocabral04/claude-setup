# Install: statusline (multi-line status bar)

A status bar for Claude Code showing: profile chip, model + context %, rate-limit
usage with reset countdowns, session id, cwd + git branch/dirty/ahead-behind, live
per-session **TTS / Ntfy / Consolidator** chips, and a network status line when the
connection degrades.

**Standalone:** unlike the other modules, statusline does **not** require `core`.
It reads the session id from Claude Code's status JSON and wires through the
`settings.json` `statusLine` key (not hooks).

**Soft integration:** the line-3 TTS/Ntfy/Consolidator chips appear automatically
when those modules are installed and enabled for the session; if they aren't, the
chips simply don't show.

## Prerequisites
- `bash`, `jq`, `git`
- macOS (uses `stat -f`, `date`, `awk`, `shasum`)
- Optional: `fswatch` (`brew install fswatch`) for the git-watch daemon
  (keeps `↑n ↓n` fresh against the remote)

## 1. Place files
```bash
mkdir -p ~/.claude/scripts
cp statusline/statusline-command.sh ~/.claude/statusline-command.sh
cp statusline/scripts/git-watch-daemon.sh ~/.claude/scripts/
cp statusline/scripts/network-daemon.sh ~/.claude/scripts/
chmod +x ~/.claude/statusline-command.sh \
         ~/.claude/scripts/git-watch-daemon.sh \
         ~/.claude/scripts/network-daemon.sh
```

## 2. Wire the statusLine setting
```bash
SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)-$RANDOM"
tmp=$(mktemp)
jq '.statusLine = {type:"command", command:"bash ~/.claude/statusline-command.sh", refreshInterval:1}' \
  "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
```
Restart Claude Code (or reload settings) to see the status bar.

## 3. Optional daemons
- **git ahead/behind freshness:** `brew install fswatch`. Nothing else to do — the
  statusline auto-spawns `git-watch-daemon.sh` per repo (it self-exits on idle).
  Without `fswatch`, `↑n ↓n` still updates whenever you fetch manually.
- **network status line:** no setup — the statusline auto-spawns
  `network-daemon.sh`, which pings `1.1.1.1` and shows line 4 only when the
  connection is offline/slow/just-reconnected.

## 4. Verify
The status bar should appear at the bottom of Claude Code. To check rendering from
a shell:
```bash
printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Claude Opus 4.7 (1M context)"},"session_id":"x","context_window":{"used_percentage":3},"effort":{"level":"high"}}' "$PWD" \
  | bash ~/.claude/statusline-command.sh
```
You should see a line with `✳ Opus 4.7 1M (high)` and `◷ 3%`, and a second line
with `▸ <cwd>/` and the git branch.

## Uninstall
```bash
SETTINGS="$HOME/.claude/settings.json"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)-$RANDOM"
tmp=$(mktemp)
jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
rm -f ~/.claude/statusline-command.sh \
      ~/.claude/scripts/git-watch-daemon.sh \
      ~/.claude/scripts/network-daemon.sh
# The daemons stop on their own (git-watch self-exits on idle; kill any lingering
# network daemon with: pkill -f network-daemon.sh). Caches live under ~/.claude/cache/.
```
