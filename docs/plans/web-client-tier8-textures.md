# Plan: 530 web client — Tier 8 textures (idx26 + TextureOps)

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. This is the heaviest tier — expect 1–2 days of work even on a fast model. Strictly read-and-port the rt4 reference; don't get creative.

## Goal

Stand up enough of the rt4 texture pipeline to feed real textured terrain + textured 3D models to `Scene`. After this lands, ground tiles stop being flat-shaded coloured lozenges; doors, walls, building roofs render with the actual textures the cache ships.

The pipeline has two halves:

1. **Texture definition decoder** — parse idx26 group bodies into a `Texture` struct (referenced texture indices, material params, tiling rules).
2. **TextureOp pipeline executor** — run the per-texture op graph (rt4 `TextureOp1..38`) against a procedural-noise + sprite blender to produce the final ARGB pixels.

The Java source has 30+ `TextureOp` subclasses. Most 530 textures only reference a small subset; we'll port the minimum referenced by an actual 530 cache and stub the rest.

## Why this is last

Until Tiers 5–7 are in:

- We have nothing to draw.
- The interface system is skeletal.
- The rasterizer is unverified (Tier 6a probe).

Adding textures earlier means colour-shading bugs that look identical to camera bugs, and we waste hours bisecting which side is broken.

## Scope (files you may edit)

- `2009scape-web/client-patch/osrs/cache/def/Texture.ts` — new file.
- `2009scape-web/client-patch/osrs/media/texture/TextureOp.ts` — new abstract base.
- `2009scape-web/client-patch/osrs/media/texture/TextureOp*.ts` — new concrete ops; one file per supported op id.
- `2009scape-web/client-patch/osrs/media/texture/TextureProvider.ts` — new file: idx26 → Texture, plus the per-texture cache + raster helper.
- `2009scape-web/client-patch/osrs/Scene.ts` — wire the texture provider in for the rasterizer's `getTexturePixel(textureId, u, v)` callback. Do **not** change projection/cull math.
- `2009scape-web/client-patch/osrs/Game.ts` — load the texture index on boot.
- `2009scape-web/client-patch/README.md` — flip the deferred bullet on textures.

## Out of scope (do NOT touch)

- Camera/projection/lighting math.
- Widget renderer.
- BAS skeletons.
- Audio.

## Reference (rt4-client)

| File | Why |
|---|---|
| `Texture.java` | Decoded shape: list of op refs + per-op params. |
| `TextureOp.java` | Abstract op. Subclasses each contribute pixels into a 64×64 (or 128×128) ARGB buffer. |
| `TextureOp4`, `5`, `11`, `12`, `14`, `15`, `16`, `17`, `19`, `23`, `25` | First-pass minimum set — these cover most ground-tile textures. |
| `TextureOpSprite`, `TextureOpTexture`, `TextureOpTile`, `TextureOpTiledSprite` | Sprite-based ops; need idx8 sprite read. |
| `TextureOpNoise`, `TextureOpHorizontalGradient`, `TextureOpVerticalGradient` | Procedural ops; pure math. |
| `Js5GlTextureProvider.java` | The reference texture-streaming class; **don't** port the GL parts, just the cache logic. |

## Implementation strategy

### Step 1 — Decode without executing

`Texture.decode(buf)` parses an idx26 entry into a struct:

```ts
export class Texture {
    public id: number = 0;
    public ops: { opId: number; params: Uint8Array }[] = [];
    public referencedSpriteIds: number[] = [];
    public referencedTextureIds: number[] = [];
    // ... port remaining metadata fields from Texture.java
}
```

At this stage, every texture in idx26 should `decode()` without throwing — but we don't generate any pixels yet. Acceptance gate: walk every idx26 group and confirm `decode()` returns successfully.

### Step 2 — Stub op executor

Implement `TextureOp.run(canvas64, ctx)` as an abstract method. Implement *only* `TextureOpColorFill` (a single solid-colour op) end-to-end. Make `TextureProvider.getOrBuild(textureId)` return a `64x64 Uint32Array` filled with whatever `decode()` says is the dominant solid colour for unimplemented ops.

