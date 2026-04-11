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

# Generate all required sizes for macOS iconset
sips -z 16 16     "$SOURCE" --out "$ICONSET/icon_16x16.png"      > /dev/null 2>&1
sips -z 32 32     "$SOURCE" --out "$ICONSET/icon_16x16@2x.png"   > /dev/null 2>&1
sips -z 32 32     "$SOURCE" --out "$ICONSET/icon_32x32.png"      > /dev/null 2>&1
sips -z 64 64     "$SOURCE" --out "$ICONSET/icon_32x32@2x.png"   > /dev/null 2>&1
sips -z 128 128   "$SOURCE" --out "$ICONSET/icon_128x128.png"    > /dev/null 2>&1
sips -z 256 256   "$SOURCE" --out "$ICONSET/icon_128x128@2x.png" > /dev/null 2>&1
sips -z 256 256   "$SOURCE" --out "$ICONSET/icon_256x256.png"    > /dev/null 2>&1
sips -z 512 512   "$SOURCE" --out "$ICONSET/icon_256x256@2x.png" > /dev/null 2>&1
sips -z 512 512   "$SOURCE" --out "$ICONSET/icon_512x512.png"    > /dev/null 2>&1
sips -z 1024 1024 "$SOURCE" --out "$ICONSET/icon_512x512@2x.png" > /dev/null 2>&1

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$ICONSET"

echo "Generated $OUTPUT"
