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

    // Camera/zoom state for mobile controls
    @Published var zoomLevel: CGFloat = 1.6 // 0.5 = zoomed out, 2.0 = zoomed in
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
    private var cameraZoom: Int32 = 750  // Java default: 750 (mudclient.java:311)

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
        packetHandler.worldState = worldState
        connection.onPacket = { [weak self] opcode, payload in
            Task { @MainActor in
                self?.packetHandler.handlePacket(opcode: opcode, payload: payload)
            }
        }
        connection.onDisconnect = { [weak self] in
            Task { @MainActor in
                self?.isRunning = false
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

    // Connect to server and send login packet.
    func start(server: ServerProfile, username: String, password: String, appState: AppState) async {
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

        // Load landscape + sprite data from archives in background
        let loader = self.landscapeLoader
        let sprLoader = self.spriteLoader
        let sharedGraphics = graphics
        Task.detached(priority: .userInitiated) {
            loader.loadArchive()
            sprLoader.loadArchive()
            NPCDefinitions.loadArchive()
            NPCDefinitions.assignAnimationNumbers()
            GameObjectDefinitions.loadArchive()
            await MainActor.run {
                // Bridge decoded sprites into GraphicsController atlas so Scene.drawEntity() can draw them
                sprLoader.bridgeInto(sharedGraphics)
                print("[Engine] Archives loaded: landscape=\(loader.isLoaded) sprites=\(sprLoader.isLoaded) npcDefs=\(NPCDefinitions.defs.count) objDefs=\(GameObjectDefinitions.defs.count)")
            }
        }

        // Connect to server with timeout
        do {
            print("[Engine] Connecting to \(server.host):\(server.port)...")

            // 10-second connection timeout
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.connection.connect(host: server.host, port: UInt16(server.port))
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
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
            worldState.addChat(sender: "[System]", text: "Connection failed: \(error.localizedDescription)")
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
    private var terrainBuiltAtSector: (Int, Int) = (-1, -1)
    /// Number of models in the scene that belong to the static terrain mesh.
    /// Anything past this index is per-frame ephemera (game objects). We
    /// truncate back to this on every tick before re-instantiating objects.
    private var terrainModelCount: Int = 0

    private func tick() {
        guard isRunning else { return }
        // Decrement NPC combat/message timeouts
        for i in 0..<worldState.npcs.count {
            if worldState.npcs[i].combatTimeout > 0 { worldState.npcs[i].combatTimeout -= 1 }
            if worldState.npcs[i].messageTimeout > 0 { worldState.npcs[i].messageTimeout -= 1 }
        }

        // Real 3D Scene renderer (matches Java client mudclient.java render path):
        // - World generates a terrain mesh for the current region
        // - Scene projects + depth-sorts all polygons
        // - GraphicsController rasterizes into pixelData
        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY
        let havePos = (px != 0 || pz != 0)
        let landscapeReady = landscapeLoader.isLoaded

        if havePos && landscapeReady, let scene = self.scene, let graphics = self.graphics, let world = self.world {
            // Rebuild terrain mesh when the player moves into a new sector (each sector = 48 tiles)
            let secX = px / 48
            let secZ = pz / 48
            if !terrainBuilt || terrainBuiltAtSector != (secX, secZ) {
                world.landscapeLoader = landscapeLoader
                let absX = worldState.worldOffsetX + px
                let absZ = worldState.worldOffsetZ + pz
                // Clear previously-added landscape models so we don't accumulate
                for i in 0..<scene.modelCount { scene.models[i] = nil }
                scene.modelCount = 0
                world.loadSections(worldX: absX, worldZ: absZ, plane: 0)
                terrainBuilt = true
                terrainBuiltAtSector = (secX, secZ)
                terrainModelCount = scene.modelCount
                print("[Engine] Terrain mesh built for sector (\(secX),\(secZ)) at abs (\(absX),\(absZ)); scene has \(scene.modelCount) models")
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
                guard abs(dx) <= 24 && abs(dz) <= 24 else { continue }

                let def = GameObjectDefinitions.get(obj.objectId)
                let modelName = def?.modelID ?? ""
                let width = def?.width ?? 1
                let height = def?.height ?? 1

                // Y-elevation in world coords: terrain-mesh Y is negative-up,
                // and World.getElevation expects world coords. The mesh is
                // built in player-local space so we pass dx/dz scaled by
                // tileSize (128) for elevation lookup.
                let xWorld = (dx * 2 + width) * 128 / 2
                let zWorld = (dz * 2 + height) * 128 / 2
                let elevation = world.getElevation(x: xWorld, z: zWorld)

                ModelArchiveLoader.shared.instantiate(
                    named: modelName,
                    atTileX: dx, atTileZ: dz,
                    direction: obj.direction,
                    width: width, height: height,
                    elevation: elevation,
                    scene: scene
                )
            }

            // Camera setup. The terrain mesh is built in player-local coordinates
            // (World.generateLandscapeModel places verts at tileX*128, tileX in [-half,+half]).
            // So camera center = (0, -cameraY, 0) puts the camera directly above the player
            // origin. Absolute world position doesn't enter the projection math.
            let cameraY: Int32 = 180  // height above ground
            scene.fogLandscapeDistance = cameraZoom * 6
            scene.setCamera(
                centerX: 0,
                centerY: -cameraY,
                centerZ: 0,
                xRot: cameraPitch * 4,
                yRot: cameraRotation * 4,
                zRot: 0,
                offset: cameraZoom * 2
            )

            // Register character billboards so they composite in with terrain.
            // Must happen AFTER setCamera (so projectPoint uses fresh matrices)
            // and BEFORE endScene (so drawSprite sees them).
            scene.reduceSprites(0)  // clear any stale billboard entries

            // Default starter-avatar sprites for other players (head1, body1, legs1)
            let defaultPlayerSprites = [0, 1, 2, -1, -1, -1, -1, -1, -1, -1, -1, -1]

            // Characters are registered in the same player-local coord frame as
            // the terrain mesh — so NPC tile offsets are (npc.x - px, npc.y - pz).
            // NPCs in active combat (combatTimeout > 0) render with combat-A
            // animation frames; the player's combat counterpart goes to B.
            // Java mudclient.java drives combatRole off ORSCharacterDirection;
            // we approximate via the combatTimeout flag set when fighting.
            let combatTick = renderLogCount  // shared frame counter for combat cycle
            for npc in worldState.npcs {
                if let def = NPCDefinitions.get(npc.npcId) {
                    let role: CharacterBillboards.CombatRole = npc.combatTimeout > 0 ? .combatA : .none
                    CharacterBillboards.register(
                        scene: scene, spriteLoader: spriteLoader,
                        tileX: npc.x - px, tileZ: npc.y - pz,
                        rsDir: 4,  // TODO: track NPC direction from packet updates
                        stepFrame: role == .none ? renderLogCount : combatTick,
                        walkModel: def.walkModel,
                        cameraRotation: cameraRotation,
                        sprites: def.sprites,
                        hairColor: Int32(def.hairColour),
                        topColor: Int32(def.topColour),
                        bottomColor: Int32(def.bottomColour),
                        skinColor: Int32(def.skinColour),
                        combatRole: role,
                        combatModel: def.combatModel,
                        combatSprite: def.combatSprite,
                        overlayMovement: 32  // small lean while attacking
                    )
                }
            }
            // Default starter-avatar palette for other players — matches the
            // Java client's defaults when no appearance update has arrived yet.
            let defaultHair: Int32 = 0xC8B89B   // light brown
            let defaultTop: Int32 = 0xC83232    // red
            let defaultBottom: Int32 = 0x3A5AA3 // blue
            let defaultSkin: Int32 = 0xECC8A6   // tan
            for player in worldState.players {
                CharacterBillboards.register(
                    scene: scene, spriteLoader: spriteLoader,
                    tileX: player.x - px, tileZ: player.y - pz,
                    rsDir: 4, stepFrame: renderLogCount,
                    walkModel: 6,
                    cameraRotation: cameraRotation,
                    sprites: defaultPlayerSprites,
                    hairColor: defaultHair, topColor: defaultTop,
                    bottomColor: defaultBottom, skinColor: defaultSkin
                )
            }
            // Local player sits at the origin in local coords. When the engine
            // is in combat with a tracked target, render in the combatB pose so
            // the player faces the NPC mid-fight.
            let localCombatRole: CharacterBillboards.CombatRole = worldState.inCombat ? .combatB : .none
            CharacterBillboards.register(
                scene: scene, spriteLoader: spriteLoader,
                tileX: 0, tileZ: 0,
                rsDir: 4, stepFrame: renderLogCount,
                walkModel: 6,
                cameraRotation: cameraRotation,
                sprites: defaultPlayerSprites,
                hairColor: defaultHair, topColor: defaultTop,
                bottomColor: defaultBottom, skinColor: defaultSkin,
                combatRole: localCombatRole,
                combatModel: 6,
                combatSprite: 5,
                overlayMovement: 32
            )

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

    // HUD overlay drawn on top of the 3D scene: coordinates bar + player center marker.
    // Kept separate from the Scene so the info layer doesn't get cleared each frame.
    private func drawHUDOverlay() {
        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight
        let px = worldState.localPlayerX
        let pz = worldState.localPlayerY
        let absX = worldState.worldOffsetX + px
        let absZ = worldState.worldOffsetZ + pz

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
        let absX = worldState.worldOffsetX + px
        let absZ = worldState.worldOffsetZ + pz

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

            // Try to draw NPC sprite, fall back to colored dot
            let npcSpriteId = npc.npcId  // Simplified: use npcId as sprite index hint
            // Entity sprites: each animation has 15 frames, frame 3 = facing south
            // Animation number for NPC comes from NPCDef.sprites1
            // For simplicity, try sprite IDs near the NPC type
            var drewSprite = false
            if spriteLoader.isLoaded {
                // Try a few sprite IDs based on NPC type (rough mapping)
                let baseSpriteId = npc.npcId * 3  // rough estimate
                spriteLoader.drawSprite(baseSpriteId, onto: &pixelData, bufferWidth: w, bufferHeight: h,
                                        atX: npcSX - tp, atY: npcSY - tp * 2, scale: 1)
                drewSprite = true  // We attempted it — even if no sprite found, we still draw the dot
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

    private func handleTap(x: Int, y: Int) {
        // Convert screen tap → world tile by inverting the same camera transform
        // the renderer uses. The Scene projects with rot1024 yaw/pitch; we
        // approximate the inverse by raycasting from the camera through the tap
        // pixel and intersecting the y=0 ground plane.
        let w = Double(MetalRenderer.gameWidth)
        let h = Double(MetalRenderer.gameHeight)

        // Tap in normalized device coords (-1..+1)
        let ndx = (Double(x) - w / 2.0) / (w / 2.0)
        let ndy = (Double(y) - h / 2.0) / (h / 2.0)

        // Approximate field of view for our perspective: ~60° horizontal at the
        // current zoom. Larger zoom values pull camera back, narrowing FOV.
        let zoomFactor = max(0.4, 1500.0 / Double(cameraZoom * 2))
        let viewX = ndx * zoomFactor                         // ground X offset per unit ray length
        let viewY = ndy * zoomFactor * (h / w)               // pitch component

        // Camera angles
        let yawRad = Double(cameraRotation) * 2.0 * .pi / 1024.0
        let pitchRad = Double(cameraPitch) * 2.0 * .pi / 1024.0

        // Tap point's ground projection in camera-space, then rotated by yaw.
        // viewY is forward-tilt; multiply by camera height (180 units) and
        // adjust by pitch to get world-Z (forward) and use viewX for sideways.
        let groundForward = (1.0 - viewY) * 180.0 / max(0.0001, sin(pitchRad))
        let groundRight = viewX * groundForward

        // Convert (right, forward) in camera space to world (X, Z) by rotating
        // by camera yaw. Tile size is 128 game units.
        let cosY = cos(yawRad), sinY = sin(yawRad)
        let dxWorld = groundRight * cosY + groundForward * sinY
        let dzWorld = -groundRight * sinY + groundForward * cosY

        let tileOffsetX = Int(dxWorld / 128.0)
        let tileOffsetY = Int(dzWorld / 128.0)

        let destX = worldState.localPlayerX + tileOffsetX
        let destZ = worldState.localPlayerY + tileOffsetY

        // Check if tap is near an NPC (within 2 tiles)
        var nearestNPC: RSCNPC? = nil
        var nearestDist = Int.max
        for npc in worldState.npcs {
            let dx = npc.x - destX
            let dz = npc.y - destZ
            let dist = dx * dx + dz * dz
            if dist < nearestDist && dist <= 4 { // within 2 tiles
                nearestDist = dist
                nearestNPC = npc
            }
        }

        // Spell-cast target mode — armed by SpellbookPanel / MagicPanelView.
        // The next world tap is consumed as the spell target instead of
        // triggering walk/talk. Resolve in priority: NPC > player > ground.
        if let spellId = worldState.pendingSpellId {
            worldState.pendingSpellId = nil
            if let npc = nearestNPC {
                print("[Input] Cast spell \(spellId) on NPC \(npc.id)")
                castSpellOnNPC(spellId: spellId, npcServerIndex: npc.id)
            } else {
                var nearestPlayer: RSCPlayer? = nil
                var nearestPlayerDist = Int.max
                for p in worldState.players {
                    let pdx = p.x - destX; let pdz = p.y - destZ
                    let pd = pdx * pdx + pdz * pdz
                    if pd < nearestPlayerDist && pd <= 4 { nearestPlayerDist = pd; nearestPlayer = p }
                }
                if let player = nearestPlayer {
                    print("[Input] Cast spell \(spellId) on player \(player.id)")
                    castSpellOnPlayer(spellId: spellId, playerServerIndex: player.id)
                } else {
                    print("[Input] Cast spell \(spellId) on ground (\(destX),\(destZ))")
                    castSpellOnGround(spellId: spellId, x: destX, z: destZ)
                }
            }
            return
        }

        if let npc = nearestNPC {
            // Tap near NPC → talk to it
            print("[Input] Talk to NPC \(npc.npcId) (server index \(npc.id)) at (\(npc.x),\(npc.y))")
            Task {
                // First walk to NPC (opcode 16 = WALK_TO_ENTITY)
                let walkBuf = ByteBuffer()
                walkBuf.newPacket(opcode: 16)
                walkBuf.putShort(npc.x)
                walkBuf.putShort(npc.y)
                try? await connection.send(walkBuf.finishPacket())

                // Then send talk command (opcode 153)
                let talkBuf = ByteBuffer()
                talkBuf.newPacket(opcode: 153)
                talkBuf.putShort(npc.id)
                try? await connection.send(talkBuf.finishPacket())
            }
        } else {
            // No NPC nearby → walk to destination with pathfinding
            let pathfinder = Pathfinder(landscapeLoader: landscapeLoader, worldState: worldState)
            let path = pathfinder.findPath(fromX: worldState.localPlayerX, fromZ: worldState.localPlayerY,
                                           toX: destX, toZ: destZ, maxSteps: 25)
            print("[Input] Walk to (\(destX),\(destZ)) path=\(path.count) waypoints")
            Task {
                let buf = ByteBuffer()
                buf.newPacket(opcode: 187)  // WALK_TO_POINT
                // First point = start position
                buf.putShort(worldState.localPlayerX)
                buf.putShort(worldState.localPlayerY)
                // Waypoints as deltas from start
                for wp in path {
                    buf.putByte(wp.x - worldState.localPlayerX)
                    buf.putByte(wp.z - worldState.localPlayerY)
                }
                try? await connection.send(buf.finishPacket())
            }
        }
    }

    // MARK: - Context Menu

    func showContextMenu(at screenPoint: CGPoint) {
        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight
        let zoom = 24.0 * Double(zoomLevel)
        let tilt = 0.55
        let camRot = Double(cameraAngle) * .pi / 180.0
        let cosR = cos(camRot); let sinR = sin(camRot)
        let cx = Double(w) / 2.0; let cy = Double(h) * 0.40

        // Convert screen point to game pixel coordinates
        let viewSize = touchTranslator.viewSize
        let scaleX = CGFloat(w) / max(1, viewSize.width)
        let scaleY = CGFloat(h) / max(1, viewSize.height)
        let gx = Double(screenPoint.x) * Double(scaleX)
        let gy = Double(screenPoint.y) * Double(scaleY)

        // Reverse isometric projection
        let rx = (gx - cx) / zoom
        let rz = (gy - cy) / (zoom * tilt)
        let tileOffsetX = Int(rx * cosR + rz * sinR)
        let tileOffsetY = Int(-rx * sinR + rz * cosR)
        let worldX = worldState.localPlayerX + tileOffsetX
        let worldZ = worldState.localPlayerY + tileOffsetY

        var actions: [(label: String, icon: String, action: () -> Void)] = []
        var title = "(\(worldX), \(worldZ))"

        // Check NPCs (within 2 tiles)
        for npc in worldState.npcs {
            let dx: Int = npc.x - worldX; let dz: Int = npc.y - worldZ
            let distSq: Int = dx * dx + dz * dz
            if distSq <= 4 {
                title = npc.name
                actions.append(("Talk to \(npc.name)", "bubble.left", { [weak self] in
                    self?.talkToNPC(serverIndex: npc.id)
                }))
                actions.append(("Attack \(npc.name)", "bolt.fill", { [weak self] in
                    self?.attackNPC(serverIndex: npc.id)
                }))
                actions.append(("Pickpocket \(npc.name)", "hand.raised", { [weak self] in
                    self?.npcCommand(serverIndex: npc.id)
                }))
                break
            }
        }

        // Check players (within 2 tiles)
        for player in worldState.players {
            let pdx: Int = player.x - worldX; let pdz: Int = player.y - worldZ
            if pdx * pdx + pdz * pdz <= 4 {
                title = player.name
                actions.append(("Attack \(player.name)", "bolt.fill", { [weak self] in
                    self?.attackPlayer(serverIndex: player.id)
                }))
                actions.append(("Follow \(player.name)", "figure.walk", { [weak self] in
                    self?.followPlayer(serverIndex: player.id)
                }))
                break
            }
        }

        // Check ground items (within 2 tiles)
        for item in worldState.groundItems {
            let idx: Int = item.x - worldX; let idz: Int = item.y - worldZ
            if idx * idx + idz * idz <= 4 {
                let itemName = ItemNames.name(for: item.itemId)
                title = itemName
                actions.append(("Take \(itemName)", "arrow.down.circle", { [weak self] in
                    self?.pickupGroundItem(x: item.x, y: item.y, itemId: item.itemId)
                }))
                break
            }
        }

        // Check game objects (within 2 tiles)
        for obj in worldState.gameObjects {
            let odx: Int = obj.x - worldX; let odz: Int = obj.y - worldZ
            if odx * odx + odz * odz <= 4 {
                let objName = ObjectNames.name(for: obj.objectId)
                title = objName
                actions.append(("Use \(objName)", "hand.tap", { [weak self] in
                    self?.objectAction1(x: obj.x, z: obj.y)
                }))
                actions.append(("Examine \(objName)", "eye", { [weak self] in
                    self?.worldState.addChat(sender: "[Examine]", text: objName)
                }))
                break
            }
        }

        // Always add walk option
        actions.append(("Walk here", "figure.walk", { [weak self] in
            Task {
                let buf = ByteBuffer()
                buf.newPacket(opcode: 187)
                buf.putShort(worldX)
                buf.putShort(worldZ)
                try? await self?.connection.send(buf.finishPacket())
            }
        }))

        if actions.count > 1 {  // More than just "walk here"
            worldState.contextMenuTitle = title
            worldState.contextMenuActions = actions
            worldState.contextMenuOpen = true
        }
    }

    // MARK: - Combat actions

    func attackNPC(serverIndex: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.npcAttack.rawValue))
            buf.putShort(serverIndex)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }

    func attackPlayer(serverIndex: Int) {
        Task {
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

    func talkToNPC(serverIndex: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.npcTalkTo.rawValue))
            buf.putShort(serverIndex)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }

    // MARK: - Dialogue

    func answerDialogue(_ optionIndex: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 116)  // QUESTION_DIALOG_ANSWER
            buf.putByte(optionIndex)
            try? await connection.send(buf.finishPacket())
        }
    }

    func logout() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 102)  // LOGOUT
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Chat

    func sendChatMessage(_ text: String) {
        worldState.addChat(sender: worldState.localPlayerName, text: text, isLocal: true)
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.chatMessage.rawValue))
            buf.putString(text)
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
            buf.putString(text)
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

    // MARK: - Inventory actions

    func equipItem(slot: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.itemEquip.rawValue))
            buf.putShort(slot)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }

    func unequipItem(slot: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.itemUnequip.rawValue))
            buf.putShort(slot)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }

    func dropItem(slot: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.itemDrop.rawValue))
            buf.putShort(slot)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }

    func useItem(slot: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.itemCommand.rawValue))
            buf.putShort(slot)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }

    func pickupGroundItem(x: Int, y: Int, itemId: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.groundItemTake.rawValue))
            buf.putShort(x)
            buf.putShort(y)
            buf.putShort(itemId)
            try? await connection.send(buf.finishPacket())
        }
    }

    func useItemOnItem(slot1: Int, slot2: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.itemUseOnItem.rawValue))
            buf.putShort(slot1)
            buf.putShort(slot2)
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Bank actions

    func bankDeposit(itemId: Int, amount: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.bankDeposit.rawValue))
            buf.putShort(itemId)
            buf.putInt(amount)
            try? await connection.send(buf.finishPacket())
        }
    }

    func bankWithdraw(itemId: Int, amount: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.bankWithdraw.rawValue))
            buf.putShort(itemId)
            buf.putInt(amount)
            try? await connection.send(buf.finishPacket())
        }
    }

    func closeBank() {
        worldState.bankOpen = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.bankClose.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Shop actions

    func shopBuy(itemId: Int, amount: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.shopBuy.rawValue))
            buf.putShort(itemId)
            buf.putShort(amount)
            try? await connection.send(buf.finishPacket())
        }
    }

    func shopSell(itemId: Int, amount: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.shopSell.rawValue))
            buf.putShort(itemId)
            buf.putShort(amount)
            try? await connection.send(buf.finishPacket())
        }
    }

    func closeShop() {
        worldState.shopOpen = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.shopClose.rawValue))
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Object/Wall interactions

    func objectAction1(x: Int, z: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.objectCommand1.rawValue))
            buf.putShort(x)
            buf.putShort(z)
            try? await connection.send(buf.finishPacket())
        }
    }

    func objectAction2(x: Int, z: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.objectCommand2.rawValue))
            buf.putShort(x)
            buf.putShort(z)
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Magic & Prayer

    func castSpellOnSelf(spellId: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.castOnSelf.rawValue))
            buf.putShort(spellId)
            try? await connection.send(buf.finishPacket())
        }
    }

    func castSpellOnNPC(spellId: Int, npcServerIndex: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.castOnNpc.rawValue))
            buf.putShort(spellId)
            buf.putShort(npcServerIndex)
            try? await connection.send(buf.finishPacket())
        }
    }

    func castSpellOnPlayer(spellId: Int, playerServerIndex: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.castOnPlayer.rawValue))
            buf.putShort(spellId)
            buf.putShort(playerServerIndex)
            try? await connection.send(buf.finishPacket())
        }
    }

    func enablePrayer(prayerId: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.prayerOn.rawValue))
            buf.putShort(prayerId)
            try? await connection.send(buf.finishPacket())
        }
    }

    func disablePrayer(prayerId: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.prayerOff.rawValue))
            buf.putShort(prayerId)
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
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.castOnLand.rawValue))
            buf.putShort(spellId)
            buf.putShort(x)
            buf.putShort(z)
            try? await connection.send(buf.finishPacket())
        }
    }

    /// Cast a spell on an inventory item (e.g. enchant, low alch, superheat).
    /// Mirrors mudclient.java ITEM_CAST_SPELL: opcode 4, [short spellId][short slot].
    func castSpellOnItem(spellId: Int, slot: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 4)
            buf.putShort(spellId)  // server reads spellId first per mudclient (idOrZ then indexOrX)
            buf.putShort(slot)
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Social

    func addFriend(name: String) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 167) // ADD_FRIEND
            buf.putString(name)
            try? await connection.send(buf.finishPacket())
        }
    }

    func removeFriend(name: String) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 195) // REMOVE_FRIEND
            buf.putString(name)
            try? await connection.send(buf.finishPacket())
        }
    }

    func addIgnore(name: String) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 132) // ADD_IGNORE
            buf.putString(name)
            try? await connection.send(buf.finishPacket())
        }
    }

    func removeIgnore(name: String) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 241) // REMOVE_IGNORE
            buf.putString(name)
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Settings

    /// Send privacy/chat-block flags. Mirrors mudclient.java createPacket64
    /// (line 2316) — opcode 64 with four 1-byte values: chat, private, trade,
    /// duel. Each is 0 (allow all) / 1 (block strangers) / 2 (block all).
    func setChatBlockFlags(chat: Int, priv: Int, trade: Int, duel: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 64)
            buf.putByte(chat)
            buf.putByte(priv)
            buf.putByte(trade)
            buf.putByte(duel)
            try? await connection.send(buf.finishPacket())
        }
    }

    func followPlayer(serverIndex: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.playerFollow.rawValue))
            buf.putShort(serverIndex)
            try? await connection.send(buf.finishPacket())
        }
    }

    func npcCommand(serverIndex: Int) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.npcCommand.rawValue))
            buf.putShort(serverIndex)
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Character Appearance

    func sendAppearance(headGender: Int, headType: Int, bodyGender: Int, skinTone: Int,
                        hairColour: Int, topColour: Int, bottomColour: Int, skinColour: Int,
                        mode1: Int = 0, mode2: Int = 0) {
        worldState.showAppearanceChange = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 235) // CHANGE_APPEARANCE
            buf.putByte(headGender)     // 0=male, 1=female
            buf.putByte(headType)       // head style 0-4
            buf.putByte(bodyGender)     // 0=male, 1=female (usually matches head)
            buf.putByte(skinTone)       // character2Colour
            buf.putByte(hairColour)     // 0-9
            buf.putByte(topColour)      // 0-14
            buf.putByte(bottomColour)   // 0-14
            buf.putByte(skinColour)     // 0-4
            buf.putByte(mode1)          // player mode (normal/ironman/etc)
            buf.putByte(mode2)          // player mode 2
            try? await connection.send(buf.finishPacket())
            print("[Engine] Appearance sent")
        }
    }

    // MARK: - Duel

    func duelAccept() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 176) // DUEL_ACCEPT
            try? await connection.send(buf.finishPacket())
        }
    }

    func duelDecline() {
        worldState.duelOpen = false
        worldState.duelConfirmOpen = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 197) // DUEL_DECLINE
            try? await connection.send(buf.finishPacket())
        }
    }

    func duelConfirmAccept() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 77) // DUEL_CONFIRM_ACCEPT
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Sleep

    func sendSleepWord(_ word: String) {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 45) // SLEEP_WORD
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
    /// Format: BYTE itemCount, then per item: SHORT itemId, INT amount, SHORT noted(0/1).
    func tradeOffer(_ items: [(id: Int, amount: Int)]) {
        // Optimistic local update — packet handler will overwrite from server later.
        worldState.tradeMyOffer = items
        worldState.tradeAccepted = false
        worldState.tradePartnerAccepted = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 46) // TRADE_OFFER
            buf.putByte(items.count)
            for it in items {
                buf.putShort(it.id)
                buf.putInt(it.amount)
                buf.putShort(0) // noted: 0 — TODO: support noted items
            }
            try? await connection.send(buf.finishPacket())
        }
    }

    /// Confirms the trade in the second-stage confirmation panel (opcode 104).
    func tradeConfirmAccept() {
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 104) // TRADE_CONFIRM_ACCEPTED
            try? await connection.send(buf.finishPacket())
        }
    }

    // MARK: - Duel offer / settings

    /// Sends the entire current duel stake list (DUEL_OFFER_ITEM, opcode 33).
    /// Java client mudclient.java:11102 — same format as trade offer.
    /// Format: BYTE itemCount, then per item: SHORT itemId, INT amount, SHORT noted(0/1).
    func duelOffer(_ items: [(id: Int, amount: Int)]) {
        worldState.duelMyStake = items
        worldState.duelAccepted = false
        worldState.duelOpponentAccepted = false
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: 33) // DUEL_OFFER_ITEM
            buf.putByte(items.count)
            for it in items {
                buf.putShort(it.id)
                buf.putInt(it.amount)
                buf.putShort(0) // noted: 0
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
            buf.newPacket(opcode: 8) // DUEL_FIRST_SETTINGS_CHANGED
            buf.putByte(retreat ? 1 : 0)
            buf.putByte(magic ? 1 : 0)
            buf.putByte(prayer ? 1 : 0)
            buf.putByte(weapons ? 1 : 0)
            try? await connection.send(buf.finishPacket())
        }
    }
}
