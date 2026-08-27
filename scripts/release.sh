#!/bin/bash
# Builds the release artifacts: drag-to-install DMG + zip, with sha256 sums.
# ditto preserves the bundle structure (never `zip -r` a .app).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
CONFIG=release scripts/bundle.sh

ZIP="dist/TinyWindow-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent dist/TinyWindow.app "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"

scripts/make-dmg.sh

echo "Release artifacts:"
ls -lh dist/TinyWindow-"$VERSION".* | awk '{print "  " $9 " (" $5 ")"}'
