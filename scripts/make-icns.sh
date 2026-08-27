#!/bin/bash
# assets/icon-1024.png → Support/AppIcon.icns via sips + iconutil (no actool).
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="assets/icon-1024.png"
if [ ! -f "$SRC" ]; then
  echo "error: $SRC missing — run 'swift scripts/gen-icon.swift' or provide your own." >&2
  exit 1
fi

ICONSET="Support/TinyWindow.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Support/AppIcon.icns
rm -rf "$ICONSET"
echo "Wrote Support/AppIcon.icns"
