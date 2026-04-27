import Foundation

// Dispatches incoming RSC server packets to world state updates.
// Matches PacketHandler.java handlePacket1() / handlePacket2().
@MainActor
final class RSCPacketHandler {
    weak var worldState: RSCWorldState?

    func handlePacket(opcode: UInt8, payload: Data) {
        guard let ws = worldState else { return }
        print("[Packet] Received opcode \(opcode) (\(payload.count) bytes)")
        let buf = ByteBuffer()
        buf.setReadData(payload)

        switch opcode {
        case 131: // SEND_MESSAGE — Java showMessage()
            // Format: INT crown, BYTE msgType (enum), BYTE formatFlags, STRING message
            // If formatFlags & 1: STRING sender, STRING clan
            // If formatFlags & 2: STRING colour
            let crown131 = buf.get32()
            let msgTypeRaw = buf.getUnsignedByte()
            let formatFlags = buf.getUnsignedByte()
            let message131 = buf.getString()
            var sender131 = ""
            var clan131 = ""
            if (formatFlags & 1) != 0 {
                sender131 = buf.getString()
                clan131 = buf.getString()
            }
            if (formatFlags & 2) != 0 {
                let _ = buf.getString() // colour code
            }
            // Message types: 1=chat, 2=private, 3=quest/NPC, 4=trade, 5=system, 6=global
            let prefix: String
            let isPriv: Bool
            switch msgTypeRaw {
            case 1: prefix = sender131.isEmpty ? "[Chat]" : sender131; isPriv = false
            case 2: prefix = sender131.isEmpty ? "[PM]" : sender131; isPriv = true
            case 3: prefix = sender131.isEmpty ? "[Quest]" : sender131; isPriv = false
            case 4: prefix = "[Trade]"; isPriv = false
            case 5, 6: prefix = "[System]"; isPriv = false
            default: prefix = sender131.isEmpty ? "[Msg]" : sender131; isPriv = false
            }
            let displayName = clan131.isEmpty ? prefix : "[\(clan131)] \(prefix)"
            ws.addChat(sender: displayName, text: message131, isPrivate: isPriv)

        case 120: // receivePrivateMsg — Java: STRING sender, STRING formerName, INT icon, STRING message
            let pmSender = buf.getString()
            let _ = buf.getString() // formerName
            let _ = buf.get32() // icon
            let pmMessage = buf.getString()
            ws.addChat(sender: pmSender, text: pmMessage, isPrivate: true)

        case 87:  // sendPrivateMessage confirmation — Java: STRING recipient, STRING message
            let pmRecipient = buf.getString()
            let pmSent = buf.getString()
            ws.addChat(sender: "To \(pmRecipient)", text: pmSent, isPrivate: true)

        case 19:  // serverConfig — setServerConfiguration()
            handleServerConfig(buf: buf, ws: ws)

        case 191: // showOtherPlayers — player position updates
            handleShowPlayers(buf: buf, ws: ws, length: payload.count)

        case 79:  // showNPCs
            handleShowNPCs(buf: buf, ws: ws, length: payload.count)

        case 25:  // loadArea — Java PacketHandler.java:1958
            // Format: SHORT playerServerIndex, SHORT worldOffsetX, SHORT worldOffsetZ, SHORT requestedPlane, SHORT m_rc
            let playerServerIndex = buf.getShort()
            let worldOffsetX = buf.getShort()
            let worldOffsetZ = buf.getShort()
            let requestedPlane = buf.getShort()
            let planeMultiplier = buf.getShort()
            ws.playerServerIndex = playerServerIndex
            ws.worldOffsetX = worldOffsetX
            ws.worldOffsetZ = worldOffsetZ - (requestedPlane * planeMultiplier)
            ws.requestedPlane = requestedPlane
            ws.loadingArea = true
            print("[Packet] loadArea: serverIdx=\(playerServerIndex) offset=(\(worldOffsetX),\(worldOffsetZ)) plane=\(requestedPlane) mult=\(planeMultiplier)")

        case 53:  // updateInventory
            handleUpdateInventory(buf: buf, ws: ws)

        case 254: // updateEquipment (SEND_EQUIPMENT)
            handleUpdateEquipment(buf: buf, ws: ws)

        case 153: // updateEquipmentStats (armour, weapon aim/power, magic, prayer)
            handleUpdateEquipmentStats(buf: buf, ws: ws)

        case 156: // loadStats + experience
            handleLoadStats(buf: buf, ws: ws)

        case 33:  // UPDATE_XP (individual skill XP only)
            let skill33 = buf.getUnsignedByte()
            let xp33 = Int(UInt32(bitPattern: Int32(buf.get32()))) / 4
            ws.updateExperience(skill: skill33, xp: xp33)

        case 159: // UPDATE_STAT — Java updateExperience(): BYTE skill, BYTE current, BYTE base, INT xp
            // Note: Java opcode 159 calls updateExperience() which reads current+base+xp
            if buf.bytesRemaining >= 7 {
                let skill159 = buf.getUnsignedByte()
                let current159 = buf.getUnsignedByte()
                let base159 = buf.getUnsignedByte()
                let xp159 = Int(UInt32(bitPattern: Int32(buf.get32()))) / 4
                if skill159 < ws.skills.count {
                    let oldXP = ws.skills[skill159].experience
                    ws.skills[skill159].current = current159
                    ws.skills[skill159].base = base159
                    ws.skills[skill159].experience = xp159
                    let gained = xp159 - oldXP
                    if gained > 0 {
                        ws.addXPDrop(skillId: skill159, amount: gained)
                    }
                }
            }

        case 129: // SEND_COMBAT_STYLE
            ws.combatStyle = buf.getByte()

        case 99:  // showGroundItems
            handleShowGroundItems(buf: buf, ws: ws)

        case 5:   // QUEST_STATUS — Java updateQuestStage()
            // Format: BYTE updateType, then:
            //   type 0: BYTE count, per quest: INT id, INT stage, STRING name
            //   type 1: INT questId, INT stage
            if buf.bytesRemaining > 0 {
                let updateType = buf.getByte()
                if updateType == 0 {
                    let questCount = buf.getByte()
                    for _ in 0..<questCount {
                        guard buf.bytesRemaining >= 9 else { break }
                        let qid = buf.get32()
                        let stage = buf.get32()
                        let name = buf.getString()
                        if let idx = ws.quests.firstIndex(where: { $0.id == qid }) {
                            ws.quests[idx] = (id: qid, name: name, stage: stage)
                        } else {
                            ws.quests.append((id: qid, name: name, stage: stage))
                        }
                    }
                    print("[Packet] Quests loaded: \(ws.quests.count)")
                } else if updateType == 1 {
                    guard buf.bytesRemaining >= 8 else { break }
                    let qid = buf.get32()
                    let stage = buf.get32()
                    if let idx = ws.quests.firstIndex(where: { $0.id == qid }) {
                        ws.quests[idx] = (id: ws.quests[idx].id, name: ws.quests[idx].name, stage: stage)
                    }
                }
            }

        case 92:  // showTradeDialog — Java: SHORT serverIndex
            let tradePartnerIdx = buf.getShort()
            // Find partner name from players list
            if let partner = ws.players.first(where: { $0.id == tradePartnerIdx }) {
                ws.tradePartnerName = partner.name
            } else {
                ws.tradePartnerName = "Player"
            }
            ws.tradeOpen = true
            ws.tradeMyOffer = []
            ws.tradeTheirOffer = []
            ws.tradeAccepted = false
            ws.tradePartnerAccepted = false
            print("[Packet] Trade opened with \(ws.tradePartnerName)")

        case 97:  // updateTradeDialog — their items, then our items
            handleUpdateTradeDialog(buf: buf, ws: ws)

        case 128: // TRADE_CONFIRMED — close trade screens
            ws.tradeOpen = false
            ws.tradeConfirmOpen = false

        case 20:  // confirmTrade — show confirmation screen
            handleTradeConfirm(buf: buf, ws: ws)

        case 162: // tradeRecipientDecision — BYTE accepted
            ws.tradePartnerAccepted = buf.getUnsignedByte() == 1

        case 15:  // tradeSelfDecision — BYTE accepted
            ws.tradeAccepted = buf.getByte() == 1

        case 149: // sendConnectionMessage — friend login/logout
            let friendName = buf.getString()
            let _ = buf.getString() // formerName
            let onlineStatus = buf.getUnsignedByte()
            let isOnline = (onlineStatus & 4) != 0
            var world149: String? = nil
            if isOnline { world149 = buf.getString() }
            // Update friend in list
            if let idx = ws.friendsList.firstIndex(where: { $0.name == friendName }) {
                ws.friendsList[idx] = (name: friendName, online: isOnline)
            } else {
                ws.friendsList.append((name: friendName, online: isOnline))
            }
            let statusText = isOnline ? "logged in" : "logged out"
            ws.addChat(sender: "[Friend]", text: "\(friendName) has \(statusText)")

        case 240: // GAME_SETTINGS — updateOptionsMenuSettings
            // Just skip the settings bytes for now
            while buf.bytesRemaining > 0 { let _ = buf.getUnsignedByte() }

        case 83:  // DISPLAY_DEATH_SCREEN
            ws.isDead = true
            ws.exitCombat()

        case 114: // SET_FATIGUE
            ws.fatigue = buf.getShort()

        case 149: // connectionMessage (login/logout notice)
            let name = buf.getString()
            let loggedIn = buf.getByte() != 0
            ws.addChat(sender: "[System]", text: "\(name) has \(loggedIn ? "logged in" : "logged out").")

        case 42:  // showBank
            handleShowBank(buf: buf, ws: ws)

        case 101: // showShop
            handleShowShop(buf: buf, ws: ws)

        case 245: // showOptionsMenu (NPC dialogue options)
            handleShowOptionsMenu(buf: buf, ws: ws)

        case 204: // playSound — Java PacketHandler.playSound() / soundPlayer.playSoundFile()
            let soundName = buf.getString()
            SoundManager.shared.play(name: soundName)

        case 118: // killAnnouncement
            let text = buf.getString()
            ws.addChat(sender: "[Kill]", text: text)

        case 222: // showServerMsg
            let text = buf.getString()
            ws.addChat(sender: "[Server]", text: text)

        case 4:   // closeConnection
            ws.exitCombat()

        case 183: // cantLogout
            ws.addChat(sender: "[System]", text: "You can't logout right now.")

        case 182: // SHOW_WELCOME — welcome dialog after login
            ws.addChat(sender: "[System]", text: "Welcome to \(ws.serverName)")

        case 234: // UPDATE_PLAYERS — player appearance/chat/combat updates
            handleUpdatePlayers(buf: buf, ws: ws)

        case 240: // GAME_SETTINGS
            break // Game options

        case 206: // SET_PRAYERS
            break // Prayer data

        case 211: // UPDATE_ENTITIES — ground item/object/wall counts
            break // Entity counts

        case 48:  // SCENERY_HANDLER — game objects
            handleShowGameObjects(buf: buf, ws: ws)

        case 91:  // BOUNDARY_HANDLER — wall objects
            handleShowWalls(buf: buf, ws: ws)

        case 165: // CLOSE_CONNECTION
            break

        case 111: // COMPLETED_TUTORIAL
            break

        case 84:  // WAKE_UP
            ws.isSleeping = false
            ws.sleepStatusText = ""

        case 51:  // PRIVACY_SETTINGS
            break

        case 52:  // UPDATE_SYSTEM_UPDATE_TIMER
            break

        case 59:  // SHOW_APPEARANCE_CHANGE — character creation screen
            ws.showAppearanceChange = true
            print("[Packet] Character creation screen requested")

        case 90:  // SET_INVENTORY_SLOT — Java updateInventoryItem()
            // Format: SHORT slot, SHORT itemID, BYTE equipped, INT amount (if stackable)
            if buf.bytesRemaining >= 3 {
                let slot90 = buf.getShort()
                var itemID90 = buf.getShort()
                let equipped90 = (itemID90 / 32768) != 0
                itemID90 &= 32767
                let amount90 = buf.bytesRemaining >= 4 ? buf.get32() : 1
                if slot90 < ws.inventory.count {
                    ws.inventory[slot90].itemId = itemID90
                    ws.inventory[slot90].equipped = equipped90
                    ws.inventory[slot90].amount = amount90
                } else {
                    // Append new slot
                    ws.inventory.append(RSCInventoryItem(id: slot90, itemId: itemID90, amount: amount90, equipped: equipped90))
                }
            }

        case 123: // REMOVE_INVENTORY_SLOT — Java removeItem()
            if buf.bytesRemaining >= 1 {
                let slot123 = buf.getUnsignedByte()
                if slot123 < ws.inventory.count {
                    ws.inventory.remove(at: slot123)
                    // Re-index remaining items
                    for i in 0..<ws.inventory.count {
                        ws.inventory[i] = RSCInventoryItem(id: i, itemId: ws.inventory[i].itemId,
                                                            amount: ws.inventory[i].amount, equipped: ws.inventory[i].equipped)
                    }
                }
            }

        case 109: // SET_IGNORE — Java updateIgnoreList()
            // Format: BYTE count, then per entry: 4x STRING (name, formerName, arg0, arg1)
            let ignoreCount = buf.getUnsignedByte()
            var ignores: [String] = []
            for _ in 0..<ignoreCount {
                let name = buf.getString()
                let _ = buf.getString() // formerName
                let _ = buf.getString() // arg0
                let _ = buf.getString() // arg1
                ignores.append(name)
            }
            ws.ignoreList = ignores

        case 203: // CLOSE_BANK
            ws.bankOpen = false

        case 137: // EXIT_SHOP
            ws.shopOpen = false

        case 194: // INCORRECT_SLEEPWORD
            ws.sleepStatusText = "Incorrect - Please wait..."

        case 244: // SET_FATIGUE_SLEEPING
            if buf.bytesRemaining >= 2 {
                ws.sleepFatigue = buf.getShort()
            }

        case 252: // DISABLE_OPTION_MENU
            ws.dialogueOpen = false
            ws.dialogueOptions = []

        case 213: // NO_OP_WHILE_WAITING_FOR_NEW_APPEARANCE
            break

        case 255: // updateEquipmentSlot
            break // Equipment slot update — handled by opcode 254 full update

        case 249: // updateBank — individual bank slot update
            if buf.bytesRemaining >= 6 {
                let slot249 = buf.getShort()
                let itemId249 = buf.getShort()
                let amount249 = buf.get32()
                if slot249 < ws.bankItems.count {
                    ws.bankItems[slot249] = (id: itemId249, amount: amount249)
                }
            }

        case 97:  // updateTradeDialog — trade items update
            // Items being offered in trade
            let tradeItemCount = buf.getUnsignedByte()
            var theirItems: [(id: Int, amount: Int)] = []
            for _ in 0..<tradeItemCount {
                let tid = buf.getShort()
                let tamt = buf.get32()
                theirItems.append((id: tid, amount: tamt))
            }
            ws.tradeTheirOffer = theirItems

        case 104: // updateNPCAppearances — NPC chat/damage/projectile updates
            handleNPCAppearances(buf: buf, ws: ws)

        case 117: // showSleepScreen — server sends captcha image data
            ws.isSleeping = true
            ws.sleepFatigue = ws.fatigue
            ws.sleepStatusText = "Enter the word to wake up"
            // The packet contains captcha image bytes — we skip them since we can't render the captcha
            // The player needs to type the word shown on screen (on PC client this shows a distorted image)

        case 15:  // tradeSelfDecision
            let _ = buf.getByte() // accepted flag

        case 20:  // confirmTrade — show trade confirmation
            break

        case 176: // beginDuelOptions — opens duel stake window
            let duelPartnerIdx = buf.getShort()
            if let partner = ws.players.first(where: { $0.id == duelPartnerIdx }) {
                ws.duelOpponentName = partner.name
            }
            ws.duelOpen = true
            ws.duelAccepted = false
            ws.duelOpponentAccepted = false
            ws.duelSettings = [false, false, false, false]
            ws.duelMyStake = []
            ws.duelTheirStake = []

        case 172: // showDuelConfirmDialog — confirmation screen
            ws.duelOpen = false
            ws.duelConfirmOpen = true
            ws.duelOpponentName = buf.getString()
            // Their stake
            let duelTheirCount = buf.getUnsignedByte()
            var duelTheirItems: [(id: Int, amount: Int)] = []
            for _ in 0..<duelTheirCount {
                let did = buf.getShort()
                let _ = buf.getByte() // noted
                let damt = buf.get32()
                duelTheirItems.append((id: did, amount: damt))
            }
            ws.duelTheirStake = duelTheirItems
            // My stake
            let duelMyCount = buf.getUnsignedByte()
            var duelMyItems: [(id: Int, amount: Int)] = []
            for _ in 0..<duelMyCount {
                let did = buf.getShort()
                let _ = buf.getByte() // noted
                let damt = buf.get32()
                duelMyItems.append((id: did, amount: damt))
            }
            ws.duelMyStake = duelMyItems
            // Settings
            ws.duelSettings[0] = buf.getUnsignedByte() == 1
            ws.duelSettings[1] = buf.getUnsignedByte() == 1
            ws.duelSettings[2] = buf.getUnsignedByte() == 1
            ws.duelSettings[3] = buf.getUnsignedByte() == 1

        case 225: // closeDuelDialog
            ws.duelOpen = false
            ws.duelConfirmOpen = false

        case 30:  // toggleDuelSetting — 4 bytes for retreat/magic/prayer/weapons
            ws.duelSettings[0] = buf.getUnsignedByte() == 1
            ws.duelSettings[1] = buf.getUnsignedByte() == 1
            ws.duelSettings[2] = buf.getUnsignedByte() == 1
            ws.duelSettings[3] = buf.getUnsignedByte() == 1
            ws.duelAccepted = false
            ws.duelOpponentAccepted = false

        case 210: // duelDecision — our accept status
            ws.duelAccepted = buf.getByte() == 1

        case 253: // duelOpponentDecision
            ws.duelOpponentAccepted = buf.getUnsignedByte() == 1

        case 89:  // showServerMessageDialogTwo
            let msg89 = buf.getString()
            ws.addChat(sender: "[Server]", text: msg89)

        case 88:  // createNPC — NPC spawn notification
            break // NPC creation data

        case 112: // updateClan
            break // Clan data

        case 116: // updateParty
            break // Party data

        case 36:  // drawTeleportBubbles
            break // Visual effect

        case 71:  // friend list init — same format as 149, handled by those updates
            break

        case 206: // togglePrayer — BYTE per prayer (enabled/disabled)
            var prayerIdx = 0
            while buf.bytesRemaining > 0 {
                let enabled = buf.getByte() == 1
                _ = enabled // Prayer state could be tracked here
                prayerIdx += 1
            }

        case 88:  // createNPC — dynamic NPC definition from server
            // SHORT id, STRING name, STRING desc, BYTE cmdLen, [STRING cmd],
            // 4x BYTE stats, BYTE attackable, BYTE spriteCount, spriteCount*INT sprites, 4*INT colours...
            // Just skip all data — we have NPC defs from JSON
            while buf.bytesRemaining > 0 { let _ = buf.getUnsignedByte() }

        case 249: // updateBank — individual slot update
            if buf.bytesRemaining >= 7 {
                let slot = buf.getUnsignedByte()
                let itemId = buf.getShort()
                let amount = buf.get32()
                if slot < ws.bankItems.count {
                    ws.bankItems[slot] = (id: itemId, amount: amount)
                }
            }

        case 147: // updateExperienceCounter — XP gained notification
            if buf.bytesRemaining >= 5 {
                let skill = buf.getUnsignedByte()
                let xp = buf.get32()
                // Could show XP drop notification
                _ = skill; _ = xp
            }

        // Remaining opcodes — skip their data to keep things clean
        case 7, 16, 21, 23, 28, 29, 32, 34, 37, 39, 49, 50, 54, 55,
             94, 95, 98, 113, 115, 119, 132, 133, 134, 135, 136, 140, 144,
             148, 150, 157, 224, 232, 237, 244, 246, 250:
            break

        default:
            print("[Packet] Unhandled opcode \(opcode) (\(payload.count) bytes)")
            break
        }
    }