This produces flat-coloured textures that match the colour distribution of the real ones — a step better than the white quads we have today, and lets the rasterizer test path land before we sweat over the procedural noise generator.

### Step 3 — Add op coverage

Implement, in this order, the rt4 ops referenced by 530 ground-tile textures (most heavily used):

1. `TextureOpHorizontalGradient` / `TextureOpVerticalGradient` (pure math)
2. `TextureOpNoise` (port `randomGenerator()` from rt4 — it's a deterministic LCG)
3. `TextureOpMonochrome` / `TextureOpMonochromeFill`
4. `TextureOpInvert` / `TextureOpFlip` (trivial)
5. `TextureOpClamp` / `TextureOpRange`
6. `TextureOpInterpolate` / `TextureOpCombine` (combinators — multi-input)
7. `TextureOpSprite` / `TextureOpTiledSprite` (need idx8 sprite read; lean on existing `SpriteLoader530.ts`)
8. `TextureOpColorGradient` / `TextureOpCurve`

After each batch of 2–3 ops, rebuild + visual-check the on-screen tile colours. Don't try to ship them all at once.

### Step 4 — Wire into rasterizer

Find the rasterizer's "what colour should this pixel be?" call site (search `Scene.ts` or whatever the per-poly raster path is named in our patches). When the polygon has a texture index, replace the flat-colour read with `TextureProvider.getOrBuild(textureId)[v * 64 + u]`. The (u, v) interpolation per scanline must match rt4's affine path; if our raster does perspective-correct, port that too — but don't introduce it as a new code path here.

### Step 5 — Lazy build cache

`TextureProvider.getOrBuild(textureId)`:

- If we already built this id, return the cached 64×64 ARGB buffer.
- Otherwise, run the texture's op graph against a fresh 64×64 canvas, cache it, return.
- Invalidate nothing — textures are immutable.

**Performance budget:** building a single texture should be ≤2ms on a desktop browser. If it takes longer, log a `[Texture] slow build for id=N: Tms` and review which op is the bottleneck. We don't need to optimise yet, just track.

## Self-test

```bash
cd 2009scape-web
cp -R client-patch/osrs/. client/osrs/
./scripts/set-client-server.sh 10.8.0.1
cd client && rm -rf dist .cache && npm run build 2>&1 | tail -5
```

Walk Lumbridge in a Playwright session. Capture a screenshot on first frame after world ready. Compare to a reference rt4-client screenshot from the same coords (we don't have a baseline; just eyeball that the green-grass / brown-stone / blue-water bands look right rather than uniform).

## Acceptance criteria

1. Every idx26 entry decodes without throwing.
2. `TextureProvider.getOrBuild(textureId)` returns a non-empty buffer for the most-referenced 50 texture ids.
3. Lumbridge ground tiles visibly display textures (not flat colours) when running locally against the Hetzner server.
4. Build is green.
5. Frame budget: cold-start (first 100 textures) ≤ 200ms total; per-texture cache hit free.
6. `docs/web-client-plan.md` Tier 8 checklist ticked with commit SHAs.

## Out of scope clarifications

- **No GL.** This is a software texture pipeline, no `WebGL` calls. The existing rasterizer is software-only.
- **No animated textures.** Ops 27–35 (animation/scrolling) — stub them to return their static reference. We'll come back if a 530 cache references one.
- **Don't refactor the rasterizer.** Wire texture lookup as the smallest possible change.
- **Don't port `TextureOp29SubOp*`.** Those are for op 29 (combined complex ops); leave op 29 as a no-op for this tier.

## Commit guidance

Multiple commits — one per natural batch:

1. `2009scape-web: tier8 — Texture decoder + ColorFill op`
2. `2009scape-web: tier8 — gradient + noise + monochrome ops`
3. `2009scape-web: tier8 — sprite + combine ops`
4. `2009scape-web: tier8 — wire TextureProvider into Scene rasterizer`

Push nothing.
