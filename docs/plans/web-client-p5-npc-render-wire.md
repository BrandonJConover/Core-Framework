# Plan: 530 web client — P5 NPC appearance → Scene render wire

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. **Pickup gate:** P4 player avatar wire must be visibly shipped — confirm by `[PlayerAvatar530] attached gender=N verts=M` in dev console. NPCs use a different lookup (NpcType530.modelIds[]) but the bridge plumbing is the same; getting players first means we can compare side-by-side when the NPC path produces wrong meshes.

## Goal

When a server NPC enters view (via `NPC_INFO`'s spawn or update mask), look up the NPC's `NpcType530.modelIds`, load each model via the existing `RawModel530.load` path, merge them into a composite, apply NpcType's recolor + retexture lists, bridge the result through `Model530Bridge`, and store on the `Npc` record's render slot. After this lands, every NPC in view shows its actual mesh instead of a placeholder.

This is the structural sibling of P4 — different lookup (NpcType530 instead of PlayerAppearance530's IdkType+ObjType combo), same bridge.

## Why now

P4 puts players on screen. P5 closes the matched-set: world geometry (P3b), terrain textures (P3c), local + remote players (P4), NPCs (P5). At that point the Scene paints the entire authoritative server state.

## Scope (files you may edit)

- `2009scape-web/client-patch/osrs/scene/NpcAppearance530.ts` — **new**: `composeNpcModel(npcType, rawModelLoader): Promise<RawModel530Data>` — port of rt4 `NpcType.getModel()` (search for `getModel` in `reference/rt4-client/.../NpcType.java`). Uses the existing `mergeRawModels` helper from `PlayerAppearance530.ts` (export it if it isn't exported yet — that's the only edit to the player-side file).
- `2009scape-web/client-patch/osrs/scene/NpcAttacher530.ts` — **new** thin glue (parallels `PlayerAvatarAttacher530`).
- `2009scape-web/client-patch/osrs/PacketHandler530.ts` — at the NPC_INFO spawn/transform branches, invoke the attacher with the NPC ref + the composed model. Don't refactor the existing per-NPC update masks.
- `2009scape-web/client-patch/osrs/scene/Scene.ts` — at the per-NPC draw site, prefer `npc.appearanceModel530` over the legacy renderable.

## Out of scope (do NOT touch)

- `PlayerAppearance530.ts` body — only export `mergeRawModels` if needed.
- BAS animation (Tier 9 / P6).
- NPC walking / movement — handled by `NPC_INFO`'s movement masks already.
- iOS port.

## Reference

| What | Source |
|---|---|
| `NpcType.getModel()` reference | `reference/rt4-client/client/src/main/java/rt4/NpcType.java` — search `getModel`. Returns the composed model with recolor/retexture applied. |
| `NpcType530` data shape | `2009scape-web/client-patch/osrs/cache/def/NpcType530.ts` (already ported). |
| `mergeRawModels` helper | `2009scape-web/client-patch/osrs/media/renderable/PlayerAppearance530.ts` — same merge function works for NPCs (vert/tri concat + index rebase). |
| Attacher pattern | [`web-client-p4-player-avatar-wire.md`](web-client-p4-player-avatar-wire.md) — copy the structure, swap player→npc + appearance lookup. |
| NPC_INFO call site | `PacketHandler530.ts` — search `NPC_INFO` / `handleNpcInfo`. The spawn-mask branch is where new NPCs need their model attached; the transform-mask branch (when a `morphIntoNpcId` change fires) needs a fresh attach with the new type id. |

## Implementation

### 1. `composeNpcModel`

```ts
import type { NpcType530Data } from '../cache/def/NpcType530';
import type { RawModel530Data } from '../cache/def/RawModel530';
import { mergeRawModels } from '../media/renderable/PlayerAppearance530';

export async function composeNpcModel(
    npcType: NpcType530Data,
    rawModelLoader: (id: number) => Promise<RawModel530Data | null>,
): Promise<RawModel530Data | null> {
    if (!npcType.modelIds || npcType.modelIds.length === 0) return null;
    const parts: RawModel530Data[] = [];
    for (const id of npcType.modelIds) {
        const m = await rawModelLoader(id);
        if (m) parts.push(m);
    }
    if (parts.length === 0) return null;
    const merged = mergeRawModels(parts);
    // Apply recolor (NpcType.recolor_s/d) — same shape as PlayerAppearance's
    // per-piece recolor pass. Walk the recolor src/dst arrays and replace
    // matching face colours in-place on `merged`.
    if (npcType.recolor_s && npcType.recolor_d) {
        applyRecolor(merged, npcType.recolor_s, npcType.recolor_d);
    }
    // Same shape for retexture if NpcType530 carries retex_s/d.
    if (npcType.retex_s && npcType.retex_d) {
        applyRetex(merged, npcType.retex_s, npcType.retex_d);
    }
    return merged;
}

function applyRecolor(m: RawModel530Data, src: number[], dst: number[]) {
    if (!m.faceColors) return;
    for (let i = 0; i < m.faceColors.length; i++) {
        const idx = src.indexOf(m.faceColors[i]);
        if (idx >= 0) m.faceColors[i] = dst[idx];
    }
}

function applyRetex(m: RawModel530Data, src: number[], dst: number[]) {
    if (!m.faceTextures) return;
    for (let i = 0; i < m.faceTextures.length; i++) {
        const idx = src.indexOf(m.faceTextures[i]);
        if (idx >= 0) m.faceTextures[i] = dst[idx];
    }
}
```

### 2. `NpcAttacher530`

```ts
import type { RawModel530Data } from '../cache/def/RawModel530';
import { Model530Bridge } from '../media/renderable/Model530Bridge';

export function attachNpcAppearance530(npc: any, mesh: RawModel530Data): void {
    if (!mesh || mesh.vertCount === 0) return;
    const bridged = Model530Bridge.attachModel(mesh);
    npc.appearanceModel530?.reset?.();
    npc.appearanceModel530 = bridged;
}
```

### 3. PacketHandler530 hook

In the `NPC_INFO` spawn-mask branch, after the NPC record is created with its `npcTypeId`, fire:

```ts
const npcType = NpcType530.cache.get(npc.npcTypeId);
if (npcType) {
    composeNpcModel(npcType, this.game.rawModelLoader).then(mesh => {
        if (mesh) attachNpcAppearance530(npc, mesh);
    });
}
```

In the transform branch (where `morphIntoNpcId` shifts the NPC's type), refresh the model the same way.

### 4. Scene draw-site precedence

Same one-liner as P4:

```ts
const renderable = npc.appearanceModel530 ?? npc.legacyRenderable;
```

## Verification gates

1. `cp` patch → client for the 4 modified files + 2 new files.
2. `cd 2009scape-web/client && npx tsc --noEmit` shows no new errors beyond the pre-existing pako warning.
3. Trace harness `2009scape-web/client-patch/.npc-appearance-test.mjs`:
   - hand-rolls 2 NpcType530Data fixtures (one with 1 modelId, one with 2 modelIds + a recolor src/dst pair)
   - hand-rolls per-id RawModel530Data fixtures (4 verts each; one with a face colour matching the recolor src)
   - inline-mirrors `composeNpcModel` (skipping the dynamic `import` — paste `mergeRawModels` source directly into the harness like `.player-appearance-test.mjs` does)
   - asserts: composite vert count = sum of input counts; recolor applied (face colour replaced)
   - hand-rolls a fixture `npc` + a fake `Model530Bridge.attachModel`; asserts `npc.appearanceModel530` non-null after attach; asserts a transform call replaces it and reset() ran exactly once
   - writes trace to `2009scape-web/client-patch/.npc-appearance-trace.txt` with `[NpcAppearance530] composed verts=N recolor-replaced=N attach+replace ok`
4. `node .npc-appearance-test.mjs` exits 0 with the marker line.

Optional Gate 5: live client shows NPCs with their proper meshes (e.g. cows look like cows, guards have armour silhouettes).

## Acceptance criteria

1. Gates 1-4 pass.
2. `[NpcAppearance530] attached typeId=N verts=M` log line fires when an NPC enters view (live).
3. `docs/web-client-plan.md` Renderer-wire section gains `- [x] P5: NpcAppearance530 wired into Scene` with commit SHA.
4. **Do not commit.**

## Out of scope clarifications

- **No animation.** NPCs T-pose until P6 ships.
- **No NPC chat / overhead text rendering.** That's a separate UI plan.
- **No optimisation of the model load.** Re-use the per-id load cache the player wire already uses; if it doesn't exist yet, *don't* add it — load N times, optimise after correctness.
- **No NPC death or removal animation.** Removal stays instant on `NPC_INFO`'s exit mask.

## Commit guidance

Two commits:

1. `2009scape-web: p5 — composeNpcModel + recolor/retex`
2. `2009scape-web: p5 — wire NpcAppearance into Scene per NPC_INFO`

Push nothing.
