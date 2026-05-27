import Foundation

let RSCCharacterInterpolationTicks = 13

struct RSCPlayer: Identifiable {
    let id: Int
    var x: Int
    var y: Int
    var previousX: Int
    var previousY: Int
    var interpolationTicksRemaining: Int
    var name: String
    var moving: Bool
    var combatLevel: Int
    /// 0..7 facing direction from showOtherPlayers's 4-bit field. Defaults
    /// to 4 (south) so the renderer keeps working before the first sync.
    var direction: Int = 4
    /// Damage value most recently delivered by opcode 234 case 2. Java
    /// counts down combatTimeout from 200 and draws the splat while
    /// combatTimeout > 150 — about 50 render ticks (~1.5s).
    var damageTaken: Int = 0
    var damageTimeout: Int = 0
    var bubbleItem: Int = -1
    var bubbleTimeout: Int = 0
    var projectileSprite: Int = -1
    var projectileRange: Int = 0
    var projectileSourceServerIndex: Int = -1
    var projectileSourceIsNpc: Bool = false
    /// Floating chat message bubble shown above the player's head.
    /// Java drawNearbyPlayers (opcode 234 case 1/7) writes player.message
    /// and player.messageTimeout = 150 (~4.5s). Cleared by decay in the
    /// engine tick loop, same path the NPC bubble uses.
    var message: String = ""
    var messageTimeout: Int = 0

    init(
        id: Int,
        x: Int,
        y: Int,
        previousX: Int? = nil,
        previousY: Int? = nil,
        interpolationTicksRemaining: Int = 0,
        name: String,
        moving: Bool,
        combatLevel: Int,
        direction: Int = 4
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.previousX = previousX ?? x
        self.previousY = previousY ?? y
        self.interpolationTicksRemaining = interpolationTicksRemaining
        self.name = name
        self.moving = moving
        self.combatLevel = combatLevel
        self.direction = direction
    }

    var interpolatedX: Double {
        RSCPlayer.interpolate(from: previousX, to: x, ticksRemaining: interpolationTicksRemaining)
    }

    var interpolatedY: Double {
        RSCPlayer.interpolate(from: previousY, to: y, ticksRemaining: interpolationTicksRemaining)
    }

    private static func interpolate(from previous: Int, to current: Int, ticksRemaining: Int) -> Double {
        guard ticksRemaining > 0, previous != current else { return Double(current) }
        let progress = 1.0 - (Double(ticksRemaining) / Double(RSCCharacterInterpolationTicks))
        return Double(previous) + (Double(current - previous) * min(1.0, max(0.0, progress)))
    }
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
    var isInvisible: Bool = false
    var isInvulnerable: Bool = false
    var groupId: Int = 0
    var icon: Int = 0
}

struct RSCNPC: Identifiable {
    var id: Int
    var x: Int
    var y: Int
    var previousX: Int
    var previousY: Int
    var interpolationTicksRemaining: Int
    var npcId: Int
    var name: String
    var currentHp: Int = 0
    var maxHp: Int = 0
    var damageTaken: Int = 0
    var combatTimeout: Int = 0
    var message: String = ""
    var messageTimeout: Int = 0
    var bubbleItem: Int = -1
    var bubbleTimeout: Int = 0
    var projectileSprite: Int = -1
    var projectileRange: Int = 0
    var projectileSourceServerIndex: Int = -1
    var projectileSourceIsNpc: Bool = false
    var skullVisible: Int = 0
    var wield: Int = 0
    var wield2: Int = 0
    /// 0..7 facing direction captured from showNPCs's per-NPC 4-bit field.
    /// Defaults to 4 (south) so the renderer always has a valid value.
    var direction: Int = 4

    init(
        id: Int,
        x: Int,
        y: Int,
        previousX: Int? = nil,
        previousY: Int? = nil,
        interpolationTicksRemaining: Int = 0,
        npcId: Int,
        name: String,
        direction: Int = 4
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.previousX = previousX ?? x
        self.previousY = previousY ?? y
        self.interpolationTicksRemaining = interpolationTicksRemaining
        self.npcId = npcId
        self.name = name
        self.direction = direction
    }

