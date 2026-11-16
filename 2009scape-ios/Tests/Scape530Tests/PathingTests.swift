import Foundation
import XCTest
@testable import Scape530

final class PathingTests: XCTestCase {
	static let baseX = 3168, baseZ = 3168

	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	/// Collision maps for the 104x104 area at 3168,3168 (loc keys from the recorded REBUILD_NORMAL).
	func lumbridgeMaps() throws -> [CollisionMap] {
		let s = try store()
		var rebuild: RebuildNormal?
		for pkt in try SessionReplayTests.recordedPackets("resizable-session") where pkt.opcode == ServerProt.rebuildNormal {
			rebuild = try RebuildNormal(payload: pkt.payload)
		}
		let r = try XCTUnwrap(rebuild)
		var keys: [String: [Int32]] = [:]
		for (region, key) in zip(r.regions, r.xteaKeys) { keys["\(region.x)_\(region.z)"] = key }
		return try CollisionBuilder.build(store: s, baseX: Self.baseX, baseZ: Self.baseZ, keys: { keys["\($0)_\($1)"] ?? [0, 0, 0, 0] })
	}

	func render(_ map: CollisionMap, path: [(x: Int, z: Int)], marks: [(x: Int, z: Int, c: UInt32)], name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		let sc = 8
		var img = Raster(width: 104 * sc, height: 104 * sc, fill: 0xFFE8E8E8)
		func px(_ x: Int) -> Int { x * sc }
		func py(_ z: Int) -> Int { (103 - z) * sc }
		for x in 0..<104 {
			for z in 0..<104 {
				let f = map[x, z]
				if (f & 0x1000000) != 0 { img.fillRect(px(x), py(z), sc, sc, 0xFF000000); continue }
				if (f & 0x200000) != 0 { img.fillRect(px(x), py(z), sc, sc, 0xFF8090A0) }
				if (f & 0x100) != 0 { img.fillRect(px(x), py(z), sc, sc, 0xFF404040) }
				if (f & 0x40000) != 0 { img.fillRect(px(x) + 2, py(z) + 2, sc - 4, sc - 4, 0xFFA07040) }
				if (f & 0x2) != 0 { img.fillRect(px(x), py(z), sc, 1, 0xFF0000C0) }
				if (f & 0x20) != 0 { img.fillRect(px(x), py(z) + sc - 1, sc, 1, 0xFF0000C0) }
				if (f & 0x8) != 0 { img.fillRect(px(x) + sc - 1, py(z), 1, sc, 0xFF0000C0) }
				if (f & 0x80) != 0 { img.fillRect(px(x), py(z), 1, sc, 0xFF0000C0) }
				if (f & 0x1) != 0 || (f & 0x4) != 0 || (f & 0x10) != 0 || (f & 0x40) != 0 { img.fillRect(px(x) + 3, py(z) + 3, 2, 2, 0xFFC000C0) }
			}
		}
		for p in path { img.fillRect(px(p.x) + 2, py(p.z) + 2, sc - 4, sc - 4, 0xFFE02020) }
		for m in marks { img.fillRect(px(m.x), py(m.z), sc, sc, m.c) }
		try Data(PNG.encode(img)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	/// Expands a route's turn points into every tile walked.
	func tiles(from s: (x: Int, z: Int), route: PathFinder.Route) -> [(x: Int, z: Int)] {
		var out = [s]
		var cur = s
		for w in route.waypoints {
			while cur.x != w.x || cur.z != w.z {
				cur.x += (w.x - cur.x).signum()
				cur.z += (w.z - cur.z).signum()
				out.append(cur)
			}
		}
		return out
	}

	func testSyntheticWalls() {
		// A wall segment (shape 0, rotation 1 = north edge) flags both sides.
		let m = CollisionMap()
		for x in 0..<104 { for z in 0..<104 { m.markLoaded(x: x, z: z) } }
		m.flagWall(angle: 1, shape: 0, blocksProjectiles: false, x: 10, z: 10)
		XCTAssertEqual(m[10, 10] & 0x2, 0x2)
		XCTAssertEqual(m[10, 11] & 0x20, 0x20)
		m.unflagWall(angle: 1, shape: 0, blocksProjectiles: false, x: 10, z: 10)
		XCTAssertEqual(m[10, 10] & 0x22, 0)
		// A solid 2x2 scenery blocks; the route detours around it.
		m.flagScenery(x: 11, z: 20, width: 2, length: 2, blocksProjectiles: false)
		let pf = PathFinder(collision: m)
		let route = pf.findPath(srcX: 10, srcZ: 21, size: 1, target: .tile(x: 14, z: 21), allowFallback: false)
		XCTAssertNotNil(route)
		XCTAssertFalse(route!.partial)
		// Unreachable target (inside blocked border) falls back to the nearest tile.
		let near = pf.findPath(srcX: 50, srcZ: 50, size: 1, target: .tile(x: 99, z: 50), allowFallback: true)
		// The border is blocked, so the search falls back to the nearest explored tile (rt4 quirk: a width-0 target counts one tile of z slack).
		XCTAssertEqual(near?.partial, true)
		XCTAssertEqual(near?.waypoints.last?.x, 98)
	}

	func testWalkPacketFields() {
		let route = PathFinder.Route(waypoints: [(5, 5), (9, 5), (9, 12)], partial: false)
		let f = PathFinder.walkPacketFields(route: route, originX: 3000, originZ: 3100, walkType: .gameClick, running: true)
		XCTAssertEqual(f.opcode, 215)
		XCTAssertEqual(f.firstX, 3005)
		XCTAssertEqual(f.firstZ, 3105)
		XCTAssertEqual(f.deltas.map { $0.dx }, [4, 4])
		XCTAssertEqual(f.deltas.map { $0.dz }, [0, 7])
		XCTAssertEqual(f.payloadLength, 9)
		let msg = PathFinder.walkMessage(route: route, originX: 3000, originZ: 3100, running: true, minimap: false)
		var c1 = IsaacRandom(seed: [0, 0, 0, 0]), c2 = IsaacRandom(seed: [0, 0, 0, 0])
		let bytes = msg.encode(&c1)
		XCTAssertEqual(bytes, ClientMessage.walk(destX: 3009, destZ: 3112, path: [(3005, 3105), (3009, 3105)], ctrlRun: true).encode(&c2))
		XCTAssertEqual(Array(bytes.prefix(3)), [215, 9, 129])
		XCTAssertEqual(bytes.count, 2 + 9)
	}

	func testLumbridgeCastlePath() throws {
		let maps = try lumbridgeMaps()
		let map = maps[0]
		let pf = PathFinder(collision: map)
		let bx = Self.baseX, bz = Self.baseZ
		// Goal on the lawn east of the castle; start = the tile inside the castle box whose
		// route to the goal is longest (deep inside the walls, so it has to find the door).
		let goal = (x: 3222 - bx, z: 3218 - bz)
		var start = (x: 0, z: 0)
		var best: PathFinder.Route?
		var bestLen = 0
		for tx in 3203...3216 {
			for tz in 3209...3226 {
				let sx = tx - bx, sz = tz - bz
				guard (map[sx, sz] & 0x12C0100) == 0,
				      let r = pf.findPath(srcX: sx, srcZ: sz, size: 1, target: .tile(x: goal.x, z: goal.z), allowFallback: false) else { continue }
				let len = tiles(from: (sx, sz), route: r).count
				if len > bestLen { bestLen = len; best = r; start = (sx, sz) }
			}
		}
		XCTAssertNotNil(best)
		print("castle start \(start.x + bx),\(start.z + bz) route tiles \(bestLen) waypoints \(best?.waypoints ?? [])")
		let route = try XCTUnwrap(pf.findPath(srcX: start.x, srcZ: start.z, size: 1, target: .tile(x: goal.x, z: goal.z), allowFallback: false))
		let walked = tiles(from: start, route: route)
		XCTAssertEqual(walked.last!.x, goal.x)
		XCTAssertEqual(walked.last!.z, goal.z)
		try render(map, path: walked, marks: [(start.x, start.z, 0xFF00A000), (goal.x, goal.z, 0xFFFFA000)], name: "collision-lumbridge-path")
		// Every step is legal: re-check each move against the flags with rt4's masks.
		for (a, b) in zip(walked, walked.dropFirst()) {
			let dx = b.x - a.x, dz = b.z - a.z
			XCTAssertEqual(map[b.x, b.z] & 0x12C0100, 0, "blocked tile \(b)")
			if dx == -1 { XCTAssertEqual(map[b.x, b.z] & 0x8, 0) }
			if dx == 1 { XCTAssertEqual(map[b.x, b.z] & 0x80, 0) }
			if dz == -1 { XCTAssertEqual(map[b.x, b.z] & 0x2, 0) }
			if dz == 1 { XCTAssertEqual(map[b.x, b.z] & 0x20, 0) }
		}
		// Some turn points: it isn't a straight line, so it must pass a gap in the walls.
		XCTAssertGreaterThan(route.waypoints.count, 1)
		// A straight line would be max(dx, dz) tiles; the walls force a real detour.
		XCTAssertGreaterThan(walked.count - 1, max(abs(goal.x - start.x), abs(goal.z - start.z)) + 6)
	}
}
