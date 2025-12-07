import SwiftUI

/// Main entry point for the OpenRSC iOS client.
/// Equivalent to Android's GameActivity.
@main
struct OpenRSCApp: App {
    @StateObject private var gameState = GameState()

    var body: some Scene {
        WindowGroup {
            GameContainerView()
                .environmentObject(gameState)
                .preferredColorScheme(.dark)
                .statusBar(hidden: true)
        }
    }
}

/// Global game state observable across the app.
@MainActor
final class GameState: ObservableObject {
    @Published var isConnected = false
    @Published var isLoggedIn = false
    @Published var loadingProgress: Double = 0
    @Published var loadingStatus: String = "Initializing..."
    @Published var errorMessage: String?

    // Server configuration
    var serverHost: String = "localhost"
    var serverPort: Int = 43594

    // Network client
    let networkClient: NetworkClient

    // Game client
    var gameClient: GameClient?

    init() {
        self.networkClient = NetworkClient()
    }

    func connect() async {
        do {
            loadingStatus = "Connecting to server..."
            try await networkClient.connect(host: serverHost, port: serverPort)
            isConnected = true
            loadingStatus = "Connected"
        } catch {
            errorMessage = "Connection failed: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        networkClient.disconnect()
        isConnected = false
        isLoggedIn = false
    }
}
