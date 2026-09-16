#!/usr/bin/env bash
# Backs up the ClipStack signing identity to a password-protected .p12.
#
# Why you want this: macOS ties each user's Accessibility grant to the
# certificate in the signature. Lose this key and every future release is signed
# by a *different* identity, so everyone who already installed ClipStack has to
# re-grant Accessibility. Keep the exported file somewhere you will still have
# it after a disk wipe.
#
#   ./Scripts/export-signing-cert.sh ~/Backups/clipstack-signing.p12
set -euo pipefail

IDENTITY="ClipStack Local"
OUTPUT="${1:-clipstack-signing.p12}"

if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "No '$IDENTITY' identity found. Run Scripts/create-signing-cert.sh first." >&2
  exit 1
fi

if [[ -e "$OUTPUT" ]]; then
  echo "Refusing to overwrite existing $OUTPUT" >&2
  exit 1
fi

echo "==> Exporting '$IDENTITY'."
echo "    You will be asked twice: once for a password to protect the export,"
echo "    then by macOS for permission to read the key from your keychain."
security export -t identities -f pkcs12 -o "$OUTPUT"

chmod 600 "$OUTPUT"
echo "✅ Wrote $OUTPUT"
echo "   Store it somewhere safe and off this machine. Restore with:"
echo "     security import $OUTPUT -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -A"
