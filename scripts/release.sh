#!/usr/bin/env bash
# Builds everything a release ships, into dist/:
#   Lookshift-<version>.dmg      the download for people (drag into Applications)
#   Lookshift-<version>.zip      the same app zipped, for Homebrew and updaters
#   SHA256SUMS.txt               checksums of both
#
# Unsigned by default. To sign and notarize, set:
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)"
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD   (an app-specific password)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
DMG="dist/Lookshift-$VERSION.dmg"
ZIP="dist/Lookshift-$VERSION.zip"

scripts/test.sh
scripts/build-app.sh

# Never ship networking code or the debug-only developer options.
BINARY=dist/Lookshift.app/Contents/MacOS/Lookshift
if nm -u "$BINARY" | grep -qE "URLSession|NSURLConnection|_socket|CFSocket|_nw_"; then
    echo "The app uses networking APIs; refusing to release" >&2; exit 1
fi
if strings "$BINARY" | grep -qE "^--(print-readings|preview-onboarding)$"; then
    echo "Developer options are in the release build; refusing to release" >&2; exit 1
fi

scripts/make-dmg.sh

if [[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_APPLE_ID:-}" ]]; then
    echo "Notarizing $DMG..."
    xcrun notarytool submit "$DMG" --wait \
        --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD"
    xcrun stapler staple "$DMG"
    # The app inside the .zip gets the same ticket, so it opens offline too.
    xcrun stapler staple dist/Lookshift.app
fi

# ditto keeps the signature and extended attributes that a plain zip would drop.
rm -f "$ZIP"
ditto -c -k --keepParent dist/Lookshift.app "$ZIP"
(cd dist && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > SHA256SUMS.txt)
cat dist/SHA256SUMS.txt
