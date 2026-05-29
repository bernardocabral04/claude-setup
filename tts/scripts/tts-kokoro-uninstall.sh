#!/bin/bash
# tts-kokoro-uninstall.sh — stop the launchd agent and (optionally) remove
# the install dir.
set -e

PLIST_LABEL="com.claude.tts-kokoro"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
INSTALL_DIR="$HOME/.claude/services/kokoro"
PURGE=0

[ "${1:-}" = "--purge" ] && PURGE=1

launchctl bootout "gui/$UID/$PLIST_LABEL" 2>/dev/null && \
  echo "launchd agent stopped." || echo "(launchd agent was not loaded.)"

if [ -f "$PLIST_PATH" ]; then
  rm -f "$PLIST_PATH"
  echo "Removed $PLIST_PATH"
fi

if [ "$PURGE" = "1" ]; then
  if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "Purged $INSTALL_DIR"
  fi
else
  echo "Note: $INSTALL_DIR kept on disk. Pass --purge to remove it."
fi