    // MARK: - Packet parsers (matching PacketHandler.java methods)

    private func handleServerConfig(buf: ByteBuffer, ws: RSCWorldState) {
        ws.serverName = buf.getString()
        ws.serverWelcomeMessage = buf.getString()
        ws.playerCount = buf.getShort()
        ws.playerMax = buf.getShort()
        ws.isMembersWorld = buf.getByte() != 0
    }

    // Port of PacketHandler.java showOtherPlayers() — bit-packed player position sync
    // Reference: PacketHandler.java:1339-1435
    private func handleShowPlayers(buf: ByteBuffer, ws: RSCWorldState, length: Int) {
        buf.startBitAccess()

        // Local player absolute position (11-bit X, 13-bit Z, 4-bit direction)
        let localX = buf.getBitMask(11)
        let localZ = buf.getBitMask(13)
        let _ = buf.getBitMask(4) // direction

        ws.localPlayerX = localX
        ws.localPlayerY = localZ

        // Number of known players to update
        let knownCount = buf.getBitMask(8)

        // Process known player updates (movement/animation)
        for _ in 0..<knownCount {
            let needsUpdate = buf.getBitMask(1)
            if needsUpdate != 0 {
                let updateType = buf.getBitMask(1)
                if updateType != 0 {
                    let needsNextSprite = buf.getBitMask(2)
                    if needsNextSprite == 3 { continue }
                    let _ = buf.getBitMask(2)
                } else {
                    let _ = buf.getBitMask(3)
                }
            }
        }

        // New players entering view — 24+ bits remaining per player
        // Format: 11-bit serverIndex, 6-bit signed relX, 6-bit signed relZ, 4-bit direction
        var newPlayers: [RSCPlayer] = []
        while length * 8 > buf.bitHead + 24 {
            let serverIndex = buf.getBitMask(11)
            var relX = buf.getBitMask(6)
            if relX > 31 { relX -= 64 }
            var relZ = buf.getBitMask(6)
            if relZ > 31 { relZ -= 64 }
            let _ = buf.getBitMask(4) // direction

            let playerTileX = localX + relX
            let playerTileZ = localZ + relZ
            newPlayers.append(RSCPlayer(id: serverIndex, x: playerTileX, y: playerTileZ,
                                        name: "Player \(serverIndex)", moving: false, combatLevel: 0))
        }

        buf.endBitAccess()

        // Update world state with nearby players
        ws.players = newPlayers

        if knownCount > 0 || newPlayers.count > 0 {
            print("[PLY] len=\(length) known=\(knownCount) new=\(newPlayers.count) localPos=(\(localX),\(localZ))")
        }
    }

