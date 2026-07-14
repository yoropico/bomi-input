#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="Bomi.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Bomi "$APP/Contents/MacOS/Bomi"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/bomi.tiff "$APP/Contents/Resources/bomi.tiff"
codesign --force --deep --sign - "$APP"
echo "Assembled $APP"
