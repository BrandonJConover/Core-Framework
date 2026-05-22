#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "== TypeScript =="
(cd "$ROOT_DIR/2009scape-web/client" && npx tsc --noEmit)

echo "== Parcel build =="
(cd "$ROOT_DIR/2009scape-web/client" && npm run build)

echo "== Patch probes =="
(cd "$ROOT_DIR/2009scape-web/client-patch" && \
  node .terrain-mesh-test.mjs && \
  node .scene-wire-test.mjs && \
  node .packet-trace-test.mjs && \
  node .process-menu-530-audit.mjs && \
  node .outgoing530-golden-test.mjs && \
  node .menu-action-flow-trace.mjs)

echo "== E2E syntax =="
(cd "$ROOT_DIR/2009scape-web/e2e" && node --check smoke-test.js)

echo "Baseline checks passed."
