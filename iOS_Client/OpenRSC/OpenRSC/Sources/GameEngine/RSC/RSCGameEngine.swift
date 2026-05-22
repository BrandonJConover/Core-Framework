import Foundation
import Combine
import MetalKit

// Coordinates the RSC game loop: networking, packet handling, world state, and rendering.
// Matches the role of GameActivity.java + RSCBitmapSurfaceView on Android.
@MainActor
final class RSCGameEngine: ObservableObject {
    let worldState = RSCWorldState()
    let touchTranslator = TouchTranslator()
    let renderer = MetalRenderer()

    private let connection = TCPConnection()
    private let packetHandler = RSCPacketHandler()
    let landscapeLoader = LandscapeLoader()
    let spriteLoader = SpriteLoader()
    private var tickTimer: Timer?
    private var pingTimer: Timer?
    private var isRunning = false
    // landscapeLoader.isLoaded is used to check if terrain data is ready

    // Pixels rendered each tick — initially all black.
    private var pixelData = [Int32](repeating: 0, count: MetalRenderer.gameWidth * MetalRenderer.gameHeight)

    /// Combine subscriptions held by the engine. The worldState forward
    /// below relies on the cancellable staying alive for the engine's
    /// lifetime; dropping it would silently break SwiftUI updates.
    private var cancellables = Set<AnyCancellable>()

    // Camera/zoom state for mobile controls
    @Published var zoomLevel: CGFloat = 0.75 // 0.5 = zoomed out, 2.0 = zoomed in
    @Published var cameraAngle: CGFloat = 0.0 // degrees rotation

    // Render logging counter
    private var renderLogCount = 0

    // 3D rendering pipeline
    private var graphics: GraphicsController?
    private var scene: Scene?
    private var world: World?
    private var cameraX: Int32 = 0
    private var cameraY: Int32 = 0
    private var cameraZ: Int32 = 0
    // Camera angles use Java's 1024-unit convention (1024 = full revolution).
    // The Scene rotates by these in setCamera. Default pitch 64 = ~22.5°
    // looking down (matches mudclient.java default).
    private var cameraRotation: Int32 = 0
    private var cameraPitch: Int32 = 64
    private var cameraZoom: Int32 = 1600  // Java default: 750; native starts wider on phone screens
    private var cameraOcclusionZoom: Int32 = 1600

    /// Camera rotation in degrees (0..360). Read by gesture handlers in GameView.
    var cameraRotationDegrees: Double { Double(cameraRotation) * 360.0 / 256.0 }
    var cameraPitchDegrees: Double { Double(cameraPitch) * 360.0 / 256.0 }

    /// Set camera yaw from a degrees value (wraps mod 360). Used by pan gesture.
    func setCameraRotationDegrees(_ deg: Double) {
        var d = deg.truncatingRemainder(dividingBy: 360.0)
        if d < 0 { d += 360 }
        cameraRotation = Int32(d * 256.0 / 360.0) & 255
    }

    /// Set camera pitch from a degrees value, clamped to a sensible range so
    /// the player can't tip the camera fully upside-down.
    func setCameraPitchDegrees(_ deg: Double) {
        // Clamp to roughly 30°..80° (look-down only) — corresponds to pitch 21..57
        let clamped = max(30.0, min(80.0, deg))
        cameraPitch = Int32(clamped * 256.0 / 360.0) & 255
    }

