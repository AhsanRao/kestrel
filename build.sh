#!/usr/bin/env bash
# swift build → Kestrel.app, ad-hoc signed.
# The bundle id and the signature together own the TCC grants (microphone, screen recording,
# accessibility), so neither may change between builds or macOS forgets every permission.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="${CONFIG:-release}"
VERSION="$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' docs/CHANGELOG.md 2>/dev/null | head -1)"
VERSION="${VERSION:-0.0.0}"
APP="Kestrel.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/Kestrel"

echo "==> assembling $APP ($VERSION)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Kestrel"

sed "s/__VERSION__/$VERSION/g" Resources/Info.plist.template > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cp -R Resources/Prompts "$APP/Contents/Resources/"
cp Resources/DefaultMemory.md "$APP/Contents/Resources/"

if [ ! -f assets/AppIcon.icns ] || [ ! -f assets/MenuBarIcon.png ]; then
  echo "==> icons missing, generating"
  ./scripts/make-icon.sh
fi
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"

# Ad-hoc signing (`--sign -`) derives the signature from a hash of the binary, so *every* rebuild
# produces a new identity and macOS silently drops Accessibility and Screen Recording — the grant
# stays ticked in System Settings and stops working, which is a miserable thing to debug. A stable
# self-signed certificate fixes it: the Designated Requirement is then the certificate, which does
# not change when the code does. `scripts/make-signing-cert.sh` creates one; without it this falls
# back to ad-hoc, and the permissions have to be re-granted after each build.
IDENTITY="${KESTREL_SIGN_IDENTITY:-Kestrel Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
  echo "==> codesign as \"$IDENTITY\" (grants survive rebuilds)"
  codesign --force --deep --sign "$IDENTITY" --identifier dev.0xash.kestrel "$APP"
else
  echo "==> ad-hoc codesign — permissions will need re-granting after this build"
  echo "    run scripts/make-signing-cert.sh once to stop that happening"
  codesign --force --deep --sign - --identifier dev.0xash.kestrel "$APP"
fi
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

echo "==> built $APP"
