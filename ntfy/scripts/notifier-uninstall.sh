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
