# RT4 Web Client Parity Matrix

Living status board for the 2009scape rev-530 browser client. The parity target is the reference 2009 rt4 client in `reference/rt4-client`; browser/mobile substitutions are allowed only where Java applet APIs do not exist.

## Reference Sources

- `reference/rt4-client`: authoritative rev-530 behavior. Use this for packet bodies, cache formats, CS2 behavior, interface ids, widgets, rendering, animation, and update masks.
- `reference/refactored-client-435`: read-only advisory architecture reference. Use it only to clarify nearby-era client structure such as chatbox/interface state, menu row selection, and broad UI loop shape.
- 2009scape Java server: authoritative for the current local playable stack's decoded packets, emitted interfaces, container ids, and smoke evidence.
- Reference-use rule: never copy 435 opcodes, packet sizes, cache layouts, interface ids, update masks, or combat packet details unless the change is confirmed against `reference/rt4-client` and live 2009scape Java output. Every 435-informed implementation note should name the 530 or Java-server source that confirmed it.

Status legend:

- `Done`: implemented and covered by automated or manual acceptance.
- `Partial`: usable or decoded, but missing visible behavior, edge cases, or coverage.
- `Planned`: not yet implemented, or only present as a stream-safe no-op.
- `Blocked`: requires upstream server/data/tooling work before the browser client can complete parity.

## Release Gates

| Gate | Required Evidence | Status | Owner |
| --- | --- | --- | --- |
| Prototype playable | Login, terrain render, local/NPC render, chat input, click movement smoke | Done | QA/Infra |
| Gameplay playable | Server-authoritative movement, object/NPC/item interactions, dialogue, bank/inventory, no packet desync in normal play | Partial | Protocol + Gameplay |
| UI playable | Modal/tab stack, CS2-driven widgets, IF button actions, inventory widgets, settings/friends/clan surfaces | Partial | UI/CS2 |
| Visual parity | Terrain, locs, players/NPCs, animations, minimap, overlays, sprites/fonts/textures close to rt4 | Partial | Renderer + Assets |
| Audio parity | Music catalog, jingles, synth/area sounds, preferences and browser unlock | Partial | Assets/Audio |
| Release ready | Full automated suite, manual checklist, 2-hour soak, no page errors, no unknown normal-play opcodes | Planned | QA/Infra |

## Subsystem Matrix

