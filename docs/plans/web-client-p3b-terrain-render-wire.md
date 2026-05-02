# Plan: 530 web client — P3b TerrainMesh530 → Scene render wire

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. P3a (`TerrainMesh530.ts` data-side build) shipped offline-verified — see `2009scape-web/client-patch/.terrain-mesh-trace.txt`. This plan wires that builder's output into the live Scene render path so the terrain mesh actually appears on screen.

## Goal

Make `TerrainMesh530.buildTerrainMesh()` run on every `REBUILD_NORMAL` (and on initial scene boot), feed the resulting `RawModel530Data` through the existing `Model530Bridge` into the legacy `Scene` model array, and confirm the terrain renders as a textured/coloured surface in the live browser. After this lands, "viewport black after world loads" should narrow to a strict subset (texture / lighting / camera) — terrain geometry is no longer the blocker.

## Why now

P3a ships pure data math. The renderer currently still uses whatever the 377 path produced (or nothing — the Tier 6a probe will tell us when it lands). Wiring P3a is the smallest unit of work that visibly closes the loop "we have heightmap data → triangles end up on screen".

## Scope (files you may edit)

- `2009scape-web/client-patch/osrs/scene/Scene.ts` — add `attachLandscape530(rawMesh: RawModel530Data, plane: number)` that bridges the raw mesh through `Model530Bridge` and stores it in the existing landscape-model slot. **Do not** refactor existing `addTile()` / `addEntity()` / `addRenderable()` paths.
- `2009scape-web/client-patch/osrs/Game.ts` — call site: after `REBUILD_NORMAL` finishes populating `anIntArrayArrayArray891` (heights) + `currentSceneTileFlags` (floor ids), iterate planes 0..3, build the mesh per plane, and hand each to `attachLandscape530`. One-shot guard `__landscape530Wired` so we don't rebuild every frame.
- `2009scape-web/client-patch/osrs/scene/TerrainAdapter530.ts` — **new** thin glue file: extracts the heights + floor-id grids out of `Game`'s 3-D arrays into the `TerrainTileSource` shape `buildTerrainMesh` expects, plus a `floLookup(id)` closure backed by the existing `FloType530` cache.

## Out of scope (do NOT touch)

- `TerrainMesh530.ts` — frozen by P3a's offline gates. Don't change the builder.
- `Model.ts`, `Model530.ts`, `Model530Animator.ts`, `Model530Bridge.ts` — the bridge layer is its own contract.
- `PlayerAppearance530.ts`, `PacketHandler530.ts` — separate phases.
- Texture wiring — leave untextured terrain visible; texture pass is the explicit next phase (P3c) once we can see anything.
- iOS port.

## Reference

| What | Source |
|---|---|
| `TerrainMesh530.buildTerrainMesh` shape | `2009scape-web/client-patch/osrs/scene/TerrainMesh530.ts` (the file P3a shipped). |
| `Model530Bridge` interface (what it expects in, what it returns) | `2009scape-web/client-patch/osrs/media/renderable/Model530Bridge.ts`. Read the `attach`/`bridge` method signatures end-to-end before writing the adapter. |
| Scene's existing model slots | `Scene.ts` ~line 423 (`addModel` closure inside the legacy per-tile loop) — we **don't** call this; we call a new `attachLandscape530` we add at the same level. |
| Heights array layout | `Game.ts:202` `anIntArrayArrayArray891: number[][][]` (4 planes × 105 × 105). |
| Floor flags array | `Game.ts:201` `currentSceneTileFlags: number[][][]` (4 planes × 104 × 104). |
| Indexing convention | `[plane][x][z]` — confirmed by P3a's research agent. |

## Implementation

### 1. `TerrainAdapter530.ts` (new)

Pure glue. Reads from `Game`'s 3D arrays, writes to a flat `TerrainTileSource`:

