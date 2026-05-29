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

# Local playable-loop gate against the Java/530 bridge dialect
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
CLIENT_SERVER_DIALECT=530 \
CLIENT_URL=http://127.0.0.1:8765/ \
node smoke-test.js

# Local deterministic bank fixture probe
AUTO_LOGIN=1 \
CAPTURE_SCREENSHOTS=0 \
SEND_COMMAND=0 \
ASSERT_BANK_INVENTORY_PROBE=1 \
ASSERT_BANK_ACTION_PROBE=1 \
BANK_FIXTURE_COMMAND='::bank' \
BANK_INVENTORY_CONTAINER_IDS=93,95 \
BANK_ACTION_CONTAINER_ID=93 \
CLIENT_USERNAME=rt4bankfx4 \
CLIENT_PASSWORD=password \
BANK_INVENTORY_REQUIRE_OPEN=1 \
BANK_INVENTORY_REQUIRE_ITEM=1 \
STABILITY_MS=0 \
CLIENT_SERVER_HOST=127.0.0.1 \
CLIENT_SERVER_PORT=43601 \
CLIENT_SERVER_DIALECT=530 \
CLIENT_URL=http://127.0.0.1:8765/ \
node smoke-test.js

# Combined first-playable smoke against Java/530
AUTO_LOGIN=1 \
CAPTURE_SCREENSHOTS=0 \
ASSERT_FIRST_PLAYABLE=1 \
CLIENT_PASSWORD=password \
CLIENT_SERVER_HOST=127.0.0.1 \
CLIENT_SERVER_PORT=43601 \
CLIENT_SERVER_DIALECT=530 \
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

The combined first-playable smoke chains the available Java/530 gates in one
runner pass: keepalive, NPC dialogue, bank inventory plus IF-button mutation on
`rt4bankfx4`, server-backed drop/take with `DROP_TAKE_TAKE_MODE=menu`, and combat
contact feedback. `ASSERT_FIRST_PLAYABLE=1` supplies the fixture defaults
(`CLIENT_USERNAME=rt4bankfx4`, `BANK_FIXTURE_COMMAND='::bank'`,
`BANK_INVENTORY_CONTAINER_IDS=93,95`, `BANK_ACTION_CONTAINER_ID=93`,
`BANK_ACTION_MODE=if`, and `STABILITY_MS=60000`); the local fixture password is
set explicitly in the command. Run
`experiments/rt4-wrapper-spike/scripts/seed-local-bank-fixture.sh` before starting
the Java stack if the preflight reports that `rt4bankfx4` is not seeded.
Add `ASSERT_FIRST_PLAYABLE_EXTENDED=1` after the base gate is green to include
the heavier logout/relog and server-restart reconnect checks in the same run.
At startup, `smoke-test.js` prints an `Effective smoke config:` line with the
resolved URL, bridge host/port/dialect, login fixture, and enabled gates. Include
that line verbatim in live failure reports so triage can spot stale hosts,
missing fixture overrides, or a wrong dialect before comparing packet traces.

### First-playable troubleshooting

When the combined live gate fails, isolate the layer before changing client code:

- Host reachability: run `CHECK_LIVE=1 2009scape-web/scripts/check-local-rt4-smoke.sh`
  with the same `CLIENT_URL`, `CLIENT_SERVER_HOST`, and `CLIENT_SERVER_PORT`. An HTTP
  or bridge-port failure means the static client or WebSocket bridge is down or the
  host is unreachable from this shell.
- Effective config: copy the first `Effective smoke config:` line from the failing
  `smoke-test.js` run into the report, along with the failing assertion. This is
  the fastest way to confirm the live run used the intended bridge, dialect,
  fixture account, and aggregate gate settings.
