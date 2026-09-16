#!/usr/bin/env bash
# One-time setup: creates a self-signed code-signing certificate in your login
# keychain so ClipStack always gets the SAME signing identity.
#
# Why this matters: an ad-hoc signature (`codesign --sign -`) has no identity
# beyond its cdhash, and the cdhash changes on every build. macOS ties the
# Accessibility grant to the signature, so ad-hoc means re-granting Accessibility
# after every single rebuild. A stable certificate pins the grant to the cert
# instead, so you grant it once.
#
# Run this once. macOS will ask for your password / permission a couple of times
# — that is the keychain, not this script, and it is expected.
set -euo pipefail

IDENTITY="ClipStack Local"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "✅ Signing identity '$IDENTITY' already exists. Nothing to do."
  exit 0
fi

echo "==> Generating a self-signed code-signing certificate…"
cat > "$WORKDIR/openssl.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = ClipStack Local

[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$WORKDIR/openssl.cnf" \
  -keyout "$WORKDIR/key.pem" \
  -out "$WORKDIR/cert.pem" 2>/dev/null

# Apple's `security import` uses the old Security-framework PKCS#12 parser, which
# understands neither OpenSSL 3's default PBES2/AES-256 encryption nor its SHA-256
# MAC. Without the legacy options below it fails with "MAC verification failed
# during PKCS12 import (wrong password?)". LibreSSL — what /usr/bin/openssl is —
# already defaults to the old algorithms and has no -legacy flag, so only pass
# these when the available openssl understands them.
LEGACY_OPTS=()
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then
  LEGACY_OPTS=(-legacy -macalg sha1)
fi

# A real password, not an empty one. PKCS#12 leaves empty passwords ambiguous —
# OpenSSL MACs over a zero-length string, Apple tries a null password — and they
# disagree. The password is only used to hand the key over, and dies with $WORKDIR.
P12_PASSWORD="$(openssl rand -hex 16)"

openssl pkcs12 -export "${LEGACY_OPTS[@]}" \
  -inkey "$WORKDIR/key.pem" \
  -in "$WORKDIR/cert.pem" \
  -name "$IDENTITY" \
  -passout "pass:$P12_PASSWORD" \
  -out "$WORKDIR/identity.p12"

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

echo "==> Importing into your login keychain…"
security import "$WORKDIR/identity.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -A

echo "==> Marking the certificate as trusted for code signing…"
echo "    (macOS will ask for your login password here.)"
security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$WORKDIR/cert.pem"

echo
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "✅ Done. '$IDENTITY' is ready — now run Scripts/build-app.sh."
  echo "   The first codesign may show a keychain prompt; choose 'Always Allow'."
else
  echo "⚠️  The identity was imported but is not showing as valid yet."
  echo "   Open Keychain Access → login → Certificates → '$IDENTITY',"
  echo "   then set Trust → Code Signing to 'Always Trust'."
  exit 1
fi