```ts
import { TerrainTileSource, TerrainMeshBuildOptions, buildTerrainMesh } from './TerrainMesh530';
import type { FloType530Data } from '../cache/def/FloType530';
import type { RawModel530Data } from '../cache/def/RawModel530';

export function tileSourceForPlane(game: any, plane: number): TerrainTileSource {
    // Game.anIntArrayArrayArray891 is [plane][x][z], 105×105 per plane.
    // Game.currentSceneTileFlags is [plane][x][z], 104×104 per plane.
    // For floor ids we fall back on game.floorOverlayIds / floorUnderlayIds /
    // tilePlanes if they exist; otherwise derive from currentSceneTileFlags
    // (the flag byte's low bits encode the underlay id, and the top bits the
    // overlay id — verify via Region.ts decode path before relying on this).
    const sizeX = 104;
    const sizeZ = 104;
    const heights = new Array(sizeX * sizeZ);
    const floorOverlays = new Array(sizeX * sizeZ);
    const floorUnderlays = new Array(sizeX * sizeZ);
    const tilePlane = new Array(sizeX * sizeZ).fill(plane);

    const heightsSrc = game.anIntArrayArrayArray891;
    const overlaysSrc = game.floorOverlayIds ?? game.currentSceneTileFlags;
    const underlaysSrc = game.floorUnderlayIds ?? game.currentSceneTileFlags;

    for (let z = 0; z < sizeZ; z++) {
        for (let x = 0; x < sizeX; x++) {
            const idx = z * sizeX + x;
            heights[idx] = heightsSrc?.[plane]?.[x]?.[z] ?? 0;
            floorOverlays[idx] = overlaysSrc?.[plane]?.[x]?.[z] ?? -1;
            floorUnderlays[idx] = underlaysSrc?.[plane]?.[x]?.[z] ?? -1;
        }
    }
    return { sizeX, sizeZ, heights, floorOverlays, floorUnderlays, tilePlane, planeFilter: plane };
}

export function floLookupFor(game: any): (id: number) => FloType530Data | null {
    return (id: number) => {
        if (id < 0) return null;
        return game.floTypeCache?.get(id) ?? null;
    };
}

export function buildLandscape530(game: any, plane: number, opts?: TerrainMeshBuildOptions): RawModel530Data {
    return buildTerrainMesh(tileSourceForPlane(game, plane), floLookupFor(game), opts);
}
```

**Important:** before relying on `game.floorOverlayIds` / `floorUnderlayIds`, *verify they exist*. If they don't (likely — only `currentSceneTileFlags` was confirmed), grep for the REBUILD_NORMAL handler in `PacketHandler530.ts` and find where the byte that carries overlay/underlay ids gets stashed. The **adapter is the right place** to stash a parallel pair of 3D arrays during decode if they don't exist; do not pollute `Game.ts`'s field list.

### 2. `Scene.ts` — add `attachLandscape530`

```ts
// Add as a sibling method to the existing addModel closure pattern.
public attachLandscape530(rawMesh: RawModel530Data, plane: number): void {
    if (!rawMesh || rawMesh.vertCount === 0) return;
    const bridged = Model530Bridge.attachModel(rawMesh);   // exact API: confirm name from Model530Bridge.ts
    // Slot the bridged model into the same per-plane landscape slot the
    // 377 path uses. If a per-plane field doesn't exist yet, add a small
    // landscape530[plane] array on Scene; never overwrite a non-null
    // existing slot without first calling .reset() on the prior model.
    if (!this.landscape530) this.landscape530 = [null, null, null, null];
    this.landscape530[plane]?.reset?.();
    this.landscape530[plane] = bridged;
}
```

The call site that draws each frame should iterate `this.landscape530` and call the bridge's `renderAtPoint` (or whatever the existing 377 landscape model uses) before per-tile entities.

### 3. `Game.ts` — call site

Find the function that finishes processing `REBUILD_NORMAL` (search for where heights + tile flags both get populated and a final "scene ready" flag flips). Add at the tail:

