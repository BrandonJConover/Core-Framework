# Rust Server Parity Status

Last updated: 2026-05-22

## Current Coordinator Snapshot

The Rust server has a strong foundation but is not at Java-server feature parity. `cargo test` currently passes locally for both Rust binaries: `conn_storm` has 8 passing smoke-helper tests, and `openrsc-server` has 644 passing tests with 1 ignored test. The latest Lane 2 evidence includes live local TCP and WebSocket Java-style pre-login server-config opcode `19` checks, a unit-covered Java custom desktop `CLIENT_VERSION=10010` RSA password login decode path, `conn_storm --custom-rsa-login` live login/reconnect coverage using the Java desktop RSA packet shape, login/bootstrap/action/command/combat-style/prayer-toggle/logout/reconnect smoke checks, plus DB-backed TCP and WebSocket reconnect smoke checks against SQLite persistence including game/privacy settings and bank open/withdraw/deposit/close/shop buy/shop sell/shop close persistence. Latest playable-loop evidence also boots Rust with `OPENRSC__JAVA_LOCS_DIR=../server-java-modern/conf/server/defs/locs`, applies 3608 NPCs, 27781 objects, 1019 ground items, loads 1296 Java object collision definitions, and passes TCP/WS `--expect-playable --expect-reconnect --custom-rsa-login` smokes. Bank ownership/persistence now exists as player-owned Rust state with repository, mapper, packet-layout, and live DB reconnect tests. Rust now handles Java-authentic banker NPC and bank object command routes for seeded bankers/booths, replacing the temporary chat-command path in the DB bank smoke. Lane 6 now mirrors additional Java bank edge behavior for closed-bank reset, zero/missing item no-ops, key denial messages, Java-style shop open payloads, Java shop buy/sell request parsing, Java-style modern stock-sensitive shop pricing/modifiers, authentic Java general store/Aubury/Wydin/Varrock Sword Shop/Bob's Axes/Lowe's Archery Store/Brian's Battle Axe Bazaar/Horvik's Armoury OpenPK/Flynn's Mace Market/Nurmof's Pickaxe Shop/Drogo's Mining Store/Gerrant's Fishy Business/Grum's Gold Exchange/Tea Seller/Gem Trader catalog data, live shop buy/sell/close dispatcher adapters with visible coin/item movement, and DB reconnect shop smoke coverage. Lane 3 has Java loc JSON loading plus opt-in runtime spawn application via `OPENRSC__JAVA_LOCS_DIR`, Java `GameObjectDef` collision loading, Java boundary and scenery loc collision-map derivation, reusable movement-collision policy helpers, first-area Java loc spawn-count/boundary/scenery-collision validation, and live walk waypoint filtering through the Java-loc collision map when opted in; Lane 4 has Java-style ground-item in-grid removal encoding, LF-terminated custom-v235 `SEND_UPDATE_PLAYERS` public-chat writer/fixtures now wired into the live tick update path, custom-v235 player appearance fixture coverage, custom-v235 `SEND_UPDATE_NPC` damage coverage, custom-v235 `SEND_UPDATE_PLAYERS` player damage coverage, custom-v235 known-NPC movement/removal coverage, custom-v235 known-player movement/removal coverage, custom-v235 player-to-NPC projectile coverage, and custom-v235 player-to-player projectile coverage for Java entity-update parity. Lane 1 has custom-v235 privacy, friend-update, ignore-list, private-message-sent, and private-message-received fixtures, and Lane 9/10 has typed compiled-content trigger helpers, real NPC dialogue/options/bank-open packet output for compiled content, answer-gated dialogue state for Bank Assistant bank opening, beginner/tutorial plugin slices including the Financial Advisor, Quest Advisor, Wilderness Guide, Mining Instructor, Fishing Instructor, Cooking Instructor, Combat Instructor, Community Instructor, Fatigue Expert, Magic Instructor, and Bank Assistant, live NPC/object/boundary/item-on-item/item-on-object/item-on-NPC/dialogue-answer content dispatch, and content-effect runtime command planning/apply helpers. Many tests still cover standalone Rust modules rather than live Java-client gameplay integration.

## Active Milestone

Milestone 1: **Playable Loop**

Acceptance target:
- Existing Java-compatible clients can login, receive world bootstrap packets, see streamed entities, walk with collision, chat, pick up/drop items, logout, and reconnect with persisted state.
- Each covered packet family has at least one parity/golden test or fixture-backed assertion.

## Session Start Checklist