| Subsystem | Current Status | Next Acceptance Target | Primary Tests / Evidence | Owner Track |
| --- | --- | --- | --- | --- |
| Login/session | Partial | Stable native 530 login over WSS and local stack without bridge-specific hacks | Playwright smoke, packet trace, logout/relog smoke, 45s+ stability | Protocol |
| Movement | Partial | Remove optimistic OpenRSC movement once native server updates drive movement | Walk smoke, movement packet golden, server-authoritative position assertion | Protocol + Gameplay |
| Outgoing packets | Partial | Every gameplay action routes through `Outgoing530` or documented browser-safe no-op | `.outgoing530-golden-test.mjs`, `.menu-action-flow-trace.mjs`, process-menu audit | Protocol |
| Incoming packets | Partial | Every rt4 server opcode is handled, state-applied, or explicitly recorded as safe no-op | `PacketHandler530` trace, opcode coverage table, replay tests | Protocol |
| Terrain | Partial | Correct overlay/underlay color, lighting, texture blend, minimap colors, chunk edges, instanced regions | terrain mesh/render tests, visual captures | Renderer |
| Locs/game objects | Partial | All shapes/orientations/morphs render, animate, pick, and update from zone packets | loc mesh tests, object-click E2E, zone replay | Renderer + Gameplay |
| Players | Partial | Appearance, movement, masks, hitsplats, overhead text, icons, animations, spotanims | player appearance/avatar tests, combat visual capture | Renderer |
| NPCs | Partial | Definition swaps, movement masks, animations, overheads, combat state, pick/click boxes | NPC appearance tests, NPC interaction E2E | Renderer + Gameplay |
| Ground items | Partial | Add/reveal/count/delete/take/drop loops visible and packet-correct | zone update tests, take/drop E2E | Gameplay |
| Inventory/items | Partial | All item options, equip/operate/drop/use-with, containers, amounts, drag/click behavior | IF/container tests, item packet goldens, inventory E2E, opt-in bank/inventory smoke probe | UI/CS2 + Gameplay |
| Interfaces/components | Partial | Open/close modal/tab stack, server active properties, access masks, scroll/model/text/inventory widgets | interface component tests, bank/options E2E | UI/CS2 |
| CS2 VM | Partial | Bank, settings, friends/ignore, clan, GE, quest journal, music/emotes/prayer/magic scripts | `.cs2-vm-test.mjs`, script-specific E2E | UI/CS2 |
| Fonts/sprites | Partial | Real idx8/idx13 fonts and sprites replace blank/stub fallback | sprite/font decode goldens, visual captures | Assets |
| Textures/materials | Partial | Texture-op support for all material ops referenced by 530 cache | `.terrain-textures-test.mjs`, terrain visual baseline | Assets + Renderer |
| Animation/skeletons | Partial | BAS/frame transforms for idle/walk/run/combat/skilling/emotes/object/NPC anims | BAS/frame tests, animation visual captures | Renderer |
| Audio/music | Partial | Music catalog, jingles, synth effects, area sounds, mute/volume prefs | music manifest tests, browser audio smoke | Assets/Audio |
| Browser input/shell | Partial | Focus, keyboard, mouse, touch, context menu, resize, fullscreen, HiDPI, preferences | Playwright input/mobile tests | QA/Infra |
| 435 advisory reference | Done | Keep 435 scoped to architecture guidance and block accidental protocol/cache/id copying | `.reference-435-advisory-test.mjs`, `docs/rt4-435-reference-leverage.md` | QA/Infra |
| Performance | Planned | Startup, decode, render, animation, memory, long-session targets recorded and met | profiler captures, 2-hour soak | QA/Infra |
| Deployment | Planned | Local and Hetzner runbooks, WSS recovery, cache headers, logs, source maps | deployment smoke, restart recovery test | QA/Infra |

## Current Protocol Notes