```ts
if (!(this as any).__landscape530Wired) {
    (this as any).__landscape530Wired = true;
    for (let plane = 0; plane < 4; plane++) {
        const mesh = buildLandscape530(this, plane);
        if (mesh.vertCount > 0) {
            this.currentScene.attachLandscape530(mesh, plane);
        }
    }
    console.log('[Landscape530] attached planes 0..3');
}
```

The one-shot guard prevents per-frame rebuilds. Tier 5a's zone-update opcodes (already shipped) don't change tile heights — they touch locs / objs — so a per-REBUILD_NORMAL build is sufficient. **Re-run the build path** when a new `REBUILD_NORMAL` arrives by clearing `__landscape530Wired = false` from the REBUILD_NORMAL handler entry.

### 4. Quick smoke

After implementation, build + serve + open in browser. Look in the dev console for `[Landscape530] attached planes 0..3` exactly once. Expect to see: terrain still potentially black-shaded (no textures), but the screen should show *coloured triangles* roughly tracking the height contour where before it was uniform black/grey.

If the screen is still black, fall to the Tier 6a renderer probe (already landed at commit `1a113b1b3` per `docs/web-client-plan.md`) and use its output to drive the Tier 6b template. Don't blind-fix.

## Verification gates

These mirror P3a's structure since this is the runtime counterpart:

1. `cp 2009scape-web/client-patch/osrs/scene/TerrainAdapter530.ts 2009scape-web/client/osrs/scene/TerrainAdapter530.ts` and the same for `Scene.ts`, `Game.ts`.
2. `cd 2009scape-web/client && npx tsc --noEmit` shows no new errors beyond the pre-existing pako warning.
3. Build a Node ESM trace harness at `2009scape-web/client-patch/.terrain-render-wire-test.mjs` that:
    - hand-rolls a fixture `game` shape with `anIntArrayArrayArray891` (4×105×105 with a sloped fixture heightmap) + `currentSceneTileFlags` (4×104×104 carrying valid floor ids) + a `floTypeCache` map of two FloType ids.
    - calls `buildLandscape530(game, 0)` and asserts the returned mesh has `vertCount > 0` and `triCount > 0`.
    - calls `attachLandscape530` on a stubbed `Scene` (fake `Model530Bridge.attachModel` returning a passthrough) and confirms `scene.landscape530[0]` is non-null.
    - writes the trace to `2009scape-web/client-patch/.terrain-render-wire-trace.txt` with line `[TerrainAdapter530] attached plane=0 verts=N tris=N`.
4. `node 2009scape-web/client-patch/.terrain-render-wire-test.mjs` exits 0 with the trace marker line present.

Optional Gate 5 (browser): if the local Hetzner stack is reachable, follow the standard build → serve → playwright workflow from `client-patch/README.md` and confirm the dev console emits `[Landscape530] attached planes 0..3` exactly once. **Don't** require this gate if the server isn't reachable; offline gates 1-4 are the bar.

## Acceptance criteria

1. Gates 1-4 pass.
2. `[Landscape530] attached planes 0..3` line appears in the dev console exactly once per REBUILD_NORMAL when run against a live server.
3. `docs/web-client-plan.md` "Renderer plan (Tier 6)" gets a new `- [x] P3b: TerrainMesh530 wired into Scene` checkbox under section 1, with the implementing commit SHA.
4. **Do not commit.** Stop hook's standing rule.

## Out of scope clarifications

- **No texture wiring.** Untextured triangles are progress; textures land in P3c (sister of Tier 8).
- **No animation / skinning.** Static terrain only.
- **Don't refactor `Scene.addModel`** — wire `attachLandscape530` as a parallel method.
- **Don't make the wire mandatory** — gate the new path so a regression bails to the old 377 landscape until the wire is proven.

## Commit guidance

`2009scape-web: p3b — wire TerrainMesh530 into Scene per plane`. Push nothing.