    var interpolatedX: Double {
        RSCNPC.interpolate(from: previousX, to: x, ticksRemaining: interpolationTicksRemaining)
    }

    var interpolatedY: Double {
        RSCNPC.interpolate(from: previousY, to: y, ticksRemaining: interpolationTicksRemaining)
    }

    private static func interpolate(from previous: Int, to current: Int, ticksRemaining: Int) -> Double {
        guard ticksRemaining > 0, previous != current else { return Double(current) }
        let progress = 1.0 - (Double(ticksRemaining) / Double(RSCCharacterInterpolationTicks))
        return Double(previous) + (Double(current - previous) * min(1.0, max(0.0, progress)))
    }
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

struct RSCTeleportBubble: Identifiable {
    let id = UUID()
    var type: Int
    var x: Int
    var y: Int
    var time: Int = 0
}

struct RSCClanMember: Identifiable {
    var id: String { name }
    var name: String
    var rank: Int
    var online: Bool
}

struct RSCClanSearchResult: Identifiable, Equatable {
    var id: Int { clanId }
    var clanId: Int
    var name: String
    var tag: String
    var members: Int
    var canJoin: Bool
    var points: Int
    var rank: Int
}

struct RSCPartyMember: Identifiable {
    var id: String { name }
    var name: String
    var rank: Int
    var online: Bool
    var currentHp: Int
    var maxHp: Int
    var combatLevel: Int
    var skull: Int
    var memberStatus: Int
    var shareLoot: Bool
    var partyMembersTotal: Int
    var inCombat: Bool
    var shareExp: Bool
    var expShared: Int64
}

struct RSCPartySearchResult: Identifiable, Equatable {
    var id: Int { partyId }
    var partyId: Int
    var members: Int
    var canJoin: Bool
    var points: Int
    var rank: Int
}

struct RSCOnlinePlayer: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var icon: Int
    var location: String
}

struct RSCUnlockedAppearances: Equatable {
    var hairStyles: [Bool] = []
    var bodyTypes: [Bool] = []
    var skinColours: [Bool] = []
    var hairColours: [Bool] = []
    var topColours: [Bool] = []
    var bottomColours: [Bool] = []
}

struct RSCBankPresetItem: Equatable {
    var itemId: Int
    var amount: Int
    var noted: Bool

    static let empty = RSCBankPresetItem(itemId: 0, amount: 0, noted: false)
}

struct RSCBankPreset: Equatable {
    var slotIndex: Int
    var inventory: [RSCBankPresetItem]
    var equipment: [RSCBankPresetItem]
}

struct RSCItemStackMetadata: Equatable {
    var id: Int
    var amount: Int
    var noted: Bool

    var legacyStack: (id: Int, amount: Int) {
        (id: id, amount: amount)
    }
}

enum ChatChannel: Int, Codable, CaseIterable {
    case chat = 0
    case privateMsg
    case quest
    case trade
    case system
    case kill
    case magic
    case clan
    case party
}

struct RSCChatMessage: Identifiable {
    let id: UUID = UUID()
    let sender: String
    let text: String
    let isLocal: Bool
    let isPrivate: Bool
    let isKill: Bool
    let channel: ChatChannel
    let timestamp: Date

    init(sender: String, text: String, isLocal: Bool = false, isPrivate: Bool = false, isKill: Bool = false, channel: ChatChannel? = nil) {
        self.sender = sender
        self.text = text
        self.isLocal = isLocal
        self.isPrivate = isPrivate
        self.isKill = isKill
        self.channel = channel ?? Self.deriveChannel(sender: sender, isLocal: isLocal, isPrivate: isPrivate, isKill: isKill)
        self.timestamp = Date()
    }

