# RSCEngine — native rsc-c for the iOS app

The "2001scape" option in the iOS app runs **rsc-c**
(<https://github.com/2003scape/rsc-c>, AGPL-3.0, see `rsc-c-src/COPYING`) —
the same C client that powers the WebAssembly browser client — compiled
natively into the app. No webview: the engine renders with its software
renderer into a framebuffer that Swift puts on screen, and Swift feeds it
touch, keyboard and audio.

```
SwiftUI / UIKit (Views/Native)          RSCEngine (C, this folder)
NativeRSCView  ── touches, text ──▶  rsc_host.h  ──▶  SDL2-subset shim ──▶ rsc-c
               ◀── frames, audio ──                (shim/rsc_sdl_shim.c)   (rsc-c-src, unmodified)
```

## Layout

| Path | What |
|------|------|
| `rsc-c-src/` | Vendored rsc-c `src/` (upstream commit `d9081d3`, 2026-10-19), **unmodified**. Console/GL-only files removed. |
| `rsc-cache/` | rsc-c game cache (`*.jag`, `*.mem`), bundled into the app. |
| `shim/SDL.h`, `shim/rsc_sdl_shim.c` | Just enough SDL2 for rsc-c's SDL2 + software-renderer path, implemented on top of a thread-safe event queue, frame buffer and audio ring. |
| `include/rsc_host.h` | The API Swift calls (`import RSCEngine`). |
| `tools/` | Headless Linux/macOS driver for testing the engine without a device. |

## How it runs

- rsc-c is built with `SDL2 RENDER_SW ANDROID`. Its `ANDROID` path is really
  its mobile SDL2 target: touch input (tap = left click, hold = menu, drag
  = rotate, pinch = zoom), UI scaled so the short side is 360 game pixels,
  and config files in `SDL_GetPrefPath` (the app's Application Support).
- `main()` is renamed `rsc_c_main()` (`-Dmain=rsc_c_main`) and runs on its own
  thread with rsc-c's original blocking game loop.
- The host writes `worlds.cfg` (server, port, RSA key) before starting, so the
  engine connects straight to the chosen server over TCP.
- rsc-c keeps global state: the engine starts once per app launch.

## Server compatibility

rsc-c sends a fixed 64-byte RSA block. `server-java-modern` previously parsed
it as a *signed* BigInteger, so about 40% of rsc-c logins failed with
"Unrecognised response code" ("missing username terminator" in the server
log). Fixed in `server-java-modern/.../net/rsc/Crypto.java`. Servers without
that fix will reject some native-client (and browser-client) logins; retrying
usually works.

The RSA modulus must match the server's `client.pem`. The Java server prints
it at startup (`RSA modulus: <decimal>`); the app accepts decimal or hex.

## Testing without a device

```sh
make -C iOS_Client/OpenRSC/RSCEngine/tools
# server-java-modern running locally on 43594
printf 'sleep 7000\ntap 390 297\nsleep 800\nshot /tmp/login.ppm\nquit\n' | \
  iOS_Client/OpenRSC/RSCEngine/tools/build/headless \
  iOS_Client/OpenRSC/RSCEngine/rsc-cache /tmp/rsc-config \
  127.0.0.1 43594 10001 <modulus-hex-or-decimal-converted> 780 360
```

See `tools/headless.c` for the command list (tap, press, drag, text, key,
shot, …).

## Updating rsc-c

Copy upstream `src/` over `rsc-c-src/` (drop `gl/`, `pica/`, `wii/`,
`*-3ds*`, `*-gl.c`, `mudclient-wii.c`, `mudclient-sdl12.c`), copy new cache
files into `rsc-cache/`, run the headless driver, then build the app. If
upstream starts using another SDL function, add it to the shim.
