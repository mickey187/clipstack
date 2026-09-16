#!/usr/bin/env bash
# Packages an already-built ClipStack.app into a drag-to-Applications DMG.
#
#   ./Scripts/make-dmg.sh            uses the version from the built app
#   ./Scripts/make-dmg.sh 1.2.0      overrides the version in the filename
set -euo pipefail
cd "$(dirname "$0")/.."

APP="ClipStack.app"
if [[ ! -d "$APP" ]]; then
  echo "$APP not found — run Scripts/build-app.sh first." >&2
  exit 1
fi

VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")}"
DMG="dist/ClipStack-${VERSION}.dmg"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
# The drag-to-install gesture every Mac user already knows.
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$DMG"
hdiutil create \
  -volname "ClipStack" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG" >/dev/null

echo "✅ $DMG ($(du -h "$DMG" | cut -f1))"
echo "   sha256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
