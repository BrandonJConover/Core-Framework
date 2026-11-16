import Foundation

@inline(__always) func jdiv(_ a: Int, _ b: Int) -> Int { b == 0 ? 0 : a / b }
/// Java `Math.sqrt((float) v / d)`: float division, then a double square root.
@inline(__always) func fsqrt(_ v: Int, _ d: Float) -> Double { Double(Float(v) / d).squareRoot() }
/// Java `(int) d` semantics: NaN is 0, out-of-range saturates.
@inline(__always) func jint(_ d: Double) -> Int {
	if d.isNaN { return 0 }
	if d >= 2147483647.0 { return Int(Int32.max) }
	if d <= -2147483648.0 { return Int(Int32.min) }
	return Int(d)
}

/// rt4 `TextureOp4` (type 4): brick pattern.
final class OpBricks: TextureOp {
	var cols = 4, rows = 8
	var colJitter = 409, rowJitter = 204, offset = 1024, yOffset = 0, gap = 81, brightVar = 1024
	private var rowH = 0, halfGap = 0, colW = 0
	private var colEdges: [[Int]] = [], rowEdges: [Int] = [], bright: [[Int]] = []
	init() { super.init(inputs: 0, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		switch op {
		case 0: cols = try p.g1()
		case 1: rows = try p.g1()
		case 2: colJitter = try p.g2()
		case 3: rowJitter = try p.g2()
		case 4: offset = try p.g2()
		case 5: yOffset = try p.g2()
		case 6: gap = try p.g2()
		case 7: brightVar = try p.g2()
		default: break
		}
	}
	override func postDecode() throws {
		guard rows > 0, cols > 0 else { throw TextureError("brick op with zero rows/cols") }
		var rnd = JavaRandom(seed: rows)
		rowH = 4096 / rows
		halfGap = gap / 2
		colEdges = [[Int]](repeating: [Int](repeating: 0, count: cols + 1), count: rows)
		let halfRow = rowH / 2
		rowEdges = [Int](repeating: 0, count: rows + 1)
		bright = [[Int]](repeating: [Int](repeating: 0, count: cols), count: rows)
		colW = 4096 / cols
		let halfCol = colW / 2
		for r in 0..<rows {
			if r > 0 {
				let j = ((rnd.nextInt(4096) - 2048) * rowJitter) >> 12
				rowEdges[r] = rowEdges[r - 1] + rowH + ((j * halfRow) >> 12)
			}
			colEdges[r][0] = 0
			for c in 0..<cols {
				if c > 0 {
					let j = ((rnd.nextInt(4096) - 2048) * colJitter) >> 12
					colEdges[r][c] = colEdges[r][c - 1] + colW + ((halfCol * j) >> 12)
				}
				bright[r][c] = brightVar <= 0 ? 4096 : 4096 - rnd.nextInt(brightVar)
			}
			colEdges[r][cols] = 4096
		}
		rowEdges[rows] = 4096
	}
	override func computeMono(_ y: Int) -> [Int] {
		var out = zeros()
		var v = ctx.heightFractions[y] + yOffset
		while v < 0 { v += 4096 }
		while v > 4096 { v -= 4096 }
		var r = 0
		while rows > r && v >= rowEdges[r] { r += 1 }
		let row = r - 1
		let hi = rowEdges[r]
		let odd = (r & 1) == 0
		let lo = rowEdges[r - 1]
		guard lo + halfGap < v && hi - halfGap > v else { return out }
		for x in 0..<ctx.width {
			var c = 0
			let shift = odd ? offset : -offset
			var u = ctx.widthFractions[x] + ((colW * shift) >> 12)
			while u < 0 { u += 4096 }
			while u > 4096 { u -= 4096 }
			while cols > c && u >= colEdges[row][c] { c += 1 }
			let cHi = colEdges[row][c]
			let cLo = colEdges[row][c - 1]
			out[x] = (cLo + halfGap < u && cHi - halfGap > u) ? bright[row][c - 1] : 0
		}
		return out
	}
}

struct TextureError: Error, CustomStringConvertible {
	let description: String
	init(_ d: String) { description = d }
}

/// rt4 `TextureOp5` (type 5): box blur.
final class OpBlur: TextureOp {
	var rx = 1, ry = 1
	init() { super.init(inputs: 1, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { rx = try p.g1() } else if op == 1 { ry = try p.g1() } else if op == 2 { monochrome = try p.g1() == 1 }
	}
	private func hblur(_ row: [Int]) -> [Int] {
		let w = ctx.width, m = ctx.widthMask
		let k = 65536 / (rx + rx + 1)
		var sum = 0
		for i in -rx...rx { sum += row[i & m] }
		var out = [Int](repeating: 0, count: w)
		var x = 0
		while w > x {
			out[x] = (k * sum) >> 16
			sum -= row[m & (x - rx)]
			x += 1
			sum += row[m & (rx + x)]
		}
		return out
	}
	override func computeMono(_ y: Int) -> [Int] {
		let n = ry + ry + 1
		let k = 65536 / n
		var rowsOut: [[Int]] = []
		for r in (y - ry)...(y + ry) { rowsOut.append(hblur(childMono(0, r & ctx.heightMask))) }
		return (0..<ctx.width).map { x in
			var s = 0
			for i in 0..<n { s += rowsOut[i][x] }
			return (k * s) >> 16
		}
	}
	override func computeColor(_ y: Int) -> [[Int]] {
		let n = ry + ry + 1
		let k = 65536 / n
		var rowsOut: [[[Int]]] = []
		for r in (y - ry)...(y + ry) { rowsOut.append(childColor(r & ctx.heightMask, 0).map(hblur)) }
		var out = zeros3()
		for x in 0..<ctx.width {
			for c in 0..<3 {
				var s = 0
				for i in 0..<n { s += rowsOut[i][c][x] }
				out[c][x] = (k * s) >> 16
			}
		}
		return out
	}
}

/// rt4 `TextureOp12` (type 12): sine/triangle wave pattern.
final class OpWave: TextureOp {
	var wave = 0, radial = 0, freq = 1
	init() { super.init(inputs: 0, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { radial = try p.g1() } else if op == 1 { wave = try p.g1() } else if op == 3 { freq = try p.g1() }
	}
	override func computeMono(_ y: Int) -> [Int] {
		var out = zeros()
		let hy = ctx.heightFractions[y]
		let dy = (hy - 2048) >> 1
		for x in 0..<ctx.width {
			let wx = ctx.widthFractions[x]
			let dx = (wx - 2048) >> 1
			var v: Int
			if radial == 0 {
				v = (wx - hy) * freq
			} else {
				let d = ((dx * dx) + (dy * dy)) >> 12
				v = jint(fsqrt(d, 4096.0) * 4096.0)
				v = Int(Double(v * freq) * 3.141592653589793)
			}
			v -= v & ~0xFFF
			if wave == 0 {
				v = (TextureOp.sine[(v >> 4) & 0xFF] + 4096) >> 1
			} else if wave == 2 {
				v -= 2048
				if v < 0 { v = -v }
				v = (2048 - v) << 1
			}
			out[x] = v
		}
		return out
	}
}

/// rt4 `TextureOp14` (type 14): rounded-rectangle gradient.
final class OpRoundRect: TextureOp {
	var m = 585
	init() { super.init(inputs: 0, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws { if op == 0 { m = try p.g2() } }
	override func computeMono(_ y: Int) -> [Int] {
		var out = zeros()
		let hy = ctx.heightFractions[y]
		let span = 2048 - m
		for x in 0..<ctx.width {
			let wx = ctx.widthFractions[x]
			if wx > m && 4096 - m > wx && 2048 - m < hy && hy < m + 2048 {
				var v = 2048 - wx
				v = v < 0 ? -v : v
				v <<= 12
				v = jdiv(v, span)
				out[x] = 4096 - v
			} else if wx > 2048 - m && wx < m + 2048 {
				var v = hy - 2048
				v = v >= 0 ? v : -v
				v -= m
				v <<= 12
				out[x] = jdiv(v, span)
			} else if hy < m || 4096 - m < hy {
				let v = wx - 2048
				let a = v < 0 ? -v : v
				out[x] = jdiv((a - m) << 12, span)
			} else if m <= wx && wx <= 4096 - m {
				out[x] = 0
			} else {
				var v = 2048 - hy
				v = v < 0 ? -v : v
				v <<= 12
				v = jdiv(v, span)
				out[x] = 4096 - v
			}
		}
		return out
	}
}

/// rt4 `TextureOp15` (type 15): cellular (Worley) noise.
final class OpCellular: TextureOp {
	var output = 2, jitter = 2048, seed = 0, metric = 1, vCells = 5, hCells = 5
	private var perm = [UInt8](repeating: 0, count: 512)
	private var jit = [Int](repeating: 0, count: 512)
	init() { super.init(inputs: 0, monochrome: true) }

	/// rt4 `TextureOp15.method1837`: seeded permutation table, shared with `OpFractal`.
	static func permutation(seed: Int) -> [UInt8] {
		var rnd = JavaRandom(seed: seed)
		var a = [UInt8](repeating: 0, count: 512)
		for i in 0..<255 { a[i] = UInt8(i) }
		for i in 0..<255 {
			let k = 255 - i
			let j = rnd.nextInt(k)
			let t = a[j]
			a[j] = a[k]
			a[k] = t
			a[511 - i] = t
		}
		return a
	}
	override func decode(_ op: Int, _ p: inout Packet) throws {
		switch op {
		case 0: hCells = try p.g1(); vCells = hCells
		case 1: seed = try p.g1()
		case 2: jitter = try p.g2()
		case 3: output = try p.g1()
		case 4: metric = try p.g1()
		case 5: hCells = try p.g1()
		case 6: vCells = try p.g1()
		default: break
		}
	}
	override func postDecode() {
		perm = OpCellular.permutation(seed: seed)
		var rnd = JavaRandom(seed: seed)
		jit = [Int](repeating: 0, count: 512)
		if jitter > 0 { for i in 0..<512 { jit[i] = Int(Int16(truncatingIfNeeded: rnd.nextInt(jitter))) } }
	}
	override func computeMono(_ y: Int) -> [Int] {
		var out = zeros()
		let py = vCells * ctx.heightFractions[y] + 2048
		let cy0 = py >> 12
		let cy1 = cy0 + 1
		for x in 0..<ctx.width {
			var d1 = Int(Int32.max), d2 = d1, d3 = d1, d4 = d1
			let px = hCells * ctx.widthFractions[x] + 2048
			let cx0 = px >> 12
			let cx1 = cx0 + 1
			for cy in (cy0 - 1)...cy1 {
				let a = Int(perm[(vCells <= cy ? cy - vCells : cy) & 0xFF])
				for cx in (cx0 - 1)...cx1 {
					let idx = (Int(perm[((hCells <= cx ? cx - hCells : cx) + a) & 0xFF])) * 2
					var dx = -(cx << 12) + px - jit[idx]
					var dy = py - jit[idx + 1] - (cy << 12)
					let v: Int
					switch metric {
					case 1: v = ((dy * dy) + (dx * dx)) >> 12
					case 3:
						dx = dx < 0 ? -dx : dx
						dy = dy >= 0 ? dy : -dy
						v = dy >= dx ? dy : dx
					case 4:
						dx = jint(fsqrt(dx < 0 ? -dx : dx, 4096.0) * 4096.0)
						dy = jint(fsqrt(dy >= 0 ? dy : -dy, 4096.0) * 4096.0)
						let s = dy + dx
						v = (s * s) >> 12
					case 5:
						let sx = dx * dx, sy = dy * dy
						v = jint(fsqrt(sy + sx, 1.6777216E7).squareRoot() * 4096.0)
					case 2: v = (dx >= 0 ? dx : -dx) + (dy < 0 ? -dy : dy)
					default: v = jint(fsqrt((dy * dy) + (dx * dx), 1.6777216E7) * 4096.0)
					}
					if v < d1 { d4 = d3; d3 = d2; d2 = d1; d1 = v }
					else if v < d2 { d4 = d3; d3 = d2; d2 = v }
					else if d3 > v { d4 = d3; d3 = v }
					else if v < d4 { d4 = v }
				}
			}
			switch output {
			case 0: out[x] = d1
			case 1: out[x] = d2
			case 3: out[x] = d3
			case 4: out[x] = d4
			case 2: out[x] = d2 - d1
			default: break
			}
		}
		return out
	}
}

/// rt4 `TextureOp16` (type 16): woven/diagonal lattice.
final class OpWeave: TextureOp {
	var width = 204, a = 1, b = 1
	init() { super.init(inputs: 0, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { b = try p.g1() } else if op == 1 { a = try p.g1() } else if op == 2 { width = try p.g2() }
	}
	override func computeMono(_ y: Int) -> [Int] {
		var out = zeros()
		let hy = ctx.heightFractions[y]
		for x in 0..<ctx.width {
			let wx = ctx.widthFractions[x]
			var u = (b * wx) >> 12
			let v = (hy * a) >> 12
			let cx = b * (wx % max(4096 / b, 1))
			let cy = (hy % max(4096 / a, 1)) * a
			if width > cy {
				u -= v
				while u < 0 { u += 4 }
				while u > 3 { u -= 4 }
				if u != 1 { out[x] = 0; continue }
				if width > cx { out[x] = 0; continue }
			}
			if cx < width {
				u -= v
				while u < 0 { u += 4 }
				while u > 3 { u -= 4 }
				if u > 0 { out[x] = 0; continue }
			}
			out[x] = 4096
		}
		return out
	}
}

/// rt4 `TextureOp19` (type 19): displace child 0 by angle (child 1) and distance (child 2).
final class OpDisplace: TextureOp {
	var amount = 32768
	init() { super.init(inputs: 3, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { amount = try p.g2() << 4 } else if op == 1 { monochrome = try p.g1() == 1 }
	}
	override func computeColor(_ y: Int) -> [[Int]] {
		let ang = childMono(1, y), dist = childMono(2, y)
		var out = zeros3()
		for x in 0..<ctx.width {
			let a = ((ang[x] * 255) >> 12) & 0xFF
			let d = (dist[x] * amount) >> 12
			let dx = (d * TextureOp.cosine[a]) >> 12
			let dy = (TextureOp.sine[a] * d) >> 12
			let sx = ((dx >> 12) + x) & ctx.widthMask
			let sy = ctx.heightMask & (y + (dy >> 12))
			let c = childColor(sy, 0)
			out[0][x] = c[0][sx]; out[1][x] = c[1][sx]; out[2][x] = c[2][sx]
		}
		return out
	}
	override func computeMono(_ y: Int) -> [Int] {
		let ang = childMono(1, y), dist = childMono(2, y)
		var out = zeros()
		for x in 0..<ctx.width {
			let d = (amount * dist[x]) >> 12
			let a = (ang[x] >> 4) & 0xFF
			let dx = (TextureOp.cosine[a] * d) >> 12
			let dy = (TextureOp.sine[a] * d) >> 12
			let sx = ctx.widthMask & ((dx >> 12) + x)
			let sy = ctx.heightMask & ((dy >> 12) + y)
			out[x] = childMono(0, sy)[sx]
		}
		return out
	}
}

/// rt4 `TextureOp23` (type 23): kaleidoscope-style mirroring by angle sector.
final class OpMirror: TextureOp {
	var monoOnly = false
	private var rowSel = 0, colSel = 0
	init() { super.init(inputs: 1, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws { if op == 0 { monochrome = try p.g1() == 1 } }
	private func select(_ y: Int, _ x: Int) {
		let wx = ctx.widthFractions[x]
		let hy = ctx.heightFractions[y]
		let f = Float(atan2(Double(wx - 2048), Double(hy - 2048)))
		let d = Double(f)
		let pi = 3.141592653589793
		if d >= -pi && -2.356194490192345 >= d { rowSel = y; colSel = x }
		else if d <= -1.5707963267948966 && -2.356194490192345 <= d { colSel = y; rowSel = x }
		else if d <= -0.7853981633974483 && d >= -1.5707963267948966 { colSel = ctx.width - y; rowSel = x }
		else if f <= 0.0 && d >= -0.7853981633974483 { colSel = x; rowSel = ctx.height - y }
		else if f >= 0.0 && d <= 0.7853981633974483 { colSel = ctx.width - x; rowSel = ctx.height - y }
		else if d >= 0.7853981633974483 && d <= 1.5707963267948966 { colSel = ctx.width - y; rowSel = ctx.height - x }
		else if d >= 1.5707963267948966 && d <= 2.356194490192345 { rowSel = ctx.height - x; colSel = y }
		else if d >= 2.356194490192345 && d <= pi { colSel = ctx.width - x; rowSel = y }
		colSel &= ctx.widthMask
		rowSel &= ctx.heightMask
	}
	override func computeMono(_ y: Int) -> [Int] {
		var out = zeros()
		for x in 0..<ctx.width { select(y, x); out[x] = childMono(0, rowSel)[colSel] }
		return out
	}
	override func computeColor(_ y: Int) -> [[Int]] {
		var out = zeros3()
		for x in 0..<ctx.width {
			select(y, x)
			let c = childColor(rowSel, 0)
			out[0][x] = c[0][colSel]; out[1][x] = c[1][colSel]; out[2][x] = c[2][colSel]
		}
		return out
	}
}

/// rt4 `TextureOp27` (type 27): stripes.
final class OpStripes: TextureOp {
	var count = 10, dutyRaw = 2048, mode = 0
	private var starts: [Int] = [], ends: [Int] = []
	init() { super.init(inputs: 0, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { count = try p.g1() } else if op == 1 { dutyRaw = try p.g2() } else if op == 2 { mode = try p.g1() }
	}
	override func postDecode() throws {
		guard count > 0 else { throw TextureError("stripes with zero count") }
		var pos = 0
		let step = 4096 / count
		let on = (dutyRaw * step) >> 12
		starts = [Int](repeating: 0, count: count + 1)
		ends = [Int](repeating: 0, count: count + 1)
		for i in 0..<count { starts[i] = pos; ends[i] = pos + on; pos += step }
		starts[count] = 4096
		ends[count] = ends[0] + 4096
	}
	private func lookup(_ v: Int) -> Int {
		for i in 0..<count where starts[i] <= v && v < starts[i + 1] { return v < ends[i] ? 4096 : 0 }
		return 0
	}
	override func computeMono(_ y: Int) -> [Int] {
		let hy = ctx.heightFractions[y]
		if mode == 0 { return [Int](repeating: lookup(hy), count: ctx.width) }
		var out = zeros()
		for x in 0..<ctx.width {
			let wx = ctx.widthFractions[x]
			var v = 0
			if mode == 1 { v = wx } else if mode == 2 { v = ((wx + hy - 4096) >> 1) + 2048 } else if mode == 3 { v = ((wx - hy) >> 1) + 2048 }
			out[x] = lookup(v)
		}
		return out
	}
}

/// rt4 `TextureOp31` (type 31): Mandelbrot set.
final class OpMandelbrot: TextureOp {
	var scale = 1365, offY = 0, offX = 0, iterations = 20
	init() { super.init(inputs: 0, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { scale = try p.g2() } else if op == 1 { iterations = try p.g2() } else if op == 2 { offX = try p.g2() } else if op == 3 { offY = try p.g2() }
	}
	override func computeMono(_ y: Int) -> [Int] {
		var out = zeros()
		for x in 0..<ctx.width {
			let cy = offY + jdiv(ctx.heightFractions[y] << 12, scale)
			let cx = offX + jdiv(ctx.widthFractions[x] << 12, scale)
			var zx = cx, zy = cy, n = 0
			var xx = (cx * cx) >> 12
			var yy = (cy * cy) >> 12
			while xx + yy < 16384 && iterations > n {
				zy = (((zx * zy) >> 12) * 2) + cy
				n += 1
				zx = xx + cx - yy
				yy = (zy * zy) >> 12
				xx = (zx * zx) >> 12
			}
			out[x] = n >= iterations - 1 ? 0 : jdiv(n << 12, iterations)
		}
		return out
	}
}

/// rt4 `TextureOp32` (type 32): emboss-style lighting of a height map.
final class OpLighting: TextureOp {
	var strength = 4096, az = 3216, el = 3216
	private var light = [0, 0, 0]
	init() { super.init(inputs: 1, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { strength = try p.g2() } else if op == 1 { az = try p.g2() } else if op == 2 { el = try p.g2() }
	}
	override func postDecode() {
		func f(_ v: Int) -> Double { Double(Float(v) / 4096.0) }
		let ce = cos(f(el))
		light[0] = Int(ce * 4096.0 * sin(f(az)))
		light[1] = Int(cos(f(az)) * ce * 4096.0)
		light[2] = Int(sin(f(el)) * 4096.0)
		let a = (light[2] * light[2]) >> 12
		let b = (light[1] * light[1]) >> 12
		let c = (light[0] * light[0]) >> 12
		let n = jint(Double((c + b + a) >> 12).squareRoot() * 4096.0)
		if n != 0 {
			light[2] = (light[2] << 12) / n
			light[0] = (light[0] << 12) / n
			light[1] = (light[1] << 12) / n
		}
	}
	override func computeMono(_ y: Int) -> [Int] {
		let k = (ctx.unit * strength) >> 12
		let up = childMono(0, ctx.heightMask & (y - 1))
		let mid = childMono(0, y)
		let dn = childMono(0, (y + 1) & ctx.heightMask)
		var out = zeros()
		for x in 0..<ctx.width {
			let gx = ((mid[ctx.widthMask & (x - 1)] - mid[(x + 1) & ctx.widthMask]) * k) >> 12
			let gy = (k * (dn[x] - up[x])) >> 12
			var ax = gx >> 4
			if ax < 0 { ax = -ax }
			if ax > 255 { ax = 255 }
			var ay = gy >> 4
			if ay < 0 { ay = -ay }
			if ay > 255 { ay = 255 }
			let n = Int(TextureTables.normalise[((ay * (ay + 1)) >> 1) + ax])
			let ny = (gy * n) >> 8
			let nx = (n * gx) >> 8
			let l1 = (ny * light[1]) >> 12
			let l0 = (light[0] * nx) >> 12
			let nz = (n * 4096) >> 8
			let l2 = (nz * light[2]) >> 12
			out[x] = l2 + l1 + l0
		}
		return out
	}
}

/// rt4 `TextureOp33` (type 33): normal map from a height map (colour output).
final class OpNormalMap: TextureOp {
	var strength = 4096, remap = true
	init() { super.init(inputs: 1, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { strength = try p.g2() } else if op == 1 { remap = try p.g1() == 1 }
	}
	override func computeColor(_ y: Int) -> [[Int]] {
		let up = childMono(0, ctx.heightMask & (y - 1))
		let mid = childMono(0, y)
		let dn = childMono(0, (y + 1) & ctx.heightMask)
		var out = zeros3()
		for x in 0..<ctx.width {
			let sy = strength * (dn[x] - up[x])
			let sx = strength * (mid[(x + 1) & ctx.widthMask] - mid[ctx.widthMask & (x - 1)])
			let gy = sy >> 12
			let gx = sx >> 12
			let q = ((gx * gx) >> 12) + ((gy * gy) >> 12)
			let len = jint(fsqrt(q + 4096, 4096.0) * 4096.0)
			var nz = 0, nx = 0, ny = 0
			if len != 0 {
				nz = 16777216 / len
				ny = sy / len
				nx = sx / len
			}
			if remap {
				ny = (ny >> 1) + 2048
				nz = (nz >> 1) + 2048
				nx = (nx >> 1) + 2048
			}
			out[0][x] = nx
			out[1][x] = ny
			out[2][x] = nz
		}
		return out
	}
}

/// rt4 `TextureOp35` (type 35): ambient-occlusion style shading of a height map.
final class OpShade: TextureOp {
	var strength = 4096
	init() { super.init(inputs: 1, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws { if op == 0 { strength = try p.g2() } }
	override func computeMono(_ y: Int) -> [Int] {
		let up = childMono(0, (y - 1) & ctx.heightMask)
		let mid = childMono(0, y)
		let dn = childMono(0, ctx.heightMask & (y + 1))
		var out = zeros()
		for x in 0..<ctx.width {
			let sy = (dn[x] - up[x]) * strength
			let sx = strength * (mid[ctx.widthMask & (x + 1)] - mid[(x - 1) & ctx.widthMask])
			let gx = sx >> 12
			let gy = sy >> 12
			let q = ((gx * gx) >> 12) + ((gy * gy) >> 12)
			let len = jint(fsqrt(q + 4096, 4096.0) * 4096.0)
			out[x] = 4096 - (len == 0 ? 0 : 16777216 / len)
		}
		return out
	}
}

/// rt4 `TextureOp37` (type 37): ornamental curve pattern.
final class OpOrnament: TextureOp {
	var p0 = 2048, p1 = 0, p2 = 0, p3 = 2048, freq = 12288, amp = 4096, div = 8192
	init() { super.init(inputs: 0, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		switch op {
		case 0: p0 = try p.g2()
		case 1: p1 = try p.g2()
		case 2: p2 = try p.g2()
		case 3: p3 = try p.g2()
		case 4: freq = try p.g2()
		case 5: amp = try p.g2()
		case 6: div = try p.g2()
		default: break
		}
	}
	private func wrap(_ v: Int) -> Int {
		let a = v < -2048 ? v + 4096 : v
		return a > 2048 ? a - 4096 : a
	}
	private func testA(_ a: Int, _ b: Int) -> Bool {
		let t = ((b - a) * freq) >> 12
		let c = TextureOp.cosine[((t * 255) >> 12) & 0xFF]
		let d = jdiv(c << 12, freq)
		let e = jdiv(d << 12, div)
		let f = (e * amp) >> 12
		return a + b < f && -f < a + b
	}
	private func testB(_ a: Int, _ b: Int) -> Bool {
		let t = (freq * (a + b)) >> 12
		let c = TextureOp.cosine[((t * 255) >> 12) & 0xFF]
		let d = jdiv(c << 12, freq)
		let e = jdiv(d << 12, div)
		let f = (e * amp) >> 12
		return f > b - a && -f < b - a
	}
	override func computeMono(_ y: Int) -> [Int] {
		var out = zeros()
		let hy = ctx.heightFractions[y] - 2048
		for x in 0..<ctx.width {
			let a = hy + p1
			let wx = ctx.widthFractions[x] - 2048
			let b = p0 + wx
			let ya = wrap(a)
			let xa = wrap(b)
			let xb = wrap(wx + p2)
			let yb = wrap(hy + p3)
			out[x] = testA(xa, ya) || testB(xb, yb) ? 4096 : 0
		}
		return out
	}
}

/// rt4 `TextureOp34` (type 34): fractal (Perlin) noise.
final class OpFractal: TextureOp {
	/// rt4 anInt642 (octave count), anInt641 (vertical cells), anInt646 (horizontal cells).
	var octaves = 4, rowCells = 4, colCells = 4, remap = true, seed = 0
	var gain = 1638
	private var amp: [Int] = [], freq: [Int] = []
	private var perm = [UInt8](repeating: 0, count: 512)
	init() { super.init(inputs: 0, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		switch op {
		case 0: remap = try p.g1() == 1
		case 1: octaves = try p.g1()
		case 2:
			gain = try p.g2b()
			if gain < 0 {
				amp = []
				for _ in 0..<octaves { amp.append(Int(Int16(truncatingIfNeeded: try p.g2b()))) }
			}
		case 3: rowCells = try p.g1(); colCells = rowCells
		case 4: seed = try p.g1()
		case 5: colCells = try p.g1()
		case 6: rowCells = try p.g1()
		default: break
		}
	}
	override func postDecode() throws {
		perm = OpCellular.permutation(seed: seed)
		if gain > 0 {
			amp = (0..<octaves).map { Int(Int16(truncatingIfNeeded: Int(pow(Double(Float(gain) / 4096.0), Double($0)) * 4096.0))) }
			freq = (0..<octaves).map { Int(Int16(truncatingIfNeeded: Int(pow(2.0, Double($0))))) }
		} else if amp.count == octaves {
			freq = (0..<octaves).map { Int(Int16(truncatingIfNeeded: Int(pow(2.0, Double($0))))) }
		}
		guard octaves >= 1, amp.count == octaves, freq.count == octaves else { throw TextureError("fractal noise without amplitudes") }
		var i = octaves - 1
		while i >= 1 {
			if amp[i] > 8 || amp[i] < -8 { break }
			octaves -= 1
			i -= 1
		}
	}
	/// rt4 `method590`: one gradient-noise sample.
	private func sample(_ px: Int, _ r1: Int, _ r0: Int, _ wrapX: Int, _ fy: Int, _ sy: Int) -> Int {
		let fy1 = fy - 4096
		let cell = px >> 12
		var cell1 = cell + 1
		let c0 = cell & 0xFF
		if cell1 >= wrapX { cell1 = 0 }
		let fx = px & 0xFFF
		var g = Int(perm[c0 + r0]) & 3
		let sx = TextureTables.smooth[fx]
		var a: Int
		if g > 1 { a = g == 2 ? fx - fy : -fx + -fy } else { a = g == 0 ? fy + fx : -fx + fy }
		cell1 &= 0xFF
		let fx1 = fx - 4096
		g = Int(perm[r0 + cell1]) & 3
		var b: Int
		if g <= 1 { b = g == 0 ? fy + fx1 : -fx1 + fy } else { b = g == 2 ? fx1 - fy : -fx1 + -fy }
		g = Int(perm[c0 + r1]) & 3
		let top = a + (((b - a) * sx) >> 12)
		if g > 1 { a = g == 2 ? fx - fy1 : -fx - fy1 } else { a = g == 0 ? fx + fy1 : fy1 + -fx }
		g = Int(perm[r1 + cell1]) & 3
		if g > 1 { b = g == 2 ? fx1 - fy1 : -fy1 + -fx1 } else { b = g == 0 ? fx1 + fy1 : fy1 + -fx1 }
		let bottom = a + (((b - a) * sx) >> 12)
		return top + ((sy * (bottom - top)) >> 12)
	}
	/// Per-octave row setup shared by all octaves: (hash of this row, hash of next row, wrapX, fractional y, smoothed y).
	private func rowSetup(_ f: Int, _ hy: Int) -> (r0: Int, r1: Int, wrapX: Int, fy: Int, sy: Int) {
		var py = (hy * f) >> 12
		let cy = py >> 12
		let r0 = Int(perm[cy & 0xFF])
		let wrapX = (colCells * f) >> 12
		let wrapY = (f * rowCells) >> 12
		py &= 0xFFF
		let sy = TextureTables.smooth[py]
		var cy1 = cy + 1
		if wrapY <= cy1 { cy1 = 0 }
		let r1 = Int(perm[cy1 & 0xFF])
		return (r0, r1, wrapX, py, sy)
	}
	override func computeMono(_ y: Int) -> [Int] {
		var out = zeros()
		let hy = rowCells * ctx.heightFractions[y]
		let w = ctx.width
		if octaves == 1 {
			let a = amp[0]
			let f = freq[0] << 12
			let s = rowSetup(f, hy)
			for x in 0..<w {
				let px = colCells * ctx.widthFractions[x]
				var v = sample((f * px) >> 12, s.r1, s.r0, s.wrapX, s.fy, s.sy)
				v = (a * v) >> 12
				out[x] = remap ? (v >> 1) + 2048 : v
			}
			return out
		}
		var a = amp[0]
		if a > 8 || a < -8 {
			let f = freq[0] << 12
			let s = rowSetup(f, hy)
			for x in 0..<w {
				let px = ctx.widthFractions[x] * colCells
				let v = sample((px * f) >> 12, s.r1, s.r0, s.wrapX, s.fy, s.sy)
				out[x] = (v * a) >> 12
			}
		}
		var o = 1
		while o < octaves {
			a = amp[o]
			if a > 8 || a < -8 {
				let f = freq[o] << 12
				let s = rowSetup(f, hy)
				if remap && o == octaves - 1 {
					for x in 0..<w {
						let px = ctx.widthFractions[x] * colCells
						var v = sample((f * px) >> 12, s.r1, s.r0, s.wrapX, s.fy, s.sy)
						v = ((a * v) >> 12) + out[x]
						out[x] = (v >> 1) + 2048
					}
				} else {
					for x in 0..<w {
						let px = ctx.widthFractions[x] * colCells
						let v = sample((px * f) >> 12, s.r1, s.r0, s.wrapX, s.fy, s.sy)
						out[x] += (v * a) >> 12
					}
				}
			}
			o += 1
		}
		return out
	}
}
