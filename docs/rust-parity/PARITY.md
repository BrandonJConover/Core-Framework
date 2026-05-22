# Rust Server Java-Parity Tracker

Last audited: 2026-05-16

Status values: `missing`, `stub`, `partial`, `parity`, `intentionally diverged`.

## Summary

| Subsystem | Status | Evidence |
|---|---|---|
| Protocol opcode names | parity | Rust `OpcodeIn`/`OpcodeOut` mirrors Java enum names. |
| Legacy opcode byte tables | partial | Rust has v38/v69/v115/v177/v201/v203/v235 tables; live dispatch still defaults to v177. |
| Packet golden harness | partial | Initial Rust parity tests and shared fixture directory exist; Java-generated fixture producer still needs to be added. |
| Client playable loop | partial | Login, initial packets, movement, chat, item pickup/drop, logout exist in Rust; real-client smoke evidence is not yet captured. |
| Java incoming handler coverage | partial | Rust live dispatch handles a small subset of Java `PayloadProcessorManager` bindings. |
| World data loading | stub | Rust currently seeds test NPCs/objects/items near Lumbridge instead of loading Java world data. |
| Entity update pipeline | partial | Rust has entity streaming and tests, but needs Java packet fixture coverage. |
| Core economy | partial | Rust has bank/shop/trade/duel modules with tests; live packet wiring is incomplete. |
| Combat | partial | Basic melee combat exists; ranged, magic, prayer, death/drop/skull parity incomplete. |
| Skills and actions | partial | Skill modules have unit tests; live interaction wiring incomplete. |
| Compiled content plugin system | partial | Initial Rust trigger/registry scaffold exists; Java plugins are not ported. |
| Quests/dialogues/NPC content | partial | Rust quest/dialogue engines exist; authentic Java plugin content is not ported. |
| Persistence/config/admin/ops | partial | DB-backed login/save exists; full Java schema/config/admin/log parity incomplete. |

## Milestone 1: Playable Loop Checklist

| Feature | Status | Required Evidence |
|---|---|---|
| Login and bootstrap | partial | Golden login/bootstrap packet fixture plus real-client smoke. |
| Logout and reconnect | partial | Persistence round trip and Java-client reconnect smoke. |
| Movement | partial | Collision-backed walking test and real-client movement smoke. |
| Chat | partial | Public chat packet fixture and proximity broadcast test. |
| Entity visibility | partial | Player/NPC/object/ground item golden update fixtures. |
| Inventory pickup/drop | partial | Packet fixture plus world/inventory mutation test. |

## Java Oracles

- Incoming handler bindings: `server-java-modern/src/com/openrsc/server/net/rsc/PayloadProcessorManager.java`
- Outgoing packet layouts: `server-java-modern/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java`
- Legacy fallback/reference: `server/`

## Lane 5 Incoming Handler Backlog

Already live in Rust: heartbeat/blink, walk, logout, command, public chat, private message, NPC/player attack, appearance change, ground item take, item drop, inventory equip/unequip.

Best next wiring groups:

| Group | Status | Rust Owner |
|---|---|---|
| Bank opcodes | partial | `bank_handler.rs` plus thin `game/server.rs` adapters |
| Trade opcodes | partial | `trade_handler.rs` plus session lookup adapters |
| Shop opcodes | partial | `shop_handler.rs` plus packet parsing adapters |
| Dialogue/menu opcodes | stub | Replace NPC greeting stub with `dialogue_handler.rs` dispatch |
| Item-use opcodes | partial | `item_use.rs` context resolution and adapters |
| Magic/prayer/duel/social/sleep | partial | Domain modules exist; live packet dispatch incomplete |
| Object/boundary/NPC command/follow/settings/report/security/tutorial/debug | missing | Needs domain behavior or explicit intentional divergence |

## Definition of Parity

A row can move to `parity` only when:
- Rust behavior is wired into the live server path.
- Unit or integration tests cover the Rust behavior.
- Golden fixtures or client smoke tests cover Java-compatible wire behavior where packets are involved.
- Any intentional Java divergence is documented here with a reason.
