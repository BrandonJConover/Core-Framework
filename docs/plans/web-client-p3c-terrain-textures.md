# Plan: 530 web client — P3c terrain texture pass

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. **Pickup gate:** P3b (TerrainMesh530 → Scene wire) must be visibly shipped first — confirm by `[Landscape530] attached planes 0..3` appearing in the dev console of the live client. If it isn't, stop and finish P3b first.

## Goal

Replace the flat per-triangle colours on the just-wired terrain mesh with the actual idx26 textures the FloType records reference. After this lands, Lumbridge ground reads as cobble + grass + dirt patches instead of solid coloured triangles.

This is the **structural sibling of Tier 8** ([web-client-tier8-textures.md](web-client-tier8-textures.md)) but scoped specifically to the terrain side. Tier 8 covers the full Texture/TextureOp pipeline; P3c is the targeted subset that lights up first.

## Why now

P3a + P3b deliver visible *coloured* terrain. The next visible win is texturing it. Doing it as a focused phase rather than waiting for the entire Tier 8 port lets us trade incrementally: ship a small texture provider that handles the ~10 most-referenced floor textures, then expand coverage.

## Scope (files you may edit)

- `2009scape-web/client-patch/osrs/scene/TerrainMesh530.ts` — extend the per-triangle output with `triangleTexture: Int32Array` (already in the type per P3a; this plan ensures it's *populated* from FloType530.texture). **Don't** change vertex/triangle layout.
- `2009scape-web/client-patch/osrs/scene/TerrainAdapter530.ts` (from P3b) — make sure the `floLookup` returns the texture id when present.
- `2009scape-web/client-patch/osrs/media/texture/TerrainTextureProvider.ts` — **new** thin texture cache: `getOrBuild(textureId): Uint32Array | null`. Backed by idx26 reads + a 6-op subset (color-fill, vertical-gradient, sprite, tiled-sprite, monochrome-fill, noise) — use the Tier 8 plan's order as the implementation order.
- `2009scape-web/client-patch/osrs/scene/Scene.ts` — at the per-poly fill site for the bridged landscape model, when the polygon has a non-negative `triangleTexture[i]`, swap the flat-colour fill for the textured fill via `TerrainTextureProvider.getOrBuild`.

## Out of scope (do NOT touch)

- Non-terrain textures (model textures on doors / trees / building roofs — separate plan after P5).
- Animated textures (water shimmer, fire flicker — wait for the per-frame texture-time hook).
- Lighting per vertex — terrain stays full-bright until lighting pass lands.
- Tier 8's full op coverage (29-subops, etc.) — only the 6 ops listed above.
- iOS port; iOS has its own Phase-5 plan (`docs/plans/ios-terrain-textures-phase5.md`).

## Reference

| What | Source |
|---|---|
| FloType.texture field | `reference/rt4-client/client/src/main/java/rt4/FloType.java` (texture id; -1 if absent). |
| Existing FloType530 | `2009scape-web/client-patch/osrs/cache/def/FloType530.ts`. |
| Texture decoder | `reference/rt4-client/client/src/main/java/rt4/Texture.java` + the 6 op subclasses. |
| Tier 8 implementation strategy | [`web-client-tier8-textures.md`](web-client-tier8-textures.md) — read first. |

## Implementation

### 1. Confirm `TerrainMesh530.ts` populates `triangleTexture`

The P3a port already has the field. Verify that for each triangle emitted, when `floLookup(id)?.texture` is non-null, write that id into `triangleTexture[triIdx]`. If it's already wired correctly (likely — P3a's research mentioned per-triangle texture), this step is a no-op — just confirm.

### 2. `TerrainTextureProvider.ts` (new)

