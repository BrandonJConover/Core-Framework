import Foundation

/// Main game client that manages game state.
/// Complete implementation matching server protocol.
@MainActor
final class GameClient: ObservableObject {
    // Game dimensions (matches RSC)
    static let gameWidth = 512
    static let gameHeight = 334

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

    // Camera
    @Published var cameraX: Int = 0
    @Published var cameraY: Int = 0
    @Published var cameraRotation: Int = 128
    @Published var cameraZoom: Int = 128

    // UI State
    @Published var showingMenu: Bool = false
    @Published var menuOptions: [String] = []
    @Published var menuPosition: CGPoint = .zero
    @Published var currentTab: Int = 0
    @Published var errorMessage: String?
    @Published var isMembersWorld: Bool = false

    // Network
    private let networkClient: NetworkClient
    private var packetHandler: PacketHandler?

    // Frame buffer for rendering
    var frameBuffer: [UInt32]

    init(networkClient: NetworkClient) {
        self.networkClient = networkClient
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
        builder.writeShort(1) // Client version
        builder.writeString(username)
        builder.writeString(password)
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

        let worldX = screenToWorldX(x)
        let worldY = screenToWorldY(y)

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
        let worldX = screenToWorldX(x)
        let worldY = screenToWorldY(y)

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
        cameraRotation = (cameraRotation + Int(deltaX * 0.5)) & 255
    }

    func handlePinch(scale: Float) {
        cameraZoom = max(64, min(255, Int(Float(cameraZoom) * scale)))
    }

    // MARK: - Coordinate Conversion

    private func screenToWorldX(_ screenX: Int) -> Int {
        cameraX + (screenX - Self.gameWidth / 2) / 32
    }

    private func screenToWorldY(_ screenY: Int) -> Int {
        cameraY + (screenY - Self.gameHeight / 2) / 32
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
        try await networkClient.send(builder.build(opcode: 16))
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
        builder.writeString(message)
        try await networkClient.send(builder.build(opcode: 216))
    }

