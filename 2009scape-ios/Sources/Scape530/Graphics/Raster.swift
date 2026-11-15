/// Software 2D framebuffer, the Swift counterpart of rt4 `SoftwareRaster`.
/// Pixels are opaque 0xFFRRGGBB. Everything the UI draws (sprites, fonts,
/// interface rectangles) goes through here; the app uploads the buffer to the
/// screen as a texture, and tests write it out as PNG.
public struct Raster {
	public let width: Int
	public let height: Int
	public var pixels: [UInt32]
	public private(set) var clipLeft = 0
	public private(set) var clipTop = 0
	public private(set) var clipRight: Int
	public private(set) var clipBottom: Int

	public init(width: Int, height: Int, fill: UInt32 = 0) {
		self.width = width
		self.height = height
		pixels = [UInt32](repeating: 0xFF00_0000 | fill, count: width * height)
		clipRight = width
		clipBottom = height
	}

	public mutating func setClip(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
		clipLeft = max(0, x0)
		clipTop = max(0, y0)
		clipRight = min(width, x1)
		clipBottom = min(height, y1)
	}

	public mutating func resetClip() { setClip(0, 0, width, height) }

	/// Blends `rgb` over the pixel at `i` with `opacity` 0...256 (rt4 style).
	@inline(__always)
	mutating func blend(_ i: Int, _ rgb: UInt32, _ opacity: Int) {
		if opacity >= 256 {
			pixels[i] = 0xFF00_0000 | rgb
			return
		}
		if opacity <= 0 { return }
		let a = UInt32(opacity), ia = 256 - a
		let d = pixels[i]
		let rb = ((rgb & 0xFF00FF) &* a &+ (d & 0xFF00FF) &* ia) >> 8 & 0xFF00FF
		let g = ((rgb & 0x00FF00) &* a &+ (d & 0x00FF00) &* ia) >> 8 & 0x00FF00
		pixels[i] = 0xFF00_0000 | rb | g
	}

