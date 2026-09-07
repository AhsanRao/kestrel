#!/usr/bin/env bash
# Creates the self-signed code-signing certificate Kestrel is signed with, once.
#
# Why this exists: an ad-hoc signature (`codesign --sign -`) is a hash of the binary, so every
# rebuild is a different identity as far as macOS is concerned. TCC keys Accessibility and Screen
# Recording to that identity, so each build silently revokes them — the checkbox stays ticked in
# System Settings and the app is denied anyway. Signing with a certificate instead makes the
# Designated Requirement the certificate, which does not change when the code does.
#
# Run once. Everything after it is `make build` as usual.
set -euo pipefail

NAME="${KESTREL_SIGN_IDENTITY:-Kestrel Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -qF "$NAME"; then
  echo "==> \"$NAME\" already exists — nothing to do"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> generating a self-signed code-signing certificate"
openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$NAME/O=dev.0xash.kestrel" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# The key and the certificate go in separately, as PEM. The obvious route — bundle them into a
# .p12 and import that — does not work here: OpenSSL 3 defaults to AES-256 and a SHA-256 MAC, and
# the macOS Security framework cannot verify either, so the import dies on "MAC verification failed
# during PKCS12 import (wrong password?)" no matter what password you give it. Two PEM files avoid
# the container, and the keychain pairs them back into an identity by public key.
echo "==> importing the private key"
security import "$WORK/key.pem" -k "$KEYCHAIN" -T /usr/bin/codesign
echo "==> importing the certificate"
security import "$WORK/cert.pem" -k "$KEYCHAIN" -T /usr/bin/codesign

echo "==> trusting it for code signing (asks for your login password)"
# User trust domain, so this never needs sudo.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

# Stops the "codesign wants to sign using key" dialog on every subsequent build.
security set-key-partition-list -S apple-tool:,apple: -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

if ! security find-identity -v -p codesigning | grep -qF "$NAME"; then
  echo
  echo "The certificate imported but is not a usable signing identity yet." >&2
  echo "Open Keychain Access, find \"$NAME\" under login, and set Trust ▸ Code Signing" >&2
  echo "to \"Always Trust\", then run: make build" >&2
  exit 1
fi

echo
security find-identity -v -p codesigning | sed 's/^/    /'
echo
echo "Done. Now run: make build"
echo "Then grant Accessibility and Screen Recording once more — and only once more."
