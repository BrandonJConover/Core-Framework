import Foundation
import XCTest
@testable import Scape530

/// Renders item and scenery models through `SoftwareModel.render` and the
/// `LocModelBuilder`, writing PNGs to `SCAPE530_OUT` for visual inspection.
final class LocModelTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	/// Draws `model` centred on screen with a fixed camera (pitch 150, yaw 0)
	/// at `distance`, rotated by `yaw`; returns the number of non-background pixels.
	@discardableResult
	func draw(_ model: SoftwareModel, _ r: Rasteriser3D, yaw: Int, distance: Int, pitch: Int = 150) -> Int {
		model.ensureBounds()
		let sinP = MathTables.sin[pitch], cosP = MathTables.cos[pitch]
		let midY = (model.minY + model.maxY) / 2
		// Pick the scene y that projects the model's centre to screen centre.
		let y = distance * sinP / cosP - midY * 1
		model.render(r, yaw: yaw, sinPitch: sinP, cosPitch: cosP, sinYaw: MathTables.sin[0], cosYaw: MathTables.cos[0], x: 0, y: y, z: distance, key: 0)
		return r.pixels.reduce(0) { $0 + ($1 != 0x405880 ? 1 : 0) }
	}

	func frame(_ ts: TextureStore) -> Rasteriser3D {
		let r = Rasteriser3D(width: 765, height: 503)
		r.unpackTextures(ts)
		r.setBrightness(0.8, jitter: false)
		return r
	}

	func present(_ r: Rasteriser3D, _ name: String) throws {
		var raster = Raster(width: 765, height: 503)
		r.copy(into: &raster)
		try save(raster, name)
	}

	func testBronzeAxe() throws {
		let s = try store()
		let ts = try TextureStore(config: s)
		let obj = try XCTUnwrap(try s.obj(1351))
		XCTAssertEqual(obj.model, 2544)
		let raw = try XCTUnwrap(try s.rawModel(obj.model)).copy()
		for (from, to) in obj.recolours { raw.recolor(from, to) }
		let model = raw.createModel(ambient: obj.ambient + 64, contrast: obj.contrast + 768, x: -50, y: -10, z: -50) { ts.meta.indices.contains($0) && ts.meta[$0].defined }
		for (i, yaw) in [0, 512, 1024].enumerated() {
			let r = frame(ts)
			r.clear(0x405880)
			let n = draw(model, r, yaw: yaw, distance: model.radius * 2 + 40)
			XCTAssertGreaterThan(n, 1500, "axe view \(i) is mostly empty")
			try present(r, "locmodel-axe-\(i)")
		}
		// Icon style (rt4 Inv.java): fixed-camera render, scaled up 5x for visibility.
		let r = frame(ts)
		r.clear(0x405880)
		let zoom = obj.zoom2d / 5
		let pc = (MathTables.cos[obj.xAngle2D] * zoom) >> 16, ps = (MathTables.sin[obj.xAngle2D] * zoom) >> 16
		model.renderAtOrigin(r, yAngle: obj.yAngle2D, zAngle: obj.zAngle2D, xAngle: obj.xAngle2D, x: obj.xOffset2D, y: ps + obj.yOffset2D - model.minY / 2, z: obj.yOffset2D + pc)
		try present(r, "locmodel-axe-icon")
	}

	/// Finds the first loc id whose name matches and which has models.
	func find(_ s: ConfigStore, name: String, shape: Int? = nil, limit: Int = 40000) throws -> LocType? {
		for id in 0..<limit {
			guard let l = try? s.loc(id), l.name == name, let m = l.models, !m.isEmpty else { continue }
			if let sh = shape, !(l.shapes ?? [10]).contains(sh) { continue }
			return l
		}
		return nil
	}

	func testLocs() throws {
		let s = try store()
		let ts = try TextureStore(config: s)
		let builder = LocModelBuilder(store: s) { ts.meta.indices.contains($0) && ts.meta[$0].defined }
		let wanted: [(String, Int?, Int)] = [("Tree", nil, 10), ("Oak", nil, 10), ("Door", 0, 0), ("Large door", 0, 0), ("Castle wall", 0, 0), ("Wall", 0, 0), ("Table", nil, 10), ("Fountain", nil, 10)]
		var rendered = 0
		for (name, shapeFilter, shape) in wanted {
			guard let loc = try find(s, name: name, shape: shapeFilter) else { print("no loc named \(name)"); continue }
			for rot in 0..<4 {
				guard let m = try builder.model(for: loc, shape: shape, rotation: rot) else { print("\(name) #\(loc.id): no model for shape \(shape)"); break }
				m.ensureBounds()
				let r = frame(ts)
				r.clear(0x405880)
				let dist = max(150, m.radius * 2 + 40)
				let n = draw(m, r, yaw: 0, distance: dist)
				print("\(name) #\(loc.id) shape \(shape) rot \(rot): \(m.vertexCount)v \(m.triangleCount)t bounds y \(m.minY)...\(m.maxY) radius \(m.radius) pixels \(n)")
				XCTAssertGreaterThan(n, 200, "\(name) rot \(rot) not drawn")
				try present(r, "locmodel-\(name.replacingOccurrences(of: " ", with: "_"))-\(loc.id)-r\(rot)")
				rendered += 1
			}
		}
		XCTAssertGreaterThan(rendered, 4)
	}

	/// Hillskew drapes a model over a sloped height grid and leaves the cached model untouched.
	func testTerrainFit() throws {
		let s = try store()
		let builder = LocModelBuilder(store: s)
		let loc = try XCTUnwrap(try find(s, name: "Table"))
		let m = try XCTUnwrap(try builder.model(for: loc, shape: 10, rotation: 0))
		let before = m.vertexY
		let flat = [[Int]](repeating: [Int](repeating: 0, count: 20), count: 20)
		XCTAssertTrue(m.fitToTerrain(type: 1, amount: 0, heights: flat, upper: nil, x: 640, baseY: 0, z: 640) === m)
		var slope = flat
		for x in 0..<20 { for z in 0..<20 { slope[x][z] = -x * 8 } }
		let fitted = m.fitToTerrain(type: 1, amount: 0, heights: slope, upper: nil, x: 640, baseY: slope[5][5], z: 640)
		XCTAssertFalse(fitted === m)
		XCTAssertNotEqual(fitted.vertexY, before)
		XCTAssertEqual(m.vertexY, before)
	}
}
