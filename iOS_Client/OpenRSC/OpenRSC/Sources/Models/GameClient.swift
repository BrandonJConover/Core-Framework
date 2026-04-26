import Foundation

struct DuelSettings {
    var disallowRetreat: Bool = false
    var disallowMagic: Bool = false
    var disallowPrayer: Bool = false
    var disallowWeapons: Bool = false
}

enum MenuContext {
    case none
    case npc(index: Int)
    case player(index: Int)
    case groundItem(itemId: Int, x: Int, y: Int)
    case world(x: Int, y: Int)
}

/// Main game client that manages game state.
/// Complete implementation matching server protocol.
@MainActor
final class GameClient: ObservableObject {
    // Game dimensions (matches RSC)
    static let gameWidth = 512
    static let gameHeight = 334
    private static let cameraRotationStep = 32
    private static let fallbackDefaultZoom = 184
    private static let minimumCameraZoom = 168
    private static let maximumCameraZoom = 192
    private static let cameraZoomPresets = [168, 184, 192]
    private static let dragRotationThreshold: Float = 7
    private static let dragZoomThreshold: Float = 8
    private static let clothingPalette: [UInt32] = [
        0xFFFF0000, 0xFFFF8000, 0xFFFFE000, 0xFFA0E000, 0xFF00E000,
        0xFF008000, 0xFF00A080, 0xFF00B0FF, 0xFF0080FF, 0xFF0030F0,
        0xFFE000E0, 0xFF303030, 0xFF604000, 0xFF805000, 0xFFFFFFFF
    ]
    private static let hairPalette: [UInt32] = [
        0xFFFFC030, 0xFFFFA040, 0xFF805030, 0xFF604020, 0xFF303030,
        0xFFFF6020, 0xFFFF4000, 0xFFFFFFFF, 0xFF3CB371, 0xFF6AE0E8
    ]
    private static let skinPalette: [UInt32] = [
        0xFFECDED0, 0xFFDDBA94, 0xFFC7956A, 0xFF9E6A43, 0xFF70462B
    ]

    // Published state - Player
    @Published var localPlayer: Player?
    @Published var players: [Int: Player] = [:]
    @Published var npcs: [Int: Npc] = [:]

    // Ordered entity lists — mirrors server's getLocalPlayers()/getLocalNpcs().
    // Bit-packed coord packets process known entities in list order (no index per update).
    var localPlayerIndices: [Int] = []
    var localNpcIndices: [Int] = []

    // Direction-to-coordinate offset mapping (derived from server Formulae.getDirection).
    // Index = sprite direction 0-7 when a mob has moved one tile.
    static let directionOffsets: [(dx: Int, dy: Int)] = [
        ( 0, -1), // 0
        (+1, -1), // 1
        (+1,  0), // 2
        (+1, +1), // 3
        ( 0, +1), // 4
        (-1, +1), // 5
        (-1,  0), // 6
        (-1, -1), // 7
    ]
    @Published var groundItems: [GroundItem] = []
    @Published var inventory: [InventoryItem] = []
    @Published var skills: [Skill] = Skill.createAll()
    @Published var questPoints: Int = 0

    // Published state - World
    @Published var sceneryObjects: [WorldObject] = []
    @Published var boundaries: [Boundary] = []

    // Published state - Equipment
    @Published var equipmentBonuses = EquipmentBonuses()

    // Published state - Social
    @Published var friendList: [(name: String, online: Bool)] = []
    @Published var ignoreList: [String] = []
    @Published var chatMessages: [ChatMessage] = []

    // Published state - Interface
    @Published var showingBank: Bool = false
    @Published var bankItems: [BankItem] = []
    @Published var maxBankSize: Int = 48

    @Published var showingShop: Bool = false
    @Published var shopItems: [ShopItem] = []
    @Published var isGeneralStore: Bool = false

    @Published var showingDialogue: Bool = false
    @Published var dialogueOptions: [String] = []

    @Published var showingSleepScreen: Bool = false
    @Published var sleepCaptchaImage: Data?

    @Published var fatigue: Int = 0
    @Published var questList: [Int: Int] = [:]

    // Equipment (11 slots; -1 = empty)
    @Published var wornEquipment: [Int] = Array(repeating: -1, count: 11)

    // Combat
    @Published var combatStyle: Int = 0   // 0=Controlled 1=Aggressive 2=Accurate 3=Defensive

    // Prayer
    @Published var activePrayers: [Bool] = Array(repeating: false, count: 18)

    // Trade
    @Published var showingTrade: Bool = false
    @Published var tradePartnerId: Int = -1
    @Published var tradePartnerName: String = ""
    @Published var tradeMyItems: [(id: Int, amount: Int, noted: Bool)] = []
    @Published var tradeTheirItems: [(id: Int, amount: Int, noted: Bool)] = []
    @Published var tradeAccepted: Bool = false
    @Published var tradeTheyAccepted: Bool = false
    @Published var showingTradeConfirm: Bool = false

    // Duel
    @Published var showingDuel: Bool = false
    @Published var duelPartnerId: Int = -1
    @Published var duelMyItems: [(id: Int, amount: Int, noted: Bool)] = []
    @Published var duelTheirItems: [(id: Int, amount: Int, noted: Bool)] = []
    @Published var duelSettings: DuelSettings = DuelSettings()
    @Published var duelAccepted: Bool = false
    @Published var duelTheyAccepted: Bool = false
    @Published var showingDuelConfirm: Bool = false

    // System
    @Published var systemUpdateTimer: Int = 0
    @Published var showingAppearanceScreen: Bool = false
    @Published var showingWelcomeScreen: Bool = false
    @Published var welcomeLastIp: String = ""
    @Published var welcomeDaysSinceLogin: Int = 0

    // Privacy / Settings
    @Published var blockChat: Bool = false
    @Published var blockPrivate: Bool = false
    @Published var blockTrade: Bool = false
    @Published var blockDuel: Bool = false
    @Published var autoCamera: Bool = true
    @Published var soundDisabled: Bool = false

    // Online list
    @Published var onlinePlayers: [(name: String, icon: Int, location: String)] = []

    // Sleep
    @Published var incorrectSleepwordAttempt: Bool = false

    // Bank preset data (raw bytes per preset slot index)
    @Published var bankPresetData: [Int: Data] = [:]

    // Camera
    @Published var cameraX: Int = 0
    @Published var cameraY: Int = 0
    @Published var cameraRotation: Int = 128
    @Published var cameraZoom: Int

