#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build/macos"
xcrun swiftc "$ROOT/src/macos/LauncherConfig.swift" "$ROOT/src/macos/handoff-geometry.swift" "$ROOT/tests/macos/main.swift" -o "$ROOT/build/macos/config-tests"
"$ROOT/build/macos/config-tests" "$ROOT/config/launcher.macos.json"
bash -n "$ROOT/scripts/build-mac.sh" "$ROOT/scripts/build-mac-icon.sh" "$ROOT/scripts/package-mac.sh" "$ROOT/scripts/test-mac.sh" "$ROOT/scripts/verify-mac-package.sh"
bash "$ROOT/scripts/build-mac.sh"
APP="$ROOT/build/Dragon Codex Boot.app"
codesign --verify --deep --strict "$APP"
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist")"
test -s "$APP/Contents/Resources/$ICON_NAME"
"$APP/Contents/MacOS/DragonCodexBoot" --preview --check
# Rendering/real-client handoff are checked separately on a logged-in Mac desktop.
