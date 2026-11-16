import Foundation

/// rt4 `TextureOpCombine` (type 7): blend modes over two children.
final class OpCombine: TextureOp {
	var function = 6
	init() { super.init(inputs: 2, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { function = try p.g1() } else if op == 1 { monochrome = try p.g1() == 1 }
	}
	/// Combine one sample pair; `a` is child 0, `b` is child 1. Returns nil for unknown functions (output stays 0).
	private func blend(_ a: Int, _ b: Int) -> Int {
		switch function {
		case 1: return b + a
		case 2: return a - b
		case 3: return (b * a) >> 12
		case 4: return b == 0 ? 4096 : (a << 12) / b
		case 5: return 4096 - (((4096 - a) * (4096 - b)) >> 12)
		case 6: return b >= 2048 ? 4096 - (((4096 - a) * (4096 - b)) >> 11) : (b * a) >> 11
		case 7: return a == 4096 ? 4096 : (b << 12) / (4096 - a)
		case 8: return a == 0 ? 0 : 4096 - ((4096 - b) << 12) / a
		case 9: return a < b ? a : b
		case 10: return a > b ? a : b
		case 11: return b < a ? a - b : b - a
		case 12: return b + a - ((a * b) >> 11)
		default: return 0
		}
	}
	override func computeMono(_ y: Int) -> [Int] {
		let a = childMono(0, y), b = childMono(1, y)
		return (0..<ctx.width).map { blend(a[$0], b[$0]) }
	}
	override func computeColor(_ y: Int) -> [[Int]] {
		let a = childColor(y, 0), b = childColor(y, 1)
		return (0..<3).map { c in (0..<ctx.width).map { blend(a[c][$0], b[c][$0]) } }
	}
}

/// rt4 `TextureOpCurve` (type 8): remap values through a spline.
final class OpCurve: TextureOp {
	var mode = 0
	private var markers: [[Int]]?
	private var before: [Int] = [0, 0], after: [Int] = [0, 0]
	private var table = [Int](repeating: 0, count: 257)
	init() { super.init(inputs: 1, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		guard op == 0 else { return }
		mode = try p.g1()
		let n = try p.g1()
		markers = try (0..<n).map { _ in [try p.g2(), try p.g2()] }
	}
	private func marker(_ i: Int) -> [Int] {
		guard let m = markers else { return [0, 0] }
		if i >= 0 { return i >= m.count ? after : m[i] }
		return before
	}
	private func clamp16(_ v: Int) -> Int { v <= -32768 ? -32767 : (v >= 32768 ? 32767 : v) }
	override func postDecode() throws {
		if markers == nil { markers = [[0, 0], [4096, 4096]] }
		guard let m = markers, m.count >= 2 else { throw TextureError("Curve operation requires at least two markers") }
		if mode == 2 {
			let m0 = m[0], m1 = m[1], n2 = m[m.count - 2], n1 = m[m.count - 1]
			before = [m0[0] + m0[0] - m1[0], -m1[1] + m0[1] + m0[1]]
			after = [n2[0] + n2[0] - n1[0], -n1[1] - -n2[1] + n2[1]]
		}
		for i in 0..<257 {
			let x = i << 4
			var j = 1
			while m.count - 1 > j && m[j][0] <= x { j += 1 }
			let hi = m[j], lo = m[j - 1]
			let span = hi[0] - lo[0]
			var v: Int
			if mode == 2 {
				let pm = marker(j - 2)[1]
				let c = hi[1], b = lo[1]
				let slope = c - pm
				let nx = marker(j + 1)[1]
				let t = jdiv((x - lo[0]) << 12, span)
				let k = nx + b - c - pm
				let t2 = (t * t) >> 12
				let l = pm - b - k
				let p1 = (slope * t) >> 12
				let p2 = (t2 * l) >> 12
				let p3 = (t2 * ((t * k) >> 12)) >> 12
				v = b + p2 + p3 + p1
			} else if mode == 1 {
				let t = jdiv((x - lo[0]) << 12, span)
				let w = (4096 - TextureOp.cosine[(t >> 5) & 0xFF]) >> 1
				let iw = 4096 - w
				v = (w * hi[1] + lo[1] * iw) >> 12
			} else {
				let t = jdiv((x - lo[0]) << 12, span)
				let it = 4096 - t
				v = (hi[1] * t + it * lo[1]) >> 12
			}
			table[i] = clamp16(v)
		}
	}
	override func computeMono(_ y: Int) -> [Int] {
		childMono(0, y).map { table[min(max($0 >> 4, 0), 256)] }
	}
}

/// rt4 `TextureOpColorGradient` (type 10): map a mono child through a colour ramp.
final class OpColorGradient: TextureOp {
	private var samples: [[Int]]?
	private var colors = [Int](repeating: 0, count: 257)
	init() { super.init(inputs: 1, monochrome: false) }
	private func setPreset(_ n: Int) throws {
		if n == 0 { return }
		guard let t = GradientPresets.table[n] else { throw TextureError("Invalid gradient preset") }
		samples = t
	}
	override func decode(_ op: Int, _ p: inout Packet) throws {
		guard op == 0 else { return }
		let preset = try p.g1()
		if preset != 0 { try setPreset(preset); return }
		let n = try p.g1()
		samples = try (0..<n).map { _ in
			let pos = try p.g2()
			return [pos, try p.g1() << 4, try p.g1() << 4, try p.g1() << 4]
		}
	}
	override func postDecode() throws {
		if samples == nil { try setPreset(1) }
		guard let s = samples, !s.isEmpty else { return }
		func c8(_ v: Int) -> Int { let a = v >> 4; return a < 0 ? 0 : (a > 255 ? 255 : a) }
		for i in 0..<257 {
			let x = i << 4
			var k = 0
			while k < s.count && x >= s[k][0] { k += 1 }
			var a: Int, b: Int, c: Int
			if k < s.count {
				let cur = s[k]
				if k > 0 {
					let prev = s[k - 1]
					let t = jdiv((x - prev[0]) << 12, cur[0] - prev[0])
					let it = 4096 - t
					c = (prev[3] * it + cur[3] * t) >> 12
					a = (it * prev[1] + t * cur[1]) >> 12
					b = (it * prev[2] + t * cur[2]) >> 12
				} else { a = cur[1]; c = cur[3]; b = cur[2] }
			} else {
				let last = s[s.count - 1]
				c = last[3]; b = last[2]; a = last[1]
			}
			colors[i] = c8(c) | (c8(b) << 8) | (c8(a) << 16)
		}
	}
	override func computeColor(_ y: Int) -> [[Int]] {
		var out = zeros3()
		let m = childMono(0, y)
		for x in 0..<ctx.width {
			let c = colors[min(max(m[x] >> 4, 0), 256)]
			out[0][x] = (c >> 12) & 0xFF0
			out[1][x] = (c >> 4) & 0xFF0
			out[2][x] = (c & 0xFF) << 4
		}
		return out
	}
}

/// rt4 `TextureOpSprite` (type 39) and `TextureOpTiledSprite` (type 18): sample an archive-8 sprite.
class OpSprite: TextureOp {
	var spriteRef = -1
	var sprite: TextureStore.SpritePixels?
	init() { super.init(inputs: 0, monochrome: false) }
	override var spriteId: Int { spriteRef }
	override func decode(_ op: Int, _ p: inout Packet) throws { if op == 0 { spriteRef = try p.g2() } }
	override func resetState() { sprite = nil }
	final func load() -> TextureStore.SpritePixels? {
		if let s = sprite { return s }
		guard spriteRef >= 0 else { return nil }
		sprite = ctx.store.spritePixels(spriteRef)
		return sprite
	}
	final func unpack(_ px: Int, _ out: inout [[Int]], _ x: Int) {
		out[2][x] = (px & 0xFF) << 4
		out[1][x] = (px >> 4) & 0xFF0
		out[0][x] = (px >> 12) & 0xFF0
	}
	override func computeColor(_ y: Int) -> [[Int]] {
		var out = zeros3()
		guard let s = load() else { return out }
		var idx = (s.height == ctx.height ? y : (s.height * y) / ctx.height) * s.width
		if ctx.width == s.width {
			for x in 0..<ctx.width { unpack(s.pixels[idx], &out, x); idx += 1 }
		} else {
			for x in 0..<ctx.width { unpack(s.pixels[idx + (s.width * x) / ctx.width], &out, x) }
		}
		return out
	}
}

final class OpTiledSprite: OpSprite {
	override func computeColor(_ y: Int) -> [[Int]] {
		var out = zeros3()
		guard let s = load() else { return out }
		let row = (y % s.height) * s.height
		for x in 0..<ctx.width { unpack(s.pixels[row + x % s.width], &out, x) }
		return out
	}
}

/// rt4 `TextureOpTexture` (type 36): another procedural texture used as an input.
final class OpTextureRef: TextureOp {
	var texId = -1
	var pixels: [Int]?
	var size = 0
	init() { super.init(inputs: 0, monochrome: false) }
	override var textureRef: Int { texId }
	override func decode(_ op: Int, _ p: inout Packet) throws { if op == 0 { texId = try p.g2() } }
	override func resetState() { pixels = nil }
	override func computeColor(_ y: Int) -> [[Int]] {
		var out = zeros3()
		if pixels == nil {
			guard texId >= 0 else { return out }
			let st = ctx.store
			size = st.isLowDetail(texId) ? 64 : 128
			pixels = st.nestedPixels(texId)
		}
		guard let px = pixels, px.count >= size * size else { return out }
		var idx = (size == ctx.height ? y : (size * y) / ctx.height) * size
		for x in 0..<ctx.width {
			let v = ctx.width == size ? px[idx] : px[idx + (size * x) / ctx.width]
			if ctx.width == size { idx += 1 }
			out[2][x] = (v & 0xFF) << 4
			out[1][x] = (v >> 4) & 0xFF0
			out[0][x] = (v >> 12) & 0xFF0
		}
		return out
	}
}

/// rt4 `TextureOp28` (type 28): random rounded blocks (cobble/shingle pattern). Draws the whole image on first use.
final class OpBlocks: TextureOp {
	var seed = 0, minW = 1024, maxW = 2048, minH = 409, maxH = 819
	var rounding = 1024, shape = 0, cornerVar = 1024, brightVar = 1024
	private var radius = 0
	private var image: [[Int]]?
	init() { super.init(inputs: 0, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		switch op {
		case 0: seed = try p.g1()
		case 1: minW = try p.g2()
		case 2: maxW = try p.g2()
		case 3: minH = try p.g2()
		case 4: maxH = try p.g2()
		case 5: rounding = try p.g2()
		case 6: shape = try p.g1()
		case 7: cornerVar = try p.g2()
		case 8: brightVar = try p.g2()
		default: break
		}
	}
	override func resetState() { image = nil }
	override func computeMono(_ y: Int) -> [Int] {
		if image == nil { image = build() }
		return image![y]
	}
	private func build() -> [[Int]] {
		let w = ctx.width, h = ctx.height
		var img = [[Int]](repeating: [Int](repeating: 0, count: w), count: h)
		var l31 = 0, l33 = 0, l35 = 0, l37 = 0, l39 = 0
		var l41 = true, l43 = true
		var l45 = 0, l47 = 0
		let l54 = (w * minW) >> 12
		let l61 = (w * maxW) >> 12
		let l68 = (maxH * h) >> 12
		let l75 = (h * minH) >> 12
		if l68 <= 1 || l54 <= 0 || l61 - l54 <= 0 || l68 - l75 <= 0 { return img }
		let l88 = w / l54 + 1
		radius = ((w / 8) * rounding) >> 12
		var l102 = [[Int]](repeating: [0, 0, 0], count: l88)
		var l106 = l102
		var rnd = JavaRandom(seed: seed)
		var guardCount = 0
		while true {
			guardCount += 1
			if guardCount > 100_000 { return img }
			var l123 = l54 + rnd.nextInt(l61 - l54)
			var l133 = rnd.nextInt(l68 - l75) + l75
			var l137 = l31 + l123
			if w < l137 { l137 = w; l123 = w - l31 }
			var l158 = 0
			if !l43 {
				var l150 = l39
				l158 = l102[l39][2]
				var l160 = 0
				var l164 = l35 + l137
				if l164 < 0 { l164 += w }
				if w < l164 { l164 -= w }
				var spins = 0
				while true {
					let l186 = l102[l150]
					if l164 >= l186[0] && l186[1] >= l164 {
						if l39 != l150 {
							var l224 = l35 + l31
							if l224 < 0 { l224 += w }
							if l224 > w { l224 -= w }
							if l160 >= 1 {
								for k in 1...l160 { l158 = max(l158, l102[(l39 + k) % max(l45, 1)][2]) }
							}
							for k in 0...l160 {
								let seg = l102[(l39 + k) % max(l45, 1)]
								let l285 = seg[2]
								if l285 != l158 {
									let l297 = seg[0], l301 = seg[1]
									let l312: Int, l316: Int
									if l164 > l224 {
										l312 = max(l224, l297); l316 = min(l164, l301)
									} else if l297 == 0 {
										l316 = min(l164, l301); l312 = 0
									} else {
										l312 = max(l224, l297); l316 = w
									}
									drawBlock(l285, &rnd, l33 + l312, -l312 + l316, l158 - l285, &img)
								}
							}
						}
						l39 = l150
						break
					}
					l160 += 1
					l150 += 1
					if l150 >= l45 { l150 = 0 }
					spins += 1
					if spins > 10_000 || l150 >= l102.count { return img }
				}
			}
			if h >= l158 + l133 { l41 = false } else { l133 = h - l158 }
			if l137 == w {
				drawBlock(l158, &rnd, l37 + l31, l123, l133, &img)
				if l41 { return img }
				l41 = true
				l33 = l37
				l43 = false
				if l47 >= l106.count { l106.append([0, 0, 0]) }
				l106[l47][0] = l31
				l47 += 1
				l39 = 0
				l45 = l47
				l47 = 0
				l106[l45 - 1][2] = l133 + l158
				l106[l45 - 1][1] = l137
				l37 = rnd.nextInt(w)
				l35 = l37 - l33
				l31 = 0
				swap(&l102, &l106)
				var l160 = l35
				if l35 < 0 { l160 = l35 + w }
				if w < l160 { l160 -= w }
				var spins = 0
				while true {
					let seg = l102[l39]
					if seg[0] <= l160 && seg[1] >= l160 { break }
					l39 += 1
					if l45 <= l39 { l39 = 0 }
					spins += 1
					if spins > 10_000 { return img }
				}
			} else {
				if l47 >= l106.count { l106.append([0, 0, 0]) }
				l106[l47][1] = l137
				l106[l47][2] = l133 + l158
				l106[l47][0] = l31
				l47 += 1
				drawBlock(l158, &rnd, l31 + l37, l123, l133, &img)
				l31 = l137
			}
		}
	}
	/// rt4 `method3386`: paint one block (with optional rounded edge falloff).
	private func drawBlock(_ row0: Int, _ rnd: inout JavaRandom, _ x0: Int, _ bw: Int, _ bh: Int, _ img: inout [[Int]]) {
		let w = ctx.width, h = ctx.height, wm = ctx.widthMask
		let l26 = cornerVar > 0 ? 4096 - rnd.nextInt(cornerVar) : 4096
		let l34 = (brightVar * radius) >> 12
		let l47 = radius - (l34 > 0 ? rnd.nextInt(l34) : 0)
		var x0 = x0
		if w <= x0 { x0 -= w }
		func rowIdx(_ r: Int) -> Int? { let i = row0 + r; return i >= 0 && i < h ? i : nil }
		if l47 > 0 {
			if bh <= 0 || bw <= 0 { return }
			let half = bw / 2, halfH = bh / 2
			let l79 = min(half, l47)
			let l90 = min(halfH, l47)
			let l97 = bw - l79 * 2
			let l101 = l79 + x0
			for r in 0..<bh {
				guard let ri = rowIdx(r) else { continue }
				var row = img[ri]
				if r < l90 {
					let l125 = (r * l26) / l90
					for c in 0..<l79 {
						let l142 = (c * l26) / l79
						let v = shape == 0 ? (l142 * l125) >> 12 : (l125 <= l142 ? l125 : l142)
						row[wm & (c + x0)] = v
						row[(bw + x0 - c - 1) & wm] = v
					}
					if w >= l97 + l101 { texFill(&row, l101, l97, l125) }
					else {
						let l133 = w - l101
						texFill(&row, l101, l133, l125)
						texFill(&row, 0, l97 - l133, l125)
					}
				} else {
					let l125 = bh - r - 1
					if l125 >= l90 {
						for c in 0..<l79 {
							let v = (l26 * c) / l79
							row[wm & (x0 + c)] = v
							row[(x0 + bw - c - 1) & wm] = v
						}
						if l101 + l97 > w {
							let l133 = w - l101
							texFill(&row, l101, l133, l26)
							texFill(&row, 0, l97 - l133, l26)
						} else { texFill(&row, l101, l97, l26) }
					} else {
						let l133 = (l125 * l26) / l90
						for c in 0..<l79 {
							let l288 = (l26 * c) / l79
							let v = shape == 0 ? (l288 * l133) >> 12 : (l133 <= l288 ? l133 : l288)
							row[wm & (x0 + c)] = v
							row[wm & (x0 + bw - c - 1)] = v
						}
						if l97 + l101 > w {
							let l142 = w - l101
							texFill(&row, l101, l142, l133)
							texFill(&row, 0, l97 - l142, l133)
						} else { texFill(&row, l101, l97, l133) }
					}
				}
				img[ri] = row
			}
		} else if w >= x0 + bw {
			for r in 0..<max(bh, 0) { if let ri = rowIdx(r) { texFill(&img[ri], x0, bw, l26) } }
		} else {
			let l68 = w - x0
			for r in 0..<max(bh, 0) {
				if let ri = rowIdx(r) {
					texFill(&img[ri], x0, l68, l26)
					texFill(&img[ri], 0, bw - l68, l26)
				}
			}
		}
	}
}

/// rt4 `TextureOp38` (type 38): random scratches/streaks. Draws the whole image on first use.
final class OpStreaks: TextureOp {
	var angle = 0, count = 2000, length = 16, angleVar = 4096, seed = 0
	private var image: [[Int]]?
	init() { super.init(inputs: 0, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		switch op {
		case 0: seed = try p.g1()
		case 1: count = try p.g2()
		case 2: length = try p.g1()
		case 3: angle = try p.g2()
		case 4: angleVar = try p.g2()
		default: break
		}
	}
	override func resetState() { image = nil }
	override func computeMono(_ y: Int) -> [Int] {
		if image == nil { image = build() }
		return image![y]
	}
	private func build() -> [[Int]] {
		let w = ctx.width, h = ctx.height
		var img = [[Int]](repeating: [Int](repeating: 0, count: w), count: h)
		let half = angleVar >> 1
		var rnd = JavaRandom(seed: seed)
		for _ in 0..<count {
			let a = angleVar > 0 ? angle + rnd.nextInt(angleVar) - half : angle
			var x0 = rnd.nextInt(w)
			let idx = (a >> 4) & 0xFF
			var y0 = rnd.nextInt(h)
			var x1 = x0 + ((length * TextureOp.cosine[idx]) >> 12)
			var y1 = y0 + ((TextureOp.sine[idx] * length) >> 12)
			var dx = x1 - x0
			var dy = y1 - y0
			if dx == 0 && dy == 0 { continue }
			if dx < 0 { dx = -dx }
			if dy < 0 { dy = -dy }
			let steep = dy > dx
			if steep {
				swap(&x0, &y0)
				swap(&x1, &y1)
			}
			if x0 > x1 {
				swap(&x0, &x1)
				swap(&y0, &y1)
			}
			let span = x1 - x0
			var ady = y1 - y0
			var cy = y0
			if ady < 0 { ady = -ady }
			var err = -span / 2
			let shade = 1024 - (rnd.nextInt(4096) >> 2)
			let step = y1 <= y0 ? -1 : 1
			let slope = 2048 / span
			var x = x0
			while x < x1 {
				err += ady
				let v = slope * (x - x0) + shade + 1024
				let ry = cy & ctx.heightMask
				if err > 0 { err += -span; cy += step }
				let rx = ctx.widthMask & x
				if steep {
					if ry < h && rx < w { img[ry][rx] = v }
				} else {
					if rx < h && ry < w { img[rx][ry] = v }
				}
				x += 1
			}
		}
		return img
	}
}
