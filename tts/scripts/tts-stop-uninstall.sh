#!/bin/bash
# Remove Claude Code TTS stop hotkeys from Karabiner-Elements
# Deletes the rule JSON and prints GUI steps for the user to disable the rules.

set -e

DST="$HOME/.config/karabiner/assets/complex_modifications/tts-stop-hotkeys.json"

# Check if destination file exists
if [[ ! -f "$DST" ]]; then
  echo "Already uninstalled: $DST not present."
  exit 0
fi

# Remove the installed file
rm -f "$DST"

cat <<EOF
Removed: $DST

To finish uninstall (one-time GUI step):
  1. Open Karabiner-Elements → Preferences → Complex Modifications.
  2. For each enabled "Claude Code TTS — Stop hotkeys" rule, click the
     "minus" (–) button to disable it.
EOF

exit 0
