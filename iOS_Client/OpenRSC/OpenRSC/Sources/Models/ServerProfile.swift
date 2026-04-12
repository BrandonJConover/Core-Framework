import Foundation

enum GameType: String, Codable, CaseIterable {
    case rsc  = "RuneScape Classic"
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
        name: "OpenRSC",
        host: "game.openrsc.com",
        port: 43594,
        wsPort: 43494,
        lastUsername: "",
        gameType: .rsc
    )
}
