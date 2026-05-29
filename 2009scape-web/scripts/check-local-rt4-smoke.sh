#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WEB_DIR="$ROOT_DIR/2009scape-web"
CLIENT_DIR="$WEB_DIR/client"
E2E_DIR="$WEB_DIR/e2e"

CLIENT_URL="${CLIENT_URL:-http://127.0.0.1:8765/}"
CLIENT_SERVER_HOST="${CLIENT_SERVER_HOST:-127.0.0.1}"
CLIENT_SERVER_PORT="${CLIENT_SERVER_PORT:-43601}"
CLIENT_SERVER_DIALECT="${CLIENT_SERVER_DIALECT:-530}"
CHECK_LIVE="${CHECK_LIVE:-0}"
CHECK_PLAYWRIGHT="${CHECK_PLAYWRIGHT:-$CHECK_LIVE}"

failures=0

note() {
  printf '%s\n' "$*"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

ok() {
  printf ' ok: %s\n' "$*"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  if have_cmd "$1"; then
    ok "$1 found"
  else
    fail "$1 is required"
  fi
}

require_file() {
  if [[ -f "$1" ]]; then
    ok "$1"
  else
    fail "missing $1"
  fi
}

require_dir() {
  if [[ -d "$1" ]]; then
    ok "$1"
  else
    fail "missing directory $1"
  fi
}

check_node_module() {
  local module="$1"
  local dir="$2"
  if (cd "$dir" && node -e "require.resolve('$module')" >/dev/null 2>&1); then
    ok "Node module '$module' resolves from $dir"
  elif [[ "$module" == "playwright" && -f "$ROOT_DIR/Deployment_Scripts/playwright/node_modules/playwright/index.js" ]]; then
    ok "Node module '$module' resolves from shared Deployment_Scripts/playwright fallback"
  else
    fail "Node module '$module' is not installed for $dir"
  fi
}

check_port() {
  local host="$1"
  local port="$2"
  local label="$3"
  if have_cmd nc && nc -z -w 3 "$host" "$port" >/dev/null 2>&1; then
    ok "$label is listening at $host:$port"
  elif have_cmd lsof && lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    ok "$label has a listener on port $port"
  else
    fail "$label is not reachable at $host:$port"
  fi
}

check_http() {
  local url="$1"
  if have_cmd curl && curl -fsS --max-time 3 "$url" >/dev/null; then
    ok "client URL responds: $url"
  else
    fail "client URL did not respond: $url"
  fi
}

note "== Local RT4 TypeScript smoke preflight =="
require_cmd node
require_cmd npm
require_cmd python3

note ""
note "== Reference sources =="
require_dir "$ROOT_DIR/reference/rt4-client/client/src/main"
require_dir "$ROOT_DIR/reference/refactored-client-435/src/main"
note "435 is advisory only; confirm behavior against rt4 rev-530 and live Java output."

note ""
note "== Client build/cache files =="
require_file "$CLIENT_DIR/package.json"
require_file "$CLIENT_DIR/dist/index.html"
require_file "$CLIENT_DIR/client_cache/main_file_cache.dat"
require_file "$CLIENT_DIR/client_cache/main_file_cache.idx0"

note ""
note "== E2E runner =="
require_file "$E2E_DIR/smoke-test.js"
if have_cmd node; then
  (cd "$E2E_DIR" && node --check smoke-test.js >/dev/null) && ok "smoke-test.js syntax" || fail "smoke-test.js syntax check failed"
  if [[ "$CHECK_PLAYWRIGHT" == "1" ]]; then
    check_node_module playwright "$E2E_DIR"
  else
    note "Set CHECK_PLAYWRIGHT=1 to require the Playwright module."
  fi
fi

note ""
note "== Bank fixture =="
require_file "$ROOT_DIR/experiments/rt4-wrapper-spike/scripts/seed-local-bank-fixture.sh"
if have_cmd node; then
  bash "$ROOT_DIR/experiments/rt4-wrapper-spike/scripts/seed-local-bank-fixture.sh" --check \
    && ok "rt4bankfx4 has inventory or bank items" \
    || fail "rt4bankfx4 is missing inventory/bank fixture items; run experiments/rt4-wrapper-spike/scripts/seed-local-bank-fixture.sh"
fi

if [[ "$CHECK_LIVE" == "1" ]]; then
  note ""
  note "== Live endpoints =="
  check_http "$CLIENT_URL"
  check_port "$CLIENT_SERVER_HOST" "$CLIENT_SERVER_PORT" "WebSocket bridge"
else
  note ""
  note "Set CHECK_LIVE=1 to require the static client and WebSocket bridge to be listening."
fi

note ""
note "Smoke command:"
cat <<EOF
AUTO_LOGIN=1 CAPTURE_SCREENSHOTS=0 SEND_COMMAND=0 ASSERT_WALK=1 ASSERT_MINIMAP_WALK=1 ASSERT_ACTION_PROBES=1 ASSERT_RENDERED_ACTION_MENU=1 ASSERT_RENDERED_NPC_MENU=1 ASSERT_LOGOUT_RELOG=1 STABILITY_MS=0 CLIENT_SERVER_HOST=$CLIENT_SERVER_HOST CLIENT_SERVER_PORT=$CLIENT_SERVER_PORT CLIENT_SERVER_DIALECT=$CLIENT_SERVER_DIALECT CLIENT_URL=$CLIENT_URL node 2009scape-web/e2e/smoke-test.js
EOF
note ""
note "Phase 1 stability gate command:"
cat <<EOF
AUTO_LOGIN=1 CAPTURE_SCREENSHOTS=0 SEND_COMMAND=0 ASSERT_KEEPALIVE=1 STABILITY_MS=60000 CLIENT_SERVER_HOST=$CLIENT_SERVER_HOST CLIENT_SERVER_PORT=$CLIENT_SERVER_PORT CLIENT_SERVER_DIALECT=$CLIENT_SERVER_DIALECT CLIENT_URL=$CLIENT_URL node 2009scape-web/e2e/smoke-test.js
EOF
note ""
note "Combined first-playable smoke command:"
cat <<EOF
AUTO_LOGIN=1 CAPTURE_SCREENSHOTS=0 ASSERT_FIRST_PLAYABLE=1 CLIENT_PASSWORD=password CLIENT_SERVER_HOST=$CLIENT_SERVER_HOST CLIENT_SERVER_PORT=$CLIENT_SERVER_PORT CLIENT_SERVER_DIALECT=$CLIENT_SERVER_DIALECT CLIENT_URL=$CLIENT_URL node 2009scape-web/e2e/smoke-test.js
EOF
note "This chains the currently available Java/530 first-playable gates: walk, minimap walk, keepalive, NPC dialogue, bank IF action, ground-item menu, drop/take through menu mode, and combat contact."
note "Add ASSERT_FIRST_PLAYABLE_EXTENDED=1 after the base gate is green to include logout/relog and server-restart reconnect."
note "Use rt4bankfx4 after running experiments/rt4-wrapper-spike/scripts/seed-local-bank-fixture.sh so the bank and drop/take probes have fixture items."
note "smoke-test.js prints an 'Effective smoke config:' line at startup; include that line with live failure reports to show the resolved URL, bridge, dialect, login fixture, and enabled gates."
note "If the aggregate live gate fails, first rerun this preflight with CHECK_LIVE=1 and the same CLIENT_URL/CLIENT_SERVER_HOST/CLIENT_SERVER_PORT to isolate host or bridge reachability."
note "Then check the rt4bankfx4 fixture account, clear tutorial/welcome UI blockers with a CAPTURE_SCREENSHOTS=1 run, and run the individual keepalive, NPC dialogue, bank, drop/take, ground-item menu, and combat contact commands below."
note ""
note "NPC dialogue smoke command:"
cat <<EOF
AUTO_LOGIN=1 CAPTURE_SCREENSHOTS=0 SEND_COMMAND=0 ASSERT_NPC_DIALOGUE_SMOKE=1 STABILITY_MS=0 CLIENT_SERVER_HOST=$CLIENT_SERVER_HOST CLIENT_SERVER_PORT=$CLIENT_SERVER_PORT CLIENT_SERVER_DIALECT=$CLIENT_SERVER_DIALECT CLIENT_URL=$CLIENT_URL node 2009scape-web/e2e/smoke-test.js
EOF
note "The default NPC dialogue smoke targets the visible tutorial RuneScape guide (945); use NPC_DIALOGUE_FIXTURE_COMMAND/NPC_DIALOGUE_TARGET_ID for other fixture NPCs."
note "It stops at Talk-to plus continue-dialogue because opcode 111 is reserved for GE offer item on the local Java stack."
note "Start the Java server with RT4_WEB_NPC_DIAGNOSTICS=1 when you need NPCTalkListener opened=true evidence."
note ""
note "Combat target smoke command:"
cat <<EOF
AUTO_LOGIN=1 CAPTURE_SCREENSHOTS=0 SEND_COMMAND=0 ASSERT_COMBAT_TARGET_PROBE=1 STABILITY_MS=0 CLIENT_SERVER_HOST=$CLIENT_SERVER_HOST CLIENT_SERVER_PORT=$CLIENT_SERVER_PORT CLIENT_SERVER_DIALECT=$CLIENT_SERVER_DIALECT CLIENT_URL=$CLIENT_URL node 2009scape-web/e2e/smoke-test.js
EOF
note ""
note "Combat contact smoke command:"
cat <<EOF
AUTO_LOGIN=1 CAPTURE_SCREENSHOTS=0 SEND_COMMAND=0 ASSERT_COMBAT_CONTACT_SMOKE=1 STABILITY_MS=0 CLIENT_SERVER_HOST=$CLIENT_SERVER_HOST CLIENT_SERVER_PORT=$CLIENT_SERVER_PORT CLIENT_SERVER_DIALECT=$CLIENT_SERVER_DIALECT CLIENT_URL=$CLIENT_URL node 2009scape-web/e2e/smoke-test.js
EOF
note "The contact smoke waits for PLAYER_INFO/NPC_INFO combatTrace530 evidence after the target packet."
note ""
note "Drop/take smoke command:"
cat <<EOF
AUTO_LOGIN=1 CAPTURE_SCREENSHOTS=0 SEND_COMMAND=0 ASSERT_DROP_TAKE_SMOKE=1 DROP_TAKE_CONTAINER_ID=93 STABILITY_MS=0 CLIENT_SERVER_HOST=$CLIENT_SERVER_HOST CLIENT_SERVER_PORT=$CLIENT_SERVER_PORT CLIENT_SERVER_DIALECT=$CLIENT_SERVER_DIALECT CLIENT_URL=$CLIENT_URL node 2009scape-web/e2e/smoke-test.js
EOF
note "The drop/take smoke sends native item opcode 135, waits for the 530 OBJ update bridge, then sends native take opcode 66."
note "Add DROP_TAKE_TAKE_MODE=menu to take through the generated ground-item menu row after the server-backed drop."
note ""
note "Ground-item menu probe command:"
cat <<EOF
AUTO_LOGIN=1 CAPTURE_SCREENSHOTS=0 SEND_COMMAND=0 ASSERT_GROUND_ITEM_MENU_PROBE=1 STABILITY_MS=0 CLIENT_SERVER_HOST=$CLIENT_SERVER_HOST CLIENT_SERVER_PORT=$CLIENT_SERVER_PORT CLIENT_SERVER_DIALECT=$CLIENT_SERVER_DIALECT CLIENT_URL=$CLIENT_URL node 2009scape-web/e2e/smoke-test.js
EOF
note "The menu probe verifies generated ground-item Take rows dispatch through processMenuActions as opcode 66."
note ""
note "Bank fixture smoke command:"
cat <<EOF
AUTO_LOGIN=1 CAPTURE_SCREENSHOTS=0 SEND_COMMAND=0 ASSERT_BANK_INVENTORY_PROBE=1 ASSERT_BANK_ACTION_PROBE=1 BANK_FIXTURE_COMMAND='::bank' BANK_INVENTORY_CONTAINER_IDS=93,95 BANK_ACTION_CONTAINER_ID=93 BANK_ACTION_MODE=if CLIENT_USERNAME=rt4bankfx4 CLIENT_PASSWORD=password BANK_INVENTORY_REQUIRE_OPEN=1 BANK_INVENTORY_REQUIRE_ITEM=1 STABILITY_MS=0 CLIENT_SERVER_HOST=$CLIENT_SERVER_HOST CLIENT_SERVER_PORT=$CLIENT_SERVER_PORT CLIENT_SERVER_DIALECT=$CLIENT_SERVER_DIALECT CLIENT_URL=$CLIENT_URL node 2009scape-web/e2e/smoke-test.js
EOF
note "Container ids 93 and 95 are the deterministic fixture's side-inventory and bank snapshots after ::bank opens the bank."
note "The action probe targets container 93 and sends Java bank IF action opcode 155, then waits for containers 93/95 to mutate."

if [[ "$failures" -gt 0 ]]; then
  note ""
  fail "$failures preflight check(s) failed"
  exit 1
fi

note ""
note "Local RT4 TypeScript smoke preflight passed."