1. Read this file and `OWNERSHIP.md`.
2. Read `PHASES.md` for phase gates and current parallel-round focus.
3. Check `git status --short` and avoid reverting unrelated dirty work.
4. Pick exactly one lane and record the intended write scope in this file.
5. Add tests or fixtures for any behavior moved toward `parity`.
6. Update `PARITY.md` only when evidence is present.

## Lane Queue

| Lane | State | Next Slice |
|---|---|---|
| 0 | active | Keep tracker current and split shared files into small reviewable slices. |
| 1 | active | Extend custom-v235 fixtures from privacy settings to social list, private-message, and encrypted chat payloads. |
| 2 | active | Verify Rust config/login with a real Java desktop client, confirm post-login UI/bootstrap packet order, then decide whether any client flavor needs ISAAC immediately after login. |
| 3 | active | Derive scenery/tile collision flags from Java object definitions and landscape `.orsc` files, then capture real-client movement/collision evidence in the first playable area. |
| 4 | ready | Add Java-generated entity goldens for additional damage variants and real-client rendering evidence. |
| 5 | active | Wire one unhandled Java opcode group at a time. Next high-value group is remaining item-use/magic adapters and richer dialogue output. |
| 6 | active | Replace more remaining hard-coded/default shops with authentic Java shop catalog data and add real-client shop evidence; remaining bank edge work is notes/certs, deposit-all, pins/presets, and deeper capacity semantics. |
| 7 | ready | Close melee combat packet gaps, then ranged/magic/prayer integration. |
| 8 | ready | Wire one gathering skill end-to-end through object/NPC/item interactions. |
| 9 | active | Extend live compiled-content dispatch into dialogue/menu answer state and richer dialogue packet output. |
| 10 | ready | Port the next tutorial/beginner dialogue batch on top of the compiled-content runtime helpers, then wire menu/dialogue answer packets into live content state. |
| 11 | ready | Fill persistence/config parity gaps discovered by playable-loop testing. |

## Active Parallel Round

Started: 2026-05-22, completed

- Lane 1 worker completed: added payload-first custom-v235 `SEND_PRIVATE_MESSAGE` fixture for sender `Alice`, former name `Alicia`, icon sprite `0`, and Java RSC-string message `hello`.
- Lane 2 worker completed: booted Rust with Java locs/object collision definitions enabled and passed TCP plus WebSocket playable/reconnect/custom-RSA smokes on side ports `46694` and `46697`.
- Lane 6 worker completed: added authentic Gem Trader catalog data from Java `GemTrader.java` with default registration and shop-open packet coverage.
- Lane 9/10 worker completed: made Bank Assistant opening answer-gated via active compiled-content dialogue state; talk now sends dialogue/options, option `0` opens bank and advances tutorial stage.
- Lane 0 coordinator completed: preserved lane ownership, integrated completed slices, updated tracker notes, and verified formatting, focused tests, diff whitespace, and full Rust validation.

Previous round, completed:

Started: 2026-05-22, completed

- Lane 1 worker completed: added payload-first custom-v235 `SEND_PRIVATE_MESSAGE_SENT` fixture for recipient `Alice` and Java RSC-string message `hello`.
- Lane 2 worker completed: booted Rust with Java locs/object collision definitions enabled and passed TCP plus WebSocket playable/reconnect/custom-RSA smokes on side ports `45694` and `45697`.
- Lane 6 worker completed: added authentic Tea Seller catalog data from Java `TeaSeller.java` with default registration and shop-open packet coverage.
- Lane 9/10 worker completed: added `ContentEffect::OpenBank`, `ContentRuntimeCommand::OpenBank`, live content sink bank-open wiring, and Bank Assistant bank-open content effect coverage.
- Lane 0 coordinator completed: preserved lane ownership, integrated completed slices, updated tracker notes, and verified formatting, focused tests, diff whitespace, and full Rust validation.

Previous round, completed:

Started: 2026-05-22, completed

- Lane 1 worker completed: added payload-first custom-v235 `SEND_IGNORE_LIST` fixture for one renamed ignore entry (`Eve` / `Evie`) plus golden payload assertions.
- Lane 3 worker completed: loaded Java `GameObjectDef.xml` collision fields beside configured Java locs, stored them on `World`, and used them in runtime Java-loc movement policy while preserving seeded defaults.
- Lane 6 worker completed: added authentic Grum's Gold Exchange catalog data from Java `GrumsGoldShop.java` with default registration and shop-open packet coverage.
- Lane 10 worker completed: ported the tutorial Bank Assistant NPC from Java `BankAssistant.java` as compiled beginner content with dialogue/menu/tutorial-stage effect tests.
- Lane 0 coordinator completed: preserved lane ownership, integrated completed slices, updated tracker notes, and verified formatting, focused tests, diff whitespace, and full Rust validation.