    func logout() async throws {
        try await networkClient.send(PacketBuilder().build(opcode: 1))
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
    /// RSC terrain color palette (256 colors in 4 segments, matching Java World.java).
    static let terrainPalette: [UInt32] = {
        var palette = [UInt32](repeating: 0, count: 256)
        for i in 0..<64 {
            // Segment 0: Snow/water blues (0-63)
            palette[i] = rgbStatic(
                r: Int(255 - Double(i) * 4.0),
                g: Int(255 - Double(i) * 1.75),
                b: 255
            )
        }
        for i in 0..<64 {
            // Segment 1: Grass greens (64-127)
            palette[64 + i] = rgbStatic(
                r: Int(Double(i) * 3.0),
                g: Int(144 + Double(i) * 1.5),
                b: Int(Double(i) * 2.0)
            )
        }
        for i in 0..<64 {
            // Segment 2: Brown/dirt (128-191)
            palette[128 + i] = rgbStatic(
                r: Int(192 - Double(i) * 1.5),
                g: Int(144 - Double(i) * 1.5),
                b: Int(96 - Double(i) * 1.0)
            )
        }
        for i in 0..<64 {
            // Segment 3: Dark brown/olive (192-255)
            palette[192 + i] = rgbStatic(
                r: Int(96 - Double(i) * 1.0),
                g: Int(96 + Double(i) * 1.0),
                b: Int(32 + Double(i) * 0.5)
            )
        }
        return palette
    }()

    private static func rgbStatic(r: Int, g: Int, b: Int) -> UInt32 {
        let cr = UInt32(max(0, min(255, r)))
        let cg = UInt32(max(0, min(255, g)))
        let cb = UInt32(max(0, min(255, b)))
        return 0xFF000000 | (cr << 16) | (cg << 8) | cb
    }

    /// Renders the current game frame to the frameBuffer.
    func renderFrame() {
        // Clear to black
        frameBuffer = Array(repeating: 0xFF000000, count: Self.gameWidth * Self.gameHeight)

        // Draw RSC-style sky gradient
        drawSkyGradient()

        // Draw terrain
        drawTerrain()

        // Draw entities (scenery, boundaries, ground items, NPCs, players)
        drawEntities()
    }

    // MARK: - Sky

    private func drawSkyGradient() {
        let skyHeight = Self.gameHeight / 3
        for y in 0..<skyHeight {
            let t = Double(y) / Double(skyHeight)
            let r = UInt32(40 + t * 60)
            let g = UInt32(80 + t * 80)
            let b = UInt32(160 + t * 60)
            let color = 0xFF000000 | (r << 16) | (g << 8) | b
            let rowStart = y * Self.gameWidth
            for x in 0..<Self.gameWidth {
                frameBuffer[rowStart + x] = color
            }
        }
    }

    // MARK: - Terrain

    private func drawTerrain() {
        let tileSize = 32
        let skyHeight = Self.gameHeight / 3
        let tilesX = Self.gameWidth / tileSize + 2
        let tilesY = (Self.gameHeight - skyHeight) / tileSize + 2

        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                let worldTileX = cameraX - tilesX / 2 + tx
                let worldTileY = cameraY - tilesY / 2 + ty

                let screenX = tx * tileSize - (cameraX * tileSize % tileSize)
                let screenY = skyHeight + ty * tileSize - (cameraY * tileSize % tileSize)

                // Procedural terrain color using RSC palette
                let hash = posMod(worldTileX * 7 + worldTileY * 13, 256)
                let paletteIndex = posMod(64 + hash % 64, 256) // Grass segment
                let color = Self.terrainPalette[paletteIndex]

                fillRectInBuffer(x: screenX, y: screenY, width: tileSize, height: tileSize, color: color)

                // Grid lines for tile boundaries (subtle)
                let darkColor = blend(color, with: 0xFF000000, alpha: 30)
                if screenX >= 0 && screenX < Self.gameWidth && screenY >= 0 && screenY < Self.gameHeight {
                    drawHLineInBuffer(x: screenX, y: screenY, width: tileSize, color: darkColor)
                    drawVLineInBuffer(x: screenX, y: screenY, height: tileSize, color: darkColor)
                }
            }
        }
    }

    // MARK: - Entities

    private func drawEntities() {
        let spriteManager = SpriteManager.shared

        // Draw scenery objects
        for obj in sceneryObjects {
            let (sx, sy) = worldToScreen(x: obj.x, y: obj.y)
            if let sprite = spriteManager.getObjectSprite(objectId: obj.objectId) {
                drawSpriteToBuffer(sprite, at: sx - sprite.width / 2, y: sy - sprite.height)
            } else {
                drawTreeShape(x: sx, y: sy, objectId: obj.objectId)
            }
        }

        // Draw boundaries
        for boundary in boundaries {
            let (sx, sy) = worldToScreen(x: boundary.x, y: boundary.y)
            drawBoundaryShape(x: sx, y: sy, direction: boundary.direction)
        }

        // Draw ground items
        for item in groundItems {
            let (sx, sy) = worldToScreen(x: item.x, y: item.y)
            if let sprite = spriteManager.getItemSprite(itemId: item.itemId) {
                drawSpriteToBuffer(sprite, at: sx - sprite.width / 2, y: sy - sprite.height / 2)
            } else {
                drawItemShape(x: sx, y: sy, itemId: item.itemId)
            }
        }

        // Draw NPCs
        for (_, npc) in npcs {
            let (sx, sy) = worldToScreen(x: npc.x, y: npc.y)
            if let sprite = spriteManager.getNpcSprite(npcId: npc.npcId, direction: npc.direction, animation: npc.animation) {
                drawSpriteToBuffer(sprite, at: sx - sprite.width / 2, y: sy - sprite.height)
            } else {
                drawHumanoid(x: sx, y: sy, color: npcColor(npc.npcId))
            }
        }

        // Draw other players
        for (_, player) in players {
            let (sx, sy) = worldToScreen(x: player.x, y: player.y)
            if let sprite = spriteManager.getPlayerSprite(
                appearance: player.appearance,
                direction: player.direction,
                isWalking: player.animation != 0,
                animationFrame: player.animation
            ) {
                drawSpriteToBuffer(sprite, at: sx - sprite.width / 2, y: sy - sprite.height)
            } else {
                drawHumanoid(x: sx, y: sy, color: 0xFFC89664)
            }
        }

        // Draw local player
        if let player = localPlayer {
            let (sx, sy) = worldToScreen(x: player.x, y: player.y)
            if let sprite = spriteManager.getPlayerSprite(
                appearance: player.appearance,
                direction: player.direction,
                isWalking: player.animation != 0,
                animationFrame: player.animation
            ) {
                drawSpriteToBuffer(sprite, at: sx - sprite.width / 2, y: sy - sprite.height)
            } else {
                drawHumanoid(x: sx, y: sy, color: 0xFFC89664)
            }
        }
    }

    // MARK: - Fallback Shape Renderers

    private func drawHumanoid(x: Int, y: Int, color: UInt32) {
        let headColor = blend(color, with: 0xFFFFFFFF, alpha: 40)
        fillRectInBuffer(x: x - 4, y: y - 48, width: 8, height: 8, color: headColor) // Head
        fillRectInBuffer(x: x - 6, y: y - 40, width: 12, height: 16, color: color)   // Body
        fillRectInBuffer(x: x - 4, y: y - 24, width: 8, height: 16, color: blend(color, with: 0xFF000000, alpha: 30)) // Legs
        fillRectInBuffer(x: x - 10, y: y - 38, width: 4, height: 12, color: color)   // Left arm
        fillRectInBuffer(x: x + 6, y: y - 38, width: 4, height: 12, color: color)    // Right arm
    }

    private func drawTreeShape(x: Int, y: Int, objectId: Int) {
        let trunkColor: UInt32 = 0xFF6B4226
        let leafColor: UInt32 = 0xFF228B22
        fillRectInBuffer(x: x - 3, y: y - 32, width: 6, height: 24, color: trunkColor)
        fillRectInBuffer(x: x - 12, y: y - 48, width: 24, height: 20, color: leafColor)
        fillRectInBuffer(x: x - 8, y: y - 56, width: 16, height: 12, color: blend(leafColor, with: 0xFFFFFFFF, alpha: 20))
    }

    private func drawBoundaryShape(x: Int, y: Int, direction: Int) {
        let wallColor: UInt32 = 0xFF808080
        if direction == 0 || direction == 2 {
            // Horizontal wall
            fillRectInBuffer(x: x - 16, y: y - 4, width: 32, height: 4, color: wallColor)
        } else {
            // Vertical wall
            fillRectInBuffer(x: x - 2, y: y - 16, width: 4, height: 32, color: wallColor)
        }
    }

    private func drawItemShape(x: Int, y: Int, itemId: Int) {
        let colors: [UInt32] = [0xFFFFD700, 0xFFC0C0C0, 0xFFCD7F32, 0xFF00FF00, 0xFFFF4444]
        let color = colors[posMod(itemId, colors.count)]
        fillRectInBuffer(x: x - 6, y: y - 6, width: 12, height: 12, color: color)
        // Inner highlight
        fillRectInBuffer(x: x - 4, y: y - 4, width: 8, height: 8, color: blend(color, with: 0xFFFFFFFF, alpha: 60))
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
                    // Alpha blend
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
        for py in max(0, y)..<min(y + height, Self.gameHeight) {
            let rowStart = py * Self.gameWidth
            for px in max(0, x)..<min(x + width, Self.gameWidth) {
                frameBuffer[rowStart + px] = color
            }
        }
    }

    private func drawHLineInBuffer(x: Int, y: Int, width: Int, color: UInt32) {
        guard y >= 0 && y < Self.gameHeight else { return }
        let rowStart = y * Self.gameWidth
        for px in max(0, x)..<min(x + width, Self.gameWidth) {
            frameBuffer[rowStart + px] = color
        }
    }

    private func drawVLineInBuffer(x: Int, y: Int, height: Int, color: UInt32) {
        guard x >= 0 && x < Self.gameWidth else { return }
        for py in max(0, y)..<min(y + height, Self.gameHeight) {
            frameBuffer[py * Self.gameWidth + x] = color
        }
    }

    // MARK: - Coordinate Utilities

    private func worldToScreen(x: Int, y: Int) -> (Int, Int) {
        let tileSize = 32
        let screenX = (x - cameraX) * tileSize + Self.gameWidth / 2
        let screenY = (y - cameraY) * tileSize + Self.gameHeight / 2 + Self.gameHeight / 3
        return (screenX, screenY)
    }

    // MARK: - Color Utilities

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
