import Foundation

struct DuelSettings {
    var disallowRetreat: Bool = false
    var disallowMagic: Bool = false
    var disallowPrayer: Bool = false
    var disallowWeapons: Bool = false
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

    init(networkClient: NetworkClient) {
        self.networkClient = networkClient
        self.cameraZoom = Self.fallbackDefaultZoom
        self.frameBuffer = Array(repeating: 0xFF000000, count: Self.gameWidth * Self.gameHeight)

        self.packetHandler = PacketHandler(gameClient: self)

        Task {
            await setupPacketHandling()
        }

        loadSpriteArchives()
    }

    /// Loads .orsc sprite archives from the app bundle.
    private func loadSpriteArchives() {
        if let spritesURL = Bundle.main.url(forResource: "Authentic_Sprites", withExtension: "orsc") {
            SpriteManager.shared.loadArchive(from: spritesURL)
        } else {
            print("GameClient: Authentic_Sprites.orsc not found in bundle")
        }
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
        }
    }

    func playerDamage(index: Int, damage: Int, curHits: Int, maxHits: Int) {
        if let player = players[index] {
            player.currentHits = curHits
            player.maxHits = maxHits
        } else if index == localPlayer?.index {
            localPlayer?.currentHits = curHits
            localPlayer?.maxHits = maxHits
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
    }

    func npcDamage(index: Int, damage: Int, curHits: Int, maxHits: Int) {
        if let npc = npcs[index] {
            npc.currentHits = curHits
            npc.maxHits = maxHits
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
            Task { try? await pickupItem(groundItem) }
        } else {
            Task { try? await walkTo(x: worldX, y: worldY) }
        }
    }

    func handleLongPress(x: Int, y: Int) {
        let world = screenToWorld(screenX: x, screenY: y)
        let worldX = world.x
        let worldY = world.y

        var options: [String] = ["Walk here"]
        if findNpcAt(worldX: worldX, worldY: worldY) != nil {
            options.insert(contentsOf: ["Talk-to", "Attack", "Examine"], at: 0)
        }
        if findPlayerAt(worldX: worldX, worldY: worldY) != nil {
            options.insert(contentsOf: ["Follow", "Trade with", "Attack"], at: 0)
        }
        if findGroundItemAt(worldX: worldX, worldY: worldY) != nil {
            options.insert(contentsOf: ["Take", "Examine"], at: 0)
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
        let centerX = Self.gameWidth / 2
        let centerY = horizonLineY()
        let tileWidth = Double(fallbackTileWidth())
        let tileHeight = Double(fallbackTileHeight())
        let rotation = cameraAngleRadians()

        let rotatedX = Double(screenX - centerX) / tileWidth
        let rotatedY = Double(screenY - centerY) / tileHeight

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
        showingMenu = true
    }

    private func showContextMenu(for player: Player, at position: CGPoint) {
        menuOptions = ["Follow \(player.username)", "Trade with \(player.username)", "Attack \(player.username)"]
        menuPosition = position
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

// MARK: - Rendering Extension

extension GameClient {
    private enum TerrainKind {
        case water
        case beach
        case grass
        case path
        case heath
        case stone
    }

    private struct TerrainTile {
        let worldX: Int
        let worldY: Int
        let screenX: Int
        let screenY: Int
        let kind: TerrainKind
        let seed: Int
        let baseColorOverride: UInt32?
        let detailColorOverride: UInt32?
        let elevation: Int
        let groundTexture: Int
        let groundOverlay: Int
        let horizontalWall: Int
        let verticalWall: Int
        let diagonalWalls: Int
    }

    private struct AuthenticTerrainVisual {
        let baseColor: UInt32
        let detailColor: UInt32
        let elevation: Int
        let groundTexture: Int
        let groundOverlay: Int
        let horizontalWall: Int
        let verticalWall: Int
        let diagonalWalls: Int
    }

    private struct SceneCommand {
        let sortY: Int
        let sortX: Int
        let draw: () -> Void
    }

    func renderFrame() {
        frameBuffer = Array(repeating: 0xFF000000, count: Self.gameWidth * Self.gameHeight)
        drawSkyGradient()
        drawTerrain()
        drawEntities()
        drawSceneVignette()
    }

    // MARK: - Sky

    private func drawSkyGradient() {
        let horizon = horizonLineY()
        for y in 0..<horizon {
            let t = Double(y) / Double(max(1, horizon))
            let top = Self.rgbStatic(r: 56, g: 93, b: 152)
            let bottom = Self.rgbStatic(r: 165, g: 198, b: 224)
            let rowColor = blend(top, with: bottom, alpha: Int(t * 255))
            drawHLineInBuffer(x: 0, y: y, width: Self.gameWidth, color: rowColor)
        }

        let sunX = Self.gameWidth - 92
        let sunY = 46
        fillEllipseInBuffer(centerX: sunX, centerY: sunY, radiusX: 22, radiusY: 22, color: 0xFFFFE6A6, alpha: 210)
        fillEllipseInBuffer(centerX: sunX, centerY: sunY, radiusX: 34, radiusY: 34, color: 0xFFFFE0A0, alpha: 48)

        drawCloud(centerX: 104, centerY: 40, scale: 20)
        drawCloud(centerX: 214, centerY: 58, scale: 14)
        drawCloud(centerX: 366, centerY: 36, scale: 18)
        drawDistantHills()
    }

    private func drawCloud(centerX: Int, centerY: Int, scale: Int) {
        let cloudColor: UInt32 = 0xFFF7FBFF
        fillEllipseInBuffer(centerX: centerX - scale, centerY: centerY + 2, radiusX: scale, radiusY: scale / 2, color: cloudColor, alpha: 115)
        fillEllipseInBuffer(centerX: centerX, centerY: centerY - 2, radiusX: scale + 6, radiusY: scale / 2 + 2, color: cloudColor, alpha: 135)
        fillEllipseInBuffer(centerX: centerX + scale, centerY: centerY + 2, radiusX: scale - 2, radiusY: scale / 2, color: cloudColor, alpha: 110)
    }

    private func drawDistantHills() {
        let horizon = horizonLineY()
        for x in stride(from: -32, to: Self.gameWidth + 32, by: 32) {
            let wave = Int(10 * sin(Double(x) * 0.04))
            let height = 26 + Int(14 * sin(Double(x) * 0.015 + 1.2))
            fillTriangleFanPeak(
                baseX: x,
                baseY: horizon - 8,
                width: 56,
                height: height + wave,
                colorTop: 0xFF5A7D67,
                colorBottom: 0xFF314E40
            )
        }
    }

    // MARK: - Terrain

    private func drawTerrain() {
        let tileWidth = fallbackTileWidth()
        let tileHeight = fallbackTileHeight()
        let radiusX = Self.gameWidth / max(1, tileWidth) / 2 + 10
        let radiusY = Self.gameHeight / max(1, tileHeight) / 2 + 10

        var tiles: [TerrainTile] = []
        tiles.reserveCapacity((radiusX * 2 + 1) * (radiusY * 2 + 1))

        for worldY in (cameraY - radiusY)...(cameraY + radiusY) {
            for worldX in (cameraX - radiusX)...(cameraX + radiusX) {
                let (screenX, screenY) = worldToScreen(x: worldX, y: worldY)
                guard screenX >= -tileWidth, screenX <= Self.gameWidth + tileWidth,
                      screenY >= horizonLineY() - tileHeight * 2, screenY <= Self.gameHeight + tileHeight else {
                    continue
                }

                let seed = terrainSeed(worldX: worldX, worldY: worldY)
                let authentic = authenticTerrainVisual(worldX: worldX, worldY: worldY)
                tiles.append(
                    TerrainTile(
                        worldX: worldX,
                        worldY: worldY,
                        screenX: screenX,
                        screenY: screenY,
                        kind: terrainKind(worldX: worldX, worldY: worldY, seed: seed),
                        seed: seed,
                        baseColorOverride: authentic?.baseColor,
                        detailColorOverride: authentic?.detailColor,
                        elevation: authentic?.elevation ?? 0,
                        groundTexture: authentic?.groundTexture ?? 0,
                        groundOverlay: authentic?.groundOverlay ?? 0,
                        horizontalWall: authentic?.horizontalWall ?? 0,
                        verticalWall: authentic?.verticalWall ?? 0,
                        diagonalWalls: authentic?.diagonalWalls ?? 0
                    )
                )
            }
        }

        tiles.sort {
            if $0.screenY == $1.screenY {
                return $0.screenX < $1.screenX
            }
            return $0.screenY < $1.screenY
        }

        for tile in tiles {
            drawTerrainTile(tile, tileWidth: tileWidth, tileHeight: tileHeight)
        }
    }

    private func drawTerrainTile(_ tile: TerrainTile, tileWidth: Int, tileHeight: Int) {
        let halfWidth = tileWidth / 2
        let halfHeight = tileHeight / 2
        let baseColor = tile.baseColorOverride ?? terrainBaseColor(kind: tile.kind, seed: tile.seed)
        let elevationBias = max(-10, min(14, tile.elevation / 9))

        for row in -halfHeight...halfHeight {
            let span = max(0, halfWidth - abs(row) * max(1, halfWidth) / max(1, halfHeight))
            let shadeBias = (row < 0 ? 28 - abs(row) * 2 : -12 - row) + elevationBias
            let shaded = shadeBias >= 0
                ? lighten(baseColor, by: min(72, shadeBias))
                : darken(baseColor, by: min(68, -shadeBias))
            drawHLineInBuffer(
                x: tile.screenX - span,
                y: tile.screenY + row,
                width: span * 2 + 1,
                color: shaded
            )
        }

        let borderLight = lighten(baseColor, by: 50)
        let borderDark = darken(baseColor, by: 74)
        for row in 0...halfHeight {
            let offset = row * max(1, halfWidth) / max(1, halfHeight)
            setPixelInBuffer(x: tile.screenX - offset, y: tile.screenY - row, color: borderLight)
            setPixelInBuffer(x: tile.screenX + offset, y: tile.screenY - row, color: borderLight)
            setPixelInBuffer(x: tile.screenX - offset, y: tile.screenY + row, color: borderDark)
            setPixelInBuffer(x: tile.screenX + offset, y: tile.screenY + row, color: borderDark)
        }

        drawTerrainDetail(tile, tileWidth: tileWidth, tileHeight: tileHeight, baseColor: baseColor)
    }

    private func drawTerrainDetail(_ tile: TerrainTile, tileWidth: Int, tileHeight: Int, baseColor: UInt32) {
        if let detailColor = tile.detailColorOverride {
            drawAuthenticTerrainDetail(
                tile,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
                baseColor: baseColor,
                detailColor: detailColor
            )
            return
        }

        let sparkleColor = lighten(baseColor, by: 36)
        let darker = darken(baseColor, by: 38)
        switch tile.kind {
        case .water:
            let rippleY = tile.screenY - tileHeight / 6
            drawHLineInBuffer(x: tile.screenX - tileWidth / 4, y: rippleY, width: tileWidth / 2, color: sparkleColor)
            drawHLineInBuffer(x: tile.screenX - tileWidth / 6, y: rippleY + 3, width: tileWidth / 3, color: blend(baseColor, with: 0xFFFFFFFF, alpha: 24))
        case .beach:
            fillEllipseInBuffer(centerX: tile.screenX - 4, centerY: tile.screenY, radiusX: 2, radiusY: 1, color: darker, alpha: 180)
            fillEllipseInBuffer(centerX: tile.screenX + 5, centerY: tile.screenY - 2, radiusX: 2, radiusY: 1, color: darker, alpha: 150)
        case .grass:
            drawVLineInBuffer(x: tile.screenX - 4, y: tile.screenY - 2, height: 4, color: sparkleColor)
            drawVLineInBuffer(x: tile.screenX + 4, y: tile.screenY - 1, height: 3, color: darker)
        case .path:
            drawHLineInBuffer(x: tile.screenX - tileWidth / 5, y: tile.screenY, width: tileWidth / 3, color: darker)
            drawHLineInBuffer(x: tile.screenX - tileWidth / 6, y: tile.screenY - 2, width: tileWidth / 4, color: sparkleColor)
        case .heath:
            fillEllipseInBuffer(centerX: tile.screenX - 3, centerY: tile.screenY - 2, radiusX: 2, radiusY: 2, color: darker, alpha: 180)
            fillEllipseInBuffer(centerX: tile.screenX + 5, centerY: tile.screenY + 1, radiusX: 2, radiusY: 1, color: sparkleColor, alpha: 140)
        case .stone:
            drawHLineInBuffer(x: tile.screenX - tileWidth / 6, y: tile.screenY - 1, width: tileWidth / 4, color: darker)
            drawVLineInBuffer(x: tile.screenX + 3, y: tile.screenY - 3, height: 5, color: sparkleColor)
        }
    }

    private func drawAuthenticTerrainDetail(
        _ tile: TerrainTile,
        tileWidth: Int,
        tileHeight: Int,
        baseColor: UInt32,
        detailColor: UInt32
    ) {
        let highlight = lighten(detailColor, by: 26)
        let darker = darken(baseColor, by: 30)
        let textureBand = posMod(tile.groundTexture, 4)

        switch tile.groundOverlay {
        case 250:
            let rippleY = tile.screenY - tileHeight / 6
            drawHLineInBuffer(
                x: tile.screenX - tileWidth / 4,
                y: rippleY,
                width: tileWidth / 2,
                color: highlight
            )
            drawHLineInBuffer(
                x: tile.screenX - tileWidth / 6,
                y: rippleY + 3,
                width: tileWidth / 3,
                color: blend(baseColor, with: 0xFFFFFFFF, alpha: 28)
            )
        default:
            let bandY = tile.screenY - tileHeight / 5 + textureBand
            drawHLineInBuffer(
                x: tile.screenX - tileWidth / 5,
                y: bandY,
                width: tileWidth / 3,
                color: highlight
            )
            fillEllipseInBuffer(
                centerX: tile.screenX - 3,
                centerY: tile.screenY - 2,
                radiusX: 2,
                radiusY: 1,
                color: darker,
                alpha: 140
            )
            fillEllipseInBuffer(
                centerX: tile.screenX + 4,
                centerY: tile.screenY + 1,
                radiusX: 2,
                radiusY: 1,
                color: detailColor,
                alpha: 120
            )
        }

        if tile.horizontalWall > 0 {
            for row in 0...(tileHeight / 2) {
                let offset = row * max(1, tileWidth / 2) / max(1, tileHeight / 2)
                setPixelInBuffer(
                    x: tile.screenX - offset,
                    y: tile.screenY - row,
                    color: lighten(detailColor, by: 42)
                )
                setPixelInBuffer(
                    x: tile.screenX + offset,
                    y: tile.screenY - row,
                    color: darken(detailColor, by: 28)
                )
            }
        }

        if tile.verticalWall > 0 {
            for row in 0...(tileHeight / 2) {
                let offset = row * max(1, tileWidth / 2) / max(1, tileHeight / 2)
                setPixelInBuffer(
                    x: tile.screenX + offset,
                    y: tile.screenY + row,
                    color: darken(detailColor, by: 20)
                )
            }
        }

        if tile.diagonalWalls > 0 {
            for offset in -(tileWidth / 4)...(tileWidth / 4) {
                let diagY = tile.screenY - tileHeight / 4 + abs(offset) / 2
                setPixelInBuffer(x: tile.screenX + offset, y: diagY, color: darker)
            }
        }
    }

    private func terrainSeed(worldX: Int, worldY: Int) -> Int {
        let macro = posMod((worldX / 4) * 53 + (worldY / 4) * 79, 256)
        let micro = posMod(worldX * 17 + worldY * 31, 128)
        return posMod(macro * 5 + micro, 1024)
    }

    private func terrainKind(worldX: Int, worldY: Int, seed: Int) -> TerrainKind {
        let coastal = posMod((worldX / 7) * 19 + (worldY / 7) * 23, 100)
        if coastal < 11 { return .water }
        if coastal < 16 { return .beach }
        if seed < 460 { return .grass }
        if seed < 590 { return .path }
        if seed < 815 { return .heath }
        return .stone
    }

    private func terrainBaseColor(kind: TerrainKind, seed: Int) -> UInt32 {
        let variation = seed % 32
        switch kind {
        case .water:
            return Self.rgbStatic(r: 48 + variation / 2, g: 94 + variation / 3, b: 160 + variation)
        case .beach:
            return Self.rgbStatic(r: 176 + variation / 2, g: 158 + variation / 4, b: 102 + variation / 5)
        case .grass:
            return Self.rgbStatic(r: 70 + variation / 3, g: 130 + variation, b: 58 + variation / 4)
        case .path:
            return Self.rgbStatic(r: 116 + variation / 3, g: 92 + variation / 5, b: 64 + variation / 6)
        case .heath:
            return Self.rgbStatic(r: 96 + variation / 4, g: 112 + variation / 4, b: 66 + variation / 5)
        case .stone:
            return Self.rgbStatic(r: 110 + variation / 4, g: 116 + variation / 4, b: 122 + variation / 5)
        }
    }

    private func authenticTerrainVisual(worldX: Int, worldY: Int) -> AuthenticTerrainVisual? {
        guard let tile = landscapeArchive.tile(
            atWorldX: worldX,
            worldY: worldY,
            plane: worldPlane,
            centeredAt: cameraX,
            centerY: cameraY
        ) else {
            return nil
        }

        let textureColor = terrainTextureColor(tile.groundTexture)
        let overlayColor = terrainOverlayColor(tile.groundOverlay) ?? textureColor
        let baseColor: UInt32
        let detailColor: UInt32

        if tile.groundOverlay == 250 {
            baseColor = blend(textureColor, with: Self.rgbStatic(r: 48, g: 96, b: 168), alpha: 180)
            detailColor = lighten(baseColor, by: 24)
        } else {
            baseColor = overlayColor
            detailColor = terrainOverlayAccent(
                overlay: tile.groundOverlay,
                fallback: lighten(overlayColor, by: 22)
            )
        }

        return AuthenticTerrainVisual(
            baseColor: baseColor,
            detailColor: detailColor,
            elevation: tile.groundElevation * 3,
            groundTexture: tile.groundTexture,
            groundOverlay: tile.groundOverlay,
            horizontalWall: tile.horizontalWall,
            verticalWall: tile.verticalWall,
            diagonalWalls: tile.diagonalWalls
        )
    }

    private func terrainTextureColor(_ textureId: Int) -> UInt32 {
        let texture = posMod(textureId, 256)
        switch texture {
        case 0..<64:
            return Self.rgbStatic(
                r: 255 - texture * 4,
                g: 255 - Int(Double(texture) * 1.75),
                b: 255 - texture * 4
            )
        case 64..<128:
            let value = texture - 64
            return Self.rgbStatic(r: value * 3, g: 144, b: 0)
        case 128..<192:
            let value = texture - 128
            return Self.rgbStatic(
                r: 192 - Int(Double(value) * 1.5),
                g: 144 - Int(Double(value) * 1.5),
                b: 0
            )
        default:
            let value = texture - 192
            return Self.rgbStatic(
                r: 96 - Int(Double(value) * 1.5),
                g: Int(Double(value) * 1.5) + 48,
                b: 0
            )
        }
    }

    private func terrainOverlayColor(_ overlayId: Int) -> UInt32? {
        guard overlayId > 0 else { return nil }
        guard let definition = TileDefinitions.shared.definition(for: overlayId) else {
            return overlayId == 250 ? Self.rgbStatic(r: 46, g: 100, b: 174) : nil
        }
        return decodeTerrainColor(definition.color)
    }

    private func terrainOverlayAccent(overlay: Int, fallback: UInt32) -> UInt32 {
        guard overlay > 0,
              let definition = TileDefinitions.shared.definition(for: overlay) else {
            return fallback
        }
        switch definition.objectType {
        case 1:
            return lighten(fallback, by: 18)
        case 0:
            return darken(fallback, by: 8)
        default:
            return fallback
        }
    }

    private func decodeTerrainColor(_ colorValue: Int) -> UInt32? {
        if colorValue == 12345678 {
            return nil
        }

        if colorValue < 0 {
            let packed = -colorValue - 1
            let blue = packed & 31
            let green = (packed >> 5) & 31
            let red = (packed >> 10) & 31
            return Self.rgbStatic(
                r: red * 255 / 31,
                g: green * 255 / 31,
                b: blue * 255 / 31
            )
        }

        if colorValue < 256 {
            return terrainTextureColor(colorValue)
        }

        return 0xFF000000 | UInt32(colorValue & 0x00FF_FFFF)
    }

    // MARK: - Entities

    private func drawEntities() {
        let spriteManager = SpriteManager.shared
        var commands: [SceneCommand] = []

        for obj in sceneryObjects {
            let (sx, sy) = worldToScreen(x: obj.x, y: obj.y)
            commands.append(
                SceneCommand(sortY: sy, sortX: sx) {
                    self.drawSceneShadow(centerX: sx, centerY: sy - 2, radiusX: 12, radiusY: 5, intensity: 70)
                    if let sprite = spriteManager.getObjectSprite(objectId: obj.objectId) {
                        self.drawSpriteToBuffer(sprite, at: sx - sprite.width / 2, y: sy - sprite.height)
                    } else {
                        self.drawObjectShape(x: sx, y: sy, objectId: obj.objectId)
                    }
                }
            )
        }

        for boundary in boundaries {
            let (sx, sy) = worldToScreen(x: boundary.x, y: boundary.y)
            commands.append(
                SceneCommand(sortY: sy, sortX: sx) {
                    self.drawSceneShadow(centerX: sx, centerY: sy - 1, radiusX: 11, radiusY: 4, intensity: 55)
                    self.drawBoundaryShape(x: sx, y: sy, direction: boundary.direction)
                }
            )
        }

        for item in groundItems {
            let (sx, sy) = worldToScreen(x: item.x, y: item.y)
            commands.append(
                SceneCommand(sortY: sy + 1, sortX: sx) {
                    self.drawSceneShadow(centerX: sx, centerY: sy, radiusX: 7, radiusY: 3, intensity: 46)
                    if let sprite = spriteManager.getItemSprite(itemId: item.itemId) {
                        self.drawSpriteToBuffer(sprite, at: sx - sprite.width / 2, y: sy - sprite.height / 2)
                    } else {
                        self.drawItemShape(x: sx, y: sy, itemId: item.itemId)
                    }
                }
            )
        }

        for (_, npc) in npcs {
            let (sx, sy) = worldToScreen(x: npc.x, y: npc.y)
            commands.append(
                SceneCommand(sortY: sy + 8, sortX: sx) {
                    self.drawSceneShadow(centerX: sx, centerY: sy - 1, radiusX: 10, radiusY: 4, intensity: 72)
                    if let sprite = spriteManager.getNpcSprite(npcId: npc.npcId, direction: npc.direction, animation: npc.animation) {
                        self.drawSpriteToBuffer(sprite, at: sx - sprite.width / 2, y: sy - sprite.height)
                    } else {
                        self.drawNpcShape(npc, x: sx, y: sy)
                    }
                }
            )
        }

        for (_, player) in players {
            let (sx, sy) = worldToScreen(x: player.x, y: player.y)
            commands.append(
                SceneCommand(sortY: sy + 10, sortX: sx) {
                    self.drawSceneShadow(centerX: sx, centerY: sy - 1, radiusX: 10, radiusY: 4, intensity: 76)
                    if let sprite = spriteManager.getPlayerSprite(
                        appearance: player.appearance,
                        direction: player.direction,
                        isWalking: player.animation != 0,
                        animationFrame: player.animation
                    ) {
                        self.drawSpriteToBuffer(sprite, at: sx - sprite.width / 2, y: sy - sprite.height)
                    } else {
                        self.drawPlayerShape(player, x: sx, y: sy, isLocal: false)
                    }
                }
            )
        }

        if let player = localPlayer {
            let (sx, sy) = worldToScreen(x: player.x, y: player.y)
            commands.append(
                SceneCommand(sortY: sy + 11, sortX: sx) {
                    self.drawSceneShadow(centerX: sx, centerY: sy - 1, radiusX: 10, radiusY: 4, intensity: 86)
                    if let sprite = spriteManager.getPlayerSprite(
                        appearance: player.appearance,
                        direction: player.direction,
                        isWalking: player.animation != 0,
                        animationFrame: player.animation
                    ) {
                        self.drawSpriteToBuffer(sprite, at: sx - sprite.width / 2, y: sy - sprite.height)
                    } else {
                        self.drawPlayerShape(player, x: sx, y: sy, isLocal: true)
                    }
                }
            )
        }

        commands.sort {
            if $0.sortY == $1.sortY {
                return $0.sortX < $1.sortX
            }
            return $0.sortY < $1.sortY
        }
        for command in commands {
            command.draw()
        }
    }

    private func drawPlayerShape(_ player: Player, x: Int, y: Int, isLocal: Bool) {
        let skin = appearanceColor(player.appearance?.skinColor, palette: Self.skinPalette, default: 0xFFDCBC92)
        let hair = appearanceColor(player.appearance?.hairColor, palette: Self.hairPalette, default: 0xFF6A4325)
        let top = appearanceColor(player.appearance?.topColor, palette: Self.clothingPalette, default: 0xFF8E3D2F)
        let bottom = appearanceColor(player.appearance?.bottomColor, palette: Self.clothingPalette, default: 0xFF5C482F)
        let trim = isLocal ? 0xFFEEDC7B : darken(top, by: 72)

        fillRectInBuffer(x: x - 7, y: y - 34, width: 3, height: 14, color: darken(top, by: 30))
        fillRectInBuffer(x: x + 4, y: y - 34, width: 3, height: 14, color: darken(top, by: 30))

        fillRectInBuffer(x: x - 5, y: y - 18, width: 4, height: 14, color: bottom)
        fillRectInBuffer(x: x + 1, y: y - 18, width: 4, height: 14, color: bottom)
        fillRectInBuffer(x: x - 6, y: y - 4, width: 5, height: 3, color: 0xFF2D1E18)
        fillRectInBuffer(x: x + 1, y: y - 4, width: 5, height: 3, color: 0xFF2D1E18)

        fillRectInBuffer(x: x - 7, y: y - 40, width: 14, height: 16, color: top)
        fillRectInBuffer(x: x - 5, y: y - 47, width: 10, height: 8, color: skin)
        fillRectInBuffer(x: x - 6, y: y - 49, width: 12, height: 3, color: hair)
        fillRectInBuffer(x: x - 6, y: y - 47, width: 1, height: 7, color: hair)
        fillRectInBuffer(x: x + 5, y: y - 47, width: 1, height: 7, color: hair)
        fillRectInBuffer(x: x - 7, y: y - 40, width: 14, height: 2, color: trim)
        fillRectInBuffer(x: x - 4, y: y - 37, width: 8, height: 2, color: lighten(top, by: 34))

        fillRectInBuffer(x: x - 3, y: y - 28, width: 1, height: 1, color: trim)
        fillRectInBuffer(x: x + 2, y: y - 28, width: 1, height: 1, color: trim)
        if isLocal {
            drawDiamondMarker(centerX: x, centerY: y - 54, radius: 5, color: 0xFFFFE082)
        }
    }

    private func drawNpcShape(_ npc: Npc, x: Int, y: Int) {
        let main = npcColor(npc.npcId)
        let accent = lighten(main, by: 34)
        let dark = darken(main, by: 66)

        fillRectInBuffer(x: x - 6, y: y - 38, width: 12, height: 18, color: main)
        fillRectInBuffer(x: x - 4, y: y - 48, width: 8, height: 10, color: accent)
        fillRectInBuffer(x: x - 3, y: y - 20, width: 3, height: 14, color: dark)
        fillRectInBuffer(x: x + 1, y: y - 20, width: 3, height: 14, color: dark)
        fillRectInBuffer(x: x - 9, y: y - 34, width: 3, height: 11, color: main)
        fillRectInBuffer(x: x + 6, y: y - 34, width: 3, height: 11, color: main)
        if posMod(npc.npcId, 3) == 0 {
            fillRectInBuffer(x: x - 5, y: y - 51, width: 2, height: 4, color: dark)
            fillRectInBuffer(x: x + 3, y: y - 51, width: 2, height: 4, color: dark)
        }
    }

    private func drawObjectShape(x: Int, y: Int, objectId: Int) {
        switch posMod(objectId, 4) {
        case 0:
            drawTreeShape(x: x, y: y, objectId: objectId)
        case 1:
            drawRockShape(x: x, y: y, objectId: objectId)
        case 2:
            drawCrateShape(x: x, y: y)
        default:
            drawPillarShape(x: x, y: y)
        }
    }

    private func drawTreeShape(x: Int, y: Int, objectId: Int) {
        let leafBase = blend(0xFF2E7D32, with: 0xFF6A9D3E, alpha: posMod(objectId * 17, 70))
        let leafHighlight = lighten(leafBase, by: 42)
        let trunk: UInt32 = 0xFF6B4226
        fillRectInBuffer(x: x - 3, y: y - 28, width: 6, height: 22, color: trunk)
        fillEllipseInBuffer(centerX: x, centerY: y - 40, radiusX: 13, radiusY: 12, color: leafBase, alpha: 255)
        fillEllipseInBuffer(centerX: x - 8, centerY: y - 34, radiusX: 9, radiusY: 8, color: darken(leafBase, by: 14), alpha: 255)
        fillEllipseInBuffer(centerX: x + 8, centerY: y - 34, radiusX: 9, radiusY: 8, color: darken(leafBase, by: 12), alpha: 255)
        fillEllipseInBuffer(centerX: x, centerY: y - 47, radiusX: 9, radiusY: 8, color: leafHighlight, alpha: 235)
    }

    private func drawRockShape(x: Int, y: Int, objectId: Int) {
        let rock = blend(0xFF7A7B84, with: 0xFF5E646C, alpha: posMod(objectId * 13, 88))
        fillEllipseInBuffer(centerX: x, centerY: y - 10, radiusX: 14, radiusY: 10, color: rock, alpha: 255)
        fillEllipseInBuffer(centerX: x - 6, centerY: y - 16, radiusX: 8, radiusY: 7, color: lighten(rock, by: 22), alpha: 255)
        drawHLineInBuffer(x: x - 7, y: y - 12, width: 10, color: darken(rock, by: 52))
    }

    private func drawCrateShape(x: Int, y: Int) {
        let wood: UInt32 = 0xFF8B5A2B
        fillRectInBuffer(x: x - 10, y: y - 18, width: 20, height: 16, color: wood)
        drawHLineInBuffer(x: x - 10, y: y - 14, width: 20, color: lighten(wood, by: 28))
        drawVLineInBuffer(x: x, y: y - 18, height: 16, color: darken(wood, by: 42))
    }

    private func drawPillarShape(x: Int, y: Int) {
        let stone: UInt32 = 0xFF9A9285
        fillRectInBuffer(x: x - 5, y: y - 28, width: 10, height: 24, color: stone)
        fillRectInBuffer(x: x - 8, y: y - 32, width: 16, height: 5, color: lighten(stone, by: 24))
        fillRectInBuffer(x: x - 7, y: y - 6, width: 14, height: 4, color: darken(stone, by: 35))
    }

    private func drawBoundaryShape(x: Int, y: Int, direction: Int) {
        let wall: UInt32 = 0xFF8A8174
        if direction == 0 || direction == 2 {
            fillRectInBuffer(x: x - 16, y: y - 8, width: 32, height: 6, color: wall)
            fillRectInBuffer(x: x - 16, y: y - 8, width: 32, height: 2, color: lighten(wall, by: 28))
            fillRectInBuffer(x: x - 16, y: y - 2, width: 4, height: 8, color: darken(wall, by: 42))
            fillRectInBuffer(x: x + 12, y: y - 2, width: 4, height: 8, color: darken(wall, by: 42))
        } else {
            fillRectInBuffer(x: x - 4, y: y - 24, width: 8, height: 24, color: wall)
            fillRectInBuffer(x: x - 4, y: y - 24, width: 8, height: 3, color: lighten(wall, by: 28))
            fillRectInBuffer(x: x + 2, y: y - 24, width: 2, height: 24, color: darken(wall, by: 44))
        }
    }

    private func drawItemShape(x: Int, y: Int, itemId: Int) {
        switch posMod(itemId, 4) {
        case 0:
            drawDiamondMarker(centerX: x, centerY: y - 3, radius: 5, color: 0xFFF0D35B)
        case 1:
            fillEllipseInBuffer(centerX: x, centerY: y - 3, radiusX: 6, radiusY: 4, color: 0xFFCFD7E2, alpha: 255)
            fillEllipseInBuffer(centerX: x + 1, centerY: y - 4, radiusX: 2, radiusY: 1, color: 0xFFFFFFFF, alpha: 220)
        case 2:
            fillRectInBuffer(x: x - 2, y: y - 11, width: 4, height: 10, color: 0xFFC7E65F)
            fillEllipseInBuffer(centerX: x, centerY: y - 12, radiusX: 4, radiusY: 3, color: 0xFFAC3248, alpha: 255)
        default:
            fillRectInBuffer(x: x - 1, y: y - 10, width: 2, height: 10, color: 0xFFCFC8C0)
            fillRectInBuffer(x: x - 4, y: y - 11, width: 8, height: 2, color: 0xFFB74A4A)
        }
    }

    // MARK: - Sprite Drawing

    private func drawSpriteToBuffer(_ sprite: Sprite, at x: Int, y: Int) {
        let drawX = sprite.useShift ? x + sprite.offsetX : x
        let drawY = sprite.useShift ? y + sprite.offsetY : y

        for sy in 0..<sprite.height {
            let destY = drawY + sy
            guard destY >= 0 && destY < Self.gameHeight else { continue }

            for sx in 0..<sprite.width {
                let destX = drawX + sx
                guard destX >= 0 && destX < Self.gameWidth else { continue }

                let pixel = sprite.pixels[sy * sprite.width + sx]
                let alpha = (pixel >> 24) & 0xFF
                if alpha == 0 { continue }

                let destIndex = destY * Self.gameWidth + destX
                if alpha == 255 {
                    frameBuffer[destIndex] = pixel
                } else {
                    let a = Int(alpha)
                    let srcR = Int((pixel >> 16) & 0xFF)
                    let srcG = Int((pixel >> 8) & 0xFF)
                    let srcB = Int(pixel & 0xFF)
                    let dst = frameBuffer[destIndex]
                    let dstR = Int((dst >> 16) & 0xFF)
                    let dstG = Int((dst >> 8) & 0xFF)
                    let dstB = Int(dst & 0xFF)
                    let outR = UInt32((srcR * a + dstR * (255 - a)) / 255)
                    let outG = UInt32((srcG * a + dstG * (255 - a)) / 255)
                    let outB = UInt32((srcB * a + dstB * (255 - a)) / 255)
                    frameBuffer[destIndex] = 0xFF000000 | (outR << 16) | (outG << 8) | outB
                }
            }
        }
    }

    // MARK: - Primitive Drawing

    private func fillRectInBuffer(x: Int, y: Int, width: Int, height: Int, color: UInt32) {
        guard width > 0, height > 0 else { return }
        let startY = max(0, y)
        let endY = min(y + height, Self.gameHeight)
        let startX = max(0, x)
        let endX = min(x + width, Self.gameWidth)
        guard startX < endX, startY < endY else { return }

        for py in startY..<endY {
            let rowStart = py * Self.gameWidth
            for px in startX..<endX {
                frameBuffer[rowStart + px] = color
            }
        }
    }

    private func drawHLineInBuffer(x: Int, y: Int, width: Int, color: UInt32) {
        guard y >= 0 && y < Self.gameHeight, width > 0 else { return }
        let startX = max(0, x)
        let endX = min(x + width, Self.gameWidth)
        guard startX < endX else { return }
        let rowStart = y * Self.gameWidth
        for px in startX..<endX {
            frameBuffer[rowStart + px] = color
        }
    }

    private func drawVLineInBuffer(x: Int, y: Int, height: Int, color: UInt32) {
        guard x >= 0 && x < Self.gameWidth, height > 0 else { return }
        let startY = max(0, y)
        let endY = min(y + height, Self.gameHeight)
        guard startY < endY else { return }
        for py in startY..<endY {
            frameBuffer[py * Self.gameWidth + x] = color
        }
    }

    private func fillEllipseInBuffer(centerX: Int, centerY: Int, radiusX: Int, radiusY: Int, color: UInt32, alpha: Int) {
        guard radiusX > 0, radiusY > 0, alpha > 0 else { return }
        let clampedAlpha = max(0, min(255, alpha))
        for y in -radiusY...radiusY {
            let normalizedY = Double(y * y) / Double(radiusY * radiusY)
            guard normalizedY <= 1 else { continue }
            let span = Int(Double(radiusX) * sqrt(1 - normalizedY))
            for x in -span...span {
                blendPixel(x: centerX + x, y: centerY + y, color: color, alpha: clampedAlpha)
            }
        }
    }

    private func fillTriangleFanPeak(baseX: Int, baseY: Int, width: Int, height: Int, colorTop: UInt32, colorBottom: UInt32) {
        guard height > 0 else { return }
        for row in 0...height {
            let t = Double(row) / Double(max(1, height))
            let span = Int(Double(width) * (1 - t))
            let color = blend(colorTop, with: colorBottom, alpha: Int(t * 255))
            drawHLineInBuffer(x: baseX - span, y: baseY - row, width: span * 2 + 1, color: color)
        }
    }

    private func drawDiamondMarker(centerX: Int, centerY: Int, radius: Int, color: UInt32) {
        for row in -radius...radius {
            let span = radius - abs(row)
            drawHLineInBuffer(x: centerX - span, y: centerY + row, width: span * 2 + 1, color: color)
        }
        drawHLineInBuffer(x: centerX - radius, y: centerY, width: radius * 2 + 1, color: darken(color, by: 40))
    }

    private func drawSceneShadow(centerX: Int, centerY: Int, radiusX: Int, radiusY: Int, intensity: Int) {
        let rotation = cameraAngleRadians() - (.pi / 5)
        let offsetX = Int(cos(rotation) * 4)
        let offsetY = Int(sin(rotation) * 2)
        fillEllipseInBuffer(
            centerX: centerX + offsetX,
            centerY: centerY + offsetY,
            radiusX: radiusX,
            radiusY: radiusY,
            color: 0xFF000000,
            alpha: intensity
        )
    }

    private func drawSceneVignette() {
        for y in 0..<Self.gameHeight {
            let edgeY = min(y, Self.gameHeight - 1 - y)
            for x in 0..<Self.gameWidth {
                let edgeX = min(x, Self.gameWidth - 1 - x)
                let edge = min(edgeX, edgeY)
                if edge < 10 {
                    let alpha = (10 - edge) * 8
                    let index = y * Self.gameWidth + x
                    frameBuffer[index] = blend(frameBuffer[index], with: 0xFF000000, alpha: alpha)
                }
            }
        }
    }

    private func setPixelInBuffer(x: Int, y: Int, color: UInt32) {
        guard x >= 0 && x < Self.gameWidth && y >= 0 && y < Self.gameHeight else { return }
        frameBuffer[y * Self.gameWidth + x] = color
    }

    private func blendPixel(x: Int, y: Int, color: UInt32, alpha: Int) {
        guard x >= 0 && x < Self.gameWidth && y >= 0 && y < Self.gameHeight else { return }
        let index = y * Self.gameWidth + x
        frameBuffer[index] = blend(frameBuffer[index], with: color, alpha: alpha)
    }

    // MARK: - Coordinate Utilities

    private func worldToScreen(x: Int, y: Int) -> (Int, Int) {
        let tileWidth = Double(fallbackTileWidth())
        let tileHeight = Double(fallbackTileHeight())
        let dx = Double(x - cameraX)
        let dy = Double(y - cameraY)
        let rotation = cameraAngleRadians()
        let elevationOffset = Double(terrainElevation(worldX: x, worldY: y)) / 7.0

        let rotatedX = dx * cos(rotation) - dy * sin(rotation)
        let rotatedY = dx * sin(rotation) + dy * cos(rotation)

        let screenX = Int(rotatedX * tileWidth) + Self.gameWidth / 2
        let screenY = Int(rotatedY * tileHeight - elevationOffset) + horizonLineY()
        return (screenX, screenY)
    }

    private func horizonLineY() -> Int {
        Self.gameHeight / 2 + 30
    }

    private func fallbackTileWidth() -> Int {
        max(22, min(42, 18 + cameraZoom / 9))
    }

    private func fallbackTileHeight() -> Int {
        max(14, fallbackTileWidth() * 5 / 9)
    }

    private func cameraAngleRadians() -> Double {
        Double(cameraRotation) / 256.0 * (.pi * 2.0)
    }

    private func terrainElevation(worldX: Int, worldY: Int) -> Int {
        guard let tile = landscapeArchive.tile(
            atWorldX: worldX,
            worldY: worldY,
            plane: worldPlane,
            centeredAt: cameraX,
            centerY: cameraY
        ) else {
            return 0
        }
        return tile.groundElevation * 3
    }

    // MARK: - Color Utilities

    private static func rgbStatic(r: Int, g: Int, b: Int) -> UInt32 {
        let cr = UInt32(max(0, min(255, r)))
        let cg = UInt32(max(0, min(255, g)))
        let cb = UInt32(max(0, min(255, b)))
        return 0xFF000000 | (cr << 16) | (cg << 8) | cb
    }

    private func appearanceColor(_ index: Int?, palette: [UInt32], default defaultColor: UInt32) -> UInt32 {
        guard let index else { return defaultColor }
        return palette[posMod(index, palette.count)]
    }

    private func blend(_ base: UInt32, with overlay: UInt32, alpha: Int) -> UInt32 {
        let a = max(0, min(255, alpha))
        let bR = Int((base >> 16) & 0xFF)
        let bG = Int((base >> 8) & 0xFF)
        let bB = Int(base & 0xFF)
        let oR = Int((overlay >> 16) & 0xFF)
        let oG = Int((overlay >> 8) & 0xFF)
        let oB = Int(overlay & 0xFF)
        let r = UInt32((bR * (255 - a) + oR * a) / 255)
        let g = UInt32((bG * (255 - a) + oG * a) / 255)
        let b = UInt32((bB * (255 - a) + oB * a) / 255)
        return 0xFF000000 | (r << 16) | (g << 8) | b
    }

    private func darken(_ color: UInt32, by amount: Int) -> UInt32 {
        blend(color, with: 0xFF000000, alpha: amount)
    }

    private func lighten(_ color: UInt32, by amount: Int) -> UInt32 {
        blend(color, with: 0xFFFFFFFF, alpha: amount)
    }

    private func npcColor(_ npcId: Int) -> UInt32 {
        let colors: [UInt32] = [
            0xFF6496C8, 0xFFC86464, 0xFF64C864, 0xFFC8C864,
            0xFFC896C8, 0xFF64C8C8, 0xFFC89664, 0xFF9664C8
        ]
        return colors[posMod(npcId, colors.count)]
    }

    private func posMod(_ a: Int, _ b: Int) -> Int {
        let m = a % b
        return m < 0 ? m + b : m
    }
}
