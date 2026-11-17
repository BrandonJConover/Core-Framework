import Foundation
import XCTest
@testable import Scape530

/// REBUILD_REGION against the real cache: copying a stretch of the world chunk for chunk, unturned, must give the
/// scene and collision a normal rebuild of the same stretch gives.
final class DynamicRegionTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func mg4(_ v: Int) -> [UInt8] { [UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF), UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }

	func staticRebuild(zoneX: Int, zoneZ: Int) throws -> RebuildNormal {
		var b: [UInt8] = [UInt8(52 >> 8), UInt8((52 + 128) & 0xFF)]
		for _ in 0..<9 { b += mg4(0) + mg4(0) + mg4(0) + mg4(0) }
		b += [UInt8(128 - 0), UInt8(zoneX >> 8), UInt8(zoneX & 0xFF), UInt8(zoneZ >> 8), UInt8((zoneZ + 128) & 0xFF), 0, UInt8((52 + 128) & 0xFF)]
		return try RebuildNormal(payload: b)
	}

	func dynamicRebuild(zoneX: Int, zoneZ: Int, rotation: Int = 0, keys: Int = 9, _ source: (Int, Int, Int) -> Int?) throws -> RebuildNormal {
		// ig2add(localX), ig2add(zoneX), g1sub(plane), ig2add(localZ).
		var out: [UInt8] = [UInt8((52 + 128) & 0xFF), 0, UInt8((zoneX + 128) & 0xFF), UInt8(zoneX >> 8), 128, UInt8((52 + 128) & 0xFF), 0]
		var bits: [Bool] = []
		func put(_ v: Int, _ n: Int) { for i in stride(from: n - 1, through: 0, by: -1) { bits.append(v >> i & 1 == 1) } }
		for level in 0..<4 { for x in 0..<13 { for z in 0..<13 {
			if let c = source(level, x, z) { put(1, 1); put(c, 26) } else { put(0, 1) }
		} } }
		while bits.count % 8 != 0 { bits.append(false) }
		for i in stride(from: 0, to: bits.count, by: 8) {
			var b: UInt8 = 0
			for j in 0..<8 where bits[i + j] { b |= 0x80 >> UInt8(j) }
			out.append(b)
		}
		for _ in 0..<keys { out += mg4(0) + mg4(0) + mg4(0) + mg4(0) }
		out += [UInt8(zoneZ >> 8), UInt8(zoneZ & 0xFF)]
		return try RebuildNormal(dynamicPayload: out)
	}

	func build(_ r: RebuildNormal, _ s: ConfigStore) -> BuiltWorld {
		let input = WorldView.BuildInput(rebuild: r, plane: r.plane, store: s, textures: nil, env: LocEnvironment(), stamp: 1, minimap: false)
		return WorldView.performBuild(input)
	}

	func testUnturnedCopyMatchesNormalBuild() throws {
		let s = try store()
		let (zx, zz) = (402, 402) // Lumbridge
		let normal = build(try staticRebuild(zoneX: zx, zoneZ: zz), s)
		XCTAssertEqual(normal.errors, [])
		let table = try dynamicRebuild(zoneX: zx, zoneZ: zz) { level, x, z in (zx - 6 + x) << 14 | (zz - 6 + z) << 3 | level << 24 }
		XCTAssertTrue(table.isDynamic)
		let copy = build(table, s)
		XCTAssertEqual(copy.errors, [])
		let a = try XCTUnwrap(normal.scene), b = try XCTUnwrap(copy.scene)
		var heightDiff = 0, flagDiff = 0, collDiff = 0
		// The outer chunk ring is built from neighbours a copy does not have; compare the inside.
		for level in 0..<4 { for x in 8..<96 { for z in 8..<96 {
			if a.tileHeights[level][x][z] != b.tileHeights[level][x][z] { heightDiff += 1 }
			if a.renderFlags[level][x][z] != b.renderFlags[level][x][z] { flagDiff += 1 }
			if normal.collision[level][x, z] != copy.collision[level][x, z] { collDiff += 1 }
		} } }
		// Heights the map file does not state come from noise, which rt4 seeds with scene (not world) coordinates in
		// a dynamic region, so only those tiles may differ on level 0.
		var unexplained = 0
		for x in 8..<96 { for z in 8..<96 where a.tileHeights[0][x][z] != b.tileHeights[0][x][z] {
			let wx = (zx - 6) * 8 + x, wz = (zz - 6) * 8 + z
			let sq = try XCTUnwrap(try s.mapSquare(x: wx / 64, z: wz / 64))
			if sq.rawHeights[0][wx % 64][wz % 64] >= 0 { unexplained += 1 }
		} }
		XCTAssertEqual(unexplained, 0, "level 0 heights that differ and are stated in the map")
		XCTAssertLessThan(heightDiff, 4 * 400, "only the noise tiles differ")
		XCTAssertEqual(flagDiff, 0, "render flags")
		XCTAssertEqual(collDiff, 0, "collision flags")
		XCTAssertEqual(copy.placements.count > 100, true, "locs were copied: \(copy.placements.count)")
		XCTAssertEqual(abs(copy.placements.count - normal.placements.count) < normal.placements.count / 4, true,
		               "placements \(copy.placements.count) vs \(normal.placements.count)")
	}

	func testTurnedChunkMovesItsLocs() throws {
		let s = try store()
		var (zx, zz) = (402, 402)
		// A source chunk with some blocked tiles, so the turn is visible in the flags.
		search: for cx in 398...406 { for cz in 398...406 {
			guard let sq = try s.mapSquare(x: cx / 8, z: cz / 8) else { continue }
			var n = 0
			for x in 0..<8 { for z in 0..<8 where sq.flags[0][(cx & 7) * 8 + x][(cz & 7) * 8 + z] & 1 != 0 { n += 1 } }
			if n > 4 && n < 60 { (zx, zz) = (cx, cz); break search }
		} }
		// One chunk of Lumbridge copied to the middle of the scene, turned a half turn, versus unturned.
		func one(_ rot: Int) throws -> BuiltWorld {
			let r = try dynamicRebuild(zoneX: zx, zoneZ: zz, keys: 1) { level, x, z in
				x == 6 && z == 6 && level == 0 ? (zx << 14 | zz << 3 | rot << 1) : nil
			}
			return build(r, s)
		}
		let plain = try one(0), turned = try one(2)
		let inChunk: (LocPlacement) -> Bool = { _ in true }

		XCTAssertEqual(plain.errors, [])
		XCTAssertEqual(turned.errors, [])
		XCTAssertEqual(plain.placements.filter(inChunk).count, turned.placements.filter(inChunk).count, "a turn keeps every loc")
		for p in plain.placements + turned.placements where p.x < 48 || p.x >= 56 || p.z < 48 || p.z >= 56 { XCTFail("loc \(p.loc.id) landed outside its chunk at \(p.x),\(p.z)") }
		// Chunks without a source are flat, and only the copied chunk is walkable-loaded.
		let sc = try XCTUnwrap(turned.scene)
		XCTAssertEqual(sc.tileHeights[0][4][4], 0)
		// A half turn: the tile flags of the copy are those of the unturned copy, mirrored through the chunk centre.
		let pl = try XCTUnwrap(plain.scene)
		var mismatches = 0, blocked = 0
		for x in 0..<8 { for z in 0..<8 {
			let f = pl.renderFlags[0][48 + x][48 + z]
			if f != sc.renderFlags[0][48 + 7 - x][48 + 7 - z] { mismatches += 1 }
			if f & 1 != 0 { blocked += 1 }
		} }
		XCTAssertEqual(mismatches, 0)
		XCTAssertGreaterThan(blocked, 0, "the chunk has blocked tiles")
	}
}
