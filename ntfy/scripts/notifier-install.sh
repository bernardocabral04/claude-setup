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
