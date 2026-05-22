#!/usr/bin/env bash
set -euo pipefail

if command -v node >/dev/null 2>&1; then
  NODE_BIN="node"
elif [ -x /opt/homebrew/bin/node ]; then
  NODE_BIN="/opt/homebrew/bin/node"
else
  echo "Node.js is required to run the RT4 wrapper smoke test." >&2
  exit 1
fi

exec "$NODE_BIN" "$(dirname "$0")/smoke-local-wrapper.mjs"