- `Outgoing530` now owns the audited rt4 encoders for item operate, component item actions 1/2/3/5, IF CS2 component clicks, continue-dialogue, CS2 dialogue-option action, ground item actions 1/2/5, selected-target packets, player/NPC/loc/item actions, chat, and close/display packets.
- `Game.processMenuActions()` no longer uses the legacy 377 opcodes for actions `225`, `352`, `444`, `564`, `575`, `894`, setting-toggle/reset component clicks, or ground-item action `270`; those route through `Outgoing530`.
- The known 377 random/anti-idle side packets inside menu actions (`165`, `126`, `157`, `222`, `95`) are now documented no-ops via `skipLegacyRandomActionPacket(...)`; `.process-menu-530-audit.mjs` fails if those raw sends or prior audited legacy gameplay sends return.
- `.outgoing530-golden-test.mjs` provides a Jest-free golden packet gate for the current encoder set. Keep the Jest test if useful during local development, but the baseline script uses the direct probe because Jest currently hangs in this workspace.
- `.menu-action-flow-trace.mjs` now verifies source dispatch plus emitted bytes for dialogue continue, CS2 dialogue-option action, settings/logout component clicks, inventory operate/equip/drop/use-on-item, ground-item option 5, NPC/player/loc actions, selected component targets on NPC/item/loc/player/ground-item, close-modal, social list packets, private messages, chat settings, command lines, input-prompt resumes, and report-abuse packets.
- Social/private-message actions now route through native `Outgoing530` encoders for add/remove friend, add/remove ignore, and private message instead of legacy raw packet writes.
- Chat-mode changes, `::` commands, integer/name/string prompt resumes, and report-abuse submissions now route through audited native `Outgoing530` encoders. The legacy 377 character-design submit opcode is explicitly suppressed because rt4 uses opcode `163` for reflection checks. Current blocker: `reference/rt4-client` shows character-design CS2 opcodes `403/404/410` mutating only local `PlayerAppearance` state, and the live 2009scape `Decoders530.kt`/`Packet.kt` map has no appearance/design decoder or packet variant; native 530 submission needs a server-side decoder change or a capture from a client/server pair that already supports it.
- The Playwright smoke runner now has optional playable-loop assertions for scene walking, minimap walking, synthetic live action packet probes, ground-item action/menu probes, server-backed drop/take, dialogue continue/options, rendered-scene right-click dispatch, first NPC combat target selection/contact feedback, bank/inventory container inspection and IF-button bank mutation, logout/relog, and restart-style reconnect through `ASSERT_WALK=1`, `ASSERT_MINIMAP_WALK=1`, `ASSERT_ACTION_PROBES=1`, `ASSERT_GROUND_ITEM_ACTION_PROBES=1`, `ASSERT_GROUND_ITEM_MENU_PROBE=1`, `ASSERT_DROP_TAKE_SMOKE=1`, `ASSERT_DIALOGUE_CONTINUE_PROBE=1`, `ASSERT_DIALOGUE_ACTION_PROBE=1`, `ASSERT_RENDERED_ACTION_MENU=1`, `ASSERT_RENDERED_NPC_MENU=1`, `ASSERT_RENDERED_LOC_MENU=1`, `ASSERT_COMBAT_TARGET_PROBE=1`, `ASSERT_COMBAT_CONTACT_SMOKE=1`, `ASSERT_BANK_INVENTORY_PROBE=1`, `ASSERT_BANK_ACTION_PROBE=1`, `ASSERT_LOGOUT_RELOG=1`, and `ASSERT_SERVER_RESTART_RECONNECT=1`. `ASSERT_FIRST_PLAYABLE=1` bundles the current Java/530 first-playable gate defaults for walk, minimap walk, keepalive, NPC dialogue, bank action, drop/take menu mode, ground-item menu, and combat contact.
- `ASSERT_BANK_INVENTORY_PROBE=1` verifies decoded container maps and item/amount alignment after login, with optional `BANK_FIXTURE_COMMAND`, `BANK_INVENTORY_CONTAINER_IDS`, `BANK_INVENTORY_REQUIRE_OPEN=1`, and `BANK_INVENTORY_REQUIRE_ITEM=1` constraints for a fixture that has opened bank/inventory. `ASSERT_BANK_ACTION_PROBE=1` now defaults to Java bank IF-button semantics through the client `Outgoing530.ifButton` helper: container `93` deposits from side inventory through component `763:0`, container `95` withdraws through bank component `762:73`, and the probe waits for a real container mutation. Set `BANK_ACTION_MODE=component-item` only for the older dispatch-only component-item regression path.
- Native 530 OBJ zone packets now mirror decoded `groundObjects` into the legacy `groundItems` linked-list path used by the current scene renderer and menu builder. `.ground-item-legacy-bridge-test.mjs` guards the reveal/add/count/delete sync points until the renderer can consume 530 ground stacks directly.
- The scene menu fallback now includes nearby ground item piles, guarded by `.ground-item-menu-fallback-test.mjs`. `ASSERT_GROUND_ITEM_MENU_PROBE=1` verifies generated Take rows still dispatch through `processMenuActions` as native opcode `66`.
- `ASSERT_DROP_TAKE_SMOKE=1` is the first server-backed inventory/ground-item loop gate: it drops a real inventory item with native opcode `135`, waits for the native OBJ update to surface through the bridge, then takes the item with native ground-item opcode `66`. Add `DROP_TAKE_TAKE_MODE=menu` to take through the generated ground-item `Take` menu row after the server-backed drop.
- `PacketHandler530` records `combatTrace530` entries for decoded player/NPC hits, target masks, emote animations, and spotanims. `ASSERT_COMBAT_CONTACT_SMOKE=1` uses that trace to prove first combat feedback after the target packet.
- Combined first-playable smoke should run on the Java/530 path with `ASSERT_FIRST_PLAYABLE=1`, `CLIENT_PASSWORD=password`, and `rt4bankfx4`. That aggregate gate chains keepalive, NPC dialogue, bank inventory plus IF-button mutation, server-backed drop/take with menu-mode take, and combat contact in one pass; it supplies `BANK_FIXTURE_COMMAND='::bank'`, `BANK_INVENTORY_CONTAINER_IDS=93,95`, `BANK_ACTION_CONTAINER_ID=93`, `BANK_ACTION_MODE=if`, and `STABILITY_MS=60000` defaults. Use `ASSERT_FIRST_PLAYABLE_EXTENDED=1` after the base gate is green to add logout/relog and server-restart reconnect.
- `smoke-test.js` now prints an `Effective smoke config:` line at startup. Copy that line into live failure reports with the failing assertion so triage can confirm the resolved `CLIENT_URL`, bridge host/port/dialect, fixture account, and enabled gates before chasing packet or client behavior.
- Parser partial-wait diagnostics now include the wait reason (`size-byte`, `size-short`, or `body`), opcode, expected bytes, and available bytes in smoke failure payloads. Interface diagnostics also expose recent combat trace and transport evidence, including keepalive reason and flush byte count. Use this to distinguish harmless stream fragmentation from socket close/drop-client failures.
- First-playable live failures should be isolated before changing client behavior: verify `CLIENT_URL` plus bridge reachability with `CHECK_LIVE=1 2009scape-web/scripts/check-local-rt4-smoke.sh`, confirm the `rt4bankfx4` fixture was seeded with `CLIENT_PASSWORD=password`, clear tutorial/welcome UI blockers with a screenshot run when probes cannot find target rows, then rerun the individual keepalive, NPC dialogue, bank fixture, drop/take menu-mode, ground-item menu, and combat contact gates printed by the runbook script.
- Current local green gate: login, scene walk, minimap walk, native loc/NPC action probes, rendered-scene generic and NPC right-click menu dispatch, and logout/relog all pass against the local OpenRSC bridge dialect with no page errors.
- Live-stack prerequisites for that gate: a current `2009scape-web/client/dist` build served at `CLIENT_URL`, 530 cache files under `2009scape-web/client/client_cache/`, the WebSocket bridge listening at `CLIENT_SERVER_HOST:CLIENT_SERVER_PORT`, a live OpenRSC/2009scape stack behind the bridge that accepts the smoke credentials, and Playwright installed for `2009scape-web/e2e`. `check-local-rt4-smoke.sh` verifies files, syntax, and optionally the HTTP/bridge endpoints; the Playwright smoke remains the login/gameplay proof.
- Next protocol/render gate: live-validate loc-only rendered menu dispatch, live-validate dialogue-continue and server-restart reconnect probes, obtain or add the server-side native character-design decoder before encoding submit, and broaden rendered-scene click coverage to loc left-click defaults and object-specific rows.
- Next bank/inventory gate: live-run the deterministic `rt4bankfx4` fixture with `BANK_FIXTURE_COMMAND='::bank'`, `ASSERT_BANK_INVENTORY_PROBE=1`, `ASSERT_BANK_ACTION_PROBE=1`, `BANK_INVENTORY_CONTAINER_IDS=93,95`, `BANK_ACTION_CONTAINER_ID=93`, `BANK_INVENTORY_REQUIRE_OPEN=1`, and `BANK_INVENTORY_REQUIRE_ITEM=1`. The probe should emit IF action opcode `155` and observe container `93` losing or container `95` gaining the selected item.

