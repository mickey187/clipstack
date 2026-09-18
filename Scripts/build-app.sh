#!/usr/bin/env bash
# Builds ClipStack.app — a real, double-clickable bundle.
#
# `swift run` is fine for watching stdout, but it cannot properly exercise a
# Dock-less menu bar app or the Accessibility permission, which are tied to a
# signed bundle. Test those here.
#
#   ./Scripts/build-app.sh              build, sign, relaunch
#   ./Scripts/build-app.sh --no-open    build and sign only
#   ./Scripts/build-app.sh --host-only  skip the Intel slice (faster dev loop)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="ClipStack.app"
IDENTITY="ClipStack Local"
DEPLOYMENT_TARGET="14.0"

OPEN_AFTER=1
UNIVERSAL=1
for arg in "$@"; do
  case "$arg" in
    --no-open)   OPEN_AFTER=0 ;;
    --host-only) UNIVERSAL=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

ARM_BIN=".build/arm64-apple-macosx/release/ClipStack"
X86_BIN=".build/x86_64-apple-macosx/release/ClipStack"

echo "==> Building release binary…"
swift build -c release --triple "arm64-apple-macosx${DEPLOYMENT_TARGET}"
if (( UNIVERSAL )); then
  swift build -c release --triple "x86_64-apple-macosx${DEPLOYMENT_TARGET}"
fi

echo "==> Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if (( UNIVERSAL )); then
  # Releases must run on Intel too, and there is no way to tell from the outside
  # that a download is Apple-Silicon-only until it refuses to launch.
  lipo -create -output "$APP/Contents/MacOS/ClipStack" "$ARM_BIN" "$X86_BIN"
else
  cp "$ARM_BIN" "$APP/Contents/MacOS/ClipStack"
fi

cp "Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Signing. A stable identity is what keeps the Accessibility grant alive across
# rebuilds — and, for released builds, across updates on other people's Macs.
# Ad-hoc identifies by cdhash, which changes every build, so it costs every user
# a re-grant every time.
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "==> Signing with '$IDENTITY'…"
  codesign --force --options runtime --sign "$IDENTITY" "$APP"
else
  echo "==> No '$IDENTITY' identity found — falling back to ad-hoc signing."
  echo "    ⚠️  You will have to re-grant Accessibility after every rebuild."
  echo "    ⚠️  Worse for licensing: keychain ACLs are tied to the signature, so"
  echo "        every rebuild makes macOS demand your password to read the trial"
  echo "        and licence items — from an app with no windows, which looks"
  echo "        exactly like malware. Licensing work is impractical without a"
  echo "        stable identity."
  echo "    Run Scripts/create-signing-cert.sh once to fix both."
  codesign --force --sign - "$APP"
fi

codesign --verify --strict --verbose=1 "$APP"
echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/ClipStack")"

if (( ! OPEN_AFTER )); then
  echo "✅ Built $APP"
  exit 0
fi

echo "==> Relaunching…"
pkill -x ClipStack 2>/dev/null || true
open "$APP"
echo "✅ $APP is running. Look for the clipboard icon in the menu bar."
echo "   Hotkey: ⌥⌘V"
