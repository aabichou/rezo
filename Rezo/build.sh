#!/bin/sh
# Builds Rezo.app (menu bar only, no Dock icon) next to this script.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=Rezo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Rezo "$APP/Contents/MacOS/Rezo"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Rezo</string>
  <key>CFBundleDisplayName</key><string>Rezo</string>
  <key>CFBundleIdentifier</key><string>io.github.adamab48.rezo</string>
  <key>CFBundleExecutable</key><string>Rezo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Rezo reads signal, battery and traffic stats from your 5G box on the local network.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "built $(pwd)/$APP"
