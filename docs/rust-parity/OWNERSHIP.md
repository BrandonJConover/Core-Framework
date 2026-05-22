# Rust Parity Lane Ownership

All parity work shares one branch. Each session must stay inside its lane unless the coordinator records an explicit handoff in `STATUS.md`.

## Global Rules

- Read `docs/rust-parity/STATUS.md` before editing.
- Do not revert unrelated dirty files.
- Keep changes small enough for one lane owner to review.
- Add or update tests before moving a row to `parity`.
- Record intentional Java divergences in `PARITY.md`.

## Lanes

| Lane | Owner Role | Primary Write Scope | Notes |
|---|---|---|---|
| 0 | Coordination and tracker | `docs/rust-parity/*` | Owns lane assignments, status, parity matrix, review order. |
| 1 | Protocol and golden harness | `server-rust/src/protocol/*`, `server-rust/tests/parity/*`, fixture docs | Owns Java-vs-Rust packet fixtures and opcode/framing parity checks. |
| 2 | Client playable loop | `server-rust/src/session/*`, `server-rust/src/network/*`, login/logout parts of `game/server.rs` | Owns real-client login, bootstrap, reconnect, logout smoke loop. |
| 3 | World data, collision, movement | `server-rust/src/game/world.rs`, `region.rs`, `walking.rs`, `pathfinding.rs` | Owns Java data loading, collision, region membership, walking. |
| 4 | Entity update pipeline | `server-rust/src/game/state_updater.rs`, entity update packet builders | Owns player/NPC/object/ground-item streaming and known-entity state. |
| 5 | Packet handler integration | Dispatch in `server-rust/src/game/server.rs` and thin handler adapters | Owns parity with Java `PayloadProcessorManager` bindings. |
| 6 | Core economy | `bank*`, `shop*`, `trade*`, `duel*`, ground-item economy flows | Owns bank/shop/trade/duel and economy logs. |
| 7 | Combat | `combat*`, `ranged.rs`, `magic.rs`, `prayer.rs`, `death.rs`, `poison.rs`, `wilderness.rs` | Owns combat rules, drops, death, skulls, aggression. |
| 8 | Skills and actions | `action.rs` and skill modules | Owns all skill action wiring and interruption semantics. |
| 9 | Compiled content plugin system | `server-rust/src/game/content.rs` and registry glue | Owns Rust trigger traits, registry, content context APIs. |
| 10 | Quests, dialogues, NPC content | `quest*`, `dialogue*`, compiled content modules | Owns Java plugin content batches. |
| 11 | Persistence, config, admin, ops | `database/*`, `infrastructure/*`, config/admin/logging surfaces | Owns DB/config/admin/metrics/load-test parity. |

## Conflict Policy

- If two lanes need the same file, the later lane must add a note to `STATUS.md` before editing.
- The coordinator resolves conflicts by preferring tested vertical slices over broad refactors.
- `game/server.rs` is shared; lane owners should add small adapter methods and avoid unrelated rewrites.
