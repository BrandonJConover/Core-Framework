# Plan: 530 web client — Tier 6a renderer instrumentation probe

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. This is a **diagnostic-only** tier — no rendering changes. Its job is to produce a one-shot console dump that pinpoints which gate (camera, frustum, raster) is dropping our terrain on the floor.

## Goal

When the user logs in and the server delivers `REBUILD_NORMAL`, emit a single `[Probe]` console dump with: scene model count, vertex extents in raw model space, vertex extents after the camera transform, screen-space extents after projection, and per-stage triangle culling counts for the first frame. This will let us tell within seconds whether "screen black after world loads" is a camera-position bug, a frustum-culling bug, a triangle-clipping bug, or a rasterizer bug.

Why: an exact-shape regression killed the iOS port last week — `Polygon` was a class, the array was initialized with `[Polygon](repeating: Polygon(), count: N)`, and every "stored" poly collapsed onto the last one. Fixed in iOS commit `38d169327`. The TS `Polygon` equivalent is value-typed today, but if the symptom matrix matches (370 polys at a 25×25 box on screen) we want to know *immediately*, not after another half-day of guessing.

## Scope (files you may edit)

- `2009scape-web/client-patch/osrs/Scene.ts` — wrap the existing endScene-equivalent with one-shot probe instrumentation.
- `2009scape-web/client-patch/osrs/Game.ts` — call the probe once after `REBUILD_NORMAL` (gate via a `__rendererProbeDone` flag).
- (Optional) `2009scape-web/client-patch/osrs/Model530.ts` — add a single-shot vertex-bounds dump if asked by the probe.

## Out of scope (do NOT touch)

- The actual rasterizer math. Diagnostic only.
- Camera/lighting fixes; that's Tier 6b once the probe tells us what's wrong.
- Anything else the parallel agent might be writing this week.

## What to instrument

The probe should compute, on its first run only, the following values and log them in a single grouped `console.log` call:

### 1. Model bounds (model space)

```
[Probe] models=<N>  worldspace bounds across all models:
        x=[<min>..<max>] y=[<min>..<max>] z=[<min>..<max>]
        sample model[0]: faces=<F>  verts=<V>
```

Read the verts straight off the model — no transforms. Tells us the mesh exists and is roughly the size we expect (a 104×104 chunk world should have x/z spanning ~104×128 = 13312 units).

### 2. Camera + frustum state

```
[Probe] camera: pos=(<x>,<y>,<z>) yaw=<deg> pitch=<deg> zoom=<offset>
        frustum near=<z> far=<z>  screen=<w>x<h>
```

Read this off whatever Scene-equivalent fields hold camera state today. (`game.cameraX/Y/Z`, `Scene.frustumNearZ/farZ`, etc. — search the patched files.)

### 3. Post-rotate vertex extents

After the per-frame `rotate1024`-style camera transform (or whatever the TS port calls it), iterate the same verts and capture `vertXRot/vertYRot/vertZRot` extents:

```
[Probe] post-rotate extents: x=[..] y=[..] z=[..]   (camera-space)
```

If post-rotate Z extents put **everything behind the near plane** (negative Z when convention is "+Z is forward", or vice versa), we have a wrong-sign camera-position bug — that's our most likely culprit.

### 4. Per-stage triangle counters

Before each cull stage, increment counters and log at the end:

```
[Probe] triangles total=<T> zCulled=<a> screenCulled=<b> visible=<v> drawn=<d>
```

If `visible > 0` but `drawn == 0`, the rasterizer is dropping everything (iOS-style class-shared-instance bug pattern). If `screenCulled` is huge but `visible` polys end up far off the buffer (`xMin > screenWidth` or `xMax < 0`), it's a screen-projection bug.

### 5. Visible-polygon screen-extents min/max

For every poly that survives all culls, capture `polygon.minX/minY/maxX/maxY` and accumulate global min/max. Print:

```
[Probe] visible-poly screen range: x=[<gMinX>..<gMaxX>] y=[<gMinY>..<gMaxY>]
        screen=<w>x<h>
```

The signal we're looking for: do the visible polys actually land inside `[0..w] × [0..h]`? If they don't, we have iOS commit `38d169327` hiding in the TS port too (or some equivalent — different root cause, same symptom).

## Implementation

### 1. Gate the probe

```ts
// In Game.ts after REBUILD_NORMAL state transitions to ready:
if (!(game as any).__rendererProbeDone) {
    (game as any).__rendererProbeDone = true;
    // Schedule the probe to run on the next render frame, after the
    // first Scene cycle has completed at least once.
    requestAnimationFrame(() => {
        if (game.scene && typeof (game.scene as any).runRendererProbe === 'function') {
            (game.scene as any).runRendererProbe(game);
        }
    });
}
```

### 2. Implement `runRendererProbe(game)` on `Scene.ts`

It should run *one* full pass with instrumentation enabled (use a `this.__probeMode = true` flag that the existing per-frame loop reads), then `console.group('[Probe] renderer state')` / `console.groupEnd()` the output blocks listed above.

Do **not** persist the probeMode flag across frames — flip it back to `false` immediately after the diagnostic pass. Production frames must be untouched.

### 3. Output format

Use `console.table` for the per-stage counters and per-model bounds rows; plain `console.log` for one-line summaries. The whole probe output should fit in maybe 10 lines so it's readable in a Playwright capture.

## Self-test

```bash
cd 2009scape-web
cp -R client-patch/osrs/. client/osrs/
./scripts/set-client-server.sh 10.8.0.1
cd client && rm -rf dist .cache && npm run build 2>&1 | tail -5
```

Then run the standard `nohup npx serve dist -l tcp://127.0.0.1:8600 ...` workflow and a Playwright login-and-walk script. Look for `[Probe] renderer state` group in the captured console. **Do not deploy.**

## Acceptance criteria

1. After REBUILD_NORMAL the dev console shows the `[Probe]` group exactly once per session.
2. Output covers all 5 sections above.
3. The probe runs in ≤50ms so we don't notice a frame hitch.
4. No production-frame console output remains after the probe runs (single-shot only).
5. Append the probe's first captured output (verbatim) to `docs/web-client-plan.md` Tier 6 section — that's the input the next plan (Tier 6b) is conditioned on.

## Out of scope clarifications

- **Do not fix anything.** This is read-only instrumentation.
- **Do not** wire the probe to a UI button; it must auto-run.
- **Do not** add probe logic to `Model530.ts`'s hot path (every frame); it should only run when `Scene.__probeMode === true`.

## Commit guidance

Single commit: `2009scape-web: tier6a — renderer state probe`. Push nothing.
