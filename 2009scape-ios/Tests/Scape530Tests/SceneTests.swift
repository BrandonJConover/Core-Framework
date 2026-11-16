import Foundation
import XCTest
@testable import Scape530

/// A coloured vertical pillar standing on the ground, enough to check entity ordering and the render call.
final class PillarEntity: SceneEntity {
	let color: Int32
	let height: Int
	var renders = 0
	init(color: Int32, height: Int) { self.color = color; self.height = height }

	func getMinY() -> Int { -height }

	func render(_ r: Rasteriser3D, yaw: Int, sinPitch: Int, cosPitch: Int, sinYaw: Int, cosYaw: Int, x: Int, y: Int, z: Int, key: Int64) {
		renders += 1
		// Four ground corners and four top corners, +-40 around the centre.
		var sx = [Int](), sy = [Int]()
		for dy in [0, -height] {
			for (dx, dz) in [(-40, -40), (40, -40), (40, 40), (-40, 40)] {
				let px = x + dx, py = y + dy, pz = z + dz
				let xr = (pz * sinYaw + px * cosYaw) >> 16
				let zr = (pz * cosYaw - px * sinYaw) >> 16
				let yv = (py * cosPitch - zr * sinPitch) >> 16
				let zv = (py * sinPitch + zr * cosPitch) >> 16
				if zv < 50 { return }
				sx.append(Int(r.centerX) + (xr << 9) / zv)
				sy.append(Int(r.centerY) + (yv << 9) / zv)
			}
		}
		r.alpha = 0
		for (a, b, c, d) in [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7)] {
			r.testX = true
			r.fillTriangle(sy[a], sy[b], sy[c], sx[a], sx[b], sx[c], Int(color))
			r.fillTriangle(sy[a], sy[c], sy[d], sx[a], sx[c], sx[d], Int(color))
		}
	}
}

final class SceneTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	func testShapedTileTables() {
		XCTAssertEqual(ShapedTile.vertexIds.count, 13)
		XCTAssertEqual(ShapedTile.triangles.count, 13)
		for t in ShapedTile.triangles { XCTAssertEqual(t.count % 4, 0) }
		// A flat quarter-turned half tile: three-vertex shapes produce one overlay triangle.
		let tile = ShapedTile(shape: 2, rotation: 1, texture: -1, x: 3, z: 4, h: [0, 0, 0, 0], underlay: [1, 2, 3, 4], overlay: [5, 6, 7, 8], underlayMinimap: 0, overlayMinimap: 0)
		XCTAssertEqual(tile.vertexX.count, 4)
		XCTAssertEqual(tile.triA.count, 2)
		XCTAssertEqual(tile.vertexX[0], 3 * 128)
		XCTAssertTrue(tile.flat)
	}

	/// Loads the 2x2 squares around Lumbridge and draws the terrain from a 3/4 camera at 765x503.
	func testLumbridgeTerrain() throws {
		let s = try store()
		var squares: [MapSquare] = []
		for rx in 49...50 { for rz in 49...50 { if let sq = try s.mapSquare(x: rx, z: rz) { squares.append(sq) } } }
		XCTAssertEqual(squares.count, 4)
		let textures = try TextureStore(config: s)
		let scene = Scene(store: s, textures: textures, width: 128, length: 128)
		let t0 = Date()
		try scene.loadMapSquares(squares, baseTileX: 49 * 64, baseTileZ: 49 * 64, centralPlane: 0)
		print("scene load: \(Date().timeIntervalSince(t0)) s, occluders \(scene.occluders.count)")

		var plain = 0, shaped = 0, textured = 0
		for x in 0..<128 { for z in 0..<128 {
			guard let t = scene.tiles[0][x][z] else { continue }
			if let p = t.plainTile { plain += 1; if p.texture >= 0 { textured += 1 } }
			if let sh = t.shapedTile { shaped += 1; if sh.textures != nil { textured += 1 } }
		} }
		print("tiles: plain \(plain) shaped \(shaped) textured \(textured)")
		XCTAssertGreaterThan(plain, 8000)
		XCTAssertGreaterThan(shaped, 100)
		XCTAssertGreaterThan(textured, 50)

		// Lumbridge castle courtyard.
		let targetX = (3232 - 49 * 64) * 128 + 64, targetZ = (3222 - 49 * 64) * 128 + 64
		let targetY = scene.tileHeight(level: 0, xFine: targetX, zFine: targetZ)
		let pillar = PillarEntity(color: 0xFF2020, height: 400)
		XCTAssertTrue(scene.add(level: 0, xFine: (3222 - 49 * 64) * 128 + 64, zFine: (3218 - 49 * 64) * 128 + 64, y: scene.tileHeight(level: 0, xFine: (3222 - 49 * 64) * 128 + 64, zFine: (3218 - 49 * 64) * 128 + 64), radius: 60, entity: pillar, yaw: 0, key: 1, extend: false))

		let pitch = 340, yaw = 120
		let dist = 4600
		let sinP = Double(MathTables.sin[pitch]) / 65536, cosP = Double(MathTables.cos[pitch]) / 65536
		let sinY = Double(MathTables.sin[yaw]) / 65536, cosY = Double(MathTables.cos[yaw]) / 65536
		let camX = targetX + Int(Double(dist) * cosP * sinY)
		let camZ = targetZ - Int(Double(dist) * cosP * cosY)
		let camY = targetY - Int(Double(dist) * sinP)

		let r = Rasteriser3D(width: 765, height: 503)
		r.setBrightness(0.8, jitter: false)
		r.unpackTextures(textures)
		r.setClip(0, 0, 765, 503)
		r.prepare()
		r.clear(0x6080C0)
		let t1 = Date()
		scene.draw(into: r, cameraX: camX, cameraY: camY, cameraZ: camZ, pitch: pitch, yaw: yaw)
		print("scene draw: \(Date().timeIntervalSince(t1)) s, pillar renders \(pillar.renders)")
		XCTAssertGreaterThan(pillar.renders, 0)

		var img = Raster(width: 765, height: 503)
		r.copy(into: &img)
		try save(img, "scene-lumbridge-terrain")
		let sky = r.pixels.filter { $0 == 0x6080C0 }.count
		print("sky pixels \(sky) of \(r.pixels.count)")
		XCTAssertLessThan(sky, r.pixels.count * 3 / 4)
	}
}