	public mutating func fillRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ rgb: UInt32, opacity: Int = 256) {
		let x0 = max(x, clipLeft), x1 = min(x + w, clipRight)
		let y0 = max(y, clipTop), y1 = min(y + h, clipBottom)
		guard x0 < x1, y0 < y1 else { return }
		for yy in y0..<y1 {
			let row = yy * width
			for xx in x0..<x1 { blend(row + xx, rgb, opacity) }
		}
	}

	public mutating func hline(_ x: Int, _ y: Int, _ w: Int, _ rgb: UInt32, opacity: Int = 256) {
		fillRect(x, y, w, 1, rgb, opacity: opacity)
	}

	public mutating func vline(_ x: Int, _ y: Int, _ h: Int, _ rgb: UInt32, opacity: Int = 256) {
		fillRect(x, y, 1, h, rgb, opacity: opacity)
	}

	public mutating func drawRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ rgb: UInt32, opacity: Int = 256) {
		hline(x, y, w, rgb, opacity: opacity)
		hline(x, y + h - 1, w, rgb, opacity: opacity)
		vline(x, y, h, rgb, opacity: opacity)
		vline(x + w - 1, y, h, rgb, opacity: opacity)
	}

	/// Bresenham line (interface type 9).
	public mutating func drawLine(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ rgb: UInt32) {
		var x = x0, y = y0
		let dx = abs(x1 - x0), dy = -abs(y1 - y0)
		let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
		var err = dx + dy
		while true {
			if x >= clipLeft && x < clipRight && y >= clipTop && y < clipBottom { pixels[y * width + x] = 0xFF00_0000 | rgb }
			if x == x1 && y == y1 { break }
			let e2 = 2 * err
			if e2 >= dy { err += dy; x += sx }
			if e2 <= dx { err += dx; y += sy }
		}
	}

	/// Draws a sprite frame with its canvas at (x, y), honouring transparency,
	/// the frame's alpha plane and an extra `opacity` (0...256).
	public mutating func draw(_ f: SpriteFrame, x: Int, y: Int, opacity: Int = 256, hFlip: Bool = false, vFlip: Bool = false) {
		let ox = x + (hFlip ? f.width - f.xOffset - f.innerWidth : f.xOffset)
		let oy = y + (vFlip ? f.height - f.yOffset - f.innerHeight : f.yOffset)
		let src = f.argb
		for sy in 0..<f.innerHeight {
			let dy = oy + sy
			guard dy >= clipTop && dy < clipBottom else { continue }
			let row = (vFlip ? f.innerHeight - 1 - sy : sy) * f.innerWidth
			for sx in 0..<f.innerWidth {
				let dx = ox + sx
				guard dx >= clipLeft && dx < clipRight else { continue }
				let c = src[row + (hFlip ? f.innerWidth - 1 - sx : sx)]
				let a = Int(c >> 24)
				guard a != 0 else { continue }
				blend(dy * width + dx, c & 0xFFFFFF, a == 255 ? opacity : (a * opacity) >> 8)
			}
		}
	}

	/// rt4 `renderResized`: scales the whole canvas (offsets included) into w×h.
	public mutating func drawScaled(_ f: SpriteFrame, x: Int, y: Int, w: Int, h: Int, opacity: Int = 256) {
		guard w > 0, h > 0, f.width > 0, f.height > 0 else { return }
		let src = f.argb
		let y0 = max(y, clipTop), y1 = min(y + h, clipBottom)
		let x0 = max(x, clipLeft), x1 = min(x + w, clipRight)
		guard x0 < x1, y0 < y1 else { return }
		for dy in y0..<y1 {
			let cy = (dy - y) * f.height / h - f.yOffset
			guard cy >= 0 && cy < f.innerHeight else { continue }
			for dx in x0..<x1 {
				let cx = (dx - x) * f.width / w - f.xOffset
				guard cx >= 0 && cx < f.innerWidth else { continue }
				let c = src[cy * f.innerWidth + cx]
				let a = Int(c >> 24)
				guard a != 0 else { continue }
				blend(dy * width + dx, c & 0xFFFFFF, a == 255 ? opacity : (a * opacity) >> 8)
			}
		}
	}

	/// Repeats a frame across a rectangle (interface sprite tiling).
	public mutating func drawTiled(_ f: SpriteFrame, x: Int, y: Int, w: Int, h: Int, opacity: Int = 256) {
		guard f.width > 0, f.height > 0 else { return }
		let saved = (clipLeft, clipTop, clipRight, clipBottom)
		setClip(max(x, saved.0), max(y, saved.1), min(x + w, saved.2), min(y + h, saved.3))
		var ty = y
		while ty < y + h {
			var tx = x
			while tx < x + w {
				draw(f, x: tx, y: ty, opacity: opacity)
				tx += f.width
			}
			ty += f.height
		}
		setClip(saved.0, saved.1, saved.2, saved.3)
	}

	/// Fills the set pixels of a 1-byte mask (font glyphs) with `rgb`.
	public mutating func drawMask(_ mask: [UInt8], w: Int, h: Int, x: Int, y: Int, rgb: UInt32, opacity: Int = 256) {
		for sy in 0..<h {
			let dy = y + sy
			guard dy >= clipTop && dy < clipBottom else { continue }
			for sx in 0..<w where mask[sy * w + sx] != 0 {
				let dx = x + sx
				guard dx >= clipLeft && dx < clipRight else { continue }
				blend(dy * width + dx, rgb, opacity)
			}
		}
	}

	/// Copies another raster in (used to compose layers).
	public mutating func blit(_ r: Raster, x: Int, y: Int) {
		for sy in 0..<r.height {
			let dy = y + sy
			guard dy >= clipTop && dy < clipBottom else { continue }
			for sx in 0..<r.width {
				let dx = x + sx
				guard dx >= clipLeft && dx < clipRight else { continue }
				pixels[dy * width + dx] = r.pixels[sy * r.width + sx]
			}
		}
	}
}
