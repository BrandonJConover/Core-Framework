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
