# OpenRSC - RuneScape Classic Emulator

## Overview
OpenRSC is a RuneScape Classic (RSC) emulator built through open-source cooperation. This fork of the Core-Framework includes several parallel client and server variants.

## Repository Structure

| Path | Language / Build | Role |
|------|-----------------|------|
| `server/` | Java 8+ / Ant | **Active server** - Legacy OpenRSC game server (Java 8-compatible, used in Replit) |
| `server-java-modern/` | Java 21 / Ant | Modernized server fork (requires Java 21, not buildable with current runtime) |
| `Client_Base/` + `PC_Client/` | Java 8 / Ant | Desktop Swing/AWT client |
| `PC_Launcher/` | Java 8 / Ant | Auto-updating launcher |
| `Android_Client/` | Java / Gradle | Android port |
| `iOS_Client/` | Swift 5.9 / Xcode | Native iOS client |
| `2009scape-web/` | TS/JS + Docker | Separate rev-530 game (requires Docker) |
| `web-client/` | nginx | nginx template for hosting JS client |

## Replit Setup

### Runtime
- **Java**: GraalVM CE 22.3.1 (Java 19) — compatible with server/ (Java 8 target)
- **Build tool**: Apache Ant 1.10.15 (system dependency)
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
# Build core server
cd server && ant compile_core

# Build plugins
cd server && ant compile_plugins

# Run server manually
cd server && ant runserver -DconfFile=local -DcoloredLogging=false
```

## Note on Java 21 (server-java-modern)
The `server-java-modern/` directory requires Java 21. The current Replit environment provides Java 19 (GraalVM CE 22.3.1). To use it, upgrade to a Java 21 runtime when available.

## Connecting
Use the **RSC+ client** or the **OpenRSC desktop client** and connect to the server's host on TCP port **43594**.
