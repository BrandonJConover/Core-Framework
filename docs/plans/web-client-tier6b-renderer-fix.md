# Plan: 530 web client — Tier 6b renderer fix (template, conditioned on 6a probe output)

> **Hand-off note for ChatGPT.** Read this whole file first. **Do not start writing code yet.** This plan is a *template*: it stays in this state until the Tier 6a probe lands and produces real diagnostic output. Once that output is captured (per Tier 6a's acceptance criterion #5), the planner fills the "What the probe showed" section and ChatGPT can implement against it.

## Goal (when filled in)

Fix whichever specific renderer gate the Tier 6a probe identifies as the cause of "screen still black/flat after world loads". The five gates are mutually exclusive — exactly one of these should be the answer:

1. **Camera position bug** — post-rotate vertex Z extents put everything behind the near plane.
2. **Frustum cull bug** — visible-poly screen extents fall outside `[0..w] × [0..h]` (the iOS-style "Polygon shared instance" pattern, just adapted to TS).
3. **Triangle clip / raster bug** — `visible > 0` but `drawn == 0`.
4. **Lighting / colour bug** — geometry rasterises but every pixel is black/clamped.
5. **`Model530` flag-bridge bug** — geometry never enters the cull pipeline because `model.m_dc` (or its 530 equivalent) is false.

Until Tier 6a's first console capture is appended below, this plan is intentionally inert — implementing any of the five fixes blind would burn iteration cycles and risk masking the real bug under a wrong fix.

## Why this template exists

Most of our planned tiers are independent enough that ChatGPT can pick them up cold. Tier 6 is different — it's a diagnose-then-fix step where the diagnostic data dictates the fix. Writing this plan in advance gives the implementer a head start: they can read the five candidate failure modes before the probe runs, and the fix becomes "match the probe output to the matching section" rather than "wing it from a console paste".

## Scope (when filled in)

Limited to the renderer / projection chain. Once a specific gate is named, scope shrinks to the subset of files relevant to that gate:

- Camera position bug → `Game.calculateCameraPosition`, `Scene.setCamera`-equivalent.
- Frustum cull bug → `Scene.endScene` cull predicate or polygon storage.
- Triangle clip / raster bug → `Rasterizer3D` (or wherever the per-poly fill lives).
- Lighting bug → `applyLighting` + `Model530` flag bridge.
- `m_dc` flag bug → `Model530.bridgeFromRawModel` (or the bridge constructor).

## Out of scope (always)

- Texture pipeline (Tier 8).
- Animations (Tier 9).
- Server protocol.
- Anything not in the gate's specific file list above.

## What the probe showed (to fill in after Tier 6a runs)

> **Implementer instructions for the planner who fills this in:**
>
> 1. Run the Tier 6a probe per its self-test block (build, `set-client-server.sh`, serve, Playwright walk-test).
> 2. Find the `[Probe] renderer state` console group in the captured output.
> 3. Paste the full group below verbatim.
> 4. Fill in **the matching gate** subsection at the bottom of this doc (delete the others).
> 5. Bump the doc's status from `template` to `ready` and re-export to ChatGPT.

```
[Probe] renderer state
…[paste captured output here]…
```

**Probe interpretation cheat sheet:**

| Probe field | Healthy value | Red flag |
|---|---|---|
| `models=N` | ≥ 1 (terrain) + game objects (~20-100) | 0 → world hasn't loaded; not a renderer bug, fix Tier 5 first. |
| `worldspace bounds: x=[..]..` | spans roughly 13312 units (104×128) | wildly bigger or near-zero → mesh emit bug, *Tier 4 regression*. |
| `camera: pos=…` | `pos` non-zero, `pitch` ~50° | `pos=(0,0,0)` w/ pitch 0 → camera never moved past origin. **Gate 1.** |
| `post-rotate: z=[..]` | mostly positive (in front of camera) | mostly negative → wrong-sign pos. **Gate 1.** |
| `triangles total=T zCulled=a screenCulled=b visible=v drawn=d` | `v > 0`, `d ≈ v` | `v == 0` everywhere → frustum kills all. **Gate 2.** |
|  |  | `v > 0`, `d == 0` → raster drops them. **Gate 3.** |
| `visible-poly screen range: x=[gMinX..gMaxX]` | inside `[0..512]` | `gMinX > 512` → all visible polys off-screen right. **Gate 2 — iOS-pattern bug.** |
| First-frame pixels | non-black | all `0xFF000000` despite drawn>0 → lighting clamps. **Gate 4.** |

## Gate 1 — Camera position bug (template)

If the probe shows `pos` near-origin or `post-rotate Z extents` mostly negative:

**File:** `2009scape-web/client-patch/osrs/Game.ts` `calculateCameraPosition()` (and any sister `setCameraPosition` helpers).

**Most likely cause** (port-pattern): the camera offset is computed from the local-player chunk position but never adds `worldOffsetX/Z` (the `REBUILD_NORMAL` base coords). Result: camera sits at world origin while the mesh is at `(2519*128, 0, 2507*128)` style absolute coords — projection puts everything way off-screen.

**Fix shape:**

```ts
// In calculateCameraPosition()
const playerWorldX = (game.localPlayer.chunkX + game.chunkBaseX) * 128 + 64;
const playerWorldZ = (game.localPlayer.chunkY + game.chunkBaseY) * 128 + 64;
this.cameraX = playerWorldX;
this.cameraY = -180;   // height above ground
this.cameraZ = playerWorldZ;
```

**Acceptance:** post-rotate Z extents go positive; visible polys land inside the buffer.

## Gate 2 — Frustum / poly-storage bug (template)

If `gMinX > screenWidth` or all polys cluster in a tiny ≤25×25 region:

**File:** `2009scape-web/client-patch/osrs/Scene.ts` polygon storage + cull predicate.

**Most likely cause:** TS port of `Polygon` is correctly value-typed, but the *backing array* aliases between sibling models — `models[i].polygons === models[j].polygons` because the bridge constructor didn't deep-copy. iOS hit the *opposite* version of this in commit `38d169327` (class-shared singleton); same symptom matrix.

**Fix shape:** confirm `RawModel530.bridgeToModel()` (or whatever the bridge call is named) allocates a fresh `Polygon[]` per bridged model; if it shares references, deep-copy at bridge time.

**Acceptance:** visible polys spread across the full screen-space extent; `gMinX..gMaxX` ≈ `[10..510]` for a centred world.

## Gate 3 — Triangle clip / raster bug (template)

If `visible > 0` but `drawn == 0`:

**File:** `2009scape-web/client-patch/osrs/Scene.ts` rasterizer call site (search for `Rasterizer3D` or `drawTriangle`-style names).

**Most likely cause:** triangle clip math feeds the rasterizer NaNs or sign-flipped coords; rasterizer early-rejects everything. Add a one-shot log inside the rasterizer: print every input triangle's projected coords for the first 5 calls.

**Fix shape:** depends on what the per-call log shows. Most common is an integer-overflow on the perspective-divide step (use `| 0` consistently to coerce, or switch to floats throughout).

## Gate 4 — Lighting / colour bug (template)

If pixels rasterise but every one is `0xFF000000`:

**File:** `Model530.ts` flag-bridge + `applyLighting` call.

**Most likely cause:** the bridge zeros the per-face brightness byte (`vertexLight` / `faceLight` in rt4 naming), so `applyLighting` produces 0×anything = 0 for every channel.

**Fix shape:** copy the brightness/lighting fields when bridging from `RawModel530` into `Model`. Mirror `Model.java` constructor lines that read `light = src.light` style copies.

## Gate 5 — `m_dc` (drawable flag) bug (template)

If `models=N` is positive but `modelSkip == N` (all models marked non-drawable):

**File:** `Model530.ts` bridge constructor.

**Most likely cause:** `m_dc` (rt4 calls it `model.aBoolean*`) defaults to `false` in TS but is set to `true` in `Model.java`'s constructor based on `vertexCount > 0`. Bridge skips that init.

**Fix shape:** set `model.m_dc = (model.vertCount > 0)` after the bridge fills vertex arrays.

## Self-test (when implementing the chosen gate)

```bash
cd 2009scape-web
cp -R client-patch/osrs/. client/osrs/
./scripts/set-client-server.sh 10.8.0.1
cd client && rm -rf dist .cache && npm run build 2>&1 | tail -5
nohup npx serve dist -l tcp://127.0.0.1:8600 > /tmp/serve-2009.log 2>&1 & disown
cd /tmp/playwright-2009scape && node walk-test.js 2>&1 | grep -E "Probe|REBUILD"
```

The probe should now show:

- `models > 0`, `drawn > 0`.
- `visible-poly screen range` inside `[0..512] × [0..334]`.
- First-frame screenshot (capture in the walk-test script) is no longer all-black — terrain visible.

## Acceptance criteria (when filled in)

1. The chosen gate's symptom no longer reproduces in the next probe run.
2. Build green.
3. The "What the probe showed" section above is updated with the *post-fix* probe output for traceability.
4. Tier 6 checklist in `docs/web-client-plan.md` ticked with commit SHA.

## Out of scope clarifications

- **Don't fix more than one gate.** The probe should pin a single root cause; if it doesn't, *add more probe instrumentation* (Tier 6a follow-up) rather than fix-by-shotgun.
- **Don't disable the Tier 6a probe after fixing.** Keep it as a permanent flight recorder behind the `__rendererProbeDone` one-shot guard so future regressions surface immediately.

## Commit guidance

Single commit, message templated by the chosen gate, e.g.:

- `2009scape-web: tier6b — fix camera not adding world chunk base offset`
- `2009scape-web: tier6b — bridge model.m_dc from vertCount>0`

Push nothing.