    private static func deriveChannel(sender: String, isLocal: Bool, isPrivate: Bool, isKill: Bool) -> ChatChannel {
        if isKill { return .kill }
        if isPrivate { return .privateMsg }
        if isLocal { return .chat }

        switch sender {
        case "[Quest]": return .quest
        case "[Trade]", "[Shop]": return .trade
        case "[System]", "[Server]", "[Friend]", "[Use]", "[Examine]": return .system
        case "[Magic]": return .magic
        case "[Clan]": return .clan
        case "[Party]": return .party
        case "[Kill]": return .kill
        default: return sender.hasPrefix("[Option ") ? .quest : .chat
        }
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
    static let maxTradeOfferSlots = 12
    static let maxDuelStakeSlots = 8
    static let maxShopSlots = 40
    private static let baseSkillNames = [
        "Attack", "Defense", "Strength", "Hits", "Ranged",
        "Prayer", "Magic", "Cooking", "Woodcut", "Fletching",
        "Fishing", "Firemaking", "Crafting", "Smithing", "Mining",
        "Herblaw", "Agility", "Thieving"
    ]
    private static let baseSkillShortNames = [
        "Atk", "Def", "Str", "HP", "Rng", "Pray", "Mag", "Cook", "WC", "Fletch",
        "Fish", "FM", "Craft", "Smith", "Mine", "Herb", "Agil", "Thief"
    ]

    func skillName(for id: Int) -> String {
        if id >= 0 && id < Self.baseSkillNames.count { return Self.baseSkillNames[id] }
        return extendedSkillName(for: id, short: false) ?? "Skill \(id)"
    }

    func skillShortName(for id: Int) -> String {
        if id >= 0 && id < Self.baseSkillShortNames.count { return Self.baseSkillShortNames[id] }
        return extendedSkillName(for: id, short: true) ?? "?\(id)"
    }

    private func extendedSkillName(for id: Int, short: Bool) -> String? {
        var nextId = Self.baseSkillNames.count
        if wantRunecraft {
            if id == nextId { return short ? "RC" : "Runecraft" }
            nextId += 1
        }
        if wantHarvesting {
            if id == nextId { return short ? "Harvest" : "Harvesting" }
            nextId += 1
        }
        // Some servers send extended stat packets before the config flags.
        // Preserve the common both-skills ordering as a readable fallback.
        if id == 18 { return short ? "RC" : "Runecraft" }
        if id == 19 { return short ? "Harvest" : "Harvesting" }
        return nil
    }

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
    /// Set when inventory/equipment state changes before the matching opcode
    /// 234 case-5 appearance refresh arrives. Equipment stats and inventory can
    /// be correct while this sidecar still shows the previous visual outfit.
    @Published var localAppearanceAwaitingRefresh: Bool = false
    @Published var npcs: [RSCNPC] = []
    @Published var groundItems: [RSCGroundItem] = []
    @Published var gameObjects: [RSCGameObject] = []
    @Published var wallObjects: [RSCWallObject] = []
    @Published var teleportBubbles: [RSCTeleportBubble] = []
    @Published var chatMessages: [RSCChatMessage] = []
    @Published var inventory: [RSCInventoryItem] = []
    @Published var equipment: [RSCEquipmentSlot] = []
    @Published var equipmentStats: RSCEquipmentStats = RSCEquipmentStats()
    /// Inventory slot selected by the "Use" command. Java keeps this as
    /// selectedItemInventoryIndex and consumes it when the next entity/item
    /// target is chosen.
    @Published var pendingItemUseSlot: Int? = nil
    /// Local-only UI/UX preferences persisted through UserDefaults. Views
    /// should mutate this via RSCGameEngine.updatePreferences(...) so disk
    /// state stays aligned with the observable mirror.
    @Published var preferences: UserPreferences = UserPreferences()
    @Published var skills: [RSCSkill] = []
    @Published var wantRunecraft: Bool = false
    @Published var wantHarvesting: Bool = false
    var serverSkillCount: Int {
        18 + (wantRunecraft ? 1 : 0) + (wantHarvesting ? 1 : 0)
    }
    @Published var serverName: String = ""
    @Published var serverWelcomeMessage: String = ""
    @Published var playerCount: Int = 0
    @Published var playerMax: Int = 0
    @Published var isMembersWorld: Bool = false
    @Published var fatigue: Int = 0
    @Published var fatigueAuthentic: Int = 0
    /// Native HUD run/walk preference. The current protocol branch does not
    /// expose a confirmed run-toggle opcode, so this is persisted locally and
    /// rendered as client UI state until server wiring is audited.
    @Published var runEnabled: Bool = false
    /// 0...100 energy display derived from the server's fatigue packet.
    @Published var runEnergy: Int = 100
    @Published var experienceFrozen: Bool = false
    @Published var petFatigue: Int = 0
    @Published var expShared: Int = 0
    @Published var openPKPoints: Int64 = 0
    @Published var openPKPointsToGpPromptOpen: Bool = false
    @Published var kills2: Int = 0
    @Published var lastNpcKilledId: Int = 0
    @Published var kills3: Int = 0
    @Published var isOnBlackHole: Bool = false
    @Published var ironmanInterfaceOpen: Bool = false
    @Published var ironmanType: Int = 0
    @Published var ironmanRestriction: Int = 0
    @Published var onlinePlayerCount: Int = 0
    @Published var onlinePlayers: [RSCOnlinePlayer] = []
    @Published var bankPinOpen: Bool = false
    @Published var elixirTicks: Int = 0
    @Published var statusProgressOpen: Bool = false
    @Published var statusProgressInterfaceId: Int = 0
    @Published var statusProgressDelay: Int = 0
    @Published var statusProgressRepeats: Int = 0
    @Published var auctionProgressInterfaceId: Int = 0
    @Published var auctionProgressDelay: Int = 0
    @Published var auctionProgressRepeats: Int = 0
    @Published var fishingTrawlerOpen: Bool = false
    @Published var fishingTrawlerWaterLevel: Int = 0
    @Published var fishingTrawlerFishCaught: Int = 0
    @Published var fishingTrawlerMinutesLeft: Int = 0
    @Published var fishingTrawlerNetBroken: Bool = false
    @Published var unlockedAppearances: RSCUnlockedAppearances = RSCUnlockedAppearances()
    @Published var isDead: Bool = false
    /// Java sets `deathScreenTimeout = 250` on opcode 83 and counts it down
    /// once per game tick before returning control to the world.
    @Published var deathScreenTimeout: Int = 0

    /// Modal server-message dialog shown by Java opcodes 222 and 89. Java
    /// keeps this separate from the scrolling chat box and requires an
    /// explicit "Click here to close window" acknowledgement.
    @Published var serverMessageDialogOpen: Bool = false
    @Published var serverMessageDialogText: String = ""
    @Published var serverMessageDialogTop: Bool = false

    /// Custom protocol SEND_INPUT_BOX (opcode 110). The current server payload
    /// only contains a prompt string; no matching response parser exists in
    /// the server tree, so native exposes it as an acknowledged prompt.
    @Published var inputPromptOpen: Bool = false
    @Published var inputPromptText: String = ""

    @Published var connectionClosedOpen: Bool = false
    @Published var connectionClosedText: String = ""
    @Published var insideTutorial: Bool = false

    /// Account-security prompts opened by Java opcodes 232 (contact details)
    /// and 224 (recovery questions). The native forms submit protocol-235
    /// SET_DETAILS / SET_RECOVERY packets through RSCGameEngine.
    @Published var contactDetailsOpen: Bool = false
    @Published var recoveryQuestionsOpen: Bool = false

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

    func clearPendingTargetMode() {
        pendingItemUseSlot = nil
        pendingSpellId = nil
    }

    func closeContextMenu() {
        contextMenuOpen = false
        contextMenuTitle = ""
        contextMenuActions = []
    }

    /// Close blocking UI before showing a terminal connection state. This
    /// keeps stale welcome/sleep/trade/etc. overlays from sitting above the
    /// connection-lost dialog and trapping touch input.
    func closeBlockingUIForConnectionClosed() {
        clearPendingTargetMode()
        closeContextMenu()
        bankOpen = false
        bankPinOpen = false
        shopOpen = false
        shopSellableItemIds = []
        tradeOpen = false
        tradeConfirmOpen = false
        tradeAccepted = false
        tradePartnerAccepted = false
        tradeMyOffer = []
        tradeTheirOffer = []
        tradeMyOfferMetadata = []
        tradeTheirOfferMetadata = []
        duelOpen = false
        duelConfirmOpen = false
        duelAccepted = false
        duelOpponentAccepted = false
        duelMyStake = []
        duelTheirStake = []
        duelMyStakeMetadata = []
        duelTheirStakeMetadata = []
        dialogueOpen = false
        dialogueOptions = []
        serverMessageDialogOpen = false
        inputPromptOpen = false
        contactDetailsOpen = false
        recoveryQuestionsOpen = false
        showAppearanceChange = false
        welcomeOpen = false
        wildernessWarningOpen = false
        openPKPointsToGpPromptOpen = false
        ironmanInterfaceOpen = false
        statusProgressOpen = false
        fishingTrawlerOpen = false
        isSleeping = false
        isDead = false
        deathScreenTimeout = 0
    }

    // Welcome dialog state — populated by opcode 182 (PacketHandler.showLoginDialog).
    // Shown once per session right after the first character/skills sync.
    /// Sticky session-only flag — true once opcode 182 has been ingested,
    /// stays true even after the user dismisses the panel so we don't
    /// re-open it when the server resends 182 (some configs do).
    @Published var welcomeShown: Bool = false
    /// Drives WelcomePanel visibility. Set true alongside welcomeShown the
    /// first time opcode 182 arrives, flipped false when the user taps
    /// "Click here to play" (or the backdrop).
    @Published var welcomeOpen: Bool = false
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
    @Published var bankPresets: [Int: RSCBankPreset] = [:]
    var bankMaxItems: Int = 0

    // Shop state (opcode 101 showShop, 137 closeShop)
    @Published var shopOpen: Bool = false
    @Published var shopItems: [(id: Int, stock: Int, price: Int)] = []
    @Published var shopSellableItemIds: Set<Int> = []
    var shopType: Int = 0
    var shopSellModifier: Int = 0
    var shopBuyModifier: Int = 0
    var shopPriceMultiplier: Int = 0

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
    @Published var tradeMyOfferMetadata: [RSCItemStackMetadata] = []
    @Published var tradeTheirOfferMetadata: [RSCItemStackMetadata] = []

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
        xpDrops.append(XPDrop(skill: skillName(for: skillId), amount: amount, timestamp: Date()))
        pruneExpiredXPDrops()
    }

