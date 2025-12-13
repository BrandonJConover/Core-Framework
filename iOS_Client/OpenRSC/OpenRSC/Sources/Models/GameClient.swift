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
    }

    private func setupPacketHandling() async {
        await networkClient.onPacketReceived = { [weak self] packet in
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

    func removeSceneryObject(x: Int, y: Int) {
        sceneryObjects.removeAll { $0.x == x && $0.y == y }
    }

    func addBoundary(id: Int, x: Int, y: Int, direction: Int) {
        boundaries.append(Boundary(id: id, x: x, y: y, direction: direction))
    }

    func removeBoundary(x: Int, y: Int) {
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

    func removeGroundItem(itemId: Int, x: Int, y: Int) {
        groundItems.removeAll { $0.itemId == itemId && $0.x == x && $0.y == y }
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
