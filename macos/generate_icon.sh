#!/bin/bash
# Generate macOS .icns icon from the project logo.
# Requires: sips (built into macOS) and iconutil (built into macOS)
# Usage: ./macos/generate_icon.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$REPO_ROOT/images/just_dna_seq.jpg"
ICONSET="$SCRIPT_DIR/icon.iconset"
OUTPUT="$SCRIPT_DIR/icon.icns"

if [ ! -f "$SOURCE" ]; then
    echo "ERROR: Source image not found: $SOURCE"
    exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Convert source to PNG first (iconutil requires PNG, not JPEG)
PNG_SOURCE="/tmp/just_dna_icon_source.png"
sips -s format png "$SOURCE" --out "$PNG_SOURCE" > /dev/null 2>&1

# Generate all required sizes for macOS iconset
for size in 16 32 128 256 512; do
    sips -z $size $size "$PNG_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null 2>&1
done

# Retina (@2x) versions
sips -z 32 32     "$PNG_SOURCE" --out "$ICONSET/icon_16x16@2x.png"   > /dev/null 2>&1
sips -z 64 64     "$PNG_SOURCE" --out "$ICONSET/icon_32x32@2x.png"   > /dev/null 2>&1
sips -z 256 256   "$PNG_SOURCE" --out "$ICONSET/icon_128x128@2x.png" > /dev/null 2>&1
sips -z 512 512   "$PNG_SOURCE" --out "$ICONSET/icon_256x256@2x.png" > /dev/null 2>&1
sips -z 1024 1024 "$PNG_SOURCE" --out "$ICONSET/icon_512x512@2x.png" > /dev/null 2>&1

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$ICONSET" "$PNG_SOURCE"

echo "Generated $OUTPUT"
