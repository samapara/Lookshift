#!/usr/bin/env bash
# Packs dist/Lookshift.app into dist/Lookshift-<version>.dmg: a window with the app,
# an arrow and an Applications shortcut, so people drag it into Applications.
#
#   scripts/build-app.sh && scripts/make-dmg.sh
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" scripts/make-dmg.sh   also signs the .dmg
#
# Laying out the window asks Finder through AppleScript; the first run may ask you to
# allow Terminal to control Finder. Without that the .dmg still works, just unarranged.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=Lookshift
VERSION=$(cat VERSION)
APP="dist/$APP_NAME.app"
DMG="dist/$APP_NAME-$VERSION.dmg"
[[ -d "$APP" ]] || { echo "Build the app first: scripts/build-app.sh" >&2; exit 1; }

WORK=$(mktemp -d)
MOUNT=""
trap '[[ -n "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet 2>/dev/null; rm -rf "$WORK"' EXIT

# Contents of the disk image.
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
# A two-resolution TIFF keeps the background sharp on Retina screens.
sips -z 400 660 Resources/dmg-background.png --out "$WORK/background.png" >/dev/null
cp Resources/dmg-background.png "$WORK/background@2x.png"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$STAGE/.background/background.tiff" 2>/dev/null
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

# A writable image to arrange, then a compressed read-only copy to ship.
hdiutil create -quiet -srcfolder "$STAGE" -volname "$APP_NAME" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
# Finder only sees disks mounted under /Volumes, so let hdiutil pick the mount point there.
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | awk -F'\t' '/\/Volumes\// {print $NF}')
[[ -d "$MOUNT" ]] || { echo "Couldn't mount the disk image" >&2; exit 1; }
DISK=$(basename "$MOUNT")
# Show the custom volume icon when the .dmg is mounted.
if command -v SetFile >/dev/null; then SetFile -a C "$MOUNT"; fi

if ! osascript <<EOF
tell application "Finder"
    set theDisk to disk "$DISK"
    open theDisk
    set win to container window of theDisk
    set current view of win to icon view
    set toolbar visible of win to false
    set statusbar visible of win to false
    set bounds of win to {200, 120, 860, 520}
    set opts to icon view options of win
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff" of theDisk
    set position of item "$APP_NAME.app" of win to {165, 190}
    set position of item "Applications" of win to {495, 190}
    update theDisk without registering applications
    delay 1
    close win
end tell
EOF
then
    echo "Finder didn't arrange the window; the .dmg works but uses the default layout." >&2
fi
sync
hdiutil detach -quiet "$MOUNT"
MOUNT=""

rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
fi
hdiutil verify -quiet "$DMG"
echo "Built $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
