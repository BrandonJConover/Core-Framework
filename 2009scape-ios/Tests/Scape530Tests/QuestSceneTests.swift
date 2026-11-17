import XCTest
@testable import Scape530

/// The quest helper drawing into a real cache scene (the recorded session of `PluginSceneTests`; needs `SCAPE530_CACHE`).
final class QuestSceneTests: XCTestCase {

	struct Setup {
		var client: GameClient
		var plugin: QuestHelperPlugin
		var npc: PathingActor
		var world: QuestTile
		var screen: ScreenPoint
	}

	/// A started client with a quest whose only step targets a visible npc of the scene.
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	/// The recorded resizable session fed into a client, as `InteractTests.startedClient`.
	func startedClient(width: Int = 1015, height: Int = 469) throws -> GameClient {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
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
				for _ in 0..<30 { client.world.cycle(varps: client.state.varps) }
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
		_ = try client.frame(width: width, height: height)
		_ = try client.frame(width: width, height: height)
		return client
	}

	func makeSetup(target: ((QuestTile, Int, String) -> QuestTarget)? = nil, varp: Int = 1) throws -> Setup {
		let client = try startedClient()
		let w = client.world
		let ctx = client.plugins.context
		let canvas = OverlayCanvas(world: w, viewport: client.overlayRect, ctx: ctx)
		let me = try XCTUnwrap(ctx.selfActor)
		// The visible npc closest to the player.
		var best: (PathingActor, ScreenPoint, Int)?
		for (_, a) in w.ctx.npcs.sorted(by: { $0.key < $1.key }) {
			guard let t = a.npcType, !t.name.isEmpty, a.size == 1, let p = canvas.project(xFine: a.xFine, zFine: a.zFine, height: 220), QuestMarkerMath.onScreen(p, viewport: canvas.viewport, margin: 30) else { continue }
			let d = abs(a.queueX[0] - me.tileX) + abs(a.queueZ[0] - me.tileZ)
			if best == nil || d < best!.2 { best = (a, p, d) }
		}
		let (npc, screen, _) = try XCTUnwrap(best, "an npc on screen in the recorded scene")
		let id = try XCTUnwrap(npc.npcType?.id), name = try XCTUnwrap(npc.npcType?.name)
		let tile = QuestTile(w.origin.x + npc.queueX[0], w.origin.z + npc.queueZ[0], w.plane)
		let tgt = target?(tile, id, name) ?? QuestTarget.npc(name: name, ids: [id], at: tile)
		let def = QuestDef(id: "test", name: "Test Quest", serverIndex: 1, points: 1, source: QuestStatusSource(varp: 9999, complete: [2]),
			steps: [QuestStep("only", "Talk to \(name) nearby.", targets: [tgt], items: [QuestItem(1735, "Shears")])])
		// The built-in instance (a second registration of the same id is ignored); give it the test catalog.
		let plugin = try XCTUnwrap(client.plugins.plugin(ofType: QuestHelperPlugin.self))
		plugin.catalog = [def]
		client.plugins.setEnabled(true, id: "questHelper")
		var f = QuestFactsSnapshot(); f.varps[9999] = varp
		plugin.testFacts = f
		plugin.refresh(ctx)
		return Setup(client: client, plugin: plugin, npc: npc, world: tile, screen: screen)
	}

	func differing(_ a: Raster, _ b: Raster, in r: (x: Int, y: Int, w: Int, h: Int)) -> Int {
		var n = 0
		for y in max(r.y, 0)..<min(r.y + r.h, a.height) { for x in max(r.x, 0)..<min(r.x + r.w, a.width) where a.pixels[y * a.width + x] != b.pixels[y * a.width + x] { n += 1 } }
		return n
	}

	func count(_ r: Raster, _ rgb: UInt32, in rect: (x: Int, y: Int, w: Int, h: Int)) -> Int {
		var n = 0
		for y in max(rect.y, 0)..<min(rect.y + rect.h, r.height) { for x in max(rect.x, 0)..<min(rect.x + rect.w, r.width) where r.pixels[y * r.width + x] == 0xFF000000 | rgb { n += 1 } }
		return n
	}

