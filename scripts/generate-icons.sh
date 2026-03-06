#!/bin/bash
set -euo pipefail

# Generate macOS app icon assets from a 1024x1024 source PNG.
# Usage: scripts/generate-icons.sh <source_1024x1024.png>

SOURCE="${1:?Usage: $0 <source_1024x1024.png>}"

if [ ! -f "$SOURCE" ]; then
    echo "Error: Source file '$SOURCE' not found."
    exit 1
fi

APPICONSET="Whiplash/Assets.xcassets/AppIcon.appiconset"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/$APPICONSET"

mkdir -p "$OUTPUT_DIR"

# macOS icon sizes: point sizes and their scale factors
# Format: "pointsize scale" → pixel size = pointsize * scale
SIZES=(
    "16 1"
    "16 2"
    "32 1"
    "32 2"
    "128 1"
    "128 2"
    "256 1"
    "256 2"
    "512 1"
    "512 2"
)

echo "Generating app icons from: $SOURCE"

for entry in "${SIZES[@]}"; do
    read -r points scale <<< "$entry"
    pixels=$((points * scale))

    if [ "$scale" -eq 1 ]; then
        filename="icon_${points}x${points}.png"
    else
        filename="icon_${points}x${points}@${scale}x.png"
    fi

    echo "  ${filename} (${pixels}x${pixels}px)"
    sips -z "$pixels" "$pixels" "$SOURCE" --out "$OUTPUT_DIR/$filename" > /dev/null 2>&1
done

# Generate .icns for DMG volume icon
echo "Generating .icns for DMG volume icon..."
ICONSET_DIR=$(mktemp -d)/Whiplash.iconset
mkdir -p "$ICONSET_DIR"

ICNS_SIZES=(
    "16 1"
    "16 2"
    "32 1"
    "32 2"
    "128 1"
    "128 2"
    "256 1"
    "256 2"
    "512 1"
    "512 2"
)

for entry in "${ICNS_SIZES[@]}"; do
    read -r points scale <<< "$entry"
    pixels=$((points * scale))

    if [ "$scale" -eq 1 ]; then
        icns_name="icon_${points}x${points}.png"
    else
        icns_name="icon_${points}x${points}@${scale}x.png"
    fi

    sips -z "$pixels" "$pixels" "$SOURCE" --out "$ICONSET_DIR/$icns_name" > /dev/null 2>&1
done

mkdir -p "$PROJECT_DIR/build"
iconutil -c icns "$ICONSET_DIR" -o "$PROJECT_DIR/build/Whiplash.icns"
rm -rf "$(dirname "$ICONSET_DIR")"

echo "Done. Icons written to $APPICONSET"
echo "DMG volume icon written to build/Whiplash.icns"
