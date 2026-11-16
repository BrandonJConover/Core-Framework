import Foundation
import XCTest
@testable import Scape530

/// Item icons (rt4 `Inv.renderObjectSprite`), inventory interfaces and ground item piles.
final class ItemsTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	func testFormatAmount() {
		XCTAssertEqual(ItemIcons.formatAmount(5), "<col=ffff00>5</col>")
		XCTAssertEqual(ItemIcons.formatAmount(99_999), "<col=ffff00>99999</col>")
		XCTAssertEqual(ItemIcons.formatAmount(100_000), "<col=ffffff>100K</col>")
		XCTAssertEqual(ItemIcons.formatAmount(9_999_999), "<col=ffffff>9999K</col>")
		XCTAssertEqual(ItemIcons.formatAmount(10_000_000), "<col=00ff80>10M</col>")
	}

	func testOutlineAndShadow() {
		// A single drawn pixel in the middle of a 5x5 canvas.
		var px = [Int](repeating: 0, count: 25)
		px[12] = 0x123456
		let o = ItemIcons.outline(px, 5, 5, 1)
		XCTAssertEqual([7, 11, 13, 17].map { o[$0] }, [1, 1, 1, 1])
		XCTAssertEqual(o[6], 0) // diagonals are not outlined
		var s = px
		ItemIcons.dropShadow(&s, 5, 5, 0x302020)
		XCTAssertEqual(s[18], 0x302020) // down-right of the pixel
		XCTAssertEqual(s[13], 0)
	}

	func testContactSheet() throws {
		let s = try store()
		let icons = ItemIcons(store: s)
		// (id, count, label): bronze axe, coins in each count colour band, a noted item, shields, runes.
		// The noted version of lobster (379): the object whose certlink is 379.
		let noted = try XCTUnwrap((0..<30000).first { id in ((try? s.obj(id)) ?? nil).map { $0.certtemplate >= 0 && $0.certlink == 379 } ?? false })
		let wanted: [(Int, Int)] = [(1351, 1), (995, 1), (995, 5), (995, 100), (995, 100_000), (995, 10_000_000), (noted, 25), (1171, 1), (1127, 1), (554, 40), (555, 1000), (1265, 1), (379, 3), (1511, 1), (385, 1), (4151, 1)]
		var sheet = Raster(width: 8 * 44 + 8, height: 2 * 40 + 8, fill: 0x3E3529)
		var drawn = 0
		for (i, (id, count)) in wanted.enumerated() {
			guard let icon = icons.sprite(selected: 1, id: id, drawText: true, count: count, shadow: 0x302020) else { print("no icon for \(id)"); continue }
			XCTAssertGreaterThan(icon.pixels.filter { $0 != 0 }.count, 80, "icon \(id) is nearly empty")
			sheet.draw(icon, x: 8 + (i % 8) * 44, y: 8 + (i / 8) * 40)
			drawn += 1
		}
		XCTAssertEqual(drawn, wanted.count)
		// Noted items show the note paper with the item drawn on it.
		let n = try XCTUnwrap(try s.objResolved(noted))
		XCTAssertTrue(n.stackable)
		// Scaled 4x for looking at.
		var big = Raster(width: sheet.width * 4, height: sheet.height * 4)
		for y in 0..<big.height { for x in 0..<big.width { big.pixels[y * big.width + x] = sheet.pixels[(y / 4) * sheet.width + x / 4] } }
		try save(big, "items-icons-x4")
		try save(sheet, "items-icons")
	}

	func testCountVariants() throws {
		let s = try store()
		let coins = try XCTUnwrap(try s.objResolved(995))
		XCTAssertNotNil(coins.countObj)
		XCTAssertNotEqual(try s.objForCount(coins, 1).id, try s.objForCount(coins, 10_000).id)
	}

	// Copied from MinimapTests.
	func replay(_ client: GameClient, cyclesPerTick: Int = 30) throws {
		let me = 2047
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: me, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		var players = PlayerInfoDecoder(selfIndex: me, localX: 52, localZ: 52)
		var npcs = NpcInfoDecoder()
		var zone: (x: Int, z: Int)?
		for pkt in try SessionReplayTests.recordedPackets("resizable-session") {
			switch pkt.opcode {
			case ServerProt.playerInfo:
				let r = try players.decode(pkt.payload)
				client.handle(.players(r, players))
				for _ in 0..<cyclesPerTick { client.world.cycle(varps: client.state.varps) }
			case ServerProt.npcInfo:
				let p = try XCTUnwrap(players.players[me])
				let r = try npcs.decode(pkt.payload, selfX: p.x, selfZ: p.z)
				client.handle(.npcs(r, npcs))
			default:
				let m = try ServerMessage.decode(pkt)
				if case .rebuildNormal(let r) = m {
					if let z = zone {
						players.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
						npcs.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
					} else {
						players = PlayerInfoDecoder(selfIndex: me, localX: r.localX, localZ: r.localZ)
					}
					zone = (r.zoneX, r.zoneZ)
				}
				client.handle(.message(m))
			}
		}
	}

	func testInventoryAndGroundItemsInGame() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		try replay(client)
		var r = try client.frame(width: 1015, height: 469)
		// The server opens interface 149 into a tab container (746:93 is the one the tutorial leaves visible); fill it like UPDATE_INV_FULL.
		let comp = 149 << 16
		let items: [ServerMessage.InvItem] = [(1351, 1), (995, 250_000), (1171, 1), (554, 40), (379, 3), (1265, 1), (385, 12), (4151, 1), (995, 7)].map { ServerMessage.InvItem(id: $0.0, count: Int32($0.1)) }
			+ [ServerMessage.InvItem](repeating: ServerMessage.InvItem(id: -1, count: 0), count: 19)
		client.handle(.message(.ifOpenSub(parent: Int32(746 << 16 | 93), component: 149, type: 1)))
		client.handle(.message(.invFull(component: Int32(comp), inv: 93, items: items)))
		r = try client.frame(width: 1015, height: 469)
		XCTAssertEqual(client.state.interfaces.invSlots[comp]?.count, 9)
		XCTAssertNotNil(client.ui.drawn.first { $0.component.id == comp }, "inventory component was not drawn")
		try save(r, "items-frame-inventory")

		// Ground items: a pile of three on a tile near the player.
		let w = client.world
		let me = try XCTUnwrap(w.selfTile)
		let tx = me.x - w.origin.x + 1, tz = me.z - w.origin.z
		client.handle(.message(.zonePartialFollows(chunkX: tx & ~7, chunkZ: tz & ~7)))
		for (id, n) in [(995, 3000), (1351, 1), (554, 20)] {
			client.handle(.message(.zoneUpdate(.objAdd(x: tx & 7, z: tz & 7, id: id, count: n, hiddenFrom: -1))))
		}
		XCTAssertEqual(w.groundObjects(x: tx, z: tz).count, 3)
		let stack = try XCTUnwrap(w.scene?.tiles[w.plane][tx][tz]?.objStack)
		XCTAssertNotNil(stack.primary)
		XCTAssertNotNil(stack.secondary)
		XCTAssertNotNil(stack.tertiary)
		client.cameraPinch(scale: 2.0)
		r = try client.frame(width: 1015, height: 469)
		try save(r, "items-frame-ground")
		// The world alone (no dialog on top), camera pulled in over the pile.
		client.world.camera.pitchTarget = 300
		for _ in 0..<60 { client.world.cycle(varps: client.state.varps) }
		var worldOnly = Raster(width: 640, height: 400)
		XCTAssertTrue(client.world.draw(into: &worldOnly, rect: (0, 0, 640, 400)))
		try save(worldOnly, "items-world-ground")
		// Removing them clears the pile.
		for id in [995, 1351, 554] { client.handle(.message(.zoneUpdate(.objDel(x: tx & 7, z: tz & 7, id: id)))) }
		XCTAssertNil(w.scene?.tiles[w.plane][tx][tz]?.objStack)
	}
}