	func testTargetNpcIsHighlightedWhenOnScreen() throws {
		let s = try makeSetup()
		let step = try XCTUnwrap(s.plugin.evaluation?.step)
		XCTAssertEqual(step.id, "only")
		var base = try s.client.frame(width: 1015, height: 469)
		// Plugin on: the frame itself already ran the overlays, so compare against the same frame with it off.
		s.client.plugins.setEnabled(false, id: "questHelper")
		base = try s.client.frame(width: 1015, height: 469)
		s.client.plugins.setEnabled(true, id: "questHelper")
		var on = base
		s.client.plugins.drawOverlays(.scene, into: &on)
		let box = (x: s.screen.x - 50, y: s.screen.y - 20, w: 100, h: 130)
		XCTAssertGreaterThan(differing(base, on, in: box), 150, "footprint fill and arrow near the npc at \(s.screen)")
		XCTAssertGreaterThan(count(on, QuestHelperPlugin.targetColour, in: box), 20, "the outline is the solid target colour")
		// Nothing was drawn far from the npc (the screen corner).
		XCTAssertEqual(differing(base, on, in: (0, 0, 120, 60)), 0)
		// The edge arrow only appears for off-screen targets.
		let c = OverlayCanvas(world: s.client.world, viewport: s.client.overlayRect, ctx: s.client.plugins.context)
		let rim = (x: c.viewport.x, y: c.viewport.y + c.viewport.h - 40, w: c.viewport.w, h: 40)
		XCTAssertEqual(count(on, QuestHelperPlugin.targetColour, in: rim), 0)
		try save(on, "quest-target-npc")
	}

	func testTargetChangesWithTheNpcNotJustTheTile() throws {
		// Same tile, different npc id: nothing highlights the npc, the tile fallback is drawn at the spawn instead.
		let s = try makeSetup(target: { tile, id, name in .npc(name: name, ids: [id + 100_000], at: QuestTile(tile.x + 6, tile.z, tile.plane)) })
		var base = try s.client.frame(width: 1015, height: 469)
		s.client.plugins.setEnabled(false, id: "questHelper")
		base = try s.client.frame(width: 1015, height: 469)
		s.client.plugins.setEnabled(true, id: "questHelper")
		var on = base
		s.client.plugins.drawOverlays(.scene, into: &on)
		XCTAssertEqual(count(on, QuestHelperPlugin.targetColour, in: (s.screen.x - 14, s.screen.y - 10, 28, 80)), 0, "the npc at the original tile is not the target")
	}

	func testLocAndTileTargetsFillTheirTile() throws {
		let s = try makeSetup(target: { tile, _, _ in .loc(name: "Test object", id: 1, at: QuestTile(tile.x, tile.z, tile.plane)) })
		var base = try s.client.frame(width: 1015, height: 469)
		s.client.plugins.setEnabled(false, id: "questHelper")
		base = try s.client.frame(width: 1015, height: 469)
		s.client.plugins.setEnabled(true, id: "questHelper")
		var on = base
		s.client.plugins.drawOverlays(.scene, into: &on)
		let ctx = s.client.plugins.context
		let canvas = OverlayCanvas(world: s.client.world, viewport: s.client.overlayRect, ctx: ctx)
		let p = try XCTUnwrap(canvas.projectTileCenter(x: s.world.x - ctx.origin.x, z: s.world.z - ctx.origin.z))
		XCTAssertGreaterThan(differing(base, on, in: (p.x - 40, p.y - 30, 80, 60)), 200)
	}

