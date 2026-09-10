#!/usr/bin/env bash
# Builds every icon asset from assets/kestrel-logo.svg — the original artwork, never a redraw.
#
#   assets/AppIcon.icns                 app icon (10 sizes, 16→1024)
#   assets/MenuBarIcon.png              36 px black template for the status item
#   assets/kestrel-menubar-template.svg the same silhouette as the spec's monochrome asset
#
# The logo SVG carries the artwork as an embedded PNG, so it is extracted losslessly; a purely
# vector source would be rendered by Quick Look instead.
set -euo pipefail

cd "$(dirname "$0")/.."
ASSETS="assets"
SOURCE="$ASSETS/kestrel-logo.svg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$SOURCE" ] || { echo "missing $SOURCE" >&2; exit 1; }

echo "==> extracting artwork from $SOURCE"
python3 - "$SOURCE" "$WORK/logo.png" <<'PY'
import base64, pathlib, re, sys
svg = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'href="data:image/(?:png|jpeg);base64,([A-Za-z0-9+/=\s]+)"', svg)
if not match:
    sys.exit("no embedded raster in the SVG")
pathlib.Path(sys.argv[2]).write_bytes(base64.b64decode(re.sub(r"\s", "", match.group(1))))
PY

if [ ! -s "$WORK/logo.png" ]; then
  echo "==> falling back to Quick Look rendering"
  qlmanage -t -s 1254 -o "$WORK" "$SOURCE" >/dev/null 2>&1
  mv "$WORK"/*.png "$WORK/logo.png"
fi

# The artwork on its own, alpha intact, for the logo in Kestrel's own windows. The icon masters
# below sit it on a plate, which is right for the Dock and wrong on glass.
cp "$WORK/logo.png" "$ASSETS/KestrelMark.png"

echo "==> building masters"
swift scripts/icon-tool.swift "$WORK/logo.png" "$ASSETS"

echo "==> assembling AppIcon.icns"
ICONSET="$ASSETS/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" \
            "512 icon_512x512" "1024 icon_512x512@2x"; do
  set -- $spec
  sips -z "$1" "$1" "$ASSETS/AppIconMaster.png" --out "$ICONSET/$2.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ASSETS/AppIcon.icns"

echo "==> done"
ls -la "$ASSETS/AppIcon.icns" "$ASSETS/MenuBarIcon.png" "$ASSETS/KestrelMark.png" "$ASSETS/kestrel-menubar-template.svg"
