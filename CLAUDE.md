# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a **fork of the OpenRSC Core-Framework** — a RuneScape Classic emulator — extended with several parallel client and server variants. The upstream project is Java 8 + Ant; this fork adds modernized server, native iOS client, web clients, and a separate 2009scape (rev 530) deployment.

The repository is **not a single buildable project**. It is a polyglot collection of independent components that share a wire protocol and (usually) a database schema. When working in any subdirectory, treat it as its own project with its own build system.

## Top-Level Components

| Path | Language / Build | Role |
|------|------------------|------|
| `server/` | Java 8 + Ant + Gradle | Legacy upstream OpenRSC game server (authoritative) |
| `server-java-modern/` | Java 21 + Ant | Modernized fork of `server/` with CVE patches and cherry-picked fixes. **Active dev target.** See `PROGRESS.md` and `CHERRY_PICKS.md` |
| `server-rust/` | Rust (stub) | Empty placeholder — do not implement against |
| `Client_Base/` + `PC_Client/` | Java 8 + Ant | Original Swing/AWT desktop client. `Client_Base/build.xml` cross-compiles `PC_Client/src` |
| `PC_Launcher/` | Java 8 + Ant | Auto-updating launcher that downloads the client jar + cache from a website |
| `Android_Client/` | Java + Gradle | Android port of the Java client |
| `iOS_Client/OpenRSC/` | Swift 5.9 + Metal + Xcode/SPM | Native iOS client (rendering own world, not a webview wrapper). `project.yml` → use `xcodegen` |
| `2009scape-web/` | TS/JS + Docker | Separate game (rev 530, not RSC). Browser client + websockify proxy + MariaDB. Independent of the rest |
| `web-client/` | nginx config + Python | nginx template + worldlist patch script for hosting the upstream JS client |
| `Deployment_Scripts/` | Bash + Playwright | Production deploy scripts and end-to-end smoke tests |
| `reference/rt4-client/` | Java (read-only) | Authoritative rev-530 rt4 client source — reference only, do not edit |

## Common Commands

### Java game server (`server/` or `server-java-modern/`)

Both directories use Ant for the canonical build. Gradle wrappers exist but Ant is what the launcher scripts and CI use.

```bash
# Build core + plugins (run from the server directory)
ant -f build.xml compile_core
ant -f build.xml compile_plugins

# Or both at once
ant compile

# Run with a specific config (file is <name>.conf in the server dir)
ant runserverzgc -DconfFile=local        # Java 17+ ZGC (preferred)
ant runserver    -DconfFile=local        # Java 8 G1GC fallback

# Helper: launches detached in a `screen` session (creates local.conf from default.conf if missing)
./ant_launcher.sh local         # ZGC
./ant_launcher.sh local g1gc    # G1GC

# server-java-modern only — network-level smoke test (boots server, hits TCP+WS ports)
./smoke_test.sh
```

Each `<name>.conf` file in the server dir corresponds to a separate world (`local`, `default`, `preservation`, `rsccabbage`, `rsccoleslaw`, `uranium`, `openpk`, `2001scape`). World choice picks the DB and the listening ports — see "Ports" below.

There are **no unit tests**. Validation is: clean compile + `smoke_test.sh` (server-java-modern only) + manual login via a client.

### Top-level Makefile (database / ops)

The root `Makefile` is purely DB and ops automation. It pulls credentials from `.env`. Common targets:

```bash
make compile                                       # Builds server core + plugins + Client_Base + PC_Launcher (all Ant projects)
make run-server                                    # Runs Deployment_Scripts/run.sh
make run-client                                    # ant -f Client_Base/build.xml runclient

make create-mariadb db=<name>                      # Create empty DB
make import-authentic-mariadb db=preservation      # Load core schema into MariaDB
make import-authentic-sqlite db=preservation       # Same for SQLite (server/inc/sqlite/<db>.db)
make import-custom-mariadb db=cabbage              # Core + addons (auctionhouse, clans, runecraft, …)
make backup-mariadb db=<name>                      # Schema dump + pruned data dump (drops most log tables)
make rank-mariadb db=<name> group=<id> username=<name>
make namechange-mariadb db=<name> oldname=<x> newname=<y>
```

`-sqlite` variants exist for every `-mariadb` target. SQLite DBs live at `server/inc/sqlite/<db>.db`.

### Java desktop client (`Client_Base/`)

```bash
ant -f Client_Base/build.xml compile               # Builds Open_RSC_Client.jar (cross-compiles PC_Client/src)
ant -f Client_Base/build.xml runclient
```

### PC Launcher (`PC_Launcher/`)

```bash
ant -f PC_Launcher/build.xml compile               # Builds OpenRSC.jar
ant -f PC_Launcher/build.xml setversion            # Stamps build version into Defaults.java
```

### iOS client (`iOS_Client/OpenRSC/`)

The Xcode project is generated from `project.yml`. After editing `project.yml` or adding sources, regenerate:

```bash
cd iOS_Client/OpenRSC
xcodegen generate
xcodebuild -project OpenRSC.xcodeproj -scheme OpenRSC -destination 'platform=iOS Simulator,name=iPhone 15'
```

There is also a Swift Package Manager `Package.swift` (target `OpenRSC` lib + `OpenRSCTests`) for `swift build` / `swift test` from the command line. Both target the same sources under `OpenRSC/Sources/`.

### 2009scape-web (separate stack)

```bash
cd 2009scape-web
docker compose up -d                               # Brings up MariaDB + 2009scape server + websockify proxy + nginx
```

This is a different game (rev-530 RuneScape, not RSC) with a different DB and different ports. It does not share code with the rest of the repo apart from being colocated.