    // Port of PacketHandler.java showNPCs() — bit-packed NPC position sync
    // Reference: PacketHandler.java:1798-1873
    // Maintains persistent NPC list: existing NPCs updated, new ones added, removed ones dropped
    private func handleShowNPCs(buf: ByteBuffer, ws: RSCWorldState, length: Int) {
        buf.startBitAccess()

        let existingCount = buf.getBitMask(8)

        // Keep first existingCount NPCs from current list (they're still in view)
        var keptNPCs = Array(ws.npcs.prefix(existingCount))

        // Process movement/animation updates for existing NPCs
        // Java: for (int i = 0; i < existingCount; i++) { npc = npcArray[i]; ... }
        let directions: [(Int, Int)] = [(0,0), (0,-1), (0,1), (-1,0), (1,0), (-1,-1), (1,-1), (-1,1), (1,1)]
        for i in 0..<existingCount {
            let needsUpdate = buf.getBitMask(1)
            if needsUpdate != 0 {
                let updateType = buf.getBitMask(1)
                if updateType != 0 {
                    let needsNextSprite = buf.getBitMask(2)
                    if needsNextSprite == 3 {
                        // NPC removed — mark for removal (set id to -1)
                        if i < keptNPCs.count { keptNPCs[i].id = -1 }
                        continue
                    }
                    let _ = buf.getBitMask(2) // nextSprite
                } else {
                    let dir = buf.getBitMask(3) // movement direction 0-8
                    // Update position based on direction
                    if i < keptNPCs.count && dir < directions.count {
                        keptNPCs[i].x += directions[dir].0
                        keptNPCs[i].y += directions[dir].1
                    }
                }
            }
        }

        // Remove NPCs marked for removal
        keptNPCs.removeAll { $0.id == -1 }

        // New NPCs entering view — 34+ bits remaining per NPC
        let localX = ws.localPlayerX
        let localZ = ws.localPlayerY
        var newCount = 0

        while length * 8 > buf.bitHead + 34 {
            let serverIndex = buf.getBitMask(12)
            var relX = buf.getBitMask(6)
            if relX > 31 { relX -= 64 }
            var relZ = buf.getBitMask(6)
            if relZ > 31 { relZ -= 64 }
            let _ = buf.getBitMask(4) // direction
            let npcTypeId = buf.getBitMask(10)

            let npcTileX = localX + relX
            let npcTileZ = localZ + relZ
            keptNPCs.append(RSCNPC(id: serverIndex, x: npcTileX, y: npcTileZ,
                                    npcId: npcTypeId, name: NPCNames.name(for: npcTypeId)))
            newCount += 1
        }

        buf.endBitAccess()
        ws.npcs = keptNPCs

        if existingCount > 0 || newCount > 0 {
            print("[NPC] len=\(length) existing=\(existingCount) new=\(newCount) total=\(keptNPCs.count)")
        }
    }

