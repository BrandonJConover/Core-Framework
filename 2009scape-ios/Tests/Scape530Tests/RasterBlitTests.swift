import XCTest
@testable import Scape530

/// The sprite and rectangle blitters were rewritten around raw pointers; they must stay pixel-identical to the
/// straightforward per-pixel `blend` they replaced (this file keeps that reference implementation).
final class RasterBlitTests: XCTestCase {
	struct Lcg {
		var s: UInt64
		mutating func next(_ n: Int) -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int((s >> 33) % UInt64(n)) }
	}

	func sprite(_ rng: inout Lcg, alpha: Bool) -> SpriteFrame {
		let iw = 1 + rng.next(23), ih = 1 + rng.next(23)
		let xo = rng.next(5), yo = rng.next(5)
		var palette = [UInt32](repeating: 0, count: 16)
		for i in 1..<16 { palette[i] = UInt32(rng.next(0xFFFFFF)) | 1 }
		let idx = (0..<iw * ih).map { _ in UInt8(rng.next(16)) }
		let a: [UInt8]? = alpha ? (0..<iw * ih).map { _ in [0, 40, 128, 255, 255][rng.next(5)] } : nil
		return SpriteFrame(width: iw + xo + rng.next(4), height: ih + yo + rng.next(4), xOffset: xo, yOffset: yo, innerWidth: iw, innerHeight: ih, indices: idx, alpha: a, palette: palette)
	}

	func referenceDraw(_ r: inout Raster, _ f: SpriteFrame, x: Int, y: Int, opacity: Int, hFlip: Bool, vFlip: Bool) {
		let ox = x + (hFlip ? f.width - f.xOffset - f.innerWidth : f.xOffset)
		let oy = y + (vFlip ? f.height - f.yOffset - f.innerHeight : f.yOffset)
		for sy in 0..<f.innerHeight {
			let dy = oy + sy
			guard dy >= r.clipTop && dy < r.clipBottom else { continue }
			let row = (vFlip ? f.innerHeight - 1 - sy : sy) * f.innerWidth
			for sx in 0..<f.innerWidth {
				let dx = ox + sx
				guard dx >= r.clipLeft && dx < r.clipRight else { continue }
				let c = f.argb[row + (hFlip ? f.innerWidth - 1 - sx : sx)]
				let a = Int(c >> 24)
				guard a != 0 else { continue }
				r.blend(dy * r.width + dx, c & 0xFFFFFF, a == 255 ? opacity : (a * opacity) >> 8)
			}
		}
	}

	func referenceScaled(_ r: inout Raster, _ f: SpriteFrame, x: Int, y: Int, w: Int, h: Int, opacity: Int) {
		guard w > 0, h > 0, f.width > 0, f.height > 0 else { return }
		let y0 = max(y, r.clipTop), y1 = min(y + h, r.clipBottom)
		let x0 = max(x, r.clipLeft), x1 = min(x + w, r.clipRight)
		guard x0 < x1, y0 < y1 else { return }
		for dy in y0..<y1 {
			let cy = (dy - y) * f.height / h - f.yOffset
			guard cy >= 0 && cy < f.innerHeight else { continue }
			for dx in x0..<x1 {
				let cx = (dx - x) * f.width / w - f.xOffset
				guard cx >= 0 && cx < f.innerWidth else { continue }
				let c = f.argb[cy * f.innerWidth + cx]
				let a = Int(c >> 24)
				guard a != 0 else { continue }
				r.blend(dy * r.width + dx, c & 0xFFFFFF, a == 255 ? opacity : (a * opacity) >> 8)
			}
		}
	}

	func background(_ rng: inout Lcg) -> Raster {
		var r = Raster(width: 64, height: 48)
		for i in 0..<r.pixels.count { r.pixels[i] = 0xFF00_0000 | UInt32(rng.next(0xFFFFFF)) }
		r.setClip(rng.next(10), rng.next(10), 40 + rng.next(24), 30 + rng.next(18))
		return r
	}

	func testSpriteBlitMatchesReference() {
		var rng = Lcg(s: 7)
		for i in 0..<400 {
			let f = sprite(&rng, alpha: i % 2 == 0)
			var fast = background(&rng)
			var slow = fast
			let x = rng.next(90) - 20, y = rng.next(70) - 15
			let opacity = [256, 256, 200, 128, 1, 0][rng.next(6)]
			let h = rng.next(2) == 0, v = rng.next(2) == 0
			fast.draw(f, x: x, y: y, opacity: opacity, hFlip: h, vFlip: v)
			referenceDraw(&slow, f, x: x, y: y, opacity: opacity, hFlip: h, vFlip: v)
			XCTAssertEqual(fast.pixels, slow.pixels, "draw #\(i) at \(x),\(y) opacity \(opacity) flips \(h)\(v)")
		}
	}

	func testScaledBlitMatchesReference() {
		var rng = Lcg(s: 11)
		for i in 0..<300 {
			let f = sprite(&rng, alpha: i % 2 == 1)
			var fast = background(&rng)
			var slow = fast
			let x = rng.next(60) - 15, y = rng.next(50) - 10
			let w = 1 + rng.next(60), h = 1 + rng.next(50)
			let opacity = [256, 256, 180, 64, 0][rng.next(5)]
			fast.drawScaled(f, x: x, y: y, w: w, h: h, opacity: opacity)
			referenceScaled(&slow, f, x: x, y: y, w: w, h: h, opacity: opacity)
			XCTAssertEqual(fast.pixels, slow.pixels, "scaled #\(i) \(x),\(y) \(w)x\(h) opacity \(opacity)")
		}
	}

	func testFillRectMatchesBlend() {
		var rng = Lcg(s: 3)
		for i in 0..<300 {
			var fast = background(&rng)
			var slow = fast
			let x = rng.next(80) - 10, y = rng.next(60) - 10, w = rng.next(50), h = rng.next(40)
			let rgb = UInt32(rng.next(0xFFFFFF)), opacity = [256, 256, 200, 100, 1, 0][rng.next(6)]
			fast.fillRect(x, y, w, h, rgb, opacity: opacity)
			let x0 = max(x, slow.clipLeft), x1 = min(x + w, slow.clipRight), y0 = max(y, slow.clipTop), y1 = min(y + h, slow.clipBottom)
			if x0 < x1 && y0 < y1 { for yy in y0..<y1 { for xx in x0..<x1 { slow.blend(yy * slow.width + xx, rgb, opacity) } } }
			XCTAssertEqual(fast.pixels, slow.pixels, "fillRect #\(i)")
		}
	}

	func testRasteriserCopyHonoursClip() {
		var rng = Lcg(s: 5)
		let r3 = Rasteriser3D(width: 30, height: 20)
		for i in 0..<30 * 20 { r3.px[i] = Int32(truncatingIfNeeded: rng.next(0xFFFFFF)) }
		for _ in 0..<100 {
			var fast = background(&rng)
			var slow = fast
			let x = rng.next(60) - 20, y = rng.next(40) - 15
			r3.copy(into: &fast, x: x, y: y)
			for sy in 0..<20 { for sx in 0..<30 {
				let dx = x + sx, dy = y + sy
				if dx >= slow.clipLeft && dx < slow.clipRight && dy >= slow.clipTop && dy < slow.clipBottom {
					slow.pixels[dy * slow.width + dx] = 0xFF00_0000 | UInt32(bitPattern: r3.px[sy * 30 + sx])
				}
			} }
			XCTAssertEqual(fast.pixels, slow.pixels)
		}
	}

	func testClearResetsPixelsAndClip() {
		var r = Raster(width: 8, height: 6)
		r.setClip(2, 2, 5, 5)
		r.fillRect(0, 0, 8, 6, 0x123456)
		r.clear()
		XCTAssertEqual(r.pixels, Raster(width: 8, height: 6).pixels)
		XCTAssertEqual(r.clipRight, 8)
		XCTAssertEqual(r.clipBottom, 6)
		XCTAssertEqual(r.clipLeft, 0)
	}
}
