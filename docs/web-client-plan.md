# Web Client Plan (rsc-c + Hetzner)

## 2007 TypeScript Client RSPS 530 Status

The 2007 web client under `2009scape-web/client-patch/osrs` is now being treated as a 530-first mobile web client. The upstream 377 code remains useful as a browser shell and fallback base, but new protocol/cache/renderer work should follow `reference/rt4-client` directly instead of preserving 377 abstractions when they get in the way. Tier 4 cache/data work is complete enough for rev-530 map and model data to reach the legacy renderer:

- [x] `RawModel530`: full rt4 idx7 byte decoder.
- [x] `BasType530` plus actor-definition wiring: 1431 animation sets.
- [x] `Model530` bridge: all 1996 referenced models preload into `Model.modelCache530`.
- [x] First `PLAYER_INFO` now instantiates the player slot.
- [x] `REBUILD_NORMAL` chunk X/Y mapping fixed: 857 locs place into the 104x104 scene grid.
- [x] 530 model bounds and copy/wrap preservation: bridged models now keep `modelHeight`, `shadowIntensity`, and packed culling fields through terrain-adjust / animation constructors.
- [x] Outgoing packet path split: legacy `putOpcode()` keeps the audited 377-to-530 bridge; new/mobile actions can use native `putOpcode530()` with exact rt4 packet bodies.
- [x] Native 530 `PLAYER_INFO` now maintains local/remote player lists, movement, mask alignment, and converts 530 appearance masks into the existing 377 `Player.updateAppearance()` format.
- [x] Native 530 `NPC_INFO` now maintains NPC lists, movement, type swaps, and initial definitions so NPCs can enter the legacy scene actor pass.

Current symptom: if the viewport still renders black, the likely causes are now renderer/camera-specific rather than missing scene/entity data:

- [ ] Verify camera setup in `Game.drawGameView()`, `setCameraPosition()`, and `calculateCameraPosition()` against the 530 spawn/chunk coordinate path.
- [ ] Add temporary projection/raster instrumentation around `Model.renderAtPoint()` and `Model.method599()` to distinguish camera frustum culling from triangle raster rejection.
- [ ] Inspect `applyLighting()` interactions with 530 color/texture flags once geometry reaches `Rasterizer3D`.
- [ ] Port high-value mobile interactions beyond walking as native 530 packets from `reference/rt4-client` instead of expanding the 377 remap table.

## Server protocol completion (2026-05-01 audit)

`PacketHandler530.ts` dispatches **55 of 97** rt4-authoritative `ServerProt` opcodes. The remaining 42 fall into clear groups; ordered by gameplay impact, the items that should land before the renderer work make a real difference are:

### Tier 5a — World/zone state (highest impact, blocks correct in-world rendering)

These opcodes drive the zone-update bus that keeps locs (game objects), ground items, and short-lived effects in sync after `REBUILD_NORMAL`. Without them the scene quietly desynchronises the moment anything spawns, despawns, or animates.

- [ ] **OBJ_ADD (135) / OBJ_DEL (240) / OBJ_REVEAL (33) / OBJ_COUNT (14)** — ground item lifecycle. Today only the initial sweep on REBUILD_NORMAL gets ground items; drops/picks-up are silently dropped.
- [ ] **LOC_ADD (179) / LOC_DEL (195) / LOC_ADD_CHANGE (202) / LOC_ANIM (20) / LOC_ANIM_SPECIFIC (235)** — game object mutations and animations (doors opening, fires lit, banks toggling).
- [ ] **MAP_PROJANIM (104) / MAP_PROJANIM_2 (16) / MAP_PROJANIM_3 (121)** — server-driven projectile animations (arrows, spells in flight, telegrabs).
- [ ] **SPOTANIM_SPECIFIC (17) / SPOTANIM_ENTITY (56)** — graphic-only animations (cast effects, eat ticks).
- [ ] **NPC_ANIM_SPECIFIC (102)** — one-shot NPC animation override.

### Tier 5b — Player + chat-side state (medium impact, blocks UX features)

