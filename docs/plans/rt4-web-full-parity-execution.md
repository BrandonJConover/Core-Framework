# RT4 Web Full Parity Execution Plan

This is the multi-session execution runbook for reaching rev-530 rt4 feature parity in the browser. Keep `docs/rt4-web-parity-matrix.md` as the source of truth for status and acceptance.

## Session Protocol

1. Pick one matrix row and one owner track.
2. Read the matching rt4 source first, usually `ClientProt.java`, `MiniMenu.java`, `Protocol.java`, `Component.java`, `InterfaceList.java`, `ScriptRunner.java`, or the relevant cache/model/audio class.
3. Implement the browser behavior in the 530-first path.
4. Add or update at least one acceptance artifact: unit test, `.mjs` probe, Playwright scenario, packet golden, visual capture, or manual checklist note.
5. Run the known-good checks affected by the change.
6. Update the parity matrix status and blockers before ending the session.

## Parallel Work Rules

- Protocol changes own `Outgoing530`, `PacketHandler530`, packet constants, packet goldens, and action dispatch.
- Renderer changes own terrain/scene/model/animation/picking code.
- UI/CS2 changes own component parsing, interface state, scripts, widget clicks, and modal/tab stack.
- Assets/Audio changes own fonts, sprites, textures, music, sound effects, and preferences.
- QA/Infra changes own Playwright, smoke scripts, local-stack scripts, visual baselines, docs, and CI gates.
- Agents must not edit the same files in parallel unless one is read-only or the owner explicitly sequences the work.

## Phase 0: Tracking And Baseline

- Keep `docs/rt4-web-parity-matrix.md` current.
- Normalize baseline commands into a script once the current dirty worktree settles.
- Preserve the prototype-playable smoke: login, render, local/NPC render, chat input, click movement, no page errors.
- Record current bridge limitations: OpenRSC local dialect is a test adapter; native 530 parity should become server-authoritative.

## Phase 1: Protocol And Action Parity

- Finish `Game.processMenuActions()` conversion so gameplay actions do not write legacy 377 packets.
- Add `Outgoing530` encoders for every rt4 `ClientProt`/`MiniMenu` action not already covered.
- Add exact byte tests for each encoder.
- Add packet-golden flow tests for walk, object click, NPC talk, item use/drop/take, bank open, shop open, dialogue continue, combat click, private message, logout.
- Expand `PacketHandler530` coverage table and trace output so unknown normal-play packets become actionable defects.

## Phase 2: World Rendering And Interaction

- Finish 530 scene picking for terrain, locs, players, NPCs, and ground items.
- Complete terrain color/lighting/texture/minimap parity.
- Complete loc shape/orientation/morph/render/pick/animate parity.
- Complete actor rendering: player/NPC appearances, masks, animations, spotanims, overhead text, hitsplats, health bars, icons.
- Add visual captures for spawn, movement, NPC area, object area, combat, minimap, bank, inventory, dialogue.

## Phase 3: UI, CS2, And Gameplay Loops

- Complete rt4 component/interface stack: modal stack, tab stack, server active properties, access masks, dynamic children.
- Expand CS2 VM until core interfaces run without stubs for bank, settings, friends/ignore, clan, GE, quest journal, music, emotes, prayer, magic, combat.
- Wire interface clicks and selected-target actions through `Outgoing530`.
- Add E2E scenarios for each gameplay loop listed in the parity matrix manual checklist.

## Phase 4: Assets, Audio, Performance, Release

- Replace font/sprite stubs with real idx8/idx13 assets.
- Finish texture-op pipeline for all referenced 530 material ops.
- Ship music OGG catalog and complete synth/area/jingle audio handling.
- Harden browser shell for focus, keyboard, mouse, touch, resize, fullscreen, HiDPI, persistence.
- Profile startup, cache decode, model composition, terrain chunking, animation tick, memory, and long-session stability.
- Complete deployment/recovery runbooks and CI gates.

## Definition Of Done For 100% Parity

- No unsupported rt4 gameplay packet in normal play.
- No unknown server opcode in normal play.
- No legacy gameplay packet leaks from browser actions.
- All core gameplay loops pass automated E2E and manual checklist.
- Visual captures approved for representative game states.
- Audio/music behavior works with browser-safe unlock and preferences.
- 2-hour soak passes without page errors, packet desync, memory blow-up, or client-caused disconnect.

