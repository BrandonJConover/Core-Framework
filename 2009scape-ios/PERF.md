# Performance

Goal: the pure-Swift rev-530 client at 60 fps minimum on an iPhone 15 Pro, with 120 Hz ProMotion looking smooth.
The renderer is a bit-exact port of rt4's software rasteriser, so every optimisation here is output-preserving
(the first frame of the benchmark scene hashes to the same value before and after, and the pixel tests pass).

## Benchmark

`scape530-bench` replays the recorded `resizable-session.bin` login (a real region from the cache: castle,
courtyard, 23 npcs, a player) into a `GameClient` and times frames. Run it in release mode:

```
swift run -c release scape530-bench <cache-dir> Tests/Scape530Tests/Fixtures/resizable-session.bin [frames] [WxH ...]
# defaults: 100 frames at 765x503 and 1600x740
```

It prints the full `GameClient.frame` time (interface, world, minimap, wall-clock cycles) and a breakdown from
section timers (`PerfStats`, one branch each when disabled): the 3D scene (ground tiles, models), the
3D-buffer copy, overlays, interfaces, minimap and a client cycle. The 3D loop runs 50/60 of a cycle per frame
like a 60 fps shell, so actors re-pose on most frames. The checksum is the hash of the first frame of a fresh
client (always exactly one cycle), to see whether a change touched any pixel. Under Docker use
`SCAPE530_NO_MODEL_CACHE=1` to switch the per-actor model cache off for an A/B.

Numbers below are the median of 3 runs x 100 frames, in milliseconds per frame, on a shared 4-core x86 Linux
container (noisy; an iPhone 15 Pro core is considerably faster than this). Relative change is what matters.

## Baseline vs after

| ms / frame | 765x503 before | after | 1091x503 before | after | 1600x740 before | after |
|---|---:|---:|---:|---:|---:|---:|
| **full frame** (`GameClient.frame`) | 24.7 | **9.4** | 32.5 | **13.8** | 46.2 | **19.6** |
| world.draw (3D + overlays) | 13.9 | 7.8 | 22.2 | 11.4 | 34.1 | 17.2 |
| &nbsp;&nbsp;ground tiles | 1.19 | 0.95 | 1.94 | 1.32 | 2.95 | 1.96 |
| &nbsp;&nbsp;models (locs, actors, items) | 10.7 | 5.8 | 16.9 | 8.4 | 26.1 | 12.8 |
| &nbsp;&nbsp;3D buffer to frame | 0.71 | 0.14 | | | 2.26 | 0.66 |
| interfaces | 9.29 | 1.28 | 9.29 | 1.33 | 8.71 | 1.28 |
| minimap | 0.53 | 0.48 | | | 0.54 | 0.48 |

About 2.6x faster at phone size (765x503), 2.4x at 1600x740; the interface drawing went 7x. Checksum of the
first frame at 765x503 is identical before and after (`c10786fd5ab2d291`).

## What changed

Found with callgrind (valgrind in the swift image) on the release bench:

1. **Dynamic exclusivity checking off** in release builds of the library (`Package.swift`,
   `-enforce-exclusivity=unchecked`, release configuration only). The rasteriser reads and writes class
   properties in its innermost loops and every access paid a `swift_beginAccess` (about 24% of all
   instructions together with the TLS lookups it needs). The game thread is serial and the code has no
   overlapping accesses; debug builds and the test suite still check. `-Ounchecked` was tried and not kept: no
   gain that stood out from the noise.
2. **Sprites** (`Graphics/Sprite.swift`, `Graphics/Raster.swift`): `SpriteFrame.argb` was a computed property
   rebuilding the whole pixel array on every blit (20% of a frame, plus an optional-array copy per pixel). It is
   now computed once at decode. `Raster.draw`, `drawScaled` and `fillRect` run on raw pointers with the row and
   column clip hoisted out of the pixel loop. Pixel-exact against the old per-pixel `blend`
   (`RasterBlitTests`).
