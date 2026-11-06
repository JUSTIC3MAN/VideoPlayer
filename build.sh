#!/bin/bash
# Builds VideoPlayer.app with Apple's free Command Line Tools (no Xcode project needed).
#
#   ./build.sh            -> build/VideoPlayer.app
#   ./build.sh install    -> also copies it to /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="VideoPlayer"
VERSION="1.0"
BUNDLE_ID="com.justiceman.videoplayer"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift is not installed. Run this once, then try again:"
  echo "  xcode-select --install"
  exit 1
fi

echo "Building $APP (release, $(uname -m))..."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP"

OUT="build/$APP.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>     <string>en</string>
    <key>CFBundleExecutable</key>            <string>$APP</string>
    <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>                  <string>$APP</string>
    <key>CFBundleDisplayName</key>           <string>$APP</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundleVersion</key>               <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>        <string>13.0</string>
    <key>LSApplicationCategoryType</key>     <string>public.app-category.video</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSPrincipalClass</key>              <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS runs it locally without complaints.
codesign --force --sign - "$OUT" >/dev/null 2>&1 || echo "(signing skipped)"
echo "Built: $OUT"

if [[ "${1:-}" == "install" ]]; then
  rm -rf "/Applications/$APP.app"
  cp -R "$OUT" /Applications/
  echo "Installed: /Applications/$APP.app"
fi