- Fixture account: `ASSERT_FIRST_PLAYABLE=1` expects the local fixture
  `rt4bankfx4` with `CLIENT_PASSWORD=password`. If bank or drop/take setup fails,
  run `experiments/rt4-wrapper-spike/scripts/seed-local-bank-fixture.sh` before
  starting the Java stack, then rerun the bank fixture smoke printed by
  `check-local-rt4-smoke.sh`.
- Tutorial or welcome UI blockers: if login reaches the game but dialogue, bank, or
  combat probes cannot find their target rows, capture screenshots once with
  `CAPTURE_SCREENSHOTS=1` and clear any welcome/tutorial modal or fixture-position
  drift before rerunning the aggregate gate.
- Gate isolation: run the individual commands printed by
  `check-local-rt4-smoke.sh` in this order: phase 1 keepalive, NPC dialogue smoke,
  bank fixture smoke, drop/take smoke with `DROP_TAKE_TAKE_MODE=menu`, ground-item
  menu probe, then combat contact smoke.

## Optional assertions

- `ASSERT_COMMAND=1` requires a `::players` command to be consumed or sent.
- `ASSERT_FIRST_PLAYABLE=1` enables the current combined Java/530 first-playable gate: scene walk, minimap walk, keepalive, NPC dialogue continue, bank fixture open/action using `rt4bankfx4`, ground-item menu probe, server-backed drop/take with menu-mode take, and combat contact feedback. It defaults `CLIENT_USERNAME=rt4bankfx4`, `BANK_FIXTURE_COMMAND='::bank'`, `BANK_INVENTORY_CONTAINER_IDS=93,95`, `BANK_ACTION_CONTAINER_ID=93`, `DROP_TAKE_TAKE_MODE=menu`, `STABILITY_MS=60000`, and suppresses the default `::players` command unless explicitly re-enabled through separate flags.
- `ASSERT_FIRST_PLAYABLE_EXTENDED=1` adds logout/relog and server-restart reconnect checks on top of any enabled base gates. Use it after `ASSERT_FIRST_PLAYABLE=1` is passing, because it is intentionally a longer recovery/stability pass.
- `ASSERT_WALK=1` clicks the 3D scene and requires local movement.
- `ASSERT_MINIMAP_WALK=1` clicks the minimap and requires movement plus a minimap-walk semantic opcode.
- `ASSERT_ACTION_PROBES=1` runs live `processMenuActions` probes after login and requires a native 530 loc action opcode, plus an NPC action opcode when an NPC is visible.
- `ASSERT_GROUND_ITEM_ACTION_PROBES=1` runs synthetic ground-item option probes and requires native 530 ground-item opcodes `66`, `33`, and `48`.
- `ASSERT_GROUND_ITEM_MENU_PROBE=1` verifies the ground-item menu-generation path. It injects a temporary local tile item into the current client scene state, asks the ground-item menu helper for rows, dispatches the generated `Take` row through `processMenuActions`, and requires native opcode `66`.
- `ASSERT_DROP_TAKE_SMOKE=1` runs the first server-backed inventory/ground-item loop. It drops a real item from container `93` through native item opcode `135`, waits for the item to appear through the 530 OBJ update/legacy ground-item bridge, then takes it back with native ground-item opcode `66`. Use `DROP_TAKE_TAKE_MODE=menu` to take through the generated ground-item `Take` menu row instead of the direct packet helper. Use `DROP_TAKE_FIXTURE_COMMAND` to seed or prepare the account, `DROP_TAKE_CONTAINER_ID` to choose the source container, and `DROP_TAKE_WAIT_MS` to tune state waits.
- `ASSERT_DIALOGUE_CONTINUE_PROBE=1` runs the `processMenuActions` click-to-continue path and requires native 530 continue-dialogue opcode `132`.
- `ASSERT_DIALOGUE_ACTION_PROBE=1` runs the CS2 dialogue-option hook and requires native 530 dialogue action opcode `111`.
- `ASSERT_KEEPALIVE=1` turns the final stability wait into a hard session gate: the client must remain in playable state, keepalive sends must advance, and no flush/drop evidence may appear. Pair with `STABILITY_MS=60000` for the Phase 1 stability gate.
- `ASSERT_NPC_DIALOGUE_SMOKE=1` runs the first server-backed NPC dialogue loop. By default it targets the visible tutorial `RuneScape guide` (`NPC_DIALOGUE_TARGET_ID=945`), generates that NPC's live menu rows, dispatches the actual `Talk-to`/`Talk` row, waits for a dialogue interface, then dispatches native continue-dialogue opcode `132`. Set `NPC_DIALOGUE_FIXTURE_COMMAND` for an opt-in setup command such as teleporting a fixture account near another NPC. It intentionally does not choose a dialogue option yet because local Java currently decodes opcode `111` as GE offer item, not CS2 dialogue option.
- `ASSERT_BANK_INVENTORY_PROBE=1` inspects decoded `containerItems`/`containerAmounts` after login. By default it only requires at least one structurally valid server container snapshot; add `BANK_INVENTORY_CONTAINER_IDS=93,95` or another comma-separated fixture-specific list to require known bank-open containers, `BANK_INVENTORY_REQUIRE_OPEN=1` to require an open modal/tab/dialogue interface, and `BANK_INVENTORY_REQUIRE_ITEM=1` to require a non-empty slot. Use the deterministic local fixture with `CLIENT_USERNAME=rt4bankfx4 CLIENT_PASSWORD=password BANK_FIXTURE_COMMAND='::bank'`; `start-local-server.sh` seeds that account by default before startup. `BANK_FIXTURE_COMMAND` accepts semicolon- or newline-separated commands for ad hoc setup. The fixture username is intentionally under 12 characters to match the local server login limit. Failures include decoded container ids, component hashes split into interface/child ids, open interface summaries, slot samples, item/amount mismatch details, before/after fixture chat when configured, and fixture advice. A structural login-only probe sees containers `93,94`; after bank open, the bank container is `95`.
- `ASSERT_BANK_ACTION_PROBE=1` builds on the bank container probe. By default it calls the client `Outgoing530.ifButton` helper and waits for containers `93`/`95` to mutate: side inventory container `93` deposits through component `(763 << 16) | 0`, bank container `95` withdraws through component `(762 << 16) | 73`. Use `BANK_ACTION_CONTAINER_ID=93` or `95` to choose the source and `BANK_ACTION_OPTION=1..7` for amount options; option 1 emits opcode `155`, option 2 `196`, option 3 `124`, option 4 `199`, option 5 `234`, option 6 `168`, and option 7 `166`. The older component-item packet smoke remains available with `BANK_ACTION_MODE=component-item` for dispatch-only regression checks.
- `ASSERT_RENDERED_ACTION_MENU=1` samples real scene right-click menus near spawn before movement, finds a rendered loc/NPC row, clicks the actual menu row, and requires the matching native 530 opcode.
- `ASSERT_RENDERED_NPC_MENU=1` requires a rendered NPC row specifically before clicking it and checking the native 530 NPC opcode.
- `ASSERT_RENDERED_LOC_MENU=1` uses the same rendered right-click path but requires a loc row specifically before clicking it and checking the native 530 loc opcode.
- `ASSERT_COMBAT_TARGET_PROBE=1` finds the first visible NPC with a generated `Attack` row, dispatches that row through `processMenuActions`, and requires the matching native 530 NPC action opcode. This proves first combat target selection; hitsplat/health/animation feedback is still a later visual-state gate.
- `ASSERT_COMBAT_CONTACT_SMOKE=1` builds on the combat target probe and waits for server feedback decoded from `PLAYER_INFO`/`NPC_INFO`: hit masks, target masks, emote animations, or spotanims recorded in `combatTrace530`. Use `COMBAT_CONTACT_WAIT_MS` to tune the wait.
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