    func pruneExpiredXPDrops() {
        let cutoff = Date().addingTimeInterval(-3)
        xpDrops.removeAll { $0.timestamp < cutoff }
    }

    // Quest journal
    @Published var quests: [(id: Int, name: String, stage: Int)] = []
    @Published var questPoints: Int = 0

    // Character appearance creation
    @Published var showAppearanceChange: Bool = false

    // Duel state
    @Published var duelOpen: Bool = false
    @Published var duelConfirmOpen: Bool = false
    @Published var duelOpponentName: String = ""
    @Published var duelMyStake: [(id: Int, amount: Int)] = []
    @Published var duelTheirStake: [(id: Int, amount: Int)] = []
    @Published var duelMyStakeMetadata: [RSCItemStackMetadata] = []
    @Published var duelTheirStakeMetadata: [RSCItemStackMetadata] = []
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
    /// Java mudclient keeps player/NPC/object tiles in a region-local 96x96
    /// frame and stores the absolute-region origin separately as
    /// midRegionBaseX/Z. Opcode 191 sends packed player coords in the
    /// server/world-offset frame; RSCPacketHandler recenters those into this
    /// base so terrain, NPCs, and server-tile action packets all agree.
    var midRegionBaseX: Int = 0
    var midRegionBaseZ: Int = 0
    var currentRegionMinX: Int = 0
    var currentRegionMaxX: Int = 0
    var currentRegionMinZ: Int = 0
    var currentRegionMaxZ: Int = 0
    var lastHeightOffset: Int = Int.min