    // UI State
    @Published var showingMenu: Bool = false
    @Published var menuOptions: [String] = []
    @Published var menuPosition: CGPoint = .zero
    @Published var menuContext: MenuContext = .none
    @Published var currentTab: Int = 0
    @Published var errorMessage: String?
    @Published var isMembersWorld: Bool = false
    @Published var worldPlane: Int = 0

    // Network
    private let networkClient: NetworkClient
    private var packetHandler: PacketHandler?
    private let landscapeArchive = LandscapeArchive.shared
    private var dragRotationAccumulator: Float = 0
    private var dragZoomAccumulator: Float = 0

    // Frame buffer for rendering
    var frameBuffer: [UInt32]

    // 3D rendering pipeline
    private(set) var graphicsController: GraphicsController?
    private(set) var scene: RSScene?
    private(set) var world: World?
    private var rendererInitialized = false
    private var lastSpriteCount = 0

    init(networkClient: NetworkClient) {
        self.networkClient = networkClient
        self.cameraZoom = Self.fallbackDefaultZoom
        self.frameBuffer = Array(repeating: 0xFF000000, count: Self.gameWidth * Self.gameHeight)

        self.packetHandler = PacketHandler(gameClient: self)

        Task {
            await setupPacketHandling()
        }

        loadSpriteArchives()
        initRenderer()
    }

    /// Loads .orsc sprite archives from the app bundle.
    private func loadSpriteArchives() {
        if let spritesURL = Bundle.main.url(forResource: "Authentic_Sprites", withExtension: "orsc") {
            SpriteManager.shared.loadArchive(from: spritesURL)
        } else {
            print("GameClient: Authentic_Sprites.orsc not found in bundle")
        }
    }

    /// Initializes the 3D rendering pipeline (Scene, World, GraphicsController).
    func initRenderer() {
        guard !rendererInitialized else { return }
        let gc = GraphicsController(width: Self.gameWidth, height: Self.gameHeight, spriteCount: 5000)
        let sc = RSScene(graphics: gc, modelCount: 25000, polyCount: 50000, spriteCount: 5000)
        let w = World(scene: sc, graphics: gc)

        // Load 3D models
        ModelArchiveLoader.shared.loadModels()

        // Set lighting direction
        sc.setDiffuseDir(x: -50, y: -10, z: -50)

        graphicsController = gc
        scene = sc
        world = w
        rendererInitialized = true
    }

    /// Triggers world terrain loading for the given region coordinates and plane.
    /// Call this when the client receives a region/area change packet.
    func loadWorldSections(worldX: Int, worldZ: Int, plane: Int) {
        world?.loadSections(worldX: worldX, worldZ: worldZ, plane: plane)
    }

    private func setupPacketHandling() async {
        await networkClient.setOnPacketReceived { [weak self] packet in
            Task { @MainActor [weak self] in
                await self?.packetHandler?.handle(packet)
            }
        }
    }

    // MARK: - Login

    func login(username: String, password: String) async throws {
        var builder = PacketBuilder()
        builder.writeByte(0) // Not reconnecting
        builder.writeInt(1) // Client version (4-byte int, server reads readInt)
        builder.writeLinefeedString(username) // Server getString reads until 0x0A
        builder.writeLinefeedString(password)
        builder.writeLong(0) // UID placeholder (8 bytes)
        let packet = builder.build(opcode: 0) // Login opcode
        try await networkClient.send(packet)
    }

    func onLoginSuccess(playerIndex: Int = 0, membersWorld: Bool = false) {
        isMembersWorld = membersWorld
        localPlayer = Player(
            index: playerIndex,
            username: "Player",
            x: 122,
            y: 648 // Lumbridge
        )
    }

    func onLoginFailed(_ reason: String) {
        errorMessage = reason
    }

    func onLogout() {
        localPlayer = nil
        players.removeAll()
        npcs.removeAll()
        inventory.removeAll()
        groundItems.removeAll()
    }

    func onLogoutDenied() {
        addServerMessage("You can't logout right now")
    }

    // MARK: - Player Updates

    func updateLocalPlayerPosition(x: Int, y: Int) {
        localPlayer?.x = x
        localPlayer?.y = y
        cameraX = x
        cameraY = y
    }

    func updatePlayerPosition(index: Int, x: Int, y: Int, direction: Int = 0) {
        if let player = players[index] {
            player.x = x
            player.y = y
            player.direction = direction
        } else if index == localPlayer?.index {
            localPlayer?.x = x
            localPlayer?.y = y
            localPlayer?.direction = direction
        } else {
            let newPlayer = Player(index: index, username: "Player\(index)", x: x, y: y)
            newPlayer.direction = direction
            players[index] = newPlayer
        }
    }

    func updatePlayerAppearance(index: Int, combatLevel: Int, appearance: PlayerAppearance) {
        if let player = players[index] {
            player.combatLevel = combatLevel
            player.appearance = appearance
        } else if index == localPlayer?.index {
            localPlayer?.combatLevel = combatLevel
            localPlayer?.appearance = appearance
        }
    }

    // MARK: - Bit-packed Player Coord Updates

    func updateLocalPlayerSprite(_ sprite: Int) {
        localPlayer?.animation = sprite
    }

    func knownPlayerMoved(index: Int, direction: Int) {
        guard direction >= 0 && direction < Self.directionOffsets.count,
              let player = players[index] else { return }
        let offset = Self.directionOffsets[direction]
        player.x += offset.dx
        player.y += offset.dy
        player.animation = direction
    }

    func knownPlayerRemoved(index: Int) {
        players.removeValue(forKey: index)
        localPlayerIndices.removeAll { $0 == index }
    }

    func knownPlayerSpriteChanged(index: Int, sprite: Int) {
        players[index]?.animation = sprite
    }

    func knownPlayerNoUpdate(index: Int) {
        // Entity retained, position unchanged — no-op
    }

    func addNewPlayer(index: Int, xOffset: Int, yOffset: Int, sprite: Int) {
        let baseX = localPlayer?.x ?? 0
        let baseY = localPlayer?.y ?? 0
        let newPlayer = Player(index: index, username: "Player\(index)", x: baseX + xOffset, y: baseY + yOffset)
        newPlayer.animation = sprite
        players[index] = newPlayer
        if !localPlayerIndices.contains(index) {
            localPlayerIndices.append(index)
        }
    }

    // MARK: - Bit-packed NPC Coord Updates

