import Foundation

enum GameType: String, Codable, CaseIterable {
    case rsc  = "2001scape"
    case rscWeb = "2001scape Web"
    case osrs = "Old School RuneScape"
}

struct ServerProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int
    var wsPort: Int
    var lastUsername: String
    var gameType: GameType

    static let openRSCDefault = ServerProfile(
        name: "2001scape (VPN)",
        host: "10.8.0.1",
        port: 43594,
        wsPort: 43494,
        lastUsername: "",
        gameType: .rsc
    )

    static let openRSCWebDefault = ServerProfile(
        name: "2001scape Web (VPN)",
        host: "10.8.0.1",
        port: 43594,
        wsPort: 43494,
        lastUsername: "",
        gameType: .rscWeb
    )
}
