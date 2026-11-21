import Foundation

/// Deterministic generator so tests can reproduce a fire; the client uses the system generator.
public struct FlameRandom: RandomNumberGenerator {
	private var state: UInt64
	public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
	public mutating func next() -> UInt64 {
		state = state &+ 0x9E37_79B9_7F4A_7C15
		var z = state
		z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
		z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
		return z ^ (z >> 31)
	}
}

/// Port of rt4 `Flames`: the software fire drawn under login-interface components with client code 1402.
/// A 128x256 intensity field scrolls upward, is seeded with sparks and blurred, and is blended through a
/// four-colour gradient over whatever is already in the framebuffer.
public final class Flames {
	/// rt4 `Flames.flameGradientSource`.
	public static let gradientSource: [Int] = [0xBF6428, 0xEC963A, 0xF2D766, 0xFFF2BA]
	/// Size of the image `render` produces (rt4 `imageFlames`).
	public static let width = 128, height = 254

	private var rng: any RandomNumberGenerator
	/// rt4 `flameShiftX`.
	private var shiftX = [Int](repeating: 0, count: 256)
	/// rt4 `flameCycle`: client cycles since the last `render`.
	private var cycles = 0
	private var buffer1 = [Int](repeating: 0, count: 32768)
	private var buffer2 = [Int](repeating: 0, count: 32768)
	private var intensityBuffer = [Int](repeating: 0, count: 32768)
	private var intensity = [Int](repeating: 0, count: 32768)
	private var gradient = [Int](repeating: 0, count: 256)
	private var runes: [SpriteFrame]
	private var offset = 0
	/// rt4 `Flames.anInt6` and `anInt5084`.
	private var wave = 0
	private var sparks = 0
	/// rt4 `client.loop`, used for the blur radius parity.
	public var loop = 0

	/// - Parameter runes: the frames of sprite group "runes" (rt4 `Flames.load`).
	public init(runes: [SpriteFrame], rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
		self.runes = runes
		self.rng = rng
		// rt4 `Flames.load`: three 64-step gradient segments between the source colours, then a flat top.
		for seg in 0..<3 {
			let next = Flames.gradientSource[seg + 1], cur = Flames.gradientSource[seg]
			var r = Float((cur >> 16) & 0xFF), g = Float((cur >> 8) & 0xFF), b = Float(cur & 0xFF)
			let dr = (Float((next >> 16) & 0xFF) - r) / 64, dg = (Float((next >> 8) & 0xFF) - g) / 64, db = (Float(next & 0xFF) - b) / 64
			for i in 0..<64 {
				gradient[i + seg * 64] = Int(b) | Int(g) << 8 | Int(r) << 16
				g += dg; b += db; r += dr
			}
		}
		for i in 192..<255 { gradient[i] = Flames.gradientSource[3] }
		setRune(nil)
	}

	/// The gradient colour for an intensity (tests).
	public func gradientColor(_ i: Int) -> Int { gradient[i] }

	/// rt4 `Flames.update`: once per client cycle.
	public func update() { cycles += 1 }

	private func random(_ n: Int) -> Int { Int(Double.random(in: 0..<1, using: &rng) * Double(n)) }

	/// rt4 `Flames.setRune`: noise field the fire is lit from; a rune's pixels are punched out of it.
	func setRune(_ sprite: SpriteFrame?) {
		for i in 0..<buffer1.count { buffer1[i] = 0 }
		for _ in 0..<5000 {
			let i = Int(256.0 * Double.random(in: 0..<1, using: &rng) * 128.0)
			buffer1[i] = random(284)
		}
		for _ in 0..<20 {
			for y in 1..<255 {
				for x in 1..<127 {
					let p = x + (y << 7)
					buffer2[p] = (buffer1[p + 128] + buffer1[p - 1] + buffer1[p + 1] + buffer1[p - 128]) / 4
				}
			}
			swap(&buffer1, &buffer2)
		}
		guard let s = sprite else { return }
		var i = 0
		for y in 0..<s.innerHeight {
			for x in 0..<s.innerWidth {
				defer { i += 1 }
				if s.indices[i] != 0 {
					let px = s.xOffset + x + 16, py = s.yOffset + y + 16
					let p = px + (py << 7)
					if p >= 0 && p < buffer1.count { buffer1[p] = 0 }
				}
			}
		}
	}

