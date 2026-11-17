import Foundation
import XCTest
@testable import Scape530

/// Touch interaction with the world: picking, menu building, action packets, walking.
final class InteractTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	/// The bytes `m` encodes to with a fresh cipher (seeded 1, 2, 3, 4) and the cipher's first key,
	/// so tests can compare against hand-written payloads.
	func encode(_ m: ClientMessage) -> (bytes: [UInt8], key: Int) {
		var a = IsaacRandom(seed: [1, 2, 3, 4])
		var b = IsaacRandom(seed: [1, 2, 3, 4])
		return (m.encode(&a), b.nextKey())
	}

	func op(_ opcode: Int, _ key: Int) -> UInt8 { UInt8(truncatingIfNeeded: opcode + key) }

	// MARK: packets (no cache needed)

	func testActionPacketLayouts() {
		var (bytes, key) = encode(.opNpc(option: 1, index: 0x1234))
		XCTAssertEqual(bytes, [op(78, key), 0x34, 0x12])
		(bytes, key) = encode(.opNpc(option: 2, index: 0x1234))
		XCTAssertEqual(bytes, [op(3, key), 0x34 &+ 128, 0x12])
		(bytes, key) = encode(.opNpc(option: 3, index: 0x1234))
		XCTAssertEqual(bytes, [op(148, key), 0x12, 0x34 &+ 128])
		(bytes, key) = encode(.opNpc(option: 4, index: 0x1234))
		XCTAssertEqual(bytes, [op(30, key), 0x12, 0x34])
		(bytes, key) = encode(.opLoc(option: 1, id: 0x0102, x: 3222, z: 3218))
		XCTAssertEqual(bytes, [op(254, key), UInt8(3222 & 0xFF), UInt8(3222 >> 8), 0x01, 0x02 &+ 128, UInt8(3218 >> 8), UInt8(3218 & 0xFF)])
		(bytes, key) = encode(.opPlayer(action: 31, index: 7))
		XCTAssertEqual(bytes, [op(71, key), 7 &+ 128, 0])
		(bytes, key) = encode(.songEnd(0x01020304))
		XCTAssertEqual(bytes, [op(137, key), 1, 2, 3, 4])
		(bytes, key) = encode(.examineNpc(typeId: 0x0102))
		XCTAssertEqual(bytes, [op(72, key), 0x01, 0x02])
		(bytes, key) = encode(.examineLoc(id: 0x0102))
		XCTAssertEqual(bytes, [op(94, key), 0x02 &+ 128, 0x01])
		(bytes, key) = encode(.opObj(option: 3, id: 995, x: 100, z: 200))
		XCTAssertEqual(bytes, [op(66, key), 100, 0, UInt8(995 >> 8), UInt8(995 & 0xFF), 200 &+ 128, 0])
	}

	func testWalkInteractMatchesWalkLayout() {
		let (a, ka) = encode(.walk(destX: 3200, destZ: 3210, path: [(3198, 3207)], ctrlRun: false, minimap: false))
		let (b, kb) = encode(.walkInteract(destX: 3200, destZ: 3210, path: [(3198, 3207)], ctrlRun: false))
		XCTAssertEqual(ka, kb)
		XCTAssertEqual(a[0], op(ClientProt.moveGameclick, ka))
		XCTAssertEqual(b[0], op(77, kb))
		XCTAssertEqual(Array(a.dropFirst()), Array(b.dropFirst()))
	}

	func testCombatColoursAndMenuSort() {
		XCTAssertEqual(MenuBuilder.combatLevelColor(other: 2, own: 3), "<col=c0ff00>")
		XCTAssertEqual(MenuBuilder.combatLevelColor(other: 3, own: 3), "<col=ffff00>")
		XCTAssertEqual(MenuBuilder.combatLevelColor(other: 40, own: 3), "<col=ff0000>")
		XCTAssertEqual(MenuBuilder.combatLevelColor(other: 1, own: 30), "<col=00ff00>")
		var m = Menu()
		m.add(op: "Walk here", base: "", action: 60)
		m.add(op: "Examine", base: "<col=ffff00>Man", action: 1007)
		m.add(op: "Talk-to", base: "<col=ffff00>Man", action: 17)
		m.sort()
		XCTAssertEqual(m.entries.map(\.op), ["Cancel", "Examine", "Walk here", "Talk-to"])
		XCTAssertEqual(m.text(m.top), "Talk-to <col=ffff00>Man")
		XCTAssertEqual(m.hoverText, "Talk-to <col=ffff00>Man<col=ffffff> / 2 more options")
	}

	func testTrianglePickMatchesRt4() {
		XCTAssertTrue(ScenePicker.pointInTriangle(3, 3, 0, 10, 0, 0, 0, 10))
		XCTAssertFalse(ScenePicker.pointInTriangle(20, 5, 0, 10, 0, 0, 0, 10))
		XCTAssertFalse(ScenePicker.pointInTriangle(9, 9, 0, 10, 0, 0, 0, 10))
	}

	// MARK: replayed session

	/// Feeds the recorded resizable session into the client (as `WorldViewTests.replay`).
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

	func startedClient(width: Int = 1015, height: Int = 469) throws -> (GameClient, [ClientMessage]) {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		try replay(client)
		_ = try client.frame(width: width, height: height)
		_ = try client.frame(width: width, height: height)
		return (client, [])
	}

	/// Projects a point of the scene to game pixels the way the scene draw does (test helper).
	func project(_ client: GameClient, xFine: Int, yFine: Int, zFine: Int) -> (Int, Int)? {
		guard let v = client.viewport, let me = client.world.selfActor, let scene = client.world.scene else { return nil }
		let groundY = scene.tileHeight(level: scene.centralPlane, xFine: me.xFine, zFine: me.zFine)
		let eye = client.world.camera.eye(groundY: groundY)
		let sinP = MathTables.sin[eye.pitch & 2047], cosP = MathTables.cos[eye.pitch & 2047]
		let sinY = MathTables.sin[eye.yaw & 2047], cosY = MathTables.cos[eye.yaw & 2047]
		let dx = xFine - eye.x, dy = yFine - eye.y, dz = zFine - eye.z
		let xr = (dz * sinY + dx * cosY) >> 16
		let zr = (dz * cosY - dx * sinY) >> 16
		let yv = (dy * cosP - zr * sinP) >> 16
		let zv = (dy * sinP + zr * cosP) >> 16
		guard zv > 50 else { return nil }
		return (v.x + v.w / 2 + (xr << 9) / zv, v.y + v.h / 2 + (yv << 9) / zv)
	}

	func testLoadsCollisionAndPicksTiles() throws {
		let (client, _) = try startedClient()
		let world = client.world
		XCTAssertEqual(world.collision.count, 4)
		let me = try XCTUnwrap(world.selfSceneTile)
		// The player's own tile is walkable; some tiles in the scene are blocked by locs or water.
		let flags = world.collision[world.plane]
		var blocked = 0
		for x in 10..<94 { for z in 10..<94 where !flags.isWalkableForTest(x, z) { blocked += 1 } }
		print("scene \(world.plane): self at \(me), \(blocked) blocked tiles of 7056")
		XCTAssertGreaterThan(blocked, 20)
		XCTAssertTrue(flags.isWalkableForTest(me.x, me.z))

		// A tile pick a little below the player lands near the player.
		let v = try XCTUnwrap(client.viewport)
		let pick = try XCTUnwrap(world.pick(x: v.x + v.w / 2, y: v.y + v.h / 2 + 60, rect: v))
		let t = try XCTUnwrap(pick.tile)
		print("pick below player: tile \(t), self \(me), hits \(pick.hits.count)")
		XCTAssertLessThan(abs(t.x - me.x), 6)
		XCTAssertLessThan(abs(t.z - me.z), 6)
	}

	/// LOC_DEL / LOC_ADD packets change both the scene and the collision map; ground items are tracked.
	func testZoneUpdatesChangeLocsAndCollision() throws {
		let (client, _) = try startedClient()
		let world = client.world
		let scene = try XCTUnwrap(world.scene)
		let plane = world.plane
		// A solid scenery loc.
		var found: (x: Int, z: Int, key: Int64)?
		search: for x in 8..<96 { for z in 8..<96 {
			let k = scene.sceneryKey(level: plane, x: x, z: z)
			if k != 0, let t = try store().loc(Int((k >> 32) & 0x7FFF_FFFF)), t.blockWalk != 0, t.width == 1, t.length == 1, ((k >> 14) & 0x1F) == 10 { found = (x, z, k); break search }
		} }
		let loc = try XCTUnwrap(found, "no 1x1 solid scenery in the scene")
		let id = Int((loc.key >> 32) & 0x7FFF_FFFF), rot = Int((loc.key >> 20) & 3)
		let map = world.collision[plane]
		XCTAssertFalse(map.isWalkableForTest(loc.x, loc.z))
		world.handle(.message(.zonePartialFollows(chunkX: loc.x, chunkZ: loc.z)), varps: [:])
		world.handle(.message(.zoneUpdate(.locDel(x: 0, z: 0, shape: 10, rotation: rot))), varps: [:])
		XCTAssertEqual(scene.sceneryKey(level: plane, x: loc.x, z: loc.z), 0)
		XCTAssertTrue(map.isWalkableForTest(loc.x, loc.z))
		world.handle(.message(.zoneUpdate(.locAdd(x: 0, z: 0, id: id, shape: 10, rotation: rot))), varps: [:])
		XCTAssertNotEqual(scene.sceneryKey(level: plane, x: loc.x, z: loc.z), 0)
		XCTAssertFalse(map.isWalkableForTest(loc.x, loc.z))

		// Ground items: add, count change, delete.
		world.handle(.message(.zoneUpdate(.objAdd(x: 0, z: 0, id: 995, count: 50, hiddenFrom: -1))), varps: [:])
		XCTAssertEqual(world.groundObjects(x: loc.x, z: loc.z), [GroundObj(type: 995, amount: 50)])
		world.handle(.message(.zoneUpdate(.objCount(x: 0, z: 0, id: 995, oldCount: 50, newCount: 75))), varps: [:])
		XCTAssertEqual(world.groundObjects(x: loc.x, z: loc.z).first?.amount, 75)
		var menu = Menu()
		MenuBuilder.addObjs(&menu, world: world, x: loc.x, z: loc.z)
		print("ground item menu: \((0..<menu.count).map { menu.text($0) })")
		XCTAssertTrue(menu.entries.contains { $0.op == "Take" && $0.action == 18 })
		world.handle(.message(.zoneUpdate(.objDel(x: 0, z: 0, id: 995))), varps: [:])
		XCTAssertTrue(world.groundObjects(x: loc.x, z: loc.z).isEmpty)
	}

	func testTapWalksAndSendsPacket() throws {
		let (client, _) = try startedClient()
		var sent: [ClientMessage] = []
		client.interaction.onSend = { sent.append($0) }
		let v = try XCTUnwrap(client.viewport)
		let me = try XCTUnwrap(client.world.selfSceneTile)
		// Find a point whose default action is "Walk here" on a walkable tile (nothing else under it).
		var target: (x: Int, y: Int, tile: (x: Int, z: Int))?
		search: for dy in stride(from: 70, through: 150, by: 10) {
			for dx in stride(from: -200, through: 200, by: 25) {
				let px = v.x + v.w / 2 + dx, py = v.y + v.h / 2 + dy
				guard client.isOverWorld(x: px, y: py), let (m, pick) = client.buildMenu(x: px, y: py), let t = pick.tile else { continue }
				if m.entries[m.top].action == Menu.Action.walkHere, abs(t.x - me.x) + abs(t.z - me.z) >= 3,
				   client.world.collision[client.world.plane].isWalkableForTest(t.x, t.z) {
					target = (px, py, t); break search
				}
			}
		}
		let tgt = try XCTUnwrap(target)
		client.tap(x: tgt.x, y: tgt.y)
		let msg = try XCTUnwrap(sent.first)
		guard case let .walk(destX, destZ, path, _, minimap) = msg else { return XCTFail("expected a walk, got \(msg)") }
		XCTAssertFalse(minimap)
		let o = client.world.origin
		XCTAssertEqual(destX, o.x + tgt.tile.x)
		XCTAssertEqual(destZ, o.z + tgt.tile.z)
		// Packet bytes: opcode 215, size, run flag, first waypoint absolute, the rest as offsets.
		let (bytes, key) = encode(msg)
		XCTAssertEqual(bytes[0], op(ClientProt.moveGameclick, key))
		XCTAssertEqual(Int(bytes[1]), (path.count + 1) * 2 + 3)
		XCTAssertEqual(bytes[2], 128) // not running
		let first = path.first ?? (x: destX, z: destZ)
		XCTAssertEqual(Int(bytes[3]) << 8 | Int(bytes[4]), first.x)
		XCTAssertEqual(Int(bytes[5]) << 8 | Int(bytes[6] &- 128), first.z)
		XCTAssertEqual(client.interaction.cross.type, 1)
		XCTAssertEqual(client.world.destinationFlag?.x, tgt.tile.x)
		print("walk packet \(bytes) to \(destX),\(destZ) via \(path.count) turns")
		var r = try client.frame(width: 1015, height: 469)
		try save(r, "interact-walk-cross")
		// The cross animates and goes away after 400 ms (20 cycles).
		for _ in 0..<25 { client.interaction.cycle() }
		XCTAssertEqual(client.interaction.cross.type, 0)
		r = try client.frame(width: 1015, height: 469)
	}

	func testLongPressOnNpcOpensMenu() throws {
		let (client, _) = try startedClient()
		let world = client.world
		var found: (id: Int, x: Int, y: Int)?
		for (id, a) in world.ctx.npcs.sorted(by: { $0.key < $1.key }) {
			guard let t = a.npcType, t.interactive, t.ops.contains(where: { $0 != nil }) else { continue }
			guard let p = project(client, xFine: a.xFine, yFine: a.groundY - 60, zFine: a.zFine), client.isOverWorld(x: p.0, y: p.1) else { continue }
			guard let (_, pick) = client.buildMenu(x: p.0, y: p.1), pick.hits.contains(Int64(id) << 32 | 0x2000_0000) else { continue }
			found = (id, p.0, p.1); break
		}
		let npc = try XCTUnwrap(found, "no pickable npc on screen; npcs: \(world.ctx.npcs.count)")
		XCTAssertTrue(client.longPress(x: npc.x, y: npc.y))
		let popup = try XCTUnwrap(client.interaction.popup)
		let type = try XCTUnwrap(world.ctx.npcs[npc.id]?.npcType)
		let lines = (0..<popup.menu.count).map { popup.menu.text($0) }
		print("menu for \(type.name): \(lines)")
		XCTAssertEqual(popup.menu.entries[0].op, "Cancel")
		XCTAssertTrue(lines.contains { $0.hasPrefix("Examine <col=ffff00>\(type.name)") })
		let firstOp = try XCTUnwrap(type.ops.compactMap { $0 }.first { $0.lowercased() != "attack" } ?? type.ops.compactMap { $0 }.first)
		XCTAssertTrue(lines.contains { $0.hasPrefix("\(firstOp) <col=ffff00>\(type.name)") }, "\(lines)")
		XCTAssertTrue(lines.contains { $0.hasPrefix("Walk here") })
		let r = try client.frame(width: 1015, height: 469)
		try save(r, "interact-menu")

		// Tapping the Examine row sends the examine packet with the npc's type id.
		var sent: [ClientMessage] = []
		client.interaction.onSend = { sent.append($0) }
		let examine = try XCTUnwrap(popup.menu.entries.firstIndex { $0.action == Menu.Action.npcExamine && Int($0.key) == npc.id })
		let rowY = (popup.menu.count - examine - 1) * 15 + popup.y + 31 - 5
		client.tap(x: popup.x + 10, y: rowY)
		XCTAssertNil(client.interaction.popup)
		XCTAssertEqual(sent.count, 1)
		if case let .examineNpc(id) = sent[0] { XCTAssertEqual(id, type.id) } else { XCTFail("sent \(sent)") }
	}

	func testTalkToNpcWalksThenSendsOp() throws {
		let (client, _) = try startedClient()
		let world = client.world
		var sent: [ClientMessage] = []
		client.interaction.onSend = { sent.append($0) }
		for (id, a) in world.ctx.npcs.sorted(by: { $0.key < $1.key }) {
			guard let t = a.npcType, t.interactive, t.ops[0] != nil, t.ops[0]?.lowercased() != "attack" else { continue }
			guard let p = project(client, xFine: a.xFine, yFine: a.groundY - 60, zFine: a.zFine), client.isOverWorld(x: p.0, y: p.1) else { continue }
			guard let (m, _) = client.buildMenu(x: p.0, y: p.1), m.entries[m.top].action == 17 else { continue }
			client.tap(x: p.0, y: p.1)
			XCTAssertEqual(client.interaction.cross.type, 2)
			XCTAssertEqual(sent.last.map { if case .opNpc(1, id) = $0 { return true } else { return false } }, true, "\(sent)")
			let (bytes, key) = encode(sent.last!)
			XCTAssertEqual(bytes, [op(78, key), UInt8(id & 0xFF), UInt8(id >> 8)])
			if sent.count == 2, case .walkInteract = sent[0] { print("walked towards npc \(id) first") }
			return
		}
		XCTFail("no npc with a default Talk-to on screen")
	}

	/// Logs in to a live server (`SCAPE530_SERVER=host:port`), taps a tile a few tiles away and waits for the
	/// player to walk there.
	func testLiveTapToWalk() throws {
		let env = ProcessInfo.processInfo.environment
		guard let server = env["SCAPE530_SERVER"] else { throw XCTSkip("needs SCAPE530_SERVER") }
		let parts = server.split(separator: ":")
		let client = try GameClient(store: try store(), server: .init(host: String(parts[0]), port: Int(parts[1]) ?? 43595))
		let (w, h) = (1015, 469)
		_ = try client.frame(width: w, height: h)
		let d = try XCTUnwrap(client.ui.drawn.last { $0.component.id == client.loginInterface << 16 | 250 })
		client.tap(x: d.x + d.w / 2, y: d.y + d.h / 2)
		// A fresh account every run: a reused one keeps wherever the last run left it (possibly walled in on Tutorial Island).
		client.type("interact\(Int.random(in: 1000...9999))\ntester\n")
		let deadline = Date().addingTimeInterval(20)
		var r = try client.frame(width: w, height: h)
		while Date() < deadline && (client.screen != .game || client.state.ticks < 12) {
			Thread.sleep(forTimeInterval: 0.02)
			r = try client.frame(width: w, height: h)
		}
		XCTAssertEqual(client.screen, .game, "status: \(client.status)")
		let settle = Date().addingTimeInterval(2)
		while Date() < settle { Thread.sleep(forTimeInterval: 0.02); r = try client.frame(width: w, height: h) }
		// A fresh account starts on Tutorial Island behind the "mouse style" screen: answer it so movement is allowed.
		// Fresh accounts start on Tutorial Island behind the character design screens: accept the defaults.
		for step in 0..<8 where client.state.interfaces.open.values.contains(771) || client.state.interfaces.open.count > 0 {
			let buttons = client.ui.drawn.filter { $0.component.ops.first.map { ["select next", "confirm changes"].contains($0.lowercased()) } ?? false }
			print("design step \(step): \(client.ui.drawn.compactMap { $0.component.ops.first }.filter { !$0.isEmpty }.prefix(12))")
			guard let c = buttons.first else { break }
			client.tap(x: c.x + c.w / 2, y: c.y + c.h / 2)
			let t = Date().addingTimeInterval(1.2)
			while Date() < t { Thread.sleep(forTimeInterval: 0.02); r = try client.frame(width: w, height: h) }
		}
		// The server's position for the player (the drawn actor lags behind while frames render slowly in debug builds).
		func position() -> (x: Int, z: Int)? { client.state.selfWorld.map { ($0.x, $0.z) } }
		let before = try XCTUnwrap(position())
		try save(r, "interact-live-before")

		// Pick a tap point whose default action is "Walk here" a few tiles away.
		let v = try XCTUnwrap(client.viewport)
		let me = try XCTUnwrap(client.world.selfSceneTile)
		var target: (x: Int, y: Int, tile: (x: Int, z: Int))?
		// Scan the whole viewport: the spawn point varies and scenery (a tree) can hide the area near the player.
		search: for dy in stride(from: -v.h / 2 + 20, through: v.h / 2 - 20, by: 10) {
			for dx in stride(from: -v.w / 2 + 20, through: v.w / 2 - 20, by: 15) {
				let px = v.x + v.w / 2 + dx, py = v.y + v.h / 2 + dy
				guard client.isOverWorld(x: px, y: py), let (m, pick) = client.buildMenu(x: px, y: py), let t = pick.tile else { continue }
				let dist = abs(t.x - me.x) + abs(t.z - me.z)
				if m.entries[m.top].action == Menu.Action.walkHere, dist >= 4, dist <= 9,
				   client.world.collision[client.world.plane].isWalkableForTest(t.x, t.z) {
					target = (px, py, t); break search
				}
			}
		}
		let tgt = try XCTUnwrap(target, "no walkable tile in view")
		var sent: [ClientMessage] = []
		client.interaction.onSend = { sent.append($0) }
		client.tap(x: tgt.x, y: tgt.y)
		print("live: tapped scene tile \(tgt.tile) from \(me), sent \(sent.count) message(s)")
		XCTAssertEqual(sent.count, 1)
		let until = Date().addingTimeInterval(5)
		var moved = false
		while Date() < until {
			Thread.sleep(forTimeInterval: 0.02)
			r = try client.frame(width: w, height: h)
			if let t = position(), t != before { moved = true }
			let o = client.world.origin
			if let t = position(), t == (x: o.x + tgt.tile.x, z: o.z + tgt.tile.z) { break }
		}
		let after = try XCTUnwrap(position())
		print("live: before \(before) after \(after)")
		try save(r, "interact-live-after")
		XCTAssertTrue(moved, "the player did not move")
		let o = client.world.origin
		XCTAssertEqual(after.x, o.x + tgt.tile.x)
		XCTAssertEqual(after.z, o.z + tgt.tile.z)
		client.logout()
	}
}

extension CollisionMap {
	/// No solid scenery, ground decor or blocked floor on the tile (test helper).
	func isWalkableForTest(_ x: Int, _ z: Int) -> Bool { (self[x, z] & (Flag.scenery | Flag.groundDecor | Flag.floorBlocked | Flag.sceneryProjectile | Flag.outside)) == 0 }
}
