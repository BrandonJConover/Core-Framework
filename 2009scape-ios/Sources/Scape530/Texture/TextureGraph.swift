import Foundation

/// A decoded texture definition: the op graph plus the render flags that
/// follow it. Port of rt4 `Texture` (graph and `method2725`) and the
/// header fields read by `GlTexture`'s constructor.
final class TextureGraph {
	let ops: [TextureOp]
	let main: TextureOp
	let alpha: TextureOp
	/// rt4 `aBoolean286`: apply the wrap-around 3x3 box blur after rendering.
	let blur: Bool
	/// rt4 `aBoolean288`: write the output transposed (column-major).
	let transposed: Bool
	let wrapU: Bool
	let wrapV: Bool
	let speedU: Int
	let speedV: Int
	/// Sprite groups (archive 8) and other textures this graph reads.
	let spriteIds: [Int]
	let textureIds: [Int]
	/// Op type numbers used, for diagnostics.
	let opTypes: [Int]

	/// rt4 `Texture.create(type)`.
	static func makeOp(_ type: Int) -> TextureOp? {
		switch type {
		case 0: return OpMonochromeFill()
		case 1: return OpColorFill()
		case 2: return OpHorizontalGradient()
		case 3: return OpVerticalGradient()
		case 4: return OpBricks()
		case 5: return OpBlur()
		case 6: return OpClamp()
		case 7: return OpCombine()
		case 8: return OpCurve()
		case 9: return OpFlip()
		case 10: return OpColorGradient()
		case 11: return OpTint()
		case 12: return OpWave()
		case 13: return OpNoise()
		case 14: return OpRoundRect()
		case 15: return OpCellular()
		case 16: return OpWeave()
		case 17: return OpHslShift()
		case 18: return OpTiledSprite()
		case 19: return OpDisplace()
		case 20: return OpTile()
		case 21: return OpInterpolate()
		case 22: return OpInvert()
		case 23: return OpMirror()
		case 24: return OpMonochrome()
		case 25: return OpColorKey()
		case 26: return OpBinary()
		case 27: return OpStripes()
		case 28: return OpBlocks()
		case 29: return OpVector()
		case 30: return OpRange()
		case 31: return OpMandelbrot()
		case 32: return OpLighting()
		case 33: return OpNormalMap()
		case 34: return OpFractal()
		case 35: return OpShade()
		case 36: return OpTextureRef()
		case 37: return OpOrnament()
		case 38: return OpStreaks()
		case 39: return OpSprite()
		default: return nil
		}
	}

	init(_ data: [UInt8]) throws {
		var p = Packet(data)
		let n = try p.g1()
		var ops: [TextureOp] = []
		var wiring: [[Int]] = []
		var types: [Int] = []
		for _ in 0..<n {
			// rt4 Texture.method3680
			_ = try p.g1()
			let type = try p.g1()
			guard let op = TextureGraph.makeOp(type) else { throw TextureError("unknown texture op type \(type)") }
			types.append(type)
			op.cacheRows = try p.g1()
			let fields = try p.g1()
			for _ in 0..<fields {
				let opcode = try p.g1()
				try op.decode(opcode, &p)
			}
			try op.postDecode()
			wiring.append(try (0..<op.children.count).map { _ in try p.g1() })
			ops.append(op)
		}
		var sprites: [Int] = [], textures: [Int] = []
		for (i, op) in ops.enumerated() {
			for (slot, target) in wiring[i].enumerated() {
				guard target < ops.count else { throw TextureError("op input out of range") }
				op.children[slot] = ops[target]
			}
			if op.spriteId > 0 { sprites.append(op.spriteId) }
			if op.textureRef > 0 { textures.append(op.textureRef) }
		}
		let mainIndex = try p.g1()
		guard mainIndex < ops.count else { throw TextureError("main op out of range") }
		main = ops[mainIndex]
		let alphaIndex = try p.g1()
		guard alphaIndex < ops.count else { throw TextureError("alpha op out of range") }
		alpha = ops[alphaIndex]
		self.ops = ops
		blur = try p.g1() == 1
		transposed = try p.g1() == 1
		wrapU = try p.g1() == 1
		wrapV = try p.g1() == 1
		_ = try p.g1() // material brightness (GL only)
		speedU = try p.g1b()
		speedV = try p.g1b()
		_ = try p.g1() // mipmap mode (GL only)
		_ = try p.g1()
		spriteIds = sprites
		textureIds = textures
		opTypes = types
	}