    // Port of PacketHandler.java updateInventory() — opcode 53
    // Format: BYTE count, then per item: SHORT itemID, BYTE equipped, BYTE noted, [INT amount if stackable]
    private func handleUpdateInventory(buf: ByteBuffer, ws: RSCWorldState) {
        let count = buf.getUnsignedByte()
        var items: [RSCInventoryItem] = []
        for i in 0..<count {
            let itemId = buf.getShort()
            let equipped = buf.getByte() != 0
            let noted = buf.getByte() == 1
            // For stackable items, read 4-byte amount; otherwise amount=1
            // We don't have item defs to check stackability, so check if there are enough bytes
            // Simple heuristic: if remaining bytes > expected for rest of items, read amount
            let amount = 1  // TODO: read get32() for stackable items when item defs available
            items.append(RSCInventoryItem(id: i, itemId: itemId, amount: amount, equipped: equipped))
        }
        ws.inventory = items
        print("[Packet] Inventory: \(count) items")
    }

    private func handleUpdateEquipment(buf: ByteBuffer, ws: RSCWorldState) {
        // Equipment format varies — for now just track that equipment changed
        print("[Packet] Equipment update (\(buf.bytesRemaining) bytes)")
    }

    // Port of PacketHandler.java updateEquipmentStats() — opcode 153
    // Format: 5 unsigned bytes (armour, weapon aim, weapon power, magic, prayer)
    private func handleUpdateEquipmentStats(buf: ByteBuffer, ws: RSCWorldState) {
        ws.equipmentStats.armourPoints = buf.getUnsignedByte()
        ws.equipmentStats.weaponAimPoints = buf.getUnsignedByte()
        ws.equipmentStats.weaponPowerPoints = buf.getUnsignedByte()
        ws.equipmentStats.magicPoints = buf.getUnsignedByte()
        ws.equipmentStats.prayerPoints = buf.getUnsignedByte()
        print("[Packet] Equip stats: arm=\(ws.equipmentStats.armourPoints) aim=\(ws.equipmentStats.weaponAimPoints) pow=\(ws.equipmentStats.weaponPowerPoints)")
    }

