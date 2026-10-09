#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build/macos"
STAGE="$(mktemp -d "$ROOT/build/macos/icon.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ICONSET="$STAGE/DragonCodexBoot.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT/assets/mac-app-icon.png" \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$ROOT/assets/mac-app-icon.png" \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/build/macos/DragonCodexBoot.icns"
