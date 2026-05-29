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