    /// True terrain/archive world coordinate. Use this for LandscapeLoader,
    /// wilderness checks, debug labels, and anything else that needs the
    /// worldOffset-inclusive map frame.
    func absoluteWorldX(_ localX: Int) -> Int {
        worldOffsetX + midRegionBaseX + localX
    }

    func absoluteWorldZ(_ localZ: Int) -> Int {
        worldOffsetZ + midRegionBaseZ + localZ
    }

    /// Java/server tile coordinate used in outbound walk/object/item packets.
    /// The worldOffset is only for local terrain archive addressing; sending
    /// it back to the server makes clicks target the wrong part of the world.
    func serverTileX(_ localX: Int) -> Int {
        midRegionBaseX + localX
    }

    func serverTileZ(_ localZ: Int) -> Int {
        midRegionBaseZ + localZ
    }

    @discardableResult
    func recenterRegion(packedPlayerX: Int, packedPlayerZ: Int) -> (localX: Int, localZ: Int, changed: Bool) {
        let wantX = packedPlayerX + worldOffsetX
        let wantZ = packedPlayerZ + worldOffsetZ

        // Java mudclient.loadNextRegion keeps a 64x64 active terrain window
        // with hysteresis and only recenters when the offset-inclusive player
        // coordinate leaves that window or the height plane changes. Rebuilding
        // the 48-tile base on every opcode 191 makes retained NPC/player/object
        // locals jump a region early.
        if lastHeightOffset == requestedPlane,
           currentRegionMinX < wantX, wantX < currentRegionMaxX,
           currentRegionMinZ < wantZ, wantZ < currentRegionMaxZ {
            return (packedPlayerX - midRegionBaseX, packedPlayerZ - midRegionBaseZ, false)
        }

        let midRegionX = (wantX + 24) / 48
        let midRegionZ = (wantZ + 24) / 48
        let nextBaseAbsX = midRegionX * 48 - 48
        let nextBaseAbsZ = midRegionZ * 48 - 48
        let nextBaseX = nextBaseAbsX - worldOffsetX
        let nextBaseZ = nextBaseAbsZ - worldOffsetZ
        let deltaX = nextBaseX - midRegionBaseX
        let deltaZ = nextBaseZ - midRegionBaseZ
        let changed = deltaX != 0 || deltaZ != 0 || lastHeightOffset != requestedPlane

        if changed {
            for i in players.indices {
                players[i].x -= deltaX
                players[i].previousX -= deltaX
                players[i].y -= deltaZ
                players[i].previousY -= deltaZ
            }
            for i in npcs.indices {
                npcs[i].x -= deltaX
                npcs[i].previousX -= deltaX
                npcs[i].y -= deltaZ
                npcs[i].previousY -= deltaZ
            }
            for i in gameObjects.indices {
                gameObjects[i].x -= deltaX
                gameObjects[i].y -= deltaZ
            }
            for i in wallObjects.indices {
                wallObjects[i].x -= deltaX
                wallObjects[i].y -= deltaZ
            }
            for i in groundItems.indices {
                groundItems[i].x -= deltaX
                groundItems[i].y -= deltaZ
            }
            if walkTargetTimeout > 0 {
                walkTargetX -= deltaX
                walkTargetY -= deltaZ
            }
            midRegionBaseX = nextBaseX
            midRegionBaseZ = nextBaseZ
            currentRegionMaxX = midRegionX * 48 + 32
            currentRegionMinX = midRegionX * 48 - 32
            currentRegionMaxZ = midRegionZ * 48 + 32
            currentRegionMinZ = midRegionZ * 48 - 32
            lastHeightOffset = requestedPlane
        }

        return (packedPlayerX - midRegionBaseX, packedPlayerZ - midRegionBaseZ, changed)
    }

