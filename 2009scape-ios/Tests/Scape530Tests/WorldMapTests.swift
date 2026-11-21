import Foundation
import XCTest
@testable import Scape530

/// The world map: map list and data from archive 23, the ground/icon/label render at every zoom, the CS2 ops and the
/// interface-755 components with the map populated, and pan / pinch.
final class WorldMapTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	/// The loaded main map, centred on a world tile.
	func mainMap(at x: Int, z: Int, store: ConfigStore) throws -> WorldMap {
		let wm = WorldMap(store: store)
		wm.playerTile = { (x, z) }
		wm.load(group: "main")
		XCTAssertNotNil(wm.current, "main map exists")
		wm.loadAll()
		XCTAssertEqual(wm.loadPercentage, 100)
		return wm
	}

	struct Stats { var nonBlack = 0.0, green = 0.0, blue = 0.0, distinct = 0, total = 0 }

	func stats(_ r: Raster) -> Stats {
		var s = Stats()
		var seen = Set<UInt32>()
		for p in r.pixels {
			s.total += 1
			let c = p & 0xFFFFFF
			if c != 0 { s.nonBlack += 1 }
			let rr = (c >> 16) & 0xFF, gg = (c >> 8) & 0xFF, bb = c & 0xFF
			if gg > rr + 8 && gg >= bb { s.green += 1 }
			if bb > rr + 20 && bb > gg { s.blue += 1 }
			if seen.count < 4096 { seen.insert(c) }
		}
		s.nonBlack /= Double(s.total); s.green /= Double(s.total); s.blue /= Double(s.total)
		s.distinct = seen.count
		return s
	}

	// MARK: data

	func testMapListAndMainMapData() throws {
		let s = try store()
		let wm = WorldMap(store: s)
		XCTAssertFalse(wm.maps.isEmpty)
		print("WORLDMAPS", wm.maps.map { "\($0.group)=\($0.name) valid=\($0.valid) zoom=\($0.defaultZoom) areas=\($0.areas.count) [\($0.minX),\($0.minZ)-\($0.maxX),\($0.maxZ)]" })
		let main = try XCTUnwrap(wm.map(group: "main"))
		XCTAssertTrue(main.contains(x: 3222, z: 3218), "Lumbridge is on the main map")
		XCTAssertTrue(main.contains(x: 3213, z: 3428), "Varrock is on the main map")
		XCTAssertEqual(wm.maps(containing: 3222, z: 3218).first?.group, "main")
		wm.load(group: "main")
		wm.loadAll()
		XCTAssertEqual(wm.loadPercentage, 100)
		XCTAssertGreaterThan(wm.width, 1000)
		XCTAssertGreaterThan(wm.length, 1000)
		XCTAssertGreaterThan(wm.labelCount, 100, "labels")
		XCTAssertGreaterThan(wm.iconCount, 100, "map function icons")
		XCTAssertFalse(wm.labelFonts.isEmpty)
		var tiles = 0
		for col in wm.chunks.ground { for case let c? in col { tiles += c.filter { $0 != 0 }.count } }
		XCTAssertGreaterThan(tiles, 100_000, "ground colours")
		XCTAssertGreaterThan(wm.overlayColors.filter { $0 > 0 }.count, 5)
		print("MAIN width=\(wm.width) length=\(wm.length) labels=\(wm.labelCount) icons=\(wm.iconCount) view=\(wm.viewX),\(wm.viewZ)")
		// The same for the other maps (dungeons): loads without trouble.
		for m in wm.maps where m.group != "main" {
			wm.load(group: m.group)
			wm.loadAll()
			XCTAssertEqual(wm.loadPercentage, 100, m.group)
		}
	}

	// MARK: rendering

	func testRenderLumbridgeAndVarrockAtEveryZoom() throws {
		let s = try store()
		let wm = try mainMap(at: 3222, z: 3218, store: s)
		for (name, x, z) in [("lumbridge", 3222, 3218), ("varrock", 3213, 3428)] {
			for (percent, _) in WorldMap.zoomLevels {
				wm.setZoom(percent: percent)
				wm.zoom = wm.targetZoom
				wm.centre(onX: x, z: z)
				wm.viewX = x - wm.originX
				wm.viewZ = wm.originZ + wm.length - z - 1
				wm.goalX = -1; wm.goalZ = -1
				var r = Raster(width: 700, height: 440)
				let t0 = Date()
				wm.drawMain(into: &r, x: 0, y: 0, w: 700, h: 440)
				let ms = Date().timeIntervalSince(t0) * 1000
				let st = stats(r)
				print("RENDER \(name) \(percent)% \(Int(ms)) ms non-black \(st.nonBlack) green \(st.green) blue \(st.blue) distinct \(st.distinct)")
				try save(r, "worldmap-\(name)-\(percent)")
				XCTAssertGreaterThan(st.nonBlack, 0.97, "\(name) \(percent)")
				XCTAssertGreaterThan(st.distinct, 12, "\(name) \(percent)")
				if percent >= 75 && name == "lumbridge" {
					XCTAssertGreaterThan(st.green, 0.05, "\(name) \(percent): grass")
				}
			}
		}
		// Lumbridge has water (the river and the lake) on screen at a wide zoom.
		wm.setZoom(percent: 37); wm.zoom = wm.targetZoom
		var r = Raster(width: 700, height: 440)
		wm.drawMain(into: &r, x: 0, y: 0, w: 700, h: 440)
		XCTAssertGreaterThan(stats(r).blue, 0.005, "water")
	}

	func testOverviewAndFlash() throws {
		let s = try store()
		let wm = try mainMap(at: 3222, z: 3218, store: s)
		var r = Raster(width: 700, height: 440)
		wm.drawMain(into: &r, x: 0, y: 0, w: 700, h: 440)
		var o = Raster(width: 240, height: 180)
		wm.drawOverview(into: &o, x: 0, y: 0, w: 240, h: 180)
		let st = stats(o)
		XCTAssertGreaterThan(st.nonBlack, 0.4)
		try save(o, "worldmap-overview")
		// Flash the bank icon: rings appear around it for three flashes, then stop.
		wm.flash(function: 0)
		XCTAssertEqual(wm.flashCount, 3)
		wm.isShown = true
		for _ in 0..<70 { wm.cycle() }
		XCTAssertEqual(wm.flashCount, 0)
	}

	// MARK: pan and zoom

	func testPanAndZoom() throws {
		let s = try store()
		let wm = try mainMap(at: 3222, z: 3218, store: s)
		wm.isShown = true
		wm.setZoom(percent: 100); wm.zoom = wm.targetZoom
		let (x0, z0) = (wm.viewX, wm.viewZ)
		// Dragging the picture right by 40 pixels at 4 px/tile moves the centre 10 tiles left.
		wm.drag(dx: 40, dy: 0)
		XCTAssertEqual(wm.viewX, x0 - 10)
		XCTAssertEqual(wm.viewZ, z0)
		wm.drag(dx: 0, dy: -40)
		XCTAssertEqual(wm.viewZ, z0 + 10)
		// Fractions accumulate instead of being lost.
		let x1 = wm.viewX
		for _ in 0..<8 { wm.drag(dx: 1, dy: 0) }
		XCTAssertEqual(wm.viewX, x1 - 2)
		// Dragging far past the edge clamps inside the area.
		wm.drag(dx: 1_000_000, dy: 1_000_000)
		XCTAssertEqual(wm.viewX, 0)
		XCTAssertEqual(wm.viewZ, 0)
		// Pinch: continuous inside 3...16, easing toward the target, and snapping to a level.
		wm.zoom(by: 1.5)
		XCTAssertEqual(wm.targetZoom, 12, accuracy: 0.01)
		wm.zoom(by: 100)
		XCTAssertEqual(wm.targetZoom, 16)
		wm.zoom(by: 0.001)
		XCTAssertEqual(wm.targetZoom, 3)
		wm.zoom(by: 1.4)
		wm.snapZoom()
		XCTAssertEqual(wm.targetZoom, 4)
		XCTAssertEqual(wm.zoomPercent, 50)
		let before = wm.zoom
		wm.cycle()
		XCTAssertLessThan(wm.zoom, before, "zoom eases toward the target")
		for _ in 0..<200 { wm.cycle() }
		XCTAssertEqual(wm.zoom, 4)
	}

	func testLabelSearch() throws {
		let s = try store()
		let wm = try mainMap(at: 3222, z: 3218, store: s)
		wm.componentSize = (700, 440)
		XCTAssertFalse(wm.labelName(startingWith: "Lumb").isEmpty)
		XCTAssertEqual(wm.labelName(startingWith: "zzzzzz"), "")
		wm.centre(onLabelPrefix: "Varrock")
		for _ in 0..<300 { wm.isShown = true; wm.cycle() }
		let c = wm.centreTile
		print("VARROCK label centre", c)
		XCTAssertTrue(abs(c.x - 3213) < 60 && abs(c.z - 3428) < 60, "glided to Varrock \(c)")
		var n = 0
		var next = wm.nextLabel(restart: true)
		while next != nil { n += 1; next = wm.nextLabel(restart: false) }
		XCTAssertGreaterThan(n, 50)
	}

	// MARK: interface 755

	/// The server opens interface 755 as the top level pane; its scripts size and place the map and overview.
	func testInterface755WithTheMapPopulated() throws {
		let s = try store()
		let host = InterfaceScriptHost(store: s)
		// The local player stands in Lumbridge: scene-local (6, 18) in the region whose central zone is (408, 406).
		host.game.rebuild = try RebuildNormal(payload: [0, 134, 128, 1, 152, 1, 22, 0, 146])
		host.game.players = PlayerInfoDecoder(selfIndex: 2047, localX: 6, localZ: 18)
		XCTAssertEqual(host.game.selfWorld?.x, 3222)
		XCTAssertEqual(host.game.selfWorld?.z, 3218)
		let wm = host.renderer.worldMap
		wm.load(group: "main")
		for (w, h) in [(852, 393), (765, 503)] {
			host.resize(width: w, height: h)
			host.apply(.ifOpenTop(id: 755, reset: 0))
			for _ in 0..<40 {
				host.cycle()
				var r = Raster(width: w, height: h)
				try host.renderer.render(755, state: host.game.interfaces, into: &r)
				if wm.loadPercentage == 100 { break }
			}
			XCTAssertEqual(wm.loadPercentage, 100, "the interface drives loading")
			for _ in 0..<5 { host.cycle() }
			var r = Raster(width: w, height: h)
			try host.renderer.render(755, state: host.game.interfaces, into: &r)
			XCTAssertEqual(host.takeErrors(), [])
			XCTAssertTrue(wm.isShown)
			let map = try XCTUnwrap(host.renderer.drawn.last { $0.component.clientCode == 1400 })
			XCTAssertGreaterThan(map.w, 300)
			XCTAssertGreaterThan(map.h, 200)
			// The map area is full of map.
			var inside = Raster(width: map.w, height: map.h)
			for y in 0..<map.h { for x in 0..<map.w { inside.pixels[y * map.w + x] = r.pixels[(map.y + y) * w + map.x + x] } }
			let st = stats(inside)
			print("755 \(w)x\(h) map rect \(map.x),\(map.y) \(map.w)x\(map.h) non-black \(st.nonBlack) distinct \(st.distinct) tiles shown \(wm.viewWidthTiles)x\(wm.viewHeightTiles)")
			XCTAssertGreaterThan(st.nonBlack, 0.9)
			XCTAssertGreaterThan(st.distinct, 12)
			try save(r, "worldmap-interface755-\(w)x\(h)")
			print("755 hidden", host.game.interfaces.hidden.filter { $0.key >> 16 == 755 && $0.value }.map { $0.key & 0xFFFF }.sorted(), "overrides", host.game.interfaces.overrides.keys.filter { $0 >> 16 == 755 }.map { $0 & 0xFFFF }.sorted(), "dynamic", host.game.interfaces.dynamic.filter { $0.key >> 16 == 755 }.map { "\($0.key & 0xFFFF):\($0.value.count)" })
		}
		// The scripts' ops answer from the map: centre, view size, loaded and default zoom.
		XCTAssertEqual(host.perform(HostOps.table[5220]!, ints: [], strings: []).ints, [1])
		let centre = host.perform(HostOps.table[5209]!, ints: [], strings: []).ints
		XCTAssertTrue(abs(Int(centre[0]) - 3222) < 30 && abs(Int(centre[1]) - 3218) < 30, "starts on the player \(centre)")
		let size = host.perform(HostOps.table[5208]!, ints: [], strings: []).ints
		XCTAssertGreaterThan(size[0], 50)
		XCTAssertEqual(host.perform(HostOps.table[5201]!, ints: [], strings: []).ints, [75], "the main map opens at its default 75%")
		host.perform(HostOps.table[5200]!, ints: [200], strings: [])
		XCTAssertEqual(host.perform(HostOps.table[5201]!, ints: [], strings: []).ints, [200])
		let coord = Int32((3213 << 14) | 3428)
		XCTAssertEqual(host.perform(HostOps.table[5206]!, ints: [coord], strings: []).strings, ["main"])
		XCTAssertEqual(host.perform(HostOps.table[5215]!, ints: [coord], strings: ["MAIN"]).ints, [1])
		XCTAssertEqual(host.perform(HostOps.table[5215]!, ints: [coord], strings: ["nonexistent"]).ints, [0])
		XCTAssertFalse(host.perform(HostOps.table[5207]!, ints: [], strings: ["main"]).strings[0].isEmpty)
		XCTAssertEqual(host.perform(HostOps.table[5218]!, ints: [], strings: []).ints.count, 1)
		// Icon switches.
		host.perform(HostOps.table[5216]!, ints: [3], strings: [])
		XCTAssertEqual(host.perform(HostOps.table[5217]!, ints: [3], strings: []).ints, [1])
		host.perform(HostOps.table[5216]!, ints: [3], strings: [])
		XCTAssertEqual(host.perform(HostOps.table[5217]!, ints: [3], strings: []).ints, [0])
	}

	/// The gesture API on the client routes to the map while it is open (so a shell that forwards camera drag, pinch and
	/// "is this over the world" keeps working without changes).
	func testGameClientGestures() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		XCTAssertFalse(client.worldMapIsOpen)
		XCTAssertNil(client.worldMapRect)
		XCTAssertFalse(client.isOverWorldMap(x: 100, y: 100))
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: 2047, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		client.handle(.message(.ifOpenTop(id: 755, reset: 0)))
		var frames = 0
		while frames < 60 {
			_ = try client.frame(width: 852, height: 393)
			frames += 1
			if client.ui.worldMap.loadPercentage == 100 { break }
		}
		XCTAssertEqual(client.ui.worldMap.loadPercentage, 100, "the map loads one stage per frame (\(frames) frames)")
		let r = try client.frame(width: 852, height: 393)
		try save(r, "worldmap-client-852x393")
		XCTAssertTrue(client.worldMapIsOpen)
		let rect = try XCTUnwrap(client.worldMapRect)
		let mid = (x: rect.x + rect.w / 2, y: rect.y + rect.h / 2)
		XCTAssertTrue(client.isOverWorldMap(x: mid.x, y: mid.y))
		XCTAssertTrue(client.isOverWorld(x: mid.x, y: mid.y), "drags that start on the map are camera drags to the shell")
		XCTAssertFalse(client.isOverWorldMap(x: rect.x - 5, y: rect.y - 5))
		// The "?" button over the bottom of the map keeps its tap.
		XCTAssertFalse(client.isOverWorldMap(x: 96, y: 369))
		let wm = client.ui.worldMap
		let (x0, z0, zoom0) = (wm.viewX, wm.viewZ, wm.targetZoom)
		client.cameraDrag(dx: -80, dy: 40)
		XCTAssertGreaterThan(wm.viewX, x0)
		XCTAssertLessThan(wm.viewZ, z0)
		client.cameraPinch(scale: 1.3)
		XCTAssertGreaterThan(wm.targetZoom, zoom0)
		client.worldMapZoomEnded()
		XCTAssertEqual(wm.targetZoom, 8)
		for _ in 0..<5 { _ = try client.frame(width: 852, height: 393) }
		XCTAssertEqual(host(client).errors.count, 0)
	}

	/// Closing the map reopens the game screen as the top-level interface; its chatbox and tabs come back because
	/// rt4's IF_OPENTOP keeps the sub-interfaces open (Brandon: the chatbox was gone after closing the map).
	func testClosingMapKeepsSubInterfaces() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: 2047, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		client.handle(.message(.ifOpenTop(id: 746, reset: 0)))
		client.handle(.message(.ifOpenSub(parent: 746 << 16 | 75, component: 752, type: 1)))
		client.handle(.message(.ifOpenTop(id: 755, reset: 0)))
		_ = try client.frame(width: 852, height: 393)
		client.handle(.message(.ifOpenTop(id: 746, reset: 2)))
		XCTAssertEqual(client.state.interfaces.top, 746)
		XCTAssertEqual(client.state.interfaces.open[746 << 16 | 75], 752, "chatbox still open")
		// A fresh login starts clean.
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: 2047, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		XCTAssertTrue(client.state.interfaces.open.isEmpty)
	}

	func host(_ c: GameClient) -> InterfaceScriptHost { c.host }
}
