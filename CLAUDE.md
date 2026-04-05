# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenRSC is an open-source RuneScape Classic (RSC) server and client framework. It includes a primary Java game server, alternative server implementations in C# and Rust, and clients for desktop (Java), Android (Kotlin), and iOS (Swift).

## Build Commands

### Compile everything
```bash
make compile    # Runs: gradle classes (server) + ant compile (Client_Base + PC_Launcher)
```

### Java Server (Gradle, in `server/`)
```bash
cd server && gradle classes                    # Compile
cd server && gradle test                       # Run tests (JUnit 5)
cd server && gradle runServer                  # Run with default.conf
cd server && gradle runServer -DconfFile=local # Run with local.conf
cd server && gradle build                      # Build fat JAR
```

### Java Client (Ant, in `Client_Base/`)
```bash
ant -f Client_Base/build.xml compile     # Compile client
ant -f Client_Base/build.xml runclient   # Run client
```

### C# Server (`server-csharp/`)
```bash
cd server-csharp && dotnet build
cd server-csharp && dotnet test          # xUnit tests
```

### Rust Server (`server-rust/`)
```bash
cd server-rust && cargo build
cd server-rust && cargo test
cd server-rust && cargo bench            # Criterion benchmarks
```

### Database Setup
```bash
make create-mariadb db=<name>
make import-authentic-mariadb db=<name>     # Core schema
make import-custom-mariadb db=<name>        # Core + addon features
make import-authentic-sqlite db=<name>      # SQLite alternative
```

### Run Server + Client
```bash
make run-server    # Starts server via Deployment_Scripts/run.sh
make run-client    # Starts desktop client
```

## Architecture

### Server (`server/src/com/openrsc/server/`)

Entry point: `Server.java` - bootstraps Netty networking, loads configuration, starts game loop.

Key subsystems:
- **GameStateUpdater** - Main game tick loop (640ms default tick rate)
- **ServerConfiguration** - YAML config loading (`.conf` files in `server/`)
- **net/** - Netty TCP (port 43594) + WebSocket (port 43494) protocol handling. `RSCProtocolDecoder`/`RSCProtocolEncoder` for packet codec, `ActionSender` for outbound packets
- **model/** - Game entities: `Player`, `Npc`, `GroundItem`, `World`
- **database/** - `GameDatabase` interface with MySQL (`MySqlGameDatabase`) and SQLite (`SqliteGameDatabase`) implementations
- **event/** - `GameTickEvent` for tick-scheduled events, `ServerEvent` for delayed actions
- **plugins/** - Game content loaded by `PluginHandler`
- **infrastructure/** - Netty config, OpenTelemetry/Prometheus metrics, distributed tracing, Consul/etcd service discovery, MessagePack/FlatBuffers serialization
- **service/** - `PlayerService`, `PcapLoggerService`

### Plugin System (`server/plugins/com/openrsc/server/plugins/`)

Game content (quests, NPC behavior, item actions, skills) lives in plugins, organized as:
- `authentic/` - Official RSC content (commands, npcs, quests, skills, minigames)
- `custom/` - Added features (runecraft, clans, auction house)
- `retro/` - Legacy content variants
- `shared/` - Cross-variant utilities

### Client (`Client_Base/src/orsc/`)

Entry point: `OpenRSC.java`. Core game UI is in `mudclient.java` (large legacy file). `PacketHandler.java` processes incoming server packets.

### Configuration

Server configs are `.conf` files (YAML) in `server/`. `default.conf` has all settings. Override with named configs (`preservation.conf`, `local.conf`, etc.) selected via `-DconfFile=<name>`.

### Database

SQL schemas in `server/database/mysql/` and `server/database/sqlite/`. Core schema: `core.sql`. Addon features (clans, auction house, runecraft, etc.) in `addons/` subdirectory.

## Code Standards

- **Java indentation**: Tabs (not spaces) per `.editorconfig`
- **Java version**: 21 (server and client)
- **Line endings**: LF
- **YAML indentation**: 2 spaces
- **Branching**: Feature branches from `master`, merge via merge request
- **VCS**: Primary repo is on GitLab (orsc.dev), mirrored to GitHub

## Key Dependencies

**Server**: Netty 4.1 (networking + QUIC), HikariCP (connection pooling), Log4j2 with async loggers (Disruptor), Gson, OpenTelemetry, Prometheus/Micrometer, Consul/etcd, JDA (Discord bot), Guice (DI). JVM args: `-Xms2G -Xmx4G -XX:+UseG1GC`.

**Client**: Minimal dependencies - Discord RPC jar, custom rendering/networking code.
