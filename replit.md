# OpenRSC - RuneScape Classic Emulator

## Overview
OpenRSC is a RuneScape Classic (RSC) emulator built through open-source cooperation. This fork of the Core-Framework includes several parallel client and server variants.

## Repository Structure

| Path | Language / Build | Role |
|------|-----------------|------|
| `server/` | Java 8+ / Ant | **Active server** - Legacy OpenRSC game server (Java 8-compatible, used in Replit) |
| `server-java-modern/` | Java 21 / Ant | Modernized server fork (requires Java 21, not buildable with current runtime) |
| `server-rust/` | Rust 2021 / Cargo | Async Tokio-based RSC server — full tick loop, REST API, multi-protocol support |
| `Client_Base/` + `PC_Client/` | Java 8 / Ant | Desktop Swing/AWT client |
| `PC_Launcher/` | Java 8 / Ant | Auto-updating launcher |
| `Android_Client/` | Java / Gradle | Android port |
| `iOS_Client/` | Swift 5.9 / Xcode | Native iOS client |
| `2009scape-web/` | TS/JS + Docker | Separate rev-530 game (requires Docker) |
| `web-client/` | nginx | nginx template for hosting JS client |

## Replit Setup

### Runtime
- **Java**: GraalVM CE 22.3.1 (Java 19) — compatible with server/ (Java 8 target)
- **Rust**: rustc 1.88.0 / cargo 1.88.0
- **Build tool**: Apache Ant 1.10.15 (system dependency)
- **System deps**: `pkg-config`, `openssl`, `protobuf` (needed for Rust server build)
- **Database**: SQLite (preservation.db pre-included at `server/inc/sqlite/preservation.db`)

### Workflow
The "Start application" workflow runs `bash start.sh` which:
1. Launches the Python status web server on **port 5000** (webview)
2. Builds the game server (if jars not present)
3. Starts the OpenRSC game server

### Server Ports
- **TCP 43594** — Game protocol (RSC+ client / OpenRSC desktop client)
- **WebSocket 43494** — Web client WebSocket proxy
- **HTTP 5000** — Status dashboard (Replit preview)

### Key Files
- `start.sh` — Main startup script
- `status_server.py` — Python HTTP status dashboard on port 5000
- `server/local.conf` — Server configuration (SQLite, preservation world)
- `server/build.xml` — Ant build file
- `server/inc/sqlite/preservation.db` — SQLite game database

### Configuration
- `server/local.conf` — Main config (copied from default.conf, modified for SQLite)
- World: Preservation (authentic RSC)
- DB type: SQLite

## Building

```bash
# Build core server (Java 8)
cd server && ant compile_core

# Build plugins
cd server && ant compile_plugins

# Run server manually
cd server && ant runserver -DconfFile=local -DcoloredLogging=false

# Build Rust server
cd server-rust && cargo build
```

## Note on Java 21 (server-java-modern)
The `server-java-modern/` directory requires Java 21. The current Replit environment provides Java 19 (GraalVM CE 22.3.1). To use it, upgrade to a Java 21 runtime when available.

## Rust Server (server-rust/)

### Architecture
- **Tick loop**: 640ms Tokio timer, 64 game modules
- **Protocols**: QUIC + TCP, multi-revision (V38 through V235)
- **Auth**: bcrypt via DB-backed PlayerRepository, or accept-all for benchmarks
- **REST API**: `/api/character/{username}`, `/api/players/online`, full CRUD
- **Entity updates**: Full `GameStateUpdater` pipeline — position, appearance, NPC, objects, ground-items

### Protocol Revision Support
All six authentic RSC client revisions are fully mapped:

| Revision | Notes |
|----------|-------|
| V38 | Earliest RSC (pre-duel/banking) |
| V69 | Same byte table as V38; payload parsing differs |
| V115 | Adds duel, banking, prayer, account-security |
| V177 | Adds NPC_COMMAND, SLEEPWORD, REPORT_ABUSE |
| V201 | Last pre-banking-trap protocol (2004-12-13) |
| V203 | Final pre-2009 retro-revival protocol |
| V235 | Post-2009; uses RSC175 SecuritySettings with 4 conflict bytes |

### Build Requirements
```bash
# System deps (installed via Replit package management):
# pkg-config, openssl, protobuf
cd server-rust && cargo build   # ~54s cold, ~4s incremental
```

### GameStateUpdater Wiring
`server.rs::send_entity_updates()` now calls `GameStateUpdater::generate_updates()` per
session each tick, producing the full bit-packed RSC update stream. Per-session
`KnownEntityList` pairs (player + NPC) are maintained in `ServerState::known_lists`
(lazy-created, cleaned up on logout).

## Connecting
Use the **RSC+ client** or the **OpenRSC desktop client** and connect to the server's host on TCP port **43594**.
