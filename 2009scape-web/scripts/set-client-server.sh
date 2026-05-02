#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <server-address>" >&2
  echo "Example: $0 10.8.0.1" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT_DIR/client/osrs/Configuration.ts"

if [[ ! -f "$CONFIG" ]]; then
  echo "Missing client configuration: $CONFIG" >&2
  echo "Run setup.sh or clone/apply the web client first." >&2
  exit 1
fi

SERVER_ADDRESS="$1" perl -0pi -e 's/public static SERVER_ADDRESS: string = "[^"]+"/public static SERVER_ADDRESS: string = "$ENV{SERVER_ADDRESS}"/' "$CONFIG"
echo "Set local web client SERVER_ADDRESS=$1"

# Also patch any built dist bundle in-place. Without this, running this
# script after `npm run build` left the dist bound to the old address
# (the source change only took effect on the next rebuild), which silently
# broke headless test runs — the client connected nowhere, REBUILD_NORMAL
# never fired with real keys, and downstream l_X_Z XTEA decrypt looked
# broken when actually it was starved of keys.
DIST_DIR="$ROOT_DIR/client/dist"
if [[ -d "$DIST_DIR" ]]; then
  patched=0
  for f in "$DIST_DIR"/*.js; do
    [[ -f "$f" ]] || continue
    if SERVER_ADDRESS="$1" perl -0pi -e 's/\.SERVER_ADDRESS="[^"]+"/.SERVER_ADDRESS="$ENV{SERVER_ADDRESS}"/g' "$f"; then
      patched=$((patched + 1))
    fi
  done
  echo "Patched SERVER_ADDRESS in $patched dist bundle(s)"
fi