## Current UI/Render/Asset Notes

- Interface parsing and CS2 execution are partial: the next useful gate is wiring `RUN_CS2` through richer `game.cs2Hooks`, preloading scripts needed by visible widgets, and opening panes through the real modal/tab stack.
- Sprite decode exists and font fallbacks are visible, but idx8/idx13 validation needs golden groups and visual captures before this can leave `Partial`.
- Texture/material decode is usable for simple terrain, but the next material gate is implementing the 530 cache texture ops still falling back to null/simple paths and capturing terrain visual baselines.

## Known Baseline Commands

Run from repo root unless noted.

```bash
cd 2009scape-web/client && npx tsc --noEmit
cd 2009scape-web/client && npm run build
cd 2009scape-web/client-patch && node .reference-435-advisory-test.mjs && node .first-playable-smoke-test.mjs && node .packet-handler530-chatbox-state-test.mjs && node .ground-item-legacy-bridge-test.mjs && node .ground-item-menu-fallback-test.mjs && node .combat-trace530-test.mjs && node .terrain-mesh-test.mjs && node .scene-wire-test.mjs && node .packet-trace-test.mjs && node .process-menu-530-audit.mjs && node .outgoing530-golden-test.mjs && node .menu-action-flow-trace.mjs
cd 2009scape-web/e2e && AUTO_LOGIN=1 CAPTURE_SCREENSHOTS=0 SEND_COMMAND=0 ASSERT_WALK=1 ASSERT_MINIMAP_WALK=1 ASSERT_ACTION_PROBES=1 ASSERT_RENDERED_ACTION_MENU=1 ASSERT_RENDERED_NPC_MENU=1 ASSERT_LOGOUT_RELOG=1 STABILITY_MS=0 CLIENT_SERVER_HOST=127.0.0.1 CLIENT_SERVER_PORT=43601 CLIENT_SERVER_DIALECT=openrsc235 CLIENT_URL=http://127.0.0.1:8765/ node smoke-test.js
cd 2009scape-web/e2e && AUTO_LOGIN=1 CAPTURE_SCREENSHOTS=0 SEND_COMMAND=0 ASSERT_BANK_INVENTORY_PROBE=1 ASSERT_BANK_ACTION_PROBE=1 BANK_FIXTURE_COMMAND='::bank' BANK_INVENTORY_CONTAINER_IDS=93,95 BANK_ACTION_CONTAINER_ID=93 BANK_ACTION_MODE=if CLIENT_USERNAME=rt4bankfx4 CLIENT_PASSWORD=password BANK_INVENTORY_REQUIRE_OPEN=1 BANK_INVENTORY_REQUIRE_ITEM=1 STABILITY_MS=0 CLIENT_SERVER_HOST=127.0.0.1 CLIENT_SERVER_PORT=43601 CLIENT_SERVER_DIALECT=530 CLIENT_URL=http://127.0.0.1:8765/ node smoke-test.js
cd 2009scape-web/e2e && AUTO_LOGIN=1 CAPTURE_SCREENSHOTS=0 ASSERT_FIRST_PLAYABLE=1 CLIENT_PASSWORD=password CLIENT_SERVER_HOST=127.0.0.1 CLIENT_SERVER_PORT=43601 CLIENT_SERVER_DIALECT=530 CLIENT_URL=http://127.0.0.1:8765/ node smoke-test.js
```

## Manual Acceptance Checklist

- Login, logout, relog, and reconnect after server restart.
- Walk by scene click and minimap click; confirm server-authoritative movement on native 530.
- Talk to an NPC, continue dialogue, choose an option, and close the interface.
- Open bank, move items, withdraw/deposit, close bank.
- Equip, operate, use, drop, and take an item.
- Use an item on loc/NPC/player/ground item/item.
- Open shop and buy/sell at least one item.
- Attack an NPC and observe movement, hitsplats, health bars, animations, sounds, and drops.
- Use prayer, magic, combat, skills, quest, music, emote, settings, friends, ignore, clan, and GE tabs.
- Verify music, jingle, synth sound, area sound, mute, and volume controls.
- Run a 2-hour session without page errors, packet desync, or client-caused disconnect.