    func knownNpcMoved(index: Int, direction: Int) {
        guard direction >= 0 && direction < Self.directionOffsets.count,
              let npc = npcs[index] else { return }
        let offset = Self.directionOffsets[direction]
        npc.x += offset.dx
        npc.y += offset.dy
        npc.animation = direction
    }

    func knownNpcRemoved(index: Int) {
        npcs.removeValue(forKey: index)
        localNpcIndices.removeAll { $0 == index }
    }

    func knownNpcSpriteChanged(index: Int, sprite: Int) {
        npcs[index]?.animation = sprite
    }

    func knownNpcNoUpdate(index: Int) {
        // Entity retained, position unchanged — no-op
    }

    func addNewNpc(index: Int, xOffset: Int, yOffset: Int, sprite: Int, npcId: Int) {
        let baseX = localPlayer?.x ?? 0
        let baseY = localPlayer?.y ?? 0
        let newNpc = Npc(index: index, npcId: npcId, x: baseX + xOffset, y: baseY + yOffset)
        newNpc.animation = sprite
        npcs[index] = newNpc
        if !localNpcIndices.contains(index) {
            localNpcIndices.append(index)
        }
    }

    // MARK: - NPC Updates

    func updateNpc(index: Int, npcId: Int, x: Int, y: Int, direction: Int = 0) {
        if let npc = npcs[index] {
            npc.x = x
            npc.y = y
            npc.direction = direction
        } else {
            let newNpc = Npc(index: index, npcId: npcId, x: x, y: y)
            newNpc.direction = direction
            npcs[index] = newNpc
        }
    }

    func updateNpcAnimation(index: Int, animation: Int) {
        npcs[index]?.animation = animation
    }

    // MARK: - World Objects

    func addSceneryObject(id: Int, x: Int, y: Int) {
        sceneryObjects.append(WorldObject(id: id, x: x, y: y))
    }

    func addSceneryObject(id: Int, xOffset: Int, yOffset: Int, direction: Int) {
        let x = (localPlayer?.x ?? 0) + xOffset
        let y = (localPlayer?.y ?? 0) + yOffset
        sceneryObjects.append(WorldObject(id: id, x: x, y: y))
    }

    func removeSceneryObject(x: Int, y: Int) {
        sceneryObjects.removeAll { $0.x == x && $0.y == y }
    }

    func removeSceneryObject(xOffset: Int, yOffset: Int) {
        let x = (localPlayer?.x ?? 0) + xOffset
        let y = (localPlayer?.y ?? 0) + yOffset
        sceneryObjects.removeAll { $0.x == x && $0.y == y }
    }

    func addBoundary(id: Int, x: Int, y: Int, direction: Int) {
        boundaries.append(Boundary(id: id, x: x, y: y, direction: direction))
    }

    func addBoundary(id: Int, xOffset: Int, yOffset: Int, direction: Int) {
        let x = (localPlayer?.x ?? 0) + xOffset
        let y = (localPlayer?.y ?? 0) + yOffset
        boundaries.append(Boundary(id: id, x: x, y: y, direction: direction))
    }

    func removeBoundary(x: Int, y: Int) {
        boundaries.removeAll { $0.x == x && $0.y == y }
    }

    func removeBoundary(xOffset: Int, yOffset: Int) {
        let x = (localPlayer?.x ?? 0) + xOffset
        let y = (localPlayer?.y ?? 0) + yOffset
        boundaries.removeAll { $0.x == x && $0.y == y }
    }

    func clearAllLocations() {
        sceneryObjects.removeAll()
        boundaries.removeAll()
        groundItems.removeAll()
    }

    // MARK: - Inventory

    func setInventory(_ items: [(Int, Int)]) {
        inventory = items.map { InventoryItem(itemId: $0.0, amount: $0.1, equipped: false) }
    }

    func setFullInventory(_ items: [(id: Int, amount: Int, equipped: Bool)]) {
        inventory = items.map { InventoryItem(itemId: $0.id, amount: $0.amount, equipped: $0.equipped) }
    }

    func setFullInventory(_ items: [(id: Int, amount: Int, equipped: Bool, noted: Bool)]) {
        inventory = items.map { InventoryItem(itemId: $0.id, amount: $0.amount, equipped: $0.equipped) }
    }

    // MARK: - Skills

    func updateSkill(skillId: Int, current: Int, max: Int, experience: Int) {
        guard skillId < skills.count else { return }
        let oldLevel = skills[skillId].maxLevel
        skills[skillId].currentLevel = current
        skills[skillId].maxLevel = max
        skills[skillId].experience = experience

        if max > oldLevel {
            Task { await SoundManager.shared.play(.levelUp) }
            addServerMessage("Congratulations! You've advanced a \(skills[skillId].name) level!")
        }
    }

    func updateExperience(skillId: Int, experience: Int) {
        guard skillId < skills.count else { return }
        skills[skillId].experience = experience
    }

    func setQuestPoints(_ points: Int) {
        questPoints = points
    }

    func setEquipmentBonuses(armour: Int, weaponAim: Int, weaponPower: Int, magic: Int, prayer: Int) {
        equipmentBonuses = EquipmentBonuses(
            armour: armour, weaponAim: weaponAim,
            weaponPower: weaponPower, magic: magic, prayer: prayer
        )
    }

    func setFatigue(_ value: Int) { fatigue = value }
    func setFatigueAsleep(_ value: Int) { fatigue = value }
    func setQuestList(_ quests: [Int: Int]) { questList = quests }

    // MARK: - Player Update Actions

    func showPlayerBubble(index: Int, itemId: Int) {
        // Action bubble over player head
    }

    func playerPublicChat(index: Int, icon: Int, message: String) {
        if let player = players[index] {
            addChatMessage(sender: player.username, message: message)
            player.chatMessage = message
            player.chatMessageExpiry = Date().addingTimeInterval(4.0)
        }
    }

    func playerDamage(index: Int, damage: Int, curHits: Int, maxHits: Int) {
        if let player = players[index] {
            player.currentHits = curHits
            player.maxHits = maxHits
            player.damageDisplay = Int(damage)
            player.damageExpiry = Date().addingTimeInterval(1.5)
        } else if index == localPlayer?.index {
            localPlayer?.currentHits = curHits
            localPlayer?.maxHits = maxHits
            localPlayer?.damageDisplay = Int(damage)
            localPlayer?.damageExpiry = Date().addingTimeInterval(1.5)
        }
    }

    func playerProjectileToNpc(casterIndex: Int, projectileType: Int, victimIndex: Int) {
        // Player cast projectile at NPC
    }

