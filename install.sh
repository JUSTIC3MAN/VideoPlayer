#!/bin/bash
# Installs or updates VideoPlayer in /Applications. Run the same line again to update:
#
#   curl -fsSL https://raw.githubusercontent.com/JUSTIC3MAN/VideoPlayer/main/install.sh | bash
#
set -euo pipefail

URL="https://github.com/JUSTIC3MAN/VideoPlayer/releases/latest/download/VideoPlayer.zip"
DEST="/Applications/VideoPlayer.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading the latest VideoPlayer..."
curl -fL --progress-bar "$URL" -o "$TMP/VideoPlayer.zip"
ditto -x -k "$TMP/VideoPlayer.zip" "$TMP"

# Close the app if it's open (the setlist is saved automatically).
pkill -x VideoPlayer 2>/dev/null && sleep 1 || true

if [ -w /Applications ]; then
  rm -rf "$DEST"
  mv "$TMP/VideoPlayer.app" "$DEST"
else
  echo "Your Mac password is needed to write to /Applications."
  sudo rm -rf "$DEST"
  sudo mv "$TMP/VideoPlayer.app" "$DEST"
fi
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

VERSION="$(defaults read "$DEST/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")"
echo "Installed VideoPlayer $VERSION in /Applications."
open "$DEST"