	func testOffScreenTargetDrawsAnEdgeArrowTowardsIt() throws {
		// A tile 35 tiles from the player: outside the view.
		let s = try makeSetup(target: { tile, id, name in .tile(name: "Far place", at: QuestTile(tile.x - 3, tile.z - 38, tile.plane), radius: 0) })
		let client = s.client
		var base = try client.frame(width: 1015, height: 469)
		client.plugins.setEnabled(false, id: "questHelper")
		base = try client.frame(width: 1015, height: 469)
		client.plugins.setEnabled(true, id: "questHelper")
		var on = base
		client.plugins.drawOverlays(.scene, into: &on)
		let ctx = client.plugins.context
		let canvas = OverlayCanvas(world: client.world, viewport: client.overlayRect, ctx: ctx)
		let me = try XCTUnwrap(ctx.selfActor)
		let dx = (s.world.x - 3) - (ctx.origin.x + me.tileX), dz = (s.world.z - 38) - (ctx.origin.z + me.tileZ)
		let m = try XCTUnwrap(QuestMarkerMath.edgeMarker(dx: dx, dz: dz, yaw: canvas.cameraYaw, viewport: canvas.viewport))
		XCTAssertGreaterThan(m.distance, 25)
		// The arrow head is the solid colour at the marker point; nothing else of the target is on screen.
		XCTAssertEqual(on.pixels[m.y * on.width + m.x], 0xFF000000 | QuestHelperPlugin.targetColour, "arrow at \(m)")
		XCTAssertGreaterThan(differing(base, on, in: (m.x - 40, m.y - 30, 80, 60)), 80, "arrow and distance label")
		// The marker is on the viewport's edge band.
		let v = canvas.viewport
		XCTAssertTrue(m.x <= v.x + 20 || m.x >= v.x + v.w - 20 || m.y <= v.y + 20 || m.y >= v.y + v.h - 20, "\(m) in \(v)")
		try save(on, "quest-offscreen-arrow")
		// Arrow off: nothing drawn.
		client.plugins.plugin(id: "questHelper")?.config.set("offscreenArrow", .bool(false))
		var off = base
		client.plugins.drawOverlays(.scene, into: &off)
		XCTAssertEqual(off.pixels, base.pixels)
	}

	/// The marker's left/right matches where the real projection puts on-screen tiles.
	func testMarkerBearingAgreesWithTheProjection() throws {
		let client = try startedClient()
		let ctx = client.plugins.context
		let canvas = OverlayCanvas(world: client.world, viewport: client.overlayRect, ctx: ctx)
		let me = try XCTUnwrap(ctx.selfActor)
		let cx = canvas.viewport.x + canvas.viewport.w / 2
		var checked = 0
		for dx in stride(from: -9, through: 9, by: 3) {
			for dz in stride(from: -9, through: 9, by: 3) where dx != 0 || dz != 0 {
				guard let p = canvas.projectTileCenter(x: me.tileX + dx, z: me.tileZ + dz) else { continue }
				let rel = QuestMarkerMath.cameraRelative(dx: Double(dx), dz: Double(dz), yaw: canvas.cameraYaw)
				guard rel.forward > 2 else { continue }   // in front of the camera
				if abs(rel.right) > 1.5 { XCTAssertEqual(rel.right > 0, p.x > cx, "tile (\(dx),\(dz)) projects to x=\(p.x), centre \(cx), right=\(rel.right)") }
				checked += 1
			}
		}
		XCTAssertGreaterThan(checked, 10)
	}