    func playerProjectileToPlayer(casterIndex: Int, projectileType: Int, victimIndex: Int) {
        // Player cast projectile at player
    }

    func updatePlayerAppearanceFull(
        index: Int, username: String, wornItems: [Int],
        hairColor: Int, topColor: Int, trouserColor: Int, skinColor: Int,
        combatLevel: Int, skullType: Int, clanTag: String?,
        isInvisible: Bool, isInvulnerable: Bool, groupId: Int, icon: Int
    ) {
        let appearance = PlayerAppearance(
            headSprite: wornItems.first ?? 0,
            bodySprite: wornItems.count > 1 ? wornItems[1] : 0,
            legSprite: wornItems.count > 2 ? wornItems[2] : 0,
            hairColor: hairColor,
            topColor: topColor,
            bottomColor: trouserColor,
            skinColor: skinColor
        )
        if let player = players[index] {
            player.username = username
            player.combatLevel = combatLevel
            player.appearance = appearance
        } else if index == localPlayer?.index {
            localPlayer?.username = username
            localPlayer?.combatLevel = combatLevel
            localPlayer?.appearance = appearance
        } else {
            let newPlayer = Player(index: index, username: username, x: 0, y: 0)
            newPlayer.combatLevel = combatLevel
            newPlayer.appearance = appearance
            players[index] = newPlayer
        }
    }

    func playerQuestChat(index: Int, message: String) {
        addServerMessage(message)
    }

    func playerMutedChat(index: Int, isMuted: Bool, onTutorial: Bool, message: String) {
        addServerMessage(message)
    }

    func playerHpUpdate(index: Int, curHits: Int, maxHits: Int) {
        if let player = players[index] {
            player.currentHits = curHits
            player.maxHits = maxHits
        } else if index == localPlayer?.index {
            localPlayer?.currentHits = curHits
            localPlayer?.maxHits = maxHits
        }
    }

    // MARK: - NPC Update Actions

    func npcChat(index: Int, recipientIndex: Int, message: String) {
        addServerMessage(message)
        if let npc = npcs[index] {
            npc.chatMessage = message
            npc.chatMessageExpiry = Date().addingTimeInterval(4.0)
        }
    }

    func npcDamage(index: Int, damage: Int, curHits: Int, maxHits: Int) {
        if let npc = npcs[index] {
            npc.currentHits = curHits
            npc.maxHits = maxHits
            npc.damageDisplay = Int(damage)
            npc.damageExpiry = Date().addingTimeInterval(1.5)
        }
    }

    func npcProjectileToNpc(casterIndex: Int, projectileType: Int, victimIndex: Int) {
        // NPC cast projectile at NPC
    }

    func npcProjectileToPlayer(casterIndex: Int, projectileType: Int, victimIndex: Int) {
        // NPC cast projectile at player
    }

    func npcSkull(index: Int, skullType: Int) {
        // NPC skull indicator
    }

    func npcWield(index: Int, wield: Int, wield2: Int) {
        // NPC equipment change
    }

    func npcBubble(index: Int, itemId: Int) {
        // Action bubble over NPC head
    }

    // MARK: - Chat

    func addChatMessage(sender: String, message: String) {
        chatMessages.append(ChatMessage(type: .player, sender: sender, message: message))
        if chatMessages.count > 100 { chatMessages.removeFirst() }
    }

    func addServerMessage(_ message: String) {
        chatMessages.append(ChatMessage(type: .server, sender: nil, message: message))
        if chatMessages.count > 100 { chatMessages.removeFirst() }
    }

    func onPrivateMessageSent(to recipient: String, message: String) {
        chatMessages.append(ChatMessage(type: .privateOut, sender: recipient, message: message))
    }

    func onPrivateMessageReceived(from sender: String, message: String) {
        chatMessages.append(ChatMessage(type: .privateIn, sender: sender, message: message))
    }

    // MARK: - Social

    func setFriendList(_ friends: [(name: String, online: Bool)]) { friendList = friends }

    func updateFriendStatus(name: String, online: Bool) {
        if let i = friendList.firstIndex(where: { $0.name == name }) {
            friendList[i] = (name: name, online: online)
        }
    }

    func setIgnoreList(_ names: [String]) { ignoreList = names }

    // MARK: - Ground Items

    func addGroundItem(itemId: Int, x: Int, y: Int) {
        groundItems.append(GroundItem(itemId: itemId, x: x, y: y))
    }

    func addGroundItem(itemId: Int, xOffset: Int, yOffset: Int) {
        let x = (localPlayer?.x ?? 0) + xOffset
        let y = (localPlayer?.y ?? 0) + yOffset
        groundItems.append(GroundItem(itemId: itemId, x: x, y: y))
    }

    func removeGroundItem(itemId: Int, x: Int, y: Int) {
        groundItems.removeAll { $0.itemId == itemId && $0.x == x && $0.y == y }
    }

    func removeGroundItem(xOffset: Int, yOffset: Int) {
        let x = (localPlayer?.x ?? 0) + xOffset
        let y = (localPlayer?.y ?? 0) + yOffset
        groundItems.removeAll { $0.x == x && $0.y == y }
    }

    func clearGroundItemsAt(x: Int, y: Int) {
        groundItems.removeAll { $0.x == x && $0.y == y }
    }

    // MARK: - Bank

    func showBank(items: [(id: Int, amount: Int)], maxSize: Int) {
        bankItems = items.enumerated().map { BankItem(slot: $0.offset, itemId: $0.element.id, amount: $0.element.amount) }
        maxBankSize = maxSize
        showingBank = true
    }

    func hideBank() { showingBank = false }

    func updateBankSlot(slot: Int, itemId: Int, amount: Int) {
        if let i = bankItems.firstIndex(where: { $0.slot == slot }) {
            if amount <= 0 { bankItems.remove(at: i) }
            else { bankItems[i] = BankItem(slot: slot, itemId: itemId, amount: amount) }
        } else if amount > 0 {
            bankItems.append(BankItem(slot: slot, itemId: itemId, amount: amount))
        }
    }

    // MARK: - Shop

    func showShop(items: [(id: Int, amount: Int, price: Int)], isGeneralStore: Bool, sellMultiplier: Int, buyMultiplier: Int) {
        shopItems = items.map { ShopItem(itemId: $0.id, amount: $0.amount, price: $0.price) }
        self.isGeneralStore = isGeneralStore
        showingShop = true
    }

    func hideShop() { showingShop = false }

