#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIKE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SPIKE_DIR/../.." && pwd)"
RT4_DIR="$REPO_ROOT/reference/rt4-client"
PUBLIC_DIR="$SPIKE_DIR/public"

cp "$RT4_DIR/client/config.json" "$PUBLIC_DIR/config.json"
echo "Restored upstream test RT4 config to $PUBLIC_DIR/config.json"