    // Port of PacketHandler.java drawGroundItems() — opcode 99
    // Java reads: if getUnsignedByte() != 255, then backs up 1 byte and reads SHORT itemID
    // The first byte is actually the high byte of the short — if it's 255, it means "end"
    // Simplified: while bytesRemaining >= 4, peek first byte; if 255 break; else read SHORT + 2 BYTEs
    private func handleShowGroundItems(buf: ByteBuffer, ws: RSCWorldState) {
        while buf.bytesRemaining >= 4 {
            // Peek at first byte to check for end marker
            let hi = buf.getUnsignedByte()
            if hi == 255 { break }

            // Read the rest of the short (hi was the high byte)
            let lo = buf.getUnsignedByte()
            var itemID = (hi << 8) | lo
            let relX = buf.getByte()
            let relZ = buf.getByte()

            let worldX = ws.localPlayerX + relX
            let worldZ = ws.localPlayerY + relZ

            if (itemID & 32768) != 0 {
                // Remove item — high bit set means already visible, remove it
                itemID &= 32767
                ws.groundItems.removeAll { $0.x == worldX && $0.y == worldZ && $0.itemId == itemID }
            } else {
                // Add new ground item
                ws.groundItems.append(RSCGroundItem(x: worldX, y: worldZ, itemId: itemID, amount: 1))
            }
        }
        print("[Packet] Ground items: \(ws.groundItems.count) total")
    }