    // MARK: - Dialogue

    func showDialogue(options: [String]) {
        dialogueOptions = options
        showingDialogue = true
    }

    func hideDialogue() {
        showingDialogue = false
        dialogueOptions = []
    }

    // MARK: - Sleep

    func showSleepScreen(captchaImage: Data) {
        sleepCaptchaImage = captchaImage
        showingSleepScreen = true
    }

    func hideSleepScreen() {
        showingSleepScreen = false
        sleepCaptchaImage = nil
    }

    // MARK: - Combat

    func onPlayerDied() {
        addServerMessage("Oh dear, you are dead!")
    }

    func onTeleport(x: Int, y: Int) {
        localPlayer?.x = x
        localPlayer?.y = y
        cameraX = x
        cameraY = y
    }

    // MARK: - Input Handling

    func handleTap(x: Int, y: Int) {
        Task { await SoundManager.shared.play(.click) }

        let world = screenToWorld(screenX: x, screenY: y)
        let worldX = world.x
        let worldY = world.y

        if let npc = findNpcAt(worldX: worldX, worldY: worldY) {
            showContextMenu(for: npc, at: CGPoint(x: x, y: y))
        } else if let player = findPlayerAt(worldX: worldX, worldY: worldY) {
            showContextMenu(for: player, at: CGPoint(x: x, y: y))
        } else if let groundItem = findGroundItemAt(worldX: worldX, worldY: worldY) {
            menuContext = .groundItem(itemId: groundItem.itemId, x: groundItem.x, y: groundItem.y)
            Task { try? await pickupItem(groundItem) }
        } else {
            menuContext = .world(x: worldX, y: worldY)
            Task { try? await walkTo(x: worldX, y: worldY) }
        }
    }

    func handleLongPress(x: Int, y: Int) {
        let world = screenToWorld(screenX: x, screenY: y)
        let worldX = world.x
        let worldY = world.y

        var options: [String] = ["Walk here"]

        if let npc = findNpcAt(worldX: worldX, worldY: worldY) {
            options.insert(contentsOf: ["Talk-to", "Attack", "Examine"], at: 0)
            menuContext = .npc(index: npc.index)
        } else if let player = findPlayerAt(worldX: worldX, worldY: worldY) {
            options.insert(contentsOf: ["Follow", "Trade with", "Attack"], at: 0)
            menuContext = .player(index: player.index)
        } else if let groundItem = findGroundItemAt(worldX: worldX, worldY: worldY) {
            options.insert(contentsOf: ["Take", "Examine"], at: 0)
            menuContext = .groundItem(itemId: groundItem.itemId, x: groundItem.x, y: groundItem.y)
        } else {
            menuContext = .world(x: worldX, y: worldY)
        }

        menuOptions = options
        menuPosition = CGPoint(x: x, y: y)
        showingMenu = true
    }

    func handlePan(deltaX: Float, deltaY: Float) {
        if deltaX != 0 {
            dragRotationAccumulator += deltaX
            while abs(dragRotationAccumulator) >= Self.dragRotationThreshold {
                stepCameraRotation(dragRotationAccumulator > 0 ? 1 : -1)
                dragRotationAccumulator += dragRotationAccumulator > 0 ? -Self.dragRotationThreshold : Self.dragRotationThreshold
            }
        }

        if deltaY != 0 {
            dragZoomAccumulator += deltaY
            while abs(dragZoomAccumulator) >= Self.dragZoomThreshold {
                stepCameraZoom(dragZoomAccumulator < 0 ? 1 : -1)
                dragZoomAccumulator += dragZoomAccumulator > 0 ? -Self.dragZoomThreshold : Self.dragZoomThreshold
            }
        }
    }

    func handlePinch(scale: Float) {
        if scale > 1.06 {
            stepCameraZoom(1)
        } else if scale < 0.94 {
            stepCameraZoom(-1)
        }
    }

    func stepCameraRotation(_ direction: Int) {
        guard direction != 0 else { return }
        let nextRotation = cameraRotation + (direction * Self.cameraRotationStep)
        cameraRotation = ((nextRotation % 256) + 256) % 256
        dragRotationAccumulator = 0
    }

    func stepCameraZoom(_ direction: Int) {
        guard direction != 0,
              let currentIndex = Self.cameraZoomPresets.firstIndex(of: nearestCameraZoomPreset(to: cameraZoom)) else {
            return
        }

        let nextIndex = max(0, min(Self.cameraZoomPresets.count - 1, currentIndex + direction))
        cameraZoom = Self.cameraZoomPresets[nextIndex]
        dragZoomAccumulator = 0
    }

    private func nearestCameraZoomPreset(to value: Int) -> Int {
        Self.cameraZoomPresets.min(by: { abs($0 - value) < abs($1 - value) }) ?? Self.fallbackDefaultZoom
    }

    func finishCameraGesture() {
        dragRotationAccumulator = 0
        dragZoomAccumulator = 0
    }

    // MARK: - Coordinate Conversion

    private func screenToWorldX(_ screenX: Int) -> Int {
        screenToWorld(screenX: screenX, screenY: Self.gameHeight / 2).x
    }

    private func screenToWorldY(_ screenY: Int) -> Int {
        screenToWorld(screenX: Self.gameWidth / 2, screenY: screenY).y
    }

    private func screenToWorld(screenX: Int, screenY: Int) -> (x: Int, y: Int) {
        // Simplified screen-to-world mapping for the 3D pipeline.
        // Uses the camera rotation angle and a fixed tile scale approximation
        // to project screen coordinates back to world tile coordinates.
        let centerX = Self.gameWidth / 2
        let centerY = Self.gameHeight / 2
        let tileScale = Double(max(1, 256 - cameraZoom + 80))
        let rotation = Double(cameraRotation) / 256.0 * (.pi * 2.0)

        let rotatedX = Double(screenX - centerX) / tileScale
        let rotatedY = Double(screenY - centerY) / tileScale

        let worldOffsetX = rotatedX * cos(rotation) + rotatedY * sin(rotation)
        let worldOffsetY = -rotatedX * sin(rotation) + rotatedY * cos(rotation)

        return (
            x: cameraX + Int(worldOffsetX.rounded()),
            y: cameraY + Int(worldOffsetY.rounded())
        )
    }

    // MARK: - Entity Finding

    private func findNpcAt(worldX: Int, worldY: Int) -> Npc? {
        npcs.values.first { abs($0.x - worldX) <= 1 && abs($0.y - worldY) <= 1 }
    }

