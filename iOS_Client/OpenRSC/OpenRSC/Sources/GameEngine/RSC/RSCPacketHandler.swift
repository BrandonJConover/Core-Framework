import Foundation

// Dispatches incoming RSC server packets to world state updates.
// Matches PacketHandler.java handlePacket1() / handlePacket2().
@MainActor
final class RSCPacketHandler {
    weak var worldState: RSCWorldState?

    func handlePacket(opcode: UInt8, payload: Data) {
        guard let ws = worldState else { return }
        let buf = ByteBuffer()
        buf.setReadData(payload)

        switch opcode {
        case 131: // chatMessage — game/system message
            let text = buf.getString()
            ws.addChat(sender: "[Server]", text: text)

        case 120: // receivePrivateMsg
            let sender = buf.getString()
            let text   = buf.getString()
            ws.addChat(sender: sender, text: text, isPrivate: true)

        case 19:  // serverConfig — setServerConfiguration()
            handleServerConfig(buf: buf, ws: ws)

        case 191: // showOtherPlayers — player position updates
            handleShowPlayers(buf: buf, ws: ws)

        case 79:  // showNPCs
            handleShowNPCs(buf: buf, ws: ws)

        case 25:  // loadArea — local player position
            ws.localPlayerX = buf.getShort()
            ws.localPlayerY = buf.getShort()

        case 53:  // updateInventory
            handleUpdateInventory(buf: buf, ws: ws)

        case 254: // updateEquipment (SEND_EQUIPMENT)
            handleUpdateEquipment(buf: buf, ws: ws)

        case 153: // updateEquipmentStats (armour, weapon aim/power, magic, prayer)
            handleUpdateEquipmentStats(buf: buf, ws: ws)

        case 156: // loadStats + experience
            handleLoadStats(buf: buf, ws: ws)

        case 33:  // UPDATE_XP
            let skill = buf.getByte()
            let xp = buf.get32()
            ws.updateExperience(skill: skill, xp: xp)

        case 159: // UPDATE_STAT (current level)
            let skill = buf.getByte()
            let level = buf.getByte()
            ws.updateStatCurrent(skill: skill, level: level)

        case 129: // SEND_COMBAT_STYLE
            ws.combatStyle = buf.getByte()

        case 99:  // showGroundItems
            handleShowGroundItems(buf: buf, ws: ws)

        case 5:   // QUEST_STATUS
            let _ = buf.getShort()
            let _ = buf.getByte()

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

        case 204: // playSound
            let _ = buf.getString() // soundName — no audio system yet

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

        default:
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

    private func handleShowPlayers(buf: ByteBuffer, ws: RSCWorldState) {
        let count = buf.getShort()
        var updated: [RSCPlayer] = []
        for _ in 0..<count {
            let pid  = buf.getShort()
            let x    = buf.getShort()
            let y    = buf.getShort()
            let moving = buf.getByte() != 0
            let name = buf.getString()
            let combat = buf.getByte()
            updated.append(RSCPlayer(id: pid, x: x, y: y, name: name, moving: moving, combatLevel: combat))
        }
        ws.players = updated
    }

    private func handleShowNPCs(buf: ByteBuffer, ws: RSCWorldState) {
        let count = buf.getShort()
        var updated: [RSCNPC] = []
        for _ in 0..<count {
            let nid    = buf.getShort()
            let x      = buf.getShort()
            let y      = buf.getShort()
            let npcId  = buf.getShort()
            let name   = buf.getString()
            updated.append(RSCNPC(id: nid, x: x, y: y, npcId: npcId, name: name))
        }
        ws.npcs = updated
    }

    private func handleUpdateInventory(buf: ByteBuffer, ws: RSCWorldState) {
        let count = buf.getShort()
        var items: [RSCInventoryItem] = []
        for i in 0..<count {
            let itemId   = buf.getShort()
            let amount   = buf.get32()
            let equipped = buf.getByte() != 0
            items.append(RSCInventoryItem(id: i, itemId: itemId, amount: amount, equipped: equipped))
        }
        ws.inventory = items
    }

    private func handleUpdateEquipment(buf: ByteBuffer, ws: RSCWorldState) {
        let count = buf.getByte()
        var slots: [RSCEquipmentSlot] = []
        for i in 0..<count {
            let itemId = buf.getShort()
            let amount = buf.get32()
            slots.append(RSCEquipmentSlot(id: i, itemId: itemId, amount: amount))
        }
        ws.equipment = slots
    }

    private func handleUpdateEquipmentStats(buf: ByteBuffer, ws: RSCWorldState) {
        ws.equipmentStats.armourPoints = buf.getShort()
        ws.equipmentStats.weaponAimPoints = buf.getShort()
        ws.equipmentStats.weaponPowerPoints = buf.getShort()
        ws.equipmentStats.magicPoints = buf.getShort()
        ws.equipmentStats.prayerPoints = buf.getShort()
    }

    private func handleShowGroundItems(buf: ByteBuffer, ws: RSCWorldState) {
        var items: [RSCGroundItem] = []
        while buf.bytesRemaining >= 8 {
            let itemId = buf.getShort()
            let x      = buf.getShort()
            let y      = buf.getShort()
            let amount = buf.getShort()
            items.append(RSCGroundItem(x: x, y: y, itemId: itemId, amount: amount))
        }
        ws.groundItems = items
    }

    private func handleShowBank(buf: ByteBuffer, ws: RSCWorldState) {
        // Bank open packet — notify via chat for now; full bank UI is in web client
        ws.addChat(sender: "[System]", text: "Bank opened.")
    }

    private func handleShowShop(buf: ByteBuffer, ws: RSCWorldState) {
        ws.addChat(sender: "[System]", text: "Shop opened.")
    }

    private func handleShowOptionsMenu(buf: ByteBuffer, ws: RSCWorldState) {
        let count = buf.getByte()
        var options: [String] = []
        for _ in 0..<count {
            options.append(buf.getString())
        }
        // Display dialogue options in chat for now
        for (i, opt) in options.enumerated() {
            ws.addChat(sender: "[Option \(i + 1)]", text: opt)
        }
    }

    private func handleLoadStats(buf: ByteBuffer, ws: RSCWorldState) {
        var skills: [RSCSkill] = []
        let count = buf.getByte()
        for i in 0..<count {
            let current = buf.getByte()
            let base    = buf.getByte()
            let exp     = buf.get32()
            skills.append(RSCSkill(id: i, current: current, base: base, experience: exp))
        }
        ws.skills = skills
    }
}
