#!/bin/bash
# update-web-client.sh
#
# Lightweight update: syncs the OpenRSC game cache and rebuilds the WASM client.
# Run this on the Hetzner server after the game cache changes.
# Assumes deploy-web-client.sh has already been run at least once.
#
# Usage: sudo bash update-web-client.sh

set -euo pipefail

RSC_C_DIR="/opt/rsc-c"
EMSDK_DIR="/opt/emsdk"
OPENRSC_CACHE_DIR="/opt/openrsc/Client_Base/Cache"

echo "==> Syncing game cache ..."
if [ -d "$OPENRSC_CACHE_DIR" ]; then
    rsync -av --delete "$OPENRSC_CACHE_DIR/" "$RSC_C_DIR/cache/"
    echo "==> Cache synced."
else
    echo "WARNING: Cache not found at $OPENRSC_CACHE_DIR. Skipping sync."
fi

echo "==> Rebuilding WebAssembly client ..."
source "$EMSDK_DIR/emsdk_env.sh"
cd "$RSC_C_DIR"
make -f Makefile.emscripten clean
make -f Makefile.emscripten

echo "==> Reloading nginx ..."
systemctl reload nginx

echo ""
echo "==> Update complete."