    // Port of PacketHandler.java showBank() — opcode 42
    // Format: SHORT itemCount, SHORT maxItems, then per item: SHORT id, INT amount
    private func handleShowBank(buf: ByteBuffer, ws: RSCWorldState) {
        let itemCount = buf.getShort()
        let maxItems = buf.getShort()
        var items: [(id: Int, amount: Int)] = []
        for _ in 0..<itemCount {
            let id = buf.getShort()
            let amount = buf.get32()
            items.append((id: id, amount: amount))
        }
        ws.bankItems = items
        ws.bankOpen = true
        ws.bankMaxItems = maxItems
        print("[Packet] Bank opened: \(itemCount) items, max \(maxItems)")
    }

    // Port of PacketHandler.java showShopDialog() — opcode 101
    // Format: BYTE count, BYTE shopType, BYTE sellMod, BYTE buyMod, BYTE priceMult,
    //         then per item: SHORT id, SHORT stock, SHORT price
    private func handleShowShop(buf: ByteBuffer, ws: RSCWorldState) {
        let count = buf.getUnsignedByte()
        let shopType = buf.getByte()
        let sellMod = buf.getUnsignedByte()
        let buyMod = buf.getUnsignedByte()
        let priceMult = buf.getUnsignedByte()
        var items: [(id: Int, stock: Int, price: Int)] = []
        for _ in 0..<count {
            let id = buf.getShort()
            let stock = buf.getShort()
            let price = buf.getShort()
            items.append((id: id, stock: stock, price: price))
        }
        ws.shopItems = items
        ws.shopOpen = true
        ws.shopType = shopType
        print("[Packet] Shop opened: \(count) items, type=\(shopType)")
    }

    // Port of PacketHandler.java showOptionsMenu() — opcode 245
    // Format: BYTE count, count * STRING option
    private func handleShowOptionsMenu(buf: ByteBuffer, ws: RSCWorldState) {
        let count = buf.getUnsignedByte()
        var options: [String] = []
        for _ in 0..<count {
            options.append(buf.getString())
        }
        ws.dialogueOptions = options
        ws.dialogueOpen = true
        print("[Packet] Dialogue: \(count) options")
        // Also show in chat for accessibility
        for (i, opt) in options.enumerated() {
            ws.addChat(sender: "[Option \(i + 1)]", text: opt)
        }
    }

    // Port of PacketHandler.java loadStats() + loadExperience() + loadQuestPoints() — opcode 156
    // Format: 18x BYTE currentLevel, 18x BYTE baseLevel, 18x INT experience, BYTE questPoints
    private func handleLoadStats(buf: ByteBuffer, ws: RSCWorldState) {
        let skillCount = 18  // RSC has 18 skills

        // Read all current levels first
        var currentLevels = [Int]()
        for _ in 0..<skillCount {
            currentLevels.append(buf.getUnsignedByte())
        }

        // Then all base levels
        var baseLevels = [Int]()
        for _ in 0..<skillCount {
            baseLevels.append(buf.getUnsignedByte())
        }

        // Then experience for each skill (4 bytes each, divided by 4)
        var experience = [Int]()
        for _ in 0..<skillCount {
            let rawXP = buf.get32()
            experience.append(Int(UInt32(bitPattern: Int32(rawXP))) / 4)
        }

        // Quest points
        let questPoints = buf.bytesRemaining > 0 ? buf.getUnsignedByte() : 0

        // Build skills array
        var skills = [RSCSkill]()
        for i in 0..<skillCount {
            skills.append(RSCSkill(id: i, current: currentLevels[i], base: baseLevels[i], experience: experience[i]))
        }
        ws.skills = skills
        print("[Packet] Stats loaded: \(skillCount) skills, questPoints=\(questPoints)")
    }

