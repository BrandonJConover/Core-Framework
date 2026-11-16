import Foundation
import XCTest
@testable import Scape530

final class ModelTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	func testEveryModelDecodes() throws {
		let s = try store()
		let idx = try s.index(ConfigStore.modelsArchive)
		var failures: [String] = []
		var ok = 0, verts = 0, tris = 0, oldFmt = 0
		for g in idx.groupIds {
			do {
				guard let m = try s.rawModel(g) else { failures.append("model \(g): missing"); continue }
				// sanity: indices in range
				for t in 0..<m.triangleCount {
					if max(m.triangleVertexA[t], m.triangleVertexB[t], m.triangleVertexC[t]) >= m.vertexCount { throw RawModel.DecodeError(description: "index out of range") }
				}
				ok += 1; verts += m.vertexCount; tris += m.triangleCount
				if m.triangleBones == nil && m.boneTriangles == nil { oldFmt += 0 }
			} catch { failures.append("model \(g): \(error)") }
			s.cache.removeValue(forKey: "RawModel#\(g)")
		}
		XCTAssertEqual(failures.prefix(10).map { $0 }, [])
		print("decoded \(ok) of \(idx.groupIds.count) models, \(verts) vertices, \(tris) triangles, failures \(failures.count)")
	}

	func testBronzeAxeAndLighting() throws {
		let s = try store()
		let obj = try XCTUnwrap(try s.obj(1351))
		let m = try XCTUnwrap(try s.rawModel(obj.model))
		print("bronze axe model \(obj.model): \(m.vertexCount) verts, \(m.triangleCount) tris, textured \(m.texturedCount)")
		XCTAssertGreaterThan(m.vertexCount, 10); XCTAssertLessThan(m.vertexCount, 2000)
		XCTAssertGreaterThan(m.triangleCount, 10)
		let lit = m.copy().createModel(ambient: 64, contrast: 768, x: -50, y: -10, z: -50)
		XCTAssertEqual(lit.triangleColorA.count, m.triangleCount)
		XCTAssertEqual(lit.triangleColorB.count, m.triangleCount)
		XCTAssertEqual(lit.triangleColorC.count, m.triangleCount)
		lit.calculateBounds()
		XCTAssertLessThan(lit.minX, lit.maxX)

		// Light a spread of models and check markers.
		let idx = try s.index(ConfigStore.modelsArchive)
		var flat = 0, hidden = 0, gouraud = 0
		for g in idx.groupIds.prefix(400) {
			guard let raw = try s.rawModel(g)?.copy() else { continue }
			let l = raw.createModel(ambient: 64, contrast: 768, x: -50, y: -10, z: -50)
			XCTAssertEqual(l.triangleColorC.count, raw.triangleCount)
			for c in l.triangleColorC { if c == -1 { flat += 1 } else if c == -2 { hidden += 1 } else { gouraud += 1 } }
		}
		print("lit 400 models: gouraud \(gouraud) flat \(flat) hidden \(hidden)")
		XCTAssertGreaterThan(gouraud, 0)
	}

	func testMergeAndTransforms() throws {
		let s = try store()
		let a = try XCTUnwrap(try s.rawModel(try XCTUnwrap(try s.obj(1351)).model)).copy()
		let b = try XCTUnwrap(try s.rawModel(try XCTUnwrap(try s.obj(1349)).model)).copy()
		let merged = RawModel(merging: [a, b])
		XCTAssertEqual(merged.triangleCount, a.triangleCount + b.triangleCount)
		XCTAssertLessThanOrEqual(merged.vertexCount, a.vertexCount + b.vertexCount)
		let x0 = a.vertexX
		a.rotateY90(); a.rotateY270()
		XCTAssertEqual(a.vertexX, x0)
		a.recolor(Int(a.triangleColors[0]), 1234)
		XCTAssertEqual(a.triangleColors[0], 1234)
	}

	func testWireframe() throws {
		let s = try store()
		let obj = try XCTUnwrap(try s.obj(1351))
		let raw = try XCTUnwrap(try s.rawModel(obj.model)).copy()
		let m = raw.createModel(ambient: 64, contrast: 768, x: -50, y: -10, z: -50)
		m.rotateX(1900); m.rotateY(300)
		m.calculateBounds()
		var r = Raster(width: 256, height: 256, fill: 0xFF202020)
		let span = max(m.maxX - m.minX, m.maxY - m.minY, 1)
		let sc = 220.0 / Double(span)
		func p(_ i: Int) -> (Int, Int) { (128 + Int(Double(m.vertexX[i] - (m.minX + m.maxX) / 2) * sc), 128 + Int(Double(m.vertexY[i] - (m.minY + m.maxY) / 2) * sc)) }
		for t in 0..<m.triangleCount where m.triangleColorC[t] != -2 {
			let (a, b, c) = (p(m.triangleVertexA[t]), p(m.triangleVertexB[t]), p(m.triangleVertexC[t]))
			r.drawLine(a.0, a.1, b.0, b.1, 0xFFFFFF); r.drawLine(b.0, b.1, c.0, c.1, 0xFFFFFF); r.drawLine(c.0, c.1, a.0, a.1, 0xFFFFFF)
		}
		try save(r, "model-bronze-axe")
	}
}
