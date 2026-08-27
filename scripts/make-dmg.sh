#!/bin/bash
# Builds the classic drag-to-install DMG: TinyWindow.app + an /Applications
# symlink, compressed UDZO. hdiutil only — no extra tooling.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/TinyWindow.app"
if [ ! -d "$APP" ]; then
  CONFIG=release scripts/bundle.sh
fi

STAGING="dist/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/TinyWindow.app"
ln -s /Applications "$STAGING/Applications"

DMG="dist/TinyWindow-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "TinyWindow $VERSION" -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "DMG: $DMG"
