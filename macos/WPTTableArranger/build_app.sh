#!/bin/bash
# Build a distributable macOS application bundle.
#
# Development (native architecture, ad-hoc signature):
#   ./build_app.sh
#
# Universal release signed with Developer ID:
#   UNIVERSAL=1 SIGN_IDENTITY="Developer ID Application: ..." ./build_app.sh
#
# Optional notarization uses a credential profile created with `notarytool store-credentials`:
#   NOTARY_PROFILE="profile-name" UNIVERSAL=1 SIGN_IDENTITY="Developer ID Application: ..." ./build_app.sh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Poker Table Arranger"
BIN_NAME="PokerTableArranger"
APP_DIR="$APP_NAME.app"
UNIVERSAL="${UNIVERSAL:-0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
RELEASE_DIR="${RELEASE_DIR:-$PWD/release}"
SWIFT_BUILD_ARGS=()
if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
    SWIFT_BUILD_ARGS+=(--disable-sandbox)
fi

stage_bundle() {
    local executable_path="$1"
    rm -rf "$APP_DIR"
    mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
    cp "$executable_path" "$APP_DIR/Contents/MacOS/$BIN_NAME"
    cp "Info.plist" "$APP_DIR/Contents/Info.plist"
}

if [[ "$UNIVERSAL" == "1" ]]; then
    echo "==> building arm64"
    swift build "${SWIFT_BUILD_ARGS[@]}" -c release --triple arm64-apple-macosx13.0
    ARM_BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" -c release --triple arm64-apple-macosx13.0 --show-bin-path)"

    echo "==> building x86_64"
    swift build "${SWIFT_BUILD_ARGS[@]}" -c release --triple x86_64-apple-macosx13.0
    INTEL_BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" -c release --triple x86_64-apple-macosx13.0 --show-bin-path)"

    TEMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TEMP_DIR"' EXIT
    /usr/bin/lipo -create \
        "$ARM_BIN_DIR/$BIN_NAME" \
        "$INTEL_BIN_DIR/$BIN_NAME" \
        -output "$TEMP_DIR/$BIN_NAME"
    BUILT_BIN="$TEMP_DIR/$BIN_NAME"
else
    echo "==> building native architecture"
    swift build "${SWIFT_BUILD_ARGS[@]}" -c release
    BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" -c release --show-bin-path)"
    BUILT_BIN="$BIN_DIR/$BIN_NAME"
fi

if [[ ! -f "$BUILT_BIN" ]]; then
    echo "error: built binary not found at $BUILT_BIN" >&2
    exit 1
fi

echo "==> assembling $APP_DIR"
stage_bundle "$BUILT_BIN"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "==> applying development-only ad-hoc signature"
    codesign --force --deep --sign - "$APP_DIR"
else
    echo "==> signing with Developer ID"
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

mkdir -p "$RELEASE_DIR"
ZIP_PATH="$RELEASE_DIR/$APP_NAME.zip"
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        echo "error: notarization requires a Developer ID Application signature" >&2
        exit 1
    fi
    echo "==> submitting to Apple notary service"
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_DIR"
    xcrun stapler validate "$APP_DIR"

    rm -f "$ZIP_PATH"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
fi

echo "==> done"
echo "App: $PWD/$APP_DIR"
echo "Archive: $ZIP_PATH"
