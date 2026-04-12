import Foundation
import Combine

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

    // Simple placeholder renderer — draws player position as a white dot.
    // Replace this with Scene.java port for authentic RSC rendering.
    private func renderWorld() {
        let w = MetalRenderer.gameWidth
        let h = MetalRenderer.gameHeight

        // Fill background
        for i in 0..<pixelData.count {
            pixelData[i] = Int32(bitPattern: 0xFF1a1a1a)
        }

        // Draw a dot at the local player's position (scaled to canvas)
        let px = min(max(worldState.localPlayerX % w, 0), w - 1)
        let py = min(max(worldState.localPlayerY % h, 0), h - 1)
        let idx = py * w + px
        if idx >= 0 && idx < pixelData.count {
            pixelData[idx] = Int32(bitPattern: 0xFFFFFFFF)
        }
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
