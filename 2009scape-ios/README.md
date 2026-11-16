# 2009scape iOS (native Swift, rev 530)

A from-scratch Swift client for the rev-530 2009scape server. No embedded Java,
C engine or web view: every subsystem is ported from
[`reference/rt4-client`](../reference/rt4-client) (the authoritative rev-530
deob) into Swift. This is an experiment project; see [ROADMAP.md](ROADMAP.md)
for the milestones toward a playable client.

The classic RSC iOS app is separate work (`iOS_Client/`) and shares no code
with this package.

## Layout

```
2009scape-ios/
├── Package.swift
├── Sources/
│   ├── Scape530/            # Pure Swift + Foundation core (builds on Linux, macOS, iOS)
│   │   ├── Util/            # Packet (rt4 Buffer), Base37, CRC32, cp1252
│   │   ├── Crypto/          # ISAAC, XTEA, RSA (tiny BigUInt)
│   │   ├── Compression/     # bzip2 + DEFLATE decoders (no zlib/libbz2 dependency)
│   │   ├── Cache/           # JS5 containers, reference tables, dat2/idx reader + writer, CacheUpdater
│   │   ├── Net/             # JS5 + login + game packets: typed ServerMessage/ClientMessage, PLAYER/NPC_INFO
│   │   ├── Config/          # obj/npc/loc/seq/spotanim/varbit/enum/floor/idk/bas decoders
│   │   ├── Graphics/        # SpriteSheet, BitmapFont (rt4 fonts + tags), Raster (software 2D), PNG
│   │   ├── Interface/       # Component (if1/if3) decoder, InterfaceRenderer (rt4 layout + drawing), InterfaceScriptHost (CS2 host: components, vars, hooks, taps)
│   │   └── Client/          # GameSession (network thread), GameState, GameClient (screens + input)
│   └── scape530-probe/      # CLI to exercise the core against a cache or live server
├── App/                     # iOS app shell (xcodegen project.yml + SwiftUI/UIKit sources)
└── Tests/Scape530Tests/     # XCTest; golden values come from running rt4's Java classes
```

The core must stay free of UIKit/SwiftUI/Metal so it can be tested in a
Linux container. Everything the player sees is drawn by the core into a
`Raster` from cache sprites, fonts and interfaces, exactly as rt4's software
mode does, so tests can render any screen to PNG (`SCAPE530_OUT=dir`). The
app only blits that raster and forwards taps and typed text.

## iOS app

```bash
cd 2009scape-ios/App
xcodegen generate
open Scape530.xcodeproj   # run the Scape530App scheme on a device or simulator
```

On first launch the app downloads the cache from the server's JS5 port into
Application Support (about 90 MB; later launches only fetch what changed),
then shows the 2009 login screen from the cache's `loginscreen` interface.
The server button (top right) sets host and port (world 1 = 43595). The game
logs in in resizable mode (window mode 2), so the server opens interface 746,
which lays itself out for the phone's shape; below 765x503 game pixels the
frame is drawn at that size and scaled down. Build the Release configuration
for real play: the software raster is slow without optimisation.

## Build and test

macOS (Xcode 15+ toolchain):

```bash
cd 2009scape-ios
swift test
```

Linux / cloud container (no local Swift install needed):

```bash
docker run --rm -v "$PWD":/pkg -w /pkg swift:6.0-jammy swift test
```

### Tests against the real cache

`CacheTests` are skipped unless `SCAPE530_CACHE` points at a 2009scape cache
directory (`main_file_cache.dat2` + `.idx0`...`.idx255`). The cache lives in
the 2009scape server repo under Git LFS at `Server/data/cache`
(`2009scape-web/setup.sh` clones it into `2009scape-web/2009scape`).

```bash
SCAPE530_CACHE=../2009scape-web/2009scape/Server/data/cache swift test
```

## Probe CLI

```bash
swift run -c release scape530-probe cache <cache-dir> --deep   # verify every group's CRC + decompress
swift run scape530-probe js5 <host> 43595                       # JS5 handshake, master index, reference tables
swift run scape530-probe login <host> 43595 <user> <pass> [js5-port]
```

`cache --deep` against the 2009scape cache verifies all 68,499 groups in the
29 archives; the only groups it cannot open are archive 5's XTEA-encrypted
`l*_*` location groups, whose keys come from the server in REBUILD_NORMAL.

### Local server for end-to-end tests

The 2009scape server builds with Maven (`Server/mvnw clean package -Dmaven.test.skip=true`)
and runs without MariaDB when `use_auth` and `persist_accounts` are both
false in its world config. Copy the cache into `Server/data/cache`, then
`java -jar target/server-1.0.0-jar-with-dependencies.jar <conf>` and point the
probe at `127.0.0.1 43595`. With `SCAPE530_CACHE` set, `login` also decrypts
the map location groups using the keys from REBUILD_NORMAL.

## Server compatibility notes

These come from 2009scape's `GlobalConfig` in rt4-client and are mirrored in
`Login.swift` / `IsaacRandom.swift`:

- RSA key: 2009scape's 1024-bit modulus, exponent 65537 (`RsaKey.scape2009`).
- `USE_ISAAC = false`: opcodes are sent and received unscrambled.
- `LOGIN_EXTRA_INFO = true`: three empty strings follow the password in the RSA block.
- `LOGIN_FAKE_IDX28 = true`: a 29th (zero) CRC is sent after archives 0...27.
- Ports: the server listens on one port, `43594 + worldId` (43595 for world 1),
  for both JS5 (opcode 15) and game login (opcode 14).
