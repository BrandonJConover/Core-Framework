# Rust Parity Phase Tracker

Last updated: 2026-05-21

## Phase Count

The full parity roadmap has 5 phases total.

| Phase | Status | Purpose | Main Remaining Work |
|---|---|---|---|
| 1. Real-Client Playable Loop | active | Make Java-compatible clients log in and play a coherent small loop. | Real desktop client verification, bootstrap/UI packet gaps, wiring Java loc loader into runtime world, collision flags for first area, entity streaming proof, remaining bank/shop live adapter edges. |
| 2. Core Gameplay Parity | pending | Make core non-content gameplay work end-to-end. | Shop buy/sell/close dispatcher and inventory/coin movement, trade, duel, social, dialogue/menu, item-use, combat, prayer drain, death/respawn, high-value skills. |
| 3. World Data and Content Architecture | pending | Replace seeded data and stabilize compiled content APIs. | Full Java/OpenRSC data loaders, collision/path validation, live trigger dispatch into content registry, dialogue and quest runtime. |
| 4. Authentic Content Port | pending | Port Java gameplay content as compiled Rust modules. | Tutorial/beginner content, F2P quests/NPCs/shops, members content, minigames/custom OpenRSC mechanics, per-content regression tests. |
| 5. Persistence, Admin, Ops, Production Replacement | pending | Make Rust operationally able to replace Java. | Complete persistence, admin/staff tools, config parity, reports/logs, metrics/health checks, Discord hooks, migration and load tests. |

## Parallel Round Focus

Current round:

- Lane 3: Java world data/collision loader groundwork.
- Lane 4: entity update/ground-item streaming parity coverage.
- Lane 6: shop/core-economy packet adapter slice.
- Lane 9: compiled content trigger registry slice.
- Lane 0: coordination, tracker updates, integration, and test pass.

Completed this round:

- Lane 3 added a neutral Java loc JSON loader with real data count checks.
- Lane 4 changed in-grid ground-item removals to Java-style `item_id | 0x8000` encoding.
- Lane 6 added Java-style shop open payloads and shop buy/sell request parsing.
- Lane 9 added typed compiled-content trigger keys/events/registry helpers.
- Lane 0 verified the combined branch with `cargo fmt --all`, focused tests, and full `cargo test --quiet`.

## Phase Gate

Phase 1 can be marked complete only when a real Java-compatible client can:

- login through the Java desktop/custom RSA path,
- receive bootstrap/UI packets without client-visible breakage,
- see player/NPC/object/ground-item state in the test area,
- walk with collision,
- chat,
- pick up/drop items,
- bank through NPC/object commands,
- logout and reconnect with persisted position, inventory, bank, settings, and appearance.

Rust-driven TCP/WS smokes cover most of this today, but real-client GUI evidence and Java data-backed collision/entity streaming are still open.
