# Plan: iOS — terrain textures (Phase 5, multi-iteration)

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. This is the longest single plan in the iOS backlog — call it 4-6 small focused commits, not one monster commit. Don't try to ship steps 1 and 4 as a single change.

## Goal

Replace the iOS terrain renderer's bbox-fill rasterizer with the already-ported `Shader.shadeScanline*` family, so terrain polygons that carry a texture index render with the actual texture from `Authentic_Sprites.orsc` (texture sprite range starts at `spriteTexture(3225)` per Java mudclient). After this lands, the iOS world stops looking like coloured Minecraft blocks and starts looking like the desktop client's textured terrain.

The original REMAINING.md entry assumed a separate `textures.orsc` archive. Survey confirms: Java loads textures from inside `Authentic_Sprites.orsc` at IDs `spriteTexture..+EntityHandler.textureCount()` using the `"texture"` package. So the texture data already ships in the bundle — the work is wiring it through to the rasterizer.

## Why this is multi-iteration

Four discrete pieces have to land in order, and rolling them up into one change makes debugging the inevitable colour-drift bug a nightmare:

1. **Texture sprite extraction** — pull the `spriteTexture..+textureCount` slice out of `Authentic_Sprites.orsc` into a 256-entry palette + indices form Scene's `loadTexture` already accepts.
2. **FloorDef → texture index** — the landscape mesh currently emits per-tile colours; it needs to also emit a texture index per face when the floor def has one.
3. **Scene fill switch** — when a polygon has a texture index ≥ 0, call into `Shader.shadeScanline*` instead of bbox-fill.
4. **Lighting + gradient sampling** — Java's textured terrain still applies per-vertex lighting; the scanline path expects pre-shaded gradient bands. Hook those up, otherwise textures show up flat-coloured at full brightness.

Steps 1+2 are read-only against the existing rasterizer; safe to ship and inspect. Steps 3+4 change pixels visibly and need a build-test loop after each one.

## Scope (files you may edit)

- `iOS_Client/OpenRSC/OpenRSC/Sources/Rendering/SpriteLoader.swift` — extend with a `textureSliceBuffer(forIndex:)` API that returns a flat `[Int32]` 64×64 (or 128×128) of pre-quantised texture pixels — the shape `Scene.loadTexture` already wants.
- `iOS_Client/OpenRSC/OpenRSC/Sources/Rendering/Scene.swift` — call site for `loadTexture` from boot; swap bbox-fill for `Shader.shadeScanline*` in the per-poly fill path. Don't touch projection / cull / depth-sort.
- `iOS_Client/OpenRSC/OpenRSC/Sources/Rendering/Shader.swift` — already ported, just becomes reachable.
- `iOS_Client/OpenRSC/OpenRSC/Sources/GameEngine/RSC/EntityDefinitions.swift` — confirm `FloorDef` exposes `textureIndex`; if not, parse it from the existing data the def comes from.
- `iOS_Client/OpenRSC/OpenRSC/Sources/Rendering/World.swift` — when emitting a quad, set `texFront = textureIndex` (or whatever rt4-style negative encoding `Scene` uses to mean "this is a texture, not a colour") instead of the flat colour.
- `iOS_Client/OpenRSC/REMAINING.md` — tick the deferred entry once all four steps land; append commit SHAs.

## Out of scope (do NOT touch)

