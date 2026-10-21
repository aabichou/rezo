#!/bin/sh
# Builds Rezo.app (menu bar only, no Dock icon) next to this script.
#
#   VERSION=1.2.3   version written into Info.plist (default: dev)
#   UNIVERSAL=1     build for both Apple Silicon and Intel (needs full Xcode)
#   SWIFT_BUILD_FLAGS="--disable-sandbox"   extra flags, e.g. inside Homebrew
set -e
cd "$(dirname "$0")"
VERSION="${VERSION:-dev}"
FLAGS="-c release $SWIFT_BUILD_FLAGS"
[ "$UNIVERSAL" = "1" ] && FLAGS="$FLAGS --arch arm64 --arch x86_64"
swift build $FLAGS
BIN="$(swift build $FLAGS --show-bin-path)/Rezo"
APP=Rezo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Rezo"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Rezo</string>
  <key>CFBundleDisplayName</key><string>Rezo</string>
  <key>CFBundleIdentifier</key><string>io.github.aabichou.rezo</string>
  <key>CFBundleExecutable</key><string>Rezo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Adem Abichou. MIT License. Independent project, not affiliated with Ooredoo, ZLT, ZTE or Quectel.</string>
  <key>NSLocalNetworkUsageDescription</key><string>Rezo reads signal, battery and traffic stats from your 5G box on the local network.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "built $(pwd)/$APP ($VERSION)"
