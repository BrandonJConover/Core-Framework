# 2009scape-web E2E smoke test

Quick Playwright-driven smoke test that verifies the web client can:

1. Reach the title screen
2. Click "Existing User" → reach username/password form
3. Submit credentials through the configured WebSocket target
4. Stay connected past the 20-second server ping timeout
5. Send a `::command` and receive a server chat response
6. Hold the session open for 45+ seconds without page errors
7. Optionally assert the playable-loop gates: scene/minimap walking, native action probes, rendered menu dispatch, and logout/relog
8. Optionally inspect decoded bank/inventory container state once a bank fixture has been opened manually or by a future harness step

Screenshots are captured at each stage under `/tmp/playwright-2009scape/` by
default so you can visually confirm the render state (chrome, chat, minimap
frame, FPS counter). Set `CAPTURE_SCREENSHOTS=0` for the fast gate.

## Running

```bash
# One-time setup (from this directory)
mkdir -p /tmp/playwright-2009scape && cp smoke-test.js /tmp/playwright-2009scape/
cd /tmp/playwright-2009scape
npm init -y
npm install playwright
npx playwright install chromium

# Run against the deployed client
node smoke-test.js

# Or run against a local static build
CLIENT_URL=http://127.0.0.1:8765/ node smoke-test.js

# Local playable-loop gate against the OpenRSC bridge dialect
AUTO_LOGIN=1 \
CAPTURE_SCREENSHOTS=0 \
SEND_COMMAND=0 \
ASSERT_WALK=1 \
ASSERT_MINIMAP_WALK=1 \
ASSERT_ACTION_PROBES=1 \
ASSERT_RENDERED_ACTION_MENU=1 \
ASSERT_RENDERED_NPC_MENU=1 \
ASSERT_LOGOUT_RELOG=1 \
STABILITY_MS=0 \
CLIENT_SERVER_HOST=127.0.0.1 \
CLIENT_SERVER_PORT=43601 \
CLIENT_SERVER_DIALECT=openrsc235 \
CLIENT_URL=http://127.0.0.1:8765/ \
node smoke-test.js

# Local deterministic bank fixture probe
AUTO_LOGIN=1 \
CAPTURE_SCREENSHOTS=0 \
SEND_COMMAND=0 \
ASSERT_BANK_INVENTORY_PROBE=1 \
BANK_FIXTURE_COMMAND='::bank' \
BANK_INVENTORY_CONTAINER_IDS=93,95 \
CLIENT_USERNAME=rt4bankfx1 \
CLIENT_PASSWORD=password \
BANK_INVENTORY_REQUIRE_OPEN=1 \
BANK_INVENTORY_REQUIRE_ITEM=1 \
STABILITY_MS=0 \
CLIENT_SERVER_HOST=127.0.0.1 \
CLIENT_SERVER_PORT=43601 \
CLIENT_SERVER_DIALECT=openrsc235 \
CLIENT_URL=http://127.0.0.1:8765/ \
node smoke-test.js
```

For Docker-free local runs, use the server and WebSocket bridge scripts under
`experiments/rt4-wrapper-spike/scripts/`, serve `2009scape-web/client/dist` on
`127.0.0.1:8765`, then run the preflight from the repo root before starting the
live smoke:

```bash
CHECK_LIVE=1 \
CLIENT_URL=http://127.0.0.1:8765/ \
CLIENT_SERVER_HOST=127.0.0.1 \
CLIENT_SERVER_PORT=43601 \
2009scape-web/scripts/check-local-rt4-smoke.sh
```

The local playable gate assumes all of these are already true:

- `2009scape-web/client/dist/index.html` exists from a current client build.
- `2009scape-web/client/client_cache/` contains the required 530 cache files.
- The static client is being served at `CLIENT_URL`.
- The WebSocket bridge is listening at `CLIENT_SERVER_HOST:CLIENT_SERVER_PORT`.
- The OpenRSC/2009scape live stack behind that bridge is running and accepts the
  smoke-test credentials. The preflight can check the HTTP and bridge ports, but
  the Playwright smoke is still the login/gameplay proof.