    // Combat state
    @Published var inCombat: Bool = false
    @Published var combatTarget: RSCCombatTarget? = nil
    @Published var combatStyle: Int = 0  // 0=controlled, 1=aggressive, 2=accurate, 3=defensive
    @Published var lastDamageReceived: Int = 0
    @Published var lastDamageDealt: Int = 0

    // Options-menu settings from opcode 240. These mirror the Java
    // updateOptionsMenuSettings packet enough for native systems to follow
    // server/user preferences without touching the SettingsPanel UI.
    @Published var optionCameraModeAuto: Bool = false
    @Published var optionMouseButtonOne: Bool = false
    @Published var optionSoundDisabled: Bool = false
    @Published var settingsBlockGlobal: Int = 0
    @Published var optionExperienceDrops: Bool = true
    @Published var optionHideRoofs: Bool = false
    @Published var optionHideFog: Bool = false
    @Published var groundItemsToggle: Int = 0
    @Published var optionHideKillFeed: Bool = false
    @Published var optionHideNameTag: Bool = false

    /// Chat/privacy block flags from opcode 51. Values match the desktop
    /// client: 0 = allow all, 1 = block strangers, 2 = block all.
    @Published var blockChat: Int = 0
    @Published var blockPrivate: Int = 0
    @Published var blockTrade: Int = 0
    @Published var blockDuel: Int = 0

