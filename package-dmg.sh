#!/bin/bash
# Builds Scripta.app (release) and packages it into build/Scripta-macOS-arm64.dmg,
# a compressed disk image with the app and a symlink to /Applications for drag-and-drop install.
set -euo pipefail
cd "$(dirname "$0")"

[ "$(uname -s)" = "Darwin" ] || { echo "package-dmg.sh richiede macOS." >&2; exit 1; }

./build-app.sh release

APP="build/Scripta.app"
DMG="build/Scripta-macOS-arm64.dmg"
STAGING="build/dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
# ditto preserves the code signature, extended attributes and the bundle's symlinks.
ditto "$APP" "$STAGING/Scripta.app"
ln -s /Applications "$STAGING/Applications"

# `diskutil image` replaces the deprecated `hdiutil create` on recent macOS; older systems lack it.
if diskutil image create from --help >/dev/null 2>&1; then
    # Its progress goes to stderr: show it only on failure.
    out=$(diskutil image create from --format UDZO --volumeName "Scripta" "$STAGING" "$DMG" 2>&1) || { echo "$out" >&2; exit 1; }
else
    hdiutil create -volname "Scripta" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
fi
rm -rf "$STAGING"
hdiutil verify "$DMG" >/dev/null

echo "Creato $DMG ($(du -h "$DMG" | cut -f1))"
