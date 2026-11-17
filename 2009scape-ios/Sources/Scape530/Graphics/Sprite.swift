/// One frame of a sprite group, as decoded by rt4 `SpriteLoader.decode`.
/// Pixels are palette indices; index 0 is transparent.
public struct SpriteFrame {
	/// Full (canvas) size shared by every frame of the group.
	public let width: Int
	public let height: Int
	/// Where the trimmed pixel block sits inside the canvas.
	public let xOffset: Int
	public let yOffset: Int
	public let innerWidth: Int
	public let innerHeight: Int
	public let indices: [UInt8]
	/// Per-pixel alpha (255 = opaque) when the frame carries an alpha plane.
	public let alpha: [UInt8]?
	public let palette: [UInt32]

	/// 0xAARRGGBB pixels of the trimmed block, ready to blend. Computed once when the frame is decoded:
	/// the blitters read it for every draw.
	public let argb: [UInt32]

	public init(width: Int, height: Int, xOffset: Int, yOffset: Int, innerWidth: Int, innerHeight: Int,
	            indices: [UInt8], alpha: [UInt8]?, palette: [UInt32]) {
		self.width = width; self.height = height
		self.xOffset = xOffset; self.yOffset = yOffset
		self.innerWidth = innerWidth; self.innerHeight = innerHeight
		self.indices = indices; self.alpha = alpha; self.palette = palette
		var out = [UInt32](repeating: 0, count: indices.count)
		out.withUnsafeMutableBufferPointer { o in
			palette.withUnsafeBufferPointer { pal in
				for i in 0..<indices.count {
					let idx = Int(indices[i])
					guard idx != 0 else { continue }
					let a = alpha.map { UInt32($0[i]) } ?? 255
					o[i] = a << 24 | (pal[idx] & 0xFFFFFF)
				}
			}
		}
		argb = out
	}
}

/// A decoded sprite group (archive 8): usually one frame, sometimes a strip
/// (fonts have 256 frames, one per cp1252 code).
public struct SpriteSheet {
	public let width: Int
	public let height: Int
	public let frames: [SpriteFrame]

	public init(_ data: [UInt8]) throws {
		var p = Packet(data)
		guard data.count >= 2 else { throw PacketUnderflow(offset: 0, wanted: 2, size: data.count) }
		p.offset = data.count - 2
		let count = try p.g2()
		p.offset = data.count - count * 8 - 7
		width = try p.g2()
		height = try p.g2()
		let paletteSize = try p.g1() + 1
		var xs = [Int](), ys = [Int](), ws = [Int](), hs = [Int]()
		for _ in 0..<count { xs.append(try p.g2()) }
		for _ in 0..<count { ys.append(try p.g2()) }
		for _ in 0..<count { ws.append(try p.g2()) }
		for _ in 0..<count { hs.append(try p.g2()) }
		p.offset = data.count + 3 - count * 8 - paletteSize * 3 - 7
		var palette = [UInt32](repeating: 0, count: paletteSize)
		for i in 1..<max(paletteSize, 1) {
			let c = UInt32(try p.g3())
			palette[i] = c == 0 ? 1 : c
		}
		p.offset = 0
		var frames: [SpriteFrame] = []
		for f in 0..<count {
			let w = ws[f], h = hs[f], n = w * h
			var px = [UInt8](repeating: 0, count: n)
			var alpha: [UInt8]?
			let flags = try p.g1()
			if flags & 1 == 0 {
				// Row-major.
				for i in 0..<n { px[i] = UInt8(try p.g1()) }
				if flags & 2 != 0 {
					var a = [UInt8](repeating: 0, count: n)
					for i in 0..<n { a[i] = UInt8(try p.g1()) }
					alpha = a
				}
			} else {
				// Column-major.
				for x in 0..<w { for y in 0..<h { px[x + y * w] = UInt8(try p.g1()) } }
				if flags & 2 != 0 {
					var a = [UInt8](repeating: 0, count: n)
					for x in 0..<w { for y in 0..<h { a[x + y * w] = UInt8(try p.g1()) } }
					alpha = a
				}
			}
			// rt4 only treats the frame as alpha-blended if some value is not 0xFF.
			if let a = alpha, !a.contains(where: { $0 != 255 }) { alpha = nil }
			frames.append(SpriteFrame(width: width, height: height, xOffset: xs[f], yOffset: ys[f],
				innerWidth: w, innerHeight: h, indices: px, alpha: alpha, palette: palette))
		}
		self.frames = frames
	}
}