- [ ] **TELEPORT_LOCAL_PLAYER (13)** — server-issued teleport; without it teleports trigger only on the next `PLAYER_INFO` tick and the `REBUILD_NORMAL` race shows a frame of the old region.
- [ ] **RESET_ANIMS (131)** — clears all in-flight character animations on logout/teleport.
- [ ] **DELETE_INVENTORY (191)** — wipes a whole inventory slot range; today the renderer can show stale items after a death until the next full inventory snapshot.
- [ ] **MESSAGE_PRIVATE (0) / MESSAGE_PRIVATE_ECHO (71) / MESSAGE_QUICKCHAT_PRIVATE (247) / MESSAGE_QUICKCHAT_PRIVATE_ECHO (141)** — private + quick-chat IO.
- [ ] **MESSAGE_CLANCHANNEL (54) / UPDATE_CLAN (196) / CLAN_QUICK_CHAT (81)** — clan-channel chat + member/membership updates.
- [ ] **CHAT_FILTER_SETTINGS (232)** — server pushes the player's chat filter (public/private/trade tabs) so the UI can mirror it.
- [ ] **LAST_LOGIN_INFO (164)** — last-login banner data (matches the iOS welcome dialog the player already sees).
- [ ] **SET_WALK_TEXT (160) / SET_SETTINGS_STRING (142)** — minimap walking-text override and per-settings string.
- [ ] **UPDATE_RUNWEIGHT (159) / UPDATE_UID192 (169) / RESET_CLIENT_VARCACHE (89) / FORCE_VARP_REFRESH (128)** — varp/varbit cache management.

### Tier 5c — Interface/widget plumbing (blocks bank, options, quest UI)

These all require the `Component`/`InterfaceList` stack from rt4-client (Tier 7 below). Wiring them now — without the widget layer — would just mean parsing-and-discarding to keep the stream aligned, which is still worthwhile so we stop drifting on every modal interaction.

