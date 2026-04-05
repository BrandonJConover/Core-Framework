import Foundation

/// Handles incoming packets from the server.
/// Complete implementation matching server OpcodeOut for custom client protocol.
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

    /// Decodes bit-packed player coordinate updates from the server.
    /// Server format (custom client path in GameStateUpdater):
    ///   localPlayerX:      11 bits
    ///   localPlayerY:      13 bits
    ///   localPlayerSprite:  4 bits
    ///   knownPlayerCount:   8 bits
    ///   Per known player:
    ///     hasUpdate: 1 bit
    ///     if hasUpdate=1: updateType: 1 bit
    ///       type=0: direction 3 bits (moved)
    ///       type=1: read 2 bits -> if 3: remove, else read 2 more -> 4-bit sprite
    ///   New players (until end of bits):
    ///     playerIndex: 11 bits
    ///     xOffset:      6 bits (signed)
    ///     yOffset:      6 bits (signed)
    ///     sprite:       4 bits
    private func handlePlayerCoords(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        reader.startBitReading()

        guard let localX = reader.readBits(11),
              let localY = reader.readBits(13),
              let localSprite = reader.readBits(4),
              let knownPlayerCount = reader.readBits(8) else {
            reader.finishBitReading()
            return
        }

        await gameClient.updateLocalPlayerPosition(x: localX, y: localY)
        await gameClient.updateLocalPlayerSprite(localSprite)

        // Snapshot the ordered known-player list before processing updates.
        // Each sequential update corresponds to the next entity in this list.
        let knownIndices = await gameClient.localPlayerIndices
        var survivingIndices: [Int] = []

        // Process known player updates
        for i in 0..<knownPlayerCount {
            let playerIndex = i < knownIndices.count ? knownIndices[i] : -1

            guard let hasUpdate = reader.readBits(1) else { break }
            if hasUpdate == 1 {
                guard let updateType = reader.readBits(1) else { break }
                if updateType == 0 {
                    // Moved: 3-bit direction
                    guard let direction = reader.readBits(3) else { break }
                    await gameClient.knownPlayerMoved(index: playerIndex, direction: direction)
                    survivingIndices.append(playerIndex)
                } else {
                    // Not moving: read 2 bits
                    guard let subType = reader.readBits(2) else { break }
                    if subType == 3 {
                        // Remove player
                        await gameClient.knownPlayerRemoved(index: playerIndex)
                    } else {
                        // Sprite changed: subType is upper 2 bits, read 2 more for full 4-bit sprite
                        guard let lowerBits = reader.readBits(2) else { break }
                        let sprite = (subType << 2) | lowerBits
                        await gameClient.knownPlayerSpriteChanged(index: playerIndex, sprite: sprite)
                        survivingIndices.append(playerIndex)
                    }
                }
            } else {
                await gameClient.knownPlayerNoUpdate(index: playerIndex)
                survivingIndices.append(playerIndex)
            }
        }

        // Rebuild localPlayerIndices: surviving known players + new players
        await MainActor.run { gameClient.localPlayerIndices = survivingIndices }

        // Process new players until end of bit data
        while reader.hasMoreBits {
            guard let playerIndex = reader.readBits(11) else { break }
            // If playerIndex is 2047 (all 1s for 11 bits), that signals end
            if playerIndex == 2047 { break }
            guard let xOffset = reader.readSignedBits(6),
                  let yOffset = reader.readSignedBits(6),
                  let sprite = reader.readBits(4) else { break }

            await gameClient.addNewPlayer(
                index: playerIndex,
                xOffset: xOffset,
                yOffset: yOffset,
                sprite: sprite
            )
        }

        reader.finishBitReading()
    }

    /// Decodes bit-packed NPC coordinate updates from the server.
    /// Server format (custom client path):
    ///   knownNpcCount: 8 bits
    ///   Per known NPC:
    ///     hasUpdate: 1 bit
    ///     if hasUpdate=1: updateType: 1 bit
    ///       type=0: direction 3 bits (moved)
    ///       type=1: read 2 bits -> if 3: remove, else read 2 more -> 4-bit sprite
    ///   New NPCs (until end of bits):
    ///     npcIndex: 12 bits
    ///     xOffset:   6 bits (signed)
    ///     yOffset:   6 bits (signed)
    ///     sprite:    4 bits
    ///     npcId:    10 bits
    private func handleNpcCoords(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        reader.startBitReading()

        guard let knownNpcCount = reader.readBits(8) else {
            reader.finishBitReading()
            return
        }

        // Snapshot the ordered known-NPC list before processing updates.
        let knownIndices = await gameClient.localNpcIndices
        var survivingIndices: [Int] = []

        // Process known NPC updates
        for i in 0..<knownNpcCount {
            let npcIndex = i < knownIndices.count ? knownIndices[i] : -1

            guard let hasUpdate = reader.readBits(1) else { break }
            if hasUpdate == 1 {
                guard let updateType = reader.readBits(1) else { break }
                if updateType == 0 {
                    guard let direction = reader.readBits(3) else { break }
                    await gameClient.knownNpcMoved(index: npcIndex, direction: direction)
                    survivingIndices.append(npcIndex)
                } else {
                    guard let subType = reader.readBits(2) else { break }
                    if subType == 3 {
                        await gameClient.knownNpcRemoved(index: npcIndex)
                    } else {
                        guard let lowerBits = reader.readBits(2) else { break }
                        let sprite = (subType << 2) | lowerBits
                        await gameClient.knownNpcSpriteChanged(index: npcIndex, sprite: sprite)
                        survivingIndices.append(npcIndex)
                    }
                }
            } else {
                await gameClient.knownNpcNoUpdate(index: npcIndex)
                survivingIndices.append(npcIndex)
            }
        }

        // Rebuild localNpcIndices: surviving known NPCs + new NPCs
        await MainActor.run { gameClient.localNpcIndices = survivingIndices }

        // Process new NPCs until end of bit data
        while reader.hasMoreBits {
            guard let npcIndex = reader.readBits(12) else { break }
            if npcIndex == 4095 { break } // all 1s signals end
            guard let xOffset = reader.readSignedBits(6),
                  let yOffset = reader.readSignedBits(6),
                  let sprite = reader.readBits(4),
                  let npcId = reader.readBits(10) else { break }

            await gameClient.addNewNpc(
                index: npcIndex,
                xOffset: xOffset,
                yOffset: yOffset,
                sprite: sprite,
                npcId: npcId
            )
        }

        reader.finishBitReading()
    }

    /// Decodes player appearance/action updates with type-based dispatch.
    /// Server format (PayloadCustomGenerator heterogeneous stream):
    ///   short updateCount
    ///   Per update: short playerIndex, byte updateType, then type-specific data
    private func handleUpdatePlayers(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let count = reader.readShort() else { return }

        for _ in 0..<count {
            guard let playerIndex = reader.readShort(),
                  let updateType = reader.readByte() else { break }

            switch updateType {
            case 0: // Bubble (action bubble over player head)
                guard let itemId = reader.readShort() else { break }
                await gameClient.showPlayerBubble(
                    index: Int(playerIndex), itemId: Int(itemId)
                )

            case 1: // Public chat
                guard let iconSprite = reader.readInt(),
                      let message = reader.readString() else { break }
                await gameClient.playerPublicChat(
                    index: Int(playerIndex),
                    icon: Int(iconSprite),
                    message: message
                )

            case 2: // Damage
                guard let damage = reader.readByte(),
                      let curHits = reader.readByte(),
                      let maxHits = reader.readByte() else { break }
                await gameClient.playerDamage(
                    index: Int(playerIndex),
                    damage: Int(damage),
                    curHits: Int(curHits),
                    maxHits: Int(maxHits)
                )

            case 3: // Projectile -> NPC
                guard let projectileType = reader.readShort(),
                      let victimIndex = reader.readShort() else { break }
                await gameClient.playerProjectileToNpc(
                    casterIndex: Int(playerIndex),
                    projectileType: Int(projectileType),
                    victimIndex: Int(victimIndex)
                )

            case 4: // Projectile -> Player
                guard let projectileType = reader.readShort(),
                      let victimIndex = reader.readShort() else { break }
                await gameClient.playerProjectileToPlayer(
                    casterIndex: Int(playerIndex),
                    projectileType: Int(projectileType),
                    victimIndex: Int(victimIndex)
                )

            case 5: // Appearance
                guard let username = reader.readString() else { break }

                guard let equipCount = reader.readByte() else { break }
                var wornItems: [Int] = []
                for _ in 0..<equipCount {
                    guard let wornItem = reader.readShort() else { break }
                    wornItems.append(Int(wornItem))
                }

                guard let hairColor = reader.readByte(),
                      let topColor = reader.readByte(),
                      let trouserColor = reader.readByte(),
                      let skinColor = reader.readByte(),
                      let combatLevel = reader.readByte(),
                      let skullType = reader.readByte() else { break }

                guard let hasClan = reader.readByte() else { break }
                var clanTag: String? = nil
                if hasClan == 1 {
                    clanTag = reader.readString()
                }

                guard let isInvisible = reader.readByte(),
                      let isInvulnerable = reader.readByte(),
                      let groupId = reader.readByte(),
                      let icon = reader.readInt() else { break }

                await gameClient.updatePlayerAppearanceFull(
                    index: Int(playerIndex),
                    username: username,
                    wornItems: wornItems,
                    hairColor: Int(hairColor),
                    topColor: Int(topColor),
                    trouserColor: Int(trouserColor),
                    skinColor: Int(skinColor),
                    combatLevel: Int(combatLevel),
                    skullType: Int(skullType),
                    clanTag: clanTag,
                    isInvisible: isInvisible != 0,
                    isInvulnerable: isInvulnerable != 0,
                    groupId: Int(groupId),
                    icon: Int(icon)
                )

            case 6: // Quest chat (NPC talking to player)
                guard let message = reader.readString() else { break }
                await gameClient.playerQuestChat(
                    index: Int(playerIndex), message: message
                )

            case 7: // Muted/tutorial chat
                guard let isMuted = reader.readByte(),
                      let onTutorial = reader.readByte(),
                      let message = reader.readString() else { break }
                await gameClient.playerMutedChat(
                    index: Int(playerIndex),
                    isMuted: isMuted != 0,
                    onTutorial: onTutorial != 0,
                    message: message
                )

            case 9: // HP update (custom client only)
                guard let curHits = reader.readByte(),
                      let maxHits = reader.readByte() else { break }
                await gameClient.playerHpUpdate(
                    index: Int(playerIndex),
                    curHits: Int(curHits),
                    maxHits: Int(maxHits)
                )

            default:
                print("Unknown player update type: \(updateType)")
                break
            }
        }
    }

    /// Decodes NPC appearance/action updates with type-based dispatch.
    /// Server format (GameStateUpdater.updateNpcAppearances, custom client):
    ///   short updateCount
    ///   Per update: short npcIndex, byte updateType, then type-specific data
    ///     Type 1 (chat):       short recipientIndex, string message
    ///     Type 2 (damage):     byte damage, byte curHits, byte maxHits
    ///     Type 3 (proj->NPC):  short projectileType, short victimIndex
    ///     Type 4 (proj->player): short projectileType, short victimIndex
    ///     Type 5 (skull):      byte skullType
    ///     Type 6 (wield):      byte wield, byte wield2
    ///     Type 7 (bubble):     short itemId
    private func handleUpdateNpcs(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let count = reader.readShort() else { return }

        for _ in 0..<count {
            guard let npcIndex = reader.readShort(),
                  let updateType = reader.readByte() else { break }

            switch updateType {
            case 1: // Chat message
                guard let recipientIndex = reader.readShort(),
                      let message = reader.readString() else { break }
                await gameClient.npcChat(
                    index: Int(npcIndex),
                    recipientIndex: Int(Int16(bitPattern: recipientIndex)),
                    message: message
                )

            case 2: // Damage
                guard let damage = reader.readByte(),
                      let curHits = reader.readByte(),
                      let maxHits = reader.readByte() else { break }
                await gameClient.npcDamage(
                    index: Int(npcIndex),
                    damage: Int(damage),
                    curHits: Int(curHits),
                    maxHits: Int(maxHits)
                )

            case 3: // Projectile -> NPC
                guard let projectileType = reader.readShort(),
                      let victimIndex = reader.readShort() else { break }
                await gameClient.npcProjectileToNpc(
                    casterIndex: Int(npcIndex),
                    projectileType: Int(projectileType),
                    victimIndex: Int(victimIndex)
                )

            case 4: // Projectile -> Player
                guard let projectileType = reader.readShort(),
                      let victimIndex = reader.readShort() else { break }
                await gameClient.npcProjectileToPlayer(
                    casterIndex: Int(npcIndex),
                    projectileType: Int(projectileType),
                    victimIndex: Int(victimIndex)
                )

            case 5: // Skull
                guard let skullType = reader.readByte() else { break }
                await gameClient.npcSkull(
                    index: Int(npcIndex),
                    skullType: Int(skullType)
                )

            case 6: // Wield
                guard let wield = reader.readByte(),
                      let wield2 = reader.readByte() else { break }
                await gameClient.npcWield(
                    index: Int(npcIndex),
                    wield: Int(wield),
                    wield2: Int(wield2)
                )

            case 7: // Bubble (action bubble over NPC head)
                guard let itemId = reader.readShort() else { break }
                await gameClient.npcBubble(
                    index: Int(npcIndex),
                    itemId: Int(itemId)
                )

            default:
                print("Unknown NPC update type: \(updateType)")
                break
            }
        }
    }

    /// Decodes scenery object updates.
    /// Server format (PayloadCustomGenerator): short id, byte x, byte y, byte direction
    /// x/y are signed byte offsets from player position.
    private func handleSceneryUpdate(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        while reader.hasMoreData {
            guard let objectId = reader.readShort(),
                  let x = reader.readSignedByte(),
                  let y = reader.readSignedByte(),
                  let direction = reader.readByte() else { break }

            if objectId == 60000 {
                await gameClient.removeSceneryObject(
                    xOffset: Int(x), yOffset: Int(y)
                )
            } else {
                await gameClient.addSceneryObject(
                    id: Int(objectId),
                    xOffset: Int(x),
                    yOffset: Int(y),
                    direction: Int(direction)
                )
            }
        }
    }

    /// Decodes boundary/wall object updates.
    /// Server format (PayloadCustomGenerator): short id, byte x, byte y, byte direction
    /// Same as scenery — x/y are signed byte offsets.
    private func handleBoundaryUpdate(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        while reader.hasMoreData {
            guard let boundaryId = reader.readShort(),
                  let x = reader.readSignedByte(),
                  let y = reader.readSignedByte(),
                  let direction = reader.readByte() else { break }

            if boundaryId == 60000 {
                await gameClient.removeBoundary(
                    xOffset: Int(x), yOffset: Int(y)
                )
            } else {
                await gameClient.addBoundary(
                    id: Int(boundaryId),
                    xOffset: Int(x),
                    yOffset: Int(y),
                    direction: Int(direction)
                )
            }
        }
    }

    /// Decodes ground item updates.
    /// Server format (PayloadCustomGenerator):
    ///   Removal: byte 255, byte x, byte y
    ///   Item:    short id (2 bytes), byte x, byte y
    /// First byte distinguishes: 0xFF = removal (1 byte), otherwise high byte of short id.
    private func handleGroundItems(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        while reader.hasMoreData {
            guard let firstByte = reader.readByte() else { break }

            let isRemoval = firstByte == 255
            let itemId: Int
            if isRemoval {
                itemId = -1
            } else {
                guard let secondByte = reader.readByte() else { break }
                itemId = (Int(firstByte) << 8) | Int(secondByte)
            }

            guard let x = reader.readSignedByte(),
                  let y = reader.readSignedByte() else { break }

            if isRemoval {
                await gameClient.removeGroundItem(
                    xOffset: Int(x), yOffset: Int(y)
                )
            } else {
                await gameClient.addGroundItem(
                    itemId: itemId,
                    xOffset: Int(x),
                    yOffset: Int(y)
                )
            }
        }
    }

    private func handleClearLocations() async {
        await gameClient?.clearAllLocations()
    }

    // MARK: - Player State

    private func handlePlayerStats(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

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

    /// Decodes inventory.
    /// Server format (PayloadCustomGenerator, custom client):
    ///   byte count
    ///   Per item: short catalogID, byte wielded, byte noted,
    ///             conditional int amount (only written when amount > 0)
    /// The server writes amount when `isStackable || noted` (ActionSender.java:969).
    /// Without item defs client-side, we use total payload size to determine the mode:
    ///   count*8 bytes → every item has an amount (all stackable/noted)
    ///   count*4 bytes → no item has an amount (all non-stackable gear)
    ///   otherwise     → mixed; read amount only when noted != 0 (best effort)
    private func handleInventory(_ reader: inout PacketReader) async {
        guard let gameClient = gameClient else { return }

        guard let count = reader.readByte() else { return }
        let itemCount = Int(count)
        let totalItemBytes = reader.remaining

        // Determine amount mode from total payload size
        let allHaveAmounts = totalItemBytes == itemCount * 8
        let noneHaveAmounts = totalItemBytes == itemCount * 4

        var items: [(id: Int, amount: Int, equipped: Bool, noted: Bool)] = []
        for _ in 0..<itemCount {
            guard let catalogID = reader.readShort(),
                  let wielded = reader.readByte(),
                  let noted = reader.readByte() else { continue }

            var amount = 1
            let shouldReadAmount: Bool
            if allHaveAmounts {
                shouldReadAmount = true
            } else if noneHaveAmounts {
                shouldReadAmount = false
            } else {
                // Mixed inventory: read amount for noted items (always have amount).
                // Un-noted stackable items will be wrong, but avoids total desync.
                shouldReadAmount = noted != 0
            }

            if shouldReadAmount {
                if let stackAmount = reader.readInt() {
                    amount = Int(stackAmount)
                    if amount == 0 { amount = 1 }
                }
            }

            items.append((
                id: Int(catalogID),
                amount: amount,
                equipped: wielded != 0,
                noted: noted != 0
            ))
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
        return remaining > 0
    }
}
