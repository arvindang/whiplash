#!/bin/bash
set -euo pipefail

# Bump version in both Info.plist and project.yml.
# Usage: scripts/bump-version.sh <version> [build_number]
# Example: scripts/bump-version.sh 1.2.0 42

VERSION="${1:?Usage: $0 <version> [build_number]}"
BUILD="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PLIST="$PROJECT_DIR/Whiplash/Info.plist"
PROJECT_YML="$PROJECT_DIR/project.yml"

# Update Info.plist
echo "Updating Info.plist..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
if [ -n "$BUILD" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
fi

# Update project.yml
echo "Updating project.yml..."
sed -i '' "s/CFBundleShortVersionString: \".*\"/CFBundleShortVersionString: \"$VERSION\"/" "$PROJECT_YML"
if [ -n "$BUILD" ]; then
    sed -i '' "s/CFBundleVersion: \".*\"/CFBundleVersion: \"$BUILD\"/" "$PROJECT_YML"
fi

echo "Version set to $VERSION${BUILD:+ (build $BUILD)}"
echo "Run 'xcodegen generate' to regenerate the Xcode project."
