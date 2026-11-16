import Foundation
import Combine

enum AppView {
    case selector
    case serverBrowser(GameType)
    case login(ServerProfile)
    case webGame(ServerProfile, String?, String?)
    case game(ServerProfile, String, String)  // server, username, password
    /// Native RSC client: the embedded rsc-c engine draws its own login screen.
    case nativeGame(ServerProfile)
}

@MainActor
final class AppState: ObservableObject {
    @Published var currentView: AppView = .selector
    @Published var isConnected: Bool = false
    @Published var loginError: String = ""

    @Published var servers: [ServerProfile] = {
        if let data = UserDefaults.standard.data(forKey: "savedServers"),
           let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            return AppState.withDefaultServers(decoded)
        }
        return AppState.withDefaultServers([])
    }()

    private static func withDefaultServers(_ savedServers: [ServerProfile]) -> [ServerProfile] {
        // Migrate profiles created by the retired Hetzner/WireGuard deployment
        // and the earlier LAN address to the Raspberry Pi on the home network.
        var servers = savedServers.map { profile in
            guard profile.gameType == .rsc || profile.gameType == .rscWeb else { return profile }
            let oldHosts = ["10.8.0.1", "192.168.0.25", "127.0.0.1", "localhost"]
            guard oldHosts.contains(profile.host) else { return profile }
            var migrated = profile
            migrated.host = "192.168.0.30"
            migrated.port = 43594
            migrated.wsPort = 43494
            migrated.name = profile.gameType == .rsc ? "2001scape (Home)" : "2001scape Web (Home)"
            return migrated
        }

        if !servers.contains(where: { $0.gameType == .rsc }) {
            servers.append(.openRSCDefault)
        }

        if !servers.contains(where: { $0.gameType == .rscWeb }) {
            servers.append(.openRSCWebDefault)
        }

        return servers
    }

    /// Test hook: `-nativeHost <host> [-nativePort <port>] -nativeRSA <modulus>`
    /// launch arguments (e.g. `xcrun simctl launch booted com.openrsc.client
    /// -nativeHost 127.0.0.1 -nativeRSA <hex>`) open the native RSC client
    /// straight away, without tapping through the menus.
    func applyLaunchArguments() {
        let defaults = UserDefaults.standard
        guard let host = defaults.string(forKey: "nativeHost"), !host.isEmpty else { return }
        let port = defaults.integer(forKey: "nativePort")
        var profile = ServerProfile(
            name: "Launch argument server",
            host: host,
            port: port > 0 ? port : 43594,
            wsPort: 43494,
            lastUsername: "",
            gameType: .rsc
        )
        profile.rsaModulus = defaults.string(forKey: "nativeRSA") ?? ""
        currentView = .nativeGame(profile)
    }

    func saveServers() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: "savedServers")
        }
    }

    func addServer(_ profile: ServerProfile) {
        servers.append(profile)
        saveServers()
    }

    func updateServer(_ profile: ServerProfile) {
        guard let index = servers.firstIndex(where: { $0.id == profile.id }) else { return }
        servers[index] = profile
        saveServers()
    }

    func updateLastUsername(_ username: String, for server: ServerProfile) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        guard servers[index].lastUsername != username else { return }
        servers[index].lastUsername = username
        saveServers()
    }

    func removeServer(at offsets: IndexSet) {
        servers.remove(atOffsets: offsets)
        saveServers()
    }
}
