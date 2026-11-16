import Foundation
import XCTest
@testable import Scape530

/// Port checks for `Rasteriser3D` (rt4 `Rasteriser`). The reference numbers
/// come from running the original rt4 Java class on the same inputs.
final class RasteriserTests: XCTestCase {
	/// java.util.Random, to replay the scenario used for the Java reference.
	struct JavaRandom {
		var seed: Int64
		init(_ s: Int64) { seed = (s ^ 0x5DEECE66D) & ((1 << 48) - 1) }
		mutating func next(_ bits: Int) -> Int32 {
			seed = (seed &* 0x5DEECE66D &+ 0xB) & ((1 << 48) - 1)
			return Int32(truncatingIfNeeded: seed >> Int64(48 - bits))
		}
		mutating func nextInt(_ bound: Int32) -> Int32 {
			if bound & (bound &- 1) == 0 { return Int32(truncatingIfNeeded: (Int64(bound) &* Int64(next(31))) >> 31) }
			while true {
				let bits = next(31)
				let val = bits % bound
				if bits &- val &+ (bound &- 1) >= 0 { return val }
			}
		}
	}

	/// 128x128 checkerboard with 16 texel squares.
	final class Checker: TextureSource {
		let t: [Int32]
		init(a: Int32 = 0xE0C040, b: Int32 = 0x4060C0) {
			t = (0..<16384).map { i in (((i & 127) >> 4) ^ ((i >> 7) >> 4)) & 1 == 0 ? a : b }
		}
		func texels(_ id: Int, brightness: Float) -> [Int32]? { t }
		func averageColor(_ id: Int) -> Int { 5000 }
		func isLowDetail(_ id: Int) -> Bool { false }
		func isOpaque(_ id: Int) -> Bool { true }
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	func make(_ w: Int, _ h: Int) -> Rasteriser3D {
		let r = Rasteriser3D(width: w, height: h)
		r.setBrightness(0.8, jitter: false)
		return r
	}

	func testPaletteExact() {
		let r = make(10, 10)
		// Values from rt4's calculateBrightness at gamma 0.8 (Java harness).
		let expected: [Int: Int32] = [0: 1, 1: 328965, 64: 10128523, 127: 16711422, 128: 1,
			1000: 16627378, 12345: 9079935, 30000: 5673348, 40000: 9146522, 65535: 16776445]
		for (i, v) in expected { XCTAssertEqual(r.palette[i], v, "palette[\(i)]") }
		var h: Int64 = 0
		for v in r.palette { h = h &* 31 &+ Int64(v) }
		XCTAssertEqual(h, 4717172655031360954)
	}

	/// Replays the Java scenario (30 flat, 30 gouraud, 40 textured triangles
	/// with random, partly off-screen vertices) and compares a hash of the
	/// whole framebuffer with the one rt4 produced.
	func testMatchesRt4Reference() {
		let W = 200, H = 150
		let r = make(W, H)
		r.unpackTextures(Checker())
		var rnd = JavaRandom(1)
		func tri() -> ([Int32], [Int32]) {
			let y = (0..<3).map { _ in rnd.nextInt(220) - 40 }
			let x = (0..<3).map { _ in rnd.nextInt(300) - 50 }
			return (y, x)
		}
		for i in 0..<30 {
			let (y, x) = tri()
			r.testPoints(x[0], x[1], x[2])
			r.alpha = i % 3 == 0 ? 0 : (i % 3 == 1 ? 100 : 254)
			r.fillTriangle(y[0], y[1], y[2], x[0], x[1], x[2], rnd.nextInt(0xFFFFFF))
		}
		r.alpha = 0
		for i in 0..<30 {
			let hs = rnd.nextInt(512)
			let (y, x) = tri()
			r.testPoints(x[0], x[1], x[2])
			r.alpha = i % 3 == 0 ? 0 : (i % 3 == 1 ? 120 : 200)
			r.jagged = i % 2 == 0
			let c = (0..<3).map { _ in (hs << 7) + rnd.nextInt(128) }
			r.fillGouraudTriangle(y[0], y[1], y[2], x[0], x[1], x[2], c[0], c[1], c[2])
		}
		r.alpha = 0
		r.jagged = true
		for i in 0..<40 {
			let (y, x) = tri()
			let vx = (0..<3).map { _ in rnd.nextInt(2000) - 1000 }
			let vy = (0..<3).map { _ in rnd.nextInt(2000) - 1000 }
			let vz = (0..<3).map { _ in rnd.nextInt(2000) + 200 }
			r.testPoints(x[0], x[1], x[2])
			r.alpha = i % 4 == 3 ? 5 : 0
			let c0 = rnd.nextInt(128) + (rnd.nextInt(512) << 7)
			let c1 = rnd.nextInt(128), c2 = rnd.nextInt(128)
			if i % 2 == 0 {
				r.fillTexturedTriangle(y[0], y[1], y[2], x[0], x[1], x[2], c0 & 127, c1, c2, vx[0], vx[1], vx[2], vy[0], vy[1], vy[2], vz[0], vz[1], vz[2], 3)
			} else {
				r.fillTexturedAlphaTriangle(y[0], y[1], y[2], x[0], x[1], x[2], c0 & 127, c1, c2, vx[0], vx[1], vx[2], vy[0], vy[1], vy[2], vz[0], vz[1], vz[2], 3)
			}
		}
		var h: Int64 = 0
		for v in r.pixels { h = h &* 31 &+ Int64(v) }
		XCTAssertEqual(h, 2733282958824329040)
	}

