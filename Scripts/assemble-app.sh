#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="Bomi.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Bomi "$APP/Contents/MacOS/Bomi"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Mode icons (menu bar ㅂ / B) + the input-method icon.
cp Resources/*.png "$APP/Contents/Resources/"
# Localized input-source display names — without these the input-source list
# shows the raw mode identifier.
for lproj in Resources/*.lproj; do
  cp -R "$lproj" "$APP/Contents/Resources/"
done
codesign --force --deep --sign - "$APP"
echo "Assembled $APP"
