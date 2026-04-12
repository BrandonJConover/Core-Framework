import Foundation
import Combine

enum AppView {
    case selector
    case serverBrowser(GameType)
    case login(ServerProfile)
    case game(ServerProfile)
}

@MainActor
final class AppState: ObservableObject {
    @Published var currentView: AppView = .selector
    @Published var isConnected: Bool = false
    @Published var loginError: String = ""

    @Published var servers: [ServerProfile] = {
        if let data = UserDefaults.standard.data(forKey: "savedServers"),
           let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            return decoded
        }
        return [ServerProfile.openRSCDefault]
    }()

    func saveServers() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: "savedServers")
        }
    }

    func addServer(_ profile: ServerProfile) {
        servers.append(profile)
        saveServers()
    }

    func removeServer(at offsets: IndexSet) {
        servers.remove(atOffsets: offsets)
        saveServers()
    }
}
