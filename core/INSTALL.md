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
