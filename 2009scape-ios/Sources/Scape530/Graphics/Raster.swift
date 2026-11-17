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

	/// - Parameter transparent: starts fully transparent (alpha 0) instead of opaque black, for the 2D layer
	///   the GPU renderer composites over its 3D scene. Partial blends then accumulate alpha (see `blend`).
	public init(width: Int, height: Int, fill: UInt32 = 0, transparent: Bool = false) {
		self.width = width
		self.height = height
		pixels = [UInt32](repeating: transparent ? 0 : 0xFF00_0000 | fill, count: width * height)
		clipRight = width
		clipBottom = height
	}

	/// Back to a blank opaque frame with the full clip, reusing the pixel buffer when nothing else holds it.
	public mutating func clear(fill: UInt32 = 0, transparent: Bool = false) {
		let c: UInt32 = transparent ? 0 : 0xFF00_0000 | fill
		pixels.withUnsafeMutableBufferPointer { $0.update(repeating: c) }
		clipLeft = 0; clipTop = 0; clipRight = width; clipBottom = height
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
		if d >> 24 != 0xFF {
			// Over a transparent / translucent pixel (GPU mode's 2D layer): straight-alpha "over".
			let da = d >> 24
			if da == 0 { pixels[i] = (min(a, 255) << 24) | rgb; return }
			let dw = (da * ia) >> 8
			let ra = min(255, a + dw)
			func ch(_ shift: UInt32) -> UInt32 { min(255, (((rgb >> shift) & 0xFF) * a + ((d >> shift) & 0xFF) * dw) / max(ra, 1)) }
			pixels[i] = (ra << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)
			return
		}
		let rb = ((rgb & 0xFF00FF) &* a &+ (d & 0xFF00FF) &* ia) >> 8 & 0xFF00FF
		let g = ((rgb & 0x00FF00) &* a &+ (d & 0x00FF00) &* ia) >> 8 & 0x00FF00
		pixels[i] = 0xFF00_0000 | rb | g
	}

	public mutating func fillRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ rgb: UInt32, opacity: Int = 256) {
		let x0 = max(x, clipLeft), x1 = min(x + w, clipRight)
		let y0 = max(y, clipTop), y1 = min(y + h, clipBottom)
		guard x0 < x1, y0 < y1, opacity > 0 else { return }
		let stride = width
		pixels.withUnsafeMutableBufferPointer { buf in
			let base = buf.baseAddress!
			if opacity >= 256 {
				let c = 0xFF00_0000 | rgb
				for yy in y0..<y1 { (base + yy * stride + x0).update(repeating: c, count: x1 - x0) }
				return
			}
			let a = UInt32(opacity), ia = 256 - a
			let srb = (rgb & 0xFF00FF) &* a, sg = (rgb & 0x00FF00) &* a
			for yy in y0..<y1 {
				let row = base + yy * stride
				for xx in x0..<x1 {
					let d = row[xx]
					let rb = (srb &+ (d & 0xFF00FF) &* ia) >> 8 & 0xFF00FF
					let g = (sg &+ (d & 0x00FF00) &* ia) >> 8 & 0x00FF00
					row[xx] = 0xFF00_0000 | rb | g
				}
			}
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
		let iw = f.innerWidth, ih = f.innerHeight
		// Columns of the sprite that land inside the clip rectangle.
		let sx0 = max(0, clipLeft - ox), sx1 = min(iw, clipRight - ox)
		guard sx0 < sx1, opacity > 0 else { return }
		let w = width, top = clipTop, bottom = clipBottom
		f.argb.withUnsafeBufferPointer { src in pixels.withUnsafeMutableBufferPointer { dst in
			for sy in 0..<ih {
				let dy = oy + sy
				guard dy >= top && dy < bottom else { continue }
				let srow = src.baseAddress! + (vFlip ? ih - 1 - sy : sy) * iw
				let drow = dst.baseAddress! + dy * w + ox
				for sx in sx0..<sx1 {
					let c = srow[hFlip ? iw - 1 - sx : sx]
					let a = Int(c >> 24)
					guard a != 0 else { continue }
					let o = a == 255 ? opacity : (a * opacity) >> 8
					if o >= 256 {
						drow[sx] = 0xFF00_0000 | (c & 0xFFFFFF)
					} else if o > 0 {
						let rgb = c & 0xFFFFFF
						let ao = UInt32(o), ia = 256 - ao
						let d = drow[sx]
						let rb = ((rgb & 0xFF00FF) &* ao &+ (d & 0xFF00FF) &* ia) >> 8 & 0xFF00FF
						let g = ((rgb & 0x00FF00) &* ao &+ (d & 0x00FF00) &* ia) >> 8 & 0x00FF00
						drow[sx] = 0xFF00_0000 | rb | g
					}
				}
			}
		} }
	}

	/// rt4 `renderResized`: scales the whole canvas (offsets included) into w×h.
	public mutating func drawScaled(_ f: SpriteFrame, x: Int, y: Int, w: Int, h: Int, opacity: Int = 256) {
		guard w > 0, h > 0, f.width > 0, f.height > 0 else { return }
		let y0 = max(y, clipTop), y1 = min(y + h, clipBottom)
		let x0 = max(x, clipLeft), x1 = min(x + w, clipRight)
		guard x0 < x1, y0 < y1 else { return }
		let iw = f.innerWidth, ih = f.innerHeight, fw = f.width, fh = f.height, fxo = f.xOffset, fyo = f.yOffset
		let stride = width
		// Source column for every destination column (the per-pixel divide hoisted out of the row loop).
		var cols = [Int](repeating: -1, count: x1 - x0)
		for dx in x0..<x1 {
			let cx = (dx - x) * fw / w - fxo
			if cx >= 0 && cx < iw { cols[dx - x0] = cx }
		}
		f.argb.withUnsafeBufferPointer { src in pixels.withUnsafeMutableBufferPointer { dst in cols.withUnsafeBufferPointer { cols in
			for dy in y0..<y1 {
				let cy = (dy - y) * fh / h - fyo
				guard cy >= 0 && cy < ih else { continue }
				let srow = src.baseAddress! + cy * iw
				let drow = dst.baseAddress! + dy * stride
				for dx in x0..<x1 {
					let cx = cols[dx - x0]
					guard cx >= 0 else { continue }
					let c = srow[cx]
					let a = Int(c >> 24)
					guard a != 0 else { continue }
					let o = a == 255 ? opacity : (a * opacity) >> 8
					if o >= 256 {
						drow[dx] = 0xFF00_0000 | (c & 0xFFFFFF)
					} else if o > 0 {
						let rgb = c & 0xFFFFFF
						let ao = UInt32(o), ia = 256 - ao
						let d = drow[dx]
						let rb = ((rgb & 0xFF00FF) &* ao &+ (d & 0xFF00FF) &* ia) >> 8 & 0xFF00FF
						let g = ((rgb & 0x00FF00) &* ao &+ (d & 0x00FF00) &* ia) >> 8 & 0x00FF00
						drow[dx] = 0xFF00_0000 | rb | g
					}
				}
			}
		} } }
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
