#!/usr/bin/env bash
# Turns one square PNG into Resources/AppIcon.icns.
#
#   ./Scripts/make-icon.sh path/to/icon-1024.png
#
# Give it a 1024×1024 PNG. Anything smaller gets upscaled into the large slots
# and will look soft in Finder and System Settings.
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="${1:-}"
if [[ -z "$SOURCE" || ! -f "$SOURCE" ]]; then
  echo "usage: $0 <square-png>" >&2
  exit 2
fi

WIDTH=$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth/{print $2}')
HEIGHT=$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight/{print $2}')
if [[ "$WIDTH" != "$HEIGHT" ]]; then
  echo "⚠️  $SOURCE is ${WIDTH}×${HEIGHT}, not square — it will be distorted." >&2
fi
if (( WIDTH < 1024 )); then
  echo "⚠️  $SOURCE is only ${WIDTH}px wide; 1024 is recommended." >&2
fi

# Artwork exported from most image tools is opaque, and an .icns built from that
# paints a white box behind the icon everywhere macOS draws it. Reshape first.
HAS_ALPHA=$(sips -g hasAlpha "$SOURCE" | awk '/hasAlpha/{print $2}')
if [[ "$HAS_ALPHA" != "yes" ]]; then
  echo "==> Source has no transparency — masking to a rounded icon shape…"
  ROUNDED="$(mktemp -d)/rounded.png"
  swift Scripts/round-icon.swift "$SOURCE" "$ROUNDED"
  SOURCE="$ROUNDED"
fi

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "$(dirname "$ICONSET")"' EXIT

# Apple's required set: each logical size at @1x and @2x.
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  sips -z $((SIZE * 2)) $((SIZE * 2)) "$SOURCE" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done

mkdir -p Resources
iconutil --convert icns "$ICONSET" --output Resources/AppIcon.icns
echo "✅ Wrote Resources/AppIcon.icns — run Scripts/build-app.sh to pick it up."
