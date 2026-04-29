import Foundation

struct RSCPlayer: Identifiable {
    let id: Int
    var x: Int
    var y: Int
    var name: String
    var moving: Bool
    var combatLevel: Int
    /// 0..7 facing direction from showOtherPlayers's 4-bit field. Defaults
    /// to 4 (south) so the renderer keeps working before the first sync.
    var direction: Int = 4
}

/// Appearance data delivered by opcode 234 case 5 (full appearance update).
/// Lives in a dictionary keyed by serverIndex so it survives across ticks
/// (showPlayers rebuilds the players array from scratch each tick — Java keeps
/// a persistent ORSCharacter table; we approximate by sidecar-keying here).
struct RSCPlayerAppearance: Equatable {
    /// 12-slot animation IDs (0 = unequipped). Order: head, shirt, pants,
    /// shield, weapon, hat, body, legs, gloves, boots, amulet, cape.
    var layerSprites: [Int]
    /// Palette indices into PlayerPalettes — server sends them as bytes 0..N
    /// then the client looks up the actual ARGB int from the palette tables.
    var colourHair: Int
    var colourTop: Int
    var colourBottom: Int
    var colourSkin: Int
    var combatLevel: Int
    var skulled: Bool
    var clanTag: String?
}

struct RSCNPC: Identifiable {
    var id: Int
    var x: Int
    var y: Int
    var npcId: Int
    var name: String
    var currentHp: Int = 0
    var maxHp: Int = 0
    var damageTaken: Int = 0
    var combatTimeout: Int = 0
    var message: String = ""
    var messageTimeout: Int = 0
    /// 0..7 facing direction captured from showNPCs's per-NPC 4-bit field.
    /// Defaults to 4 (south) so the renderer always has a valid value.
    var direction: Int = 4
}

struct RSCGameObject: Identifiable {
    var id: String { "\(x)_\(y)_\(objectId)" }
    var x: Int
    var y: Int
    var objectId: Int
    var direction: Int
}

struct RSCWallObject: Identifiable {
    var id: String { "\(x)_\(y)_\(wallId)_\(direction)" }
    var x: Int
    var y: Int
    var wallId: Int
    var direction: Int
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
    let isKill: Bool
    let timestamp: Date

    init(sender: String, text: String, isLocal: Bool = false, isPrivate: Bool = false, isKill: Bool = false) {
        self.sender = sender
        self.text = text
        self.isLocal = isLocal
        self.isPrivate = isPrivate
        self.isKill = isKill
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
    /// Local player's 0..7 facing direction from showOtherPlayers's
    /// 4-bit field. The renderer feeds this to CharacterBillboards so the
    /// local avatar faces the way the server says it's facing.
    @Published var localPlayerDirection: Int = 4
    @Published var localPlayerName: String = ""
    @Published var players: [RSCPlayer] = []
    /// Per-player appearance keyed by serverIndex. Survives the per-tick
    /// rebuild of `players`; the renderer looks up this map for each
    /// drawn player and falls back to a starter avatar when missing.
    @Published var playerAppearances: [Int: RSCPlayerAppearance] = [:]
    @Published var npcs: [RSCNPC] = []
    @Published var groundItems: [RSCGroundItem] = []
    @Published var gameObjects: [RSCGameObject] = []
    @Published var wallObjects: [RSCWallObject] = []
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

    /// Ticks remaining until the server reboots (opcode 52). Server sends
    /// ticks-of-32ms; Java code multiplies by 32 to get milliseconds. We
    /// keep that scaled value here so the banner shows seconds = ticks/1000.
    /// 0 = no pending update.
    @Published var systemUpdateTicks: Int = 0

    /// Transient friend-status toast notifications. Each toast self-expires
    /// after ~3 seconds. Pushed by opcode 149 (friend login/logout).
    struct FriendToast: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let online: Bool
        let createdAt: Date
    }
    @Published var friendToasts: [FriendToast] = []

    func pushFriendToast(name: String, online: Bool) {
        friendToasts.append(FriendToast(name: name, online: online, createdAt: Date()))
        let cutoff = Date().addingTimeInterval(-3.0)
        friendToasts.removeAll { $0.createdAt < cutoff }
    }

    // Welcome dialog state — populated by opcode 182 (PacketHandler.showLoginDialog).
    // Shown once per session right after the first character/skills sync.
    @Published var welcomeShown: Bool = false
    @Published var welcomeLastIP: String = ""
    /// Days since the previous login (0 = today). 65535 means "never logged in".
    @Published var welcomeDaysAgo: Int = 0
    /// Days remaining until recovery questions expire (0 if not set).
    @Published var welcomeRecoveryDays: Int = 0
    /// 0..5 — index into a tip-of-the-day text array picked client-side.
    @Published var welcomeTipOfDay: Int = 0

    // Bank state (opcode 42 showBank, 203 closeBank)
    @Published var bankOpen: Bool = false
    @Published var bankItems: [(id: Int, amount: Int)] = []
    var bankMaxItems: Int = 0