- The iOS app target's avoid list (HUDView, MinimapPanel, …).
- The 530 web client (different texture pipeline; see `docs/plans/web-client-tier8-textures.md`).
- Animated textures (deferred — water shimmer, fire flicker).
- 3D model textures (different code path; `RSModel`'s `faceTextureFront` is already wired but currently unused).
- iOS sound system.

## Reference (Java mudclient + iOS port files)

| What | Source | Notes |
|---|---|---|
| Texture loading | `Client_Base/src/orsc/mudclient.java` lines 14449-14587 (`loadTextures`, `loadTexturesAuthentic`) | The reference for steps 1+2. Key insight: textures are read from the **sprite archive** at offset `spriteTexture(3225) + i`, and converted to a 256-entry palette + indices for the rasterizer. |
| Per-frame raster path | `Client_Base/src/orsc/graphics/three/Scene.java` `endScene()` | The Java equivalent of our iOS `Scene.endScene()`. Look for the call into one of the six `Shader.shadeScanline*` variants — that's where we have to plug in. |
| Scanline overloads (already ported) | `iOS_Client/OpenRSC/OpenRSC/Sources/Rendering/Shader.swift` | Six variants. Phase 5 wires up only the most common: `shadeScanlineOpaqueNormal` (most ground tiles) and `shadeScanlineTransparentNormal` (tiles with cutouts). Blend + Large variants come in a follow-up. |
| Texture metadata | `EntityHandler.textures` on the Java side — `getTexture(idx).type/dictionary` etc. | Some 530-derived ports load this from a JSON; for OpenRSC RSC data, derive from the sprite itself (Java mudclient line 14528-14586 builds the palette inline from the sprite pixels). |

## Implementation — step by step

### Step 1 — Extract textures into the Scene texture table

Mirror Java mudclient.java:14520-14587 verbatim. For each `i in 0 ..< EntityHandler.textureCount()`:

1. Look up the sprite at id `spriteTexture + i` from `Authentic_Sprites.orsc`.
2. Build a 256-entry palette histogram from the sprite's pixels (mudclient quantises by `((p & 0xf80000) >> 9) | ((p & 0xf800) >> 6) | ((p & 0xf8) >> 3)`).
3. Pack the most-common 256 colours into the palette table; remap the sprite into indexed bytes.
4. Call `scene.loadTexture(index: i, pixels: paletteARGB, type: typeFromSomething1, data: indexedBytes)`.

`Scene.loadTexture` already exists at line 675; just call it. The `type` arg controls 64×64 vs 128×128 — derive from `sprite.somethingWidth / 64 - 1` per Java line 14586.

**Acceptance for step 1**: `[Models]`-style boot log shows `[Textures] Loaded N textures from spriteTexture range (X..Y)`. No visible change yet — table populated, nothing reads it.

### Step 2 — FloorDef → texture index

`FloorDef` (whatever struct holds `groundOverlay`, `groundTexture`) needs to surface `textureIndex` to whoever builds landscape geometry. In `World.generateLandscapeModel`, when `tile.groundTexture > 0`, set the face's "texture or colour" attribute to encode the texture index instead of the flat colour. Java's encoding: pass a negative-int sentinel as `texFront`; `Scene` checks `if (texFront < -1 || texFront > 100000) treat as colour else treat as texture index`.

Confirm the iOS `Scene` keeps the same convention; if not, add a `model.faceTextureFront[i] = -1 - textureIndex` style encoding and update Scene's per-poly read to match.

**Acceptance for step 2**: With step 3 not yet shipped, terrain still renders bbox-fill (the encoding is set but nothing reads it). Verify by `print` that ~20% of tile faces in Lumbridge now report a non-trivial texture index.

### Step 3 — Scene fill switch

In `Scene.endScene()`, the per-poly fill loop currently does bbox fill. Add a branch: if the poly's texture index is ≥ 0, call `Shader.shadeScanlineOpaqueNormal(...)` (the most common variant). Otherwise keep the bbox path.

The `Shader.shadeScanline*` API needs:

- A pointer to the 64×64 texture pixels (look up via `scene.m_L[textureIndex]` — already loaded in step 1).
- A pointer to the framebuffer (already wired).
- The poly's three projected vertex coords + per-vertex u/v.

Per-vertex u/v is the tricky part: Java's terrain mesh emits u/v as `tileX & 0x7F`-style coords scaled to texture space. Mirror what `World.generateLandscapeModel` already implicitly does for the bbox path — read line 130-133 (the four `model.vertX/vertY/vertZ` writes) and add corresponding u/v.

**Acceptance for step 3**: Lumbridge ground tiles render with texture content (cobble, dirt, grass patterns) instead of flat colours. Lighting will look wrong (everything full bright) — that's step 4.

### Step 4 — Lighting + gradient sampling

Java pre-shades per-vertex via `applyLighting()` and feeds `Shader.shadeScanline*` a shaded gradient ramp (the variant suffix tells you which: `Opaque*` skips lighting, `Blend*` uses a 50% mix). For lit terrain we want `shadeScanlineOpaqueNormal` *with* per-vertex shading.

Implement: at landscape build time, fold the existing `LandscapeLoader.tileColor` brightness factor into the texture's palette by precomputing N (typically 8) brightness ramps of each 256-colour palette, and at raster time pick the ramp matching the polygon's average lighting. Mudclient does this in `loadTexturesAuthentic` line 14542+ (`dictionary[i*8+brightness] = scaled colour`).

**Acceptance for step 4**: Day/night appearance varies with elevation gradient; tile borders no longer look flat.

## Self-test (after each step)

```bash
cd /Users/brandonjconover/Documents/GitHub/Core-Framework/iOS_Client/OpenRSC \
  && xcodegen generate \
  && xcodebuild -project OpenRSC.xcodeproj -scheme OpenRSC \
       -configuration Debug \
       -destination 'id=00008130-000805D10AF0001C' \
       -derivedDataPath /tmp/openrsc-build-ralph build
```

`BUILD SUCCEEDED`. iPhone 15 Pro device: `Brick the 15th`, id `00008130-000805D10AF0001C`. After step 3, eyeball the terrain in Lumbridge: cobble, dirt, grass patches should be visible. After step 4, the elevation shading should be subtle but present.

## Acceptance criteria (full plan)

1. Step 1: boot log shows the texture-loading line; `Scene.m_L` non-empty for the loaded indices.
2. Step 2: World's landscape model encodes texture indices on tile faces that have `groundTexture > 0`.
3. Step 3: Lumbridge ground tiles render with visible texture patterns.
4. Step 4: Per-vertex lighting visibly modulates texture brightness with elevation.
5. Build green throughout.
6. iOS REMAINING.md "Terrain textures" entry ticked, with one-line summary of each step's commit SHA.

## Out of scope clarifications

- **Don't ship animated textures.** Water shimmer / fire flicker need a tick counter feeding into the texture sample — separate plan.
- **Don't refactor `Shader.swift`.** It's already ported; don't second-guess it.
- **Don't add a settings toggle for textures-on/off.** Once it works, leave it on.
- **Don't optimise palette quantisation.** Mudclient's algorithm is fine; matching it byte-for-byte is the goal.

## Commit guidance

Four commits, one per step:

1. `iOS: load terrain textures from sprite archive`
2. `iOS: encode texture index on landscape faces`
3. `iOS: switch terrain fill to scanline rasterizer`
4. `iOS: per-vertex lighting on textured terrain`

Push nothing.