    private func findPlayerAt(worldX: Int, worldY: Int) -> Player? {
        players.values.first { abs($0.x - worldX) <= 1 && abs($0.y - worldY) <= 1 }
    }

    private func findGroundItemAt(worldX: Int, worldY: Int) -> GroundItem? {
        groundItems.first { $0.x == worldX && $0.y == worldY }
    }

    private func showContextMenu(for npc: Npc, at position: CGPoint) {
        menuOptions = ["Talk-to NPC", "Attack NPC", "Examine NPC"]
        menuPosition = position
        menuContext = .npc(index: npc.index)
        showingMenu = true
    }

    private func showContextMenu(for player: Player, at position: CGPoint) {
        menuOptions = ["Follow \(player.username)", "Trade with \(player.username)", "Attack \(player.username)"]
        menuPosition = position
        menuContext = .player(index: player.index)
        showingMenu = true
    }

    // MARK: - Actions

    func walkTo(x: Int, y: Int) async throws {
        var builder = PacketBuilder()
        builder.writeShort(UInt16(x))
        builder.writeShort(UInt16(y))
        // Opcode 187 = WALK_TO_POINT (16 is WALK_TO_ENTITY)
        try await networkClient.send(builder.build(opcode: 187))
    }

    func pickupItem(_ item: GroundItem) async throws {
        var builder = PacketBuilder()
        builder.writeShort(UInt16(item.x))
        builder.writeShort(UInt16(item.y))
        builder.writeShort(UInt16(item.itemId))
        try await networkClient.send(builder.build(opcode: 247))
    }

    func sendChat(_ message: String) async throws {
        var builder = PacketBuilder()
        // Server custom parser expects linefeed-terminated string for chat
        builder.writeLinefeedString(message)
        try await networkClient.send(builder.build(opcode: 216))
    }

    func logout() async throws {
        // Opcode 102 = LOGOUT (1 is not valid for custom parser)
        try await networkClient.send(PacketBuilder().build(opcode: 102))
    }

    // MARK: - State Mutators (called by PacketHandler)

    func setCombatStyle(_ style: Int) {
        combatStyle = style
    }

    func setActivePrayers(_ prayers: [Bool]) {
        activePrayers = prayers
    }

    func setInventorySlot(slot: Int, itemId: Int, wielded: Bool, noted: Bool, amount: Int) {
        // Ensure inventory is large enough
        while inventory.count <= slot {
            inventory.append(InventoryItem(itemId: 0, amount: 0, equipped: false))
        }
        if itemId == 0 {
            // Empty slot — remove if within bounds
            if slot < inventory.count {
                inventory.remove(at: slot)
            }
        } else {
            inventory[slot] = InventoryItem(itemId: itemId, amount: amount, equipped: wielded)
        }
    }

    func removeInventorySlot(slot: Int) {
        guard slot < inventory.count else { return }
        inventory.remove(at: slot)
    }

    func setFullEquipment(slots: [(wieldPosition: Int, itemId: Int, amount: Int)]) {
        wornEquipment = Array(repeating: -1, count: 11)
        for slot in slots {
            let pos = slot.wieldPosition
            if pos >= 0 && pos < wornEquipment.count {
                wornEquipment[pos] = slot.itemId
            }
        }
    }

    func updateEquipmentSlot(slot: Int, itemId: Int, amount: Int) {
        guard slot >= 0 && slot < wornEquipment.count else { return }
        wornEquipment[slot] = (itemId == 0xFFFF) ? -1 : itemId
    }

    func setSystemUpdateTimer(_ seconds: Int) {
        systemUpdateTimer = seconds
    }

    func showAppearanceScreen() {
        showingAppearanceScreen = true
    }

    func showWelcomeScreen(lastIp: String, daysSinceLogin: Int, recoveryDays: Int) {
        welcomeLastIp = lastIp
        welcomeDaysSinceLogin = daysSinceLogin
        showingWelcomeScreen = true
    }

    func setPrivacySettings(blockChat: Bool, blockPrivate: Bool, blockTrade: Bool, blockDuel: Bool) {
        self.blockChat = blockChat
        self.blockPrivate = blockPrivate
        self.blockTrade = blockTrade
        self.blockDuel = blockDuel
    }

    func setGameSettings(autoCamera: Bool, singleMouseButton: Bool, soundDisabled: Bool) {
        self.autoCamera = autoCamera
        self.soundDisabled = soundDisabled
    }

    func setOnlineList(_ players: [(name: String, icon: Int, location: String)]) {
        onlinePlayers = players
    }

