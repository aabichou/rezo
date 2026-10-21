#!/bin/sh
# Regenerates Resources/AppIcon.icns and docs/icon.png from scripts/make-icon.swift.
set -e
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swift scripts/make-icon.swift "$TMP" >/dev/null
SET="$TMP/AppIcon.iconset"
mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
sips -z 256 256 "$TMP/icon_1024.png" --out ../docs/icon.png >/dev/null
rm -rf "$TMP"
echo "wrote Resources/AppIcon.icns and docs/icon.png"
