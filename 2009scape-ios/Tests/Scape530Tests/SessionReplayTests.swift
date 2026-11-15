import XCTest
@testable import Scape530

/// Replays a game session recorded from a live 2009scape server with
/// `PROBE_RECORD=... scape530-probe login` (two players on Tutorial Island,
/// then a ::tele to Lumbridge, ::item spawns and an ::anim). Every packet must
/// decode strictly, and the entity decoders must stay in sync for the whole run.
final class SessionReplayTests: XCTestCase {
	func packets() throws -> [GamePacket] {
		let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/login-session", withExtension: "bin"))
		var p = Packet([UInt8](try Data(contentsOf: url)))
		var out: [GamePacket] = []
		while p.remaining > 0 {
			let op = try p.g1()
			let len = Int(try p.g4())
			out.append(GamePacket(opcode: op, payload: try p.gdata(len)))
		}
		return out
	}

	func testEveryRecordedPacketDecodes() throws {
		let all = try packets()
		XCTAssertGreaterThan(all.count, 400)
		XCTAssertEqual(all[0].opcode, ServerProt.rebuildNormal)
		let first = try RebuildNormal(payload: all[0].payload)
		var players = PlayerInfoDecoder(selfIndex: 11, localX: first.localX, localZ: first.localZ)
		var npcs = NpcInfoDecoder()
		var zone = (first.zoneX, first.zoneZ)
		var names: Set<String> = []
		var npcTypes: Set<Int> = []
		var inventory: [Int: ServerMessage.InvItem] = [:]
		var rebuilds = 0

		for pkt in all {
			switch pkt.opcode {
			case ServerProt.playerInfo:
				let r = try players.decode(pkt.payload)
				for m in r.updated.values { if let n = m.appearance?.name { names.insert(n) } }
			case ServerProt.npcInfo:
				let me = players.players[players.selfIndex]!
				_ = try npcs.decode(pkt.payload, selfX: me.x, selfZ: me.z)
				npcs.npcs.values.forEach { npcTypes.insert($0.type) }
			default:
				let msg = try ServerMessage.decode(pkt)
				if case .unhandled(let op, _) = msg { XCTFail("opcode \(op) not decoded") }
				if case .rebuildNormal(let r) = msg {
					rebuilds += 1
					players.rebase(dx: (r.zoneX - zone.0) * 8, dz: (r.zoneZ - zone.1) * 8)
					npcs.rebase(dx: (r.zoneX - zone.0) * 8, dz: (r.zoneZ - zone.1) * 8)
					zone = (r.zoneX, r.zoneZ)
				}
				if case .invPartial(_, 93, let slots) = msg {
					for s in slots { inventory[s.slot] = s.item }
				}
			}
		}
		XCTAssertEqual(rebuilds, 3) // login reply, the server's repeat right after login, ::tele
		XCTAssertTrue(names.isSuperset(of: ["walker3", "buddy2"]), "\(names)")
		XCTAssertTrue(npcTypes.contains(0), "Hans (npc 0) stands by Lumbridge castle")
		XCTAssertEqual(inventory[0], .init(id: 1351, count: 1)) // bronze axe
		XCTAssertEqual(inventory[1], .init(id: 995, count: 5000)) // coins
	}
}