	/// rt4 `Texture.method2725`: render `size`x`size` texels (0xRRGGBB).
	/// `flip` mirrors columns (the software path uses `true`, nested texture reads `false`).
	func render(store: TextureStore, size: Int, brightness: Double, flip: Bool) -> [Int32] {
		store.setBrightness(brightness)
		let ctx = TextureContext(store: store)
		ctx.setSize(height: size, width: size)
		for op in ops { op.prepare(ctx) }
		var out = [Int32](repeating: 0, count: size * size)
		var idx = 0
		for row in 0..<size {
			if transposed { idx = row }
			let r: [Int], g: [Int], b: [Int]
			if main.monochrome {
				let m = main.mono(row)
				r = m; g = m; b = m
			} else {
				let c = main.color(row)
				r = c[0]; g = c[1]; b = c[2]
			}
			var col = flip ? size - 1 : 0
			let step = flip ? -1 : 1
			let end = flip ? -1 : size
			while col != end {
				let map = store.brightnessMap
				var rv = r[col] >> 4
				if rv > 255 { rv = 255 }
				if rv < 0 { rv = 0 }
				rv = map[rv]
				var bv = b[col] >> 4
				var gv = g[col] >> 4
				if gv > 255 { gv = 255 }
				if gv < 0 { gv = 0 }
				if bv > 255 { bv = 255 }
				gv = map[gv]
				if bv < 0 { bv = 0 }
				bv = map[bv]
				out[idx] = Int32(truncatingIfNeeded: (rv << 16) + (gv << 8) + bv)
				idx += 1
				if transposed { idx += size - 1 }
				col += step
			}
		}
		for op in ops { op.clear() }
		return out
	}

	/// The wrap-around 3x3 box blur from rt4 `GlTexture.method4295`.
	static func blur3x3(_ src: [Int32], size: Int) -> [Int32] {
		var colR = [Int](repeating: 0, count: size)
		var colG = colR, colB = colR
		var out = [Int32](repeating: 0, count: size * size)
		var a = size, b = size
		let total = size * size
		var outIdx = total
		for _ in 0..<3 {
			var c = size - 1
			while c >= 0 {
				a -= 1
				let px = Int(src[a])
				colR[c] += (px >> 16) & 0xFF
				colG[c] += (px >> 8) & 0xFF
				colB[c] += px & 0xFF
				c -= 1
			}
			if a == 0 { a = total }
		}
		for _ in 0..<size {
			var sumG = 0, sumB = 0, sumR = 0
			var lead = 1, trail = 1
			for _ in 0..<3 {
				lead -= 1
				sumG += colG[lead]
				sumB += colB[lead]
				sumR += colR[lead]
				if lead == 0 { lead = size }
			}
			var c = size - 1
			while c >= 0 {
				trail -= 1
				let g = sumG / 9, bl = sumB / 9
				lead -= 1
				let r = sumR / 9
				outIdx -= 1
				out[outIdx] = Int32(truncatingIfNeeded: bl | (r << 16) | (g << 8))
				sumR += colR[lead] - colR[trail]
				sumB += colB[lead] - colB[trail]
				sumG += colG[lead] - colG[trail]
				if trail == 0 { trail = size }
				if lead == 0 { lead = size }
				c -= 1
			}
			c = size - 1
			while c >= 0 {
				b -= 1
				let old = Int(src[b])
				a -= 1
				let new = Int(src[a])
				colR[c] += ((new >> 16) & 0xFF) - ((old >> 16) & 0xFF)
				colG[c] += ((new >> 8) & 0xFF) - ((old >> 8) & 0xFF)
				colB[c] += (new & 0xFF) - (old & 0xFF)
				c -= 1
			}
			if b == 0 { b = total }
			if a == 0 { a = total }
		}
		return out
	}
}