- [ ] **IF_SETCOLOUR (2)** — sets a component's text colour.
- [ ] **WIDGETSTRUCT_SETTING (9)** — varc-style struct field write to a component.
- [ ] **IF_SETTEXT2 (48) / IF_SETTEXT3 (123)** — pushes server-side string into a text component.
- [ ] **IF_SETSCROLLPOS (220)** — scroll-position seek (used by quest journal, bank tabs).
- [ ] **SWITCH_WIDGET (176)** — replaces a tab/page within a parent interface.
- [ ] **INTERFACE_ANIMATE_ROTATE (207)** — interface model rotate-on-axis animation.
- [ ] **GAME_FRAME_UNK (209)** — game-frame-level interface update (unknown payload; mirror Java's parse to stay aligned).

### Tier 5d — Audio + misc (low impact for now, wire when audio comes online)

- [ ] **SOUND_AREA (97) / SYNTH_SOUND (172)** — area-loop and one-shot SFX. Currently `SoundTrack.ts` is the only audio path and even that is gated behind the position-bound break we shipped to avoid an empty-buffer infinite loop.
- [ ] **GENERATE_CHAT_HEAD_FROM_BODY (111)** — quest-NPC chat-head sprite generated from a body model (used in dialog overlays).
- [ ] **REFLECTION_CHEAT_CHECK (114)** — anti-cheat reflection probe; safe no-op.
- [ ] **URL_OPEN (42)** — server requests the browser to open a URL (membership upgrade, etc).

## Renderer plan (Tier 6)

Once Tier 5a lands, the scene actually contains the right entities and the rasterizer becomes the bottleneck for "screen still black/flat". Order:

1. **Camera-frustum verification.** `Game.calculateCameraPosition()` was last touched on the chunkX/chunkY fix (`fceb862e7`); add a one-shot debug probe to log the projected min/max screen-space X/Y of `models[0]` after `REBUILD_NORMAL` and confirm the same shape we audited in the iOS port (where polygons were silently collapsing to 25×25 off-screen because `Polygon` was a class shared across N slots — see iOS commit `38d169327`). The TS `Polygon` equivalent is value-typed today but the symptom matrix is identical, so the same probe is the fastest triage.
2. **`applyLighting()` against 530 face flags.** rt4 packs texture/colour-shift bits we don't replicate yet; the bridge in `Model530` zeros most flags, which produces flat-shaded geometry.
3. **`Rasterizer3D` instrumentation** — count triangles entering vs leaving each cull stage so we can attribute "no pixels" to a specific gate.
4. **Texture streaming** (defers to Tier 8). Until textures are wired, expect flat-shaded coloured terrain that matches Java when run with `-DDISABLE_TEXTURES`.

## Interface system (Tier 7)

Required to surface bank/options/quest UI properly, and to make Tier 5c handlers do something visible. Concrete checklist:

- [ ] Port `Component.java` (rt4) to TS — there are ~50 fields per component but most are passive containers. The first three pages (Component, ComponentPointer, InterfaceList) cover ~80% of in-game widgets.
- [ ] Wire `Js5Cache.getRegionBytes` style decompression into idx3 (interface defs) and idx13 (interface graphics).
- [ ] Hook `ScriptRunner` (CS2) — many interfaces dispatch logic through CS2 scripts; can ship a stub that no-ops unknown opcodes and selectively port the ones bank/options need.
- [ ] Wire the modal stack: server says "open IF X", client opens the right component tree.

## Audio + fonts + textures (Tier 8)

Currently stubbed; fully deferred until Tiers 5–7 are in:

- [ ] Real fonts from idx8/idx13 (`TypeFace.ts` is currently blank).
- [ ] Real sprites from idx8/idx13 (`ImageRGB`/`IndexedImage` stubs).
- [ ] Textures from idx26 + texture-op pipeline (rt4 has `TextureOp1..Op30`; we need 11/12/14/15/16/17/19/23/25 at minimum based on which ops a 530 cache references).
- [ ] BAS skeletal transforms (BAS data is decoded; transform application is still TODO).
- [ ] `SoundBank` + PCM mixer (rt4 `Sound`/`SoundBank`/`SoundPcmStream`/`SoundPlayer` chain).

## Goal

Deploy a browser-playable OpenRSC web client on the Hetzner VPS so players can connect without installing anything. The client uses `rsc-c` compiled to WebAssembly via Emscripten, served over HTTPS/WSS.

## Architecture

```
Browser
  │  HTTPS (port 443) — serves mudclient.html/.js/.wasm/.data
  ▼
Nginx (Hetzner VPS)
  │  WSS (port 43494) — proxied or direct WebSocket
  ▼
OpenRSC Java Server (port 43494 WebSocket)
```

The OpenRSC server already has native WebSocket support on port 43494 (`want_feature_websockets: true` in `default.conf`). No websockify proxy is needed.

## Requirements

### Hetzner Server
- Nginx
- Let's Encrypt SSL cert (certbot)
- Emscripten SDK 3.1.22 (exact version — newer causes SDL2 audio issues)
- git
- ~500MB free disk space for rsc-c build + cache

### Domain
- A subdomain pointing at the Hetzner VPS (e.g., `play.yourdomain.com`)
- DNS A record pointing to the server IP

### OpenRSC Server Config
These must be set in `connections.conf` before running:
```
ssl_server_cert_path: /etc/letsencrypt/live/play.yourdomain.com/fullchain.pem
ssl_server_key_path: /etc/letsencrypt/live/play.yourdomain.com/privkey.pem
```

And in the world's `.conf` file:
```
ws_server_port: 43494
want_feature_websockets: true
```

## Critical HTTP Headers

Emscripten's WebAssembly requires `SharedArrayBuffer` for memory threading. Chrome and Firefox require these headers on every response:

```nginx
add_header Cross-Origin-Opener-Policy "same-origin";
add_header Cross-Origin-Embedder-Policy "require-corp";
```

Without these, the WASM client will fail with a `SharedArrayBuffer is not defined` error.

## Build Steps

### 1. Install Emscripten (exact version 3.1.22)

```bash
cd /opt
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install 3.1.22
./emsdk activate 3.1.22
source /opt/emsdk/emsdk_env.sh
echo 'source /opt/emsdk/emsdk_env.sh' >> /etc/profile.d/emsdk.sh
```

### 2. Clone and Configure rsc-c

```bash
cd /opt
git clone https://github.com/2003scape/rsc-c.git
cd rsc-c
```

Edit `src/ui/worldlist.c` — change `worldlist_set_defaults()` to point at your server:

```c
// In worldlist_set_defaults():
strcpy(list[0].name, "OpenRSC");
strcpy(list[0].host, "YOUR_SERVER_HOSTNAME");
list[0].port = USE_WEBSOCKS ? 43494 : 43594;
strcpy(list[0].rsa_exponent, "00010001");
strcpy(list[0].rsa_modulus, "87cef754966ecb19806238d9fecf0f421e816976f74f365c86a584e51049794d41fefbdc5fed3a3ed3b7495ba24262bb7d1dd5d2ff9e306b5bbf5522a2e85b25");
```

### 3. Download Cache

The game cache must be present before building (Emscripten preloads it into the WASM data file):

```bash
cd /opt/rsc-c
mkdir -p cache
# Copy cache from your existing OpenRSC client cache directory
# or download from your server's cache distribution endpoint
rsync -avz /opt/openrsc/Client_Base/Cache/ /opt/rsc-c/cache/
```

### 4. Build

```bash
cd /opt/rsc-c
source /opt/emsdk/emsdk_env.sh
make -f Makefile.emscripten
```

Output files (4 files, all required):
```
mudclient.html
mudclient.js
mudclient.wasm
mudclient.data
```

### 5. Configure Nginx

```nginx
server {
    listen 443 ssl http2;
    server_name play.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/play.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/play.yourdomain.com/privkey.pem;

    # Required for WebAssembly SharedArrayBuffer
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;

    root /opt/rsc-c;
    index mudclient.html;

    location / {
        try_files $uri $uri/ =404;
        # Correct MIME types for WASM
        types {
            application/wasm wasm;
        }
    }

    location /mudclient.html {
        default_type text/html;
    }
}

server {
    listen 80;
    server_name play.yourdomain.com;
    return 301 https://$host$request_uri;
}
```

### 6. SSL Certificate

```bash
certbot --nginx -d play.yourdomain.com
```

Auto-renewal is configured by certbot automatically.

### 7. Test

```bash
# Check nginx config
nginx -t

# Reload nginx
systemctl reload nginx

# Test WebSocket connectivity
curl -I https://play.yourdomain.com/mudclient.html
```

Open `https://play.yourdomain.com/mudclient.html` in a browser. The game should load, connect via WSS to port 43494, and show the login screen.

## Deployment Script

See `Deployment_Scripts/deploy-web-client.sh` for the automated deployment script.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `SharedArrayBuffer is not defined` | Missing COOP/COEP headers | Add `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers in nginx |
| WebSocket connection refused | SSL cert not configured on OpenRSC server | Set `ssl_server_cert_path` in `connections.conf`, restart server |
| Black screen, no login | Cache not preloaded | Rebuild with correct `cache/` directory present |
| Audio distorted | Wrong Emscripten version | Must use exactly 3.1.22 |
| `wasm streaming compile failed` | Wrong MIME type | Add `application/wasm wasm` to nginx `types` block |

## Updating the Client

When the server cache changes:
```bash
cd /opt/rsc-c
rsync -avz /opt/openrsc/Client_Base/Cache/ ./cache/
source /opt/emsdk/emsdk_env.sh
make -f Makefile.emscripten
systemctl reload nginx
```

## Future: iOS rsc-c Port

The same `rsc-c` C codebase that builds for WASM could be compiled for iOS via SDL2. This would give a native iOS RSC client with authentic rendering without needing to port the Java mudclient. This is tracked in `ios-mobile-finish-plan.md` as an alternative rendering path.

What's needed:
1. An Xcode project or CMakeLists.txt with iOS deployment target
2. SDL2 iOS framework (via SDL2 releases)
3. Compile flags: `-DSDL2 -DRENDER_SW` (software renderer) or `-DRENDER_GL` (OpenGL ES 3.0)
4. `#ifdef TARGET_OS_IPHONE` guards in `get_config_path()` and audio initialization
