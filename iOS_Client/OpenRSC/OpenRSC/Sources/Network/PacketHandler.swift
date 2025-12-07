import Foundation

/// Handles incoming packets from the server.
/// Equivalent to Java's PacketHandler.
actor PacketHandler {
    weak var gameClient: GameClient?

    // Opcodes (matching server)
    enum Opcode: UInt8 {
        // Login
        case loginResponse = 0
        case logout = 4

        // Player updates
        case playerUpdate = 191
        case playerMovement = 145
        case playerAppearance = 234

        // NPC updates
        case npcUpdate = 79
        case npcMovement = 104

        // Ground items
        case groundItemAdd = 99
        case groundItemRemove = 156

        // Inventory
        case inventoryItems = 53
        case inventoryUpdate = 90

        // Equipment
        case equipmentUpdate = 177

        // Skills
        case skillUpdate = 33
        case experienceGain = 159

        // Chat
        case chatMessage = 131
        case serverMessage = 48

        // World updates
        case objectAdd = 48
        case objectRemove = 101
        case wallObjectAdd = 95
        case wallObjectRemove = 220

        // Interface
        case openShop = 101
        case closeShop = 137
        case openBank = 42
        case closeBank = 171

        // Combat
        case combatUpdate = 203
        case deathScreen = 83

        // Sound
        case playSound = 204

        // Settings
        case settings = 240
    }

    init(gameClient: GameClient) {
        self.gameClient = gameClient
    }

    /// Processes an incoming packet.
    func handle(_ packet: Packet) async {
        guard let opcode = Opcode(rawValue: packet.opcode) else {
            print("Unknown opcode: \(packet.opcode)")
            return
        }

        var reader = PacketReader(packet)

        switch opcode {
        case .loginResponse:
            await handleLoginResponse(&reader)

        case .playerUpdate:
            await handlePlayerUpdate(&reader)

        case .npcUpdate:
            await handleNpcUpdate(&reader)

        case .inventoryItems:
            await handleInventoryItems(&reader)

        case .skillUpdate:
            await handleSkillUpdate(&reader)

        case .chatMessage:
            await handleChatMessage(&reader)

        case .serverMessage:
            await handleServerMessage(&reader)

        case .groundItemAdd:
            await handleGroundItemAdd(&reader)

        case .groundItemRemove:
            await handleGroundItemRemove(&reader)

        case .playSound:
            await handlePlaySound(&reader)

        default:
            print("Unhandled opcode: \(opcode)")
        }
    }

    private func handleLoginResponse(_ reader: inout PacketReader) async {
        guard let responseCode = reader.readByte() else { return }

        switch responseCode {
        case 0:
            print("Login successful")
            await gameClient?.onLoginSuccess()
        case 1:
            await gameClient?.onLoginFailed("Invalid username or password")
        case 2:
            await gameClient?.onLoginFailed("Account is already logged in")
        case 3:
            await gameClient?.onLoginFailed("Account is banned")
        default:
            await gameClient?.onLoginFailed("Unknown error: \(responseCode)")
        }
    }

    private func handlePlayerUpdate(_ reader: inout PacketReader) async {
        // Parse player position and appearance updates
        guard let gameClient = gameClient else { return }

        // Read player count
        guard let count = reader.readShort() else { return }

        for _ in 0..<count {
            guard let serverIndex = reader.readShort(),
                  let x = reader.readShort(),
                  let y = reader.readShort() else { continue }

            await gameClient.updatePlayerPosition(
                index: Int(serverIndex),
                x: Int(x),
                y: Int(y)
            )
        }
    }

    private func handleNpcUpdate(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let count = reader.readShort() else { return }

        for _ in 0..<count {
            guard let serverIndex = reader.readShort(),
                  let npcId = reader.readShort(),
                  let x = reader.readShort(),
                  let y = reader.readShort() else { continue }

            await gameClient.updateNpc(
                index: Int(serverIndex),
                npcId: Int(npcId),
                x: Int(x),
                y: Int(y)
            )
        }
    }

    private func handleInventoryItems(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let count = reader.readByte() else { return }

        var items: [(Int, Int)] = []
        for _ in 0..<count {
            guard let itemId = reader.readShort(),
                  let amount = reader.readInt() else { continue }
            items.append((Int(itemId), Int(amount)))
        }

        await gameClient.setInventory(items)
    }

    private func handleSkillUpdate(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let skillId = reader.readByte(),
              let currentLevel = reader.readByte(),
              let maxLevel = reader.readByte(),
              let experience = reader.readInt() else { return }

        await gameClient.updateSkill(
            skillId: Int(skillId),
            current: Int(currentLevel),
            max: Int(maxLevel),
            experience: Int(experience)
        )
    }

    private func handleChatMessage(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let sender = reader.readString(),
              let message = reader.readString() else { return }

        await gameClient.addChatMessage(sender: sender, message: message)
    }

    private func handleServerMessage(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let message = reader.readString() else { return }

        await gameClient.addServerMessage(message)
    }

    private func handleGroundItemAdd(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let itemId = reader.readShort(),
              let x = reader.readShort(),
              let y = reader.readShort() else { return }

        await gameClient.addGroundItem(
            itemId: Int(itemId),
            x: Int(x),
            y: Int(y)
        )
    }

    private func handleGroundItemRemove(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let itemId = reader.readShort(),
              let x = reader.readShort(),
              let y = reader.readShort() else { return }

        await gameClient.removeGroundItem(
            itemId: Int(itemId),
            x: Int(x),
            y: Int(y)
        )
    }

    private func handlePlaySound(_ reader: inout PacketReader) async {
        guard let soundId = reader.readShort() else { return }
        // TODO: Play sound effect
        print("Play sound: \(soundId)")
    }
}
