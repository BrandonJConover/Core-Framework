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
    let isPrivate: Bool
    let timestamp: Date

    init(sender: String, text: String, isLocal: Bool = false, isPrivate: Bool = false) {
        self.sender = sender
        self.text = text
        self.isLocal = isLocal
        self.isPrivate = isPrivate
        self.timestamp = Date()
    }
}

struct RSCInventoryItem: Identifiable {
    let id: Int   // slot index
    var itemId: Int
    var amount: Int
    var equipped: Bool
}

struct RSCEquipmentSlot: Identifiable {
    let id: Int   // slot index (0=head, 1=cape, 2=amulet, 3=weapon, 4=body, 5=shield, 6=legs, 7=gloves, 8=boots)
    var itemId: Int
    var amount: Int
}

struct RSCSkill: Identifiable {
    let id: Int   // skill index
    var current: Int  // current (boosted/drained) level
    var base: Int     // base level
    var experience: Int
}

/// Combat target info (NPC or player we're fighting)
struct RSCCombatTarget {
    enum TargetType { case npc, player }
    let type: TargetType
    let serverIndex: Int
    var name: String
    var combatLevel: Int
    var currentHp: Int
    var maxHp: Int
}

/// Equipment bonus stats sent by server
struct RSCEquipmentStats {
    var armourPoints: Int = 0
    var weaponAimPoints: Int = 0
    var weaponPowerPoints: Int = 0
    var magicPoints: Int = 0
    var prayerPoints: Int = 0
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
    @Published var equipment: [RSCEquipmentSlot] = []
    @Published var equipmentStats: RSCEquipmentStats = RSCEquipmentStats()
    @Published var skills: [RSCSkill] = []
    @Published var serverName: String = ""
    @Published var serverWelcomeMessage: String = ""
    @Published var playerCount: Int = 0
    @Published var playerMax: Int = 0
    @Published var isMembersWorld: Bool = false
    @Published var fatigue: Int = 0
    @Published var isDead: Bool = false

    // Combat state
    @Published var inCombat: Bool = false
    @Published var combatTarget: RSCCombatTarget? = nil
    @Published var combatStyle: Int = 0  // 0=controlled, 1=aggressive, 2=accurate, 3=defensive
    @Published var lastDamageReceived: Int = 0
    @Published var lastDamageDealt: Int = 0

    // Computed combat stats
    var hitpoints: Int { skills.first(where: { $0.id == 3 })?.current ?? 10 }
    var maxHitpoints: Int { skills.first(where: { $0.id == 3 })?.base ?? 10 }
    var prayerPoints: Int { skills.first(where: { $0.id == 5 })?.current ?? 0 }
    var maxPrayer: Int { skills.first(where: { $0.id == 5 })?.base ?? 0 }
    var combatLevel: Int {
        let atk = skills.first(where: { $0.id == 0 })?.base ?? 1
        let def = skills.first(where: { $0.id == 1 })?.base ?? 1
        let str = skills.first(where: { $0.id == 2 })?.base ?? 1
        let hp  = skills.first(where: { $0.id == 3 })?.base ?? 10
        return (atk + def + str + hp) / 4
    }

    func addChat(sender: String, text: String, isLocal: Bool = false, isPrivate: Bool = false) {
        let msg = RSCChatMessage(sender: sender, text: text, isLocal: isLocal, isPrivate: isPrivate)
        chatMessages.append(msg)
        if chatMessages.count > 100 { chatMessages.removeFirst() }
    }

    func updateExperience(skill: Int, xp: Int) {
        guard skill >= 0 && skill < skills.count else { return }
        skills[skill].experience = xp
    }

    func updateStatCurrent(skill: Int, level: Int) {
        guard skill >= 0 && skill < skills.count else { return }
        skills[skill].current = level
    }

    func enterCombat(target: RSCCombatTarget) {
        inCombat = true
        combatTarget = target
    }

    func exitCombat() {
        inCombat = false
        combatTarget = nil
    }
}
