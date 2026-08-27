#!/bin/bash
# Builds a release zip: ditto preserves the bundle structure (never `zip -r` a .app).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
CONFIG=release scripts/bundle.sh

ZIP="dist/TinyWindow-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent dist/TinyWindow.app "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Release artifact: $ZIP"