```ts
import type { Js5Cache } from '../../Js5Cache';
import type { FloType530Data } from '../../cache/def/FloType530';

const TEXTURE_SIZE = 64;
const TEXTURE_PIXELS = TEXTURE_SIZE * TEXTURE_SIZE;

export class TerrainTextureProvider {
    private static cache = new Map<number, Uint32Array>();
    private static missing = new Set<number>();
    private static js5: Js5Cache | null = null;

    static attach(js5: Js5Cache) { this.js5 = js5; }

    /** Synchronous lookup; returns null on first call (and triggers async build).
     *  Caller should fall back to flat-colour fill until cache populates. */
    static getOrBuild(textureId: number): Uint32Array | null {
        if (textureId < 0) return null;
        if (this.cache.has(textureId)) return this.cache.get(textureId)!;
        if (this.missing.has(textureId)) return null;
        // Kick off async build; first frame still falls back to colour.
        this.tryBuild(textureId);
        return null;
    }

    private static async tryBuild(textureId: number): Promise<void> {
        if (!this.js5) { this.missing.add(textureId); return; }
        const raw = await this.js5.getGroupBytes(/* idx26 */ 26, textureId);
        if (!raw) { this.missing.add(textureId); return; }
        try {
            const pixels = this.runOpGraph(raw);
            this.cache.set(textureId, pixels);
        } catch (e) {
            this.missing.add(textureId);
        }
    }

    /** Run the texture's op graph against a 64x64 ARGB canvas. v1 supports
     *  ColorFill + VerticalGradient + Sprite + TiledSprite + MonochromeFill + Noise.
     *  Anything else logs once and falls back to dominant-colour fill. */
    private static runOpGraph(raw: Uint8Array): Uint32Array {
        // ... port the 6 ops listed above; mirror Tier 8 plan §1-3.
        // Out of v1 scope: ops 23-29, animated ops, op 29 sub-ops.
        const out = new Uint32Array(TEXTURE_PIXELS);
        // ... fill out
        return out;
    }
}
```

Don't gold-plate this. The 6 ops named cover the heavily-used floor textures; expand only when a specific FloType id fails.

### 3. Scene per-poly fill switch

Find the call site that fills bridged landscape polygons (added in P3b). When `triangleTexture[i] >= 0`:

```ts
const texPixels = TerrainTextureProvider.getOrBuild(triangleTexture[i]);
if (texPixels) {
    // Sample texPixels[u + v * 64] for each rasterized fragment.
    // Use whatever scanline path the bridge already exposes; do NOT
    // refactor the rasterizer.
} else {
    // Fall back to flat-colour fill (the P3b path).
}
```

If the rasterizer doesn't yet expose a textured-fill primitive, the plan widens — fall back to **dominant-colour** fill (one ARGB read per triangle from `texPixels[0]`). Wait until the rasterizer learns proper UV interpolation before shipping per-pixel sampling.

## Verification gates

1. `cp` patch → client for the 3 modified files + 1 new file.
2. `cd 2009scape-web/client && npx tsc --noEmit` shows no new errors beyond the pre-existing pako warning.
3. Trace harness `2009scape-web/client-patch/.terrain-textures-test.mjs`:
   - Hand-rolls a fixture FloType530 record with `texture: 5`, ColorFill → solid red 0xFFFF0000.
   - Inline-mirrors `TerrainTextureProvider.runOpGraph` against the fixture op bytes; asserts the returned `Uint32Array` is 4096 entries long and every entry equals 0xFFFF0000.
   - Re-runs against a VerticalGradient fixture; asserts top-row vs bottom-row entries differ.
   - Writes the trace to `2009scape-web/client-patch/.terrain-textures-trace.txt` with `[TerrainTextureProvider] colorFill+vGradient ok pixels=4096+4096`.
4. `node 2009scape-web/client-patch/.terrain-textures-test.mjs` exits 0 with the marker line.

Optional Gate 5 (browser): live client shows non-uniform terrain colour patterns. **Don't** require if server isn't reachable.

## Acceptance criteria

1. Gates 1-4 pass.
2. Live client (when reachable) shows ground patches that read as patterns, not flat colour.
3. `docs/web-client-plan.md` Tier 6 / Renderer plan section gains `- [x] P3c: terrain texture provider (6 ops)` with commit SHA.
4. **Do not commit.**

## Out of scope clarifications

- **No texture rotation / scale per polygon.** UV is straight `(tileU, tileV)`.
- **No depth blending.** Terrain stays opaque.
- **No animated textures.** Static only.
- **No lighting interaction.** Texture pixel = output pixel.
- **Don't widen op coverage past 6 in this plan.** Op-creep is its own follow-up.

## Commit guidance

`2009scape-web: p3c — terrain textures (6-op provider)`. Push nothing.