    // Clan/party state from opcodes 112 and 116. Full setup/search UI is a
    // separate surface, but the native client keeps the server state instead
    // of dropping it.
    @Published var inClan: Bool = false
    @Published var clanName: String = ""
    @Published var clanTag: String = ""
    @Published var clanLeader: String = ""
    @Published var isClanLeader: Bool = false
    @Published var clanMembers: [RSCClanMember] = []
    @Published var clanInviteFrom: String = ""
    @Published var clanInviteName: String = ""
    @Published var clanSettings: [Int] = [0, 0, 0]
    @Published var clanAllowed: [Bool] = [false, false]
    @Published var clanSearchResults: [RSCClanSearchResult] = []

    @Published var inParty: Bool = false
    @Published var partyLeader: String = ""
    @Published var isPartyLeader: Bool = false
    @Published var partyMembers: [RSCPartyMember] = []
    @Published var partyInviteFrom: String = ""
    @Published var partyInviteName: String = ""
    @Published var partySettings: [Int] = [0, 0, 0]
    @Published var partyAllowed: [Bool] = [false, false]
    @Published var partySearchResults: [RSCPartySearchResult] = []

    /// Damage splat for the local player. Java counts down combatTimeout
    /// from 200 and draws the splat while it stays > 150 (~50 render ticks).
    @Published var localDamageTaken: Int = 0
    @Published var localDamageTimeout: Int = 0

    /// Floating chat bubble for the local player. Mirrors the message field
    /// on remote players — set when our own opcode 234 case 1/7 echo lands
    /// or when we send a public chat. Bubble shows while messageTimeout > 0.
    @Published var localMessage: String = ""
    @Published var localMessageTimeout: Int = 0

    /// Last tile we asked the server to walk us to, plus a fading-marker
    /// counter so the renderer can pulse a small X on the destination
    /// while the engine is en route. Java's mudclient doesn't render
    /// this, but it's a key piece of mobile feedback — without it taps
    /// can feel like nothing happened until the avatar starts moving.
    @Published var walkTargetX: Int = 0
    @Published var walkTargetY: Int = 0
    @Published var walkTargetTimeout: Int = 0

