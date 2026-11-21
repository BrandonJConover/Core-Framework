import Foundation

/// The labels' font (rt4 `WorldMapFont`).
///
/// rt4 pre-renders AWT's bold Helvetica at 11, 12, 14, 17, 19, 22, 26 and 30 pixels. There is no AWT here, so this
/// scales the cache's bold 12 point bitmap font to the same sizes, anti-aliasing the edges by area sampling, and keeps
/// rt4's measuring, centring and drop shadow.
final class WorldMapFont {
	struct Glyph {
		var x: Int, y: Int, w: Int, h: Int
		var alpha: [UInt8]
	}

	let size: Int
	private let base: BitmapFont
	private let scale: Double
	private var glyphs: [Int: Glyph] = [:]
	/// rt4 `method1503`: the line advance.
	let lineHeight: Int
	/// rt4 `method1511`: the height of a capital letter (above the baseline).
	let capHeight: Int

	/// The base font is built for 12 pixel text with room for ascenders (line height 12-13).
	static let referenceSize = 12.5

	init(size: Int, base: BitmapFont) {
		self.size = size
		self.base = base
		scale = Double(size) / WorldMapFont.referenceSize
		lineHeight = max(Int(Double(size) * 1.15) - 1, 1)
		let a = base.glyphs[Int(UInt8(ascii: "A"))]
		capHeight = max(Int((Double(a.innerHeight) * Double(size) / WorldMapFont.referenceSize).rounded()), 1)
	}

	private func advance(_ c: Int) -> Int { Int((Double(base.glyphWidths[c]) * scale).rounded()) }

	/// rt4 `getStringWidth`: `@abcd@` and `~abcd~` colour tags take no room.
	func width(_ s: [UInt8]) -> Int {
		var w = 0, i = 0
		while i < s.count {
			let c = s[i]
			if (c == 64 || c == 126) && i + 4 < s.count && s[i + 4] == c { i += 5; continue }
			w += advance(Int(c))
			i += 1
		}
		return w
	}

	private func glyph(_ c: Int) -> Glyph? {
		if let g = glyphs[c] { return g }
		guard c < base.glyphs.count else { return nil }
		let f = base.glyphs[c]
		var g: Glyph?
		if f.innerWidth > 0 && f.innerHeight > 0 {
			// Where the glyph's pixels sit relative to the pen (x) and the baseline (y), in destination pixels.
			let gx = Double(f.xOffset) * scale
			let gy = Double(f.yOffset - base.lineHeight) * scale
			let x0 = Int(gx.rounded(.down)), y0 = Int(gy.rounded(.down))
			let x1 = Int((gx + Double(f.innerWidth) * scale).rounded(.up)), y1 = Int((gy + Double(f.innerHeight) * scale).rounded(.up))
			let w = x1 - x0, h = y1 - y0
			var alpha = [UInt8](repeating: 0, count: w * h)
			let samples = 3
			for py in 0..<h {
				for px in 0..<w {
					var hit = 0
					for sy in 0..<samples {
						let v = (Double(y0 + py) + (Double(sy) + 0.5) / Double(samples) - gy) / scale
						let iy = Int(v.rounded(.down))
						guard iy >= 0, iy < f.innerHeight else { continue }
						for sx in 0..<samples {
							let u = (Double(x0 + px) + (Double(sx) + 0.5) / Double(samples) - gx) / scale
							let ix = Int(u.rounded(.down))
							if ix >= 0, ix < f.innerWidth, f.indices[iy * f.innerWidth + ix] != 0 { hit += 1 }
						}
					}
					alpha[py * w + px] = UInt8(hit * 255 / (samples * samples))
				}
			}
			g = Glyph(x: x0, y: y0, w: w, h: h, alpha: alpha)
		}
		if let g { glyphs[c] = g }
		return g
	}

	private func draw(_ s: [UInt8], x startX: Int, y baseline: Int, color: UInt32, shadow: Bool, into r: inout Raster) {
		var x = startX
		var i = 0
		while i < s.count {
			let c = Int(s[i])
			i += 1
			guard let g = glyph(c) else { x += advance(c); continue }
			if shadow {
				blit(g, x + 1, baseline, 0, 160, &r)
				blit(g, x, baseline + 1, 0, 160, &r)
			}
			blit(g, x, baseline, color, 256, &r)
			x += advance(c)
		}
	}

	private func blit(_ g: Glyph, _ x: Int, _ baseline: Int, _ rgb: UInt32, _ opacity: Int, _ r: inout Raster) {
		let ox = x + g.x, oy = baseline + g.y
		for py in 0..<g.h {
			let dy = oy + py
			guard dy >= r.clipTop, dy < r.clipBottom else { continue }
			for px in 0..<g.w {
				let a = Int(g.alpha[py * g.w + px])
				guard a > 8 else { continue }
				let dx = ox + px
				guard dx >= r.clipLeft, dx < r.clipRight else { continue }
				r.blend(dy * r.width + dx, rgb, (a * opacity) >> 8)
			}
		}
	}

	/// rt4 `renderStringCenter`: `baseline` is the text's baseline.
	func drawCentered(_ text: String, x: Int, baseline: Int, color: UInt32, into r: inout Raster) {
		let s = Cp1252.encode(text)
		let half = width(s) / 2
		if x - half > r.clipRight || x + half < r.clipLeft || baseline - capHeight > r.clipBottom || baseline < 0 { return }
		draw(s, x: x - half, y: baseline, color: color, shadow: color != 0, into: &r)
	}
}
