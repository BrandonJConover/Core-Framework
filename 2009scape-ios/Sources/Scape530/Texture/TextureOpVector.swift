import Foundation

/// rt4 `TextureOp29` (type 29): a list of vector shapes drawn into a whole image on first use.
///
/// rt4 has four shape kinds (`TextureOp29SubOp1..4`: line, cubic bezier,
/// rectangle, ellipse). The rev-530 cache only uses lines (type 0), so only the
/// line path (`TextureOp29.method3982`, `method1306`, `method4019` and
/// `TextureOp29SubOp4.method2054/fillRange/method4547`) is ported; the other
/// kinds are parsed for their size and rejected so a cache that uses them
/// fails loudly rather than rendering wrong.
final class OpVector: TextureOp {
	struct Line { let x0: Int, y0: Int, x1: Int, y1: Int, color: Int }
	private var lines: [Line] = []
	private var image: [[Int]]?
	// clip rectangle: rt4 TextureOp29 statics (anInt4164 xMin=0, anInt5063 xMax, anInt5773 yMin=0, anInt2869 yMax)
	private var xMax = 0, yMax = 0

	init() { super.init(inputs: 0, monochrome: true) }

	override func decode(_ op: Int, _ p: inout Packet) throws {
		if op == 0 {
			let n = try p.g1()
			lines = []
			for _ in 0..<n {
				let type = try p.g1()
				if type == 0 {
					// TextureOp29SubOp1.create: four signed shorts (12-bit fractions), colour, spare byte
					let a = try p.g2b(), b = try p.g2b(), c = try p.g2b(), d = try p.g2b()
					let color = try p.g3()
					_ = try p.g1()
					// fields: anInt1010=a (x0), 1012=b (y0), 1017=c (x1), 1015=d (y1)
					lines.append(Line(x0: a, y0: b, x1: c, y1: d, color: color))
				} else {
					throw TextureError("vector texture op uses unported shape type \(type)")
				}
			}
		} else if op == 1 {
			monochrome = try p.g1() == 1
		}
	}

	override func resetState() { image = nil }

	private func drawn() -> [[Int]] {
		if let i = image { return i }
		let w = ctx.width, h = ctx.height
		var img = [[Int]](repeating: [Int](repeating: 0, count: w), count: h)
		xMax = ctx.widthMask
		yMax = ctx.heightMask
		for l in lines {
			// TextureOp29SubOp1.method4009(height, width)
			let x0 = (w * l.x0) >> 12
			let x1 = (l.x1 * w) >> 12
			let y0 = (h * l.y0) >> 12
			let y1 = (h * l.y1) >> 12
			line(&img, l.color, y1, x0, y0, x1)
		}
		image = img
		return img
	}

	private func clamp(_ maxV: Int, _ v: Int, _ minV: Int) -> Int { minV > v ? minV : (v > maxV ? maxV : v) }
	private func put(_ img: inout [[Int]], _ r: Int, _ c: Int, _ v: Int) {
		if r >= 0 && r < img.count && c >= 0 && c < img[r].count { img[r][c] = v }
	}
	private func rowFill(_ img: inout [[Int]], _ r: Int, _ a: Int, _ b: Int, _ v: Int) {
		guard r >= 0 && r < img.count else { return }
		var i = max(a, 0)
		let e = min(b, img[r].count)
		while i < e { img[r][i] = v; i += 1 }
	}

	/// rt4 `TextureOp29SubOp4.method2054`: vertical run in column `x`.
	private func vline(_ img: inout [[Int]], _ a: Int, _ x: Int, _ b: Int, _ v: Int) {
		if a <= b { var r = a; while r < b { put(&img, r, x, v); r += 1 } }
		else { var r = b; while r < a { put(&img, r, x, v); r += 1 } }
	}

	/// rt4 `TextureOp29SubOp4.fillRange`: horizontal run in row `y` between two columns.
	private func hline(_ img: inout [[Int]], _ v: Int, _ y: Int, _ b: Int, _ a: Int) {
		if a <= b { rowFill(&img, y, a, b, v) } else { rowFill(&img, y, b, a, v) }
	}