    func onIncorrectSleepword() {
        incorrectSleepwordAttempt = true
        // Reset after a moment so it can trigger again
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.incorrectSleepwordAttempt = false
        }
    }

    func setBankPresetData(slotIndex: Int, data: Data) {
        bankPresetData[slotIndex] = data
    }

    // Trade mutators
    func showTrade(partnerIndex: Int) {
        tradePartnerId = partnerIndex
        tradeMyItems = []
        tradeTheirItems = []
        tradeAccepted = false
        tradeTheyAccepted = false
        showingTrade = true
    }

    func updateTradeTheirItems(_ items: [(id: Int, amount: Int, noted: Bool)]) {
        tradeTheirItems = items
    }

    func setTradeAccepted(_ accepted: Bool) {
        tradeAccepted = accepted
    }

    func setTradeTheyAccepted(_ accepted: Bool) {
        tradeTheyAccepted = accepted
    }

    func showTradeConfirm(partnerName: String, myItems: [(id: Int, amount: Int, noted: Bool)], theirItems: [(id: Int, amount: Int, noted: Bool)]) {
        tradePartnerName = partnerName
        tradeMyItems = myItems
        tradeTheirItems = theirItems
        showingTradeConfirm = true
    }

    func hideTrade() {
        showingTrade = false
        showingTradeConfirm = false
        tradePartnerId = -1
        tradePartnerName = ""
        tradeMyItems = []
        tradeTheirItems = []
        tradeAccepted = false
        tradeTheyAccepted = false
    }

    // Duel mutators
    func showDuel(partnerIndex: Int) {
        duelPartnerId = partnerIndex
        duelMyItems = []
        duelTheirItems = []
        duelAccepted = false
        duelTheyAccepted = false
        showingDuel = true
    }

    func updateDuelTheirItems(_ items: [(id: Int, amount: Int, noted: Bool)]) {
        duelTheirItems = items
    }

    func updateDuelSettings(_ settings: DuelSettings) {
        duelSettings = settings
    }

    func setDuelAccepted(_ accepted: Bool) {
        duelAccepted = accepted
    }

    func setDuelTheyAccepted(_ accepted: Bool) {
        duelTheyAccepted = accepted
    }

    func showDuelConfirm(partnerName: String, myItems: [(id: Int, amount: Int, noted: Bool)], theirItems: [(id: Int, amount: Int, noted: Bool)], settings: DuelSettings) {
        tradePartnerName = partnerName  // reuse tradePartnerName for duel partner display
        duelMyItems = myItems
        duelTheirItems = theirItems
        duelSettings = settings
        showingDuelConfirm = true
    }

    func hideDuel() {
        showingDuel = false
        showingDuelConfirm = false
        duelPartnerId = -1
        duelMyItems = []
        duelTheirItems = []
        duelAccepted = false
        duelTheyAccepted = false
    }

    // MARK: - Action Senders

    func sendCombatStyle(_ style: Int) async throws {
        // opcode 29, payload: 1 byte style
        var b = PacketBuilder()
        b.writeByte(UInt8(style))
        try await networkClient.send(b.build(opcode: 29))
    }

    func sendPrayerToggle(prayerId: Int, active: Bool) async throws {
        // opcode 60 = activate, 254 = deactivate; payload: 2 bytes (short prayerId)
        var b = PacketBuilder()
        b.writeShort(UInt16(prayerId))
        try await networkClient.send(b.build(opcode: active ? 60 : 254))
    }

    func sendTradeAccept() async throws {
        try await networkClient.send(PacketBuilder().build(opcode: 104))
    }

    func sendTradeDecline() async throws {
        try await networkClient.send(PacketBuilder().build(opcode: 230))
    }

    func sendTradeWith(playerIndex: Int) async throws {
        var b = PacketBuilder()
        b.writeShort(UInt16(playerIndex))
        try await networkClient.send(b.build(opcode: 142))
    }

    func sendDialogueAnswer(optionIndex: Int) async throws {
        var b = PacketBuilder()
        b.writeByte(UInt8(optionIndex))
        try await networkClient.send(b.build(opcode: 116))
    }

    func sendBankClose() async throws {
        try await networkClient.send(PacketBuilder().build(opcode: 212))
    }

    func sendBankWithdraw(slot: Int, amount: Int) async throws {
        var b = PacketBuilder()
        b.writeShort(UInt16(slot))
        b.writeInt(UInt32(amount))
        try await networkClient.send(b.build(opcode: 22))
    }

    func sendBankDeposit(slot: Int, amount: Int) async throws {
        var b = PacketBuilder()
        b.writeShort(UInt16(slot))
        b.writeInt(UInt32(amount))
        try await networkClient.send(b.build(opcode: 23))
    }

    func sendShopClose() async throws {
        try await networkClient.send(PacketBuilder().build(opcode: 166))
    }

    func sendShopBuy(itemId: Int, amount: Int) async throws {
        var b = PacketBuilder()
        b.writeShort(UInt16(itemId))
        b.writeInt(UInt32(amount))
        try await networkClient.send(b.build(opcode: 236))
    }

    func sendShopSell(slot: Int, amount: Int) async throws {
        var b = PacketBuilder()
        b.writeShort(UInt16(slot))
        b.writeInt(UInt32(amount))
        try await networkClient.send(b.build(opcode: 221))
    }

    func sendSleepword(_ word: String) async throws {
        var b = PacketBuilder()
        b.writeLinefeedString(word)
        try await networkClient.send(b.build(opcode: 45))
    }

    func talkToNpc(npcIndex: Int) async throws {
        var b = PacketBuilder()
        b.writeShort(UInt16(npcIndex))
        try await networkClient.send(b.build(opcode: 153))
    }

    func attackNpc(npcIndex: Int) async throws {
        var b = PacketBuilder()
        b.writeShort(UInt16(npcIndex))
        try await networkClient.send(b.build(opcode: 190))
    }

    func attackPlayer(playerIndex: Int) async throws {
        var b = PacketBuilder()
        b.writeShort(UInt16(playerIndex))
        try await networkClient.send(b.build(opcode: 171))
    }

    func followPlayer(playerIndex: Int) async throws {
        var b = PacketBuilder()
        b.writeShort(UInt16(playerIndex))
        try await networkClient.send(b.build(opcode: 165))
    }

    func duelPlayer(playerIndex: Int) async throws {
        var b = PacketBuilder()
        b.writeShort(UInt16(playerIndex))
        try await networkClient.send(b.build(opcode: 103))
    }

    func dropItem(slot: Int) async throws {
        var b = PacketBuilder()
        b.writeShort(UInt16(slot))
        try await networkClient.send(b.build(opcode: 246))
    }

    func equipItem(slot: Int) async throws {
        var b = PacketBuilder()
        b.writeShort(UInt16(slot))
        try await networkClient.send(b.build(opcode: 169))
    }

    func unequipItem(slot: Int) async throws {
        var b = PacketBuilder()
        b.writeShort(UInt16(slot))
        try await networkClient.send(b.build(opcode: 170))
    }

    // MARK: - Menu Action Execution

    func onMenuOptionSelected(index: Int) {
        showingMenu = false
        let context = menuContext
        menuContext = .none
        Task {
            switch context {
            case .npc(let i):
                switch index {
                case 0: try? await talkToNpc(npcIndex: i)
                case 1: try? await attackNpc(npcIndex: i)
                default: break
                }
            case .player(let i):
                switch index {
                case 0: try? await followPlayer(playerIndex: i)
                case 1: try? await sendTradeWith(playerIndex: i)
                case 2: try? await attackPlayer(playerIndex: i)
                default: break
                }
            case .groundItem(let id, let x, let y):
                if let item = groundItems.first(where: { $0.itemId == id && $0.x == x && $0.y == y }) {
                    try? await pickupItem(item)
                }
            case .world(let x, let y):
                try? await walkTo(x: x, y: y)
            case .none:
                break
            }
        }
    }
}

// MARK: - Game Models

final class Player: ObservableObject, Identifiable {
    let id = UUID()
    let index: Int
    @Published var username: String
    @Published var x: Int
    @Published var y: Int
    @Published var direction: Int = 0
    @Published var combatLevel: Int = 3
    @Published var appearance: PlayerAppearance?
    @Published var animation: Int = 0
    @Published var currentHits: Int = 10
    @Published var maxHits: Int = 10
    var chatMessage: String? = nil
    var chatMessageExpiry: Date? = nil
    var damageDisplay: Int? = nil
    var damageExpiry: Date? = nil