- The Playwright module is installed for `2009scape-web/e2e` when running the
  live smoke; set `CHECK_PLAYWRIGHT=1` during preflight to require it.

## Optional assertions

- `ASSERT_COMMAND=1` requires a `::players` command to be consumed or sent.
- `ASSERT_WALK=1` clicks the 3D scene and requires local movement.
- `ASSERT_MINIMAP_WALK=1` clicks the minimap and requires movement plus a minimap-walk semantic opcode.
- `ASSERT_ACTION_PROBES=1` runs live `processMenuActions` probes after login and requires a native 530 loc action opcode, plus an NPC action opcode when an NPC is visible.
- `ASSERT_GROUND_ITEM_ACTION_PROBES=1` runs synthetic ground-item option probes and requires native 530 ground-item opcodes `66`, `33`, and `48`.
- `ASSERT_DIALOGUE_CONTINUE_PROBE=1` runs the `processMenuActions` click-to-continue path and requires native 530 continue-dialogue opcode `132`.
- `ASSERT_DIALOGUE_ACTION_PROBE=1` runs the CS2 dialogue-option hook and requires native 530 dialogue action opcode `111`.
- `ASSERT_BANK_INVENTORY_PROBE=1` inspects decoded `containerItems`/`containerAmounts` after login. By default it only requires at least one structurally valid server container snapshot; add `BANK_INVENTORY_CONTAINER_IDS=93,95` or another comma-separated fixture-specific list to require known bank-open containers, `BANK_INVENTORY_REQUIRE_OPEN=1` to require an open modal/tab/dialogue interface, and `BANK_INVENTORY_REQUIRE_ITEM=1` to require a non-empty slot. Use the deterministic local fixture with `CLIENT_USERNAME=rt4bankfx1 CLIENT_PASSWORD=password BANK_FIXTURE_COMMAND='::bank'`. The fixture username is intentionally under 12 characters to match the local server login limit. Failures include decoded container ids, component hashes split into interface/child ids, open interface summaries, slot samples, item/amount mismatch details, before/after fixture chat when configured, and fixture advice. A structural login-only probe sees containers `93,94`; after bank open, the bank container is `95`. This is a QA placeholder for the bank/inventory lane: it does not mutate slots, withdraw/deposit, or click item rows yet.
- `ASSERT_RENDERED_ACTION_MENU=1` samples real scene right-click menus near spawn before movement, finds a rendered loc/NPC row, clicks the actual menu row, and requires the matching native 530 opcode.
- `ASSERT_RENDERED_NPC_MENU=1` requires a rendered NPC row specifically before clicking it and checking the native 530 NPC opcode.
- `ASSERT_RENDERED_LOC_MENU=1` uses the same rendered right-click path but requires a loc row specifically before clicking it and checking the native 530 loc opcode.
- `ASSERT_LOGOUT_RELOG=1` calls the client logout path, logs back in, and requires the second session to reach the playable in-game state. By default it uses `CLIENT_RELOG_USERNAME` or the original username plus `r` so the OpenRSC bridge does not block on same-account transfer state after a raw socket close.
- `ASSERT_SERVER_RESTART_RECONNECT=1` closes the live game WebSocket with a restart-style close code, then requires the client to open a new socket, send reconnect login opcode `18`, and return to the playable in-game state.

## Interpreting output

Pass looks like:
- `===== CONSOLE (4) =====` — just the COOP warning + three init logs
- `===== PAGE ERRORS (0) =====`
- Screenshots 03/04/05 show the full 2009scape UI chrome with chat messages from the server

A fail typically shows:
- `PAGE ERRORS (1+)` — the TypeError with a stack trace reveals which render path broke
- Or `FATAL: page.goto: net::ERR_CONNECTION_REFUSED` — web server is down (systemctl restart 2009scape-web on the Hetzner box)

## Coordinates

The canvas is 765×503 native. The script computes scaleX/scaleY relative to the viewport so clicks work at different window sizes. Notable canvas coords:
- Existing User button: `(462, 291)`
- Login button: `(302, 321)`
- Cancel button: `(462, 321)`

All taken from Game.ts login screen handler at [drawLoginScreen state 2](../../2009scape-web/client-patch/Login530.ts) / `loginScreenState === 2`.
