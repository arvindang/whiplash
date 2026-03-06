#!/bin/bash
set -euo pipefail

# Full release pipeline: build, sign, notarize, package DMG.
#
# Required env vars:
#   TEAM_ID          — Apple Developer Team ID
#   APPLE_ID         — Apple ID email (for notarytool)
#   KEYCHAIN_PROFILE — notarytool stored credentials profile name
#
# Usage: scripts/release.sh

: "${TEAM_ID:?Set TEAM_ID to your Apple Developer Team ID}"
: "${KEYCHAIN_PROFILE:?Set KEYCHAIN_PROFILE to your notarytool stored credentials profile}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="Whiplash"
SCHEME="Whiplash"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

# Read version from Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Whiplash/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Whiplash/Info.plist)
echo "=== Building $APP_NAME v$VERSION ($BUILD) ==="

# Clean previous build artifacts
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR"

# Step 1: Regenerate Xcode project
echo ""
echo "--- Step 1: Generating Xcode project ---"
xcodegen generate

# Step 2: Archive
echo ""
echo "--- Step 2: Archiving ---"
xcodebuild archive \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    TEAM_ID="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    -quiet

# Step 3: Export .app from archive
echo ""
echo "--- Step 3: Exporting .app ---"
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$APP_PATH"

# Step 4: Verify code signature
echo ""
echo "--- Step 4: Verifying code signature ---"
codesign --verify --deep --strict "$APP_PATH"
echo "Code signature valid."

# Step 5: Create ZIP for notarization
echo ""
echo "--- Step 5: Creating ZIP for notarization ---"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Step 6: Submit for notarization
echo ""
echo "--- Step 6: Submitting for notarization (this may take a few minutes) ---"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

# Step 7: Staple the app
echo ""
echo "--- Step 7: Stapling notarization ticket ---"
xcrun stapler staple "$APP_PATH"

# Step 8: Create DMG
echo ""
echo "--- Step 8: Creating DMG ---"
DMG_STAGING="$BUILD_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGING"

# Apply volume icon if available
if [ -f "$BUILD_DIR/Whiplash.icns" ]; then
    # Set volume icon by mounting, copying, and setting attributes
    MOUNT_DIR=$(hdiutil attach "$DMG_PATH" -readwrite -noverify -noautoopen | tail -1 | awk '{print $3}')
    if [ -n "$MOUNT_DIR" ]; then
        cp "$BUILD_DIR/Whiplash.icns" "$MOUNT_DIR/.VolumeIcon.icns"
        SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
        hdiutil detach "$MOUNT_DIR" -quiet
        # Convert back to read-only compressed
        hdiutil convert "$DMG_PATH" -format UDZO -o "${DMG_PATH}.tmp" -ov
        mv "${DMG_PATH}.tmp" "$DMG_PATH"
    fi
fi

# Step 9: Sign and notarize DMG
echo ""
echo "--- Step 9: Signing DMG ---"
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/')
if [ -z "$IDENTITY" ]; then
    echo "Error: No Developer ID Application identity found in keychain"
    exit 1
fi
echo "Using identity: $IDENTITY"
codesign --sign "$IDENTITY" --timestamp "$DMG_PATH"

echo ""
echo "--- Step 10: Notarizing DMG ---"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

xcrun stapler staple "$DMG_PATH"

# Done
echo ""
echo "========================================="
echo "Release build complete!"
echo "  App: $APP_PATH"
echo "  DMG: $DMG_PATH"
echo "  Version: $VERSION (build $BUILD)"
echo "========================================="
echo ""
echo "To publish on GitHub:"
echo "  gh release create v$VERSION $DMG_PATH --title \"Whiplash v$VERSION\" --generate-notes"

# Clean up ZIP (only needed for notarization)
rm -f "$ZIP_PATH"
