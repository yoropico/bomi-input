#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="$HOME/Library/Input Methods"
mkdir -p "$DEST"
killall Bomi 2>/dev/null || true
rm -rf "$DEST/Bomi.app"
cp -R Bomi.app "$DEST/Bomi.app"
echo "Installed to $DEST/Bomi.app"
echo "Now: System Settings > Keyboard > Input Sources > + > add Bomi (log out/in if it does not appear)."
