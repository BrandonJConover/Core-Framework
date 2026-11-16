import Foundation

// Simple generators and filters. Each class names the rt4 class it ports.

/// rt4 `TextureOpMonochromeFill` (type 0).
final class OpMonochromeFill: TextureOp {
	var value = 4096
	init() { super.init(inputs: 0, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws { if op == 0 { value = (try p.g1() << 12) / 255 } }
	override func computeMono(_ y: Int) -> [Int] { [Int](repeating: value, count: ctx.width) }
}

/// rt4 `TextureOpColorFill` (type 1).
final class OpColorFill: TextureOp {
	var red = 0, green = 0, blue = 0
	init() { super.init(inputs: 0, monochrome: false); setColor(0) }
	func setColor(_ c: Int) { green = (c >> 4) & 0xFF0; blue = (c & 0xFF) << 4; red = (c >> 12) & 0xFF0 }
	override func decode(_ op: Int, _ p: inout Packet) throws { if op == 0 { setColor(try p.g3()) } }
	override func computeColor(_ y: Int) -> [[Int]] {
		let w = ctx.width
		return [[Int](repeating: red, count: w), [Int](repeating: green, count: w), [Int](repeating: blue, count: w)]
	}
}

/// rt4 `TextureOpHorizontalGradient` (type 2).
final class OpHorizontalGradient: TextureOp {
	init() { super.init(inputs: 0, monochrome: true) }
	override func computeMono(_ y: Int) -> [Int] { ctx.widthFractions }
}

/// rt4 `TextureOpVerticalGradient` (type 3).
final class OpVerticalGradient: TextureOp {
	init() { super.init(inputs: 0, monochrome: true) }
	override func computeMono(_ y: Int) -> [Int] { [Int](repeating: ctx.heightFractions[y], count: ctx.width) }
}

/// rt4 `TextureOpNoise` (type 13): integer hash noise.
final class OpNoise: TextureOp {
	init() { super.init(inputs: 0, monochrome: true) }
	private func hash(_ a: Int, _ b: Int) -> Int {
		let n = Int32(truncatingIfNeeded: b &+ a &* 57)
		let m = n ^ (n << 1)
		let v = m &* (m &* m &* 15731 &+ 789221) &+ 1376312589
		return 4096 - Int((v & Int32.max) / 262144)
	}
	override func computeMono(_ y: Int) -> [Int] {
		let hy = ctx.heightFractions[y]
		return (0..<ctx.width).map { hash(hy, ctx.widthFractions[$0]) % 4096 }
	}
}

/// rt4 `TextureOpInvert` (type 22).
final class OpInvert: TextureOp {
	init() { super.init(inputs: 1, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws { if op == 0 { monochrome = try p.g1() == 1 } }
	override func computeMono(_ y: Int) -> [Int] { childMono(0, y).map { 4096 - $0 } }
	override func computeColor(_ y: Int) -> [[Int]] { childColor(y, 0).map { $0.map { 4096 - $0 } } }
}

/// rt4 `TextureOpMonochrome` (type 24): colour to grey.
final class OpMonochrome: TextureOp {
	init() { super.init(inputs: 1, monochrome: true) }
	override func computeMono(_ y: Int) -> [Int] {
		let c = childColor(y, 0)
		return (0..<ctx.width).map { (c[2][$0] + c[0][$0] + c[1][$0]) / 3 }
	}
}

/// rt4 `TextureOpBinary` (type 26): threshold to 0 or 4096.
final class OpBinary: TextureOp {
	var maxValue = 4096, minValue = 0
	init() { super.init(inputs: 1, monochrome: true) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { minValue = try p.g2() } else if op == 1 { maxValue = try p.g2() }
	}
	override func computeMono(_ y: Int) -> [Int] {
		childMono(0, y).map { minValue <= $0 && $0 <= maxValue ? 4096 : 0 }
	}
}

/// rt4 `TextureOpClamp` (type 6).
final class OpClamp: TextureOp {
	var lo = 0, hi = 4096
	init() { super.init(inputs: 1, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { lo = try p.g2() } else if op == 1 { hi = try p.g2() } else if op == 2 { monochrome = try p.g1() == 1 }
	}
	private func clamp(_ v: Int) -> Int { lo > v ? lo : (v > hi ? hi : v) }
	override func computeMono(_ y: Int) -> [Int] { childMono(0, y).map(clamp) }
	override func computeColor(_ y: Int) -> [[Int]] { childColor(y, 0).map { $0.map(clamp) } }
}

/// rt4 `TextureOpFlip` (type 9).
final class OpFlip: TextureOp {
	var flipX = true, flipY = true
	init() { super.init(inputs: 1, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { flipX = try p.g1() == 1 } else if op == 1 { flipY = try p.g1() == 1 } else if op == 2 { monochrome = try p.g1() == 1 }
	}
	private func flip(_ r: [Int]) -> [Int] { flipX ? (0..<ctx.width).map { r[ctx.widthMask - $0] } : r }
	override func computeMono(_ y: Int) -> [Int] { flip(childMono(0, flipY ? ctx.heightMask - y : y)) }
	override func computeColor(_ y: Int) -> [[Int]] { childColor(flipY ? ctx.heightMask - y : y, 0).map(flip) }
}

/// rt4 `TextureOpRange` (type 30): remap 0...4096 to [lo, hi].
final class OpRange: TextureOp {
	var lo = 1024, span = 2048, hi = 3072
	init() { super.init(inputs: 1, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { lo = try p.g2() } else if op == 1 { hi = try p.g2() } else if op == 2 { monochrome = try p.g1() == 1 }
	}
	override func postDecode() { span = hi - lo }
	override func computeMono(_ y: Int) -> [Int] { childMono(0, y).map { lo + (($0 * span) >> 12) } }
	override func computeColor(_ y: Int) -> [[Int]] { childColor(y, 0).map { $0.map { lo + ((span * $0) >> 12) } } }
}

/// rt4 `TextureOpInterpolate` (type 21): blend child 0 and 1 by child 2.
final class OpInterpolate: TextureOp {
	init() { super.init(inputs: 3, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws { if op == 0 { monochrome = try p.g1() == 1 } }
	override func computeMono(_ y: Int) -> [Int] {
		let a = childMono(0, y), b = childMono(1, y), t = childMono(2, y)
		return (0..<ctx.width).map { x in
			let k = t[x]
			if k == 4096 { return a[x] }
			if k == 0 { return b[x] }
			return (k * a[x] + (4096 - k) * b[x]) >> 12
		}
	}
	override func computeColor(_ y: Int) -> [[Int]] {
		let t = childMono(2, y), a = childColor(y, 0), b = childColor(y, 1)
		var out = zeros3()
		for x in 0..<ctx.width {
			let k = t[x]
			for c in 0..<3 {
				if k == 4096 { out[c][x] = a[c][x] }
				else if k == 0 { out[c][x] = b[c][x] }
				else { out[c][x] = ((4096 - k) * b[c][x] + k * a[c][x]) >> 12 }
			}
		}
		return out
	}
}

/// rt4 `TextureOpTile` (type 20).
final class OpTile: TextureOp {
	var hTiles = 4, vTiles = 4
	init() { super.init(inputs: 1, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { hTiles = try p.g1() } else if op == 1 { vTiles = try p.g1() }
	}
	private func srcRow(_ y: Int) -> Int {
		let th = ctx.height / max(vTiles, 1)
		return th > 0 ? (ctx.height * (y % th)) / th : 0
	}
	private func srcCol(_ x: Int) -> Int {
		let tw = ctx.width / max(hTiles, 1)
		return tw > 0 ? (ctx.width * (x % tw)) / tw : 0
	}
	override func computeMono(_ y: Int) -> [Int] {
		let r = childMono(0, srcRow(y))
		return (0..<ctx.width).map { r[srcCol($0)] }
	}
	override func computeColor(_ y: Int) -> [[Int]] {
		let r = childColor(srcRow(y), 0)
		return r.map { ch in (0..<ctx.width).map { ch[srcCol($0)] } }
	}
}

/// rt4 `TextureOp11` (type 11): tint grey pixels with a colour.
final class OpTint: TextureOp {
	var r = 4096, g = 4096, b = 4096
	init() { super.init(inputs: 1, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { r = try p.g2() } else if op == 1 { g = try p.g2() } else if op == 2 { b = try p.g2() }
	}
	override func computeColor(_ y: Int) -> [[Int]] {
		let c = childColor(y, 0)
		var out = zeros3()
		for x in 0..<ctx.width {
			let cr = c[0][x], cg = c[1][x], cb = c[2][x]
			if cr == cb && cg == cb {
				out[0][x] = (r * cr) >> 12
				out[1][x] = (cb * g) >> 12
				out[2][x] = (cg * b) >> 12
			} else { out[0][x] = r; out[1][x] = g; out[2][x] = b }
		}
		return out
	}
}

/// rt4 `TextureOp25` (type 25): recolour pixels near a key colour.
final class OpColorKey: TextureOp {
	var gain1 = 4096, gain2 = 4096, gain3 = 4096, tolerance = 409
	var key = [0, 0, 0]
	init() { super.init(inputs: 1, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		switch op {
		case 0: tolerance = try p.g2()
		case 1: gain2 = try p.g2()
		case 2: gain1 = try p.g2()
		case 3: gain3 = try p.g2()
		case 4:
			let c = try p.g3()
			key[2] = (c >> 12) & 0x0 // rt4 really masks this with 0
			key[1] = (c >> 4) & 0xFF0
			key[0] = (c & 0xFF0000) << 4
		default: break
		}
	}
	override func computeColor(_ y: Int) -> [[Int]] {
		let c = childColor(y, 0)
		var out = zeros3()
		for x in 0..<ctx.width {
			let r = c[0][x], g = c[1][x], b = c[2][x]
			if tolerance < abs(r - key[0]) { out[0][x] = r; out[1][x] = g; out[2][x] = b; continue }
			if abs(g - key[1]) > tolerance { out[0][x] = r; out[1][x] = g; out[2][x] = b; continue }
			if abs(b - key[2]) <= tolerance {
				out[0][x] = (gain3 * r) >> 12
				out[1][x] = (gain1 * g) >> 12
				out[2][x] = (gain2 * b) >> 12
			} else { out[0][x] = r; out[1][x] = g; out[2][x] = b }
		}
		return out
	}
}

/// rt4 `TextureOp17` (type 17): HSL shift of a colour image.
final class OpHslShift: TextureOp {
	var hueShift = 0, satShift = 0, lumShift = 0
	private var out0 = 0, out1 = 0, out2 = 0, hue = 0, sat = 0, lum = 0
	init() { super.init(inputs: 1, monochrome: false) }
	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 { hueShift = try p.g2b() }
		else if op == 1 { satShift = (try p.g1b() << 12) / 100 }
		else if op == 2 { lumShift = (try p.g1b() << 12) / 100 }
	}
	/// rt4 `method1991`: HSL (12-bit) to the three output channels
	/// (`out0` = rt4 anInt2554, `out1` = anInt2543, `out2` = anInt2553).
	private func toRGB(_ l: Int, _ s: Int, _ h: Int) {
		let q = l <= 2048 ? (l * (s + 4096)) >> 12 : l + s - ((l * s) >> 12)
		if q <= 0 { out0 = l; out1 = l; out2 = l; return }
		let h6 = h * 6
		let p = l + l - q
		let sector = h6 >> 12
		let sat = ((q - p) << 12) / q
		let frac = h6 - (sector << 12)
		let t = (q * sat) >> 12
		let u = (t * frac) >> 12
		let rising = u + p
		let falling = q - u
		switch sector {
		case 0: out2 = p; out0 = q; out1 = rising
		case 1: out2 = p; out1 = q; out0 = falling
		case 2: out0 = p; out1 = q; out2 = rising
		case 3: out1 = falling; out2 = q; out0 = p
		case 4: out2 = q; out0 = rising; out1 = p
		case 5: out1 = p; out0 = q; out2 = falling
		default: break
		}
	}
	/// rt4 `method1992`: RGB to HSL (12-bit).
	private func toHSL(_ rr: Int, _ gg: Int, _ bb: Int) {
		let mx0 = rr > gg ? rr : gg
		let mx = bb <= mx0 ? mx0 : bb
		let mn0 = gg > rr ? rr : gg
		let mn = bb >= mn0 ? mn0 : bb
		let d = mx - mn
		if d > 0 {
			let dg = ((mx - gg) << 12) / d
			let dr = ((mx - rr) << 12) / d
			let db = ((mx - bb) << 12) / d
			if rr == mx { hue = mn == gg ? db + 20480 : -dg + 4096 }
			else if mx == gg { hue = mn == bb ? dr + 4096 : -db + 12288 }
			else { hue = mn == rr ? dg + 12288 : -dr + 20480 }
			hue /= 6
		} else { hue = 0 }
		lum = (mn + mx) / 2
		if lum > 0 && lum < 4096 { sat = (d << 12) / (lum > 2048 ? 8192 - lum * 2 : lum * 2) } else { sat = 0 }
	}
	override func computeColor(_ y: Int) -> [[Int]] {
		let c = childColor(y, 0)
		var out = zeros3()
		for x in 0..<ctx.width {
			toHSL(c[0][x], c[1][x], c[2][x])
			lum += lumShift
			if lum < 0 { lum = 0 }
			sat += satShift
			if lum > 4096 { lum = 4096 }
			if sat < 0 { sat = 0 }
			if sat > 4096 { sat = 4096 }
			hue += hueShift
			while hue < 0 { hue += 4096 }
			while hue > 4096 { hue -= 4096 }
			toRGB(lum, sat, hue)
			out[0][x] = out0
			out[1][x] = out1
			out[2][x] = out2
		}
		return out
	}
}
