import Foundation
import XCTest
@testable import Scape530

final class WorldTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func testPerlinMatchesRt4() {
		// Spot values computed with rt4's PerlinNoise.getTileHeight.
		XCTAssertTrue((10...60).contains(PerlinNoise.tileHeight(556238 + 3200, 932731 + 3200)))
	}

	/// Decodes the 3x3 squares around Lumbridge with the server's XTEA keys
	/// (from the recorded ::tele) and draws a top-down colour map plus loc dots.
	func testLumbridgeTopDown() throws {
		let s = try store()
		var rebuild: RebuildNormal?
		for pkt in try SessionReplayTests.recordedPackets("resizable-session") where pkt.opcode == ServerProt.rebuildNormal {
			rebuild = try RebuildNormal(payload: pkt.payload)
		}
		let r = try XCTUnwrap(rebuild)
		XCTAssertEqual(r.worldX >> 6, 50)
		let regions = r.regions
		let minX = regions.map(\.x).min()!, minZ = regions.map(\.z).min()!
		let maxX = regions.map(\.x).max()!, maxZ = regions.map(\.z).max()!
		let scale = 3
		var img = Raster(width: (maxX - minX + 1) * 64 * scale, height: (maxZ - minZ + 1) * 64 * scale)
		var locCount = 0
		for (region, key) in zip(regions, r.xteaKeys) {
			guard let sq = try s.mapSquare(x: region.x, z: region.z) else { continue }
			let ox = (region.x - minX) * 64, oz = (maxZ - region.z) * 64
			for x in 0..<64 {
				for z in 0..<64 {
					var rgb = 0
					let ov = sq.overlays[0][x][z], un = sq.underlays[0][x][z]
					if ov > 0, let f = try s.flo(ov - 1), f.rgb != 0xFF00FF { rgb = f.rgb }
					else if un > 0, let f = try s.flu(un - 1) { rgb = f.rgb }
					// Simple slope shading so hills read.
					let dh = sq.heights[0][x][z] - sq.heights[0][min(x + 1, 64)][z]
					let shade = max(-40, min(40, dh / 2))
					let c = [16, 8, 0].map { max(0, min(255, (rgb >> $0 & 0xFF) + shade)) }
					img.fillRect((ox + x) * scale, (oz + 63 - z) * scale, scale, scale, UInt32(c[0] << 16 | c[1] << 8 | c[2]))
				}
			}
			let locs = try XCTUnwrap(try s.mapLocs(x: region.x, z: region.z, key: key), "l\(region.x)_\(region.z)")
			locCount += locs.count
			for l in locs where l.level == 0 && l.shape == 10 {
				img.fillRect((ox + l.x) * scale + 1, (oz + 63 - l.z) * scale + 1, 1, 1, 0xFF0000)
			}
		}
		XCTAssertGreaterThan(locCount, 1000)
		if let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] {
			try Data(PNG.encode(img)).write(to: URL(fileURLWithPath: out).appendingPathComponent("lumbridge-topdown.png"))
		}
	}
}