	/// rt4 `TextureOp29.method3982`: clip a line to the image and draw it.
	private func line(_ img: inout [[Int]], _ color: Int, _ y1: Int, _ x0: Int, _ y0: Int, _ x1: Int) {
		let dx = x1 - x0
		let dy = y1 - y0
		if dx == 0 {
			if dy != 0 {
				// method1306
				if x0 >= 0 && x0 <= xMax { vline(&img, clamp(yMax, y0, 0), x0, clamp(yMax, y1, 0), color) }
			}
		} else if dy == 0 {
			// method4019
			if y0 >= 0 && y0 <= yMax { hline(&img, color, y0, clamp(xMax, x1, 0), clamp(xMax, x0, 0)) }
		} else {
			let slope = (dy << 12) / dx // dx != 0 here
			let b = y0 - ((slope * x0) >> 12)
			var sx0: Int, sy0: Int
			if 0 > x0 { sx0 = 0; sy0 = ((0 * slope) >> 12) + b }
			else if x0 > xMax { sy0 = ((xMax * slope) >> 12) + b; sx0 = xMax }
			else { sx0 = x0; sy0 = y0 }
			var sx1: Int, sy1: Int
			if x1 < 0 { sx1 = 0; sy1 = b + ((slope * 0) >> 12) }
			else if xMax < x1 { sx1 = xMax; sy1 = b + ((slope * xMax) >> 12) }
			else { sy1 = y1; sx1 = x1 }
			if 0 > sy1 { sx1 = jdiv((0 - b) << 12, slope); sy1 = 0 }
			else if sy1 > yMax { sy1 = yMax; sx1 = jdiv((yMax - b) << 12, slope) }
			if sy0 < 0 { sy0 = 0; sx0 = jdiv((0 - b) << 12, slope) }
			else if yMax < sy0 { sy0 = yMax; sx0 = jdiv((yMax - b) << 12, slope) }
			bresenham(&img, color, sy1, sy0, sx1, sx0)
		}
	}

	/// rt4 `TextureOp29SubOp4.method4547`.
	private func bresenham(_ img: inout [[Int]], _ color: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int) {
		var arg1 = a1, arg2 = a2, arg3 = a3, arg4 = a4
		var l9 = arg1 - arg2
		var l14 = arg3 - arg4
		if l14 == 0 {
			if l9 != 0 { vline(&img, arg2, arg4, arg1, color) }
			return
		}
		if l9 == 0 { hline(&img, color, arg2, arg3, arg4); return }
		if l9 < 0 { l9 = -l9 }
		if l14 < 0 { l14 = -l14 }
		let steep = l14 < l9
		if steep {
			swap(&arg1, &arg3)
			swap(&arg2, &arg4)
		}
		if arg3 < arg4 {
			swap(&arg3, &arg4)
			swap(&arg1, &arg2)
		}
		var pos = arg2
		let span = arg3 - arg4
		var delta = arg1 - arg2
		var err = -(span >> 1)
		let stepDir = arg1 <= arg2 ? -1 : 1
		if delta < 0 { delta = -delta }
		var i = arg4
		if steep {
			while i <= arg3 {
				put(&img, i, pos, color)
				err += delta
				if err > 0 { pos += stepDir; err -= span }
				i += 1
			}
		} else {
			while i <= arg3 {
				err += delta
				put(&img, pos, i, color)
				if err > 0 { pos += stepDir; err -= span }
				i += 1
			}
		}
	}

	override func computeMono(_ y: Int) -> [Int] { drawn()[y] }
	override func computeColor(_ y: Int) -> [[Int]] {
		let row = drawn()[y]
		return [row.map { ($0 >> 12) & 0xFF0 }, row.map { ($0 >> 4) & 0xFF0 }, row.map { ($0 & 0xFF) << 4 }]
	}
}
