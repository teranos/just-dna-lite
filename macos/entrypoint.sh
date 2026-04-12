#!/bin/bash
# Just DNA Lite - macOS app launcher
# This script is placed inside JustDNALite.app/Contents/MacOS/

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$SCRIPT_DIR/../Resources"
APP_DIR="$RESOURCES_DIR/app"
UV="$RESOURCES_DIR/uv"

export PATH="$RESOURCES_DIR:$PATH"

cd "$APP_DIR"

if [ ! -d ".venv" ]; then
    osascript -e 'display notification "Setting up environment (first launch)... This may take a few minutes." with title "Just DNA Lite"' 2>/dev/null || true
    "$UV" sync 2>&1 | tee /tmp/just-dna-lite-setup.log
fi

(sleep 25 && open "http://localhost:3000") &

exec "$UV" run start
