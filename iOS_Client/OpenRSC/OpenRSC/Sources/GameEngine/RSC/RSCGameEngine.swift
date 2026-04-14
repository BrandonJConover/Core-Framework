import Foundation
import Combine
import MetalKit

// Coordinates the RSC game loop: networking, packet handling, world state, and rendering.
// Matches the role of GameActivity.java + RSCBitmapSurfaceView on Android.
@MainActor
final class RSCGameEngine: ObservableObject {
    let worldState = RSCWorldState()
    let touchTranslator = TouchTranslator()
    var renderer: MetalRenderer?

    private let connection = TCPConnection()
    private let packetHandler = RSCPacketHandler()
    private var tickTimer: Timer?
    private var isRunning = false

    // Pixels rendered each tick — initially all black.
    private var pixelData = [Int32](repeating: 0, count: MetalRenderer.gameWidth * MetalRenderer.gameHeight)

    // 3D rendering pipeline
    private var graphics: GraphicsController?
    private var scene: Scene?
    private var world: World?
    private var cameraX: Int32 = 0
    private var cameraY: Int32 = 0
    private var cameraZ: Int32 = 0
    private var cameraRotation: Int32 = 0
    private var cameraPitch: Int32 = 64
    private var cameraZoom: Int32 = 250

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

        touchTranslator.onTap = { [weak self] x, y in
            self?.handleTap(x: x, y: y)
        }
    }

    // Connect to server and send login packet.
    func start(server: ServerProfile, appState: AppState) async {
        do {
            // Initialize 3D rendering pipeline
            let graphics = GraphicsController(width: Int32(MetalRenderer.gameWidth), height: Int32(MetalRenderer.gameHeight), spriteCount: 5000)
            let scene = Scene(graphics: graphics, modelCount: 25000, polyCount: 50000, spriteCount: 5000)
            let world = World(scene: scene, graphics: graphics)
            try ModelArchiveLoader.shared.loadModels(from: "")

            self.graphics = graphics
            self.scene = scene
            self.world = world

            // Connect to server
            try await connection.connect(host: server.host, port: UInt16(server.port))
            let loginData = RSCLoginHandler.encodeLogin(
                username: server.lastUsername,
                password: ""  // password not stored in ServerProfile — passed from LoginView in production
            )
            try await connection.send(loginData)
            isRunning = true
            startTickLoop()
        } catch {
            appState.loginError = "Connection failed: \(error.localizedDescription)"
            appState.currentView = .login(server)
        }
    }

    func stop() {
        isRunning = false
        tickTimer?.invalidate()
        tickTimer = nil
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

    private func tick() {
        guard isRunning else { return }
        // Render world state to pixel buffer
        renderWorld()
        // Upload to Metal texture
        renderer?.updatePixels(pixelData)
    }

    // 3D renderer using Scene/World pipeline (TODO: enable after fixing Scene/World)
    private func renderWorld() {
        // Placeholder: fill with dark background
        for i in 0..<pixelData.count {
            pixelData[i] = Int32(bitPattern: 0xFF1a1a2e)
        }

        // TODO: Uncomment when Scene/World compile
        /*
        // Update camera from world state
        cameraX = Int32(worldState.localPlayerX)
        cameraY = Int32(0)  // Elevation handled by world.getElevation()
        cameraZ = Int32(worldState.localPlayerY)

        // Set camera in scene
        scene?.setCamera(
            centerX: cameraX,
            centerY: cameraY,
            centerZ: cameraZ,
            xRot: cameraPitch * 4,
            yRot: cameraRotation * 4,
            zRot: 0,
            offset: cameraZoom * 2
        )

        // Load terrain for current region if needed
        if let world = world {
            let regionX = Int(cameraX) / 96
            let regionZ = Int(cameraZ) / 96
            world.loadSections(worldX: regionX, worldZ: regionZ, plane: 0)
        }

        // Render the scene
        scene?.endScene(1)

        // Copy rendered pixels to output buffer
        if let graphics = graphics {
            pixelData = graphics.pixelData
        }
        */
    }

    // MARK: - Input handling

    private func handleTap(x: Int, y: Int) {
        // Build walk-to-point packet and send
        Task {
            let buf = ByteBuffer()
            buf.newPacket(opcode: Int(RSCOutOpcode.walkToPoint.rawValue))
            buf.putShort(x)
            buf.putShort(y)
            let data = buf.finishPacket()
            try? await connection.send(data)
        }
    }
}
