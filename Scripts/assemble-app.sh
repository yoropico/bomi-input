#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
# Stage the bundle WITHOUT the .app extension. LaunchServices' lsd registers
# every *.app bundle it discovers anywhere under the home directory -- dot-dirs
# included (verified 2026-08-11: an earlier .build/Bomi.app staging output was
# registered within minutes of assembly). A second registration of
# com.bomi.inputmethod.bomi next to ~/Library/Input Methods/Bomi.app makes
# HIToolbox register the input modes twice at login -- the duplicate
# "Sebeolsik Final" rows in the input menu (2026-08-07/08-10/08-11 incidents).
# `lsregister -u` is not a fix: lsd re-registers the file while it exists.
APP=".build/Bomi-staging"
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
