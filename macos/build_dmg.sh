#!/bin/bash
# Create a DMG installer from the .app bundle.
# Usage: ./macos/build_dmg.sh <app_version> [arch]
#
# Requires: create-dmg (brew install create-dmg)

set -euo pipefail

APP_VERSION="${1:?Usage: build_dmg.sh <app_version> [arch]}"
ARCH="${2:-$(uname -m)}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/dist/macos"
APP_BUNDLE="$BUILD_DIR/JustDNALite.app"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "ERROR: $APP_BUNDLE not found. Run build_app.sh first."
    exit 1
fi

case "$ARCH" in
    arm64|aarch64) ARCH_LABEL="arm64" ;;
    x86_64|amd64)  ARCH_LABEL="x64" ;;
    *)             ARCH_LABEL="$ARCH" ;;
esac

DMG_NAME="JustDNALite-${APP_VERSION}-${ARCH_LABEL}.dmg"
DMG_PATH="$REPO_ROOT/dist/$DMG_NAME"

rm -f "$DMG_PATH"

create-dmg \
    --volname "Just DNA Lite" \
    --volicon "$SCRIPT_DIR/icon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "JustDNALite.app" 150 190 \
    --app-drop-link 450 190 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$BUILD_DIR/" \
    || true  # create-dmg returns non-zero when no icon file exists; DMG is still valid

if [ -f "$DMG_PATH" ]; then
    echo "Created $DMG_PATH"
else
    echo "ERROR: Failed to create DMG"
    exit 1
fi