    // MARK: - Player Updates (opcode 234)
    // Port of PacketHandler.java drawNearbyPlayers()
    // Format: SHORT playerCount, then per player: SHORT serverIndex, BYTE updateType, type-specific data
    private func handleUpdatePlayers(buf: ByteBuffer, ws: RSCWorldState) {
        let playerCount = buf.getShort()
        for _ in 0..<playerCount {
            guard buf.bytesRemaining >= 3 else { break }
            let serverIndex = buf.getShort()
            let updateType = buf.getUnsignedByte()

            switch updateType {
            case 0: // Bubble item
                let _ = buf.getShort() // itemType

            case 1, 7: // Chat message
                let _ = buf.get32() // crownID
                if updateType == 7 {
                    let _ = buf.getUnsignedByte() // muted
                    let _ = buf.getUnsignedByte() // onTutorial
                }
                let message = buf.getString()
                // Find player and set their chat
                if let idx = ws.players.firstIndex(where: { $0.id == serverIndex }) {
                    ws.addChat(sender: ws.players[idx].name, text: message)
                }

            case 6: // Quest message
                let message = buf.getString()
                if serverIndex == ws.playerServerIndex {
                    ws.addChat(sender: "[Quest]", text: message)
                }

            case 2: // Combat damage
                let damage = buf.getUnsignedByte()
                let curhp = buf.getUnsignedByte()
                let maxhp = buf.getUnsignedByte()
                if serverIndex == ws.playerServerIndex {
                    // Update local player HP
                    if let hpIdx = ws.skills.firstIndex(where: { $0.id == 3 }) {
                        ws.skills[hpIdx].current = curhp
                        ws.skills[hpIdx].base = maxhp
                    }
                    ws.lastDamageReceived = damage
                }

            case 3, 4: // Projectile
                let _ = buf.getShort() // sprite
                let _ = buf.getShort() // shooterServerIndex

            case 5: // Full appearance update
                let playerName = buf.getString()
                let itemCount = buf.getUnsignedByte()
                for _ in 0..<itemCount { let _ = buf.getShort() } // equipment sprites
                let hairColour = buf.getUnsignedByte()
                let topColour = buf.getUnsignedByte()
                let bottomColour = buf.getUnsignedByte()
                let skinColour = buf.getUnsignedByte()
                let combatLevel = buf.getUnsignedByte()
                let skulled = buf.getUnsignedByte()
                let hasClan = buf.getByte()
                if hasClan == 1 { let _ = buf.getString() } // clanTag
                let _ = buf.getByte() // isInvisible
                let _ = buf.getByte() // isInvulnerable
                let _ = buf.getByte() // groupID
                let _ = buf.get32() // icon

                // Update or add player
                if let idx = ws.players.firstIndex(where: { $0.id == serverIndex }) {
                    ws.players[idx].name = playerName
                    ws.players[idx].combatLevel = combatLevel
                } else if serverIndex != ws.playerServerIndex {
                    // This is appearance-only, position comes from opcode 191
                    // We'll match by server index later
                }
                if serverIndex == ws.playerServerIndex {
                    ws.localPlayerName = playerName
                }

            case 8: // Heal
                let _ = buf.getUnsignedByte() // heal amount
                let curhp8 = buf.getUnsignedByte()
                let maxhp8 = buf.getUnsignedByte()
                if serverIndex == ws.playerServerIndex {
                    if let hpIdx = ws.skills.firstIndex(where: { $0.id == 3 }) {
                        ws.skills[hpIdx].current = curhp8
                        ws.skills[hpIdx].base = maxhp8
                    }
                }

            case 9: // HP update (no damage/heal value)
                let curhp9 = buf.getUnsignedByte()
                let maxhp9 = buf.getUnsignedByte()
                if serverIndex == ws.playerServerIndex {
                    if let hpIdx = ws.skills.firstIndex(where: { $0.id == 3 }) {
                        ws.skills[hpIdx].current = curhp9
                        ws.skills[hpIdx].base = maxhp9
                    }
                }

            default:
                break
            }
        }
    }

    // MARK: - Game Objects (opcode 48)
    // Port of PacketHandler.java showGameObjects()
    // Format: while data remains: BYTE marker, if != 255: SHORT id, BYTE relX, BYTE relZ, BYTE direction
    //         if 255: BYTE relX>>3, BYTE relZ>>3 (batch remove)
    private func handleShowGameObjects(buf: ByteBuffer, ws: RSCWorldState) {
        while buf.bytesRemaining > 0 {
            let marker = buf.getUnsignedByte()
            if marker == 255 {
                // Batch remove — remove objects in a region
                guard buf.bytesRemaining >= 2 else { break }
                let regionRelX = ws.localPlayerX + buf.getByte()
                let regionRelZ = ws.localPlayerY + buf.getByte()
                let rx = regionRelX >> 3
                let rz = regionRelZ >> 3
                ws.gameObjects.removeAll { ($0.x >> 3) == rx && ($0.y >> 3) == rz }
            } else {
                // Add/update object — marker was first byte of SHORT id
                guard buf.bytesRemaining >= 4 else { break }
                let idLo = buf.getUnsignedByte()
                let objectId = (marker << 8) | idLo
                let relX = buf.getByte()
                let relZ = buf.getByte()
                let direction = buf.getByte()
                let worldX = ws.localPlayerX + relX
                let worldZ = ws.localPlayerY + relZ

                // Remove existing object at this position
                ws.gameObjects.removeAll { $0.x == worldX && $0.y == worldZ }

                // Add new object (60000 = remove only, don't re-add)
                if objectId != 60000 {
                    ws.gameObjects.append(RSCGameObject(x: worldX, y: worldZ, objectId: objectId, direction: direction))
                }
            }
        }
        print("[Packet] Game objects: \(ws.gameObjects.count)")
    }

