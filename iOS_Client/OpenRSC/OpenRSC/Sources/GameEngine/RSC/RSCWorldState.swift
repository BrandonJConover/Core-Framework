import Foundation

struct RSCPlayer: Identifiable {
    let id: Int
    var x: Int
    var y: Int
    var name: String
    var moving: Bool
    var combatLevel: Int
}

struct RSCNPC: Identifiable {
    let id: Int
    var x: Int
    var y: Int
    var npcId: Int
    var name: String
}

struct RSCGroundItem: Identifiable {
    var id: String { "\(x)_\(y)_\(itemId)" }
    var x: Int
    var y: Int
    var itemId: Int
    var amount: Int
}

struct RSCChatMessage: Identifiable {
    let id: UUID = UUID()
    let sender: String
    let text: String
    let isLocal: Bool
}

struct RSCInventoryItem: Identifiable {
    let id: Int   // slot index
    var itemId: Int
    var amount: Int
    var equipped: Bool
}

struct RSCSkill: Identifiable {
    let id: Int   // skill index
    var level: Int
    var experience: Int
}

@MainActor
final class RSCWorldState: ObservableObject {
    @Published var localPlayerX: Int = 0
    @Published var localPlayerY: Int = 0
    @Published var localPlayerName: String = ""
    @Published var players: [RSCPlayer] = []
    @Published var npcs: [RSCNPC] = []
    @Published var groundItems: [RSCGroundItem] = []
    @Published var chatMessages: [RSCChatMessage] = []
    @Published var inventory: [RSCInventoryItem] = []
    @Published var skills: [RSCSkill] = []
    @Published var serverName: String = ""
    @Published var serverWelcomeMessage: String = ""
    @Published var playerCount: Int = 0
    @Published var playerMax: Int = 0
    @Published var isMembersWorld: Bool = false
    @Published var fatigue: Int = 0
    @Published var isDead: Bool = false

    func addChat(sender: String, text: String, isLocal: Bool = false) {
        let msg = RSCChatMessage(sender: sender, text: text, isLocal: isLocal)
        chatMessages.append(msg)
        if chatMessages.count > 100 { chatMessages.removeFirst() }
    }

    func updateExperience(skill: Int, xp: Int) {
        guard skill >= 0 && skill < skills.count else { return }
        skills[skill].experience = xp
    }

    func updateStatCurrent(skill: Int, level: Int) {
        guard skill >= 0 && skill < skills.count else { return }
        skills[skill].level = level
    }
}
