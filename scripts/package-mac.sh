#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/build-mac.sh"
mkdir -p "$ROOT/dist" "$ROOT/build/macos/package"
STAGE="$(mktemp -d "$ROOT/build/macos/package/dragon-codex-boot.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Dragon Codex Boot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/media"
# Assemble only approved files; the working app can contain personal configuration/media.
cp "$ROOT/build/Dragon Codex Boot.app/Contents/MacOS/DragonCodexBoot" "$APP/Contents/MacOS/"
cp "$ROOT/build/Dragon Codex Boot.app/Contents/Info.plist" "$APP/Contents/"
cp "$ROOT/config/launcher.macos.json" "$APP/Contents/Resources/launcher.json"
cp "$ROOT/media/startup.mp4" "$APP/Contents/Resources/media/startup.mp4"
cp "$ROOT/media/MEDIA_NOTICE.md" "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ARCHIVE="$ROOT/dist/DragonCodexBoot-0.1.0-mac-universal-with-video.zip"
ditto --norsrc -c -k --keepParent "$APP" "$ARCHIVE"
bash "$ROOT/scripts/verify-mac-package.sh" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
printf 'Packaged: %s\n' "$ARCHIVE"
