#!/bin/bash
# build-web-client.sh
#
# Builds the Local_RSC React app for iOS embedding and copies the output
# into the iOS Swift package resources directory.
#
# Usage: bash iOS_Client/build-web-client.sh
# Run from the repo root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_RSC_DIR="$REPO_ROOT/../Local_RSC"
DEST_DIR="$REPO_ROOT/iOS_Client/OpenRSC/OpenRSC/Sources/WebClient"

if [ ! -d "$LOCAL_RSC_DIR" ]; then
    echo "ERROR: Local_RSC not found at $LOCAL_RSC_DIR"
    exit 1
fi

echo "==> Installing dependencies..."
cd "$LOCAL_RSC_DIR"
npm install --silent

echo "==> Building Local_RSC for iOS embedding..."
IOS_BUILD=1 npm run build

echo "==> Copying dist to iOS resources..."
rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"
cp -r "$LOCAL_RSC_DIR/dist/." "$DEST_DIR/"

echo "==> Regenerating Xcode project..."
cd "$REPO_ROOT/iOS_Client/OpenRSC"
xcodegen generate --quiet

echo ""
echo "==> Done. Web client bundled at:"
echo "    $DEST_DIR"
echo ""
echo "    Rebuild the iOS app in Xcode to pick up the changes."
