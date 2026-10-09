#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Dragon Codex Boot.app"
SIGNING_IDENTITY="${DRAGON_MAC_SIGNING_IDENTITY:--}"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Build this app on macOS with Xcode Command Line Tools." >&2
  exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/media" "$ROOT/build/macos"
bash "$ROOT/scripts/build-mac-icon.sh"
cp "$ROOT/build/macos/DragonCodexBoot.icns" "$APP/Contents/Resources/"
for architecture in arm64 x86_64; do
  xcrun swiftc -O -target "$architecture-apple-macos13.0" \
    "$ROOT"/src/macos/*.swift \
    -framework AppKit -framework AVFoundation -framework ScreenCaptureKit -framework QuartzCore -framework IOSurface \
    -o "$ROOT/build/macos/dragon-codex-boot-$architecture"
done
lipo -create "$ROOT/build/macos/dragon-codex-boot-arm64" \
  "$ROOT/build/macos/dragon-codex-boot-x86_64" -output "$APP/Contents/MacOS/DragonCodexBoot"
cp "$ROOT/media/startup.mp4" "$APP/Contents/Resources/media/startup.mp4"
cp "$ROOT/media/MEDIA_NOTICE.md" "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
if [[ ! -f "$APP/Contents/Resources/launcher.json" ]]; then
  cp "$ROOT/config/launcher.macos.json" "$APP/Contents/Resources/launcher.json"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.swtxbling.dragon-codex-boot</string>
  <key>CFBundleName</key><string>Dragon Codex Boot</string>
  <key>CFBundleDisplayName</key><string>Dragon Codex Boot</string>
  <key>CFBundleExecutable</key><string>DragonCodexBoot</string>
  <key>CFBundleIconFile</key><string>DragonCodexBoot.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.1</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>仅在本机内存中显示所选 Codex 窗口，用于启动动画的渐进交接。</string>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
touch "$APP"
printf 'Built: %s\n' "$APP"