    init(index: Int, username: String, x: Int, y: Int) {
        self.index = index
        self.username = username
        self.x = x
        self.y = y
    }
}

struct PlayerAppearance {
    var headSprite: Int = 0
    var bodySprite: Int = 0
    var legSprite: Int = 0
    var hairColor: Int = 0
    var topColor: Int = 0
    var bottomColor: Int = 0
    var skinColor: Int = 0
}

final class Npc: ObservableObject, Identifiable {
    let id = UUID()
    let index: Int
    let npcId: Int
    @Published var x: Int
    @Published var y: Int
    @Published var direction: Int = 0
    @Published var animation: Int = 0
    @Published var currentHits: Int = 10
    @Published var maxHits: Int = 10
    var chatMessage: String? = nil
    var chatMessageExpiry: Date? = nil
    var damageDisplay: Int? = nil
    var damageExpiry: Date? = nil

    init(index: Int, npcId: Int, x: Int, y: Int) {
        self.index = index
        self.npcId = npcId
        self.x = x
        self.y = y
    }
}

struct GroundItem: Identifiable {
    let id = UUID()
    let itemId: Int
    let x: Int
    let y: Int
}

struct InventoryItem: Identifiable {
    let id = UUID()
    let itemId: Int
    let amount: Int
    let equipped: Bool
}

struct BankItem: Identifiable {
    let id = UUID()
    let slot: Int
    let itemId: Int
    let amount: Int
}

struct ShopItem: Identifiable {
    let id = UUID()
    let itemId: Int
    let amount: Int
    let price: Int
}

struct WorldObject: Identifiable {
    let id = UUID()
    let objectId: Int
    let x: Int
    let y: Int

    init(id: Int, x: Int, y: Int) {
        self.objectId = id
        self.x = x
        self.y = y
    }
}

struct Boundary: Identifiable {
    let id = UUID()
    let boundaryId: Int
    let x: Int
    let y: Int
    let direction: Int

    init(id: Int, x: Int, y: Int, direction: Int) {
        self.boundaryId = id
        self.x = x
        self.y = y
        self.direction = direction
    }
}

struct EquipmentBonuses {
    var armour: Int = 0
    var weaponAim: Int = 0
    var weaponPower: Int = 0
    var magic: Int = 0
    var prayer: Int = 0
}

struct Skill: Identifiable {
    let id: Int
    let name: String
    var currentLevel: Int
    var maxLevel: Int
    var experience: Int

    static func createAll() -> [Skill] {
        ["Attack", "Defense", "Strength", "Hits", "Ranged", "Prayer", "Magic",
         "Cooking", "Woodcutting", "Fletching", "Fishing", "Firemaking",
         "Crafting", "Smithing", "Mining", "Herblaw", "Agility", "Thieving", "Runecraft"]
            .enumerated().map { i, name in
                Skill(id: i, name: name, currentLevel: i == 3 ? 10 : 1, maxLevel: i == 3 ? 10 : 1, experience: 0)
            }
    }
}

struct ChatMessage: Identifiable {
    enum MessageType { case player, server, quest, trade, privateIn, privateOut }
    let id = UUID()
    let type: MessageType
    let sender: String?
    let message: String
    let timestamp = Date()
}

// MARK: - 3D Rendering Extension

extension GameClient {

    /// Renders a single frame using the 3D RSScene pipeline.
    /// Called each frame by the Metal draw loop (GameRendererView.Coordinator).
    func renderFrame() {
        guard let gc = graphicsController, let sc = scene, let w = world else {
            // Fallback: clear to black if renderer not ready
            frameBuffer = Array(repeating: 0xFF000000, count: Self.gameWidth * Self.gameHeight)
            return
        }

        // 1. Clear previous sprites
        sc.reduceSprites(lastSpriteCount)
        lastSpriteCount = 0

        // 2. Add player sprites to scene
        for (_, player) in players {
            let tileX = player.x * 128 + 64
            let tileZ = player.y * 128 + 64
            let elevation = -w.getElevation(x: tileX, z: tileZ)
            _ = sc.drawSprite(
                spriteIndex: 5000 + player.index,
                x: tileX, pickIndex: player.index, y: elevation,
                z: tileZ, width: 145, height: 220
            )
            lastSpriteCount += 1
        }

        // Local player sprite
        if let lp = localPlayer {
            let tileX = lp.x * 128 + 64
            let tileZ = lp.y * 128 + 64
            let elevation = -w.getElevation(x: tileX, z: tileZ)
            _ = sc.drawSprite(
                spriteIndex: 5000 + lp.index,
                x: tileX, pickIndex: lp.index, y: elevation,
                z: tileZ, width: 145, height: 220
            )
            lastSpriteCount += 1
        }

        // 3. Add NPC sprites
        for (_, npc) in npcs {
            let tileX = npc.x * 128 + 64
            let tileZ = npc.y * 128 + 64
            let elevation = -w.getElevation(x: tileX, z: tileZ)
            _ = sc.drawSprite(
                spriteIndex: 20000 + npc.index,
                x: tileX, pickIndex: 20000 + npc.index, y: elevation,
                z: tileZ, width: 145, height: 220
            )
            lastSpriteCount += 1
        }

        // 4. Add ground item sprites
        for item in groundItems {
            let tileX = item.x * 128 + 64
            let tileZ = item.y * 128 + 64
            let elevation = -w.getElevation(x: tileX, z: tileZ)
            _ = sc.drawSprite(
                spriteIndex: 40000 + item.itemId,
                x: tileX, pickIndex: 40000 + item.itemId, y: elevation,
                z: tileZ, width: 96, height: 64
            )
            lastSpriteCount += 1
        }

        // 5. Clear screen
        gc.blackScreen()

        // 6. Set camera — map 2D client coords to 3D world space
        let camTileX = cameraX * 128 + 64
        let camTileZ = cameraY * 128 + 64
        let camElev = -w.getElevation(x: camTileX, z: camTileZ) - 180
        sc.setCamera(
            centerX: camTileX, centerY: camElev, centerZ: camTileZ,
            xRot: 912, yRot: cameraRotation * 4, zRot: 0,
            offset: cameraZoom * 2
        )

        // 7. Render 3D scene
        sc.endScene()

        // 8. Copy pixel data to frameBuffer for Metal upload
        frameBuffer = gc.pixelData
    }
}