Previous round, completed:

Started: 2026-05-22, completed

- Lane 1 worker completed: added payload-first custom-v235 `SEND_FRIEND_UPDATE` online fixture for `Alice` on world `main`, plus golden payload assertions.
- Lane 3 worker completed: added Java-style scenery footprint collision for `GameObjectDef` type `1`, opt-in object-definition-aware Java loc collision map construction, and first-area table collision validation.
- Lane 6 worker completed: added authentic Gerrant's Fishy Business catalog data from Java `GerrantsFishingGear.java` with default registration and shop-open packet coverage.
- Lane 10 worker completed: ported the tutorial Magic Instructor NPC from Java `MagicInstructor.java` as compiled beginner content with dialogue/menu-option effect tests.
- Lane 0 coordinator completed: preserved lane ownership, integrated completed slices, updated tracker notes, and verified formatting, focused tests, diff whitespace, and full Rust validation.

Previous round, completed:

Started: 2026-05-21, completed

- Lane 2 worker completed: live Rust TCP and WebSocket `conn_storm --expect-playable --expect-reconnect --custom-rsa-login` passed against side ports with Java desktop RSA login shape; no code changes were needed.
- Lane 3 worker completed: added first-area Java loc spawn-count and boundary-collision validation from real `NpcLocs`/`SceneryLocs`/`BoundaryLocs`/`GroundItems` assets.
- Lane 6 worker completed: added authentic Drogo's Mining Store catalog data from Java `Drogo.java` with default registration and shop-open packet coverage.
- Lane 10 worker completed: ported the tutorial Fatigue Expert NPC from Java `FatigueExpert.java` as compiled beginner content with message/dialogue/tutorial-stage effect tests.
- Lane 0 coordinator completed: preserved lane ownership, integrated completed slices, updated tracker notes, and verified formatting, focused tests, diff whitespace, and full `cargo test --quiet`.

Previous round, completed:

Started: 2026-05-21, completed

- Lane 10 worker completed: ported the tutorial Cooking Instructor NPC from Java `CookingInstructor.java` as compiled beginner content with dialogue/message/item-grant effect tests.
- Lane 6 worker completed: added authentic Nurmof's Pickaxe Shop data from Java `NurmofPickaxe.java` with catalog/open-packet tests.
- Lane 4/1 worker completed: added payload-first custom-v235 `SEND_UPDATE_PLAYERS` player damage fixture coverage and shared state-updater/golden assertions.
- Lane 0 coordinator completed: integrated completed slices, updated tracker notes, and verified formatting, JSON fixtures, focused tests, and full `cargo test --quiet`.

Previous round, completed:

- Lane 9/10 worker completed: added `NpcDialogue` and `DialogueOptions` content effects, runtime commands, and live sink packet output using dialogue packet builders.
- Lane 4/1 worker completed: added payload-first custom-v235 `SEND_UPDATE_PLAYERS` player-to-player projectile fixture coverage and shared state-updater/golden assertions.
- Lane 6 worker completed: added authentic Flynn's Mace Market data from Java `FlynnMaces.java` with catalog/open-packet tests.
- Lane 10 worker completed: ported the tutorial Community Instructor NPC as compiled beginner content with NPC dialogue and menu option effects.
- Lane 0 local coordinator completed: updated tracker notes, integrated completed slices, and verified formatting, JSON fixtures, focused tests, and full `cargo test --quiet`.

Previous round, completed:

- Lane 5/9 worker completed: wired Java `QUESTION_DIALOG_ANSWER` into compiled `DialogueAnswer` content dispatch with signed-byte parser and live adapter tests.
- Lane 4/1 worker completed: added payload-first custom-v235 `SEND_UPDATE_PLAYERS` player-to-NPC projectile fixture coverage and shared state-updater assertions.
- Lane 6 worker completed: added authentic Horvik's Armoury OpenPK data from Java `HorvikTheArmourerOpenPk.java` with catalog/open-packet tests.
- Lane 10 worker completed: ported the tutorial Combat Instructor NPC as compiled beginner content with dialogue/message/item-grant/tutorial-stage effect tests.
- Lane 0 local coordinator completed: updated tracker notes, integrated completed slices, and verified formatting, JSON fixtures, focused tests, and full `cargo test --quiet`.

Previous round, completed:

