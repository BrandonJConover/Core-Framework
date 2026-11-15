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

- [x] Run `scape530-probe js5` and `login` against a real 2009scape server
      (2026-11-15, locally built 2009scape server, no DB): JS5 serves all 29
      reference tables with matching CRCs, login returns code 2, REBUILD_NORMAL
      decodes (Tutorial Island, 3094,3107), the server's XTEA keys open all 9
      `l*_*` groups, and ~450 packets in 5 s frame cleanly.
- [ ] Do the same from the Mac/iPhone against a reachable server (the Mac
      cannot reach the WireGuard address).
- [x] Keepalive / idle packets so the session survives (rt4 `client.mainLoop` outbound cadence).
- [x] Decode server packets into typed `ServerMessage`s (VARPs, interfaces,
      chat, inventories, stats, RUN_CS2, zone updates) plus PLAYER_INFO/NPC_INFO
      with masks. Zero decode failures across login, teleports, items, anims
      and two players on a live server. Folding them into a `GameState` is next.
- [x] Client packets: keepalive, `::commands`, walking (MOVE_GAMECLICK/MINIMAPCLICK).
- [x] Unit tests built from captured packet streams (`Fixtures/login-session.bin`).

## M2: iOS app shell

- [x] `App/project.yml` (xcodegen) app target depending on the package.
- [x] Login screen drawn from the cache's own `loginscreen` interface (744):
      main menu scroll, then "Please Log In" with username/password typed
      through the system keyboard; server/port sheet; Keychain storage.
      The components CS2 would toggle are set by `GameClient.loginState()`
      until the interpreter lands.
- [x] Cache bootstrap: `CacheUpdater` downloads via JS5 into Application
      Support in the standard `dat2`/`idx` layout and only refetches groups
      whose CRC/version changed.
- [x] `GameSession` network thread (login, framing, PLAYER/NPC_INFO, keepalive)
      feeding `GameState` on the UI thread; resizable game frame (746) renders
      after login. A test drives the full flow against a live server.
- [ ] First run on a device via the MacBook Air; move frame upload to Metal.
- [ ] Non-blocking transport on `Network.framework`.

## M3: See the world

- [x] Config decoders: ObjType, NpcType, LocType, SeqType, SpotAnimType, VarbitType, EnumType, FloType, FluType, IdkType, BasType. Every entry in the cache decodes (about 88,000).
- [ ] Remaining small configs: ParamType, StructType, InvType, VarpType, LightType.
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

- [x] Sprites (archive 8), fonts (archive 13 metrics + rt4 kerning/tags), software 2D raster.
- [x] Interface components (archive 3, if1 + if3, all 31,622 decode) with rt4 layout and drawing for layers, rectangles, text, sprites and lines.
- [ ] CS2 interpreter (archive 12). The biggest single port; the HUD's dynamic parts (tab switching, chat, orbs, login screen states) run on it.
- [ ] Inventory/item icons (type 2 and IF_SETOBJECT), model components (type 6), IF_BUTTON packets.
- [ ] Right-click menus mapped to long-press; on-screen keyboard for chat.

## M6: Polish

- [ ] Sound effects (archive 4/14) and music (archive 6) through AVAudioEngine.
- [ ] Resizable layout for iPhone vs iPad, safe areas, controller support.
- [ ] TestFlight build via the MacBook Air.

## M7: Offline play (server on device)

The app supports both modes: connect to a remote 2009scape server, or play
fully offline against a server running inside the app. The client talks to
both through the same socket protocol, so nothing above changes. The
2009scape server is Kotlin/Java on the JVM, which iOS cannot run as-is, so
this milestone means one of:

- Porting the server's game logic to Swift (largest, fully native), or
- Running the JVM server through an embedded interpreter/AOT build (for
  example a GraalVM native-image-style compile), which needs research on what
  iOS allows.

Decide between them once the client is playable; the server's content
scripts (quests, skills, NPC dialogue) are the bulk of that work.

## Many revisions, one client

Goal (Brandon, 2026-11-15): one client that can talk to many RSPS revisions,
picking the packet set and asset formats for the server it connects to.
Rev 530 is the first; nothing above should block on this, but the shared
layers are kept free of 530 specifics so others can plug in later:

- **Shared core** (revision-agnostic): `Packet`, ISAAC/XTEA/RSA, bzip2/DEFLATE,
  sockets/`GameSession` threading, `Raster`, sprite/font drawing, the
  interface layout engine, game state shapes (entities, inventories, stats),
  the iOS shell and touch input.
- **Per-era modules** (formats shared by a range of revisions): JS5 caches
  and if1/if3 interfaces (roughly 400-600s), the older JAG archive cache and
  317-style interfaces, and RSC classic as its own era.
- **Per-revision definitions**: opcode tables and packet bodies
  (`ServerProt`/`ClientProt`/`ServerMessage`/`ClientMessage` today), the login
  block, config opcode quirks (like npc 1688's later-revision opcodes), and
  server keys. The plan is a `Revision` value chosen at connect time that
  supplies these, with 530's current tables becoming the first instance.

Typed messages (`ServerMessage`, `ClientMessage`) are already the boundary:
the UI and game state only see those, never opcodes, so a new revision means
a new decoder/encoder pair rather than changes above it.

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
