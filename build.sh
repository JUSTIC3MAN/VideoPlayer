#!/bin/bash
# Builds VideoPlayer.app with Apple's free Command Line Tools (no Xcode project needed).
#
#   ./build.sh            -> build/VideoPlayer.app (for this Mac)
#   ./build.sh install    -> also copies it to /Applications
#   UNIVERSAL=1 ./build.sh  -> one app for both Intel and Apple Silicon (needs full Xcode; used by GitHub)
set -euo pipefail
cd "$(dirname "$0")"

APP="VideoPlayer"
VERSION="${VERSION:-1.0}"
BUILD="${BUILD:-0}"          # GitHub sets this; 0 = built by hand
BUNDLE_ID="com.justiceman.videoplayer"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift is not installed. Run this once, then try again:"
  echo "  xcode-select --install"
  exit 1
fi

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
  echo "Building $APP $VERSION (Intel + Apple Silicon)..."
else
  ARCH_FLAGS=()
  echo "Building $APP $VERSION ($(uname -m))..."
fi
# The ${a[@]+...} form keeps macOS's bash 3.2 happy when the list is empty.
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/$APP"

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
    <key>CFBundleVersion</key>               <string>$BUILD</string>
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
