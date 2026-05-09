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
            // Format: BYTE msgType, BYTE formatFlags, ZERO_STRING message
            // If formatFlags & 1: ZERO_STRING sender, ZERO_STRING clan
            // If formatFlags & 2: ZERO_STRING colour
            let msgTypeRaw = buf.getUnsignedByte()
            let formatFlags = buf.getUnsignedByte()
            let message131 = buf.getZeroPaddedString()
            var sender131 = ""
            var clan131 = ""
            if (formatFlags & 1) != 0 {
                sender131 = buf.getZeroPaddedString()
                clan131 = buf.getZeroPaddedString()
            }
            if (formatFlags & 2) != 0 {
                let _ = buf.getZeroPaddedString() // colour code
            }
            // Message types: 1=chat, 2=private, 3=quest/NPC, 4=trade, 5=system, 6=global
            let prefix: String
            let isPriv: Bool
            let channel: ChatChannel
            switch msgTypeRaw {
            case 1: prefix = sender131.isEmpty ? "[Chat]" : sender131; isPriv = false; channel = .chat
            case 2: prefix = sender131.isEmpty ? "[PM]" : sender131; isPriv = true; channel = .privateMsg
            case 3: prefix = sender131.isEmpty ? "[Quest]" : sender131; isPriv = false; channel = .quest
            case 4: prefix = "[Trade]"; isPriv = false; channel = .trade
            case 5, 6: prefix = "[System]"; isPriv = false; channel = .system
            default: prefix = sender131.isEmpty ? "[Msg]" : sender131; isPriv = false; channel = .chat
            }
            let displayName = clan131.isEmpty ? prefix : "[\(clan131)] \(prefix)"
            ws.addChat(sender: displayName, text: message131, isPrivate: isPriv, channel: channel)

        case 120: // receivePrivateMsg — ZERO_STRING sender/former, BYTE icon, 8-byte id, RSC string
            let pmSender = buf.getZeroPaddedString()
            let _ = buf.getZeroPaddedString() // formerName
            let _ = buf.getUnsignedByte() // icon
            if buf.bytesRemaining >= 8 { _ = buf.getBytes(8) } // message id
            let pmMessage = buf.getEncryptedString()
            ws.addChat(sender: pmSender, text: pmMessage, isPrivate: true)

        case 87:  // sendPrivateMessage confirmation — ZERO_STRING recipient, RSC string message
            let pmRecipient = buf.getZeroPaddedString()
            let pmSent = buf.getEncryptedString()
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

        case 34: // SEND_EXPERIENCE_TOGGLE — BYTE 1=frozen, 0=enabled
            if buf.bytesRemaining >= 1 {
                let frozen = buf.getUnsignedByte() == 1
                if ws.experienceFrozen != frozen {
                    ws.addChat(sender: "[System]", text: frozen ? "Experience gain is now off." : "Experience gain is now on.")
                }
                ws.experienceFrozen = frozen
            }

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

        case 132: // SEND_AUCTION_PROGRESS — custom interface/delay/repeat triplet
            if buf.bytesRemaining >= 3 {
                ws.auctionProgressInterfaceId = buf.getUnsignedByte()
                ws.auctionProgressDelay = buf.getUnsignedByte()
                ws.auctionProgressRepeats = buf.getUnsignedByte()
            }

        case 133: // SEND_FISHING_TRAWLER — custom show/update/hide interface
            handleFishingTrawler(buf: buf, ws: ws)

        case 134: // SEND_STATUS_PROGRESS_BAR
            handleStatusProgress(buf: buf, ws: ws)

        case 135: // SEND_BANK_PIN_INTERFACE
            if buf.bytesRemaining >= 1 { ws.bankPinOpen = buf.getUnsignedByte() != 0 }

        case 136: // SEND_ONLINE_LIST
            handleOnlineList(buf: buf, ws: ws)

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
            let formerName = buf.getString()
            let onlineStatus = buf.getUnsignedByte()
            let rename = (onlineStatus & 1) != 0
            let isOnline = (onlineStatus & 4) != 0
            var world149: String? = nil
            if isOnline { world149 = buf.getString() }
            // Update friend in list
            if let idx = ws.friendsList.firstIndex(where: { $0.name == friendName || (rename && $0.name == formerName) }) {
                ws.friendsList[idx] = (name: friendName, online: isOnline)
            } else if !rename {
                ws.friendsList.append((name: friendName, online: isOnline))
            }
            let statusText = isOnline ? "logged in" : "logged out"
            ws.addChat(sender: "[Friend]", text: "\(friendName) has \(statusText)")
            ws.pushFriendToast(name: friendName, online: isOnline)
            _ = world149

        case 240: // GAME_SETTINGS — updateOptionsMenuSettings
            handleOptionsMenuSettings(buf: buf, ws: ws)

        case 83:  // DISPLAY_DEATH_SCREEN
            ws.isDead = true
            ws.deathScreenTimeout = 250
            ws.exitCombat()

        case 54: // SEND_ELIXIR
            if buf.bytesRemaining >= 2 { ws.elixirTicks = buf.getShort() }

        case 114: // SET_FATIGUE
            if buf.bytesRemaining >= 2 { ws.fatigue = buf.getShort() }
            if buf.bytesRemaining >= 2 { ws.fatigueAuthentic = buf.getShort() }
            ws.runEnergy = Self.runEnergy(fromFatigue: ws.fatigue)

        case 42:  // showBank
            handleShowBank(buf: buf, ws: ws)

        case 101: // showShop
            handleShowShop(buf: buf, ws: ws)

        case 245: // showOptionsMenu (NPC dialogue options)
            handleShowOptionsMenu(buf: buf, ws: ws)

        case 204: // playSound — Java PacketHandler.playSound() / soundPlayer.playSoundFile()
            let soundName = buf.getZeroPaddedString()
            SoundManager.shared.play(name: soundName)

        case 118: // killAnnouncement — Java PacketHandler.announceKill():
            // STRING victim, STRING attacker, INT killType (0=COMBAT, 1=MAGIC, 2=RANGED).
            let victim = buf.getString()
            let attacker = buf.getString()
            let killType = buf.get32()
            let style: String
            switch killType {
            case 1: style = "with magic"
            case 2: style = "with ranged"
            default: style = "in combat"
            }
            ws.addChat(sender: "[Kill]", text: "\(attacker) defeated \(victim) \(style).", isKill: true)

        case 222: // showServerMsg — Java showServerMessageDialog(), top box
            let text = buf.getString()
            ws.serverMessageDialogText = text
            ws.serverMessageDialogTop = true
            ws.serverMessageDialogOpen = true
            ws.addChat(sender: "[Server]", text: text)

        case 224: // SEND_OPEN_RECOVERY — Java setShowRecoveryDialogue(true)
            ws.recoveryQuestionsOpen = true

        case 232: // SEND_OPEN_DETAILS — Java setShowContactDialogue(true)
            ws.contactDetailsOpen = true

        case 4:   // closeConnection
            ws.exitCombat()
            ws.connectionClosedText = "The server has ended your session."
            ws.connectionClosedOpen = true

        case 183: // cantLogout
            ws.addChat(sender: "[System]", text: "You can't logout right now.")

        case 182: // SHOW_WELCOME — welcome dialog after login
            // Java showLoginDialog (PacketHandler.java:2396): STRING lastIP,
            // SHORT daysAgo, SHORT recoveryDays. Plus a tip-of-day index 0..5
            // we pick locally. Show once per session.
            if !ws.welcomeShown {
                ws.welcomeLastIP = buf.getString()
                ws.welcomeDaysAgo = buf.getShort()
                ws.welcomeRecoveryDays = buf.getShort()
                ws.welcomeTipOfDay = Int.random(in: 0..<6)
                ws.welcomeShown = true
                ws.welcomeOpen = true
            }
            ws.addChat(sender: "[System]", text: "Welcome to \(ws.serverName)")

        case 234: // UPDATE_PLAYERS — player appearance/chat/combat updates
            handleUpdatePlayers(buf: buf, ws: ws)

        case 206: // SET_PRAYERS
            handleSetPrayers(buf: buf, ws: ws)

        case 211: // UPDATE_ENTITIES — ground item/object/wall counts
            handleUpdateEntityCounts(buf: buf, ws: ws)

        case 48:  // SCENERY_HANDLER — game objects
            handleShowGameObjects(buf: buf, ws: ws)

        case 91:  // BOUNDARY_HANDLER — wall objects
            handleShowWalls(buf: buf, ws: ws)

        case 165: // CLOSE_CONNECTION
            ws.connectionClosedText = "The server has closed the connection."
            ws.connectionClosedOpen = true

        case 111: // COMPLETED_TUTORIAL
            break

        case 113: // SEND_IRONMAN
            handleIronman(buf: buf, ws: ws)

        case 115: // SEND_ON_BLACK_HOLE
            if buf.bytesRemaining >= 1 { ws.isOnBlackHole = buf.getUnsignedByte() != 0 }

        case 84:  // WAKE_UP
            ws.isSleeping = false
            ws.sleepStatusText = ""

        case 51:  // PRIVACY_SETTINGS
            if buf.bytesRemaining >= 4 {
                ws.blockChat = buf.getUnsignedByte()
                ws.blockPrivate = buf.getUnsignedByte()
                ws.blockTrade = buf.getUnsignedByte()
                ws.blockDuel = buf.getUnsignedByte()
            }

        case 52:  // UPDATE_SYSTEM_UPDATE_TIMER
            // Java mudclient.java:413 — server sends ticks, multiplies by 32
            // to convert to ~milliseconds (one tick ≈ 32ms client clock).
            if buf.bytesRemaining >= 2 {
                let rawTicks = buf.getShort()
                ws.systemUpdateTicks = rawTicks * 32
            }

        case 59:  // SHOW_APPEARANCE_CHANGE — character creation screen
            ws.showAppearanceChange = true
            print("[Packet] Character creation screen requested")

        case 90:  // SET_INVENTORY_SLOT — Java updateInventoryItem()
            // Format: BYTE slot, SHORT itemID-with-equipped-bit, [ushort/int amount if stackable]
            if buf.bytesRemaining >= 3 {
                let slot90 = buf.getUnsignedByte()
                let rawItemID90 = buf.getUnsignedShort()
                let equipped90 = (rawItemID90 & 32768) != 0
                let itemID90 = rawItemID90 & 32767
                let amount90: Int
                if itemID90 == 0 {
                    amount90 = 0
                    _ = buf.getBytes(buf.bytesRemaining)
                } else {
                    amount90 = ItemDefinitions.isStackable(itemID90) && buf.bytesRemaining >= 2 ? buf.getUnsignedShortInt() : 1
                }

                while ws.inventory.count <= slot90 {
                    ws.inventory.append(RSCInventoryItem(id: ws.inventory.count, itemId: 0, amount: 0, equipped: false))
                }
                ws.inventory[slot90].itemId = itemID90
                ws.inventory[slot90].equipped = equipped90
                ws.inventory[slot90].amount = amount90
                print("[Packet] Inventory slot update: slot=\(slot90) itemId=\(itemID90) amount=\(amount90) equipped=\(equipped90)")
            }

        case 123: // REMOVE_INVENTORY_SLOT — Java removeItem()
            if buf.bytesRemaining >= 1 {
                let slot123 = buf.getUnsignedByte()
                if slot123 < ws.inventory.count {
                    let removed = ws.inventory[slot123]
                    ws.inventory.remove(at: slot123)
                    // Re-index remaining items
                    for i in 0..<ws.inventory.count {
                        ws.inventory[i] = RSCInventoryItem(id: i, itemId: ws.inventory[i].itemId,
                                                            amount: ws.inventory[i].amount, equipped: ws.inventory[i].equipped)
                    }
                    print("[Packet] Inventory slot removed: slot=\(slot123) itemId=\(removed.itemId) amount=\(removed.amount)")
                } else {
                    print("[Packet] Inventory remove ignored: slot=\(slot123) count=\(ws.inventory.count)")
                }
            }

        case 109: // SET_IGNORE — Java updateIgnoreList()
            // Format: BYTE count, then per entry: 4x RSC strings
            // (raw/display current name, raw/display former name).
            let ignoreCount = buf.getUnsignedByte()
            var ignores: [String] = []
            for _ in 0..<ignoreCount {
                let rawName = buf.getString()
                var name = buf.getString() // display current name
                if name.isEmpty { name = rawName }
                let _ = buf.getString() // raw formerName
                let _ = buf.getString() // display formerName
                ignores.append(name)
            }
            ws.ignoreList = ignores

        case 237: // updateIgnoreListBecauseNameChange
            let rawName = buf.getString()
            var name = buf.getString()
            if name.isEmpty { name = rawName }
            let rawFormerName = buf.getString()
            var formerName = buf.getString()
            if formerName.isEmpty { formerName = rawName.isEmpty ? rawFormerName : rawName }
            let updateExisting = buf.getUnsignedByte() == 1
            if updateExisting, let idx = ws.ignoreList.firstIndex(of: formerName) {
                ws.ignoreList[idx] = name
            } else if !ws.ignoreList.contains(name) {
                ws.ignoreList.append(name)
            }

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
            handleUpdateEquipmentSlot(buf: buf, ws: ws)

        case 249: // updateBank — individual bank slot update
            if buf.bytesRemaining >= 5 {
                let slot249 = buf.getUnsignedByte()
                let itemId249 = buf.getUnsignedShort()
                let amount249 = buf.getUnsignedShortInt()
                if slot249 < ws.bankItems.count {
                    ws.bankItems[slot249] = (id: itemId249, amount: amount249)
                }
            }

        case 104: // updateNPCAppearances — NPC chat/damage/projectile updates
            handleNPCAppearances(buf: buf, ws: ws)

        case 117: // showSleepScreen — server sends captcha image data
            ws.isSleeping = true
            ws.sleepFatigue = ws.fatigue
            ws.sleepStatusText = "Enter the word to wake up"
            // The remaining bytes are the encoded captcha sprite. SleepPanel
            // renders them via a custom RLE decoder mirroring
            // mudclient.makeSleepSprite (PacketHandler.java:2422-2438).
            var captchaBytes: [UInt8] = []
            while buf.bytesRemaining > 0 {
                captchaBytes.append(UInt8(truncatingIfNeeded: buf.getUnsignedByte()))
            }
            ws.sleepCaptchaBytes = Data(captchaBytes)

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

        case 6: // updateDuelDialog — opponent stake items
            let duelTheirCount = buf.getUnsignedByte()
            var duelTheirItems: [(id: Int, amount: Int)] = []
            for _ in 0..<duelTheirCount {
                let did = buf.getShort()
                let damt = buf.get32()
                duelTheirItems.append((id: did, amount: damt))
            }
            ws.duelTheirStake = duelTheirItems
            ws.duelAccepted = false
            ws.duelOpponentAccepted = false

        case 172: // showDuelConfirmDialog — confirmation screen
            ws.duelOpen = false
            ws.duelConfirmOpen = true
            ws.duelOpponentName = buf.getZeroPaddedString()
            // Their stake
            let duelTheirCount = buf.getUnsignedByte()
            var duelTheirItems: [(id: Int, amount: Int)] = []
            for _ in 0..<duelTheirCount {
                let did = buf.getShort()
                let damt = buf.get32()
                duelTheirItems.append((id: did, amount: damt))
            }
            ws.duelTheirStake = duelTheirItems
            // My stake
            let duelMyCount = buf.getUnsignedByte()
            var duelMyItems: [(id: Int, amount: Int)] = []
            for _ in 0..<duelMyCount {
                let did = buf.getShort()
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

        case 89:  // showServerMessageDialogTwo — Java lower/centered server modal
            let msg89 = buf.getString()
            ws.serverMessageDialogText = msg89
            ws.serverMessageDialogTop = false
            ws.serverMessageDialogOpen = true
            ws.addChat(sender: "[Server]", text: msg89)

        case 88:  // createNPC — dynamic NPC definition from server
            handleCreateNPC(buf: buf, ws: ws)

        case 112: // updateClan
            handleUpdateClan(buf: buf, ws: ws)

        case 116: // updateParty
            handleUpdateParty(buf: buf, ws: ws)

        case 36:  // drawTeleportBubbles
            if buf.bytesRemaining >= 3, ws.teleportBubbles.count < 50 {
                let type = buf.getUnsignedByte()
                let x = ws.localPlayerX + buf.getByte()
                let z = ws.localPlayerY + buf.getByte()
                ws.teleportBubbles.append(RSCTeleportBubble(type: type, x: x, y: z))
            }

        case 71:  // legacy SEND_FRIEND_LIST — BYTE count, [LONG usernameHash, BYTE world]
            let friendCount = buf.getUnsignedByte()
            var friends: [(name: String, online: Bool)] = []
            for _ in 0..<friendCount {
                guard buf.bytesRemaining >= 9 else { break }
                let hash = getInt64(buf)
                let world = buf.getUnsignedByte()
                let name = Self.username(fromHash: hash)
                if !name.isEmpty && name != "invalid_name" {
                    friends.append((name: name, online: world != 0 && world != 255))
                }
            }
            if !friends.isEmpty || friendCount == 0 {
                ws.friendsList = friends
            }

        case 147: // SEND_KILLS2 — Java reads 3x INT
            if buf.bytesRemaining >= 12 {
                ws.kills2 = buf.get32()
                ws.lastNpcKilledId = buf.get32()
                ws.kills3 = buf.get32()
            }

        case 148: // Set OpenPK points — Java reads LONG
            if buf.bytesRemaining >= 8 {
                ws.openPKPoints = getInt64(buf)
            }

        case 98: // shared XP percentage
            if buf.bytesRemaining >= 2 {
                ws.expShared = buf.getShort()
            }

        case 110: // SEND_INPUT_BOX — custom prompt string
            let prompt = buf.getString()
            ws.inputPromptText = prompt
            ws.inputPromptOpen = true
            ws.addChat(sender: "[Server]", text: prompt)

        case 140: // pet fatigue
            if buf.bytesRemaining >= 2 {
                ws.petFatigue = buf.getShort()
            }

        case 144: // SEND_OPENPK_POINTS_TO_GP_RATIO — no payload, opens Java conversion prompt
            ws.openPKPointsToGpPromptOpen = true

        case 150: // SEND_BANK_PRESET
            handleBankPreset(buf: buf, ws: ws)

        case 250: // UPDATE_UNLOCKED_APPEARANCES
            handleUnlockedAppearances(buf: buf, ws: ws)

        // Remaining opcodes — skip their data to keep things clean
        case 7, 16, 21, 23, 28, 29, 32, 37, 39, 49, 50, 55,
             94, 95, 119, 157, 189, 246:
            break

        default:
            print("[Packet] Unhandled opcode \(opcode) (\(payload.count) bytes)")
            break
        }
    }

    private static func runEnergy(fromFatigue fatigue: Int) -> Int {
        // Authentic servers use 0...7500 internally; several custom payloads
        // already downscale to 0...100. Accept either shape and render energy
        // as the inverse of fatigue.
        let fatiguePercent = fatigue > 100 ? fatigue / 75 : fatigue
        return max(0, min(100, 100 - fatiguePercent))
    }

    // MARK: - Packet parsers (matching PacketHandler.java methods)

    private func getInt64(_ buf: ByteBuffer) -> Int64 {
        let high = UInt64(UInt32(bitPattern: Int32(buf.get32())))
        let low = UInt64(UInt32(bitPattern: Int32(buf.get32())))
        return Int64(bitPattern: (high << 32) | low)
    }

    private func handleCreateNPC(buf: ByteBuffer, ws: RSCWorldState) {
        guard buf.bytesRemaining >= 2 else { return }
        let id = buf.getShort()
        let name = buf.getString()
        let description = buf.getString()

        let commandLength = buf.bytesRemaining > 0 ? buf.getUnsignedByte() : 0
        let command = commandLength > 0 ? buf.getString() : ""

        guard buf.bytesRemaining >= 6 else { return }
        let attack = buf.getUnsignedByte()
        let strength = buf.getUnsignedByte()
        let defense = buf.getUnsignedByte()
        let hits = buf.getUnsignedByte()
        let attackable = buf.getUnsignedByte() == 1

        let spriteCount = buf.getUnsignedByte()
        var sprites = Array(repeating: 0, count: 12)
        for i in 0..<spriteCount {
            let sprite = buf.bytesRemaining >= 4 ? buf.get32() : 0
            if i < sprites.count { sprites[i] = sprite }
        }

        guard buf.bytesRemaining >= 22 else { return }
        let hairColour = buf.get32()
        let topColour = buf.get32()
        let bottomColour = buf.get32()
        let skinColour = buf.get32()
        let camera1 = buf.getShort()
        let camera2 = buf.getShort()
        let walkModel = buf.getUnsignedByte()
        let combatModel = buf.getUnsignedByte()
        let combatSprite = buf.getUnsignedByte()

        let combatLevel = (attack + strength + defense + hits) / 4
        let def = NPCDefinition(
            id: id,
            name: name.isEmpty ? "NPC \(id)" : name,
            description: description,
            command: command,
            command2: "",
            attack: attack,
            strength: strength,
            hits: hits,
            defense: defense,
            combatLevel: combatLevel,
            attackable: attackable,
            aggressive: false,
            respawnTime: 0,
            sprites: sprites,
            hairColour: hairColour,
            topColour: topColour,
            bottomColour: bottomColour,
            skinColour: skinColour,
            camera1: camera1,
            camera2: camera2,
            walkModel: walkModel,
            combatModel: combatModel,
            combatSprite: combatSprite
        )
        NPCDefinitions.upsert(def)

        for idx in ws.npcs.indices where ws.npcs[idx].npcId == id {
            ws.npcs[idx].name = def.name
            if ws.npcs[idx].maxHp == 0 {
                ws.npcs[idx].maxHp = hits
                ws.npcs[idx].currentHp = hits
            }
        }
    }

    private static func username(fromHash hash: Int64) -> String {
        guard hash >= 0 else { return "invalid_name" }
        var value = hash
        var chars: [Character] = []
        while value != 0 {
            let idx = Int(value % 37)
            value /= 37
            if idx == 0 {
                chars.insert(" ", at: 0)
            } else if idx < 27 {
                let scalar = UnicodeScalar((value % 37 == 0 ? 65 : 97) + idx - 1)!
                chars.insert(Character(scalar), at: 0)
            } else {
                let scalar = UnicodeScalar(48 + idx - 27)!
                chars.insert(Character(scalar), at: 0)
            }
        }
        return String(chars)
    }

    private func handleIronman(buf: ByteBuffer, ws: RSCWorldState) {
        guard buf.bytesRemaining >= 2 else { return }
        let interfaceId = buf.getUnsignedByte()
        let actionId = buf.getUnsignedByte()
        switch actionId {
        case 0:
            if buf.bytesRemaining >= 2 {
                ws.ironmanType = buf.getUnsignedByte()
                ws.ironmanRestriction = buf.getUnsignedByte()
            }
        case 1:
            ws.ironmanInterfaceOpen = interfaceId != 0
        case 2:
            ws.ironmanInterfaceOpen = false
        default:
            break
        }
    }

    private func handleStatusProgress(buf: ByteBuffer, ws: RSCWorldState) {
        guard buf.bytesRemaining >= 1 else { return }
        let interfaceId = buf.getUnsignedByte()
        ws.statusProgressInterfaceId = interfaceId
        ws.statusProgressOpen = interfaceId > 0 && interfaceId != 2
        if ws.statusProgressOpen {
            if interfaceId == 1, buf.bytesRemaining >= 2 {
                ws.statusProgressDelay = buf.getShort()
            }
            if buf.bytesRemaining >= 1 {
                ws.statusProgressRepeats = buf.getUnsignedByte()
            }
        } else if interfaceId == 2 {
            ws.statusProgressDelay = 0
            ws.statusProgressRepeats = 0
        }
    }

    private func handleFishingTrawler(buf: ByteBuffer, ws: RSCWorldState) {
        guard buf.bytesRemaining >= 2 else { return }
        _ = buf.getUnsignedByte() // interface id; Java currently uses 6.
        let action = buf.getUnsignedByte()
        switch action {
        case 0:
            ws.fishingTrawlerOpen = true
        case 1:
            guard buf.bytesRemaining >= 6 else { return }
            ws.fishingTrawlerOpen = true
            ws.fishingTrawlerWaterLevel = buf.getShort()
            ws.fishingTrawlerFishCaught = buf.getShort()
            ws.fishingTrawlerMinutesLeft = buf.getUnsignedByte()
            ws.fishingTrawlerNetBroken = buf.getUnsignedByte() == 1
        case 2:
            ws.fishingTrawlerOpen = false
        default:
            break
        }
    }

    private func handleOnlineList(buf: ByteBuffer, ws: RSCWorldState) {
        guard buf.bytesRemaining >= 2 else { return }
        ws.onlinePlayerCount = buf.getShort()
        var players: [RSCOnlinePlayer] = []
        while buf.bytesRemaining > 0 {
            let name = buf.getString()
            guard buf.bytesRemaining >= 4 else { break }
            let icon = buf.get32()
            let location = buf.getString()
            if !name.isEmpty {
                players.append(RSCOnlinePlayer(name: name, icon: icon, location: location))
            }
        }
        ws.onlinePlayers = players
    }

    private func handleUnlockedAppearances(buf: ByteBuffer, ws: RSCWorldState) {
        guard buf.bytesRemaining >= 24 else { return }
        let hairStyleCount = max(0, buf.get32())
        let bodyTypeCount = max(0, buf.get32())
        let skinColourCount = max(0, buf.get32())
        let hairColourCount = max(0, buf.get32())
        let topColourCount = max(0, buf.get32())
        let bottomColourCount = max(0, buf.get32())

        func readBoolArray(_ count: Int) -> [Bool] {
            guard count > 0 else { return [] }
            return (0..<count).map { _ in buf.getBitMask(1) == 1 }
        }

        buf.startBitAccess()
        let hairStyles = readBoolArray(hairStyleCount)
        let bodyTypes = readBoolArray(bodyTypeCount)
        let skinColours = readBoolArray(skinColourCount)
        let hairColours = readBoolArray(hairColourCount)
        let topColours = readBoolArray(topColourCount)
        let bottomColours = readBoolArray(bottomColourCount)
        buf.endBitAccess()

        ws.unlockedAppearances = RSCUnlockedAppearances(
            hairStyles: hairStyles,
            bodyTypes: bodyTypes,
            skinColours: skinColours,
            hairColours: hairColours,
            topColours: topColours,
            bottomColours: bottomColours
        )
    }

    private func handleBankPreset(buf: ByteBuffer, ws: RSCWorldState) {
        guard buf.bytesRemaining >= 2 else { return }
        let slotIndex = buf.getShort()

        func readPresetItem(hasNotedByte: Bool) -> RSCBankPresetItem {
            guard buf.bytesRemaining > 0 else { return .empty }
            let first = buf.getUnsignedByte()
            // Server writes a single byte ItemId.NOTHING (0) for empty slots,
            // otherwise it writes a full short item id. We have already read
            // the high byte, so stitch the short back together.
            if first == 0 { return .empty }
            guard buf.bytesRemaining > 0 else { return .empty }
            let itemId = (first << 8) | buf.getUnsignedByte()
            var noted = false
            if hasNotedByte, buf.bytesRemaining > 0 {
                noted = buf.getUnsignedByte() != 0
            }
            var amount = 1
            if ItemDefinitions.isStackable(itemId, noted: noted), buf.bytesRemaining >= 4 {
                amount = max(1, buf.get32())
            }
            return RSCBankPresetItem(itemId: itemId, amount: amount, noted: noted)
        }

        let inventory = (0..<30).map { _ in readPresetItem(hasNotedByte: true) }
        let equipment = (0..<14).map { _ in readPresetItem(hasNotedByte: false) }
        ws.bankPresets[slotIndex] = RSCBankPreset(slotIndex: slotIndex, inventory: inventory, equipment: equipment)
    }

    private func handleServerConfig(buf: ByteBuffer, ws: RSCWorldState) {
        ws.serverName = buf.getString()
        ws.serverWelcomeMessage = buf.getString()
        ws.playerCount = buf.getShort()
        ws.playerMax = buf.getShort()
        ws.isMembersWorld = buf.getByte() != 0
    }

    /// Port of PacketHandler.java updateOptionsMenuSettings() for the settings
    /// that native systems currently consume. Some servers send shorter
    /// packets than the newest Java client expects, so each field is guarded
    /// and any trailing bytes are drained to keep packet parsing aligned.
    private func handleOptionsMenuSettings(buf: ByteBuffer, ws: RSCWorldState) {
        func readByte() -> Int? {
            guard buf.bytesRemaining > 0 else { return nil }
            return buf.getUnsignedByte()
        }

        if let value = readByte() { ws.optionCameraModeAuto = value == 1 } // 0
        if let value = readByte() { ws.optionMouseButtonOne = value == 1 } // 1
        if let value = readByte() { ws.optionSoundDisabled = value == 1 } // 2
        if let value = readByte() { ws.combatStyle = value } // 3
        if let value = readByte() { ws.settingsBlockGlobal = value } // 4

        // 5..24 are persisted for Java UI/settings only in this native pass.
        for _ in 5...24 {
            guard readByte() != nil else { return }
        }

        if let value = readByte() { ws.optionExperienceDrops = value == 1 } // 25
        if let value = readByte() { ws.optionHideRoofs = value == 1 } // 26
        if let value = readByte() { ws.optionHideFog = value == 1 } // 27
        if let value = readByte() { ws.groundItemsToggle = value } // 28

        // 29..30 are Java UI choices.
        for _ in 29...30 {
            guard readByte() != nil else { return }
        }

        if let value = readByte() { ws.optionHideKillFeed = value == 1 } // 31

        // 32..34 are fight-mode selector / XP counter / inventory count.
        for _ in 32...34 {
            guard readByte() != nil else { return }
        }

        if let value = readByte() { ws.optionHideNameTag = value == 1 } // 35

        while buf.bytesRemaining > 0 { _ = buf.getUnsignedByte() }
    }

    /// 3-bit movement direction encoding shared by showOtherPlayers and
    /// showNPCs (PacketHandler.java:1391-1404 and 1827-1842). Index = direction
    /// code 0..7, value = (deltaX, deltaY) tile offset, also re-used as the
    /// new facing (`animationNext = modelIndex` in Java).
    private static let movementDeltas: [(Int, Int)] = [
        (0, -1),   // 0 N
        (1, -1),   // 1 NE
        (1, 0),    // 2 E
        (1, 1),    // 3 SE
        (0, 1),    // 4 S
        (-1, 1),   // 5 SW
        (-1, 0),   // 6 W
        (-1, -1)   // 7 NW
    ]

    // Port of PacketHandler.java showOtherPlayers() — bit-packed player position sync
    // Reference: PacketHandler.java:1339-1435
    private func handleShowPlayers(buf: ByteBuffer, ws: RSCWorldState, length: Int) {
        buf.startBitAccess()

        // Local player absolute position (11-bit X, 13-bit Z, 4-bit direction)
        let localX = buf.getBitMask(11)
        let localZ = buf.getBitMask(13)
        let localDir = buf.getBitMask(4)

        ws.localPlayerX = localX
        ws.localPlayerY = localZ
        ws.localPlayerDirection = localDir & 7

        // Number of known (returning) players to update.
        let knownCount = buf.getBitMask(8)

        // Java keeps a per-tick known/active table: snapshot the prior
        // active list, advance kept entries via the update bits, then fold
        // genuinely-new players from the tail. We mirror that so the
        // players array doesn't blink empty between announcements.
        var kept: [RSCPlayer] = ws.players
        var keep = Array(repeating: true, count: kept.count)

        for i in 0..<knownCount {
            let needsUpdate = buf.getBitMask(1)
            if needsUpdate == 0 { continue }
            let updateType = buf.getBitMask(1)
            if updateType != 0 {
                // Animation/sprite branch.
                let needsNextSprite = buf.getBitMask(2)
                if needsNextSprite == 3 {
                    // Player removed — drop the kept entry.
                    if i < kept.count { keep[i] = false }
                    continue
                }
                // Java: animationNext = (needsNextSprite << 2) + 2bit. The
                // low 3 bits are the new facing direction.
                let nextSprite = buf.getBitMask(2)
                if i < kept.count {
                    kept[i].direction = ((needsNextSprite << 2) | nextSprite) & 7
                }
            } else {
                // Motion branch — 3-bit modelIndex is both the move vector
                // and the new facing direction.
                let modelIndex = buf.getBitMask(3)
                if i < kept.count, modelIndex < Self.movementDeltas.count {
                    let (dx, dy) = Self.movementDeltas[modelIndex]
                    kept[i].previousX = kept[i].x
                    kept[i].previousY = kept[i].y
                    kept[i].x += dx
                    kept[i].y += dy
                    kept[i].interpolationTicksRemaining = RSCCharacterInterpolationTicks
                    kept[i].direction = modelIndex & 7
                    kept[i].moving = true
                }
            }
        }

        // Drop removed entries while preserving order.
        kept = zip(kept, keep).compactMap { $1 ? $0 : nil }

        // New players entering view — 24+ bits remaining per player.
        // Format: 11-bit serverIndex, 6-bit signed relX, 6-bit signed relZ, 4-bit direction.
        while length * 8 > buf.bitHead + 24 {
            let serverIndex = buf.getBitMask(11)
            var relX = buf.getBitMask(6)
            if relX > 31 { relX -= 64 }
            var relZ = buf.getBitMask(6)
            if relZ > 31 { relZ -= 64 }
            let dir = buf.getBitMask(4)

            let playerTileX = localX + relX
            let playerTileZ = localZ + relZ
            // De-dupe: if the server re-announces a known player, prefer the
            // fresh authoritative coords from this entry over the kept one.
            if let existing = kept.firstIndex(where: { $0.id == serverIndex }) {
                kept[existing].previousX = kept[existing].x
                kept[existing].previousY = kept[existing].y
                kept[existing].x = playerTileX
                kept[existing].y = playerTileZ
                kept[existing].interpolationTicksRemaining =
                    (kept[existing].previousX == playerTileX && kept[existing].previousY == playerTileZ)
                    ? 0
                    : RSCCharacterInterpolationTicks
                kept[existing].direction = dir & 7
            } else {
                kept.append(RSCPlayer(id: serverIndex, x: playerTileX, y: playerTileZ,
                                       name: "Player \(serverIndex)", moving: false, combatLevel: 0,
                                       direction: dir & 7))
            }
        }

        buf.endBitAccess()

        ws.players = kept

        if knownCount > 0 || kept.count > 0 {
            print("[PLY] len=\(length) known=\(knownCount) total=\(kept.count) localPos=(\(localX),\(localZ))")
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

        // Process movement/animation updates for existing NPCs.
        // Java: for (int i = 0; i < existingCount; i++) { npc = npcArray[i]; ... }
        // The 3-bit movement direction matches the shared 8-compass encoding
        // used by showOtherPlayers (PacketHandler.java:1827-1842).
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
                    // Java showOtherPlayers (PacketHandler.java:1385):
                    // animationNext = (needsNextSprite << 2) + 2bit. This
                    // 4-bit code is the next animation index — for NPCs
                    // that's still effectively the facing direction.
                    let nextSprite = buf.getBitMask(2)
                    if i < keptNPCs.count {
                        keptNPCs[i].direction = ((needsNextSprite << 2) | nextSprite) & 7
                    }
                } else {
                    let dir = buf.getBitMask(3) // 0..7 — N, NE, E, SE, S, SW, W, NW
                    // Update position based on direction; also update facing
                    // — Java setKnownPlayer/showNPCs treats `modelIndex` as
                    // both motion vector and the new animationNext (which
                    // CharacterBillboards reads as rsDir).
                    if i < keptNPCs.count, dir < Self.movementDeltas.count {
                        let (dx, dy) = Self.movementDeltas[dir]
                        keptNPCs[i].previousX = keptNPCs[i].x
                        keptNPCs[i].previousY = keptNPCs[i].y
                        keptNPCs[i].x += dx
                        keptNPCs[i].y += dy
                        keptNPCs[i].interpolationTicksRemaining = RSCCharacterInterpolationTicks
                        keptNPCs[i].direction = dir & 7
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
            let dir = buf.getBitMask(4)
            let npcTypeId = buf.getBitMask(10)

            let npcTileX = localX + relX
            let npcTileZ = localZ + relZ
            let npcName = NPCDefinitions.get(npcTypeId)?.name ?? NPCNames.name(for: npcTypeId)
            var npc = RSCNPC(id: serverIndex, x: npcTileX, y: npcTileZ,
                             npcId: npcTypeId, name: npcName)
            npc.direction = dir & 7
            keptNPCs.append(npc)
            newCount += 1
        }

        buf.endBitAccess()
        ws.npcs = keptNPCs

        if existingCount > 0 || newCount > 0 {
            print("[NPC] len=\(length) existing=\(existingCount) new=\(newCount) total=\(keptNPCs.count)")
        }
    }

    // Port of PacketHandler.java updateInventory() — opcode 53
    // Format: BYTE count, then per item: SHORT itemID-with-equipped-bit, [ushort/int amount if stackable]
    private func handleUpdateInventory(buf: ByteBuffer, ws: RSCWorldState) {
        let count = buf.getUnsignedByte()
        var items: [RSCInventoryItem] = []
        for i in 0..<count {
            let rawItemId = buf.getUnsignedShort()
            let equipped = (rawItemId & 32768) != 0
            let itemId = rawItemId & 32767
            let amount = ItemDefinitions.isStackable(itemId) && buf.bytesRemaining >= 2 ? buf.getUnsignedShortInt() : 1
            items.append(RSCInventoryItem(id: i, itemId: itemId, amount: amount, equipped: equipped))
        }
        ws.inventory = items
        print("[Packet] Inventory: \(count) items")
    }

    private func handleUpdateEquipment(buf: ByteBuffer, ws: RSCWorldState) {
        let count = buf.getUnsignedByte()
        var slots: [RSCEquipmentSlot] = []
        for _ in 0..<count {
            guard buf.bytesRemaining >= 3 else { break }
            let serverSlot = buf.getByte()
            let itemId = buf.getUnsignedShort()
            guard let slot = canonicalEquipmentSlot(serverSlot) else { continue }
            let amount = ItemDefinitions.isStackable(itemId) && buf.bytesRemaining >= 4 ? buf.get32() : 1
            slots.append(RSCEquipmentSlot(id: slot, itemId: itemId, amount: amount))
        }
        ws.equipment = slots.sorted { $0.id < $1.id }
        print("[Packet] Equipment: \(ws.equipment.count) items")
    }

    private func handleUpdateEquipmentSlot(buf: ByteBuffer, ws: RSCWorldState) {
        guard buf.bytesRemaining >= 3 else { return }
        let serverSlot = buf.getByte()
        let rawItemId = buf.getUnsignedShort()
        guard let slot = canonicalEquipmentSlot(serverSlot) else { return }

        if rawItemId == 0xFFFF {
            ws.equipment.removeAll { $0.id == slot }
            return
        }

        let amount = ItemDefinitions.isStackable(rawItemId) && buf.bytesRemaining >= 4 ? buf.get32() : 1
        let nextSlot = RSCEquipmentSlot(id: slot, itemId: rawItemId, amount: amount)
        if let existing = ws.equipment.firstIndex(where: { $0.id == slot }) {
            ws.equipment[existing] = nextSlot
        } else {
            ws.equipment.append(nextSlot)
            ws.equipment.sort { $0.id < $1.id }
        }
    }

    private func canonicalEquipmentSlot(_ serverSlot: Int) -> Int? {
        switch serverSlot {
        case 5: return 0
        case 6: return 1
        case 7: return 2
        case let slot where slot > 7: return slot - 3
        case let slot where slot >= 0: return slot
        default: return nil
        }
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
    // Format: BYTE itemCount, BYTE maxItems, then per item: SHORT id, ushort/int amount
    private func handleShowBank(buf: ByteBuffer, ws: RSCWorldState) {
        let itemCount = buf.getUnsignedByte()
        let maxItems = buf.getUnsignedByte()
        var items: [(id: Int, amount: Int)] = []
        for _ in 0..<itemCount {
            let id = buf.getUnsignedShort()
            let amount = buf.getUnsignedShortInt()
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
                let itemType = buf.getShort()
                if serverIndex == ws.playerServerIndex {
                    ws.localBubbleItem = itemType
                    ws.localBubbleTimeout = 150
                } else if let idx = ws.players.firstIndex(where: { $0.id == serverIndex }) {
                    ws.players[idx].bubbleItem = itemType
                    ws.players[idx].bubbleTimeout = 150
                }

            case 1, 7: // Chat message
                let _ = buf.get32() // crownID
                if updateType == 7 {
                    let _ = buf.getUnsignedByte() // muted
                    let _ = buf.getUnsignedByte() // onTutorial
                }
                let message = buf.getString()
                // Java drawNearbyPlayers also sets player.message and
                // player.messageTimeout = 150 so the bubble floats above
                // the head, not just in the chat log.
                if serverIndex == ws.playerServerIndex {
                    ws.localMessage = message
                    ws.localMessageTimeout = 150
                    ws.addChat(sender: ws.localPlayerName.isEmpty ? "You" : ws.localPlayerName,
                               text: message, isLocal: true)
                } else if let idx = ws.players.firstIndex(where: { $0.id == serverIndex }) {
                    ws.players[idx].message = message
                    ws.players[idx].messageTimeout = 150
                    ws.addChat(sender: ws.players[idx].name, text: message)
                }

            case 6: // Quest message
                let message = buf.getString()
                if serverIndex == ws.playerServerIndex {
                    ws.addChat(sender: "[Quest]", text: message)
                }

            case 2: // Combat damage — Java drawNearbyPlayers, sets damageTaken
                    // and combatTimeout = 200 so the splat is shown for ~50 render
                    // ticks (timeout > 150 window).
                let damage = buf.getUnsignedByte()
                let curhp = buf.getUnsignedByte()
                let maxhp = buf.getUnsignedByte()
                if serverIndex == ws.playerServerIndex {
                    if let hpIdx = ws.skills.firstIndex(where: { $0.id == 3 }) {
                        ws.skills[hpIdx].current = curhp
                        ws.skills[hpIdx].base = maxhp
                    }
                    ws.serverMessageDialogOpen = false
                    ws.welcomeOpen = false
                    ws.lastDamageReceived = damage
                    ws.localDamageTaken = damage
                    ws.localDamageTimeout = 200
                } else if let idx = ws.players.firstIndex(where: { $0.id == serverIndex }) {
                    ws.players[idx].damageTaken = damage
                    ws.players[idx].damageTimeout = 200
                }

            case 3, 4: // Projectile targeting this player
                let sprite = buf.getShort()
                let shooterServerIndex = buf.getShort()
                if serverIndex == ws.playerServerIndex {
                    ws.localProjectileSprite = sprite
                    ws.localProjectileRange = 40
                    ws.localProjectileSourceServerIndex = shooterServerIndex
                    ws.localProjectileSourceIsNpc = updateType == 3
                } else if let idx = ws.players.firstIndex(where: { $0.id == serverIndex }) {
                    ws.players[idx].projectileSprite = sprite
                    ws.players[idx].projectileRange = 40
                    ws.players[idx].projectileSourceServerIndex = shooterServerIndex
                    ws.players[idx].projectileSourceIsNpc = updateType == 3
                }

            case 5: // Full appearance update — Java drawNearbyPlayers (PacketHandler.java:2690)
                let playerName = buf.getString()
                let itemCount = buf.getUnsignedByte()
                // Java zero-fills layerAnimation[itemCount..12]. We mirror that
                // so callers always have a 12-slot array.
                var sprites = [Int](repeating: 0, count: 12)
                for i in 0..<min(itemCount, 12) { sprites[i] = buf.getShort() }
                // If the server somehow sent more than 12 (shouldn't happen),
                // drain the extras to keep the stream aligned.
                if itemCount > 12 {
                    for _ in 12..<itemCount { let _ = buf.getShort() }
                }
                let hairColour = buf.getUnsignedByte()
                let topColour = buf.getUnsignedByte()
                let bottomColour = buf.getUnsignedByte()
                let skinColour = buf.getUnsignedByte()
                let combatLevel = buf.getUnsignedByte()
                let skulled = buf.getUnsignedByte()
                var clanTag: String? = nil
                if buf.getByte() == 1 { clanTag = buf.getString() }
                let _ = buf.getByte() // isInvisible
                let _ = buf.getByte() // isInvulnerable
                let _ = buf.getByte() // groupID
                let _ = buf.get32() // icon

                ws.playerAppearances[serverIndex] = RSCPlayerAppearance(
                    layerSprites: sprites,
                    colourHair: hairColour,
                    colourTop: topColour,
                    colourBottom: bottomColour,
                    colourSkin: skinColour,
                    combatLevel: combatLevel,
                    skulled: skulled != 0,
                    clanTag: clanTag
                )

                if let idx = ws.players.firstIndex(where: { $0.id == serverIndex }) {
                    ws.players[idx].name = playerName
                    ws.players[idx].combatLevel = combatLevel
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
                    ws.serverMessageDialogOpen = false
                    ws.welcomeOpen = false
                }

            case 9: // HP update (no damage/heal value)
                let curhp9 = buf.getUnsignedByte()
                let maxhp9 = buf.getUnsignedByte()
                if serverIndex == ws.playerServerIndex {
                    if let hpIdx = ws.skills.firstIndex(where: { $0.id == 3 }) {
                        ws.skills[hpIdx].current = curhp9
                        ws.skills[hpIdx].base = maxhp9
                    }
                    ws.serverMessageDialogOpen = false
                    ws.welcomeOpen = false
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

    // Port of PacketHandler.java generateCounts() — opcode 211.
    // Each pair of signed shorts identifies an 8x8 region being refreshed;
    // existing ground items, scenery, and wall objects in that region are
    // pruned before the follow-up showGroundItems/showGameObjects/showWalls
    // packets add the current contents back.
    private func handleUpdateEntityCounts(buf: ByteBuffer, ws: RSCWorldState) {
        var regions: [(x: Int, z: Int)] = []
        while buf.bytesRemaining >= 4 {
            let regionX = (ws.localPlayerX + buf.getShort()) >> 3
            let regionZ = (ws.localPlayerY + buf.getShort()) >> 3
            regions.append((x: regionX, z: regionZ))
        }

        guard !regions.isEmpty else { return }

        ws.groundItems.removeAll { item in
            regions.contains { region in (item.x >> 3) == region.x && (item.y >> 3) == region.z }
        }
        ws.gameObjects.removeAll { object in
            regions.contains { region in (object.x >> 3) == region.x && (object.y >> 3) == region.z }
        }
        ws.wallObjects.removeAll { wall in
            regions.contains { region in (wall.x >> 3) == region.x && (wall.y >> 3) == region.z }
        }
    }

    // MARK: - Trade Updates

    // opcode 97 — updateTradeDialog: opponent items only
    private func handleUpdateTradeDialog(buf: ByteBuffer, ws: RSCWorldState) {
        let theirCount = buf.getUnsignedByte()
        var theirItems: [(id: Int, amount: Int)] = []
        for _ in 0..<theirCount {
            let itemId = buf.getShort()
            let amount = buf.get32()
            theirItems.append((id: itemId, amount: amount))
        }
        ws.tradeTheirOffer = theirItems
        ws.tradeAccepted = false
        ws.tradePartnerAccepted = false
        print("[Packet] Trade update: their=\(theirCount) items")
    }

    // opcode 20 — confirmTrade: show confirmation screen
    private func handleTradeConfirm(buf: ByteBuffer, ws: RSCWorldState) {
        let partnerName = buf.getZeroPaddedString()
        ws.tradePartnerName = partnerName
        let theirCount = buf.getUnsignedByte()
        var theirItems: [(id: Int, amount: Int)] = []
        for _ in 0..<theirCount {
            let itemId = buf.getShort()
            let amount = buf.get32()
            theirItems.append((id: itemId, amount: amount))
        }
        let myCount = buf.getUnsignedByte()
        var myItems: [(id: Int, amount: Int)] = []
        for _ in 0..<myCount {
            let itemId = buf.getShort()
            let amount = buf.get32()
            myItems.append((id: itemId, amount: amount))
        }
        ws.tradeTheirOffer = theirItems
        ws.tradeMyOffer = myItems
        ws.tradeOpen = false
        ws.tradeConfirmOpen = true
        print("[Packet] Trade confirm with \(partnerName)")
    }

    // Port of PacketHandler.java togglePrayer(length) — opcode 206.
    private func handleSetPrayers(buf: ByteBuffer, ws: RSCWorldState) {
        var idx = 0
        var next = ws.activePrayers
        while buf.bytesRemaining > 0 {
            if idx >= next.count {
                next.append(false)
            }
            next[idx] = buf.getByte() == 1
            idx += 1
        }
        if idx > 0 {
            ws.activePrayers = next
        }
    }

    // Port of PacketHandler.java updateClan() — opcode 112. Native iOS does
    // not yet expose the full clan setup/search UI, but it keeps membership,
    // invites, and settings in worldState so social surfaces can bind to it.
    private func handleUpdateClan(buf: ByteBuffer, ws: RSCWorldState) {
        guard buf.bytesRemaining > 0 else { return }
        let actionType = buf.getUnsignedByte()
        switch actionType {
        case 0: // Send clan
            ws.clanName = buf.getString()
            ws.clanTag = buf.getString()
            ws.clanLeader = buf.getString()
            ws.isClanLeader = buf.getUnsignedByte() == 1
            let count = buf.getUnsignedByte()
            var members: [RSCClanMember] = []
            for _ in 0..<count {
                let name = buf.getString()
                let rank = buf.getUnsignedByte()
                let online = buf.getUnsignedByte() == 1
                members.append(RSCClanMember(name: name, rank: rank, online: online))
            }
            ws.clanMembers = members
            ws.inClan = true
            ws.addChat(sender: "[Clan]", text: "Clan loaded: \(ws.clanName)")

        case 1: // Leave clan
            ws.inClan = false
            ws.clanMembers = []
            ws.clanName = ""
            ws.clanTag = ""
            ws.clanLeader = ""
            ws.isClanLeader = false
            ws.addChat(sender: "[Clan]", text: "You have left your clan.")

        case 2: // Sent invitation
            ws.clanInviteFrom = buf.getString()
            ws.clanInviteName = buf.getString()
            ws.addChat(sender: "[Clan]", text: "\(ws.clanInviteFrom) invited you to \(ws.clanInviteName).")

        case 3: // Settings
            ws.clanSettings = [buf.getUnsignedByte(), buf.getUnsignedByte(), buf.getUnsignedByte()]
            ws.clanAllowed = [buf.getUnsignedByte() == 1, buf.getUnsignedByte() == 1]

        case 4: // Search results
            let count = buf.getShort()
            var results: [RSCClanSearchResult] = []
            for _ in 0..<count {
                guard buf.bytesRemaining > 0 else { break }
                let clanId = buf.getShort()
                let clanName = buf.getString()
                let clanTag = buf.getString()
                let members = buf.getUnsignedByte()
                let canJoin = buf.getUnsignedByte() == 1
                let clanPoints = buf.get32()
                let clanRank = buf.getShort()
                results.append(RSCClanSearchResult(
                    clanId: clanId,
                    name: clanName,
                    tag: clanTag,
                    members: members,
                    canJoin: canJoin,
                    points: clanPoints,
                    rank: clanRank
                ))
            }
            ws.clanSearchResults = results

        default:
            while buf.bytesRemaining > 0 { _ = buf.getUnsignedByte() }
        }
    }

    // Port of PacketHandler.java updateParty() — opcode 116.
    private func handleUpdateParty(buf: ByteBuffer, ws: RSCWorldState) {
        guard buf.bytesRemaining > 0 else { return }
        let actionType = buf.getUnsignedByte()
        switch actionType {
        case 0: // Send party
            ws.partyLeader = buf.getString()
            ws.isPartyLeader = buf.getUnsignedByte() == 1
            let count = buf.getUnsignedByte()
            var members: [RSCPartyMember] = []
            for _ in 0..<count {
                let name = buf.getString()
                let rank = buf.getUnsignedByte()
                let online = buf.getUnsignedByte() == 1
                let curHp = buf.getUnsignedByte()
                let maxHp = buf.getUnsignedByte()
                let cbLvl = buf.getUnsignedByte()
                let skull = buf.getUnsignedByte()
                _ = buf.getUnsignedByte() // pMemD
                let shareLoot = buf.getUnsignedByte() == 1
                _ = buf.getUnsignedByte() // partyMembersTotal
                _ = buf.getUnsignedByte() // inCombat
                let shareExp = buf.getUnsignedByte() == 1
                _ = buf.get32() // expShared high
                _ = buf.get32() // expShared low
                members.append(RSCPartyMember(
                    name: name, rank: rank, online: online,
                    currentHp: curHp, maxHp: maxHp, combatLevel: cbLvl,
                    skull: skull, shareLoot: shareLoot, shareExp: shareExp
                ))
            }
            ws.partyMembers = members
            ws.inParty = true
            ws.addChat(sender: "[Party]", text: "Party loaded with \(members.count) member(s).")

        case 1: // Leave party
            ws.inParty = false
            ws.partyMembers = []
            ws.partyLeader = ""
            ws.isPartyLeader = false
            ws.addChat(sender: "[Party]", text: "You have left your party.")

        case 2: // Sent invitation
            ws.partyInviteFrom = buf.getString()
            ws.partyInviteName = buf.getString()
            ws.addChat(sender: "[Party]", text: "\(ws.partyInviteFrom) invited you to \(ws.partyInviteName).")

        case 3: // Settings
            ws.partySettings = [buf.getUnsignedByte(), buf.getUnsignedByte(), buf.getUnsignedByte()]
            ws.partyAllowed = [buf.getUnsignedByte() == 1, buf.getUnsignedByte() == 1]

        case 4: // Search results
            let count = buf.getShort()
            var results: [RSCPartySearchResult] = []
            for _ in 0..<count {
                guard buf.bytesRemaining > 0 else { break }
                let partyId = buf.getShort()
                let members = buf.getUnsignedByte()
                let canJoin = buf.getUnsignedByte() == 1
                let partyPoints = buf.get32()
                let partyRank = buf.getShort()
                results.append(RSCPartySearchResult(
                    partyId: partyId,
                    members: members,
                    canJoin: canJoin,
                    points: partyPoints,
                    rank: partyRank
                ))
            }
            ws.partySearchResults = results

        default:
            while buf.bytesRemaining > 0 { _ = buf.getUnsignedByte() }
        }
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

            case 3: // Projectile targeting this NPC from another NPC
                let sprite = buf.getShort()
                let shooterServerIndex = buf.getShort()
                if let idx = ws.npcs.firstIndex(where: { $0.id == serverIndex }) {
                    ws.npcs[idx].projectileSprite = sprite
                    ws.npcs[idx].projectileRange = 40
                    ws.npcs[idx].projectileSourceServerIndex = shooterServerIndex
                    ws.npcs[idx].projectileSourceIsNpc = true
                }

            case 4: // Projectile targeting this NPC from a player
                let sprite = buf.getShort()
                let shooterServerIndex = buf.getShort()
                if let idx = ws.npcs.firstIndex(where: { $0.id == serverIndex }) {
                    ws.npcs[idx].projectileSprite = sprite
                    ws.npcs[idx].projectileRange = 40
                    ws.npcs[idx].projectileSourceServerIndex = shooterServerIndex
                    ws.npcs[idx].projectileSourceIsNpc = false
                }

            case 5: // Skull visibility
                let skull = buf.getUnsignedByte()
                if let idx = ws.npcs.firstIndex(where: { $0.id == serverIndex }) {
                    ws.npcs[idx].skullVisible = skull
                }

            case 6: // Wield change
                let wield = buf.getUnsignedByte()
                let wield2 = buf.getUnsignedByte()
                if let idx = ws.npcs.firstIndex(where: { $0.id == serverIndex }) {
                    ws.npcs[idx].wield = wield
                    ws.npcs[idx].wield2 = wield2
                }

            case 7: // Bubble item
                let itemType = buf.getShort()
                if let idx = ws.npcs.firstIndex(where: { $0.id == serverIndex }) {
                    ws.npcs[idx].bubbleItem = itemType
                    ws.npcs[idx].bubbleTimeout = 150
                }

            default:
                break
            }
        }
    }
}
