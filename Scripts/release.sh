#!/usr/bin/env bash
# Cuts a release: bump version, test, build universal, sign, DMG, publish to GitHub.
#
#   ./Scripts/release.sh 1.1.0
#   ./Scripts/release.sh 1.1.0 --dry-run    everything except tagging and publishing
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "usage: $0 <version>   e.g. $0 1.1.0" >&2
  exit 2
fi

IDENTITY="ClipStack Local"
TAG="v$VERSION"

# --- Guards -----------------------------------------------------------------

# Releasing an ad-hoc build would silently cost every existing user their
# Accessibility grant, because TCC keys off the signing certificate.
if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "❌ No '$IDENTITY' signing identity. Run Scripts/create-signing-cert.sh." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "❌ Working tree is dirty. Commit or stash first." >&2
  git status --short >&2
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "❌ Tag $TAG already exists." >&2
  exit 1
fi

# --- Build ------------------------------------------------------------------

echo "==> Running tests…"
./Scripts/test.sh >/dev/null

echo "==> Setting version to $VERSION…"
plutil -replace CFBundleShortVersionString -string "$VERSION" Resources/Info.plist
plutil -replace CFBundleVersion -string "$VERSION" Resources/Info.plist

echo "==> Building universal release…"
./Scripts/build-app.sh --no-open >/dev/null

ARCHS=$(lipo -archs ClipStack.app/Contents/MacOS/ClipStack)
if [[ "$ARCHS" != *"x86_64"* || "$ARCHS" != *"arm64"* ]]; then
  echo "❌ Expected a universal binary, got: $ARCHS" >&2
  exit 1
fi
echo "    architectures: $ARCHS"

./Scripts/make-dmg.sh "$VERSION"
DMG="dist/ClipStack-${VERSION}.dmg"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

# --- Publish ----------------------------------------------------------------

if (( DRY_RUN )); then
  echo
  echo "✅ Dry run complete. Would have tagged $TAG and published $DMG"
  echo "   Version bump is left in Resources/Info.plist — revert it if you are not releasing."
  exit 0
fi

echo "==> Committing and tagging…"
git add Resources/Info.plist
git commit -m "Release $TAG"
git tag -a "$TAG" -m "ClipStack $VERSION"
git push origin HEAD --tags

echo "==> Publishing GitHub release…"
NOTES=$(cat <<NOTE
## Install

1. Download \`ClipStack-${VERSION}.dmg\` below and drag ClipStack to Applications.
2. The first launch is blocked — ClipStack is not notarized (no paid Apple
   Developer account). Open **System Settings → Privacy & Security**, scroll to
   the bottom, and click **Open Anyway**.
   Or, in Terminal: \`xattr -dr com.apple.quarantine /Applications/ClipStack.app\`
3. Grant Accessibility when asked — it is what lets ClipStack press ⌘V for you.
   Everything else works without it.

Universal (Apple Silicon + Intel), macOS 14 or later.

\`\`\`
sha256  $SHA
\`\`\`
NOTE
)

gh release create "$TAG" "$DMG" --title "ClipStack $VERSION" --notes "$NOTES"
echo "✅ Released $TAG"
gh release view "$TAG" --json url --jq .url