	/// rt4 `Flames.method4528`: advances the fire by `cycles` steps.
	func advance(_ cyclesRaw: Int) {
		var n = min(cyclesRaw, 256)
		n = min(n, 10)
		offset += n * 128
		if buffer1.count < offset {
			offset -= buffer1.count
			if !runes.isEmpty { setRune(runes[min(random(12), runes.count - 1)]) }
		}
		var p = 0
		let upper = (256 - n) * 128, step = n * 128
		for _ in 0..<upper {
			var v = intensityBuffer[p + step] - n * buffer1[(buffer1.count - 1) & (offset + p)] / 6
			if v < 0 { v = 0 }
			intensityBuffer[p] = v
			p += 1
		}
		for y in (256 - n)..<256 {
			let row = y * 128
			for x in 0..<128 {
				intensityBuffer[x + row] = (random(100) < 50 && x > 10 && x < 118) ? 255 : 0
			}
		}
		for y in 0..<(256 - n) { shiftX[y] = shiftX[y + n] }
		for y in (256 - n)..<256 {
			let w = Double(wave)
			shiftX[y] = Int(sin(w / 14.0) * 16.0 + sin(w / 15.0) * 14.0 + sin(w / 16.0) * 12.0)
			wave += 1
		}
		sparks += n
		let radius = (n + (loop & 1)) / 2
		guard radius > 0 else { return }
		for _ in 0..<sparks {
			let x = random(124) + 2
			let y = random(128) + 128
			intensityBuffer[x + (y << 7)] = 192
		}
		sparks = 0
		// Horizontal box blur, then vertical (rt4 does it in place with running sums).
		for y in 0..<256 {
			let row = y * 128
			var sum = 0
			for x in -radius..<128 {
				if radius + x < 128 { sum += intensityBuffer[row + x + radius] }
				if x - radius - 1 >= 0 { sum -= intensityBuffer[x + row - radius - 1] }
				if x >= 0 { intensity[x + row] = sum / (radius * 2 + 1) }
			}
		}
		for x in 0..<128 {
			var sum = 0
			for y in -radius..<256 {
				let row = y * 128
				if y + radius < 256 { sum += intensity[radius * 128 + x + row] }
				if y - radius - 1 >= 0 { sum -= intensity[x + row - (radius + 1) * 128] }
				if y >= 0 { intensityBuffer[row + x] = sum / (radius * 2 + 1) }
			}
		}
	}

	/// rt4 `Flames.render(x, y)`: advances the fire by the cycles since the last call, then replaces the 128x254
	/// block of `raster` at (x, y) with the fire blended over what is there, shifted sideways per row.
	public func render(into raster: inout Raster, x: Int, y: Int) {
		if cycles > 0 {
			advance(cycles)
			cycles = 0
		}
		var src = 0
		var out = [UInt32](repeating: 0, count: Flames.width * Flames.height)
		var o = 0
		for row in 1..<255 {
			var shift = (256 - row) * shiftX[row] / 256
			if shift < 0 { shift = 0 }
			shift = min(shift, 127)
			src += shift
			let ry = y + row - 1
			func under(_ i: Int) -> UInt32 {
				let px = x + i
				return px >= 0 && px < raster.width && ry >= 0 && ry < raster.height ? raster.pixels[ry * raster.width + px] : 0xFF00_0000
			}
			// The first 128 - shift columns carry fire (the field is read from `shift` on, so it leans left); the last
			// `shift` columns are the untouched framebuffer (rt4 `imageFlames` second loop).
			for col in 0..<(128 - shift) {
				let c = under(col)
				var v = intensityBuffer[src]; src += 1
				if v == 0 {
					out[o] = c
				} else {
					let a = min(v + 18, 255)
					let b = min(256 - v - 18, 255)
					v = gradient[min(v, 255)]
					let cc = UInt32(c & 0xFFFFFF)
					let lhs = (UInt32(b) &* (cc & 0xFF00FF) &+ UInt32(v & 0xFF00FF) &* UInt32(a)) & 0xFF00_FF00
					let rhs = (UInt32(v & 0xFF00) &* UInt32(a) &+ (cc & 0xFF00) &* UInt32(b)) & 0xFF0000
					out[o] = 0xFF00_0000 | (((lhs &+ rhs) >> 8) & 0xFFFFFF)
				}
				o += 1
			}
			for col in (128 - shift)..<128 {
				out[o] = under(col); o += 1
			}
		}
		for row in 0..<Flames.height {
			let ry = y + row
			guard ry >= raster.clipTop, ry < raster.clipBottom else { continue }
			for col in 0..<Flames.width {
				let px = x + col
				guard px >= raster.clipLeft, px < raster.clipRight else { continue }
				raster.pixels[ry * raster.width + px] = out[row * Flames.width + col]
			}
		}
	}
}