- Lane 5/9 worker completed: wired Java custom `NPC_USE_ITEM` into compiled `UseItemOnNpc` content dispatch with parser and live adapter tests.
- Lane 4/1 worker completed: added payload-first custom-v235 `SEND_PLAYER_COORDS` known-player movement/removal fixture coverage and shared state-updater assertions.
- Lane 6 worker completed: added authentic Brian's Battle Axe Bazaar data from Java `BriansBattleAxes.java` with catalog/open-packet tests.
- Lane 10 worker completed: ported the tutorial Fishing Instructor NPC as compiled beginner content with dialogue/message/item-grant/tutorial-stage effect tests.
- Lane 0 local coordinator completed: updated tracker notes, integrated completed slices, and verified formatting, JSON fixtures, focused tests, and full `cargo test --quiet`.

- Lane 5/9 worker completed: wired Java custom `USE_ITEM_ON_SCENERY` into compiled `UseItemOnObject` content dispatch with parser and live adapter tests.
- Lane 4/1 worker completed: added payload-first custom-v235 `SEND_NPC_COORDS` known-NPC movement/removal fixture coverage and shared state-updater assertions.
- Lane 10 worker completed: ported the tutorial Mining Instructor NPC as compiled beginner content with dialogue/message/tutorial-stage effect tests.
- Lane 6 worker completed: added authentic Lowe's Archery Store data from Java `LowesArchery.java` with catalog/open-packet tests.
- Lane 0 local coordinator completed: updated tracker notes, integrated completed slices, and verified formatting, JSON fixtures, focused tests, and full `cargo test --quiet`.

Previous round, completed:

- Lane 4/1 worker completed: added a payload-first custom-v235 `SEND_UPDATE_PLAYERS` type-5 player appearance fixture and shared builder/test coverage.
- Lane 5/9 worker completed: wired Java `ITEM_USE_ITEM` packets into compiled `UseItemOnItem` content events with focused adapter tests.
- Lane 6 worker completed: added authentic Bob's Axes default shop data from `BobsAxes.java` with catalog/open-packet tests.
- Lane 10 worker completed: ported the tutorial Wilderness Guide NPC as compiled beginner content with dialogue/message/tutorial-stage effect tests.
- Lane 0 local coordinator completed: updated tracker notes, integrated completed slices, and verified formatting, JSON, focused tests, and full `cargo test --quiet`.

Previous round, completed:

- Lane 4 worker completed: live public chat update emission now appends the shared LF-terminated custom-v235 `SEND_UPDATE_PLAYERS` payload helper, with a live tick layout test.
- Lane 5/9 worker completed: `OBJECT_COMMAND`/`OBJECT_COMMAND2` now try compiled `UseObject` content before bank-object fallback, and `INTERACT_WITH_BOUNDARY`/`INTERACT_WITH_BOUNDARY2` dispatch `UseBoundary` content events.
- Lane 6 worker completed: default shop 2 now uses the authentic Java Varrock Sword Shop catalog from `VarrockSwords.java`, with catalog/open-packet tests.
- Lane 10 worker completed: Quest Advisor NPC `489` is registered as compiled beginner content using `QuestAdvisor.java` as the oracle, with dialogue/message/tutorial-stage effect tests.
- Lane 0 local coordinator completed: preserved lane boundaries, integrated completed slices, refreshed tracker notes, and verified `cargo fmt --all` plus full `cargo test --quiet`.

- Lane 3 worker completed: exposed Java loc collision through a reusable movement-collision policy while preserving seeded default behavior, added runtime tile blockers, and implemented the pathfinding collision trait for the walking collision map.
- Lane 4/1 worker completed: added LF-terminated custom-v235 `SEND_UPDATE_PLAYERS` player-chat writer/packet helper, updated fixtures/docs, and verified the fixture-backed protocol/state-updater tests after the shared server compile issue was resolved.
- Lane 6 worker completed: replaced the default general store and Aubury rune shop built-ins with Java/OpenRSC-authentic catalog data and added catalog/open-packet assertions.
- Lane 5/9 worker completed: registered the compiled beginner/tutorial content by default, added the live content runtime sink adapter, and routed `NPC_TALK_TO` plus primary `NPC_COMMAND` through compiled content while preserving banker fallback behavior.
- Lane 3 follow-up worker completed: live `WALK_TO_POINT` now filters Java waypoint queues through `World::can_move_with_collision` when Java loc collision is configured, preserving seeded test behavior otherwise.
- Lane 4/1 follow-up worker completed: added a custom-v235 `SEND_UPDATE_NPC` damage packet helper, fixture, and docs for hitpoint update parity.
- Lane 6 follow-up worker completed: replaced built-in shop 4 with Java-authentic Wydin's Food Store data and verified catalog/open-packet behavior.
- Lane 10 follow-up worker completed: ported the tutorial Financial Advisor talk trigger as compiled Rust content with dialogue/message/stage effects.
- Lane 0 local coordinator completed: reviewed shared-file integration, ran focused tests across content/protocol/world/entity/shop/smoke paths, and refreshed this tracker.

