import Foundation
import Combine

enum AppView {
    case selector
    case serverBrowser(GameType)
    case login(ServerProfile)
    case webGame(ServerProfile, String?, String?)
    case game(ServerProfile, String, String)  // server, username, password
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
        var servers = savedServers

        if !servers.contains(where: { $0.gameType == .rsc }) {
            servers.append(.openRSCDefault)
        }

        if !servers.contains(where: { $0.gameType == .rscWeb }) {
            servers.append(.openRSCWebDefault)
        }

        return servers
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
