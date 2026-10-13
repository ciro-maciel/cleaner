#!/bin/bash
# Every installer bumps the patch version, builds, packs a .dmg and installs it in /Applications.
#   scripts/dist.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IFS=. read -r MAJOR MINOR PATCH < "$ROOT/VERSION"
VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
echo "$VERSION" > "$ROOT/VERSION"

"$ROOT/scripts/build.sh"

STAGE="$(mktemp -d)"
cp -R "$ROOT/dist/Cleaner.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$ROOT/dist/Cleaner-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Cleaner $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# Install from the packed image, the same bytes a tester gets.
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -nobrowse -mountpoint "$MOUNT" >/dev/null
# ⌘Q and "quit" only hide Cleaner to the menu bar; stop the process for the swap.
pkill -x Cleaner >/dev/null 2>&1 || true
rm -rf /Applications/Cleaner.app
cp -R "$MOUNT/Cleaner.app" /Applications/
hdiutil detach "$MOUNT" >/dev/null
echo "Installed /Applications/Cleaner.app ($VERSION) from $DMG"