    init() {
        worldState.preferences = UserPreferences.load()
        worldState.runEnabled = worldState.preferences.runByDefault
        applyPersistedCameraPreferences()
        packetHandler.worldState = worldState
        // Forward worldState's @Published changes into the engine's own
        // objectWillChange. GameView is @StateObject'd to the engine and
        // doesn't observe worldState directly, so without this its body
        // (which gates modal panels on flags like welcomeOpen) never
        // re-evaluates when those flags flip — it took an unrelated
        // engine-level publish to indirectly trigger a redraw, which is
        // why the welcome dialog appeared stuck open after dismiss.
        worldState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        connection.onPacket = { [weak self] opcode, payload in
            Task { @MainActor in
                self?.packetHandler.handlePacket(opcode: opcode, payload: payload)
            }
        }
        connection.onDisconnect = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.presentConnectionClosed("Disconnected from the server.")
            }
        }
        connection.onLoginResponse = { [weak self] code in
            let result = RSCLoginHandler.decodeLoginResponse(code)
            print("[Engine] Login result: \(result)")
            switch result {
            case .success(let playerID):
                self?.worldState.addChat(sender: "[System]", text: "Logged in (player \(playerID))")
            default:
                let msg = RSCLoginHandler.errorMessage(for: result)
                self?.worldState.addChat(sender: "[System]", text: "Login: \(msg)")
            }
        }

        touchTranslator.onTap = { [weak self] x, y in
            self?.handleTap(x: x, y: y)
        }
    }

    /// Mutates the live preferences mirror and flushes the result to
    /// UserDefaults. Future settings UI should use this as the only write path
    /// so observation and persistence stay in lockstep.
    func updatePreferences(_ mutate: (inout UserPreferences) -> Void) {
        var prefs = worldState.preferences
        mutate(&prefs)
        guard prefs != worldState.preferences else { return }
        worldState.preferences = prefs
        UserPreferences.save(prefs)
    }

    private func applyPersistedCameraPreferences() {
        let prefs = worldState.preferences
        if prefs.lastCameraYawDegrees != 0 {
            setCameraRotationDegrees(prefs.lastCameraYawDegrees)
            cameraAngle = CGFloat(prefs.lastCameraYawDegrees)
        }
        if prefs.lastCameraPitchDegrees != 0 {
            setCameraPitchDegrees(prefs.lastCameraPitchDegrees)
        }
        if prefs.lastCameraZoom > 0 {
            // Early native builds persisted Java-like 750 and later native
            // 1200-ish defaults, both of which feel cramped on a phone
            // viewport. Treat those default bands as "no preference" and
            // widen them to the current native default; preserve deliberate
            // wider/closer user changes outside those bands.
            let legacyDefault = (700.0...820.0).contains(prefs.lastCameraZoom)
                || (1050.0...1300.0).contains(prefs.lastCameraZoom)
            let rawZoom = legacyDefault ? 1600.0 : prefs.lastCameraZoom
            let persistedZoom = max(900.0, min(2400.0, rawZoom))
            cameraZoom = Int32(persistedZoom)
            cameraOcclusionZoom = Int32(persistedZoom)
            zoomLevel = CGFloat(1200.0 / persistedZoom)
        }
    }

    // Connect to server and send login packet.
    func start(server: ServerProfile, username: String, password: String, appState: AppState) async {
        // Server indexes can be reused across sessions. Clear transient world
        // state before connecting so stale appearances/entities cannot make
        // the local avatar borrow another player's gear while the first fresh
        // update packets are still arriving.
        worldState.playerAppearances = [:]
        worldState.players = []
        worldState.npcs = []
        worldState.groundItems = []
        worldState.gameObjects = []
        worldState.wallObjects = []
        worldState.midRegionBaseX = 0
        worldState.midRegionBaseZ = 0

        // Initialize 3D rendering pipeline
        let graphics = GraphicsController(width: Int32(MetalRenderer.gameWidth), height: Int32(MetalRenderer.gameHeight), spriteCount: 5000)
        let scene = Scene(graphics: graphics, modelCount: 25000, polyCount: 50000, spriteCount: 5000)
        let world = World(scene: scene, graphics: graphics)
        do { try ModelArchiveLoader.shared.loadModels(from: "") }
        catch { print("[Engine] Model archive load skipped: \(error)") }

        self.graphics = graphics
        self.scene = scene
        self.world = world

        // Start rendering immediately — shows terrain even before server connects
        isRunning = true
        startTickLoop()
        print("[Engine] Render loop started")

        // Load cache/definition data before connecting. The server sends
        // object/NPC/world packets immediately after login; if those packets
        // race ahead of GameObjectDefinitions/NPCDefinitions, the first scene
        // build can skip scenery until a later sector rebuild. Desktop
        // mudclient completes this cache bootstrap before entering the world,
        // so we do the same while the pre-login render loop is already alive.
        let loader = self.landscapeLoader
        let sprLoader = self.spriteLoader
        let sharedGraphics = graphics
        let sharedScene = scene
        await Task.detached(priority: .userInitiated) {
            loader.loadArchive()
            sprLoader.loadArchive()
            NPCDefinitions.loadArchive()
            NPCDefinitions.assignAnimationNumbers()
            GameObjectDefinitions.loadArchive()
        }.value
        // Bridge decoded sprites into GraphicsController atlas so
        // Scene.drawEntity() can draw them, and upload terrain texture pages
        // before the first world scene can be generated.
        sprLoader.bridgeInto(sharedGraphics)
        _ = sprLoader.loadTerrainTextures(into: sharedScene)
        print("[Engine] Archives loaded: landscape=\(loader.isLoaded) sprites=\(sprLoader.isLoaded) npcDefs=\(NPCDefinitions.defs.count) objDefs=\(GameObjectDefinitions.defs.count)")

        // Connect to server with timeout
        do {
            print("[Engine] Connecting to \(server.host):\(server.port)...")

            // Device launches can take a little longer to leave Network.framework's
            // setup path when the server is reachable only over VPN/bridge
            // routing. Keep the timeout finite, but long enough that a slightly
            // delayed `.ready` state does not race with our timeout task and
            // leave a half-connected socket delivering bytes after failure UI.
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.connection.connect(host: server.host, port: UInt16(server.port))
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 20_000_000_000)
                    throw NSError(domain: "OpenRSC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection timed out"])
                }
                // Wait for whichever finishes first
                try await group.next()
                group.cancelAll()
            }

            print("[Engine] Connected!")

            // Send login packet
            print("[Engine] Sending login for '\(username)'...")
            let loginData = RSCLoginHandler.encodeLogin(username: username, password: password)
            print("[Engine] Login packet (\(loginData.count) bytes)")

            connection.expectLoginResponse()
            try await connection.send(loginData)
            print("[Engine] Login packet sent")

            // Send ping every 5 seconds
            startPingLoop()
        } catch {
            print("[Engine] Connection failed: \(error)")
            connection.disconnect()
            worldState.addChat(sender: "[System]", text: "Connection failed: \(error.localizedDescription)")
            presentConnectionClosed("Connection failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        isRunning = false
        tickTimer?.invalidate()
        tickTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil
        connection.disconnect()
    }

    private func presentConnectionClosed(_ message: String) {
        isRunning = false
        tickTimer?.invalidate()
        tickTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil
        worldState.closeBlockingUIForConnectionClosed()
        worldState.connectionClosedText = message
        worldState.connectionClosedOpen = true
    }

    // MARK: - Game loop

    private func startTickLoop() {
        // RSC target: 50ms tick (20fps game logic), render at 30fps via MTKView
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    // Send ping (opcode 67) every 5 seconds — matches Java client mudclient.java:1583
    private func startPingLoop() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                let buf = ByteBuffer()
                buf.newPacket(opcode: 67)
                let data = buf.finishPacket()
                try? await self.connection.send(data)
            }
        }
    }

    private var terrainBuilt = false
    private var terrainBuiltAtTile: (Int, Int, Int) = (-1, -1, Int.min)
    /// Number of models in the scene that belong to the static terrain mesh.
    /// Anything past this index is per-frame ephemera (game objects). We
    /// truncate back to this on every tick before re-instantiating objects.
    private var terrainModelCount: Int = 0
    private var loggedMissingObjectModels = Set<String>()
    private let projectileMaxRange = 40

    private func tick() {
        guard isRunning else { return }
        // Decrement NPC combat/message timeouts. damageTimeout is the same
        // counter — left as combatTimeout in the struct for legacy reasons —
        // and the splat is drawn while it's > 150 (Java mudclient.java:6515).
        for i in 0..<worldState.npcs.count {
            if worldState.npcs[i].combatTimeout > 0 { worldState.npcs[i].combatTimeout -= 1 }
            if worldState.npcs[i].messageTimeout > 0 { worldState.npcs[i].messageTimeout -= 1 }
            if worldState.npcs[i].bubbleTimeout > 0 { worldState.npcs[i].bubbleTimeout -= 1 }
            if worldState.npcs[i].projectileRange > 0 { worldState.npcs[i].projectileRange -= 1 }
            if worldState.npcs[i].interpolationTicksRemaining > 0 {
                worldState.npcs[i].interpolationTicksRemaining -= 1
            }
        }
        // Decay player damage splat timeouts (set to 200 by opcode 234 case 2;
        // splat visible while > 150).
        for i in 0..<worldState.players.count {
            if worldState.players[i].damageTimeout > 0 { worldState.players[i].damageTimeout -= 1 }
            if worldState.players[i].bubbleTimeout > 0 { worldState.players[i].bubbleTimeout -= 1 }
            if worldState.players[i].projectileRange > 0 { worldState.players[i].projectileRange -= 1 }
            if worldState.players[i].messageTimeout > 0 { worldState.players[i].messageTimeout -= 1 }
            if worldState.players[i].interpolationTicksRemaining > 0 {
                worldState.players[i].interpolationTicksRemaining -= 1
            }
        }
        if worldState.localDamageTimeout > 0 { worldState.localDamageTimeout -= 1 }
        if worldState.localBubbleTimeout > 0 { worldState.localBubbleTimeout -= 1 }
        if worldState.localProjectileRange > 0 { worldState.localProjectileRange -= 1 }
        if worldState.localMessageTimeout > 0 { worldState.localMessageTimeout -= 1 }
        if worldState.walkTargetTimeout > 0 {
            // Drop the marker as soon as we step onto the tile; the
            // timeout is just a safety net for paths that get cancelled
            // by the server (NPC blocking the destination, etc).
            if worldState.localPlayerX == worldState.walkTargetX
                && worldState.localPlayerY == worldState.walkTargetY {
                worldState.walkTargetTimeout = 0
            } else {
                worldState.walkTargetTimeout -= 1
            }
        }
        for i in 0..<worldState.teleportBubbles.count {
            worldState.teleportBubbles[i].time += 1
        }
        worldState.teleportBubbles.removeAll { $0.time > 50 }
        // Wilderness check — Java mudclient.java:5326-5349. Positive
        // distance from the ditch (Z=2203) puts the player in PvP territory;
        // wilderness level scales every 6 tiles. Fire the once-per-session
        // warning when the player approaches the ditch (-10 .. 0 window).
        if worldState.localPlayerX != 0 || worldState.localPlayerY != 0 {
            let absZ = worldState.absoluteWorldZ(worldState.localPlayerY)
            let centerX = 2203 - absZ
            worldState.inWilderness = centerX > 0
            worldState.wildernessLevel = worldState.inWilderness ? max(1, centerX / 6 + 1) : 0
            if !worldState.wildernessWarningSeen, centerX > -10, centerX <= 0 {
                worldState.wildernessWarningOpen = true
                worldState.wildernessWarningSeen = true
            }
        }
        // Tick down the system-update countdown (50ms per tick = engine timer
        // interval). Banner hides automatically when it reaches 0.
        if worldState.systemUpdateTicks > 0 {
            worldState.systemUpdateTicks = max(0, worldState.systemUpdateTicks - 50)
        }
        if worldState.deathScreenTimeout > 0 {
            worldState.deathScreenTimeout -= 1
            if worldState.deathScreenTimeout == 0 {
                worldState.isDead = false
                worldState.addChat(sender: "[System]", text: "You have been granted another life. Be more careful this time!")
                worldState.addChat(sender: "[System]", text: "You retain your skills. Your objects land where you died.")
            }
        }
        worldState.pruneExpiredXPDrops()
        persistCameraPreferencesIfNeeded()

        // Real 3D Scene renderer (matches Java client mudclient.java render path):
        // - World generates a terrain mesh for the current region
        // - Scene projects + depth-sorts all polygons
        // - GraphicsController rasterizes into pixelData
        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY
        let havePos = (px != 0 || pz != 0)
        let landscapeReady = landscapeLoader.isLoaded

        if havePos && landscapeReady, let scene = self.scene, let graphics = self.graphics, let world = self.world {
            // Rebuild terrain mesh around the current player tile. The mesh is
            // generated in player-local coordinates (tile offset -half...half),
            // while actors are also rendered relative to the current player.
            // If we only rebuild on region-base shifts, walking inside a region
            // leaves terrain anchored to the previous player tile and actors
            // appear to drift across the wrong ground.
            let secX = worldState.midRegionBaseX / 48
            let secZ = worldState.midRegionBaseZ / 48
            let plane = worldState.requestedPlane
            let absX = worldState.absoluteWorldX(px)
            let absZ = worldState.absoluteWorldZ(pz)
            if !terrainBuilt || terrainBuiltAtTile != (absX, absZ, plane) {
                world.landscapeLoader = landscapeLoader
                // Clear previously-added landscape models so we don't accumulate
                for i in 0..<scene.modelCount { scene.models[i] = nil }
                scene.modelCount = 0
                world.loadSections(worldX: absX, worldZ: absZ, plane: plane)
                terrainBuilt = true
                terrainBuiltAtTile = (absX, absZ, plane)
                terrainModelCount = scene.modelCount
                worldState.loadingArea = false
                print("[Engine] Terrain mesh built for sector (\(secX),\(secZ)) plane=\(plane) at abs (\(absX),\(absZ)); scene has \(scene.modelCount) models")
            }

            // Game-object 3D models. Mirrors PacketHandler.gotObjectsPacket()
            // in the Java client: clone from the model archive, rotate by
            // direction*32 (256-space yaw), translate to (tileX, -elevation,
            // tileZ) in the *player-local* coord frame the terrain mesh uses.
            //
            // We rebuild this list every tick because the Scene model array
            // is shared with the terrain mesh (which we don't want to reparse
            // each frame). Truncating back to `terrainModelCount` keeps
            // memory bounded.
            if scene.modelCount > terrainModelCount {
                for i in terrainModelCount..<scene.modelCount { scene.models[i] = nil }
                scene.modelCount = terrainModelCount
            }
            for obj in worldState.gameObjects {
                let dx = obj.x - px       // tile-local X relative to player
                let dz = obj.y - pz       // (worldState uses y for the world Z axis)
                // Cull anything outside the terrain footprint (terrain is
                // generated for ~half a sector around the player).
                guard World.isTileOffsetInsideGeneratedTerrain(dx: dx, dz: dz) else { continue }

                let def = GameObjectDefinitions.get(obj.objectId)
                let modelName = def?.modelID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard shouldRenderObjectModel(modelName) else { continue }
                guard ModelArchiveLoader.shared.getModel(named: modelName) != nil else {
                    logMissingObjectModel(modelName, objectId: obj.objectId, objectName: def?.name)
                    continue
                }

                let width = def?.width ?? 1
                let height = def?.height ?? 1
                let placement = rotatedObjectFootprint(width: width, height: height, direction: obj.direction)

                // Y-elevation in world coords: terrain-mesh Y is negative-up,
                // and World.getElevation expects world coords. The mesh is
                // built in player-local space so we pass dx/dz scaled by
                // tileSize (128) for elevation lookup.
                let xWorld = (dx * 2 + placement.width) * 128 / 2
                let zWorld = (dz * 2 + placement.height) * 128 / 2
                let elevation = world.getElevation(x: xWorld, z: zWorld)

                let model = ModelArchiveLoader.shared.instantiate(
                    named: modelName,
                    atTileX: dx, atTileZ: dz,
                    direction: obj.direction,
                    width: width, height: height,
                    elevation: elevation,
                    scene: scene
                )
                Self.applyJavaObjectLighting(to: model)
                // Java mudclient.java:14361 applies a special vertical offset
                // to object id 74 after placement. Keep this outside
                // ModelArchiveLoader so the avoid-owned loader remains a pure
                // archive/instantiate boundary.
                if obj.objectId == 74 {
                    model.translate2(0, -480, 0)
                }
            }
            for wall in worldState.wallObjects {
                let dx = wall.x - px
                let dz = wall.y - pz
                guard World.isTileOffsetInsideGeneratedTerrain(dx: dx, dz: dz) else { continue }
                if let model = makeBoundaryWallModel(tileX: dx, tileZ: dz, direction: wall.direction, wallId: wall.wallId, world: world) {
                    scene.addModel(model)
                }
            }

            // Camera setup. Terrain tiles are quads from tileOffset*128 to
            // tileOffset*128+128, and actors/taps use tile centers at +64.
            // Center the camera on that tile center so the local player,
            // terrain, and hit-testing share one frame.
            let desiredZoom = Int32(1200.0 / max(0.5, min(3.0, Double(zoomLevel))))
            cameraZoom = cameraZoomWithOcclusion(desiredZoom)
            let cameraY: Int32 = 180  // height above ground
            let playerGroundY = Int32(world.getElevation(x: 64, z: 64))
            scene.fogLandscapeDistance = cameraZoom * 6
            scene.setCamera(
                centerX: 64,
                centerY: -playerGroundY - cameraY,
                centerZ: 64,
                xRot: cameraPitch * 4,
                yRot: cameraRotation * 4,
                zRot: 0,
                offset: cameraZoom * 2
            )

            // Register character billboards so they composite in with terrain.
            // Must happen AFTER setCamera (so projectPoint uses fresh matrices)
            // and BEFORE endScene (so drawSprite sees them).
            scene.reduceSprites(0)  // clear any stale billboard entries

            // Default starter-avatar sprites for other players (head1, body1, legs1).
            // Used until opcode 234 case 5 delivers the player's actual layerAnimation.
            let defaultPlayerSprites = [0, 1, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1]
            // Default starter palette indices (Java mudclient defaults from
            // appearance creation: hair=2 light brown, top=8 light blue,
            // bottom=8 light blue, skin=0 fair).
            let defaultHairIdx = 2, defaultTopIdx = 8, defaultBottomIdx = 8, defaultSkinIdx = 0

            // Characters are registered in the same player-local coord frame as
            // the terrain mesh — so NPC tile offsets are (npc.x - px, npc.y - pz).
            // NPCs in active combat (combatTimeout > 0) render with combat-A
            // animation frames; the player's combat counterpart goes to B.
            // Java mudclient.java drives combatRole off ORSCharacterDirection;
            // we approximate via the combatTimeout flag set when fighting.
            let combatTick = renderLogCount  // shared frame counter for combat cycle
            func elevationForTileOffset(tileX: Double, tileZ: Double) -> Int {
                let localX = Int((tileX * 128.0).rounded()) + 64
                let localZ = Int((tileZ * 128.0).rounded()) + 64
                return world.getElevation(x: localX, z: localZ)
            }
            for npc in worldState.npcs {
                if let def = NPCDefinitions.get(npc.npcId) {
                    let role: CharacterBillboards.CombatRole = npc.combatTimeout > 0 ? .combatA : .none
                    let tileX = npc.interpolatedX - Double(px)
                    let tileZ = npc.interpolatedY - Double(pz)
                    var sprites = def.sprites
                    if npc.wield > 0 {
                        if sprites.count <= 4 { sprites += Array(repeating: -1, count: 5 - sprites.count) }
                        sprites[4] = npc.wield
                    }
                    if npc.wield2 > 0 {
                        if sprites.count <= 10 { sprites += Array(repeating: -1, count: 11 - sprites.count) }
                        sprites[10] = npc.wield2
                    }
                    CharacterBillboards.register(
                        scene: scene, spriteLoader: spriteLoader,
                        tileX: tileX,
                        tileZ: tileZ,
                        rsDir: npc.direction,
                        stepFrame: role == .none ? renderLogCount : combatTick,
                        walkModel: def.walkModel,
                        cameraRotation: cameraRotation,
                        sprites: sprites,
                        hairColor: Int32(def.hairColour),
                        topColor: Int32(def.topColour),
                        bottomColor: Int32(def.bottomColour),
                        skinColor: Int32(def.skinColour),
                        combatRole: role,
                        combatModel: def.combatModel,
                        combatSprite: def.combatSprite,
                        overlayMovement: 32,  // small lean while attacking
                        elevation: elevationForTileOffset(tileX: tileX, tileZ: tileZ)
                    )
                }
            }
            // Per-player avatar: prefer the real appearance from opcode 234
            // case 5 when we've received it; else fall back to the starter
            // palette + sprite triplet so the slot still renders something.
            for player in worldState.players {
                let appearance = worldState.playerAppearances[player.id]
                let sprites: [Int] = appearance.map { app in
                    app.layerSprites.map(Self.appearanceAnimationIndex)
                } ?? defaultPlayerSprites
                let hairIdx = appearance?.colourHair ?? defaultHairIdx
                let topIdx = appearance?.colourTop ?? defaultTopIdx
                let bottomIdx = appearance?.colourBottom ?? defaultBottomIdx
                let skinIdx = appearance?.colourSkin ?? defaultSkinIdx
                let colourTransform = playerColourTransform(for: appearance)
                let tileX = player.interpolatedX - Double(px)
                let tileZ = player.interpolatedY - Double(pz)
                CharacterBillboards.register(
                    scene: scene, spriteLoader: spriteLoader,
                    tileX: tileX,
                    tileZ: tileZ,
                    rsDir: player.direction, stepFrame: renderLogCount,
                    walkModel: 6,
                    cameraRotation: cameraRotation,
                    sprites: sprites,
                    hairColor: PlayerPalettes.hairColour(hairIdx),
                    topColor: PlayerPalettes.clothingColour(topIdx),
                    bottomColor: PlayerPalettes.clothingColour(bottomIdx),
                    skinColor: PlayerPalettes.skinColour(skinIdx),
                    colourTransform: colourTransform,
                    elevation: elevationForTileOffset(tileX: tileX, tileZ: tileZ)
                )
            }
            // Local player sits at the origin in local coords. When the engine
            // is in combat with a tracked target, render in the combatB pose so
            // the player faces the NPC mid-fight.
            let localCombatRole: CharacterBillboards.CombatRole = worldState.inCombat ? .combatB : .none
            if worldState.localAppearanceAwaitingRefresh && renderLogCount % 120 == 0 {
                print("[Appearance] waiting for local opcode 234 case 5 after equipment/inventory change")
            }
            if let localApp = worldState.playerAppearances[worldState.playerServerIndex] {
                let localSprites = localApp.layerSprites.map(Self.appearanceAnimationIndex)
                CharacterBillboards.register(
                    scene: scene, spriteLoader: spriteLoader,
                    tileX: 0, tileZ: 0,
                    rsDir: worldState.localPlayerDirection, stepFrame: renderLogCount,
                    walkModel: 6,
                    cameraRotation: cameraRotation,
                    sprites: localSprites,
                    hairColor: PlayerPalettes.hairColour(localApp.colourHair),
                    topColor: PlayerPalettes.clothingColour(localApp.colourTop),
                    bottomColor: PlayerPalettes.clothingColour(localApp.colourBottom),
                    skinColor: PlayerPalettes.skinColour(localApp.colourSkin),
                    colourTransform: playerColourTransform(for: localApp),
                    combatRole: localCombatRole,
                    combatModel: 6,
                    combatSprite: 5,
                    overlayMovement: 32,
                    elevation: elevationForTileOffset(tileX: 0, tileZ: 0)
                )
            }

            scene.endScene(1)

            // Copy graphics output into our buffer for Metal upload
            if graphics.pixelData.count == pixelData.count {
                pixelData = graphics.pixelData
            }

            // HUD overlay — info bar + player marker + label
            drawHUDOverlay()

            renderLogCount += 1
            if renderLogCount <= 5 || renderLogCount % 120 == 0 {
                print("[Render] Scene tick=\(renderLogCount) pos=(\(px),\(pz)) models=\(scene.modelCount)")
            }
        } else {
            // No player position yet — fall back to overhead map placeholder
            renderWorld()
        }

        // Upload to Metal texture
        renderer.updatePixels(pixelData)
    }

    private func playerColourTransform(for appearance: RSCPlayerAppearance?) -> Int32 {
        var transform = UInt32(0xFFFFFFFF)
        if appearance?.isInvisible == true {
            transform &= 0x80FFFFFF
        }
        if appearance?.isInvulnerable == true {
            transform &= 0xFF202020
        }
        return Int32(bitPattern: transform)
    }

    static func appearanceAnimationIndex(_ id: Int) -> Int {
        // Server player appearance layers are 1-based. Java's drawPlayer uses
        // `layerAnimation[mappedLayer] - 1`; rendering the raw id shifts boots
        // into full helms and shields into crossbows.
        id <= 0 ? -1 : id - 1
    }

    private func shouldRenderObjectModel(_ modelName: String) -> Bool {
        let key = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !key.isEmpty && key != "na"
    }

    private func logMissingObjectModel(_ modelName: String, objectId: Int, objectName: String?) {
        let key = "\(objectId):\(modelName.lowercased())"
        guard loggedMissingObjectModels.insert(key).inserted else { return }
        let displayName = objectName.map { " '\($0)'" } ?? ""
        print("[Models] missing object model '\(modelName)' for object \(objectId)\(displayName)")
    }

    private func rotatedObjectFootprint(width: Int, height: Int, direction: Int) -> (width: Int, height: Int) {
        if direction == 0 || direction == 4 {
            return (width, height)
        }
        return (height, width)
    }

    static func applyJavaObjectLighting(to model: RSModel) {
        model.setDiffuseLightAndColor(-50, -10, -50, 48, 48, true, 117)
    }

    static func boundaryWallTileEndpoints(tileX: Double, tileZ: Double, direction: Int) -> (start: (x: Double, z: Double), end: (x: Double, z: Double)) {
        switch direction & 3 {
        case 0:
            return ((tileX, tileZ), (tileX + 1.0, tileZ))
        case 1:
            return ((tileX, tileZ), (tileX, tileZ + 1.0))
        case 2:
            return ((tileX + 1.0, tileZ), (tileX, tileZ + 1.0))
        default:
            return ((tileX, tileZ), (tileX + 1.0, tileZ + 1.0))
        }
    }

    private func makeBoundaryWallModel(tileX: Int, tileZ: Int, direction: Int, wallId: Int, world: World) -> RSModel? {
        let tileSize = 128
        let tileEndpoints = Self.boundaryWallTileEndpoints(tileX: Double(tileX), tileZ: Double(tileZ), direction: direction)
        let endpoints = (
            (Int(tileEndpoints.start.x * Double(tileSize)), Int(tileEndpoints.start.z * Double(tileSize))),
            (Int(tileEndpoints.end.x * Double(tileSize)), Int(tileEndpoints.end.z * Double(tileSize)))
        )

        let y0 = -world.getElevation(x: endpoints.0.0, z: endpoints.0.1)
        let y1 = -world.getElevation(x: endpoints.1.0, z: endpoints.1.1)
        let height = boundaryWallHeight(wallId: wallId)
        let model = RSModel(vertexCount: 4, faceCount: 1)
        let v0 = model.insertVertex(x: Int32(endpoints.0.0), y: Int32(y0), z: Int32(endpoints.0.1))
        let v1 = model.insertVertex(x: Int32(endpoints.0.0), y: Int32(y0 - height), z: Int32(endpoints.0.1))
        let v2 = model.insertVertex(x: Int32(endpoints.1.0), y: Int32(y1 - height), z: Int32(endpoints.1.1))
        let v3 = model.insertVertex(x: Int32(endpoints.1.0), y: Int32(y1), z: Int32(endpoints.1.1))
        guard v0 >= 0, v1 >= 0, v2 >= 0, v3 >= 0 else { return nil }

        let resources = boundaryWallFaceResources(wallId: wallId)
        model.insertFace(count: 4, indices: [v0, v1, v2, v3],
                         texFront: resources.front, texBack: resources.back)
        model.setDiffuseLightAndColor(-50, -10, -50, 60, 24, false, -95)
        model.m_Yb = 1
        return model
    }

    private func boundaryWallHeight(wallId: Int) -> Int {
        EntityDefinitions.getDoorDef(wallId)?.wallObjectHeight ?? 100
    }

    private func boundaryWallColor(wallId: Int) -> Int32 {
        let name = (EntityDefinitions.getDoorDef(wallId)?.name ?? "").lowercased()
        if name.contains("gate") || name.contains("door") {
            return Int32(bitPattern: 0xFF7A5230)
        }
        return Int32(bitPattern: 0xFF6B6254)
    }

    private func boundaryWallFaceResources(wallId: Int) -> (front: Int32, back: Int32) {
        let fallback = boundaryWallColor(wallId: wallId)
        guard let def = EntityDefinitions.getDoorDef(wallId) else {
            return (fallback, fallback)
        }

        // Java createWallObjectModel feeds DoorDef.modelVar2/modelVar3
        // straight into insertFace as front/back texture resources. The
        // native renderer also needs a packed-colour fallback for ids whose
        // texture pages are not available yet, so keep the visible front face
        // stable and expose the Java texture candidate through texBack.
        let front = def.frontTexture >= 0 ? Int32(def.frontTexture) : fallback
        let back = def.backTexture >= 0 ? Int32(def.backTexture) : fallback
        if front == 0 && back == 0 {
            return (fallback, fallback)
        }
        return (fallback, back)
    }

    // HUD overlay drawn on top of the 3D scene: coordinates bar + player center marker.
    // Kept separate from the Scene so the info layer doesn't get cleared each frame.
    private func drawHUDOverlay() {
        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight
        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY
        let absX = worldState.absoluteWorldX(px)
        let absZ = worldState.absoluteWorldZ(pz)

        // Top info bar
        for y in 0..<12 {
            for x in 0..<w { pixelData[y * w + x] = Int32(bitPattern: 0xCC000000) }
        }
        drawText("(\(absX),\(absZ)) NPC\(worldState.npcs.count) OBJ\(worldState.gameObjects.count)", x: 4, y: 3, color: 0xFFFFFFFF)

        // Player center marker so we can always find the camera target
        let cx = w / 2
        let cy = h / 2
        let ringR = 12
        let ringColor: Int32 = (renderLogCount / 8) % 2 == 0 ? Int32(bitPattern: 0xFF00FF44) : Int32(bitPattern: 0xFF88FF99)
        for angleDeg in stride(from: 0, to: 360, by: 8) {
            let rad = Double(angleDeg) * .pi / 180.0
            let rx = cx + Int(Double(ringR) * cos(rad))
            let ry = cy + Int(Double(ringR) * 0.4 * sin(rad))
            if rx >= 0 && rx < w && ry >= 0 && ry < h {
                pixelData[ry * w + rx] = ringColor
            }
        }
        let pn = worldState.localPlayerName.isEmpty ? "YOU" : worldState.localPlayerName.uppercased()
        drawText(pn, x: cx - pn.count * 2, y: cy - 20, color: 0xFFFFFF00)

        // Bottom-right wilderness chip — Java client puts this where the
        // skull sprite + "Wilderness / Level: N" text sits at gameWidth-47
        // (mudclient.java:5335-5339). Until SoundManager-managed sprites
        // include the skull, we mock it with a small dark capsule.
        if worldState.inWilderness {
            let chipW = 60
            let chipH = 24
            let cxR = w - chipW - 4
            let cyB = h - chipH - 4
            let bg = Int32(bitPattern: 0xCC1A0000)
            let border = Int32(bitPattern: 0xFFFFFF00)
            for ry in 0..<chipH {
                for rx in 0..<chipW {
                    let sx = cxR + rx
                    let sy = cyB + ry
                    if sx < 0 || sx >= w || sy < 0 || sy >= h { continue }
                    let onEdge = ry == 0 || ry == chipH - 1 || rx == 0 || rx == chipW - 1
                    pixelData[sy * w + sx] = onEdge ? border : bg
                }
            }
            drawText("WILD", x: cxR + 4, y: cyB + 4, color: 0xFFFFFF00)
            drawText("LVL \(worldState.wildernessLevel)", x: cxR + 4, y: cyB + 13, color: 0xFFFFFF00)
        }

        drawProjectiles()
        drawTeleportBubbles()
        drawGroundItems3D()
        drawWalkTargetMarker()
        drawOverheadItemBubbles()
        drawSkullIndicators()
        drawDamageSplats()
        drawChatBubbles()
    }

    /// Mobile tap feedback: a small fading X on the server walk target. This
    /// intentionally uses Scene.projectPoint rather than a second projection
    /// approximation, so the marker lines up with the same camera as characters.
    private func drawWalkTargetMarker() {
        guard worldState.walkTargetTimeout > 0, let scene = self.scene else { return }
        let dx = worldState.walkTargetX - worldState.localPlayerX
        let dz = worldState.walkTargetY - worldState.localPlayerY
        guard abs(dx) <= 32 && abs(dz) <= 32 else { return }

        let proj = scene.projectPoint(
            worldX: Int32(dx) * 128 + 64,
            worldY: 0,
            worldZ: Int32(dz) * 128 + 64
        )
        guard proj.depth >= scene.rot1024_zTop else { return }

        let alpha = max(64, min(255, worldState.walkTargetTimeout * 4))
        let color = (UInt32(alpha) << 24) | 0x00FF3333
        let x = Int(proj.screenX)
        let y = Int(proj.screenY)
        let r = 6 + (renderLogCount / 6) % 3
        drawLine(x0: x - r, y0: y - r / 2, x1: x + r, y1: y + r / 2, color: color)
        drawLine(x0: x - r, y0: y + r / 2, x1: x + r, y1: y - r / 2, color: color)
    }

    /// Draws dropped ground items in the live 3D view. The packet handler was
    /// already retaining opcode 99, but the Scene path only showed those items
    /// on the minimap/fallback map. This projects the tile centre through the
    /// active camera and uses the Java item sprite range (spriteItem + itemId)
    /// when available, falling back to a small pickup marker plus short label.
    private func drawGroundItems3D() {
        guard let scene = self.scene else { return }
        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY
        for item in worldState.groundItems {
            let dx = item.x - px
            let dz = item.y - pz
            guard abs(dx) <= 32 && abs(dz) <= 32 else { continue }
            let proj = scene.projectPoint(
                worldX: Int32(dx) * 128 + 64,
                worldY: -8,
                worldZ: Int32(dz) * 128 + 64
            )
            guard proj.depth >= scene.rot1024_zTop else { continue }
            drawGroundItemMarker(
                itemId: item.itemId,
                amount: item.amount,
                centerX: Int(proj.screenX),
                centerY: Int(proj.screenY)
            )
        }
    }

    private func drawGroundItemMarker(itemId: Int, amount: Int, centerX: Int, centerY: Int) {
        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight
        let spriteId = 2150 + itemId
        if let gs = spriteLoader.getSprite(spriteId), gs.width <= 32, gs.height <= 32 {
            spriteLoader.drawSprite(
                spriteId,
                onto: &pixelData,
                bufferWidth: w,
                bufferHeight: h,
                atX: centerX - gs.width / 2,
                atY: centerY - gs.height / 2,
                scale: 1
            )
            if amount > 1 {
                let suffix = amount >= 1_000 ? "\(amount / 1_000)K" : "\(amount)"
                drawText(suffix, x: centerX + 4, y: centerY + 2, color: 0xFFFFFF00)
            }
            return
        }

        let outline = Int32(bitPattern: 0xFF000000)
        let fill = Int32(bitPattern: 0xFFFF3333)
        for dy in -4...4 {
            let span = 4 - abs(dy)
            for dx in -span...span {
                let sx = centerX + dx
                let sy = centerY + dy
                guard sx >= 0 && sx < w && sy >= 0 && sy < h else { continue }
                pixelData[sy * w + sx] = abs(dy) == 4 || abs(dx) == span ? outline : fill
            }
        }
        let name = ItemNames.name(for: itemId)
        let label = name == "Item" ? "\(itemId)" : String(name.prefix(10))
        drawText(label, x: centerX - label.count * 2, y: centerY + 7, color: 0xFFFF6666)
    }

    /// Floats short chat messages above NPCs and players, mirroring Java's
    /// drawCharacterOverlay path for `messageTimeout > 0`. The message
    /// projects through the same Scene camera the billboards use so the
    /// bubble tracks the speaker even as the camera rotates.
    private func drawChatBubbles() {
        guard let scene = self.scene else { return }
        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY

        for npc in worldState.npcs where npc.messageTimeout > 0 && !npc.message.isEmpty {
            drawCharacterChatBubble(
                scene: scene,
                tileX: npc.x - px,
                tileZ: npc.y - pz,
                text: npc.message,
                hasItemBubble: npc.bubbleTimeout > 0 && npc.bubbleItem >= 0
            )
        }

        for player in worldState.players where player.messageTimeout > 0 && !player.message.isEmpty {
            drawCharacterChatBubble(
                scene: scene,
                tileX: player.x - px,
                tileZ: player.y - pz,
                text: player.message,
                hasItemBubble: player.bubbleTimeout > 0 && player.bubbleItem >= 0
            )
        }

        if worldState.localMessageTimeout > 0 && !worldState.localMessage.isEmpty {
            drawChatBubble(
                centerX: MetalRenderer.gameWidth / 2,
                bottomY: worldState.localBubbleTimeout > 0 && worldState.localBubbleItem >= 0
                    ? MetalRenderer.gameHeight / 2 - 50
                    : MetalRenderer.gameHeight / 2 - 30,
                text: worldState.localMessage
            )
        }
    }

    private func drawCharacterChatBubble(scene: Scene, tileX: Int, tileZ: Int, text: String, hasItemBubble: Bool) {
        guard abs(tileX) <= 32 && abs(tileZ) <= 32 else { return }
        let proj = scene.projectPoint(
            worldX: Int32(tileX) * 128 + 64,
            worldY: hasItemBubble ? -120 : -150,
            worldZ: Int32(tileZ) * 128 + 64
        )
        if proj.depth < scene.rot1024_zTop { return }
        // Item bubbles draw from topY = projectedY - 20 and are 24px tall.
        // When both overlays are present, use that top edge as the chat
        // baseline so the caption stacks above the item icon instead of
        // crossing through it.
        let bottomY = hasItemBubble ? Int(proj.screenY) - 22 : Int(proj.screenY)
        drawChatBubble(centerX: Int(proj.screenX), bottomY: bottomY, text: text)
    }

    /// Caption-bar above a head: dark translucent backing, light gold text,
    /// truncated at ~32 chars to keep it readable through the small font.
    private func drawChatBubble(centerX: Int, bottomY: Int, text: String) {
        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight
        let trimmed = String(text.prefix(32))
        let glyphW = 4   // 3px font + 1px tracking
        let textW = max(0, trimmed.count * glyphW - 1)
        let padX = 3
        let padY = 2
        let boxW = textW + padX * 2
        let boxH = 5 + padY * 2  // 5px font height
        let boxX = centerX - boxW / 2
        let boxY = bottomY - boxH - 2  // float above the projected anchor
        let bg = Int32(bitPattern: 0xCC101010)
        let border = Int32(bitPattern: 0xFFC8A951)
        for ry in 0..<boxH {
            for rx in 0..<boxW {
                let sx = boxX + rx
                let sy = boxY + ry
                if sx < 0 || sx >= w || sy < 0 || sy >= h { continue }
                let onEdge = ry == 0 || ry == boxH - 1 || rx == 0 || rx == boxW - 1
                pixelData[sy * w + sx] = onEdge ? border : bg
            }
        }
        drawText(trimmed, x: boxX + padX, y: boxY + padY, color: 0xFFFFEFA8)
    }

    /// Draw teleport/telegrab-style bubbles from opcode 36. Java keeps these
    /// for 50 ticks and draws an expanding fading circle; type 0 is blue-ish,
    /// type 1 is red-ish.
    private func drawTeleportBubbles() {
        guard let scene = self.scene else { return }
        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY

        for bubble in worldState.teleportBubbles {
            let dx = bubble.x - px
            let dz = bubble.y - pz
            guard abs(dx) <= 32 && abs(dz) <= 32 else { continue }

            let proj = scene.projectPoint(
                worldX: Int32(dx) * 128 + 64,
                worldY: 0,
                worldZ: Int32(dz) * 128 + 64
            )
            if proj.depth < scene.rot1024_zTop { continue }

            let radius = bubble.type == 0 ? 20 + bubble.time * 2 : 10 + bubble.time
            let alpha = max(0, 255 - bubble.time * 5)
            let color = bubble.type == 0
                ? UInt32(0x0000FF + bubble.time * 0x0500)
                : UInt32(0xFF0000 + bubble.time * 0x0500)
            drawCircleOutline(centerX: Int(proj.screenX), centerY: Int(proj.screenY), radius: radius, rgb: color, alpha: alpha)
        }
    }

    /// Draw skull markers over skulled players/NPCs. Mirrors Java's overlay
    /// rule that player skulls hide while an item bubble is active; NPC skulls
    /// are shown whenever their skull flag is positive.
    private func drawSkullIndicators() {
        guard let scene = self.scene else { return }
        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY

        for npc in worldState.npcs where npc.skullVisible > 0 {
            let dx = npc.x - px
            let dz = npc.y - pz
            guard abs(dx) <= 32 && abs(dz) <= 32 else { continue }
            let proj = scene.projectPoint(
                worldX: Int32(dx) * 128 + 64,
                worldY: -142,
                worldZ: Int32(dz) * 128 + 64
            )
            if proj.depth < scene.rot1024_zTop { continue }
            drawSkullMarker(centerX: Int(proj.screenX), centerY: Int(proj.screenY) - 12, red: npc.skullVisible == 2)
        }

        for player in worldState.players {
            guard let appearance = worldState.playerAppearances[player.id],
                  appearance.skulled,
                  player.bubbleTimeout == 0 else { continue }
            let dx = player.x - px
            let dz = player.y - pz
            guard abs(dx) <= 32 && abs(dz) <= 32 else { continue }
            let proj = scene.projectPoint(
                worldX: Int32(dx) * 128 + 64,
                worldY: -142,
                worldZ: Int32(dz) * 128 + 64
            )
            if proj.depth < scene.rot1024_zTop { continue }
            drawSkullMarker(centerX: Int(proj.screenX), centerY: Int(proj.screenY) - 12, red: false)
        }

        if let localAppearance = worldState.playerAppearances[worldState.playerServerIndex],
           localAppearance.skulled,
           worldState.localBubbleTimeout == 0 {
            drawSkullMarker(
                centerX: MetalRenderer.gameWidth / 2,
                centerY: MetalRenderer.gameHeight / 2 - 52,
                red: false
            )
        }
    }

    private func drawSkullMarker(centerX: Int, centerY: Int, red: Bool) {
        let spriteId = 2013 // mudclient.spriteMedia + 13, GUI skull
        if let gs = spriteLoader.getSprite(spriteId), gs.width <= 24, gs.height <= 24 {
            spriteLoader.drawSprite(
                spriteId,
                onto: &pixelData,
                bufferWidth: MetalRenderer.gameWidth,
                bufferHeight: MetalRenderer.gameHeight,
                atX: centerX - gs.width / 2,
                atY: centerY - gs.height / 2,
                scale: 1
            )
            return
        }

        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight
        let color = Int32(bitPattern: red ? 0xFFFF3333 : 0xFFFFFFFF)
        let outline = Int32(bitPattern: 0xFF000000)
        let rows = [
            "01110",
            "11111",
            "10101",
            "11111",
            "01110",
            "10101",
            "01010"
        ]
        for (ry, row) in rows.enumerated() {
            for (rx, ch) in row.enumerated() where ch == "1" {
                let sx = centerX - 2 + rx
                let sy = centerY - 3 + ry
                for oy in -1...1 {
                    for ox in -1...1 where abs(ox) + abs(oy) == 1 {
                        let px = sx + ox
                        let py = sy + oy
                        if px >= 0 && px < w && py >= 0 && py < h {
                            pixelData[py * w + px] = outline
                        }
                    }
                }
                if sx >= 0 && sx < w && sy >= 0 && sy < h {
                    pixelData[sy * w + sx] = color
                }
            }
        }
    }

    /// Draw active ranged/magic projectiles. Java stores the projectile on the
    /// target character, points it back at the shooter, and decrements
    /// projectileRange from 40. We use the same interpolation, then project the
    /// in-flight point through the live Scene camera.
    private func drawProjectiles() {
        guard let scene = self.scene else { return }

        for player in worldState.players where player.projectileRange > 0 && player.projectileSprite >= 0 {
            guard let source = projectileSourcePosition(
                serverIndex: player.projectileSourceServerIndex,
                isNpc: player.projectileSourceIsNpc
            ) else { continue }
            drawProjectile(
                sprite: player.projectileSprite,
                range: player.projectileRange,
                sourceTile: source,
                targetTile: (player.x, player.y),
                scene: scene
            )
        }

        for npc in worldState.npcs where npc.projectileRange > 0 && npc.projectileSprite >= 0 {
            guard let source = projectileSourcePosition(
                serverIndex: npc.projectileSourceServerIndex,
                isNpc: npc.projectileSourceIsNpc
            ) else { continue }
            drawProjectile(
                sprite: npc.projectileSprite,
                range: npc.projectileRange,
                sourceTile: source,
                targetTile: (npc.x, npc.y),
                scene: scene
            )
        }

        if worldState.localProjectileRange > 0 && worldState.localProjectileSprite >= 0,
           let source = projectileSourcePosition(
                serverIndex: worldState.localProjectileSourceServerIndex,
                isNpc: worldState.localProjectileSourceIsNpc
           ) {
            drawProjectile(
                sprite: worldState.localProjectileSprite,
                range: worldState.localProjectileRange,
                sourceTile: source,
                targetTile: (worldState.localPlayerX, worldState.localPlayerY),
                scene: scene
            )
        }
    }

    private func projectileSourcePosition(serverIndex: Int, isNpc: Bool) -> (x: Int, z: Int)? {
        if isNpc {
            return worldState.npcs.first(where: { $0.id == serverIndex }).map { ($0.x, $0.y) }
        }
        if serverIndex == worldState.playerServerIndex {
            return (worldState.localPlayerX, worldState.localPlayerY)
        }
        return worldState.players.first(where: { $0.id == serverIndex }).map { ($0.x, $0.y) }
    }

    private func drawProjectile(sprite: Int,
                                range: Int,
                                sourceTile: (x: Int, z: Int),
                                targetTile: (x: Int, z: Int),
                                scene: Scene) {
        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY
        let clampedRange = max(0, min(projectileMaxRange, range))
        let inv = projectileMaxRange - clampedRange

        let sourceX = sourceTile.x * 128 + 64
        let sourceZ = sourceTile.z * 128 + 64
        let targetX = targetTile.x * 128 + 64
        let targetZ = targetTile.z * 128 + 64

        let worldX = (sourceX * inv + targetX * clampedRange) / projectileMaxRange
        let worldZ = (sourceZ * inv + targetZ * clampedRange) / projectileMaxRange
        let height = -96
        let proj = scene.projectPoint(
            worldX: Int32(worldX - px * 128),
            worldY: Int32(height),
            worldZ: Int32(worldZ - pz * 128)
        )
        guard proj.depth >= scene.rot1024_zTop else { return }
        drawProjectileMarker(sprite: sprite, centerX: Int(proj.screenX), centerY: Int(proj.screenY))
    }

    private func drawProjectileMarker(sprite: Int, centerX: Int, centerY: Int) {
        let spriteId = 3160 + sprite
        if let gs = spriteLoader.getSprite(spriteId), gs.width <= 32, gs.height <= 32 {
            spriteLoader.drawSprite(
                spriteId,
                onto: &pixelData,
                bufferWidth: MetalRenderer.gameWidth,
                bufferHeight: MetalRenderer.gameHeight,
                atX: centerX - gs.width / 2,
                atY: centerY - gs.height / 2,
                scale: 1
            )
            return
        }

        let color: UInt32
        switch sprite {
        case 1: color = 0xFF66AAFF  // magic
        case 2: color = 0xFFE8D27A  // ranged
        case 4: color = 0xFFFF4444  // skull
        default: color = 0xFFFFFFFF
        }
        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight
        for dy in -4...4 {
            let span = 4 - abs(dy)
            for dx in -span...span {
                let sx = centerX + dx
                let sy = centerY + dy
                if sx >= 0 && sx < w && sy >= 0 && sy < h {
                    pixelData[sy * w + sx] = Int32(bitPattern: color)
                }
            }
        }
    }

    /// Draw item bubbles over characters that received the Java bubble-item
    /// update (players: opcode 234 case 0, NPCs: opcode 104 case 7). The
    /// desktop client uses a GUI clipping bubble plus the item sprite; we draw
    /// a compact rounded-looking frame and use the item sprite when the bundle
    /// has one, falling back to the item name/id so the game event is visible.
    private func drawOverheadItemBubbles() {
        guard let scene = self.scene else { return }
        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY

        for npc in worldState.npcs where npc.bubbleTimeout > 0 && npc.bubbleItem >= 0 {
            let dx = npc.x - px
            let dz = npc.y - pz
            guard abs(dx) <= 32 && abs(dz) <= 32 else { continue }
            let proj = scene.projectPoint(
                worldX: Int32(dx) * 128 + 64,
                worldY: -120,
                worldZ: Int32(dz) * 128 + 64
            )
            if proj.depth < scene.rot1024_zTop { continue }
            drawItemBubble(itemId: npc.bubbleItem, centerX: Int(proj.screenX), topY: Int(proj.screenY) - 20)
        }

        for player in worldState.players where player.bubbleTimeout > 0 && player.bubbleItem >= 0 {
            let dx = player.x - px
            let dz = player.y - pz
            guard abs(dx) <= 32 && abs(dz) <= 32 else { continue }
            let proj = scene.projectPoint(
                worldX: Int32(dx) * 128 + 64,
                worldY: -120,
                worldZ: Int32(dz) * 128 + 64
            )
            if proj.depth < scene.rot1024_zTop { continue }
            drawItemBubble(itemId: player.bubbleItem, centerX: Int(proj.screenX), topY: Int(proj.screenY) - 20)
        }

        if worldState.localBubbleTimeout > 0 && worldState.localBubbleItem >= 0 {
            drawItemBubble(
                itemId: worldState.localBubbleItem,
                centerX: MetalRenderer.gameWidth / 2,
                topY: MetalRenderer.gameHeight / 2 - 48
            )
        }
    }

    private func drawItemBubble(itemId: Int, centerX: Int, topY: Int) {
        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight
        let bw = 34
        let bh = 24
        let left = centerX - bw / 2
        let top = topY
        let bg = Int32(bitPattern: 0xEED8D8D8)
        let border = Int32(bitPattern: 0xFF303030)
        for y in 0..<bh {
            for x in 0..<bw {
                let sx = left + x
                let sy = top + y
                guard sx >= 0 && sx < w && sy >= 0 && sy < h else { continue }
                let edge = x == 0 || x == bw - 1 || y == 0 || y == bh - 1
                pixelData[sy * w + sx] = edge ? border : bg
            }
        }

        // The Java client's item sprites live at/after spriteItem (2150), but
        // only a subset is bundled in sprites_v2.dat. Try that first; if the
        // sprite is absent, draw a short name/id so the bubble still conveys
        // the action.
        let spriteId = 2150 + itemId
        if let sprite = spriteLoader.getSprite(spriteId), sprite.width <= bw, sprite.height <= bh {
            spriteLoader.drawSprite(
                spriteId,
                onto: &pixelData,
                bufferWidth: w,
                bufferHeight: h,
                atX: centerX - sprite.width / 2,
                atY: top + (bh - sprite.height) / 2,
                scale: 1
            )
        } else {
            let name = ItemNames.name(for: itemId)
            let label = name == "Item" ? "\(itemId)" : String(name.prefix(7))
            drawText(label, x: centerX - (label.count * 2), y: top + 9, color: 0xFF111111)
        }
    }

    /// Draws RSC's red damage splats over any character whose damage-timeout
    /// is in the 150..200 visible window. Mirrors the Java path
    /// (mudclient.java:6515-6526 for NPCs, :6719-6729 for players): a small
    /// red disc centred on the head, with the damage value painted in white
    /// on top. We project tile coords through the live Scene camera so the
    /// splats track the same screen positions as the billboard sprites.
    private func drawDamageSplats() {
        guard let scene = self.scene else { return }
        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY

        // NPCs in the active damage window
        for npc in worldState.npcs where npc.damageTaken > 0 && npc.combatTimeout > 150 {
            let dx = npc.x - px
            let dz = npc.y - pz
            guard abs(dx) <= 32 && abs(dz) <= 32 else { continue }
            let proj = scene.projectPoint(
                worldX: Int32(dx) * 128 + 64,
                worldY: -64,                    // ~half a sprite height above ground
                worldZ: Int32(dz) * 128 + 64
            )
            if proj.depth < scene.rot1024_zTop { continue }
            drawSplat(centerX: Int(proj.screenX), centerY: Int(proj.screenY), damage: npc.damageTaken)
        }

        // Remote players
        for player in worldState.players where player.damageTaken > 0 && player.damageTimeout > 150 {
            let dx = player.x - px
            let dz = player.y - pz
            guard abs(dx) <= 32 && abs(dz) <= 32 else { continue }
            let proj = scene.projectPoint(
                worldX: Int32(dx) * 128 + 64,
                worldY: -64,
                worldZ: Int32(dz) * 128 + 64
            )
            if proj.depth < scene.rot1024_zTop { continue }
            drawSplat(centerX: Int(proj.screenX), centerY: Int(proj.screenY), damage: player.damageTaken)
        }

        // Local player — anchored to screen centre (same place CharacterBillboards puts it).
        if worldState.localDamageTaken > 0 && worldState.localDamageTimeout > 150 {
            drawSplat(
                centerX: MetalRenderer.gameWidth / 2,
                centerY: MetalRenderer.gameHeight / 2 - 4,
                damage: worldState.localDamageTaken
            )
        }
    }

    /// Filled red disc with a one-pixel dark outline + white damage number.
    /// Damage 0 still draws the splat per Java behaviour ("0" splash for
    /// blocked hits) but only when the caller has already gated on the
    /// visibility window above.
    private func drawSplat(centerX: Int, centerY: Int, damage: Int) {
        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight
        let radius = 7
        let bodyColor = Int32(bitPattern: 0xFFCC1818)
        let outlineColor = Int32(bitPattern: 0xFF400000)
        for dy in -radius...radius {
            for dx in -radius...radius {
                let d2 = dx*dx + dy*dy
                if d2 > radius*radius { continue }
                let sx = centerX + dx
                let sy = centerY + dy
                if sx < 0 || sx >= w || sy < 0 || sy >= h { continue }
                pixelData[sy * w + sx] = (d2 > (radius - 1) * (radius - 1)) ? outlineColor : bodyColor
            }
        }
        let dmgStr = "\(damage)"
        let textW = dmgStr.count * 4 - 1   // 3px glyph + 1px advance, minus trailing
        drawText(dmgStr, x: centerX - textW / 2, y: centerY - 2, color: 0xFFFFFFFF)
    }

    private func drawCircleOutline(centerX: Int, centerY: Int, radius: Int, rgb: UInt32, alpha: Int) {
        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight
        guard radius > 0, alpha > 0 else { return }
        let outer = radius * radius
        let innerRadius = max(0, radius - 2)
        let inner = innerRadius * innerRadius
        let a = UInt32(max(0, min(255, alpha)))
        let color = Int32(bitPattern: (a << 24) | (rgb & 0x00FFFFFF))

        for dy in -radius...radius {
            for dx in -radius...radius {
                let d2 = dx * dx + dy * dy
                guard d2 <= outer && d2 >= inner else { continue }
                let sx = centerX + dx
                let sy = centerY + dy
                if sx >= 0 && sx < w && sy >= 0 && sy < h {
                    pixelData[sy * w + sx] = color
                }
            }
        }
    }

    private func drawLine(x0: Int, y0: Int, x1: Int, y1: Int, color: UInt32) {
        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight
        var x = x0
        var y = y0
        let dx = abs(x1 - x0)
        let sx = x0 < x1 ? 1 : -1
        let dy = -abs(y1 - y0)
        let sy = y0 < y1 ? 1 : -1
        var err = dx + dy

        while true {
            if x >= 0 && x < w && y >= 0 && y < h {
                pixelData[y * w + x] = Int32(bitPattern: color)
            }
            if x == x1 && y == y1 { break }
            let e2 = err * 2
            if e2 >= dy {
                err += dy
                x += sx
            }
            if e2 <= dx {
                err += dx
                y += sy
            }
        }
    }

    /// Pull the camera inward when static world geometry sits between the
    /// player and the camera. The Java client keeps the player visible by
    /// adjusting camera distance around occluders; this native approximation
    /// samples the tile ray behind the player using the current yaw and shortens
    /// the camera when a wall/object occupies that path.
    private func cameraZoomWithOcclusion(_ desiredZoom: Int32) -> Int32 {
        let yaw = Int((cameraRotation * 4) & 1023)
        let pitch = Int((cameraPitch * 4) & 1023)
        let offset = desiredZoom * 2

        var offX: Int32 = 0
        var offY: Int32 = 0
        var offZ: Int32 = offset

        if pitch != 0 {
            let sin = FastMath.trigTable1024[pitch]
            let cos = FastMath.trigTable1024[pitch + 1024]
            let tmp = (cos &* offY &- sin &* offset) >> 15
            offZ = (sin &* offY &+ offset &* cos) >> 15
            offY = tmp
        }

        if yaw != 0 {
            let sin = FastMath.trigTable1024[yaw]
            let cos = FastMath.trigTable1024[yaw + 1024]
            let tmp = (offX &* cos &+ offZ &* sin) >> 15
            offZ = (cos &* offZ &- sin &* offX) >> 15
            offX = tmp
        }

        let cameraTileX = -Double(offX) / 128.0
        let cameraTileZ = -Double(offZ) / 128.0
        let distanceTiles = max(1.0, sqrt(cameraTileX * cameraTileX + cameraTileZ * cameraTileZ))
        let stepX = cameraTileX / distanceTiles
        let stepZ = cameraTileZ / distanceTiles

        let objectTiles = Set(worldState.gameObjects.map { "\($0.x),\($0.y)" })
        let wallTiles = Set(worldState.wallObjects.map { "\($0.x),\($0.y)" })
        var occludedAt: Double?

        let maxSample = min(18, max(2, Int(distanceTiles.rounded(.down))))
        for step in 1...maxSample {
            let tx = worldState.localPlayerX + Int((stepX * Double(step)).rounded())
            let tz = worldState.localPlayerY + Int((stepZ * Double(step)).rounded())
            let key = "\(tx),\(tz)"
            if objectTiles.contains(key) || wallTiles.contains(key) {
                occludedAt = Double(step)
                break
            }
        }

        let targetZoom: Int32
        if let occludedAt {
            // Keep the camera just in front of the nearest blocking tile, but
            // do not collapse into the old close-up view on mobile. Dense towns
            // can have scenery immediately behind the player; a hard 520 floor
            // made the world feel over-zoomed and hurt tap targeting.
            targetZoom = min(desiredZoom, max(900, Int32((occludedAt - 0.35) * 64.0)))
        } else {
            targetZoom = desiredZoom
        }

        if cameraOcclusionZoom == 0 { cameraOcclusionZoom = targetZoom }
        if cameraOcclusionZoom > targetZoom {
            cameraOcclusionZoom = max(targetZoom, cameraOcclusionZoom - 90)
        } else if cameraOcclusionZoom < targetZoom {
            cameraOcclusionZoom = min(targetZoom, cameraOcclusionZoom + 35)
        }
        return cameraOcclusionZoom
    }

    private func persistCameraPreferencesIfNeeded() {
        // Save at most every ~5 seconds (100 ticks x 50ms). UserDefaults writes
        // are tiny here, but this keeps gesture-heavy camera rotation from
        // turning into a disk-write stream.
        guard renderLogCount > 0, renderLogCount % 100 == 0 else { return }

        let yaw = cameraRotationDegrees
        let pitch = cameraPitchDegrees
        let zoom = Double(cameraZoom)
        let prefs = worldState.preferences
        guard abs(yaw - prefs.lastCameraYawDegrees) > 1
            || abs(pitch - prefs.lastCameraPitchDegrees) > 1
            || abs(zoom - prefs.lastCameraZoom) > 50 else { return }

        updatePreferences { p in
            p.lastCameraYawDegrees = yaw
            p.lastCameraPitchDegrees = pitch
            p.lastCameraZoom = zoom
        }
    }

    // Simple 3x5 pixel font for rendering text on the map
    private static let font3x5: [Character: [UInt8]] = {
        // Each character is 3 wide x 5 tall, stored as 5 rows of 3 bits
        let defs: [(Character, [UInt8])] = [
            ("A", [0b010, 0b101, 0b111, 0b101, 0b101]),
            ("B", [0b110, 0b101, 0b110, 0b101, 0b110]),
            ("C", [0b011, 0b100, 0b100, 0b100, 0b011]),
            ("D", [0b110, 0b101, 0b101, 0b101, 0b110]),
            ("E", [0b111, 0b100, 0b110, 0b100, 0b111]),
            ("F", [0b111, 0b100, 0b110, 0b100, 0b100]),
            ("G", [0b011, 0b100, 0b101, 0b101, 0b011]),
            ("H", [0b101, 0b101, 0b111, 0b101, 0b101]),
            ("I", [0b111, 0b010, 0b010, 0b010, 0b111]),
            ("J", [0b001, 0b001, 0b001, 0b101, 0b010]),
            ("K", [0b101, 0b110, 0b100, 0b110, 0b101]),
            ("L", [0b100, 0b100, 0b100, 0b100, 0b111]),
            ("M", [0b101, 0b111, 0b111, 0b101, 0b101]),
            ("N", [0b101, 0b111, 0b111, 0b111, 0b101]),
            ("O", [0b010, 0b101, 0b101, 0b101, 0b010]),
            ("P", [0b110, 0b101, 0b110, 0b100, 0b100]),
            ("Q", [0b010, 0b101, 0b101, 0b110, 0b011]),
            ("R", [0b110, 0b101, 0b110, 0b101, 0b101]),
            ("S", [0b011, 0b100, 0b010, 0b001, 0b110]),
            ("T", [0b111, 0b010, 0b010, 0b010, 0b010]),
            ("U", [0b101, 0b101, 0b101, 0b101, 0b010]),
            ("V", [0b101, 0b101, 0b101, 0b010, 0b010]),
            ("W", [0b101, 0b101, 0b111, 0b111, 0b101]),
            ("X", [0b101, 0b101, 0b010, 0b101, 0b101]),
            ("Y", [0b101, 0b101, 0b010, 0b010, 0b010]),
            ("Z", [0b111, 0b001, 0b010, 0b100, 0b111]),
            ("0", [0b111, 0b101, 0b101, 0b101, 0b111]),
            ("1", [0b010, 0b110, 0b010, 0b010, 0b111]),
            ("2", [0b110, 0b001, 0b010, 0b100, 0b111]),
            ("3", [0b110, 0b001, 0b010, 0b001, 0b110]),
            ("4", [0b101, 0b101, 0b111, 0b001, 0b001]),
            ("5", [0b111, 0b100, 0b110, 0b001, 0b110]),
            ("6", [0b011, 0b100, 0b111, 0b101, 0b010]),
            ("7", [0b111, 0b001, 0b010, 0b010, 0b010]),
            ("8", [0b010, 0b101, 0b010, 0b101, 0b010]),
            ("9", [0b010, 0b101, 0b111, 0b001, 0b110]),
            (" ", [0b000, 0b000, 0b000, 0b000, 0b000]),
            ("(", [0b010, 0b100, 0b100, 0b100, 0b010]),
            (")", [0b010, 0b001, 0b001, 0b001, 0b010]),
            (",", [0b000, 0b000, 0b000, 0b010, 0b100]),
            (".", [0b000, 0b000, 0b000, 0b000, 0b010]),
        ]
        var d = [Character: [UInt8]]()
        for (c, rows) in defs { d[c] = rows }
        return d
    }()

    private func drawText(_ text: String, x: Int, y: Int, color: UInt32) {
        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight
        var cx = x
        for ch in text.uppercased() {
            guard let rows = RSCGameEngine.font3x5[ch] else { cx += 4; continue }
            for row in 0..<5 {
                for col in 0..<3 {
                    if (rows[row] >> (2 - col)) & 1 == 1 {
                        let px = cx + col
                        let py = y + row
                        if px >= 0 && px < w && py >= 0 && py < h {
                            pixelData[py * w + px] = Int32(bitPattern: color)
                        }
                    }
                }
            }
            cx += 4
        }
    }

    private func renderWorld() {
        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight

        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY

        // Absolute world position for sector lookups
        let absX = worldState.absoluteWorldX(px)
        let absZ = worldState.absoluteWorldZ(pz)

        // Tile size in pixels — scales with zoom
        let tp = max(2, min(16, Int(6.0 * zoomLevel)))
        let centerX = w / 2
        let centerY = h / 2
        let tilesW = w / tp + 2
        let tilesH = h / tp + 2

        // Render terrain tiles using real landscape data
        for ty in (-tilesH/2)..<(tilesH/2) {
            for tx in (-tilesW/2)..<(tilesW/2) {
                let screenX = centerX + tx * tp - tp / 2
                let screenY = centerY + ty * tp - tp / 2
                let worldTX = absX + tx
                let worldTZ = absZ + ty

                // Get real tile data from landscape archive
                var color: Int32
                if landscapeLoader.isLoaded, let tile = landscapeLoader.getTile(worldX: worldTX, worldZ: worldTZ, plane: 0) {
                    color = LandscapeLoader.tileColor(overlay: tile.groundOverlay, texture: tile.groundTexture, elevation: tile.groundElevation)

                    if tile.horizontalWall > 0 || tile.verticalWall > 0 {
                        color = LandscapeLoader.packRGB(r: 60, g: 55, b: 45)
                    }
                    if tile.roofTexture > 0 {
                        color = LandscapeLoader.packRGB(r: 100, g: 90, b: 75)
                    }
                } else {
                    let noise = abs(worldTX * 73856093 ^ worldTZ * 19349663) % 20
                    color = LandscapeLoader.packRGB(r: 20 + noise, g: 55 + noise, b: 15)
                }

                for dy in 0..<tp {
                    for dx in 0..<tp {
                        let sx = screenX + dx
                        let sy = screenY + dy
                        if sx >= 0 && sx < w && sy >= 0 && sy < h {
                            pixelData[sy * w + sx] = color
                        }
                    }
                }
            }
        }

        // Helper to draw entities
        func drawEntity(worldX: Int, worldZ: Int, color: UInt32, size: Int) {
            let sx = centerX + (worldX - px) * tp
            let sy = centerY + (worldZ - pz) * tp
            for dy in (-size/2)..<(size/2) {
                for dx in (-size/2)..<(size/2) {
                    let ex = sx + dx
                    let ey = sy + dy
                    if ex >= 0 && ex < w && ey >= 0 && ey < h {
                        pixelData[ey * w + ex] = Int32(bitPattern: color)
                    }
                }
            }
        }

        // Draw NPCs with labels, health bars, damage splats, and chat
        for npc in worldState.npcs {
            let npcSX = centerX + (npc.x - px) * tp
            let npcSY = centerY + (npc.y - pz) * tp
            guard npcSX > -tp*3 && npcSX < w + tp*3 && npcSY > -tp*3 && npcSY < h + tp*3 else { continue }

            if spriteLoader.isLoaded {
                // Try a few sprite IDs based on NPC type (rough mapping)
                let baseSpriteId = npc.npcId * 3  // rough estimate
                spriteLoader.drawSprite(baseSpriteId, onto: &pixelData, bufferWidth: w, bufferHeight: h,
                                        atX: npcSX - tp, atY: npcSY - tp * 2, scale: 1)
            }

            // NPC dot as fallback/indicator
            let outlineColor: UInt32 = npc.combatTimeout > 0 ? 0xFFFF0000 : 0xFF000000
            drawEntity(worldX: npc.x, worldZ: npc.y, color: outlineColor, size: tp + 2)
            drawEntity(worldX: npc.x, worldZ: npc.y, color: 0xFFFFDD00, size: tp)

            var labelY = npcSY - tp - 2

            // NPC chat message bubble
            if npc.messageTimeout > 0 && !npc.message.isEmpty {
                let chatStr = String(npc.message.prefix(20))
                let chatX = npcSX - (chatStr.count * 2)
                drawText(chatStr, x: chatX, y: labelY - 8, color: 0xFFFFFFFF)
                labelY -= 8
            }

            // NPC name
            let nameStr = String(npc.name.prefix(14))
            drawText(nameStr, x: npcSX - (nameStr.count * 2), y: labelY, color: 0xFFFFFF00)

            // Health bar if NPC has HP data and is in combat
            if npc.maxHp > 0 && npc.combatTimeout > 0 {
                let barW = tp * 3
                let barY = labelY - 4
                let barX = npcSX - barW / 2
                let hpPct = max(0.0, min(1.0, Double(npc.currentHp) / Double(npc.maxHp)))
                let greenW = Int(Double(barW) * hpPct)
                for bx in 0..<barW {
                    for by in 0..<2 { // 2px tall bar
                        let bpx = barX + bx; let bpy = barY + by
                        if bpx >= 0 && bpx < w && bpy >= 0 && bpy < h {
                            pixelData[bpy * w + bpx] = Int32(bitPattern: bx < greenW ? 0xFF00CC00 : 0xFFCC0000)
                        }
                    }
                }

                // Damage splat number
                if npc.damageTaken > 0 {
                    let dmgStr = "\(npc.damageTaken)"
                    drawText(dmgStr, x: npcSX + tp, y: npcSY - 3, color: 0xFFFF3333)
                }
            }
        }

        // Draw other players with labels
        for player in worldState.players {
            let plSX = centerX + (player.x - px) * tp
            let plSY = centerY + (player.y - pz) * tp
            guard plSX > -tp*3 && plSX < w + tp*3 && plSY > -tp*3 && plSY < h + tp*3 else { continue }

            drawEntity(worldX: player.x, worldZ: player.y, color: 0xFF000000, size: tp + 2)
            drawEntity(worldX: player.x, worldZ: player.y, color: 0xFF00DDFF, size: tp)
            let nameStr = String(player.name.prefix(14))
            drawText(nameStr, x: plSX - (nameStr.count * 2), y: plSY - tp - 2, color: 0xFF00FFFF)
        }

        // Draw game objects color-coded by type
        for obj in worldState.gameObjects {
            let objName = ObjectNames.name(for: obj.objectId).lowercased()
            let objColor: UInt32
            if objName.contains("tree") || objName.contains("willow") || objName.contains("yew") || objName.contains("oak") {
                objColor = 0xFF1B5E20  // dark green — trees
            } else if objName.contains("rock") || objName.contains("ore") || objName.contains("mine") {
                objColor = 0xFF616161  // gray — rocks/mining
            } else if objName.contains("furnace") || objName.contains("fire") || objName.contains("range") || objName.contains("stove") {
                objColor = 0xFFE65100  // orange — fire/cooking
            } else if objName.contains("bank") || objName.contains("booth") {
                objColor = 0xFFFFC107  // gold — bank
            } else if objName.contains("altar") || objName.contains("chapel") {
                objColor = 0xFFCE93D8  // purple — prayer
            } else if objName.contains("door") || objName.contains("gate") || objName.contains("ladder") || objName.contains("stair") {
                objColor = 0xFF8D6E63  // brown — doors/traversal
            } else if objName.contains("fish") || objName.contains("net") {
                objColor = 0xFF0288D1  // blue — fishing
            } else if objName.contains("anvil") || objName.contains("forge") {
                objColor = 0xFF455A64  // dark steel — smithing
            } else if objName.contains("sign") || objName.contains("chest") || objName.contains("table") || objName.contains("chair") {
                objColor = 0xFF795548  // wood brown — furniture
            } else {
                objColor = 0xFF553311  // default brown
            }
            drawEntity(worldX: obj.x, worldZ: obj.y, color: objColor, size: tp)
            // Show name for important objects nearby
            let dx = abs(obj.x - px)
            let dz = abs(obj.y - pz)
            if dx <= 5 && dz <= 5 && objName != "object" {
                let labelX = centerX + (obj.x - px) * tp - (min(objName.count, 10) * 2)
                let labelY = centerY + (obj.y - pz) * tp - 7
                drawText(String(objName.prefix(12)), x: labelX, y: labelY, color: 0xFFDDDDDD)
            }
        }

        // Draw walls as lines between tiles
        for wall in worldState.wallObjects {
            let sx = centerX + (wall.x - px) * tp
            let sy = centerY + (wall.y - pz) * tp
            guard sx > -tp && sx < w + tp && sy > -tp && sy < h + tp else { continue }
            let wallColor = Int32(bitPattern: 0xFF5D4037)
            // Direction: 0=north wall, 1=east wall, 2=diagonal NE, 3=diagonal NW
            switch wall.direction {
            case 0: // horizontal wall (along X axis, north side of tile)
                for i in 0..<tp {
                    let wx = sx + i; let wy = sy
                    if wx >= 0 && wx < w && wy >= 0 && wy < h { pixelData[wy * w + wx] = wallColor }
                }
            case 1: // vertical wall (along Z axis, east side of tile)
                for i in 0..<tp {
                    let wx = sx + tp - 1; let wy = sy + i
                    if wx >= 0 && wx < w && wy >= 0 && wy < h { pixelData[wy * w + wx] = wallColor }
                }
            case 2: // diagonal NE
                for i in 0..<tp {
                    let wx = sx + i; let wy = sy + tp - 1 - i
                    if wx >= 0 && wx < w && wy >= 0 && wy < h { pixelData[wy * w + wx] = wallColor }
                }
            case 3: // diagonal NW
                for i in 0..<tp {
                    let wx = sx + i; let wy = sy + i
                    if wx >= 0 && wx < w && wy >= 0 && wy < h { pixelData[wy * w + wx] = wallColor }
                }
            default: break
            }
        }

        // Draw ground items as small red dots with names
        for item in worldState.groundItems {
            drawEntity(worldX: item.x, worldZ: item.y, color: 0xFFFF3333, size: 4)
            let dx = abs(item.x - px)
            let dz = abs(item.y - pz)
            if dx <= 5 && dz <= 5 {
                let itemName = ItemNames.name(for: item.itemId)
                let labelX = centerX + (item.x - px) * tp - (min(itemName.count, 10) * 2)
                let labelY = centerY + (item.y - pz) * tp - 7
                drawText(String(itemName.prefix(12)), x: labelX, y: labelY, color: 0xFFFF6666)
            }
        }

        // Draw local player as white square with outline
        drawEntity(worldX: px, worldZ: pz, color: 0xFF000000, size: tp + 4) // black outline
        drawEntity(worldX: px, worldZ: pz, color: 0xFFFFFFFF, size: tp + 2) // white fill

        // Draw player name label
        let playerName = worldState.localPlayerName.isEmpty ? "You" : worldState.localPlayerName
        drawText(playerName, x: centerX - (playerName.count * 2), y: centerY - tp - 6, color: 0xFFFFFFFF)

        // Info bar at top
        for y in 0..<14 {
            for x in 0..<w {
                pixelData[y * w + x] = Int32(bitPattern: 0xDD000000)
            }
        }
        // Position text
        drawText("(\(absX),\(absZ)) NPC\(worldState.npcs.count) OBJ\(worldState.gameObjects.count) WALL\(worldState.wallObjects.count)", x: 4, y: 4, color: 0xFFFFFFFF)

        // Compass at top-right
        drawText("N", x: w - 12, y: 4, color: 0xFFFF4444)

        // Legend at bottom
        let legendY = h - 10
        for x in 0..<w {
            pixelData[legendY * w + x] = Int32(bitPattern: 0xDD000000)
            if legendY + 1 < h { pixelData[(legendY + 1) * w + x] = Int32(bitPattern: 0xDD000000) }
        }
        drawText("YOU", x: 4, y: legendY + 2, color: 0xFFFFFFFF)
        drawText("NPC", x: 40, y: legendY + 2, color: 0xFFFFDD00)
        drawText("PLAYER", x: 76, y: legendY + 2, color: 0xFF00DDFF)
        drawText("ITEM", x: 128, y: legendY + 2, color: 0xFFFF3333)

        // Log render state periodically
        renderLogCount += 1
        if renderLogCount <= 3 || renderLogCount % 200 == 0 {
            print("[Render] tick=\(renderLogCount) local=(\(px),\(pz)) abs=(\(absX),\(absZ)) sector=(\(absX/48),\(absZ/48)) npcs=\(worldState.npcs.count)")
        }
    }

    // (Terrain colors now come from LandscapeLoader using real archive data)

    // MARK: - Input handling

    /// Pick the tile whose projected center is nearest to a game-canvas pixel.
    /// The previous input code tried to invert the camera with a hand-rolled
    /// raycast, which drifted badly as soon as camera rotation/zoom changed.
    /// Sampling projected tile centers is cheap at RSC scale and guarantees
    /// tap-to-walk and long-press context menus use the same camera math as the
    /// renderer.
    private func worldTileNearestScreenPoint(gameX: Double, gameY: Double) -> (x: Int, z: Int) {
        guard let scene = self.scene else {
            return (worldState.localPlayerX, worldState.localPlayerY)
        }

        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY
        var best = (x: px, z: pz)
        var bestDist = Double.greatestFiniteMagnitude

        for dz in -24...24 {
            for dx in -24...24 {
                let localX = dx * 128 + 64
                let localZ = dz * 128 + 64
                let elevation = world?.getElevation(x: localX, z: localZ) ?? 0
                let proj = scene.projectPoint(
                    worldX: Int32(localX),
                    worldY: -Int32(elevation),
                    worldZ: Int32(localZ)
                )
                guard proj.depth >= scene.rot1024_zTop else { continue }

                let sx = Double(proj.screenX)
                let sy = Double(proj.screenY)
                guard sx >= -64 && sx <= Double(MetalRenderer.gameWidth + 64),
                      sy >= -64 && sy <= Double(MetalRenderer.gameHeight + 64) else { continue }

                let ddx = sx - gameX
                let ddy = sy - gameY
                let dist = ddx * ddx + ddy * ddy
                if dist < bestDist {
                    bestDist = dist
                    best = (x: px + dx, z: pz + dz)
                }
            }
        }

        return best
    }

    private func projectedScreenPoint(tileX: Double, tileZ: Double, yOffset: Int32 = 0) -> (x: Double, y: Double, depth: Int32)? {
        guard let scene = self.scene else { return nil }
        let localX = Int32(((tileX - Double(worldState.localPlayerX)) * 128.0).rounded()) + 64
        let localZ = Int32(((tileZ - Double(worldState.localPlayerY)) * 128.0).rounded()) + 64
        let elevation = world?.getElevation(x: Int(localX), z: Int(localZ)) ?? 0
        let proj = scene.projectPoint(worldX: localX, worldY: -Int32(elevation) + yOffset, worldZ: localZ)
        guard proj.depth >= scene.rot1024_zTop else { return nil }
        return (Double(proj.screenX), Double(proj.screenY), proj.depth)
    }

    private func minimumGameRadius(forScreenPoints points: CGFloat) -> Double {
        let viewSize = touchTranslator.viewSize
        guard viewSize.width > 0, viewSize.height > 0 else {
            return Double(points)
        }
        let xRadius = Double(points * CGFloat(MetalRenderer.gameWidth) / viewSize.width)
        let yRadius = Double(points * CGFloat(MetalRenderer.gameHeight) / viewSize.height)
        return max(xRadius, yRadius)
    }

    /// Prefer screen-space entity hit tests over tile-nearest picking. Mobile
    /// taps land on the visible sprite, not always on the projected tile centre;
    /// this mirrors the PC client's menu building, which starts from what is
    /// actually under the cursor.
    private func nearestNPCOnScreen(gameX: Double, gameY: Double) -> RSCNPC? {
        var best: (npc: RSCNPC, score: Double, depth: Int32)?
        let minRadius = minimumGameRadius(forScreenPoints: 22)
        let radiusX = max(34.0, minRadius)
        let radiusY = max(58.0, minRadius * 1.35)
        for npc in worldState.npcs {
            guard let p = projectedScreenPoint(tileX: npc.interpolatedX, tileZ: npc.interpolatedY) else { continue }
            // Feet are anchored at p.y; mobile taps often land on the lower
            // half of the visible sprite. Use a slightly taller ellipse than
            // the desktop cursor hotspot so tapping an NPC's body/feet still
            // resolves to the actor instead of falling through to ground walk.
            let dx = (p.x - gameX) / radiusX
            let dy = (p.y - 36.0 - gameY) / radiusY
            let score = dx * dx + dy * dy
            if score <= 1.0 && (best == nil || score < best!.score || (score == best!.score && p.depth < best!.depth)) {
                best = (npc, score, p.depth)
            }
        }
        return best?.npc
    }

    private func nearestPlayerOnScreen(gameX: Double, gameY: Double) -> RSCPlayer? {
        var best: (player: RSCPlayer, score: Double, depth: Int32)?
        let minRadius = minimumGameRadius(forScreenPoints: 22)
        let radiusX = max(34.0, minRadius)
        let radiusY = max(58.0, minRadius * 1.35)
        for player in worldState.players {
            guard let p = projectedScreenPoint(tileX: player.interpolatedX, tileZ: player.interpolatedY) else { continue }
            let dx = (p.x - gameX) / radiusX
            let dy = (p.y - 36.0 - gameY) / radiusY
            let score = dx * dx + dy * dy
            if score <= 1.0 && (best == nil || score < best!.score || (score == best!.score && p.depth < best!.depth)) {
                best = (player, score, p.depth)
            }
        }
        return best?.player
    }

    private func nearestGroundItemOnScreen(gameX: Double, gameY: Double) -> RSCGroundItem? {
        var best: (item: RSCGroundItem, score: Double, depth: Int32)?
        let radius = max(18.0, minimumGameRadius(forScreenPoints: 18))
        for item in worldState.groundItems {
            guard let p = projectedScreenPoint(tileX: Double(item.x), tileZ: Double(item.y), yOffset: -8) else { continue }
            let dx = p.x - gameX
            let dy = p.y - gameY
            let score = dx * dx + dy * dy
            if score <= radius * radius && (best == nil || score < best!.score || (score == best!.score && p.depth < best!.depth)) {
                best = (item, score, p.depth)
            }
        }
        return best?.item
    }

    private func nearestGameObjectOnScreen(gameX: Double, gameY: Double) -> RSCGameObject? {
        var best: (object: RSCGameObject, score: Double, depth: Int32)?
        for object in worldState.gameObjects {
            let footprint = objectFootprint(for: object)
            let centerX = (Double(footprint.minX) + Double(footprint.maxX) + 1.0) / 2.0
            let centerZ = (Double(footprint.minZ) + Double(footprint.maxZ) + 1.0) / 2.0
            guard let p = projectedScreenPoint(tileX: centerX, tileZ: centerZ, yOffset: -20) else { continue }
            let physicalMin = minimumGameRadius(forScreenPoints: 22)
            let radius = max(
                physicalMin,
                Double(max(24, min(64, 18 * max(1, max(footprint.maxX - footprint.minX + 1, footprint.maxZ - footprint.minZ + 1)))))
            )
            let dx = (p.x - gameX) / radius
            let dy = (p.y - gameY) / radius
            let score = dx * dx + dy * dy
            if score <= 1.0 && (best == nil || score < best!.score || (score == best!.score && p.depth < best!.depth)) {
                best = (object, score, p.depth)
            }
        }
        return best?.object
    }

    private func nearestWallObjectOnScreen(gameX: Double, gameY: Double) -> RSCWallObject? {
        var best: (wall: RSCWallObject, score: Double, depth: Int32)?
        let radius = max(24.0, minimumGameRadius(forScreenPoints: 22))
        for wall in worldState.wallObjects {
            let sample = projectedWallSegment(for: wall, yOffset: -18)
            let score: Double
            let depth: Int32
            if let sample {
                score = distanceSquaredToSegment(
                    px: gameX,
                    py: gameY,
                    ax: sample.a.x,
                    ay: sample.a.y,
                    bx: sample.b.x,
                    by: sample.b.y
                ) / (radius * radius)
                depth = min(sample.a.depth, sample.b.depth)
            } else if let p = projectedScreenPoint(tileX: Double(wall.x), tileZ: Double(wall.y), yOffset: -18) {
                let dx = (p.x - gameX) / radius
                let dy = (p.y - gameY) / radius
                score = dx * dx + dy * dy
                depth = p.depth
            } else {
                continue
            }
            if score <= 1.0 && (best == nil || score < best!.score || (score == best!.score && depth < best!.depth)) {
                best = (wall, score, depth)
            }
        }
        return best?.wall
    }

    private func projectedWallSegment(for wall: RSCWallObject, yOffset: Int32 = 0) -> (a: (x: Double, y: Double, depth: Int32), b: (x: Double, y: Double, depth: Int32))? {
        let endpoints = Self.boundaryWallTileEndpoints(tileX: Double(wall.x), tileZ: Double(wall.y), direction: wall.direction)
        guard let a = projectedScreenPoint(tileX: endpoints.start.x - 0.5, tileZ: endpoints.start.z - 0.5, yOffset: yOffset),
              let b = projectedScreenPoint(tileX: endpoints.end.x - 0.5, tileZ: endpoints.end.z - 0.5, yOffset: yOffset) else {
            return nil
        }
        return (a, b)
    }

    private func distanceSquaredToSegment(px: Double, py: Double, ax: Double, ay: Double, bx: Double, by: Double) -> Double {
        let vx = bx - ax
        let vy = by - ay
        let lenSq = vx * vx + vy * vy
        guard lenSq > 0.0001 else {
            let dx = px - ax
            let dy = py - ay
            return dx * dx + dy * dy
        }
        let t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / lenSq))
        let cx = ax + t * vx
        let cy = ay + t * vy
        let dx = px - cx
        let dy = py - cy
        return dx * dx + dy * dy
    }

    private func nearestNPC(toX x: Int, z: Int, maxDistanceSquared: Int = 4) -> RSCNPC? {
        var nearest: RSCNPC? = nil
        var nearestDist = Int.max
        for npc in worldState.npcs {
            let dx = npc.x - x
            let dz = npc.y - z
            let dist = dx * dx + dz * dz
            if dist < nearestDist && dist <= maxDistanceSquared {
                nearestDist = dist
                nearest = npc
            }
        }
        return nearest
    }

    private func nearestPlayer(toX x: Int, z: Int, maxDistanceSquared: Int = 4) -> RSCPlayer? {
        var nearest: RSCPlayer? = nil
        var nearestDist = Int.max
        for player in worldState.players {
            let dx = player.x - x
            let dz = player.y - z
            let dist = dx * dx + dz * dz
            if dist < nearestDist && dist <= maxDistanceSquared {
                nearestDist = dist
                nearest = player
            }
        }
        return nearest
    }

    private func nearestGroundItem(toX x: Int, z: Int) -> RSCGroundItem? {
        var nearest: RSCGroundItem? = nil
        var nearestDist = Int.max
        for item in worldState.groundItems {
            let dx = item.x - x
            let dz = item.y - z
            let dist = dx * dx + dz * dz
            if dist < nearestDist && dist <= 4 {
                nearestDist = dist
                nearest = item
            }
        }
        return nearest
    }

    private func nearestGameObject(toX x: Int, z: Int) -> RSCGameObject? {
        var nearest: RSCGameObject? = nil
        var nearestDist = Int.max
        for object in worldState.gameObjects {
            let footprint = objectFootprint(for: object)
            let dx: Int
            if x < footprint.minX {
                dx = footprint.minX - x
            } else if x > footprint.maxX {
                dx = x - footprint.maxX
            } else {
                dx = 0
            }
            let dz: Int
            if z < footprint.minZ {
                dz = footprint.minZ - z
            } else if z > footprint.maxZ {
                dz = z - footprint.maxZ
            } else {
                dz = 0
            }
            let dist = dx * dx + dz * dz
            if dist < nearestDist && dist <= 4 {
                nearestDist = dist
                nearest = object
            }
        }
        return nearest
    }

    private func nearestWallObject(toX x: Int, z: Int) -> RSCWallObject? {
        var nearest: RSCWallObject? = nil
        var nearestDist = Int.max
        for wall in worldState.wallObjects {
            let dx = wall.x - x
            let dz = wall.y - z
            let dist = dx * dx + dz * dz
            if dist < nearestDist && dist <= 4 {
                nearestDist = dist
                nearest = wall
            }
        }
        return nearest
    }

    private func groundItem(atX x: Int, z: Int) -> RSCGroundItem? {
        worldState.groundItems.first { $0.x == x && $0.y == z }
    }

    private func npc(atX x: Int, z: Int) -> RSCNPC? {
        worldState.npcs.first { $0.x == x && $0.y == z }
    }

    private func player(atX x: Int, z: Int) -> RSCPlayer? {
        worldState.players.first { $0.x == x && $0.y == z }
    }

    private func gameObject(containingX x: Int, z: Int) -> RSCGameObject? {
        worldState.gameObjects.first { object in
            let footprint = objectFootprint(for: object)
            return x >= footprint.minX && x <= footprint.maxX
                && z >= footprint.minZ && z <= footprint.maxZ
        }
    }

    private func wallObject(atX x: Int, z: Int) -> RSCWallObject? {
        worldState.wallObjects.first { $0.x == x && $0.y == z }
    }

    private var worldInputBlockedByModal: Bool {
        worldState.welcomeOpen
            || worldState.serverMessageDialogOpen
            || worldState.inputPromptOpen
            || worldState.connectionClosedOpen
            || worldState.contactDetailsOpen
            || worldState.recoveryQuestionsOpen
            || worldState.bankPinOpen
            || worldState.openPKPointsToGpPromptOpen
            || worldState.ironmanInterfaceOpen
            || worldState.statusProgressOpen
            || worldState.fishingTrawlerOpen
            || worldState.sleepCaptchaBytes != nil
            || worldState.showAppearanceChange
            || worldState.wildernessWarningOpen
    }

    private func isActionableCommand(_ command: String) -> Bool {
        let lowered = command.lowercased()
        return !command.isEmpty && lowered != "walkto" && lowered != "null" && lowered != "examine"
    }

    private func primaryObjectAction(for object: RSCGameObject) -> (command: String, useFirstAction: Bool)? {
        guard let def = GameObjectDefinitions.get(object.objectId) else { return nil }
        let command1 = def.command1.trimmingCharacters(in: .whitespacesAndNewlines)
        if isActionableCommand(command1) { return (command1, true) }
        let command2 = def.command2.trimmingCharacters(in: .whitespacesAndNewlines)
        if isActionableCommand(command2) { return (command2, false) }
        return nil
    }

    private func primaryWallAction(for wall: RSCWallObject) -> (command: String, useFirstAction: Bool)? {
        guard let def = EntityDefinitions.getDoorDef(wall.wallId) else { return nil }
        let command1 = def.command1.trimmingCharacters(in: .whitespacesAndNewlines)
        if isActionableCommand(command1) { return (command1, true) }
        let command2 = def.command2.trimmingCharacters(in: .whitespacesAndNewlines)
        if isActionableCommand(command2) { return (command2, false) }
        return nil
    }

    private func objectFootprint(for object: RSCGameObject) -> (minX: Int, maxX: Int, minZ: Int, maxZ: Int) {
        guard let def = GameObjectDefinitions.get(object.objectId) else {
            return (object.x, object.x, object.y, object.y)
        }

        var width = def.width
        var height = def.height
        if object.direction != 0 && object.direction != 4 {
            swap(&width, &height)
        }

        var minX = object.x
        var minZ = object.y
        // Type 2/3 objects use the expanded direction-sensitive reach box in
        // mudclient.walkToObject(); this keeps doors/gates and diagonal scenery
        // from trying to path onto the blocked origin tile.
        if def.type == 2 || def.type == 3 {
            switch object.direction {
            case 0:
                width += 1
                minX -= 1
            case 2:
                height += 1
            case 4:
                width += 1
            case 6:
                minZ -= 1
                height += 1
            default:
                break
            }
        }

        return (minX, minX + max(1, width) - 1, minZ, minZ + max(1, height) - 1)
    }

    private func nearestApproachTile(around footprint: (minX: Int, maxX: Int, minZ: Int, maxZ: Int)) -> (x: Int, z: Int) {
        var candidates: [(x: Int, z: Int)] = []
        for x in (footprint.minX - 1)...(footprint.maxX + 1) {
            candidates.append((x, footprint.minZ - 1))
            candidates.append((x, footprint.maxZ + 1))
        }
        if footprint.minZ <= footprint.maxZ {
            for z in footprint.minZ...footprint.maxZ {
                candidates.append((footprint.minX - 1, z))
                candidates.append((footprint.maxX + 1, z))
            }
        }
        return nearestReachableTile(from: candidates, fallback: (footprint.minX, footprint.minZ))
    }

    private func nearestInteractionTile(inside area: (minX: Int, maxX: Int, minZ: Int, maxZ: Int)) -> (x: Int, z: Int) {
        var candidates: [(x: Int, z: Int)] = []
        for x in area.minX...area.maxX {
            for z in area.minZ...area.maxZ {
                candidates.append((x, z))
            }
        }
        return nearestReachableTile(from: candidates, fallback: (area.minX, area.minZ))
    }

    private func nearestReachableTile(from candidates: [(x: Int, z: Int)], fallback: (x: Int, z: Int)) -> (x: Int, z: Int) {
        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY
        let pathfinder = Pathfinder(landscapeLoader: landscapeLoader, worldState: worldState)
        var best = fallback
        var bestDist = Int.max
        var bestPathLength = Int.max

        for candidate in candidates {
            let dx = candidate.x - px
            let dz = candidate.z - pz
            let dist = dx * dx + dz * dz
            if candidate.x == px && candidate.z == pz {
                return candidate
            }
            let path = pathfinder.findPath(fromX: px, fromZ: pz, toX: candidate.x, toZ: candidate.z, maxSteps: 25)
            guard !path.isEmpty else { continue }
            if path.count < bestPathLength || (path.count == bestPathLength && dist < bestDist) {
                best = candidate
                bestDist = dist
                bestPathLength = path.count
            }
        }
        return best
    }

    private func approachTile(for object: RSCGameObject) -> (x: Int, z: Int) {
        let footprint = objectFootprint(for: object)
        if let def = GameObjectDefinitions.get(object.objectId), def.type == 2 || def.type == 3 {
            return nearestInteractionTile(inside: footprint)
        }
        return nearestApproachTile(around: footprint)
    }

    private func approachTileForObject(x: Int, z: Int) -> (x: Int, z: Int) {
        if let object = worldState.gameObjects.first(where: { $0.x == x && $0.y == z }) {
            return approachTile(for: object)
        }
        return (x, z)
    }

    private func approachTileForWall(x: Int, z: Int, direction: Int) -> (x: Int, z: Int) {
        let candidates: [(x: Int, z: Int)]
        switch direction {
        case 0:
            // Java walkToWall uses the area spanning both sides of the north
            // boundary: (x,z-1) through (x,z). Pick the reachable side nearest
            // the player instead of always forcing the north tile.
            candidates = [(x, z - 1), (x, z)]
        case 1:
            // Vertical boundary: reachable from either (x-1,z) or (x,z).
            candidates = [(x - 1, z), (x, z)]
        default:
            candidates = [(x, z)]
        }
        return nearestReachableTile(from: candidates, fallback: candidates[0])
    }

    private func approachTileForGroundItem(x: Int, z: Int) -> (x: Int, z: Int) {
        let pathfinder = Pathfinder(landscapeLoader: landscapeLoader, worldState: worldState)
        if !pathfinder.findPath(
            fromX: worldState.localPlayerX,
            fromZ: worldState.localPlayerY,
            toX: x,
            toZ: z,
            maxSteps: 25
        ).isEmpty {
            return (x, z)
        }

        let candidates = [
            (x, z - 1), (x + 1, z), (x, z + 1), (x - 1, z),
            (x + 1, z - 1), (x + 1, z + 1), (x - 1, z + 1), (x - 1, z - 1)
        ].sorted {
            let da = ($0.0 - worldState.localPlayerX) * ($0.0 - worldState.localPlayerX)
                + ($0.1 - worldState.localPlayerY) * ($0.1 - worldState.localPlayerY)
            let db = ($1.0 - worldState.localPlayerX) * ($1.0 - worldState.localPlayerX)
                + ($1.1 - worldState.localPlayerY) * ($1.1 - worldState.localPlayerY)
            return da < db
        }

        for candidate in candidates {
            let path = pathfinder.findPath(
                fromX: worldState.localPlayerX,
                fromZ: worldState.localPlayerY,
                toX: candidate.0,
                toZ: candidate.1,
                maxSteps: 25
            )
            if !path.isEmpty || (candidate.0 == worldState.localPlayerX && candidate.1 == worldState.localPlayerY) {
                return candidate
            }
        }
        return (x, z)
    }

    private func serverTileX(_ localX: Int) -> Int {
        worldState.serverTileX(localX)
    }

    private func serverTileZ(_ localZ: Int) -> Int {
        worldState.serverTileZ(localZ)
    }

    @discardableResult
    private func sendWalkPath(toX destX: Int, toZ destZ: Int, walkToEntity: Bool) async -> [(x: Int, z: Int)] {
        if worldState.localPlayerX == destX && worldState.localPlayerY == destZ {
            return []
        }

        let pathfinder = Pathfinder(landscapeLoader: landscapeLoader, worldState: worldState)
        let path = pathfinder.findPath(
            fromX: worldState.localPlayerX,
            fromZ: worldState.localPlayerY,
            toX: destX,
            toZ: destZ,
            maxSteps: 25
        )

        let encodedPath: [(x: Int, z: Int)]
        if path.isEmpty {
            worldState.walkTargetTimeout = 0
            worldState.addChat(sender: "[Path]", text: "I can't reach that.")
            return []
        } else {
            encodedPath = path
        }

        let markerEnd = encodedPath.last
        worldState.walkTargetX = markerEnd?.x ?? destX
        worldState.walkTargetY = markerEnd?.z ?? destZ
        worldState.walkTargetTimeout = 80

        // Java sends the first actual path step as the packet anchor, then
        // up to 25 signed waypoint deltas relative to that anchor. The server
        // adds the anchor itself as step zero, so using the current player tile
        // here makes movement/action paths collapse or lag behind the tap.
        // The anchor is transmitted in Java/server tile coordinates
        // (midRegionBase + local). worldOffset is only for local terrain
        // archive addressing and must not be sent back to the server.
        let serverPath = encodedPath.map { (x: serverTileX($0.x), z: serverTileZ($0.z)) }
        let firstStep = encodedPath[0]
        let packet = Self.makeWalkPacket(serverPath: serverPath, walkToEntity: walkToEntity)
        logAction(
            walkToEntity ? "walk-entity" : "walk",
            opcode: walkToEntity ? Int(RSCOutOpcode.walkToEntity.rawValue) : Int(RSCOutOpcode.walkToPoint.rawValue),
            payload: packet,
            details: "dest=(\(destX),\(destZ)) first=(\(firstStep.x),\(firstStep.z)) steps=\(encodedPath.count)"
        )
        try? await connection.send(packet)
        return encodedPath
    }

    private func queueApproach(toX destX: Int, z destZ: Int, action: String) async -> Bool {
        let path = await sendWalkPath(toX: destX, toZ: destZ, walkToEntity: true)
        if worldState.localPlayerX == destX && worldState.localPlayerY == destZ {
            return true
        }
        guard !path.isEmpty else {
            print("[Action] blocked action=\"\(action)\" approach=(\(destX),\(destZ))")
            return false
        }
        return true
    }

    private func queueEntityApproach(toX destX: Int, z destZ: Int, action: String) async -> Bool {
        let dx = abs(worldState.localPlayerX - destX)
        let dz = abs(worldState.localPlayerY - destZ)
        if max(dx, dz) <= 1 {
            return true
        }
        return await queueApproach(toX: destX, z: destZ, action: action)
    }

    static func makeWalkPacket(serverPath: [(x: Int, z: Int)], walkToEntity: Bool) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(walkToEntity ? RSCOutOpcode.walkToEntity.rawValue : RSCOutOpcode.walkToPoint.rawValue))
        guard let firstStep = serverPath.first else { return buf.finishPacket() }
        buf.putShort(firstStep.x)
        buf.putShort(firstStep.z)
        for wp in serverPath.dropFirst().prefix(25) {
            let dx = max(-128, min(127, wp.x - firstStep.x))
            let dz = max(-128, min(127, wp.z - firstStep.z))
            buf.putByte(dx)
            buf.putByte(dz)
        }
        return buf.finishPacket()
    }

    func blink(toX x: Int, z: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.blink.rawValue))
            buf.putShort(serverTileX(x))
            buf.putShort(serverTileZ(z))
            try? await connection.send(buf.finishPacket())
        }
    }

    private func handleTap(x: Int, y: Int) {
        guard !worldInputBlockedByModal else { return }

        let gameX = Double(x)
        let gameY = Double(y)
        let target = worldTileNearestScreenPoint(gameX: Double(x), gameY: Double(y))
        let destX = target.x
        let destZ = target.z

        let screenNPC = nearestNPCOnScreen(gameX: gameX, gameY: gameY)
        let screenPlayer = nearestPlayerOnScreen(gameX: gameX, gameY: gameY)
        let screenGroundItem = nearestGroundItemOnScreen(gameX: gameX, gameY: gameY)
        let screenObject = nearestGameObjectOnScreen(gameX: gameX, gameY: gameY)
        let screenWall = nearestWallObjectOnScreen(gameX: gameX, gameY: gameY)

        let exactNPC = npc(atX: destX, z: destZ)
        let exactPlayer = player(atX: destX, z: destZ)
        let exactGroundItem = groundItem(atX: destX, z: destZ)
        let exactObject = gameObject(containingX: destX, z: destZ)
        let exactWall = wallObject(atX: destX, z: destZ)

        // Item-use target mode — armed by inventory "Use". The next tap on a
        // world entity consumes the pending item instead of doing default walk
        // or talk behavior.
        if let itemSlot = worldState.pendingItemUseSlot {
            let targetNPC = screenNPC ?? exactNPC
            let targetPlayer = screenPlayer ?? exactPlayer
            let targetGroundItem = screenGroundItem ?? exactGroundItem
            let targetWall = screenWall ?? exactWall
            let targetObject = screenObject ?? exactObject
            if let npc = targetNPC {
                worldState.pendingItemUseSlot = nil
                print("[Input] Use item slot \(itemSlot) on NPC \(npc.id)")
                useItemOnNPC(slot: itemSlot, serverIndex: npc.id)
            } else if let player = targetPlayer {
                worldState.pendingItemUseSlot = nil
                print("[Input] Use item slot \(itemSlot) on player \(player.id)")
                useItemOnPlayer(slot: itemSlot, serverIndex: player.id)
            } else if let item = targetGroundItem {
                worldState.pendingItemUseSlot = nil
                print("[Input] Use item slot \(itemSlot) on ground item \(item.itemId)")
                useItemOnGroundItem(slot: itemSlot, x: item.x, z: item.y, itemId: item.itemId)
            } else if let wall = targetWall {
                worldState.pendingItemUseSlot = nil
                print("[Input] Use item slot \(itemSlot) on wall \(wall.wallId)")
                useItemOnWall(slot: itemSlot, x: wall.x, z: wall.y, direction: wall.direction)
            } else if let object = targetObject {
                worldState.pendingItemUseSlot = nil
                print("[Input] Use item slot \(itemSlot) on object \(object.objectId)")
                useItemOnObject(slot: itemSlot, x: object.x, z: object.y)
            } else {
                worldState.addChat(sender: "[Use]", text: "No target selected. Tap a target or cancel.")
            }
            return
        }

        // Spell-cast target mode — armed by SpellbookPanel / MagicPanelView.
        // The next world tap is consumed as the spell target instead of
        // triggering walk/talk. Resolve specific entities before falling back
        // to a bare land cast.
        if let spellId = worldState.pendingSpellId {
            worldState.pendingSpellId = nil
            let targetNPC = screenNPC ?? exactNPC
            let targetPlayer = screenPlayer ?? exactPlayer
            let targetGroundItem = screenGroundItem ?? exactGroundItem
            let targetWall = screenWall ?? exactWall
            let targetObject = screenObject ?? exactObject
            if let npc = targetNPC {
                print("[Input] Cast spell \(spellId) on NPC \(npc.id)")
                castSpellOnNPC(spellId: spellId, npcServerIndex: npc.id)
            } else if let player = targetPlayer {
                print("[Input] Cast spell \(spellId) on player \(player.id)")
                castSpellOnPlayer(spellId: spellId, playerServerIndex: player.id)
            } else if let item = targetGroundItem {
                print("[Input] Cast spell \(spellId) on ground item \(item.itemId)")
                castSpellOnGroundItem(spellId: spellId, x: item.x, z: item.y, itemId: item.itemId)
            } else if let wall = targetWall {
                print("[Input] Cast spell \(spellId) on wall \(wall.wallId)")
                castSpellOnWall(spellId: spellId, x: wall.x, z: wall.y, direction: wall.direction)
            } else if let object = targetObject {
                print("[Input] Cast spell \(spellId) on object \(object.objectId)")
                castSpellOnObject(spellId: spellId, x: object.x, z: object.y)
            } else {
                print("[Input] Cast spell \(spellId) on ground (\(destX),\(destZ))")
                castSpellOnGround(spellId: spellId, x: destX, z: destZ)
            }
            return
        }

        let targetNPC = screenNPC ?? exactNPC
        let targetGroundItem = screenGroundItem ?? exactGroundItem
        let targetWall = screenWall ?? exactWall
        let targetObject = screenObject ?? exactObject

        if let npc = targetNPC {
            performPrimaryNPCAction(npc)
        } else if let item = targetGroundItem {
            // PC left-click priority takes ground items when the click lands on
            // the item marker. Keep plain terrain taps as walking.
            print("[Input] Take ground item \(item.itemId) at (\(item.x),\(item.y))")
            pickupGroundItem(x: item.x, y: item.y, itemId: item.itemId)
        } else if let wall = targetWall {
            let action = primaryWallAction(for: wall)
            print("[Input] \(action?.command ?? "Use") wall \(wall.wallId) at (\(wall.x),\(wall.y)) dir=\(wall.direction)")
            if action?.useFirstAction == false {
                wallAction2(x: wall.x, z: wall.y, direction: wall.direction)
            } else {
                wallAction1(x: wall.x, z: wall.y, direction: wall.direction)
            }
        } else if let object = targetObject,
                  let action = primaryObjectAction(for: object) {
            print("[Input] \(action.command) object \(object.objectId) at (\(object.x),\(object.y))")
            if action.useFirstAction {
                objectAction1(x: object.x, z: object.y)
            } else {
                objectAction2(x: object.x, z: object.y)
            }
        } else {
            // No NPC nearby → walk to destination with pathfinding
            let pathfinder = Pathfinder(landscapeLoader: landscapeLoader, worldState: worldState)
            let path = pathfinder.findPath(fromX: worldState.localPlayerX, fromZ: worldState.localPlayerY,
                                           toX: destX, toZ: destZ, maxSteps: 25)
            print("[Input] Walk to (\(destX),\(destZ)) path=\(path.count) waypoints")
            Task {
                await sendWalkPath(toX: destX, toZ: destZ, walkToEntity: false)
            }
        }
    }

    private func performPrimaryNPCAction(_ npc: RSCNPC) {
        guard let def = NPCDefinitions.get(npc.npcId) else {
            print("[Input] Talk to NPC \(npc.npcId) (server index \(npc.id)) at (\(npc.x),\(npc.y))")
            talkToNPC(serverIndex: npc.id)
            return
        }

        let command1 = def.command.trimmingCharacters(in: .whitespacesAndNewlines)
        let command2 = def.command2.trimmingCharacters(in: .whitespacesAndNewlines)
        let command1Valid = isActionableCommand(command1)
        let command2Valid = isActionableCommand(command2)

        if command1Valid {
            print("[Input] \(command1) NPC \(npc.npcId) (server index \(npc.id)) at (\(npc.x),\(npc.y))")
            npcCommand(serverIndex: npc.id)
        } else if def.attackable {
            print("[Input] Attack NPC \(npc.npcId) (server index \(npc.id)) at (\(npc.x),\(npc.y))")
            attackNPC(serverIndex: npc.id)
        } else if command2Valid {
            print("[Input] \(command2) NPC \(npc.npcId) (server index \(npc.id)) at (\(npc.x),\(npc.y))")
            npcCommand2(serverIndex: npc.id)
        } else {
            print("[Input] Talk to NPC \(npc.npcId) (server index \(npc.id)) at (\(npc.x),\(npc.y))")
            talkToNPC(serverIndex: npc.id)
        }
    }

    // MARK: - Context Menu

    func showContextMenu(at screenPoint: CGPoint) {
        guard !worldInputBlockedByModal else { return }

        // Convert screen point to game pixel coordinates
        let viewSize = touchTranslator.viewSize
        let scaleX = CGFloat(MetalRenderer.gameWidth) / max(1, viewSize.width)
        let scaleY = CGFloat(MetalRenderer.gameHeight) / max(1, viewSize.height)
        let gx = Double(screenPoint.x) * Double(scaleX)
        let gy = Double(screenPoint.y) * Double(scaleY)

        let target = worldTileNearestScreenPoint(gameX: gx, gameY: gy)
        let worldX = target.x
        let worldZ = target.z
        let screenNPC = nearestNPCOnScreen(gameX: gx, gameY: gy)
        let screenPlayer = nearestPlayerOnScreen(gameX: gx, gameY: gy)
        let screenItem = nearestGroundItemOnScreen(gameX: gx, gameY: gy)
        let screenObject = nearestGameObjectOnScreen(gameX: gx, gameY: gy)
        let screenWall = nearestWallObjectOnScreen(gameX: gx, gameY: gy)
        let targetNPC = screenNPC ?? npc(atX: worldX, z: worldZ)
        let targetPlayer = screenPlayer ?? player(atX: worldX, z: worldZ)
        let targetItem = screenItem ?? groundItem(atX: worldX, z: worldZ)
        let targetWall = screenWall ?? wallObject(atX: worldX, z: worldZ)
        let targetObject = screenObject ?? gameObject(containingX: worldX, z: worldZ)

        var actions: [(label: String, icon: String, action: () -> Void)] = []
        var title = "(\(worldX), \(worldZ))"
        let pendingItemSlot = worldState.pendingItemUseSlot
        let pendingItemName = pendingItemSlot
            .flatMap { slot in worldState.inventory.first(where: { $0.id == slot })?.itemId }
            .map { ItemNames.name(for: $0) } ?? "item"
        let pendingSpellId = worldState.pendingSpellId
        let normalAction: (@escaping () -> Void) -> () -> Void = { [weak self] action in
            {
                self?.worldState.clearPendingTargetMode()
                action()
            }
        }

        if pendingItemSlot != nil || pendingSpellId != nil {
            actions.append(("Cancel target selection", "xmark.circle", { [weak self] in
                self?.worldState.pendingItemUseSlot = nil
                self?.worldState.pendingSpellId = nil
                self?.worldState.addChat(sender: "[Action]", text: "Cancelled")
            }))
        }
        if worldState.insideTutorial {
            actions.append(("Skip tutorial", "forward.end.fill", { [weak self] in
                self?.skipTutorial()
            }))
        }

        // Check NPCs (within 2 tiles). Always offer Examine; offer Attack only
        // for combat-eligible NPCs (NPCDef.attackable == true).
        for npc in targetNPC.map({ [$0] }) ?? worldState.npcs {
            let dx: Int = npc.x - worldX; let dz: Int = npc.y - worldZ
            let distSq: Int = dx * dx + dz * dz
            if targetNPC?.id == npc.id || (targetNPC == nil && distSq <= 1) {
                title = npc.name
                if let pendingItemSlot {
                    actions.append(("Use \(pendingItemName) with \(npc.name)", "hand.point.up.left", { [weak self] in
                        self?.useItemOnNPC(slot: pendingItemSlot, serverIndex: npc.id)
                    }))
                }
                if let pendingSpellId {
                    actions.append(("Cast spell on \(npc.name)", "sparkles", { [weak self] in
                        self?.castSpellOnNPC(spellId: pendingSpellId, npcServerIndex: npc.id)
                    }))
                }
                actions.append(("Talk to \(npc.name)", "bubble.left", normalAction { [weak self] in
                    self?.talkToNPC(serverIndex: npc.id)
                }))
                if let def = NPCDefinitions.get(npc.npcId) {
                    let command1 = def.command.trimmingCharacters(in: .whitespacesAndNewlines)
                    let command2 = def.command2.trimmingCharacters(in: .whitespacesAndNewlines)
                    if def.attackable {
                        actions.append(("Attack \(npc.name) (lvl \(def.combatLevel))", "bolt.fill", normalAction { [weak self] in
                            self?.attackNPC(serverIndex: npc.id)
                        }))
                    }
                    if isActionableCommand(command1) {
                        actions.append(("\(command1) \(npc.name)", "hand.raised", normalAction { [weak self] in
                            self?.npcCommand(serverIndex: npc.id)
                        }))
                    }
                    if isActionableCommand(command2) {
                        actions.append(("\(command2) \(npc.name)", "ellipsis.circle", normalAction { [weak self] in
                            self?.npcCommand2(serverIndex: npc.id)
                        }))
                    }
                }
                actions.append(("Examine \(npc.name)", "eye", normalAction { [weak self] in
                    let descr = NPCDefinitions.get(npc.npcId)?.description ?? npc.name
                    self?.worldState.addChat(sender: "[Examine]", text: descr)
                }))
                break
            }
        }

        // Check players (within 2 tiles). Add Trade + Duel + Follow + Examine.
        for player in targetPlayer.map({ [$0] }) ?? worldState.players {
            let pdx: Int = player.x - worldX; let pdz: Int = player.y - worldZ
            if targetPlayer?.id == player.id || (targetPlayer == nil && pdx * pdx + pdz * pdz <= 1) {
                title = player.name
                if let pendingItemSlot {
                    actions.append(("Use \(pendingItemName) with \(player.name)", "hand.point.up.left", { [weak self] in
                        self?.useItemOnPlayer(slot: pendingItemSlot, serverIndex: player.id)
                    }))
                }
                if let pendingSpellId {
                    actions.append(("Cast spell on \(player.name)", "sparkles", { [weak self] in
                        self?.castSpellOnPlayer(spellId: pendingSpellId, playerServerIndex: player.id)
                    }))
                }
                actions.append(("Attack \(player.name)", "bolt.fill", normalAction { [weak self] in
                    self?.attackPlayer(serverIndex: player.id)
                }))
                actions.append(("Trade with \(player.name)", "arrow.left.arrow.right", normalAction { [weak self] in
                    self?.requestTrade(serverIndex: player.id)
                }))
                actions.append(("Duel \(player.name)", "shield.lefthalf.filled", normalAction { [weak self] in
                    self?.requestDuel(serverIndex: player.id)
                }))
                actions.append(("Follow \(player.name)", "figure.walk", normalAction { [weak self] in
                    self?.followPlayer(serverIndex: player.id)
                }))
                actions.append(("Examine \(player.name)", "eye", normalAction { [weak self] in
                    self?.worldState.addChat(sender: "[Examine]", text: "\(player.name) (combat level \(player.combatLevel))")
                }))
                break
            }
        }

        // Check ground items (within 2 tiles)
        for item in targetItem.map({ [$0] }) ?? worldState.groundItems {
            let idx: Int = item.x - worldX; let idz: Int = item.y - worldZ
            if (targetItem?.x == item.x && targetItem?.y == item.y && targetItem?.itemId == item.itemId)
                || (targetItem == nil && idx * idx + idz * idz <= 1) {
                let itemName = ItemNames.name(for: item.itemId)
                title = itemName
                if let pendingItemSlot {
                    actions.append(("Use \(pendingItemName) with \(itemName)", "hand.point.up.left", { [weak self] in
                        self?.useItemOnGroundItem(slot: pendingItemSlot, x: item.x, z: item.y, itemId: item.itemId)
                    }))
                }
                if let pendingSpellId {
                    actions.append(("Cast spell on \(itemName)", "sparkles", { [weak self] in
                        self?.castSpellOnGroundItem(spellId: pendingSpellId, x: item.x, z: item.y, itemId: item.itemId)
                    }))
                }
                actions.append(("Take \(itemName)", "arrow.down.circle", normalAction { [weak self] in
                    self?.pickupGroundItem(x: item.x, y: item.y, itemId: item.itemId)
                }))
                break
            }
        }

        // Check boundary/wall objects (doors, gates, fences). Java keeps these
        // separate from scenery and sends boundary-specific opcodes that include
        // direction, so route them through their own actions.
        for wall in targetWall.map({ [$0] }) ?? worldState.wallObjects {
            let wdx = wall.x - worldX
            let wdz = wall.y - worldZ
            if targetWall?.id == wall.id || (targetWall == nil && wdx * wdx + wdz * wdz <= 1) {
                let wallName = EntityDefinitions.getDoorDef(wall.wallId)?.name ?? "Door"
                title = wallName
                if let pendingItemSlot {
                    actions.append(("Use \(pendingItemName) with \(wallName)", "hand.point.up.left", { [weak self] in
                        self?.useItemOnWall(slot: pendingItemSlot, x: wall.x, z: wall.y, direction: wall.direction)
                    }))
                }
                if let pendingSpellId {
                    actions.append(("Cast spell on \(wallName)", "sparkles", { [weak self] in
                        self?.castSpellOnWall(spellId: pendingSpellId, x: wall.x, z: wall.y, direction: wall.direction)
                    }))
                }
                if let def = EntityDefinitions.getDoorDef(wall.wallId) {
                    let command1 = def.command1.trimmingCharacters(in: .whitespacesAndNewlines)
                    let command2 = def.command2.trimmingCharacters(in: .whitespacesAndNewlines)
                    if isActionableCommand(command1) {
                        actions.append(("\(command1) \(wallName)", "door.left.hand.open", normalAction { [weak self] in
                            self?.wallAction1(x: wall.x, z: wall.y, direction: wall.direction)
                        }))
                    }
                    if isActionableCommand(command2) {
                        actions.append(("\(command2) \(wallName)", "door.left.hand.closed", normalAction { [weak self] in
                            self?.wallAction2(x: wall.x, z: wall.y, direction: wall.direction)
                        }))
                    }
                } else {
                    actions.append(("Open \(wallName)", "door.left.hand.open", normalAction { [weak self] in
                        self?.wallAction1(x: wall.x, z: wall.y, direction: wall.direction)
                    }))
                    actions.append(("Close \(wallName)", "door.left.hand.closed", normalAction { [weak self] in
                        self?.wallAction2(x: wall.x, z: wall.y, direction: wall.direction)
                    }))
                }
                actions.append(("Examine \(wallName)", "eye", normalAction { [weak self] in
                    self?.worldState.addChat(sender: "[Examine]", text: wallName)
                }))
                break
            }
        }

        // Check game objects (within 2 tiles). This deliberately comes after
        // boundary/wall objects so broad scenery hitboxes cannot hide doors,
        // gates, or fences under the same finger.
        for obj in targetObject.map({ [$0] }) ?? worldState.gameObjects {
            let odx: Int = obj.x - worldX; let odz: Int = obj.y - worldZ
            if targetObject?.id == obj.id || (targetObject == nil && odx * odx + odz * odz <= 1) {
                let def = GameObjectDefinitions.get(obj.objectId)
                let objName = def?.name.isEmpty == false ? def!.name : ObjectNames.name(for: obj.objectId)
                title = objName
                let command1 = def?.command1.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let command2 = def?.command2.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if let pendingItemSlot {
                    actions.append(("Use \(pendingItemName) with \(objName)", "hand.point.up.left", { [weak self] in
                        self?.useItemOnObject(slot: pendingItemSlot, x: obj.x, z: obj.y)
                    }))
                }
                if let pendingSpellId {
                    actions.append(("Cast spell on \(objName)", "sparkles", { [weak self] in
                        self?.castSpellOnObject(spellId: pendingSpellId, x: obj.x, z: obj.y)
                    }))
                }
                if isActionableCommand(command1) {
                    actions.append(("\(command1) \(objName)", "hand.tap", normalAction { [weak self] in
                        self?.objectAction1(x: obj.x, z: obj.y)
                    }))
                }
                if isActionableCommand(command2) {
                    actions.append(("\(command2) \(objName)", "ellipsis.circle", normalAction { [weak self] in
                        self?.objectAction2(x: obj.x, z: obj.y)
                    }))
                }
                actions.append(("Examine \(objName)", "eye", normalAction { [weak self] in
                    self?.worldState.addChat(sender: "[Examine]", text: def?.description.isEmpty == false ? def!.description : objName)
                }))
                break
            }
        }

        // Always add walk option
        actions.append(("Walk here", "figure.walk", normalAction { [weak self] in
            Task {
                await self?.sendWalkPath(toX: worldX, toZ: worldZ, walkToEntity: false)
            }
        }))

        if !actions.isEmpty {
            worldState.contextMenuTitle = title
            worldState.contextMenuActions = actions
            worldState.contextMenuOpen = true
        }
    }

    // MARK: - Combat actions

    func attackNPC(serverIndex: Int) {
        Task {
            if let npc = worldState.npcs.first(where: { $0.id == serverIndex }) {
                guard await queueEntityApproach(toX: npc.x, z: npc.y, action: "npc-attack") else { return }
            }
            let data = Self.makeNpcTargetPacket(opcode: .npcAttack, serverIndex: serverIndex)
            logAction("npc-attack", opcode: RSCOutOpcode.npcAttack, payload: data, details: "serverIndex=\(serverIndex)")
            try? await connection.send(data)
        }
    }

    func attackPlayer(serverIndex: Int) {
        Task {
            if let player = worldState.players.first(where: { $0.id == serverIndex }) {
                guard await queueEntityApproach(toX: player.x, z: player.y, action: "player-attack") else { return }
            }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.playerAttack.rawValue))
            buf.putShort(serverIndex)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }

    func setCombatStyle(_ style: Int) {
        worldState.combatStyle = style
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.combatStyleChange.rawValue))
            buf.putByte(style)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }

    func toggleRun() {
        worldState.runEnabled.toggle()
        updatePreferences { prefs in
            prefs.runByDefault = worldState.runEnabled
        }

        // The handoff suspected opcode 185, but the modern parser maps 185 to
        // spell-cast actions for several payload versions. Until the server
        // exposes a confirmed run-mode input opcode, keep this as local HUD
        // state instead of risking a wrong movement packet.
        print("[Input] Run mode \(worldState.runEnabled ? "enabled" : "disabled") locally; no confirmed run opcode available")
    }

    func talkToNPC(serverIndex: Int) {
        Task {
            if let npc = worldState.npcs.first(where: { $0.id == serverIndex }) {
                guard await queueEntityApproach(toX: npc.x, z: npc.y, action: "npc-talk") else { return }
            }
            let data = Self.makeNpcTargetPacket(opcode: .npcTalkTo, serverIndex: serverIndex)
            logAction("npc-talk", opcode: RSCOutOpcode.npcTalkTo, payload: data, details: "serverIndex=\(serverIndex)")
            try? await connection.send(data)
        }
    }

    // MARK: - Dialogue

    func answerDialogue(_ optionIndex: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.dialogueAnswer.rawValue))
            buf.putByte(optionIndex)
            try? await connection.send(buf.finishPacket())
        }
    }

    func logout() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.logout.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    func skipTutorial() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.skipTutorial.rawValue))
            try? await connection.send(buf.finishPacket())
            worldState.addChat(sender: "[Tutorial]", text: "Skip tutorial requested.")
        }
    }

    // MARK: - Chat

    func sendChatMessage(_ text: String) {
        worldState.addChat(sender: worldState.localPlayerName, text: text, isLocal: true)
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.chatMessage.rawValue))
            buf.putEncryptedString(text)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }

    func sendPrivateMessage(to recipient: String, text: String) {
        worldState.addChat(sender: "To \(recipient)", text: text, isLocal: true, isPrivate: true)
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.privateMessage.rawValue))
            buf.putString(recipient)
            buf.putEncryptedString(text)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }

    func sendServerCommand(_ command: String) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.command.rawValue))
            buf.putString(command)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }

    func reportAbuse(playerName: String, reason: Int, suggestsOrMutes: Bool) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.reportAbuse.rawValue))
            buf.putString(playerName)
            buf.putByte(reason)
            buf.putByte(suggestsOrMutes ? 1 : 0)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }

    // MARK: - Inventory actions

    private func logAction(_ name: String, opcode: RSCOutOpcode, payload: Data, details: String = "") {
        let suffix = details.isEmpty ? "" : " \(details)"
        print("[Action] \(name) opcode=\(opcode.rawValue) bytes=\(payload.count)\(suffix)")
    }

    private func logAction(_ name: String, opcode: Int, payload: Data, details: String = "") {
        let suffix = details.isEmpty ? "" : " \(details)"
        print("[Action] \(name) opcode=\(opcode) bytes=\(payload.count)\(suffix)")
    }

    func equipItem(slot: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.itemEquip.rawValue))
            buf.putShort(slot)
            let data = buf.finishPacket()
            logAction("equip", opcode: RSCOutOpcode.itemEquip, payload: data, details: "slot=\(slot)")
            try? await connection.send(data)
        }
    }

    func unequipItem(slot: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.itemUnequip.rawValue))
            buf.putShort(slot)
            let data = buf.finishPacket()
            logAction("unequip", opcode: RSCOutOpcode.itemUnequip, payload: data, details: "slot=\(slot)")
            try? await connection.send(data)
        }
    }

    func unequipEquipmentSlot(_ slot: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.itemUnequipFromEquipment.rawValue))
            buf.putByte(slot)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }

    static func makeItemDropPacket(slot: Int, amount: Int) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(RSCOutOpcode.itemDrop.rawValue))
        buf.putShort(slot)
        buf.putInt(max(1, amount))
        return buf.finishPacket()
    }

    static func makeItemCommandPacket(slot: Int, commandIndex: Int, amount: Int) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(RSCOutOpcode.itemCommand.rawValue))
        buf.putShort(slot)
        buf.putInt(max(1, amount))
        buf.putByte(commandIndex)
        return buf.finishPacket()
    }

    static func makeItemUseOnGroundPacket(x: Int, z: Int, groundItemId: Int, slot: Int) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(RSCOutOpcode.itemUseOnGround.rawValue))
        buf.putShort(x)
        buf.putShort(z)
        buf.putShort(slot)
        buf.putShort(groundItemId)
        return buf.finishPacket()
    }

    static func makeNpcTargetPacket(opcode: RSCOutOpcode, serverIndex: Int) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(opcode.rawValue))
        buf.putShort(serverIndex)
        return buf.finishPacket()
    }

    static func makeGroundItemTakePacket(x: Int, z: Int, itemId: Int) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(RSCOutOpcode.groundItemTake.rawValue))
        buf.putShort(x)
        buf.putShort(z)
        buf.putShort(itemId)
        return buf.finishPacket()
    }

    static func makeObjectActionPacket(opcode: RSCOutOpcode, x: Int, z: Int) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(opcode.rawValue))
        buf.putShort(x)
        buf.putShort(z)
        return buf.finishPacket()
    }

    static func makeWallActionPacket(opcode: RSCOutOpcode, x: Int, z: Int, direction: Int) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(opcode.rawValue))
        buf.putShort(x)
        buf.putShort(z)
        buf.putByte(direction)
        return buf.finishPacket()
    }

    static func makeItemUseOnObjectPacket(x: Int, z: Int, slot: Int) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(RSCOutOpcode.itemUseOnObject.rawValue))
        buf.putShort(x)
        buf.putShort(z)
        buf.putShort(slot)
        return buf.finishPacket()
    }

    static func makeItemUseOnWallPacket(x: Int, z: Int, direction: Int, slot: Int) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(RSCOutOpcode.wallUseItem.rawValue))
        buf.putShort(x)
        buf.putShort(z)
        buf.putByte(direction)
        buf.putShort(slot)
        return buf.finishPacket()
    }

    func dropItem(slot: Int) {
        Task {
            let amount = worldState.inventory.indices.contains(slot) ? worldState.inventory[slot].amount : 1
            let packet = Self.makeItemDropPacket(slot: slot, amount: amount)
            logAction("drop", opcode: RSCOutOpcode.itemDrop, payload: packet, details: "slot=\(slot) amount=\(max(1, amount))")
            try? await connection.send(packet)
        }
    }

    func itemCommands(for itemId: Int) -> [String] {
        ItemDefinitions.commandOptions(for: itemId).map(\.label)
    }

    func itemCommandOptions(for itemId: Int) -> [ItemCommandOption] {
        ItemDefinitions.commandOptions(for: itemId)
    }

    func itemCommand(slot: Int, commandIndex: Int, amount: Int = 1) {
        Task {
            let packet = Self.makeItemCommandPacket(
                slot: slot,
                commandIndex: commandIndex,
                amount: amount
            )
            logAction("item-command", opcode: RSCOutOpcode.itemCommand, payload: packet, details: "slot=\(slot) command=\(commandIndex) amount=\(max(1, amount))")
            try? await connection.send(packet)
        }
    }

    func itemCommandAll(slot: Int, commandIndex: Int) {
        let amount = worldState.inventory.indices.contains(slot) ? worldState.inventory[slot].amount : 1
        itemCommand(slot: slot, commandIndex: commandIndex, amount: amount)
    }

    func useItem(slot: Int) {
        if let spellId = worldState.pendingSpellId {
            castSpellOnItem(spellId: spellId, slot: slot)
            return
        }

        if let pending = worldState.pendingItemUseSlot {
            if pending == slot {
                cancelItemUse()
            } else {
                useItemOnItem(slot1: pending, slot2: slot)
            }
            return
        }

        worldState.pendingSpellId = nil
        worldState.pendingItemUseSlot = slot
        if let item = worldState.inventory.first(where: { $0.id == slot }) {
            print("[Action] use-arm slot=\(slot) item=\(item.itemId)")
            worldState.addChat(sender: "[Use]", text: "Select a target for \(ItemNames.name(for: item.itemId))")
        }
    }

    func cancelItemUse() {
        worldState.pendingItemUseSlot = nil
        worldState.addChat(sender: "[Use]", text: "Cancelled")
    }

    private func clearPendingItemUse() {
        worldState.pendingItemUseSlot = nil
    }

    func itemUseLabel(for slot: Int?) -> String {
        guard let slot,
              let item = worldState.inventory.first(where: { $0.id == slot }) else {
            return "item"
        }
        return ItemNames.name(for: item.itemId)
    }

    func useItemOnNPC(slot: Int, serverIndex: Int) {
        Task {
            if let npc = worldState.npcs.first(where: { $0.id == serverIndex }) {
                guard await queueEntityApproach(toX: npc.x, z: npc.y, action: "item-on-npc") else { return }
            }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.itemUseOnNpc.rawValue))
            buf.putShort(serverIndex)
            buf.putShort(slot)
            try? await connection.send(buf.finishPacket())
            clearPendingItemUse()
        }
    }

    func useItemOnPlayer(slot: Int, serverIndex: Int) {
        Task {
            if let player = worldState.players.first(where: { $0.id == serverIndex }) {
                guard await queueEntityApproach(toX: player.x, z: player.y, action: "item-on-player") else { return }
            }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.playerUseItem.rawValue))
            buf.putShort(serverIndex)
            buf.putShort(slot)
            try? await connection.send(buf.finishPacket())
            clearPendingItemUse()
        }
    }

    func useItemOnGroundItem(slot: Int, x: Int, z: Int, itemId: Int) {
        Task {
            let approach = approachTileForGroundItem(x: x, z: z)
            guard await queueApproach(toX: approach.x, z: approach.z, action: "item-on-ground") else { return }
            try? await connection.send(Self.makeItemUseOnGroundPacket(
                x: serverTileX(x),
                z: serverTileZ(z),
                groundItemId: itemId,
                slot: slot
            ))
            clearPendingItemUse()
        }
    }

    func useItemOnObject(slot: Int, x: Int, z: Int) {
        Task {
            let approach = approachTileForObject(x: x, z: z)
            guard await queueApproach(toX: approach.x, z: approach.z, action: "item-on-object") else { return }
            try? await connection.send(Self.makeItemUseOnObjectPacket(
                x: serverTileX(x),
                z: serverTileZ(z),
                slot: slot
            ))
            clearPendingItemUse()
        }
    }

    func useItemOnWall(slot: Int, x: Int, z: Int, direction: Int) {
        Task {
            let approach = approachTileForWall(x: x, z: z, direction: direction)
            guard await queueApproach(toX: approach.x, z: approach.z, action: "item-on-wall") else { return }
            try? await connection.send(Self.makeItemUseOnWallPacket(
                x: serverTileX(x),
                z: serverTileZ(z),
                direction: direction,
                slot: slot
            ))
            clearPendingItemUse()
        }
    }

    func pickupGroundItem(x: Int, y: Int, itemId: Int) {
        Task {
            let approach = approachTileForGroundItem(x: x, z: y)
            guard await queueApproach(toX: approach.x, z: approach.z, action: "ground-take") else { return }
            let packet = Self.makeGroundItemTakePacket(x: serverTileX(x), z: serverTileZ(y), itemId: itemId)
            logAction("ground-take", opcode: RSCOutOpcode.groundItemTake, payload: packet, details: "item=\(itemId) tile=(\(x),\(y)) server=(\(serverTileX(x)),\(serverTileZ(y)))")
            try? await connection.send(packet)
        }
    }

    func useItemOnItem(slot1: Int, slot2: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.itemUseOnItem.rawValue))
            buf.putShort(slot1)
            buf.putShort(slot2)
            try? await connection.send(buf.finishPacket())
            clearPendingItemUse()
        }
    }

    // MARK: - Bank actions

    static func makeBankDepositPacket(itemId: Int, amount: Int) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(RSCOutOpcode.bankDeposit.rawValue))
        buf.putShort(itemId)
        buf.putInt(amount)
        return buf.finishPacket()
    }

    static func makeBankWithdrawPacket(itemId: Int, amount: Int, noted: Bool) -> Data {
        let buf = ByteBuffer()
        buf.newPacket(opcode: Int(RSCOutOpcode.bankWithdraw.rawValue))
        buf.putShort(itemId)
        buf.putInt(amount)
        buf.putByte(noted ? 1 : 0)
        return buf.finishPacket()
    }

    func bankDeposit(itemId: Int, amount: Int) {
        Task {
            try? await connection.send(Self.makeBankDepositPacket(itemId: itemId, amount: amount))
        }
    }

    func bankWithdraw(itemId: Int, amount: Int, noted: Bool = false) {
        Task {
            try? await connection.send(Self.makeBankWithdrawPacket(itemId: itemId, amount: amount, noted: noted))
        }
    }

    func bankDepositAllFromInventory() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.bankDepositAllInventory.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    func bankDepositAllFromEquipment() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.bankDepositAllEquipment.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    func bankSavePreset(slot: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.bankSavePreset.rawValue))
            buf.putShort(slot)
            try? await connection.send(buf.finishPacket())
        }
    }

    func bankLoadPreset(slot: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.bankLoadPreset.rawValue))
            buf.putShort(slot)
            try? await connection.send(buf.finishPacket())
        }
    }

    func bankEquipItem(slot: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.itemEquipFromBank.rawValue))
            buf.putShort(slot)
            try? await connection.send(buf.finishPacket())
        }
    }

    func bankRemoveEquipment(slot: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.itemRemoveToBank.rawValue))
            buf.putByte(slot)
            try? await connection.send(buf.finishPacket())
        }
    }

    func setBankNoteSwap(enabled: Bool) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.interfaceOptions.rawValue))
            buf.putByte(1) // InterfaceOptions.SWAP_NOTE
            buf.putByte(enabled ? 1 : 0)
            try? await connection.send(buf.finishPacket())
        }
    }

    func setCertSwap(enabled: Bool) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.interfaceOptions.rawValue))
            buf.putByte(0) // InterfaceOptions.SWAP_CERT
            buf.putByte(enabled ? 1 : 0)
            try? await connection.send(buf.finishPacket())
        }
    }

    func moveBankItem(from slot: Int, to targetSlot: Int, insert: Bool) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.interfaceOptions.rawValue))
            buf.putByte(insert ? 3 : 2) // BANK_INSERT / BANK_SWAP
            buf.putInt(slot)
            buf.putInt(targetSlot)
            try? await connection.send(buf.finishPacket())
        }
    }

    func moveInventoryItem(from slot: Int, to targetSlot: Int, insert: Bool) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.interfaceOptions.rawValue))
            buf.putByte(insert ? 4 : 5) // INVENTORY_INSERT / INVENTORY_SWAP
            buf.putInt(slot)
            buf.putInt(targetSlot)
            try? await connection.send(buf.finishPacket())
        }
    }

    func cancelBatchAction() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.interfaceOptions.rawValue))
            buf.putByte(6) // InterfaceOptions.CANCEL_BATCH
            try? await connection.send(buf.finishPacket())
        }
    }

    func submitBankPin(_ pin: String) {
        worldState.bankPinOpen = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.interfaceOptions.rawValue))
            buf.putByte(8) // InterfaceOptions.BANK_PIN
            buf.putByte(0) // submit entered pin
            buf.putString(pin)
            try? await connection.send(buf.finishPacket())
        }
    }

    func closeBank() {
        worldState.bankOpen = false
        worldState.clearPendingTargetMode()
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.bankClose.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Shop actions

    func shopBuy(itemId: Int, amount: Int) {
        let safeAmount = max(0, min(amount, 65_535))
        guard safeAmount > 0 else { return }
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.shopBuy.rawValue))
            buf.putShort(itemId)
            buf.putShort(worldState.shopItems.first(where: { $0.id == itemId })?.stock ?? 0)
            buf.putShort(safeAmount)
            try? await connection.send(buf.finishPacket())
        }
    }

    func shopSell(itemId: Int, amount: Int) {
        let safeAmount = max(0, min(amount, 65_535))
        guard safeAmount > 0 else { return }
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.shopSell.rawValue))
            buf.putShort(itemId)
            buf.putShort(worldState.shopItems.first(where: { $0.id == itemId })?.stock ?? 0)
            buf.putShort(safeAmount)
            try? await connection.send(buf.finishPacket())
        }
    }

    func closeShop() {
        worldState.shopOpen = false
        worldState.shopSellableItemIds = []
        worldState.clearPendingTargetMode()
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.shopClose.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Object/Wall interactions

    func objectAction1(x: Int, z: Int) {
        Task {
            let approach = approachTileForObject(x: x, z: z)
            guard await queueApproach(toX: approach.x, z: approach.z, action: "object-1") else { return }
            let packet = Self.makeObjectActionPacket(opcode: .objectCommand1, x: serverTileX(x), z: serverTileZ(z))
            logAction("object-1", opcode: RSCOutOpcode.objectCommand1, payload: packet, details: "tile=(\(x),\(z)) server=(\(serverTileX(x)),\(serverTileZ(z)))")
            try? await connection.send(packet)
        }
    }

    func objectAction2(x: Int, z: Int) {
        Task {
            let approach = approachTileForObject(x: x, z: z)
            guard await queueApproach(toX: approach.x, z: approach.z, action: "object-2") else { return }
            let packet = Self.makeObjectActionPacket(opcode: .objectCommand2, x: serverTileX(x), z: serverTileZ(z))
            logAction("object-2", opcode: RSCOutOpcode.objectCommand2, payload: packet, details: "tile=(\(x),\(z)) server=(\(serverTileX(x)),\(serverTileZ(z)))")
            try? await connection.send(packet)
        }
    }

    func wallAction1(x: Int, z: Int, direction: Int) {
        Task {
            let approach = approachTileForWall(x: x, z: z, direction: direction)
            guard await queueApproach(toX: approach.x, z: approach.z, action: "wall-1") else { return }
            let packet = Self.makeWallActionPacket(opcode: .wallCommand1, x: serverTileX(x), z: serverTileZ(z), direction: direction)
            logAction("wall-1", opcode: RSCOutOpcode.wallCommand1, payload: packet, details: "tile=(\(x),\(z)) dir=\(direction) server=(\(serverTileX(x)),\(serverTileZ(z)))")
            try? await connection.send(packet)
        }
    }

    func wallAction2(x: Int, z: Int, direction: Int) {
        Task {
            let approach = approachTileForWall(x: x, z: z, direction: direction)
            guard await queueApproach(toX: approach.x, z: approach.z, action: "wall-2") else { return }
            let packet = Self.makeWallActionPacket(opcode: .wallCommand2, x: serverTileX(x), z: serverTileZ(z), direction: direction)
            logAction("wall-2", opcode: RSCOutOpcode.wallCommand2, payload: packet, details: "tile=(\(x),\(z)) dir=\(direction) server=(\(serverTileX(x)),\(serverTileZ(z)))")
            try? await connection.send(packet)
        }
    }

    // MARK: - Magic & Prayer

    func castSpellOnSelf(spellId: Int) {
        worldState.clearPendingTargetMode()
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.castOnSelf.rawValue))
            buf.putShort(spellId)
            try? await connection.send(buf.finishPacket())
        }
    }

    func castSpellOnNPC(spellId: Int, npcServerIndex: Int) {
        Task {
            if let npc = worldState.npcs.first(where: { $0.id == npcServerIndex }) {
                guard await queueEntityApproach(toX: npc.x, z: npc.y, action: "spell-on-npc") else { return }
            }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.castOnNpc.rawValue))
            buf.putShort(spellId)
            buf.putShort(npcServerIndex)
            try? await connection.send(buf.finishPacket())
            worldState.clearPendingTargetMode()
        }
    }

    func castSpellOnPlayer(spellId: Int, playerServerIndex: Int) {
        Task {
            if let player = worldState.players.first(where: { $0.id == playerServerIndex }) {
                guard await queueEntityApproach(toX: player.x, z: player.y, action: "spell-on-player") else { return }
            }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.castOnPlayer.rawValue))
            buf.putShort(spellId)
            buf.putShort(playerServerIndex)
            try? await connection.send(buf.finishPacket())
            worldState.clearPendingTargetMode()
        }
    }

    func castSpellOnGroundItem(spellId: Int, x: Int, z: Int, itemId: Int) {
        Task {
            let approach = approachTileForGroundItem(x: x, z: z)
            guard await queueApproach(toX: approach.x, z: approach.z, action: "spell-on-ground") else { return }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.castOnGroundItem.rawValue))
            buf.putShort(spellId)
            buf.putShort(serverTileX(x))
            buf.putShort(serverTileZ(z))
            buf.putShort(itemId)
            try? await connection.send(buf.finishPacket())
            worldState.clearPendingTargetMode()
        }
    }

    func castSpellOnObject(spellId: Int, x: Int, z: Int) {
        Task {
            let approach = approachTileForObject(x: x, z: z)
            guard await queueApproach(toX: approach.x, z: approach.z, action: "spell-on-object") else { return }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.castOnObject.rawValue))
            buf.putShort(spellId)
            buf.putShort(serverTileX(x))
            buf.putShort(serverTileZ(z))
            try? await connection.send(buf.finishPacket())
            worldState.clearPendingTargetMode()
        }
    }

    func castSpellOnWall(spellId: Int, x: Int, z: Int, direction: Int) {
        Task {
            let approach = approachTileForWall(x: x, z: z, direction: direction)
            guard await queueApproach(toX: approach.x, z: approach.z, action: "spell-on-wall") else { return }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.castOnWall.rawValue))
            // The native login targets the custom 10009 protocol branch, whose
            // spell structs read spell first, then target coordinate + boundary
            // direction.
            buf.putShort(spellId)
            buf.putShort(serverTileX(x))
            buf.putShort(serverTileZ(z))
            buf.putByte(direction)
            try? await connection.send(buf.finishPacket())
            worldState.clearPendingTargetMode()
        }
    }

    func enablePrayer(prayerId: Int) {
        guard prayerId >= 0 && prayerId < worldState.activePrayers.count else { return }
        worldState.activePrayers[prayerId] = true
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.prayerOn.rawValue))
            buf.putByte(prayerId)
            try? await connection.send(buf.finishPacket())
        }
    }

    func disablePrayer(prayerId: Int) {
        guard prayerId >= 0 && prayerId < worldState.activePrayers.count else { return }
        worldState.activePrayers[prayerId] = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.prayerOff.rawValue))
            buf.putByte(prayerId)
            try? await connection.send(buf.finishPacket())
        }
    }

    /// Mirror of mudclient.java prayer toggle (clickHandler around line 8916):
    /// sends opcode 60 + 1-byte slot to enable, opcode 254 + 1-byte slot to
    /// disable. Optimistically updates `activePrayers` so the UI reflects the
    /// change immediately; the server still has authority via subsequent
    /// updateStat / drain packets.
    func togglePrayer(prayerId: Int) {
        guard prayerId >= 0 && prayerId < worldState.activePrayers.count else { return }
        let isOn = worldState.activePrayers[prayerId]
        worldState.activePrayers[prayerId] = !isOn
        Task {
            let buf = ByteBuffer()
            // Java client uses 1-byte slot for prayer toggle, not short — see
            // mudclient.java:8918 putByte(spellIndex). We mirror that exactly.
            buf.newPacket(opcode: isOn ? Int(RSCOutOpcode.prayerOff.rawValue)
                                       : Int(RSCOutOpcode.prayerOn.rawValue))
            buf.putByte(prayerId)
            try? await connection.send(buf.finishPacket())
        }
    }

    /// Cast a spell on a ground tile (telekinetic grab, alch on ground item).
    /// Mirrors RSCOutOpcode.castOnLand (158) with [short spellId][short x][short z].
    func castSpellOnGround(spellId: Int, x: Int, z: Int) {
        Task {
            guard await queueApproach(toX: x, z: z, action: "spell-on-ground-tile") else { return }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.castOnLand.rawValue))
            buf.putShort(spellId)
            buf.putShort(serverTileX(x))
            buf.putShort(serverTileZ(z))
            try? await connection.send(buf.finishPacket())
            worldState.clearPendingTargetMode()
        }
    }

    /// Cast a spell on an inventory item (e.g. enchant, low alch, superheat).
    /// Mirrors mudclient.java ITEM_CAST_SPELL: opcode 4, [short spellId][short slot].
    func castSpellOnItem(spellId: Int, slot: Int) {
        worldState.clearPendingTargetMode()
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.castOnItem.rawValue))
            buf.putShort(spellId)  // server reads spellId first per mudclient (idOrZ then indexOrX)
            buf.putShort(slot)
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Social

    func addFriend(name: String) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.addFriend.rawValue))
            buf.putString(name)
            try? await connection.send(buf.finishPacket())
        }
    }

    func removeFriend(name: String) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.removeFriend.rawValue))
            buf.putString(name)
            try? await connection.send(buf.finishPacket())
        }
    }

    func addIgnore(name: String) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.addIgnore.rawValue))
            buf.putString(name)
            try? await connection.send(buf.finishPacket())
        }
    }

    func removeIgnore(name: String) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.removeIgnore.rawValue))
            buf.putString(name)
            try? await connection.send(buf.finishPacket())
        }
    }

    func addDelayedIgnore(name: String) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.addDelayedIgnore.rawValue))
            buf.putString(name)
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Settings

    enum GameSettingIndex: Int {
        case cameraModeAuto = 0
        case mouseButtonOne = 2
        case soundDisabled = 3
        case blockGlobal = 9
        case experienceDrops = 25
        case hideRoofs = 26
        case hideFog = 27
        case groundItems = 28
        case killFeed = 31
        case floatingNameTags = 35
    }

    /// Send GAME_SETTINGS_CHANGED (opcode 111) with a 1-byte index and value.
    /// The current custom parser accepts indexes 0...99 and persists modern
    /// settings such as ground-item display, global-chat block, and mobile UI
    /// options through this path.
    func sendGameSetting(index: Int, value: Int) {
        let clampedIndex = max(0, min(99, index))
        let clampedValue = max(0, min(255, value))
        applyGameSettingLocally(index: clampedIndex, value: clampedValue)
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.gameSettings.rawValue))
            buf.putByte(clampedIndex)
            buf.putByte(clampedValue)
            try? await connection.send(buf.finishPacket())
        }
    }

    func sendGameSetting(_ setting: GameSettingIndex, enabled: Bool) {
        sendGameSetting(index: setting.rawValue, value: enabled ? 1 : 0)
    }

    func sendGameSetting(_ setting: GameSettingIndex, value: Int) {
        sendGameSetting(index: setting.rawValue, value: value)
    }

    private func applyGameSettingLocally(index: Int, value: Int) {
        switch GameSettingIndex(rawValue: index) {
        case .cameraModeAuto:
            worldState.optionCameraModeAuto = value == 1
        case .mouseButtonOne:
            worldState.optionMouseButtonOne = value == 1
        case .soundDisabled:
            worldState.optionSoundDisabled = value == 1
        case .blockGlobal:
            worldState.settingsBlockGlobal = value
        case .experienceDrops:
            worldState.optionExperienceDrops = value == 1
        case .hideRoofs:
            worldState.optionHideRoofs = value == 1
        case .hideFog:
            worldState.optionHideFog = value == 1
        case .groundItems:
            worldState.groundItemsToggle = value
        case .killFeed:
            worldState.optionHideKillFeed = value == 1
        case .floatingNameTags:
            worldState.optionHideNameTag = value == 1
        case .none:
            break
        }
    }

    /// Send privacy/chat-block flags. Mirrors mudclient.java createPacket64
    /// (line 2316) — opcode 64 with four 1-byte values: chat, private, trade,
    /// duel. Each is 0 (allow all) / 1 (block strangers) / 2 (block all).
    func setChatBlockFlags(chat: Int, priv: Int, trade: Int, duel: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.privacySettings.rawValue))
            buf.putByte(chat)
            buf.putByte(priv)
            buf.putByte(trade)
            buf.putByte(duel)
            try? await connection.send(buf.finishPacket())
        }
    }

    func followPlayer(serverIndex: Int) {
        Task {
            if let player = worldState.players.first(where: { $0.id == serverIndex }) {
                guard await queueEntityApproach(toX: player.x, z: player.y, action: "player-follow") else { return }
            }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.playerFollow.rawValue))
            buf.putShort(serverIndex)
            try? await connection.send(buf.finishPacket())
        }
    }

    /// Send PLAYER_INIT_TRADE_REQUEST (opcode 142 in protocol 235). The
    /// other player gets a "X wishes to trade with you" prompt and either
    /// accepts (TradePanel opens) or declines.
    func requestTrade(serverIndex: Int) {
        Task {
            if let player = worldState.players.first(where: { $0.id == serverIndex }) {
                guard await queueEntityApproach(toX: player.x, z: player.y, action: "player-trade") else { return }
            }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.playerTrade.rawValue))
            buf.putShort(serverIndex)
            try? await connection.send(buf.finishPacket())
        }
    }

    /// Send PLAYER_DUEL request (opcode 103 in protocol 235). Same flow as trade — server
    /// confirms, the DuelPanel opens for both sides.
    func requestDuel(serverIndex: Int) {
        Task {
            if let player = worldState.players.first(where: { $0.id == serverIndex }) {
                guard await queueEntityApproach(toX: player.x, z: player.y, action: "player-duel") else { return }
            }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.playerDuel.rawValue))
            buf.putShort(serverIndex)
            try? await connection.send(buf.finishPacket())
        }
    }

    func npcCommand(serverIndex: Int) {
        Task {
            if let npc = worldState.npcs.first(where: { $0.id == serverIndex }) {
                guard await queueEntityApproach(toX: npc.x, z: npc.y, action: "npc-command-1") else { return }
            }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.npcCommand.rawValue))
            buf.putShort(serverIndex)
            try? await connection.send(buf.finishPacket())
        }
    }

    func npcCommand2(serverIndex: Int) {
        Task {
            if let npc = worldState.npcs.first(where: { $0.id == serverIndex }) {
                guard await queueEntityApproach(toX: npc.x, z: npc.y, action: "npc-command-2") else { return }
            }
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.npcCommand2.rawValue))
            buf.putShort(serverIndex)
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Character Appearance

    func sendAppearance(headGender: Int, headType: Int, bodyGender: Int, skinTone: Int,
                        hairColour: Int, topColour: Int, bottomColour: Int, skinColour: Int) {
        worldState.showAppearanceChange = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.appearanceChange.rawValue))
            buf.putByte(headGender)     // 0=male, 1=female
            buf.putByte(headType)       // head style 0-4
            buf.putByte(bodyGender)     // 0=male, 1=female (usually matches head)
            buf.putByte(skinTone)       // character2Colour
            buf.putByte(hairColour)     // 0-9
            buf.putByte(topColour)      // 0-14
            buf.putByte(bottomColour)   // 0-14
            buf.putByte(skinColour)     // 0-4
            buf.putByte(0)              // ironmanMode
            buf.putByte(0)              // isOneXp
            try? await connection.send(buf.finishPacket())
            print("[Engine] Appearance sent")
        }
    }

    // MARK: - Account Security

    func submitContactDetails(name: String, zipCode: String, country: String, email: String) {
        worldState.contactDetailsOpen = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.setContactDetails.rawValue))
            buf.putString(name)
            buf.putString(zipCode)
            buf.putString(country)
            buf.putString(email)
            try? await connection.send(buf.finishPacket())
        }
    }

    func changePassword(oldPassword: String, newPassword: String) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.changePassword.rawValue))
            buf.putString(oldPassword)
            buf.putString(newPassword)
            try? await connection.send(buf.finishPacket())
        }
    }

    func cancelRecoveryRequest() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.cancelRecoveryRequest.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    func submitRecoveryQuestions(_ pairs: [(question: String, answer: String)]) {
        worldState.recoveryQuestionsOpen = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.setRecovery.rawValue))
            for pair in pairs.prefix(5) {
                buf.putString(String(pair.question.prefix(50)))
                buf.putString(String(pair.answer.prefix(100)))
            }
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Duel

    func duelAccept() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.duelAccept.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    func duelDecline() {
        worldState.duelOpen = false
        worldState.duelConfirmOpen = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.duelDecline.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    func duelConfirmAccept() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.duelConfirmAccept.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Sleep

    func sendSleepWord(_ word: String) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.sleepWord.rawValue))
            buf.putString(word)
            try? await connection.send(buf.finishPacket())
        }
        worldState.sleepStatusText = "Checking..."
    }

    // MARK: - Trade

    func tradeAccept() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.tradeAccept.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    func tradeDecline() {
        worldState.tradeOpen = false
        worldState.tradeConfirmOpen = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.tradeDecline.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    /// Sends the entire current trade offer list to the server (TRADE_OFFER, opcode 46).
    /// Java client mudclient.java:17215 — replaces server-side offer with the full list.
    /// Format: BYTE itemCount, then per item: SHORT itemId, INT amount, SHORT noted.
    func tradeOffer(_ items: [(id: Int, amount: Int)]) {
        sendTradeOffer(items.map { RSCItemStackMetadata(id: $0.id, amount: $0.amount, noted: false) })
    }

    /// Metadata-aware trade offer helper for future noted-item panels.
    func tradeOffer(_ items: [RSCItemStackMetadata]) {
        sendTradeOffer(items)
    }

    private func sendTradeOffer(_ items: [RSCItemStackMetadata]) {
        let prepared = prepareOfferItems(items, maxSlots: RSCWorldState.maxTradeOfferSlots)
        // Optimistic local update — packet handler will overwrite from server later.
        worldState.tradeMyOfferMetadata = prepared
        worldState.tradeMyOffer = prepared.map { $0.legacyStack }
        worldState.tradeAccepted = false
        worldState.tradePartnerAccepted = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.tradeOffer.rawValue))
            buf.putByte(prepared.count)
            for it in prepared {
                buf.putShort(it.id)
                buf.putInt(it.amount)
                buf.putShort(it.noted ? 1 : 0)
            }
            try? await connection.send(buf.finishPacket())
        }
    }

    /// Confirms the trade in the second-stage confirmation panel (opcode 104).
    func tradeConfirmAccept() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.tradeConfirmAccept.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Duel offer / settings

    /// Sends the entire current duel stake list (DUEL_OFFER_ITEM, opcode 33).
    /// Java client mudclient.java:11102 — same format as trade offer.
    /// Format: BYTE itemCount, then per item: SHORT itemId, INT amount, SHORT noted.
    func duelOffer(_ items: [(id: Int, amount: Int)]) {
        sendDuelOffer(items.map { RSCItemStackMetadata(id: $0.id, amount: $0.amount, noted: false) })
    }

    /// Metadata-aware duel stake helper for future noted-item panels.
    func duelOffer(_ items: [RSCItemStackMetadata]) {
        sendDuelOffer(items)
    }

    private func sendDuelOffer(_ items: [RSCItemStackMetadata]) {
        let prepared = prepareOfferItems(items, maxSlots: RSCWorldState.maxDuelStakeSlots)
        worldState.duelMyStakeMetadata = prepared
        worldState.duelMyStake = prepared.map { $0.legacyStack }
        worldState.duelAccepted = false
        worldState.duelOpponentAccepted = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.duelOffer.rawValue))
            buf.putByte(prepared.count)
            for it in prepared {
                buf.putShort(it.id)
                buf.putInt(it.amount)
                buf.putShort(it.noted ? 1 : 0)
            }
            try? await connection.send(buf.finishPacket())
        }
    }

    /// Sends the four duel rule toggles (DUEL_FIRST_SETTINGS_CHANGED, opcode 8).
    /// Java client mudclient.java:3026 — order is retreat, magic, prayer, weapons.
    /// Each byte is 1 (rule enabled / restriction on) or 0.
    func duelSettingsChange(retreat: Bool, magic: Bool, prayer: Bool, weapons: Bool) {
        worldState.duelSettings = [retreat, magic, prayer, weapons]
        worldState.duelAccepted = false
        worldState.duelOpponentAccepted = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.duelSettings.rawValue))
            buf.putByte(retreat ? 1 : 0)
            buf.putByte(magic ? 1 : 0)
            buf.putByte(prayer ? 1 : 0)
            buf.putByte(weapons ? 1 : 0)
            try? await connection.send(buf.finishPacket())
        }
    }

    private func prepareOfferItems(_ items: [RSCItemStackMetadata], maxSlots: Int) -> [RSCItemStackMetadata] {
        items.prefix(maxSlots).compactMap { item in
            let amount = max(0, item.amount)
            guard amount > 0 else { return nil }
            return RSCItemStackMetadata(id: item.id, amount: amount, noted: item.noted)
        }
    }
}
