import Foundation
import XCTest
@testable import Scape530

/// The minimap: image built from the scene, drawn rotated into the interface-746 component with dots,
/// compass and flag, and mapped back from taps. Uses the recorded resizable session.
final class MinimapTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	// Copied from WorldViewTests (XCTestCase has no plain init on Linux).
	/// Feeds the recorded session (rebuilds, player and npc info) into a `GameClient` as session
	/// events, running 30 client cycles per player-info tick the way a live game would.
	func replay(_ client: GameClient, cyclesPerTick: Int = 30) throws {
		let me = 2047 // the first player-info section is always the local player
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

	func testShapedTilePatterns() {
		// Every shape row has 16 entries and every rotation is a permutation of 0..15.
		for row in MinimapImage.shapeMask { XCTAssertEqual(row.count, 16) }
		for row in MinimapImage.rotationOrder { XCTAssertEqual(Set(row), Set(0..<16)) }
	}

	func testReplayMinimap() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		try replay(client)
		var r = try client.frame(width: 1015, height: 469)
		r = try client.frame(width: 1015, height: 469)
		let mm = client.world.minimap
		let p = try XCTUnwrap(mm.placement, "minimap component not found")
		print("minimap component \(p.x),\(p.y) \(p.w)x\(p.h); icons \(mm.image.icons.count); friends \(mm.friends.count)")
		try save(r, "minimap-frame-1015x469")

		// A crop of the component, enlarged 3x.
		var crop = Raster(width: p.w * 3, height: p.h * 3)
		for y in 0..<crop.height { for x in 0..<crop.width { crop.pixels[y * crop.width + x] = r.pixels[(p.y + y / 3) * r.width + p.x + x / 3] } }
		try save(crop, "minimap-component-x3")

		// The raw static image, the part around Lumbridge's castle (scene is 104 tiles = 416 px).
		var raw = Raster(width: 512, height: 512)
		for i in 0..<raw.pixels.count { raw.pixels[i] = 0xFF00_0000 | mm.image.pixels[i] }
		try save(raw, "minimap-raw")

		// The centre of the map is the player's own tile, and the mapping is monotone with distance.
		let me = try XCTUnwrap(client.world.selfTile)
		let cx = p.x + p.w / 2, cy = p.y + p.h / 2
		let c = try XCTUnwrap(client.minimapTileAt(x: cx, y: cy))
		XCTAssertEqual(c.tileX, me.x)
		XCTAssertEqual(c.tileZ, me.z)
		client.world.camera.yawTarget = 0
		let east = try XCTUnwrap(client.minimapTileAt(x: cx + 40, y: cy))
		XCTAssertLessThanOrEqual(abs(east.tileX - me.x - 10), 1)
		let north = try XCTUnwrap(client.minimapTileAt(x: cx, y: cy - 40))
		XCTAssertLessThanOrEqual(abs(north.tileZ - me.z - 10), 1)
		XCTAssertNil(client.minimapTileAt(x: p.x - 5, y: p.y - 5))

		// Turned camera and a destination flag.
		client.world.camera.yawTarget = 300
		client.minimapDestination = (me.x + 5, me.z + 3)
		r = try client.frame(width: 1015, height: 469)
		try save(r, "minimap-frame-rotated")
	}
}
