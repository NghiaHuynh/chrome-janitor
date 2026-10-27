#!/bin/bash
# Builds ChromeJanitor.app from Sources/ using the system Swift toolchain.
set -euo pipefail
cd "$(dirname "$0")"

APP="ChromeJanitor"
OUT="build/$APP.app"
ARCH="${ARCH:-$(uname -m)}"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

# A duplicate key in the L10n dictionary literal traps at launch, not at compile time.
dupes=$(grep -oE '"[a-z0-9_]+":' Sources/L10n.swift | sort | uniq -d || true)
if [ -n "$dupes" ]; then echo "ERROR: duplicate L10n keys: $dupes" >&2; exit 1; fi

echo "==> compiling ($ARCH)"
swiftc -O -parse-as-library \
  -target "$ARCH-apple-macos12.0" \
  -framework SwiftUI -framework AppKit \
  -o "$OUT/Contents/MacOS/$APP" \
  Sources/*.swift

cp Resources/Info.plist "$OUT/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"
fi
# AppKit only localises its standard menus for localizations the bundle declares.
for lproj in Resources/*.lproj; do
  cp -R "$lproj" "$OUT/Contents/Resources/"
done
printf 'APPL????' > "$OUT/Contents/PkgInfo"

echo "==> ad-hoc signing"
codesign --force --sign - --timestamp=none "$OUT" >/dev/null

echo "==> $PWD/$OUT"