## Handoff Notes

- Protocol enum names already mirror Java; do not rename them for Rust style.
- `game/server.rs` decodes incoming opcodes through the session protocol version. Unknown/contextual opcodes still need better visible failure tests.
- TCP and WebSocket transports now send login responses as the Java-compatible one raw status byte, while regular game packets remain framed as `u16 length | opcode | payload`.
- `conn_storm --expect-bootstrap` verifies the raw login byte plus required bootstrap and first tick entity opcodes over TCP or WebSocket.
- `conn_storm --expect-bootstrap`, `--expect-playable`, `--expect-reconnect`, and `--expect-db-reconnect` now first open a separate pre-login TCP/WS connection, send Java desktop client config request bytes `[0, 1, 19]`, and verify `SEND_SERVER_CONFIGS` opcode `19` with Java-style line-feed-terminated strings, 88 config entries, RSA exponent `010001`, and the Java `server.pem` modulus. Latest local TCP/WS DB reconnect smoke runs passed this check on side ports.
- `LoginRequest::decode` now accepts both the legacy/null-terminated smoke login shape and the Java custom desktop login shape (`reconnecting` byte, `CLIENT_VERSION=10010`, LF-terminated username, encryption version `1`, RSA password block, RSA client-details block, UID/trailing client limitations). Unit coverage builds a Java-client-style RSA block with the advertised server modulus and verifies the password decrypts/pads/trims as Java `LoginPacketHandler` expects.
- `conn_storm --custom-rsa-login` now sends the Java desktop-style custom RSA login envelope instead of the legacy null-terminated smoke login: opcode `0`, reconnecting byte, `CLIENT_VERSION=10010`, LF-terminated username, encryption marker `1`, RSA password block, RSA client-details block, and UID trailer. Reconnect in this mode also uses opcode `0` with reconnecting byte `1`, matching the Java inauthentic custom desktop branch rather than the authentic v177 relogin opcode `19`.
- Java reference check for the custom desktop branch: after config/login, the Java 21 inauthentic `authenticClient == -1` path sends server configs and login packets without immediately installing ISAAC ciphers for the custom desktop frame stream. Next real-client check should therefore focus first on packet order/UI bootstrap gaps, while keeping ISAAC validation open for other authentic client paths.
- `conn_storm --expect-playable` now runs the bootstrap smoke plus walk, public chat, `online`/`pos` command server-message responses, combat-style selection, prayer activate/deactivate response bitmap checks, ground-item pickup, item drop, and the expected player/server-message/combat-style/prayer/inventory/ground-item response packets. Latest repeated local runs passed with `--custom-rsa-login` against Rust on side-by-side ports: TCP `127.0.0.1:44594` and WS `127.0.0.1:44494`.
- `conn_storm --expect-reconnect` now verifies logout/reconnect over both transports: TCP sends Java v177 `LOGOUT` opcode `6`, WebSocket sends Java v177 `CONFIRM_LOGOUT` opcode `1`, both wait for server disconnect, then reconnect with Java v177 relogin opcode `19` and the reconnecting flag set. Latest local live runs passed combined `--expect-playable --expect-reconnect --custom-rsa-login` smoke against Rust side ports with Java locs enabled: TCP `127.0.0.1:46694` p50 `26us`, WS `127.0.0.1:46697` p50 `59us`. The Java-loc boot applied 3608 NPCs, 27781 objects, 1019 ground items, and loaded 1296 Java object collision definitions.
- `conn_storm --expect-db-reconnect` now seeds a SQLite account, logs in through real DB auth, verifies bootstrap position/skills/inventory/game settings, walks one tile, changes appearance colors/body/head/gender fields, changes combat style, changes game settings, changes privacy settings, opens seeded bank rows through Java v177 `OBJECT_COMMAND` against the seeded bank booth and verifies `SEND_BANK_OPEN`, withdraws then redeposits one bank item with `SEND_BANK_UPDATE`/`SEND_INVENTORY` checks, closes the bank, opens default shop 2 through the debug opener, buys and sells bronze sword `66`, closes the shop, logs out, asserts DB rows for position/skills/appearance/inventory/bank/combat style/settings/post-shop coin count, reconnects, verifies the second bootstrap, and opens the same bank rows through Java v177 `NPC_COMMAND` against the seeded banker NPC over TCP and WebSocket. Latest local live runs passed on TCP `127.0.0.1:44594` and WS `127.0.0.1:44494` against `/tmp/openrsc-db-bank-movement-smoke.db` with `--custom-rsa-login`, so the DB reconnect smoke now covers the Java desktop RSA login/reconnect packet shape and a live shop transaction loop.
- Rust dispatch now handles both `OpcodeIn::Logout` and `OpcodeIn::CONFIRM_LOGOUT` through the same logout path. Outbound Java-style logout confirmation packets are still not emitted before disconnect, so that remains a protocol parity caveat rather than a playable-loop blocker.
- DB persistence caveat for reconnect work: repository-backed login currently hydrates DB id, position, fatigue, appearance, skills, combat style, sparse inventory slots, player bank rows, and the seven persisted settings booleans. Logout saves position, skills, appearance, combat style, inventory slot rows, player bank rows, and settings. Auto-save still saves position and skills only. Quests, friends/ignores, fatigue on save, last login/online flags, group/staff metadata, and skull still need save/load coverage before the persisted-state part of Milestone 1 can be marked complete.
- Inventory persistence now maps `player_inventory.equipped` to the live inventory slot `wielded` flag and `noted` to the live item note flag. This is covered by a SQLite repository replacement test, a transaction rollback regression test, a pure helper round-trip test, and the DB-backed TCP/WS `conn_storm` reconnect smoke.
- Game settings now support Java v177 `GAME_SETTINGS_CHANGED` two-byte packets for camera auto, one-button mouse, and sound-off settings, echo `SEND_GAME_SETTINGS`, hydrate from `player_settings`, persist on logout, and are covered by DB-backed TCP/WS reconnect smoke. Privacy settings use the same settings row and are persisted through the existing live handler.
- Rust `api_port` is configurable through `OPENRSC__API_PORT`, allowing side-by-side Java-vs-Rust smoke runs when Java already owns port 43595.
- Java `PayloadProcessorManager` is the required incoming-handler oracle.
- Compiled Rust content is the chosen strategy; do not introduce Lua/Rhai scripting for parity v1.
- Lane 1 should use payload-first fixtures under `protocol-golden/custom-v235/`; keep Java/Rust transport framing tests separate because the current simplified Rust codec and Java inauthentic encoder frame bytes differently.
- Lane 1 custom-v235 privacy settings fixtures landed for incoming wire opcode `64` payload `00010200` and outgoing `SEND_PRIVACY_SETTINGS` wire opcode `51` payload `00010200`. Social fixture coverage now includes payload-first Java custom-client `SEND_FRIEND_UPDATE` wire opcode `149` for `Alice` coming online on world `main`, `SEND_IGNORE_LIST` wire opcode `109` for one renamed ignore entry (`Eve` / `Evie`) using the Java duplicate-string layout, `SEND_PRIVATE_MESSAGE_SENT` wire opcode `87` for recipient `Alice` with Java `writeRSCString` message `hello`, and `SEND_PRIVATE_MESSAGE` wire opcode `120` for sender `Alice`, former name `Alicia`, icon sprite `0`, and Java RSC-string message `hello`. Keep future payload fixtures separate from transport framing tests.
- Lane 5 should keep `game/server.rs` as a thin wire adapter. Move gameplay rules into bank/trade/shop/dialogue/item-use/magic/prayer/duel/social/fatigue modules instead of growing business logic in the dispatcher.
- Lane 9/10 should register compiled content via `ContentPlugin` and `ContentTrigger`; content should return effects rather than directly owning runtime world/session state.
- Current Lane 1 fixtures cover custom-v235 server message, privacy settings, bank deposit/withdraw/close, and prayer activate/deactivate. Withdraw is the custom parser shape (`short catalogID`, `int amount`); authentic v203/v235 magic-number withdraw needs a separate fixture family.
- Current Lane 5 live adapter progress: `PRIVACY_SETTINGS_CHANGED` parses four Java custom bytes and updates `PlayerSettings`. `PRAYER_ACTIVATED`/`PRAYER_DEACTIVATED` parse the Java custom one-byte prayer id, update `Player.prayer`, send the Java-compatible 14-byte `SEND_PRAYERS_ACTIVE` bitmap on bootstrap/toggle, and feed active prayer combat bonuses into combat snapshots.
- Prayer parity caveats remain: Java `LACKS_PRAYERS` message text, duel no-prayer restrictions, UIM protect-item blocking, authentic drain cadence, persistence/restore semantics for active prayers, and real Java-client UI evidence are still pending.
- Lane 3 has `world_loader` for Java/OpenRSC `NpcLocs.json`, `SceneryLocs.json`, `BoundaryLocs.json`, and `GroundItems.json`, plus `World::apply_spawn_manager` / `World::apply_base_java_locs_dir` to explicitly apply those spawns to a live `World`. `GameState::initialize` now preserves seeded default behavior unless `OPENRSC__JAVA_LOCS_DIR` or `with_java_locs_dir` opts into Java loc spawns; when opted in, it also loads sibling `GameObjectDef.xml` collision fields for object-definition-aware scenery blocking. `CollisionMap::apply_java_object_spawn` / `apply_java_boundary` and `World::java_loc_collision_map()` derive Java boundary-object blockers from loaded locs, live `WALK_TO_POINT` now filters queued Java waypoints through `World::can_move_with_collision` when Java loc collision is configured, and `base_java_locs_first_area_spawn_slice_drives_boundary_collision` validates real first-area spawn counts plus Java boundary blocking at `(424,18)`. `CollisionMap::apply_java_scenery` and `World::java_loc_collision_map_with_object_defs` now also apply Java `GameObjectDef` type-1 scenery footprints, with first-area validation for the table at `(426,15)`. Next slices are deriving broader landscape `.orsc` tile flags and capturing real-client collision evidence.
- Lane 4 ground item streaming now uses Java custom in-grid removal encoding: `short(item_id | 0x8000) | byte(dx) | byte(dy)`, while preserving `0xff | dx | dy` tile-clear behavior for out-of-grid removals. Lane 4 also has payload-only fixtures for `SEND_UPDATE_PLAYERS` type-1 public chat, type-2 player damage layout, type-5 player appearance, type-3 player-to-NPC projectile layout, type-4 player-to-player projectile layout, `SEND_UPDATE_NPC` type-2 damage layout, `SEND_NPC_COORDS` known-NPC movement/removal layout, and `SEND_PLAYER_COORDS` known-player movement/removal layout. `out_update_players_chat.json` and `out_update_players_chat_java_custom.json` assert the Java custom chat layout with LF-terminated icon/message strings through `state_updater::build_custom_v235_player_chat_update_packet`; the live server tick path now appends that shared helper payload for queued public chat. `out_update_players_appearance_java_custom.json` asserts one Java custom type-5 appearance entry with LF-terminated username/icon strings, zero equipment, colors, combat level, skull/clan/visibility/invulnerability flags, and group id. `out_update_players_damage_java_custom.json` asserts custom-v235 player damage entries as `count | player_index | type=2 | damage/current/max`. `out_update_players_projectile_java_custom.json` asserts one Java custom player-to-NPC projectile update as `count | caster_player_index | type=3 | projectile_type | victim_npc_index`; `out_update_players_projectile_player_java_custom.json` asserts the same field widths for type-4 player victims. `out_update_npc_damage_java_custom.json` asserts custom-v235 NPC damage entries as `count | npc_index | type=2 | damage/current/max`. `out_npc_coords_known_move_remove_java_custom.json` asserts Java custom known-NPC local-cache movement/removal without NPC indices: slot 0 moves east and slot 1 is removed. `out_player_coords_known_move_remove_java_custom.json` asserts Java custom known-player local-cache movement/removal with viewer coordinate/facing bits, prior local-player count, slot 0 moving east, and slot 1 removal. The remaining Lane 4 work is expanding Java-generated entity fixtures for additional damage variants, then capturing real-client rendering evidence.
- Bank deposit/withdraw request parsing exists in `bank_handler`, and connected `Player` now owns a `PlayerBank` hydrated from and saved to `player_bank`. Bank open/update packet builders now use Java-compatible compact amount encoding and one-slot `SEND_BANK_UPDATE` deltas. `NPC_COMMAND` on Java banker IDs `95, 224, 268, 540, 617` and `OBJECT_COMMAND`/`OBJECT_COMMAND2` on Java bank object IDs `64, 942` open persisted bank contents; seeded Lumbridge banker/booth fixtures let DB-backed TCP/WS reconnect smoke cover authentic bank open plus session-gated withdraw/deposit/close movement. The temporary `bank` command remains as a debug helper, but the smoke no longer depends on it. Latest Lane 6 bank edge slice makes closed-bank deposit/withdraw packets send the same close/reset interface packet Rust uses for bank close, makes zero-amount packets no-op while the bank is open, makes missing inventory/bank items no-op like Java, and maps full-bank/full-inventory denial text to Java wording (`You don't have room for that in your bank`, `You don't have room to hold everything!`). Coverage: `cargo test --quiet bank_handler`, `cargo test --quiet maps_bank_errors_to_java_style_messages`, full `cargo test --quiet`, plus TCP and WS `conn_storm --expect-db-reconnect --custom-rsa-login` side-port smokes passed. Next bank work is notes/certs, deposit-all, pin/preset flows, and deeper capacity semantics.
- Shop handler now builds Java custom/v235 `SEND_SHOP_OPEN` payloads: count, general flag, sell/buy/price modifiers, then item id/current stock/base stock triples. `ShopItemAmountRequest` parses Java buy/sell payloads (`catalog_id`, stock amount, amount), and live `SHOP_BUY`/`SHOP_SELL`/`SHOP_CLOSE` adapters now update shop stock, move visible coins/items through player inventory, send shop/inventory/close packets, and clear open shop state on logout. The built-in Varrock Sword Shop, Aubury rune shop, Wydin's Food Store, Bob's Axes, Lowe's Archery Store, Brian's Battle Axe Bazaar, Horvik's Armoury OpenPK, Flynn's Mace Market, Nurmof's Pickaxe Shop, Drogo's Mining Store, Gerrant's Fishy Business, Grum's Gold Exchange, Tea Seller, Gem Trader, and default general store now use Java/OpenRSC-authentic stock IDs/amounts plus restock, sell, buy, and price modifiers, and Rust shop pricing uses Java-style modern stock-sensitive buy/sell math. `conn_storm --expect-db-reconnect` covers this path over TCP and WebSocket through a small debug shop opener. Remaining shop work is loading authentic Java shop catalog data beyond the current built-ins, real-client/shop smoke evidence, and deeper stack/cert/capacity semantics.
- Lane 9 typed content scaffold now has `ContentTriggerKey`, full `ContentEvent` variants for declared trigger kinds, typed registration helpers (`on_talk_npc`, `on_use_item_on_npc`, `on_use_item_on_object`, `on_dialogue_answer`, `on_command`, etc.), exact-key-first dispatch with kind-wide fallback, command case normalization, and tests. `content::beginner::BeginnerTutorialPlugin` is the first compiled Rust content slice, with tutorial guide, Financial Advisor, Quest Advisor, Wilderness Guide, Mining Instructor, Fishing Instructor, Cooking Instructor, Combat Instructor, Community Instructor, Fatigue Expert, Magic Instructor, Bank Assistant, and controls guide triggers returning message/dialogue/options/quest-stage/item-grant/open-bank effects. `content::runtime` now translates ordered `ContentEffect` batches into typed runtime commands including real NPC dialogue, menu option, shop-open, and bank-open packet output, can build a plan directly from a registry event, and applies through a `ContentRuntimeSink` with first-failed-command indexing. Live server dispatch now feeds NPC talk/command, object command, boundary interaction, item-on-item, item-on-object, item-on-NPC, and dialogue-answer events into compiled content, and keeps a narrow per-player active compiled-content dialogue id so Bank Assistant opens the bank only after option `0` is selected. Remaining content architecture work is broader multi-step dialogue state and richer dialogue packet coverage.
- Round 1 full-parity execution ran six parallel explorer agents due to the current thread cap. Lane 1 recommends Java-generated custom-v235 fixtures for privacy/social/encrypted chat first. Lane 2 identified the first real-client blocker as the Java desktop client's pre-login server-config opcode `19` plus authentic RSA/login payload shape; Rust now responds to the small config request and decodes the custom desktop RSA password block, leaving real-client verification and possible post-login ISAAC enablement as the next blocker. Lane 3's first data-loader slice has landed. Lane 4's first ground-item removal encoding slice has landed. Lane 5 returned the next incoming-handler backlog: `QUESTION_DIALOG_ANSWER`, boundary commands, item command/use routes, and shop buy/sell/close before trade/duel/social. Lane 6's first bank hardening and shop payload/parser slices have landed; remaining economy widening should move next to shop dispatcher/inventory-coin movement or notes/certs/deposit-all behavior.
- The former intermittent `game::combat_event::tests::test_xp_awards_with_style` failure was fixed by making the test deterministic. Live combat-style packets now update `Player.combat_style`, echo `SEND_COMBAT_STYLE`, feed combat snapshots, and persist on logout.
