# Plan: 530 web client — Tier 5a zone-update opcodes

> **Hand-off note for ChatGPT.** Read this whole file first. Stop and ask if anything is ambiguous before writing code. Touch only the files in *Scope*; do **not** modify the *Out of scope* list. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`.

## Goal

Decode 13 `ServerProt` zone-update opcodes that the 2009scape rev-530 web client currently silently drops, so the scene stays in sync with server state after the initial `REBUILD_NORMAL`. After this lands, doors animating, items spawning/despawning, projectiles in flight, and spot animations will all reach the renderer instead of being thrown away.

## Why this is the next thing

`PacketHandler530.ts` covers 55/97 opcodes. The 13 listed below are everything the rt4-client routes through `Protocol.readZonePacket()` (line 125 of `reference/rt4-client/client/src/main/java/rt4/Protocol.java`) — the world-state update bus. Without them every animation, dropped item, locked door, and projectile after spawn-in is invisible.

## Scope (files you may edit)

- `2009scape-web/client-patch/osrs/PacketHandler530.ts` — add the 13 `case` branches.
- `2009scape-web/client-patch/osrs/Game.ts` — add the 4 typed lists described below if they don't already exist (`groundObjects`, `locAnims`, `projAnims`, `spotAnims`). Do not refactor existing fields.
- `2009scape-web/client-patch/osrs/cache/def/` — add `ObjStackNode.ts` if missing (a tiny value-only struct, see *Implementation*).
- `2009scape-web/client-patch/README.md` — flip the deferred bullet that says "outgoing interactions beyond walking" only if the README contains a Tier 5a checkbox (otherwise leave alone).

## Out of scope (do NOT touch)

- `Js5Cache.ts`, `Login530.ts`, `Buffer.ts`, `Configuration.ts`, `RawModel530.ts`, `Model.ts`, `Model530.ts`, `Scene.ts`.
- The renderer (`Game.drawGameView`, `Game.calculateCameraPosition`).
- iOS client (`iOS_Client/**`).
- The 2009scape Java server (`2009scape-web/2009scape/**`).

## Reference (rt4-client, authoritative)

Read each rt4 handler before porting; the byte order matters. All paths under `reference/rt4-client/client/src/main/java/rt4/`:

| Opcode | Name | rt4 file:line |
|---|---|---|
| 14 | `OBJ_COUNT` | `Protocol.java:236-255` |
| 16 | `MAP_PROJANIM_2` | `Protocol.java:273-298` |
| 17 | `SPOTANIM_SPECIFIC` | `Protocol.java:180-192` |
| 20 | `LOC_ANIM` | `Protocol.java:205-217` |
| 33 | `OBJ_REVEAL` | `Protocol.java:138-153` |
| 56 | `SPOTANIM_ENTITY` | `Protocol.java:1348+` (search for `SPOTANIM_ENTITY`) |
| 102 | `NPC_ANIM_SPECIFIC` | search `Protocol.java` for `NPC_ANIM_SPECIFIC` |
| 104 | `MAP_PROJANIM` | `Protocol.java:299+` |
| 121 | `MAP_PROJANIM_3` | `Protocol.java:154-179` |
| 135 | `OBJ_ADD` | `Protocol.java:256-272` |
| 179 | `LOC_ADD` | `Protocol.java:193-204` |
| 195 | `LOC_DEL` | `Protocol.java:127-137` |
| 202 | `LOC_ADD_CHANGE` | `Protocol.java:218-235` |
| 235 | `LOC_ANIM_SPECIFIC` | `Protocol.java:1926+` |
| 240 | `OBJ_DEL` | `Protocol.java:384+` |

`SceneGraph.currentChunkX/currentChunkZ` are set by `REBUILD_NORMAL`. Our equivalent fields on `Game` are `chunkX` and `chunkY` (see `PacketHandler530.handleRebuildNormal`).

The buffer helper names map 1:1: rt4 `g1` → our `g1`, rt4 `g1neg` → our `g1neg`, rt4 `g2add` → our `g2add`, etc. They're already defined as `static` methods on `PacketHandler530`. **Do not invent new helpers** — if rt4 uses `g1bsub` and we don't have it, port the helper as a 5-line `static` and add a code comment pointing back to the Java equivalent.

## Implementation

### 1. New world-state lists on `Game` (one-time)

If they don't already exist, add:

```ts
// In Game.ts, near the existing scene-state fields.
public groundObjects: ObjStack[][][] = [];   // [plane][x][z] → stack
public locAnims: { plane: number; x: number; z: number; anim: number; layer: number }[] = [];
public projAnims: ProjAnim[] = [];
public spotAnims: SpotAnim[] = [];
```

`ObjStack`, `ProjAnim`, and `SpotAnim` are tiny value structs — port them as plain TS classes with public fields matching rt4's `ObjStack.java`, `ProjAnim.java`, `SpotAnim.java`. Don't port the linked-list machinery; use plain arrays and let the renderer (later tier) iterate them.

### 2. The 13 `case` branches

For every opcode below, follow this pattern:

```ts
case 14: {  // OBJ_COUNT
    const local15 = this.g1(buf);
    const local19 = game.chunkY + (local15 & 0x7);
    const local23 = game.chunkX + ((local15 >> 4) & 0x7);
    const local27 = this.g2(buf);
    const local31 = this.g2(buf);
    const local39 = this.g2(buf);
    if (local23 < 0 || local19 < 0 || local23 >= 104 || local19 >= 104) break;
    const stack = game.groundObjects?.[game.plane]?.[local23]?.[local19];
    if (!stack) break;
    for (const obj of stack) {
        if ((local27 & 0x7FFF) === obj.type && local31 === obj.amount) {
            obj.amount = local39;
            break;
        }
    }
    return true;
}
```

Match rt4's variable names (`local15`, `local19`, `local23`, …) inside each block — they make code review against the Java reference effortless and aren't worth renaming.

For projectile/spotanim opcodes (16, 17, 56, 102, 104, 121), construct the corresponding object and push to the matching list. Do **not** try to render them — the renderer will pull from `game.projAnims` / `game.spotAnims` next tier.

For NPC anim 102, find the matching NPC in `game.npcs` (530-side list `Game.npcs530` or whatever the parallel agent's most recent rename calls it) by serverIndex and assign `npc.animation = local15` plus `npc.animationDelay = ...`. Do not invent fields not on the existing NpcType530 (if the field doesn't exist yet, *add it as `public animationOverride: number = -1`*).

### 3. Wire dispatch

`PacketHandler530.dispatch()` is the big switch. Add the new cases beside their existing siblings, ordered by group (loc, obj, projanim, spotanim, anim) for review-friendliness. Every case must `return true;` when it succeeds and fall through to the existing `default: if (size > 0) buf.currentPosition += size; return true;` only on bounds-rejection.

### 4. Buffer alignment guard

Each branch must consume *exactly* the bytes rt4 reads. After implementing, set `(globalThis as any).__zoneAuditDebug = true` and verify by running a Playwright session that the captured `[NPC] / [PLY]` log lines appear at the same offsets they did before this change. If you see "Parsed N packet(s), M remaining" with `M > 0` *only* on packets following a new opcode, your byte-read count is wrong.

### 5. Self-test before handing back

Run:

```bash
cd 2009scape-web
cp -R client-patch/osrs/. client/osrs/
./scripts/set-client-server.sh 10.8.0.1
cd client && rm -rf dist .cache && npm run build 2>&1 | tail -5
```

Build must finish without TS errors. There is no automated runtime test for this tier — the Hetzner server has to be running for that. **Do not deploy.** Just confirm `BUILD SUCCEEDED`-equivalent (last lines of `npm run build` show only the asset listing, no errors).

## Acceptance criteria

1. `PacketHandler530.dispatch` covers all 13 opcodes; the count of handled opcodes goes from 55 → 68.
2. `Game` exposes `groundObjects`, `locAnims`, `projAnims`, `spotAnims` (or kept their existing names if a parallel agent already added them — check git log first).
3. `npm run build` succeeds with zero TypeScript errors after `cp -R client-patch/osrs/. client/osrs/`.
4. No existing test or playwright script regresses (none currently target this code path, so step 3 is the bar).
5. Update `docs/web-client-plan.md`'s **Tier 5a** checklist: tick every item and append the commit SHA at the end of each line.

## Out of scope clarifications

- **Do not** start rendering the new state. That's Tier 6.
- **Do not** add audio for `SOUND_AREA` (97) or `SYNTH_SOUND` (172) — those are Tier 5d and need a sound bank port.
- **Do not** widen the dispatcher to handle the 32 still-missing opcodes outside this list. Future tiers will.
- **Do not** touch the 377 → 530 remap table; we're moving away from it. Each new branch is native 530.

## Commit guidance

One commit per group is fine; please prefix every commit message with `2009scape-web: tier5a — `. Example:

```
2009scape-web: tier5a — LOC_ADD/LOC_DEL/LOC_ADD_CHANGE zone updates
```

Push nothing.
