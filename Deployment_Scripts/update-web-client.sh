#!/bin/bash
# update-web-client.sh
#
# Lightweight update: syncs the OpenRSC game cache and rebuilds the WASM client.
# Run this on the Hetzner server after the game cache changes.
# Assumes deploy-web-client.sh has already been run at least once.
#
# Usage:
#   sudo bash update-web-client.sh [--domain play.yourdomain.com]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RSC_C_DIR="/opt/rsc-c"
EMSDK_DIR="/opt/emsdk"
OPENRSC_CACHE_DIR="/opt/openrsc/Client_Base/Cache"
DOMAIN="${DOMAIN:-play.yourdomain.com}"
OPENRSC_WS_PORT="43494"
OPENRSC_TCP_PORT="43594"
OPENRSC_RSA_EXP="00010001"
OPENRSC_RSA_MOD="87cef754966ecb19806238d9fecf0f421e816976f74f365c86a584e51049794d41fefbdc5fed3a3ed3b7495ba24262bb7d1dd5d2ff9e306b5bbf5522a2e85b25"
WORLDLIST_PATCHER="$REPO_ROOT/web-client/worldlist-patch.py"
WEBCLIENT_PATCHER="$REPO_ROOT/web-client/apply-mobile-patches.py"
MOBILE_WEBCLIENT_DIR="$REPO_ROOT/iOS_Client/OpenRSC/OpenRSC/Sources/WebClient"

for arg in "$@"; do
  case $arg in
    --domain=*) DOMAIN="${arg#*=}" ;;
    --domain)   shift; DOMAIN="$1" ;;
  esac
done

echo "==> Syncing game cache ..."
if [ -d "$OPENRSC_CACHE_DIR" ]; then
    rsync -av --delete "$OPENRSC_CACHE_DIR/" "$RSC_C_DIR/cache/"
    echo "==> Cache synced."
else
    echo "WARNING: Cache not found at $OPENRSC_CACHE_DIR. Skipping sync."
fi

echo "==> Patching worldlist for $DOMAIN ..."
python3 "$WORLDLIST_PATCHER" \
  --file "$RSC_C_DIR/src/ui/worldlist.c" \
  --host "$DOMAIN" \
  --ws-port "$OPENRSC_WS_PORT" \
  --tcp-port "$OPENRSC_TCP_PORT" \
  --rsa-exp "$OPENRSC_RSA_EXP" \
  --rsa-mod "$OPENRSC_RSA_MOD"

echo "==> Rebuilding WebAssembly client ..."
source "$EMSDK_DIR/emsdk_env.sh"
cd "$RSC_C_DIR"
if grep -q -- "-s MAX_WEBGL_VERSION=2" Makefile.emscripten && ! grep -q -- "-s MIN_WEBGL_VERSION=2" Makefile.emscripten; then
  echo "==> Pinning Emscripten to WebGL 2 for iOS/Safari shader compatibility ..."
  sed -i 's/-s MAX_WEBGL_VERSION=2/-s MIN_WEBGL_VERSION=2 -s MAX_WEBGL_VERSION=2/' Makefile.emscripten
fi
if grep -q -- "-s INITIAL_MEMORY=30MB" Makefile.emscripten; then
  echo "==> Raising initial WASM memory to avoid Safari heap growth stalls ..."
  sed -i 's/-s INITIAL_MEMORY=30MB/-s INITIAL_MEMORY=64MB/' Makefile.emscripten
fi
make -f Makefile.emscripten clean
make -f Makefile.emscripten

echo "==> Applying mobile web-client HTML and JavaScript patches ..."
python3 "$WEBCLIENT_PATCHER" \
  --rsc-c-dir "$RSC_C_DIR" \
  --source-web-client "$MOBILE_WEBCLIENT_DIR"

echo "==> Reloading nginx ..."
systemctl reload nginx

echo ""
echo "==> Update complete."
