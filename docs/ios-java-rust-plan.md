# iOS, Java Server, and Rust Server Plan

## Current iOS status

- The repository did not contain a real installable iOS app target. It was a Swift package with app-style source files.
- The Swift package could not resolve initially because `Tests/` was missing.
- The iOS client hardcoded `localhost:43594`, which is only correct in Simulator. On a physical iPhone, `localhost` points at the phone itself, not the Mac running the server.
- The app had several state-management bugs that prevented runtime flow:
  - `GameView` created a brand-new `NetworkClient` instead of using the connected one from app state.
  - The login screen only connected a TCP socket and never sent credentials.
  - The loading screen never completed because progress was never advanced.

## Validation results from April 3, 2026

- The iOS app now builds successfully as an iPhone app target with:
  - `xcodebuild build -project iOS_Client/OpenRSC/OpenRSC.xcodeproj -scheme OpenRSC -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
- A physical iPhone build attempt reached signing and provisioning, but installation is still blocked on this machine because Xcode does not have a usable Apple account/profile configured for the active development team.
- The attached iPhone can be reached by Xcode, so the remaining blocker for on-device install is provisioning rather than source compilation.
- The Mac's current LAN address is `192.168.0.54`, which is the address a physical iPhone would need to use instead of `localhost` when connecting to a server running on this Mac.

## Java server compatibility findings

- The Java server default world config listens on TCP `43594` and WebSocket `43494` in [server/default.conf](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/default.conf#L21).
- The bundled SQLite database is present at [server/inc/sqlite/preservation.db](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/inc/sqlite/preservation.db).
- The custom-client login format is:
  - `opcode 0`
  - reconnect flag byte
  - 4-byte `clientVersion`
  - line-feed-terminated username
  - line-feed-terminated password
  - 8-byte UID
  Reference: [LoginPacketHandler.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/LoginPacketHandler.java#L471)
- Client-to-server packets use a 2-byte length that excludes the length field.
  Reference: [Network_Base.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src/orsc/net/Network_Base.java#L187)
- Server-to-client packets use a 2-byte length that includes the length field.
  Reference: [RSCProtocolEncoderMain.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/RSCProtocolEncoderMain.java#L35)
- Login success/failure is sent as a raw single byte before framed world packets begin.
  Reference: [mudclient.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src/orsc/mudclient.java#L14510)

## Java server build status in this repo

- The Java server could not be started from source during validation.
- The Gradle build was blocked first by an incorrect QUIC dependency coordinate. That was corrected locally from `netty-incubator-codec-quic` to the published `netty-incubator-codec-classes-quic`.
- After that fix, the Gradle build still fails with two broader categories of issues:
  - missing dependencies in `build.gradle` for classes that the source imports (`Guice`, `JDA`, `emoji-java`, `gitlab4j`, `XStream`, `commons-lang`, `commons-compress`, and others)
  - source-level compile errors in the current Java codebase (for example direct field access against record-like types and duplicated exception variable names in `AvatarGenerator`)
- The older Ant-based scripts are also not runnable as committed because they expect `server/build.xml`, which is not present in the repository.
- Because the Java server is not currently runnable from source, the iOS client could not be fully tested end-to-end against a live Java world in this session.

## Why the iOS client still does not fully run the Java game yet

- The iOS app can be brought to a buildable state, but it is not yet protocol-complete enough to play the Java server end-to-end.
- Important packet mismatches remain:
  - `worldInfo` is currently treated like a login response in the iOS client, but the Java server sends five shorts.
    Reference: [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java#L800)
  - `playerCoords` and `npcCoords` are bit-packed in the Java server, but the iOS client currently reads them as plain shorts and bytes.
    Reference: [PayloadCustomGenerator.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/server/src/com/openrsc/server/net/rsc/generators/impl/PayloadCustomGenerator.java#L809)
  - The iOS client does not yet implement the initial config packet (`opcode 19`) or the broader set of custom-client capability/config packets that the Java client uses.

## Android-to-iOS port findings

- The Android app is mostly a platform wrapper. The actual game client behavior still lives in the shared Java code under [Client_Base/src](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src).
- That means the best parity oracle for the iOS port is the shared Java client, not the Android activity alone.
- The Android/shared client performs an initial server-config bootstrap before login:
  - it opens a socket
  - sends `opcode 19`
  - immediately parses the server config payload
  Reference: [mudclient.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src/orsc/mudclient.java#L16563)
- The shared client applies a very large config surface from that payload, including server name, welcome text, UI toggles, content toggles, custom-bank flags, equipment tab, parties, harvesting, right-click trade, sleep features, and many others.
  Reference: [PacketHandler.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src/orsc/PacketHandler.java#L929)
- The shared login packet sends more than username and password. After the UID, it also sends client limitation/capability data with `tellLimitations(...)`.
  Reference: [mudclient.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src/orsc/mudclient.java#L14415)
- The shared client decodes player and NPC coordinate updates with bit-packed reads, not simple byte/short reads.
  References:
  [PacketHandler.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src/orsc/PacketHandler.java#L1328)
  [PacketHandler.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src/orsc/PacketHandler.java#L1788)
- The Android wrapper also has a manual server-selection flow that writes `ip.txt` and `port.txt`, which is why Android local/LAN testing works more naturally than the current iOS port.
  Reference: [CacheUpdater.java](/Users/brandonjconover/Documents/GitHub/Core-Framework/Android_Client/Open RSC Android Client/src/main/java/com/openrsc/android/updater/CacheUpdater.java#L147)

## Highest-risk iOS gaps caused by the Android conversion

- Missing pre-login config bootstrap, which likely means the iOS client starts without the same feature flags and world settings the Java/Android client expects.
- Missing client capability payload in the login request, which can affect server-side compatibility negotiation.
- Incomplete packet coverage compared with the shared Java `PacketHandler`, especially for custom packets and entity/world update packets.
- Simplified entity-update decoding where the source client uses bit-packed parsing.
- Missing Android-era local/LAN server selection ergonomics for testing physical devices against a developer machine.

## Local_RSC reference-client findings

- [Local_RSC](/Users/brandonjconover/Documents/GitHub/Local_RSC) is not primarily an Electron app. It is a Vite/React mobile-web client with parallel C# core and Godot front-end experiments.
- It is valuable as a feature and UX reference, especially for mobile ergonomics and client architecture.
- It is not the right protocol source of truth for Java compatibility. Its React protocol layer currently assumes a simplified WebSocket-first model and several packet formats that do not match the shared Java client exactly.

### What is useful to port from Local_RSC

- Settings architecture
  - persistent settings categories for display, controls, mobile layout, accessibility, audio, and network
  - good reference files:
    - [SettingsContext.jsx](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/context/SettingsContext.jsx)
    - [SettingsService.js](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/services/SettingsService.js)
- Mobile gesture handling
  - swipe, long-press, swipe-action, and pinch-zoom behavior
  - good reference files:
    - [useGestures.js](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/hooks/useGestures.js)
    - [GestureRecognizer.cs](/Users/brandonjconover/Documents/GitHub/Local_RSC/csharp-client/RSCClient.Core/Input/GestureRecognizer.cs)
- Login and server-selection UX
  - separate connect/login states, remember-me behavior, status text, and cleaner host/port entry flows
  - good reference files:
    - [LoginPage.jsx](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/pages/LoginPage.jsx)
    - [LoginScreen.cs](/Users/brandonjconover/Documents/GitHub/Local_RSC/godot-client/scripts/ui/LoginScreen.cs)
- Modular screen/panel composition
  - chat, bank, trade, shop, quest, equipment, friends, and map panels that can inspire the SwiftUI structure
  - good reference files:
    - [GamePage.jsx](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/pages/GamePage.jsx)
    - [src/components/game](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/components/game)
- Event-driven client architecture
  - cleaner separation between network service, state manager, UI, and input systems
  - good reference files:
    - [GameContext.jsx](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/context/GameContext.jsx)
    - [GameClient.cs](/Users/brandonjconover/Documents/GitHub/Local_RSC/csharp-client/RSCClient.Core/GameClient.cs)
    - [GameManager.cs](/Users/brandonjconover/Documents/GitHub/Local_RSC/godot-client/scripts/autoload/GameManager.cs)

### What should not be ported blindly from Local_RSC

- The React/WebSocket protocol assumptions in:
  - [GameService.js](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/services/GameService.js)
  - [RSCProtocol.js](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/services/RSCProtocol.js)
  - [ProtocolAdapter.js](/Users/brandonjconover/Documents/GitHub/Local_RSC/src/services/ProtocolAdapter.js)
- Those files are useful as architecture references, but they currently diverge from the known-good Java client behavior in `Client_Base`.

### Best Local_RSC-inspired ports for the iOS app

1. Add a first-class settings model to the Swift client
- Include server host/port, remember-last-server, controls, UI layout, audio, and accessibility preferences.

2. Add a proper mobile gesture layer
- Support swipe-to-open panels, long-press interaction, and pinch-to-zoom in the game view.

3. Restructure the Swift app around clearer service/state boundaries
- Separate transport, protocol decoding, game state, and UI state more cleanly.

4. Port the better login/server UX
- Make local/LAN testing easy on physical iPhone hardware.
- Persist recent server targets and last-used account name locally.

5. Use the C# and Godot code as a modularity reference for future growth
- Especially if the Swift client starts to accumulate more panels and gameplay systems.

## Rust server status

- The Rust server has broad module coverage and strong infrastructure scaffolding, but it is still far from Java parity.
- Local validation currently fails before full compilation because `protoc` is missing for the `etcd-client` dependency.
  - `cargo check` failed on April 3, 2026 with: missing `protoc`
- There are visible placeholders/TODOs in core runtime paths:
  - authentication in [server-rust/src/session/handler.rs](/Users/brandonjconover/Documents/GitHub/Core-Framework/server-rust/src/session/handler.rs)
  - placeholder login handling in [server-rust/src/network/tcp.rs](/Users/brandonjconover/Documents/GitHub/Core-Framework/server-rust/src/network/tcp.rs)
  - placeholder password handling in [server-rust/src/game/auth.rs](/Users/brandonjconover/Documents/GitHub/Core-Framework/server-rust/src/game/auth.rs)

## What the Rust server still needs for parity

1. Protocol compatibility
- Implement the exact custom-client packet framing, raw login response, opcode mappings, and payload layouts used by the Java server.
- Add the legacy/authentic-client paths if true multi-protocol support is required.

2. Login and account flow
- Complete authentication, account loading, reconnect semantics, and capability negotiation.
- Match Java login response codes and world boot packets.

3. World loading and data parity
- Load the same world data, map data, config data, and database-backed content as the Java server.
- Reproduce Java-side entity definitions, world dimensions, and spawn data.

4. Plugin and scripting system
- Port or replace the Java plugin architecture so quests, NPC interactions, skills, commands, and minigames are data-driven or script-driven rather than hard-coded.

5. Game-content parity
- Port quest logic, NPC dialogue/interaction trees, item scripts, skilling actions, shops, combat behaviors, minigames, social systems, and admin/player commands.

6. Persistence and operational compatibility
- Match the Java database schema and migration behavior closely enough for existing world/account data.
- Finish cache, metrics, tracing, health, and discovery integration in a way that does not block local development.

## Recommended finish plan

### Phase 1: Make the iOS client a reliable developer app

- Keep a real Xcode project in-repo.
- Finish the custom-client bootstrap flow and connection UX.
- Port the `opcode 19` server-config bootstrap and apply the config fields needed for the current world.
- Port the client limitation payload sent during login.
- Implement packet decoders needed to reach a stable logged-in game state against the Java server.
- Add a server-address setting that defaults sensibly for Simulator and makes physical-device LAN testing straightforward.
- Acceptance criteria:
  - app installs on a physical iPhone
  - app can log in to the Java server
  - app stays connected without immediate protocol desync

### Phase 1.5: Restore a runnable Java parity server

- Decide on one supported Java build path and repair it fully.
- Minimum work:
  - restore the missing dependencies in `server/build.gradle`
  - fix the current Java compile errors
  - either remove the dead Ant launcher path or restore the missing Ant build file
- Acceptance criteria:
  - `gradle -p server runServer` starts a local world successfully
  - the server listens on `43594`
  - a local protocol smoke test can send a login packet and receive a valid login response byte

### Phase 2: Lock down a protocol contract

- Treat the Java custom-client protocol as the temporary source of truth.
- Use the shared Java client in [Client_Base/src](/Users/brandonjconover/Documents/GitHub/Core-Framework/Client_Base/src) as the behavioral reference implementation for the iOS port.
- Write packet-level docs and golden tests for:
  - config bootstrap (`opcode 19`)
  - login request
  - login response
  - world info
  - stats/inventory
  - player/npc/world updates
- Acceptance criteria:
  - Java server and a standalone protocol test harness agree on packet bytes

### Phase 3: Use the Java server as the parity oracle

- Build parity checklists by feature area:
  - auth
  - movement
  - chat/social
  - inventory/bank/shop
  - combat
  - skilling
  - quests/dialogue
- Acceptance criteria:
  - each feature area has packet captures, expected behavior, and test cases

### Phase 4: Bring the Rust server to protocol parity first

- Finish the Rust TCP/custom-client pipeline before broader content work.
- Make the Rust server speak the same client-visible protocol as Java for login and basic world boot.
- Acceptance criteria:
  - the iOS client can connect to Rust and receive the same boot/login packets as Java

### Phase 5: Port world loading and persistence

- Load world definitions, entity data, and player data from compatible sources.
- Reuse the Java database layout where possible to avoid inventing a second content system too early.
- Acceptance criteria:
  - a saved Java account can log into Rust and spawn into a valid world

### Phase 6: Port content through a scripting/plugin layer

- Build the scripting/plugin system before large-scale content migration.
- Port content in slices:
  - core login/tutorial
  - movement/world interactions
  - inventory/bank/shop
  - combat
  - skilling
  - quests/minigames/commands
- Acceptance criteria:
  - content additions no longer require deep server-core edits