    /// Wilderness state. Mirrors Java mudclient.java:5326-5349:
    /// `centerX = -playerLocalZ - worldOffsetZ - (midRegionBaseZ - 2203)`,
    /// where positive centerX puts the player in PvP territory and the
    /// (centerX / 6) + 1 derived level shows in the bottom-right corner.
    /// We surface the same data here so HUD pieces can render the level
    /// chip and a one-shot warning overlay when crossing the ditch.
    @Published var inWilderness: Bool = false
    @Published var wildernessLevel: Int = 0
    /// Drives the "Warning! Proceed with caution" panel. Set true when
    /// the player walks within ~10 tiles of the ditch for the first
    /// time this session; the panel flips it back to false on dismiss.
    @Published var wildernessWarningOpen: Bool = false
    /// Sticky session marker so the warning only ever fires once per
    /// login (Java mudclient guards on `showUiWildWarn == 0`).
    @Published var wildernessWarningSeen: Bool = false
    @Published var localBubbleItem: Int = -1
    @Published var localBubbleTimeout: Int = 0
    @Published var localProjectileSprite: Int = -1
    @Published var localProjectileRange: Int = 0
    @Published var localProjectileSourceServerIndex: Int = -1
    @Published var localProjectileSourceIsNpc: Bool = false

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
        let rng = skills.first(where: { $0.id == 4 })?.base ?? 1
        let pray = skills.first(where: { $0.id == 5 })?.base ?? 1
        let mag = skills.first(where: { $0.id == 6 })?.base ?? 1
        return Self.rscCombatLevel(attack: atk, defense: def, strength: str, hits: hp, magic: mag, prayer: pray, ranged: rng)
    }

    static func rscCombatLevel(
        attack: Int,
        defense: Int,
        strength: Int,
        hits: Int,
        magic: Int,
        prayer: Int,
        ranged: Int,
        isSpecial: Bool = false
    ) -> Int {
        // Server Formulae.getCombatLevel(): melee uses attack+strength,
        // defense is defense+hits, ranged can dominate when 1.5x melee,
        // and prayer+magic is always an additive /8 term.
        let multiplier = isSpecial ? 2.0 : 1.0
        let attackScore = multiplier * Double(attack + strength)
        let defenseScore = multiplier * Double(defense) + Double(hits)
        let magicPrayer = Double(prayer + magic) / 8.0
        let rangedScore = multiplier * Double(ranged)
        let level: Double
        if attackScore < rangedScore * 1.5 {
            level = (isSpecial ? (2.0 * defenseScore + 3.0 * rangedScore) / 14.0
                               : (2.0 * defenseScore + 3.0 * rangedScore) / 8.0)
                + magicPrayer
        } else {
            level = (isSpecial ? (attackScore + defenseScore) / 7.0
                               : (attackScore + defenseScore) / 4.0)
                + magicPrayer
        }
        return Int(floor(level))
    }

    func addChat(sender: String, text: String, isLocal: Bool = false, isPrivate: Bool = false, isKill: Bool = false, channel: ChatChannel? = nil) {
        let msg = RSCChatMessage(sender: sender, text: text, isLocal: isLocal, isPrivate: isPrivate, isKill: isKill, channel: channel)
        chatMessages.append(msg)
        if chatMessages.count > 100 { chatMessages.removeFirst() }
    }

    func updateExperience(skill: Int, xp: Int) {
        ensureSkillExists(skill)
        guard skill >= 0 && skill < skills.count else { return }
        let gained = xp - skills[skill].experience
        skills[skill].experience = xp
        if gained > 0 { addXPDrop(skillId: skill, amount: gained) }
    }

    func updateStatCurrent(skill: Int, level: Int) {
        ensureSkillExists(skill)
        guard skill >= 0 && skill < skills.count else { return }
        skills[skill].current = level
    }

    func ensureSkillCount(_ count: Int) {
        guard count > skills.count else { return }
        for id in skills.count..<count {
            let base = id == 3 ? 10 : 1
            skills.append(RSCSkill(id: id, current: base, base: base, experience: 0))
        }
    }

    func ensureSkillExists(_ skill: Int) {
        guard skill >= 0 else { return }
        ensureSkillCount(skill + 1)
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
