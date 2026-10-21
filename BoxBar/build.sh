#!/bin/sh
# Builds BoxBar.app (menu bar only, no Dock icon) next to this script.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=BoxBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BoxBar "$APP/Contents/MacOS/BoxBar"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>BoxBar</string>
  <key>CFBundleDisplayName</key><string>BoxBar</string>
  <key>CFBundleIdentifier</key><string>local.boxbar</string>
  <key>CFBundleExecutable</key><string>BoxBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>BoxBar reads signal, battery and traffic stats from your 5G box on the local network.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "built $(pwd)/$APP"
