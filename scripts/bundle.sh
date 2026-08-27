#!/bin/bash
# Assembles dist/TinyWindow.app from the SwiftPM build — no Xcode required.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
CODESIGN_ID="${CODESIGN_ID:-TinyWindow Dev}"
VERSION="$(tr -d '[:space:]' < VERSION)"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/TinyWindow"

APP="dist/TinyWindow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/TinyWindow"
sed "s/@VERSION@/$VERSION/g" Support/Info.plist.in > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ ! -f Support/AppIcon.icns ] || [ assets/icon-1024.png -nt Support/AppIcon.icns ]; then
  scripts/make-icns.sh
fi
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SPM resource bundles, if any ever appear (Bundle.module finds them here).
for bundle in "$BIN_DIR"/TinyWindow_*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$APP/Contents/Resources/"
done

# Sign with the stable dev identity when present; ad-hoc otherwise.
# Ad-hoc means a new cdhash-based designated requirement per build, so the
# Accessibility grant silently dies on every rebuild — see README.
if [ "$CODESIGN_ID" = "-" ]; then
  codesign --force --timestamp=none --identifier com.tinyqaq.TinyWindow --sign - "$APP"
  echo "Signed ad-hoc (CODESIGN_ID=-)."
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$CODESIGN_ID"; then
  codesign --force --timestamp=none --identifier com.tinyqaq.TinyWindow \
    --sign "$CODESIGN_ID" "$APP"
  echo "Signed with '$CODESIGN_ID' (stable designated requirement)."
else
  echo "warning: signing identity '$CODESIGN_ID' not found — signing ad-hoc." >&2
  echo "         Accessibility permission will RESET on every rebuild." >&2
  echo "         One-time fix: create the self-signed cert (see README)." >&2
  codesign --force --timestamp=none --identifier com.tinyqaq.TinyWindow --sign - "$APP"
fi

echo "Built $APP (version $VERSION, $CONFIG)"
