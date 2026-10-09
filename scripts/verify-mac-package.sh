#!/bin/bash
set -euo pipefail
ARCHIVE="${1:?Usage: verify-mac-package.sh archive.zip}"
count=0
while IFS= read -r entry; do
  case "$entry" in
    */) continue ;;
    "Dragon Codex Boot.app/Contents/Info.plist"|\
    "Dragon Codex Boot.app/Contents/MacOS/DragonCodexBoot"|\
    "Dragon Codex Boot.app/Contents/Resources/launcher.json"|\
    "Dragon Codex Boot.app/Contents/Resources/DragonCodexBoot.icns"|\
    "Dragon Codex Boot.app/Contents/Resources/media/startup.mp4"|\
    "Dragon Codex Boot.app/Contents/Resources/LICENSE"|\
    "Dragon Codex Boot.app/Contents/Resources/MEDIA_NOTICE.md"|\
    "Dragon Codex Boot.app/Contents/Resources/THIRD_PARTY_NOTICES.md"|\
    "Dragon Codex Boot.app/Contents/_CodeSignature/CodeResources") count=$((count + 1)) ;;
    *) printf 'Unexpected package file: %s\n' "$entry" >&2; exit 1 ;;
  esac
done < <(unzip -Z1 "$ARCHIVE")
[[ "$count" -eq 9 ]] || { echo 'Package is missing required files.' >&2; exit 1; }
unzip -tq "$ARCHIVE"
echo 'Package contains only the nine approved app files.'