    // MARK: - Walls (opcode 91)
    // Port of PacketHandler.java showWalls()
    // Same format pattern as game objects
    private func handleShowWalls(buf: ByteBuffer, ws: RSCWorldState) {
        while buf.bytesRemaining > 0 {
            let marker = buf.getUnsignedByte()
            if marker == 255 {
                guard buf.bytesRemaining >= 2 else { break }
                let regionRelX = ws.localPlayerX + buf.getByte()
                let regionRelZ = ws.localPlayerY + buf.getByte()
                let rx = regionRelX >> 3
                let rz = regionRelZ >> 3
                ws.wallObjects.removeAll { ($0.x >> 3) == rx && ($0.y >> 3) == rz }
            } else {
                guard buf.bytesRemaining >= 4 else { break }
                let idLo = buf.getUnsignedByte()
                let wallId = (marker << 8) | idLo
                let relX = buf.getByte()
                let relZ = buf.getByte()
                let direction = buf.getByte()
                let worldX = ws.localPlayerX + relX
                let worldZ = ws.localPlayerY + relZ

                ws.wallObjects.removeAll { $0.x == worldX && $0.y == worldZ && $0.direction == direction }

                if wallId != 60000 {
                    ws.wallObjects.append(RSCWallObject(x: worldX, y: worldZ, wallId: wallId, direction: direction))
                }
            }
        }
        print("[Packet] Wall objects: \(ws.wallObjects.count)")
    }

    // MARK: - Trade Updates

    // opcode 97 — updateTradeDialog: their items then our items
    private func handleUpdateTradeDialog(buf: ByteBuffer, ws: RSCWorldState) {
        let theirCount = buf.getUnsignedByte()
        var theirItems: [(id: Int, amount: Int)] = []
        for _ in 0..<theirCount {
            let itemId = buf.getShort()
            let _ = buf.getByte() // noted flag
            let amount = buf.get32()
            theirItems.append((id: itemId, amount: amount))
        }
        let myCount = buf.getUnsignedByte()
        var myItems: [(id: Int, amount: Int)] = []
        for _ in 0..<myCount {
            let itemId = buf.getShort()
            let _ = buf.getByte() // noted flag
            let amount = buf.get32()
            myItems.append((id: itemId, amount: amount))
        }
        ws.tradeTheirOffer = theirItems
        ws.tradeMyOffer = myItems
        ws.tradeAccepted = false
        ws.tradePartnerAccepted = false
        print("[Packet] Trade update: my=\(myCount) items, their=\(theirCount) items")
    }

    // opcode 20 — confirmTrade: show confirmation screen
    private func handleTradeConfirm(buf: ByteBuffer, ws: RSCWorldState) {
        let partnerName = buf.getString()
        ws.tradePartnerName = partnerName
        let theirCount = buf.getUnsignedByte()
        var theirItems: [(id: Int, amount: Int)] = []
        for _ in 0..<theirCount {
            let itemId = buf.getShort()
            let _ = buf.getByte() // noted
            let amount = buf.get32()
            theirItems.append((id: itemId, amount: amount))
        }
        let myCount = buf.getUnsignedByte()
        var myItems: [(id: Int, amount: Int)] = []
        for _ in 0..<myCount {
            let itemId = buf.getShort()
            let _ = buf.getByte() // noted
            let amount = buf.get32()
            myItems.append((id: itemId, amount: amount))
        }
        ws.tradeTheirOffer = theirItems
        ws.tradeMyOffer = myItems
        ws.tradeOpen = false
        ws.tradeConfirmOpen = true
        print("[Packet] Trade confirm with \(partnerName)")
    }

    // MARK: - NPC Appearance Updates (opcode 104)
    // Port of PacketHandler.java updateNPCAppearances()
    private func handleNPCAppearances(buf: ByteBuffer, ws: RSCWorldState) {
        let count = buf.getShort()
        for _ in 0..<count {
            guard buf.bytesRemaining >= 3 else { break }
            let serverIndex = buf.getShort()
            let updateType = buf.getUnsignedByte()

            switch updateType {
            case 1: // NPC chat message
                let chatRecipient = buf.getShort()
                let message = buf.getString()
                if let idx = ws.npcs.firstIndex(where: { $0.id == serverIndex }) {
                    ws.npcs[idx].message = message
                    ws.npcs[idx].messageTimeout = 150
                    // Show in chat if directed at local player
                    if chatRecipient == ws.playerServerIndex {
                        ws.addChat(sender: ws.npcs[idx].name, text: message)
                    }
                }

            case 2: // NPC damage/health
                let damage = buf.getUnsignedByte()
                let currentHp = buf.getUnsignedByte()
                let maxHp = buf.getUnsignedByte()
                if let idx = ws.npcs.firstIndex(where: { $0.id == serverIndex }) {
                    ws.npcs[idx].damageTaken = damage
                    ws.npcs[idx].currentHp = currentHp
                    ws.npcs[idx].maxHp = maxHp
                    ws.npcs[idx].combatTimeout = 200
                }

            case 3: // Projectile (NPC attacking)
                let _ = buf.getShort() // sprite
                let _ = buf.getShort() // shooter server index

            case 4: // Projectile (player attacking NPC)
                let _ = buf.getShort() // sprite
                let _ = buf.getShort() // shooter server index

            case 5: // Skull visibility
                let _ = buf.getUnsignedByte()

            case 6: // Wield change
                let _ = buf.getUnsignedByte() // wield
                let _ = buf.getUnsignedByte() // wield2

            case 7: // Bubble item
                let _ = buf.getShort() // itemType

            default:
                break
            }
        }
    }
}
