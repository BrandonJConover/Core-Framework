import Foundation

/// Main game client that manages game state.
/// Equivalent to Java's mudclient.
@MainActor
final class GameClient: ObservableObject {
    // Game dimensions (matches RSC)
    static let gameWidth = 512
    static let gameHeight = 334

    // Published state
    @Published var localPlayer: Player?
    @Published var players: [Int: Player] = [:]
    @Published var npcs: [Int: Npc] = [:]
    @Published var groundItems: [GroundItem] = []
    @Published var inventory: [InventoryItem] = []
    @Published var skills: [Skill] = Skill.createAll()
    @Published var chatMessages: [ChatMessage] = []

    // Camera
    @Published var cameraX: Int = 0
    @Published var cameraY: Int = 0
    @Published var cameraRotation: Int = 128
    @Published var cameraZoom: Int = 128

    // UI State
    @Published var showingMenu: Bool = false
    @Published var menuOptions: [String] = []
    @Published var currentTab: Int = 0

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
        builder.writeString(username)
        builder.writeString(password)
        let packet = builder.build(opcode: 0) // Login opcode
        try await networkClient.send(packet)
    }

    func onLoginSuccess() {
        localPlayer = Player(
            index: 0,
            username: "Player",
            x: 122,
            y: 648 // Lumbridge
        )
    }

    func onLoginFailed(_ reason: String) {
        print("Login failed: \(reason)")
    }

    // MARK: - Player Updates

    func updatePlayerPosition(index: Int, x: Int, y: Int) {
        if let player = players[index] {
            player.x = x
            player.y = y
        } else if index == localPlayer?.index {
            localPlayer?.x = x
            localPlayer?.y = y
        }
    }

    // MARK: - NPC Updates

    func updateNpc(index: Int, npcId: Int, x: Int, y: Int) {
        if let npc = npcs[index] {
            npc.x = x
            npc.y = y
        } else {
            npcs[index] = Npc(index: index, npcId: npcId, x: x, y: y)
        }
    }

    // MARK: - Inventory

    func setInventory(_ items: [(Int, Int)]) {
        inventory = items.map { InventoryItem(itemId: $0.0, amount: $0.1) }
    }

    // MARK: - Skills

    func updateSkill(skillId: Int, current: Int, max: Int, experience: Int) {
        guard skillId < skills.count else { return }
        skills[skillId].currentLevel = current
        skills[skillId].maxLevel = max
        skills[skillId].experience = experience
    }

    // MARK: - Chat

    func addChatMessage(sender: String, message: String) {
        let chatMessage = ChatMessage(
            type: .player,
            sender: sender,
            message: message
        )
        chatMessages.append(chatMessage)

        // Keep only last 100 messages
        if chatMessages.count > 100 {
            chatMessages.removeFirst()
        }
    }

    func addServerMessage(_ message: String) {
        let chatMessage = ChatMessage(
            type: .server,
            sender: nil,
            message: message
        )
        chatMessages.append(chatMessage)
    }

    // MARK: - Ground Items

    func addGroundItem(itemId: Int, x: Int, y: Int) {
        groundItems.append(GroundItem(itemId: itemId, x: x, y: y))
    }

    func removeGroundItem(itemId: Int, x: Int, y: Int) {
        groundItems.removeAll { $0.itemId == itemId && $0.x == x && $0.y == y }
    }

    // MARK: - Input Handling

    func handleTap(x: Int, y: Int) {
        // Convert screen coordinates to game coordinates
        // TODO: Implement proper coordinate transformation
        print("Tap at: \(x), \(y)")
    }

    func handleLongPress(x: Int, y: Int) {
        // Show context menu
        print("Long press at: \(x), \(y)")
    }

    func handlePan(deltaX: Float, deltaY: Float) {
        // Rotate camera
        cameraRotation = (cameraRotation + Int(deltaX * 0.5)) & 255
    }

    func handlePinch(scale: Float) {
        // Zoom camera
        let newZoom = Int(Float(cameraZoom) * scale)
        cameraZoom = max(0, min(255, newZoom))
    }

    // MARK: - Actions

    func walkTo(x: Int, y: Int) async throws {
        var builder = PacketBuilder()
        builder.writeShort(UInt16(x))
        builder.writeShort(UInt16(y))
        let packet = builder.build(opcode: 187) // Walk opcode
        try await networkClient.send(packet)
    }

    func sendChat(_ message: String) async throws {
        var builder = PacketBuilder()
        builder.writeString(message)
        let packet = builder.build(opcode: 216) // Chat opcode
        try await networkClient.send(packet)
    }
}

// MARK: - Game Models

final class Player: ObservableObject, Identifiable {
    let id = UUID()
    let index: Int
    @Published var username: String
    @Published var x: Int
    @Published var y: Int
    @Published var combatLevel: Int = 3
    @Published var appearance: PlayerAppearance?

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
    var skinColor: Int = 0
}

final class Npc: ObservableObject, Identifiable {
    let id = UUID()
    let index: Int
    let npcId: Int
    @Published var x: Int
    @Published var y: Int
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
}

struct Skill: Identifiable {
    let id: Int
    let name: String
    var currentLevel: Int
    var maxLevel: Int
    var experience: Int

    static func createAll() -> [Skill] {
        let names = [
            "Attack", "Defense", "Strength", "Hits", "Ranged",
            "Prayer", "Magic", "Cooking", "Woodcutting", "Fletching",
            "Fishing", "Firemaking", "Crafting", "Smithing", "Mining",
            "Herblaw", "Agility", "Thieving", "Runecraft"
        ]
        return names.enumerated().map { index, name in
            Skill(
                id: index,
                name: name,
                currentLevel: index == 3 ? 10 : 1, // Hits starts at 10
                maxLevel: index == 3 ? 10 : 1,
                experience: 0
            )
        }
    }
}

struct ChatMessage: Identifiable {
    enum MessageType {
        case player
        case server
        case quest
        case trade
    }

    let id = UUID()
    let type: MessageType
    let sender: String?
    let message: String
    let timestamp = Date()
}
