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
        case 131: // chatMessage — showMessage()
            let sender = buf.getString()
            let text   = buf.getString()
            ws.addChat(sender: sender, text: text)

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

        case 156: // loadStats + experience
            handleLoadStats(buf: buf, ws: ws)

        case 149: // connectionMessage (login/logout notice)
            let _ = buf.getString() // player name
            let _ = buf.getByte()   // logged in flag

        case 4:   // closeConnection
            break

        case 183: // cantLogout
            break

        default:
            break
        }
    }

    // MARK: - Packet parsers (matching PacketHandler.java methods)

    private func handleServerConfig(buf: ByteBuffer, ws: RSCWorldState) {
        let count = buf.getShort()
        for _ in 0..<count {
            let key = buf.getString()
            let value = buf.getString()
            if key == "SERVER_NAME" { ws.serverName = value }
        }
    }

    private func handleShowPlayers(buf: ByteBuffer, ws: RSCWorldState) {
        // showOtherPlayers packet: count, then for each: [short id, short x, short y, byte moving, string name, byte combatLevel]
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

    private func handleLoadStats(buf: ByteBuffer, ws: RSCWorldState) {
        var skills: [RSCSkill] = []
        let count = buf.getByte()
        for i in 0..<count {
            let level = buf.getByte()
            let exp   = buf.get32()
            skills.append(RSCSkill(id: i, level: level, experience: exp))
        }
        ws.skills = skills
    }
}
