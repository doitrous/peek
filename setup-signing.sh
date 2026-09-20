#!/bin/bash
# One-time: create a self-signed code-signing identity in the login keychain so
# Peek keeps a STABLE signature (and therefore stable TCC permission grants)
# across rebuilds. Safe to re-run — it no-ops if the identity already exists.
set -euo pipefail

CERT_NAME="Peek Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Identity '$CERT_NAME' already exists — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = codesign
prompt             = no
[ dn ]
CN = $CERT_NAME
[ codesign ]
keyUsage             = critical, digitalSignature
extendedKeyUsage     = critical, codeSigning
basicConstraints     = critical, CA:false
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" 2>/dev/null

# -legacy + SHA1 MAC/PBE: OpenSSL 3.x's default p12 cipher isn't readable by
# macOS `security import` (MAC verification fails) — the legacy format is.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/peek.p12" -passout pass:peek -name "$CERT_NAME" \
  -legacy -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES 2>/dev/null

# -T /usr/bin/codesign lets codesign use the key. macOS may show a one-time
# keychain prompt on the first sign — click "Always Allow".
security import "$TMP/peek.p12" -k "$KEYCHAIN" -P peek -T /usr/bin/codesign

echo "Created code-signing identity: $CERT_NAME"
