# Roadmap: native Swift 2009scape client

Goal: a playable rev-530 2009scape client on iPhone/iPad written in Swift,
ported subsystem by subsystem from `reference/rt4-client`. Each milestone ends
with something you can run and see.

Sources to port from, in order of authority:

1. `reference/rt4-client` (rt4 deob, rev 530). Pin: commit `a7c7dea3`
   (gitlab.com/2009scape/rt4-client). The submodule entry has no
   `.gitmodules`, so clone it by hand if the folder is empty.
2. Live 2009scape server behaviour (`gitlab.com/2009scape/2009scape`, `Server/`).
3. `2009scape-web/client-patch/osrs/*530*.ts`: our own TypeScript port of
   many rev-530 decoders (RawModel530, LocType530, NpcType530, BasType530,
   SeqType530, terrain mesh, player appearance...). Useful as a second
   reading of the Java, never as the source of truth.

## M0: Core library (done)

Pure Swift package `Scape530`, tested on Linux in Docker and on macOS.

- [x] `Packet` (rt4 `Buffer` reads/writes incl. add/sub/neg/middle-endian variants, smarts, cp1252 strings)
- [x] ISAAC, XTEA, RSA with 2009scape's key (golden values from rt4 Java)
- [x] bzip2 + DEFLATE in pure Swift
- [x] JS5 containers, reference tables (`Js5Index`), group/file unpacking, `dat2`/`idx` reader
- [x] JS5 network protocol (handshake, requests, 512-byte block parser)
- [x] Login handshake + login block (rt4 `LoginManager` steps 2-9)
- [x] Game packet framer + `ServerProt`/`ClientProt` tables, REBUILD_NORMAL decoder
- [x] `scape530-probe` CLI

## M1: Talk to a live server

- [ ] Run `scape530-probe js5` and `login` against a real 2009scape server
      (local Docker stack from `2009scape-web/`, or a public port; the Mac
      cannot reach the WireGuard address).
- [ ] Keepalive / idle packets so the session survives (rt4 `client.mainLoop` outbound cadence).
- [ ] Decode the core server packets into a `GameState` (not rendered yet):
      VARP_SMALL/LARGE, interface open/close, chat messages, inventory updates,
      skill stats, RUN_CS2 arguments. Unknown opcodes are skipped by length.
- [ ] Unit tests built from captured packet streams.

## M2: iOS app shell

- [ ] `project.yml` (xcodegen) app target depending on the package.
- [ ] SwiftUI login screen (server/port/world, username, password) with Keychain storage.
- [ ] Cache bootstrap: download via JS5 into Application Support, written in the
      standard `dat2`/`idx` layout so `DiskCache` reads it back; CRC check on start.
      Option to side-load a bundled cache for faster first launch.
- [ ] Network transport on `Network.framework` (non-blocking), feeding the framer on the game tick.
- [ ] `MTKView` that shows a debug overlay (connection state, tick, position).

## M3: See the world

- [ ] Config decoders from archive 2: FloType/FluType (floors), LocType, ObjType, NpcType, SeqType, SpotAnimType, IdkType, BasType, EnumType, ParamType.
- [ ] Map squares from archive 5: `m{x}_{z}` terrain and `l{x}_{z}` locations (XTEA keys from REBUILD_NORMAL).
- [ ] Terrain mesh (heights, underlays/overlays, shapes, blending) and loc placement.
- [ ] `RawModel` decoder (archive 7) and lighting.
- [ ] Metal renderer: terrain + static locs + camera (drag to rotate, pinch to zoom).

## M4: Things move

- [ ] PLAYER_INFO / NPC_INFO bit-packed updates (movement + masks).
- [ ] Player appearance compositing (kits + worn items, recolours).
- [ ] Animation: frame bases + framesets (archives 0/1), SeqType playback, BAS idle/walk.
- [ ] Tap-to-walk: pathfinding + MOVE_GAMECLICK; minimap.
- [ ] Zone updates: LOC_ADD/DEL, OBJ_ADD/DEL, projectiles, spot anims.

## M5: Interfaces

- [ ] Sprites (archive 8), fonts, and a 2D compositor drawn as Metal textures.
- [ ] Interface components (archive 3) and the CS2 interpreter (archive 12). This is the biggest single port; the whole HUD (inventory, chatbox, tabs, bank) runs on it.
- [ ] Right-click menus mapped to long-press; on-screen keyboard for chat.

## M6: Polish

- [ ] Sound effects (archive 4/14) and music (archive 6) through AVAudioEngine.
- [ ] Resizable layout for iPhone vs iPad, safe areas, controller support.
- [ ] TestFlight build via the MacBook Air.

## Rendering approach

rt4 has two renderers: a software rasteriser (`Rasteriser`, used by the
"safe mode") and an OpenGL one. The plan above assumes a Metal GPU renderer
that consumes the same decoded models and terrain, because it is the native
fit for iOS and keeps frame times low on phones. The alternative is to port
the software rasteriser line by line and blit its framebuffer through Metal:
more faithful pixel output, more code, and heavier on battery.

## Build environments

- Cloud containers: `docker run --rm -v "$PWD":/pkg -w /pkg swift:6.0-jammy swift test`
  (start `dockerd` first if it is not running). The Swift toolchain download
  site is blocked, but Docker Hub images work.
- Device builds: Brandon's MacBook Air through Remote Control, from a clone
  outside iCloud-synced folders (for example `~/Developer`).
