#!/bin/bash
# Resources/icon-source.png -> Resources/AppIcon.icns (macOS icon grid).
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Resources/icon-source.png"
[ -f "$SRC" ] || { echo "missing $SRC"; exit 1; }

mkdir -p build
echo "==> building maskicon"
swiftc -O -framework AppKit -o build/maskicon Tools/maskicon.swift
./build/maskicon "$SRC" build/icon-1024.png

SET="build/AppIcon.iconset"
rm -rf "$SET"; mkdir -p "$SET"
for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
            "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" "512:icon_256x256@2x" \
            "512:icon_512x512" "1024:icon_512x512@2x"; do
  px="${spec%%:*}"; name="${spec#*:}"
  sips -z "$px" "$px" build/icon-1024.png --out "$SET/$name.png" >/dev/null
done

iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "==> Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1))"
