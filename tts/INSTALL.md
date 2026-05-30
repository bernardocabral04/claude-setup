# Install: tts (speak Claude's responses)

Speaks Claude's reply when a turn ends (`Stop` hook). Cleans the text with an LLM
first (OpenRouter fast-path, else `claude -p`), then synthesizes via a local
**Kokoro** server if available, falling back to macOS `say`.

## Prerequisites
- **core installed** (see `../core/INSTALL.md`)
- macOS (`say`, `afplay`), `bash`, `jq`, `python3`, `curl`
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
- **Kokoro voices (higher quality):** requires Python 3.10–3.12
  (`brew install python@3.12`). Stage the server, then build it:
  ```bash
  mkdir -p ~/.claude/services/kokoro
  cp tts/kokoro-server/server.py tts/kokoro-server/requirements.txt ~/.claude/services/kokoro/
  bash ~/.claude/scripts/tts-kokoro-install.sh                 # build venv + start.sh, smoke-test
  bash ~/.claude/scripts/tts-kokoro-install.sh --with-launchd  # optional: run as a login service
  ```
  First run downloads the Kokoro-82M model (~hundreds of MB, cached). The server
  listens on `http://127.0.0.1:8321`; `tts-speak.sh` uses it automatically and
  falls back to Apple `say`. Tune `TTS_KOKORO_VOICE` / `TTS_KOKORO_SPEED` in
  `~/.claude/tts.conf`. Uninstall: `bash ~/.claude/scripts/tts-kokoro-uninstall.sh`
  then `rm -rf ~/.claude/services/kokoro`. Alternative: `tts/kokoro-server/Dockerfile`
  builds a container serving on port 7860.
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
