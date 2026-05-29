#!/bin/bash
# Install Claude Code TTS stop hotkeys into Karabiner-Elements
# Copies the rule JSON and prints instructions for the user to enable it in the GUI.

set -e

SRC="$HOME/.claude/scripts/assets/tts-stop-hotkeys.json"
DST_DIR="$HOME/.config/karabiner/assets/complex_modifications"
DST="$DST_DIR/tts-stop-hotkeys.json"

# Check if source file exists
if [[ ! -f "$SRC" ]]; then
  echo "Error: TTS stop hotkeys file not found at $SRC" >&2
  exit 1
fi

# Create destination directory if missing
mkdir -p "$DST_DIR"

# Copy source to destination (overwrites if exists — idempotent)
cp -f "$SRC" "$DST"

cat <<EOF
Installed: tts-stop-hotkeys.json → $DST

Next step (one-time):
  1. Open Karabiner-Elements → Preferences → Complex Modifications.
  2. Click "Add rule".
  3. Find "Claude Code TTS — Stop hotkeys" and click "Enable" on both rules:
       - Cmd+Opt+Shift+. → Stop ALL Claude Code TTS playback
       - Cmd+Opt+.       → Stop CURRENT Claude Code TTS playback

Once enabled, the hotkeys are live immediately (no daemon restart needed).
EOF

exit 0