3. **Interface layout** (`Interface/InterfaceRenderer.swift`): every layer scanned and copied all components of
   its interface (a ~1 KB struct each) to find its children. A per-interface parent to children index is built
   once when the group is loaded.
4. **Models**: each model cleared 17 KB of depth-bucket tables (`SoftwareModel+Render`); now only what the
   previous model dirtied. Each actor keeps its posed model and rebuilds it only when its pose inputs changed
   (`PathingActor.buildModel`, signature of look, npc type, sequence frames, layers), which pays at 60/120 Hz
   where several frames share a client cycle.
5. **Textures**: the rasteriser keeps the texel arrays it has seen per texture id (no provider lock plus
   dictionary hash per textured triangle), and `TextureStore.prewarm` generates all textures on a background
   queue, using a private copy of the config store, so the first frame to show a texture does not stall on
   its procedural generation.
6. **3D buffer to frame** copy (`Rasteriser3D.copy`) works per row on pointers; the frame buffer of
   `GameClient.frame` is reused when the shell has dropped the previous raster (no multi-megabyte allocation
   per frame).

Not done, on purpose: strip-parallel rasterisation. The scanline code is one 4,000-line transliteration whose
clipping is tied to the viewport, and the painter's algorithm order has to be replayed per strip to stay
bit-exact; it was judged not worth the risk against a phone that already clears 60 fps. If it is wanted later,
the safe design is to record the scene's draw commands and replay them per horizontal strip on worker
threads, each with its own clip rows.

## Smooth motion (render-side interpolation)

rt4 moves actors and eases the camera once per 20 ms client cycle and redraws the same state in between, so on
a 60 or 120 Hz display motion steps at 50 Hz. `GameClient.smoothMotion` (default off = rt4-faithful) draws
actors, their overhead text and hit splats, and the camera between the previous and the latest cycle:

- `WorldView.cycle` snapshots each actor's position and yaw, and the camera's follow point, before the cycle
  runs.
- `GameClient.frame(width:height:at:)` sets `world.renderAlpha = (now - lastCycleAt) / 20 ms` (0...1) after
  running the due cycles. The picture trails the simulation by up to one cycle.
- `WorldView.draw` and `pick` apply `prev + (current - prev) * alpha` to actors and camera (shortest way round
  for yaw), draw or pick, and restore the real values, so game logic, collision, sounds and the minimap
  never see interpolated state. Moves bigger than a walk or run step (teleports, forced movement, region
  shifts, camera snaps) are shown at the new position at once.
- Not interpolated: projectiles, ground spot animations, the minimap dots and click cross. Model animation
  frames still advance per cycle (rt4 tweens them itself).

How the app uses it (already wired in `App/Sources`, minimal edits):

- `GameLoop.requestFrame(width:height:smooth:smoothMotion:)` sets `client.smoothMotion` on the game queue, then
  calls `client.frame(width:height:)` as before. A shell that wants the display timestamp can call
  `client.frame(width:height:at: Date(...))` instead (convert `CADisplayLink.targetTimestamp`).
- `GameView` passes `MobileSettings.smoothMotion` (new Controls toggle "Smooth motion (60/120 Hz)", default on)
  and asks the display link for 120 Hz when it is on (60 when off, 30 when throttled).
- Frames are drawn on the game queue and dropped while one is in flight, so a device that cannot hold 120 Hz
  degrades to 60 or 40 fps with the same motion quality.

## Tests

`InterpolationTests` (blend, shortest-way yaw, jumps, faithful mode, state restored, full-cycle alpha equals
the faithful picture, clock-driven alpha) and `RasterBlitTests` (fast blitters against the old per-pixel
reference). The whole suite passes in debug; the rendering suites also pass in release with the
exclusivity flag active (`swift test -c release -Xswiftc -enable-testing`).