    // Shop state (opcode 101 showShop, 137 closeShop)
    @Published var shopOpen: Bool = false
    @Published var shopItems: [(id: Int, stock: Int, price: Int)] = []
    var shopType: Int = 0

    // Dialogue state (opcode 245 showOptionsMenu, 252 disableOptionsMenu)
    @Published var dialogueOpen: Bool = false
    @Published var dialogueOptions: [String] = []

    // Trade state
    @Published var tradeOpen: Bool = false
    @Published var tradeConfirmOpen: Bool = false
    @Published var tradePartnerName: String = ""
    @Published var tradeAccepted: Bool = false
    @Published var tradePartnerAccepted: Bool = false
    @Published var tradeMyOffer: [(id: Int, amount: Int)] = []
    @Published var tradeTheirOffer: [(id: Int, amount: Int)] = []

    // Friends/Ignore
    @Published var friendsList: [(name: String, online: Bool)] = []
    @Published var ignoreList: [String] = []

    // XP drop notifications
    struct XPDrop: Identifiable {
        let id = UUID()
        let skill: String
        let amount: Int
        let timestamp: Date
    }
    @Published var xpDrops: [XPDrop] = []

    func addXPDrop(skillId: Int, amount: Int) {
        let names = ["Attack","Defense","Strength","Hits","Ranged","Prayer","Magic","Cooking",
                     "Woodcut","Fletching","Fishing","Firemaking","Crafting","Smithing","Mining",
                     "Herblaw","Agility","Thieving"]
        let name = skillId < names.count ? names[skillId] : "Skill"
        xpDrops.append(XPDrop(skill: name, amount: amount, timestamp: Date()))
        // Remove old drops (older than 3 seconds)
        let cutoff = Date().addingTimeInterval(-3)
        xpDrops.removeAll { $0.timestamp < cutoff }
    }

    // Quest journal
    @Published var quests: [(id: Int, name: String, stage: Int)] = []

    // Character appearance creation
    @Published var showAppearanceChange: Bool = false

    // Duel state
    @Published var duelOpen: Bool = false
    @Published var duelConfirmOpen: Bool = false
    @Published var duelOpponentName: String = ""
    @Published var duelMyStake: [(id: Int, amount: Int)] = []
    @Published var duelTheirStake: [(id: Int, amount: Int)] = []
    @Published var duelSettings: [Bool] = [false, false, false, false] // retreat, magic, prayer, weapons
    @Published var duelAccepted: Bool = false
    @Published var duelOpponentAccepted: Bool = false

    // Sleep/fatigue state
    @Published var isSleeping: Bool = false
    @Published var sleepFatigue: Int = 0
    @Published var sleepStatusText: String = ""
    /// Raw bytes of the sleep-screen captcha. The Java client decodes it via
    /// `mc.makeSleepSprite(bytes)` (mudclient.java:7800ish) — a custom RLE
    /// blob that produces a 255×40 grayscale word image. We store the bytes
    /// here; the SleepPanel renders them as a CGImage on-screen.
    @Published var sleepCaptchaBytes: Data? = nil
    /// Width/height of the decoded captcha sprite (255×40 from server).
    var sleepCaptchaWidth: Int = 255
    var sleepCaptchaHeight: Int = 40

    // Context menu state
    @Published var contextMenuOpen: Bool = false
    @Published var contextMenuTitle: String = ""
    @Published var contextMenuActions: [(label: String, icon: String, action: () -> Void)] = []

    // World region data (from opcode 25 loadArea)
    var playerServerIndex: Int = 0
    var worldOffsetX: Int = 0
    var worldOffsetZ: Int = 0
    var requestedPlane: Int = 0
    var loadingArea: Bool = false
    // midRegionBase computed from player position
    var midRegionBaseX: Int { ((localPlayerX + 24) / 48) * 48 - 48 }
    var midRegionBaseZ: Int { ((localPlayerY + 24) / 48) * 48 - 48 }

    // Combat state
    @Published var inCombat: Bool = false
    @Published var combatTarget: RSCCombatTarget? = nil
    @Published var combatStyle: Int = 0  // 0=controlled, 1=aggressive, 2=accurate, 3=defensive
    @Published var lastDamageReceived: Int = 0
    @Published var lastDamageDealt: Int = 0

    // Active prayers — index matches the prayer slot (0..49 capacity, 14 used in RSC)
    @Published var activePrayers: [Bool] = Array(repeating: false, count: 50)

    // Pending spell cast — when set, the next world tap is interpreted as the
    // target rather than a walk. Cleared by RSCGameEngine.handleTap.
    @Published var pendingSpellId: Int? = nil

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

    func addChat(sender: String, text: String, isLocal: Bool = false, isPrivate: Bool = false, isKill: Bool = false) {
        let msg = RSCChatMessage(sender: sender, text: text, isLocal: isLocal, isPrivate: isPrivate, isKill: isKill)
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