### E2E smoke tests

```bash
node Deployment_Scripts/playwright/login-flow.mjs  # Live login flow against deployed server
node 2009scape-web/e2e/smoke-test.js               # 2009scape web client smoke test (Playwright)
```

## Architecture: Java Game Server

Both `server/` and `server-java-modern/` share the same architecture (the modern variant is a cherry-pick fork). High-level structure documented in each directory's `SERVER.md`:

- **`src/com/openrsc/server/`** — core server (sockets, packet I/O, login, world ticking, model entities). Entry point: `Server.java`.
- **`plugins/com/openrsc/server/plugins/`** — game content (quests, NPC dialogues, skill mechanics, item interactions). Compiled into a separate `plugins.jar` that depends on `core.jar`.
- **`conf/server/`** — XML/text data assets loaded at boot (entity defs, languages, fonts, badwords, log4j2 config).
- **`database/{mysql,sqlite}/`** — schema files: `core.sql` (authentic), `retro.sql` (2001scape), and per-feature addons under `addons/`.

### Tick model & event types
The world advances on a fixed game tick (default 640 ms — the average observed in 2018 RSC+ replays). Two event categories:
- **Game tick events** — fire on tick boundaries; used for skill timers, combat rounds, walking.
- **Server events** — async / off-tick; used for chat options, item drops, follow logic.

### Packet flow
1. `RSCConnectionHandler` (Netty pipeline) reads a packet and enqueues it on the `Player`.
2. `Server.java`'s game loop calls `Player.processIncomingPackets()` each tick.
3. The packet ID dispatches to a `PacketHandler` implementation under `src/com/openrsc/server/net/rsc/handlers/`.
4. `PacketHandler` implementations should only parse + delegate. Game logic lives in `plugins/`.
5. Outgoing packets go through `ActionSender.java`.

### Player data layering
- **DB field** — persisted across logins.
- **Cache** — survives across sessions but not in DB (e.g., volatile per-account state).
- **Attribute** — single-session only; cleared on logout.

### Multi-world / multi-port
A single server JAR can run different worlds via different conf files. Ports are offset by world: `server_port` is `43594 + worldOffset` (e.g. preservation=43594, cabbage=43595, openrsc=43596). The matching WebSocket port is `43494 + worldOffset`. `connections.conf` lists cross-world links. **Editing port logic requires updating both server config and any client/proxy that targets it.**

### Cross-server invariant
`server-java-modern/` MUST stay protocol-compatible with the upstream Java client and the iOS client. When changing wire formats, packet handlers, or ActionSender, treat all clients (Java/PC, Android, iOS, 2009scape-web — though the last is a separate codebase) as consumers and verify nothing breaks. Reference clients to consult: `Client_Base/src/`, `iOS_Client/OpenRSC/OpenRSC/Sources/Network/`, and `reference/rt4-client/` for rev-530 protocol questions.

## Architecture: iOS Client

`iOS_Client/OpenRSC/OpenRSC/Sources/` is laid out by subsystem, not feature:

- `Network/` — TCP socket, packet framing, opcode dispatch, ISAAC cipher. `GameProtocol.swift` is the protocol layer.
- `GameEngine/RSC/` — game state, tick loop, AppState.
- `Rendering/` — Metal-backed software-style 3D pipeline (Scene/Polygon/RSModel/Shader). Shaders are runtime-compiled from `Shaders.metal`.
- `Models/` — entity models (Player, NPC, items).
- `Views/` — SwiftUI HUD, modal overlays, game view container.
- `Input/` — touch / pinch / context-menu gestures.
- `WebClient/` — fallback WKWebView path; **excluded from the iOS app target** (`project.yml` excludes `WebClient/**`). Uses upstream JS client.

Asset files live next to `Sources/` (`Authentic_Sprites.orsc`, `Authentic_Landscape.orsc`, `landscape.dat`, `sprites.dat`, `ItemDefs.json`, `NpcDefs.json`, `GameObjectDef.xml`). They are bundled via `project.yml`'s resources block.

## Repository Conventions

- **Branches:** Upstream uses `develop` as the integration branch (PRs target it). This fork's active branch is `ios/phase1-foundation`. The Makefile and CI assume Ant; do not switch builds to Gradle without updating both.
- **Tabs, not spaces** — see `.editorconfig` and `CONTRIBUTING.md`. Source uses single tabs.
- **No GitLab CI runs locally** — `.gitlab-ci.yml` is upstream's pipeline; ignore for local work.
- **`compile_core.cmd` / `compile_plugins.cmd` / `compile_server.sh` / `compile_client.cmd`** are Windows/Linux convenience wrappers over the Ant targets. Don't introduce divergent build logic.
- **Two `plugins/` directories appear in `server-java-modern/`** (`plugins` and `plugins 2`, also `src` and `src 2`) — these are macOS Finder duplicates from a copy. Build only references `plugins/` and `src/`. Don't delete blindly without checking what's inside.

## Where to Look First

- **Adding a packet handler:** `server/src/com/openrsc/server/net/rsc/handlers/` (and matching opcode in `iOS_Client/OpenRSC/OpenRSC/Sources/Network/`)
- **Adding game content:** `server/plugins/com/openrsc/server/plugins/`
- **Tuning world behavior without code changes:** the `<name>.conf` file (database, ports, tick speed, XP rates, max players, etc.)
- **Modernizing/cherry-picking:** `server-java-modern/CHERRY_PICKS.md` tracks what's been pulled from upstream develop
- **Protocol questions:** read the existing Java client first (`Client_Base/src/`), then iOS, then `reference/rt4-client/` for rev-530 specifics
