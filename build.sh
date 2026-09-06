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

echo "==> ad-hoc codesign"
codesign --force --deep --sign - --identifier dev.0xash.kestrel "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

echo "==> built $APP"