	func testPanelAndMinimapMarker() throws {
		let s = try makeSetup()
		let client = s.client
		var base = try client.frame(width: 1015, height: 469)
		client.plugins.setEnabled(false, id: "questHelper")
		base = try client.frame(width: 1015, height: 469)
		client.plugins.setEnabled(true, id: "questHelper")
		// HUD layer: panel in the top-left of the viewport.
		var on = base
		client.plugins.drawOverlays(.hud, into: &on)
		let v = client.overlayRect
		XCTAssertGreaterThan(differing(base, on, in: (v.x, v.y, 200, 70)), 400, "panel background and text")
		XCTAssertEqual(differing(base, on, in: (v.x + v.w - 200, v.y + v.h - 60, 200, 60)), 0)
		// Panel hidden / moved.
		client.plugins.plugin(id: "questHelper")?.config.set("panel", .string("Hidden"))
		var hidden = base
		client.plugins.drawOverlays(.hud, into: &hidden)
		XCTAssertEqual(hidden.pixels, base.pixels)
		client.plugins.plugin(id: "questHelper")?.config.set("panel", .string("Top right"))
		var right = base
		client.plugins.drawOverlays(.hud, into: &right)
		XCTAssertGreaterThan(differing(base, right, in: (v.x + v.w - 200, v.y, 200, 70)), 400)
		XCTAssertEqual(differing(base, right, in: (v.x, v.y, 150, 70)), 0)
		try save(on, "quest-panel")
		// The minimap marker is the target tile.
		let markers = client.world.minimapMarkers
		XCTAssertEqual(markers.count, 1)
		XCTAssertEqual(markers.first?.x, s.world.x)
		XCTAssertEqual(markers.first?.z, s.world.z)
		// Turning the setting off clears it.
		client.plugins.plugin(id: "questHelper")?.config.set("minimap", .bool(false))
		s.plugin.refresh(client.plugins.context)
		XCTAssertTrue(client.world.minimapMarkers.isEmpty)
		// A tile on another plane is not marked on this plane's minimap.
		client.plugins.plugin(id: "questHelper")?.config.set("minimap", .bool(true))
		s.plugin.catalog = [QuestDef(id: "test", name: "Test Quest", serverIndex: 1, points: 1, source: QuestStatusSource(varp: 9999, complete: [2]), steps: [QuestStep("only", "Go up.", targets: [.tile(name: "Upstairs", at: QuestTile(s.world.x, s.world.z, 1), radius: 0)])])]
		s.plugin.refresh(client.plugins.context)
		XCTAssertTrue(client.world.minimapMarkers.isEmpty)
		// Shutting the plugin down clears the marker too.
		s.plugin.catalog = [QuestDef(id: "test", name: "Test Quest", serverIndex: 1, points: 1, source: QuestStatusSource(varp: 9999, complete: [2]), steps: [QuestStep("only", "Here.", targets: [.tile(name: "Here", at: s.world, radius: 0)])])]
		s.plugin.refresh(client.plugins.context)
		XCTAssertEqual(client.world.minimapMarkers.count, 1)
		client.plugins.setEnabled(false, id: "questHelper")
		XCTAssertTrue(client.world.minimapMarkers.isEmpty)
	}

	func testBackpackItemsAreOutlined() throws {
		let s = try makeSetup()
		let client = s.client
		// Shears in slot 4 of the backpack and a bucket in slot 5 (not part of the step).
		client.handle(.message(.invFull(component: Int32(149 << 16), inv: 93, items: [.init(id: -1, count: 0), .init(id: -1, count: 0), .init(id: -1, count: 0), .init(id: -1, count: 0), .init(id: 1735, count: 1), .init(id: 1925, count: 1)])))
		var base = try client.frame(width: 1015, height: 469)
		client.plugins.setEnabled(false, id: "questHelper")
		base = try client.frame(width: 1015, height: 469)
		client.plugins.setEnabled(true, id: "questHelper")
		let slots = client.plugins.context.backpackSlots()
		guard !slots.isEmpty else { throw XCTSkip("the recorded session does not show the backpack tab") }
		let shears = try XCTUnwrap(slots.first { $0.itemId == 1735 }, "\(slots)")
		let bucket = try XCTUnwrap(slots.first { $0.itemId == 1925 })
		XCTAssertEqual(shears.slot, 4)
		var on = base
		client.plugins.drawOverlays(.hud, into: &on)
		XCTAssertGreaterThan(differing(base, on, in: (shears.x, shears.y, 32, 32)), 60, "outline and tint on the needed item")
		XCTAssertEqual(differing(base, on, in: (bucket.x, bucket.y, 32, 32)), 0, "other items are left alone")
		try save(on, "quest-backpack")
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}
}
