import Foundation

/// Handles incoming packets from the server.
/// Complete implementation matching server OpcodeOut.
actor PacketHandler {
    weak var gameClient: GameClient?
    private let soundManager = SoundManager.shared

    // Server to Client opcodes (matching server OpcodeOut)
    enum Opcode: UInt8 {
        // World updates
        case playerCoords = 191
        case npcCoords = 79
        case updatePlayers = 234
        case updateNpcs = 104
        case sceneryHandler = 48
        case boundaryHandler = 91
        case groundItemHandler = 99
        case clearLocations = 211

        // Player state
        case playerStats = 156
        case playerStatEquipmentBonus = 153
        case playerStatFatigue = 114
        case playerStatFatigueAsleep = 244
        case playerStatExperience = 33
        case playerQuestList = 5
        case playerInventory = 53

        // Combat
        case playerDied = 83

        // Interface
        case showBank = 42
        case hideBank = 171
        case updateBankItem = 249
        case showShop = 101
        case hideShop = 137
        case showDialogue = 245
        case hideDialogue = 252

        // Chat
        case message = 131
        case privateMessageSent = 87
        case privateMessageReceived = 120
        case friendList = 71
        case friendUpdate = 149
        case ignoreList = 109

        // System
        case logout = 4
        case logoutDeny = 183
        case worldInfo = 25

        // Misc
        case playSound = 204
        case teleport = 145
        case showSleepScreen = 117
        case wakeUp = 84
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
        // World updates
        case .playerCoords:
            await handlePlayerCoords(&reader)
        case .npcCoords:
            await handleNpcCoords(&reader)
        case .updatePlayers:
            await handleUpdatePlayers(&reader)
        case .updateNpcs:
            await handleUpdateNpcs(&reader)
        case .sceneryHandler:
            await handleSceneryUpdate(&reader)
        case .boundaryHandler:
            await handleBoundaryUpdate(&reader)
        case .groundItemHandler:
            await handleGroundItems(&reader)
        case .clearLocations:
            await handleClearLocations()

        // Player state
        case .playerStats:
            await handlePlayerStats(&reader)
        case .playerStatEquipmentBonus:
            await handleEquipmentBonus(&reader)
        case .playerStatFatigue:
            await handleFatigue(&reader)
        case .playerStatFatigueAsleep:
            await handleFatigueAsleep(&reader)
        case .playerStatExperience:
            await handleExperience(&reader)
        case .playerQuestList:
            await handleQuestList(&reader)
        case .playerInventory:
            await handleInventory(&reader)

        // Combat
        case .playerDied:
            await handlePlayerDied()

        // Interface
        case .showBank:
            await handleShowBank(&reader)
        case .hideBank:
            await handleHideBank()
        case .updateBankItem:
            await handleUpdateBankItem(&reader)
        case .showShop:
            await handleShowShop(&reader)
        case .hideShop:
            await handleHideShop()
        case .showDialogue:
            await handleShowDialogue(&reader)
        case .hideDialogue:
            await handleHideDialogue()

        // Chat
        case .message:
            await handleChatMessage(&reader)
        case .privateMessageSent:
            await handlePrivateMessageSent(&reader)
        case .privateMessageReceived:
            await handlePrivateMessageReceived(&reader)
        case .friendList:
            await handleFriendList(&reader)
        case .friendUpdate:
            await handleFriendUpdate(&reader)
        case .ignoreList:
            await handleIgnoreList(&reader)

        // System
        case .logout:
            await handleLogout()
        case .logoutDeny:
            await handleLogoutDeny()
        case .worldInfo:
            await handleWorldInfo(&reader)

        // Misc
        case .playSound:
            await handlePlaySound(&reader)
        case .teleport:
            await handleTeleport(&reader)
        case .showSleepScreen:
            await handleShowSleepScreen(&reader)
        case .wakeUp:
            await handleWakeUp()
        }
    }

    // MARK: - World Updates

    private func handlePlayerCoords(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        // Read local player update first
        guard let localX = reader.readShort(),
              let localY = reader.readShort() else { return }

        await gameClient.updateLocalPlayerPosition(x: Int(localX), y: Int(localY))

        // Read other players
        while reader.hasMoreData {
            guard let serverIndex = reader.readShort(),
                  let x = reader.readShort(),
                  let y = reader.readShort(),
                  let direction = reader.readByte() else { break }

            await gameClient.updatePlayerPosition(
                index: Int(serverIndex),
                x: Int(x),
                y: Int(y),
                direction: Int(direction)
            )
        }
    }

    private func handleNpcCoords(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        while reader.hasMoreData {
            guard let serverIndex = reader.readShort(),
                  let npcId = reader.readShort(),
                  let x = reader.readShort(),
                  let y = reader.readShort(),
                  let direction = reader.readByte() else { break }

            await gameClient.updateNpc(
                index: Int(serverIndex),
                npcId: Int(npcId),
                x: Int(x),
                y: Int(y),
                direction: Int(direction)
            )
        }
    }

    private func handleUpdatePlayers(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let count = reader.readShort() else { return }

        for _ in 0..<count {
            guard let serverIndex = reader.readShort(),
                  let appearanceId = reader.readShort(),
                  let combatLevel = reader.readByte() else { continue }

            // Read appearance data
            let headSprite = reader.readByte() ?? 0
            let bodySprite = reader.readByte() ?? 0
            let legSprite = reader.readByte() ?? 0
            let hairColor = reader.readByte() ?? 0
            let topColor = reader.readByte() ?? 0
            let bottomColor = reader.readByte() ?? 0
            let skinColor = reader.readByte() ?? 0

            await gameClient.updatePlayerAppearance(
                index: Int(serverIndex),
                combatLevel: Int(combatLevel),
                appearance: PlayerAppearance(
                    headSprite: Int(headSprite),
                    bodySprite: Int(bodySprite),
                    legSprite: Int(legSprite),
                    hairColor: Int(hairColor),
                    topColor: Int(topColor),
                    bottomColor: Int(bottomColor),
                    skinColor: Int(skinColor)
                )
            )
        }
    }

    private func handleUpdateNpcs(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        while reader.hasMoreData {
            guard let serverIndex = reader.readShort(),
                  let animation = reader.readByte() else { break }

            await gameClient.updateNpcAnimation(
                index: Int(serverIndex),
                animation: Int(animation)
            )
        }
    }

    private func handleSceneryUpdate(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        while reader.hasMoreData {
            guard let objectId = reader.readShort(),
                  let x = reader.readShort(),
                  let y = reader.readShort() else { break }

            if objectId == 60000 {
                await gameClient.removeSceneryObject(x: Int(x), y: Int(y))
            } else {
                await gameClient.addSceneryObject(id: Int(objectId), x: Int(x), y: Int(y))
            }
        }
    }

    private func handleBoundaryUpdate(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        while reader.hasMoreData {
            guard let boundaryId = reader.readShort(),
                  let x = reader.readShort(),
                  let y = reader.readShort(),
                  let direction = reader.readByte() else { break }

            if boundaryId == 60000 {
                await gameClient.removeBoundary(x: Int(x), y: Int(y))
            } else {
                await gameClient.addBoundary(
                    id: Int(boundaryId),
                    x: Int(x),
                    y: Int(y),
                    direction: Int(direction)
                )
            }
        }
    }

    private func handleGroundItems(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        while reader.hasMoreData {
            guard let itemId = reader.readShort(),
                  let x = reader.readShort(),
                  let y = reader.readShort() else { break }

            if itemId == 60000 {
                await gameClient.clearGroundItemsAt(x: Int(x), y: Int(y))
            } else {
                await gameClient.addGroundItem(itemId: Int(itemId), x: Int(x), y: Int(y))
            }
        }
    }

    private func handleClearLocations() async {
        await gameClient?.clearAllLocations()
    }

    // MARK: - Player State

    private func handlePlayerStats(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        // Read all 19 skills (including Runecraft)
        for skillId in 0..<19 {
            guard let current = reader.readByte(),
                  let max = reader.readByte(),
                  let experience = reader.readInt() else { return }

            await gameClient.updateSkill(
                skillId: skillId,
                current: Int(current),
                max: Int(max),
                experience: Int(experience)
            )
        }

        // Read quest points
        if let questPoints = reader.readShort() {
            await gameClient.setQuestPoints(Int(questPoints))
        }
    }

    private func handleEquipmentBonus(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let armour = reader.readByte(),
              let weaponAim = reader.readByte(),
              let weaponPower = reader.readByte(),
              let magic = reader.readByte(),
              let prayer = reader.readByte() else { return }

        await gameClient.setEquipmentBonuses(
            armour: Int(armour),
            weaponAim: Int(weaponAim),
            weaponPower: Int(weaponPower),
            magic: Int(magic),
            prayer: Int(prayer)
        )
    }

    private func handleFatigue(_ reader: inout PacketReader) async {
        guard let fatigue = reader.readShort() else { return }
        await gameClient?.setFatigue(Int(fatigue))
    }

    private func handleFatigueAsleep(_ reader: inout PacketReader) async {
        guard let fatigue = reader.readShort() else { return }
        await gameClient?.setFatigueAsleep(Int(fatigue))
    }

    private func handleExperience(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let skillId = reader.readByte(),
              let experience = reader.readInt() else { return }

        await gameClient.updateExperience(skillId: Int(skillId), experience: Int(experience))

        // Play level up sound if level increased
        await soundManager.play(.levelUp)
    }

    private func handleQuestList(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        var quests: [Int: Int] = [:]
        while reader.hasMoreData {
            guard let questId = reader.readByte(),
                  let status = reader.readByte() else { break }
            quests[Int(questId)] = Int(status)
        }

        await gameClient.setQuestList(quests)
    }

    private func handleInventory(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let count = reader.readByte() else { return }

        var items: [(id: Int, amount: Int, equipped: Bool)] = []
        for _ in 0..<count {
            guard let itemIdWithFlag = reader.readShort() else { continue }

            let equipped = (itemIdWithFlag & 0x8000) != 0
            let itemId = Int(itemIdWithFlag & 0x7FFF)

            var amount = 1
            if let stackAmount = reader.readInt(), stackAmount > 0 {
                amount = Int(stackAmount)
            }

            items.append((id: itemId, amount: amount, equipped: equipped))
        }

        await gameClient.setFullInventory(items)
    }

    // MARK: - Combat

    private func handlePlayerDied() async {
        await soundManager.play(.death)
        await gameClient?.onPlayerDied()
    }

    // MARK: - Interface

    private func handleShowBank(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let itemCount = reader.readByte(),
              let maxBankSize = reader.readShort() else { return }

        var bankItems: [(id: Int, amount: Int)] = []
        for _ in 0..<itemCount {
            guard let itemId = reader.readShort(),
                  let amount = reader.readInt() else { continue }
            bankItems.append((id: Int(itemId), amount: Int(amount)))
        }

        await gameClient.showBank(items: bankItems, maxSize: Int(maxBankSize))
    }

    private func handleHideBank() async {
        await gameClient?.hideBank()
    }

    private func handleUpdateBankItem(_ reader: inout PacketReader) async {
        guard let slot = reader.readByte(),
              let itemId = reader.readShort(),
              let amount = reader.readInt() else { return }

        await gameClient?.updateBankSlot(
            slot: Int(slot),
            itemId: Int(itemId),
            amount: Int(amount)
        )
    }

    private func handleShowShop(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let itemCount = reader.readByte(),
              let generalStore = reader.readByte(),
              let sellMultiplier = reader.readByte(),
              let buyMultiplier = reader.readByte() else { return }

        var shopItems: [(id: Int, amount: Int, price: Int)] = []
        for _ in 0..<itemCount {
            guard let itemId = reader.readShort(),
                  let amount = reader.readShort(),
                  let price = reader.readInt() else { continue }
            shopItems.append((id: Int(itemId), amount: Int(amount), price: Int(price)))
        }

        await gameClient.showShop(
            items: shopItems,
            isGeneralStore: generalStore == 1,
            sellMultiplier: Int(sellMultiplier),
            buyMultiplier: Int(buyMultiplier)
        )
    }

    private func handleHideShop() async {
        await gameClient?.hideShop()
    }

    private func handleShowDialogue(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let optionCount = reader.readByte() else { return }

        var options: [String] = []
        for _ in 0..<optionCount {
            if let option = reader.readString() {
                options.append(option)
            }
        }

        await gameClient.showDialogue(options: options)
    }

    private func handleHideDialogue() async {
        await gameClient?.hideDialogue()
    }

    // MARK: - Chat

    private func handleChatMessage(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }
        guard let message = reader.readString() else { return }

        if message.contains(":") {
            let parts = message.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                await gameClient.addChatMessage(
                    sender: String(parts[0]),
                    message: String(parts[1]).trimmingCharacters(in: .whitespaces)
                )
                return
            }
        }

        await gameClient.addServerMessage(message)
    }

    private func handlePrivateMessageSent(_ reader: inout PacketReader) async {
        guard let recipient = reader.readString(),
              let message = reader.readString() else { return }

        await gameClient?.onPrivateMessageSent(to: recipient, message: message)
    }

    private func handlePrivateMessageReceived(_ reader: inout PacketReader) async {
        guard let sender = reader.readString(),
              let message = reader.readString() else { return }

        await soundManager.play(.privateMessage)
        await gameClient?.onPrivateMessageReceived(from: sender, message: message)
    }

    private func handleFriendList(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }
        guard let count = reader.readByte() else { return }

        var friends: [(name: String, online: Bool)] = []
        for _ in 0..<count {
            guard let name = reader.readString(),
                  let worldId = reader.readByte() else { continue }
            friends.append((name: name, online: worldId > 0))
        }

        await gameClient.setFriendList(friends)
    }

    private func handleFriendUpdate(_ reader: inout PacketReader) async {
        guard let name = reader.readString(),
              let worldId = reader.readByte() else { return }

        await gameClient?.updateFriendStatus(name: name, online: worldId > 0)
    }

    private func handleIgnoreList(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }
        guard let count = reader.readByte() else { return }

        var ignoreList: [String] = []
        for _ in 0..<count {
            if let name = reader.readString() {
                ignoreList.append(name)
            }
        }

        await gameClient.setIgnoreList(ignoreList)
    }

    // MARK: - System

    private func handleLogout() async {
        await gameClient?.onLogout()
    }

    private func handleLogoutDeny() async {
        await gameClient?.onLogoutDenied()
    }

    private func handleWorldInfo(_ reader: inout PacketReader) async {
        guard let responseCode = reader.readByte() else { return }

        switch responseCode {
        case 0:
            let playerIndex = reader.readShort() ?? 0
            let isMembersWorld = (reader.readByte() ?? 0) == 1
            await gameClient?.onLoginSuccess(
                playerIndex: Int(playerIndex),
                membersWorld: isMembersWorld
            )
        case 1:
            await gameClient?.onLoginFailed("Invalid username or password")
        case 2:
            await gameClient?.onLoginFailed("Account is already logged in")
        case 3:
            await gameClient?.onLoginFailed("Client version outdated")
        case 4:
            await gameClient?.onLoginFailed("Server is full")
        case 5:
            await gameClient?.onLoginFailed("Login server offline")
        case 6:
            await gameClient?.onLoginFailed("Account is banned")
        case 7:
            await gameClient?.onLoginFailed("Account is locked")
        default:
            await gameClient?.onLoginFailed("Unknown error: \(responseCode)")
        }
    }

    // MARK: - Misc

    private func handlePlaySound(_ reader: inout PacketReader) async {
        guard let soundId = reader.readShort() else { return }
        await soundManager.playById(Int(soundId))
    }

    private func handleTeleport(_ reader: inout PacketReader) async {
        guard let x = reader.readShort(),
              let y = reader.readShort() else { return }

        await soundManager.play(.teleport)
        await gameClient?.onTeleport(x: Int(x), y: Int(y))
    }

    private func handleShowSleepScreen(_ reader: inout PacketReader) async {
        guard let imageLength = reader.readShort() else { return }

        var imageData = Data()
        for _ in 0..<imageLength {
            if let byte = reader.readByte() {
                imageData.append(byte)
            }
        }

        await gameClient?.showSleepScreen(captchaImage: imageData)
    }

    private func handleWakeUp() async {
        await gameClient?.hideSleepScreen()
    }
}

// MARK: - Packet Reader Extension

extension PacketReader {
    var hasMoreData: Bool {
        return position < data.count
    }
}
