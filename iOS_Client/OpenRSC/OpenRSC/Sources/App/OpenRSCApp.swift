import SwiftUI
import UIKit

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
                .onAppear {
                    AppOrientationController.apply(gameState.gameOrientationPreference)
                }
                .onChange(of: gameState.gameOrientationPreference) { newValue in
                    AppOrientationController.apply(newValue)
                }
        }
    }
}

enum GameOrientationPreference: String, CaseIterable, Identifiable {
    case automatic
    case landscapeLeft
    case landscapeRight

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .landscapeLeft:
            return "Landscape Left"
        case .landscapeRight:
            return "Landscape Right"
        }
    }

    var shortTitle: String {
        switch self {
        case .automatic:
            return "Auto"
        case .landscapeLeft:
            return "Left"
        case .landscapeRight:
            return "Right"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Follow device rotation."
        case .landscapeLeft:
            return "Lock the game to the left landscape orientation."
        case .landscapeRight:
            return "Lock the game to the right landscape orientation."
        }
    }

    var interfaceOrientations: UIInterfaceOrientationMask {
        switch self {
        case .automatic:
            return .allButUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        }
    }
}

enum AppOrientationController {
    @MainActor
    static func apply(_ preference: GameOrientationPreference) {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        for scene in scenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: preference.interfaceOrientations)) { error in
                print("Orientation update failed: \(error.localizedDescription)")
            }
        }

        UIViewController.attemptRotationToDeviceOrientation()
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

    // Server configuration (bindable from the login form, persisted across launches)
    @Published var serverHost: String = "localhost"
    @Published var serverPortText: String = "43594"
    @Published var rememberedUsername: String = ""
    @Published var gameOrientationPreference: GameOrientationPreference = .automatic

    var serverPort: Int { Int(serverPortText) ?? 43594 }

    // Server info received after bootstrap
    @Published var serverConfiguration: ServerConfiguration?

    // Network client
    let networkClient: NetworkClient

    // Game client
    var gameClient: GameClient?

    init() {
        self.networkClient = NetworkClient()

        // Restore last-used settings
        let defaults = UserDefaults.standard
        if let host = defaults.string(forKey: "openrsc_serverHost"), !host.isEmpty {
            self.serverHost = host
        }
        if let port = defaults.string(forKey: "openrsc_serverPort"), !port.isEmpty {
            self.serverPortText = port
        }
        if let username = defaults.string(forKey: "openrsc_username"), !username.isEmpty {
            self.rememberedUsername = username
        }
        if let orientationRawValue = defaults.string(forKey: "openrsc_gameOrientationPreference"),
           let orientation = GameOrientationPreference(rawValue: orientationRawValue) {
            self.gameOrientationPreference = orientation
        }
    }

    /// Saves current connection settings to UserDefaults.
    private func saveSettings(username: String) {
        let defaults = UserDefaults.standard
        defaults.set(serverHost, forKey: "openrsc_serverHost")
        defaults.set(serverPortText, forKey: "openrsc_serverPort")
        defaults.set(username, forKey: "openrsc_username")
        defaults.set(gameOrientationPreference.rawValue, forKey: "openrsc_gameOrientationPreference")
    }

    func updateGameOrientationPreference(_ preference: GameOrientationPreference) {
        gameOrientationPreference = preference
        UserDefaults.standard.set(preference.rawValue, forKey: "openrsc_gameOrientationPreference")
    }

    func connectAndLogin(username: String, password: String) async {
        // Persist settings so they survive app restarts
        saveSettings(username: username)

        do {
            loadingStatus = "Connecting to \(serverHost):\(serverPort)..."
            try await networkClient.connect(host: serverHost, port: serverPort)
            isConnected = true

            let client = GameClient(networkClient: networkClient)
            gameClient = client

            loadingStatus = "Logging in as \(username)..."
            try await client.login(username: username, password: password)
            isLoggedIn = true
            loadingStatus = "Connected"
        } catch {
            errorMessage = "Connection failed: \(error.localizedDescription)"
            isConnected = false
            isLoggedIn = false
        }
    }

    func disconnect() {
        Task { await networkClient.disconnect() }
        isConnected = false
        isLoggedIn = false
        gameClient = nil
        serverConfiguration = nil
    }
}

/// Server configuration received during bootstrap.
struct ServerConfiguration {
    let displayName: String
    let welcomeText: String
    let featureSummary: String
}
