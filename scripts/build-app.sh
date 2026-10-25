#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) dist/Lookshift.app.
#
#   scripts/build-app.sh                 ad-hoc signed, for local use and free downloads
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" scripts/build-app.sh
#                                        signed for notarization (see scripts/release.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=Lookshift
BUNDLE_ID=${BUNDLE_ID:-io.github.samapara.Lookshift}
VERSION=$(cat VERSION)
BUILD=${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
ARCHS=${ARCHS:-"arm64 x86_64"}
APP="dist/$APP_NAME.app"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
binaries=()
for arch in $ARCHS; do
    echo "Building ${arch}..."
    triple="$arch-apple-macosx14.0"
    swift build -c release --product "$APP_NAME" --triple "$triple" 2>&1 | grep -E "error|warning: [^s]" || true
    # Newer SwiftPM writes every triple to the same folder, so copy each binary out right away.
    bin="$(swift build -c release --triple "$triple" --show-bin-path)/$APP_NAME"
    [[ "$(lipo -archs "$bin")" == "$arch" ]] || { echo "Expected a $arch binary at $bin" >&2; exit 1; }
    cp "$bin" "$STAGE/$APP_NAME-$arch"
    binaries+=("$STAGE/$APP_NAME-$arch")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/$APP_NAME" "${binaries[@]}"
sed -e "s/\$(BUNDLE_ID)/$BUNDLE_ID/" -e "s/\$(VERSION)/$VERSION/" -e "s/\$(BUILD)/$BUILD/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --force --options runtime --timestamp --entitlements Resources/Lookshift.entitlements \
        --sign "$DEVELOPER_ID" "$APP"
else
    codesign --force --options runtime --entitlements Resources/Lookshift.entitlements --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION, build $BUILD, $(lipo -archs "$APP/Contents/MacOS/$APP_NAME"))"