	/// HSL16 helper: hue 0...63, saturation 0...7, lightness 0...127.
	func hsl(_ h: Int32, _ s: Int32, _ l: Int32) -> Int32 { (h << 10) + (s << 7) + l }

	func testShapes() throws {
		let r = make(400, 300)
		r.clear(0x202830)
		// Flat triangles.
		r.testPoints(20, 80, 140)
		r.fillTriangle(20, 20, 100, 20, 140, 80, Int32(r.palette[Int(hsl(5, 6, 70))]))
		// Gouraud, three HSL colours.
		r.testPoints(170, 290, 230)
		r.fillGouraudTriangle(20, 20, 100, 170, 290, 230, hsl(5, 7, 120), hsl(5, 7, 30), hsl(5, 7, 70))
		// Alpha over a flat backdrop.
		r.testPoints(0, 150, 150)
		r.fillTriangle(130, 130, 230, 20, 200, 110, r.palette[Int(hsl(42, 5, 50))])
		r.alpha = 128
		r.testPoints(60, 220, 140)
		r.fillGouraudTriangle(150, 150, 260, 60, 220, 140, hsl(10, 7, 90), hsl(10, 7, 40), hsl(10, 7, 100))
		r.alpha = 0
		// Clipped at the screen edges.
		r.testPoints(-40, 120, 60)
		r.fillGouraudTriangle(-30, 60, 40, 300, 440, 330, hsl(30, 7, 120), hsl(30, 7, 30), hsl(30, 7, 80))
		r.testPoints(-60, 80, 20)
		r.fillGouraudTriangle(250, 310, 330, 330, 440, 380, hsl(52, 7, 120), hsl(52, 7, 60), hsl(52, 7, 30))
		// Degenerate (collinear): must draw nothing and not crash.
		let before = r.pixels
		r.testPoints(10, 20, 30)
		r.fillGouraudTriangle(280, 285, 290, 10, 20, 30, hsl(1, 1, 1), hsl(1, 1, 1), hsl(1, 1, 1))
		XCTAssertEqual(before, r.pixels)
		XCTAssertEqual(r.pixels.filter { $0 != 0x202830 }.count > 5000, true)
		var out = Raster(width: 400, height: 300)
		r.copy(into: &out)
		try save(out, "raster3d-shapes")
	}

	func testPerspectiveQuad() throws {
		let r = make(400, 300)
		r.clear(0x000000)
		r.unpackTextures(Checker())
		r.setBounds(200, 150)
		// A floor quad in camera space: y down, z away from the camera.
		// Texture space: origin A, U along +x, V along +z, one texture per U x V.
		let pts: [(Int32, Int32, Int32)] = [(-300, 100, 200), (300, 100, 200), (300, 100, 1200), (-300, 100, 1200)]
		let sx = pts.map { 200 + $0.0 * 512 / $0.2 }
		let sy = pts.map { 150 + $0.1 * 512 / $0.2 }
		r.testPoints(sx[0], sx[1], sx[2])
		// rt4 passes the texture-space basis as the first three view points.
		func tri(_ a: Int, _ b: Int, _ c: Int) {
			r.fillTexturedTriangle(sy[a], sy[b], sy[c], sx[a], sx[b], sx[c], 127, 127, 127,
				pts[0].0, pts[1].0, pts[3].0, pts[0].1, pts[1].1, pts[3].1, pts[0].2, pts[1].2, pts[3].2, 1)
		}
		tri(0, 1, 2)
		tri(0, 2, 3)
		var out = Raster(width: 400, height: 300)
		r.copy(into: &out)
		try save(out, "raster3d-checker")
		XCTAssertGreaterThan(r.pixels.filter { $0 != 0 }.count, 5000)
		// Perspective correctness: the squares near the horizon are narrower
		// than the ones near the camera, along a scanline.
		func transitions(_ y: Int) -> Int {
			var n = 0
			for x in 1..<400 {
				let a = r.pixels[y * 400 + x], b = r.pixels[y * 400 + x - 1]
				if a != b && a != 0 && b != 0 { n += 1 }
			}
			return n
		}
		XCTAssertGreaterThan(transitions(Int(sy[3]) + 8), 0)
	}

	func testTiming() {
		let r = make(765, 503)
		var rnd = JavaRandom(7)
		let t0 = Date()
		for _ in 0..<2000 {
			let hs = rnd.nextInt(512)
			let y = (0..<3).map { _ in rnd.nextInt(503) }
			let x = (0..<3).map { _ in rnd.nextInt(765) }
			r.testPoints(x[0], x[1], x[2])
			let c = (0..<3).map { _ in (hs << 7) + rnd.nextInt(128) }
			r.fillGouraudTriangle(y[0], y[1], y[2], x[0], x[1], x[2], c[0], c[1], c[2])
		}
		print("raster3d: 2000 random gouraud triangles on 765x503 in \(Date().timeIntervalSince(t0)) s")
	}
}
