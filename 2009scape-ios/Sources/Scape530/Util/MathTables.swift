import Foundation

/// rt4 `MathUtils` lookup tables: 2048-step sine/cosine scaled by 65536.
public enum MathTables {
	public static let sin: [Int] = (0..<2048).map { Int(Foundation.sin(Double($0) * 0.0030679615) * 65536.0) }
	public static let cos: [Int] = (0..<2048).map { Int(Foundation.cos(Double($0) * 0.0030679615) * 65536.0) }
}

/// rt4 `PerlinNoise`: the procedural height used for level-0 tiles that do
/// not store one. Java int overflow semantics are kept with wrapping ops.
public enum PerlinNoise {
	public static func tileHeight(_ a: Int, _ b: Int) -> Int {
		var h = interpolatedNoise(4, b + 45365, a + 91923)
			+ ((interpolatedNoise(2, b + 10294, a + 37821) - 128) >> 1)
			+ ((interpolatedNoise(1, b, a) - 128) >> 2) - 128
		h = Int(Double(h) * 0.3) + 35
		return min(60, max(10, h))
	}

	static func interpolatedNoise(_ scale: Int, _ x: Int, _ z: Int) -> Int {
		let ix = x / scale, iz = z / scale
		let fz = z & (scale - 1), fx = (scale - 1) & x
		let a = smoothNoise(ix, iz), b = smoothNoise(ix + 1, iz)
		let c = smoothNoise(ix, iz + 1), d = smoothNoise(ix + 1, iz + 1)
		return interpolate(interpolate(a, b, fx, scale), interpolate(c, d, fx, scale), fz, scale)
	}

	static func smoothNoise(_ x: Int, _ z: Int) -> Int {
		let corners = noise(x - 1, z - 1) + noise(x + 1, z - 1) + noise(x - 1, z + 1) + noise(x + 1, z + 1)
		let sides = noise(x - 1, z) + noise(x + 1, z) + noise(x, z - 1) + noise(x, z + 1)
		return sides / 8 + corners / 16 + noise(x, z) / 4
	}

	static func interpolate(_ a: Int, _ b: Int, _ t: Int, _ scale: Int) -> Int {
		let f = (65536 - MathTables.cos[t * 1024 / scale]) >> 1
		return ((a * (65536 - f)) >> 16) + ((b * f) >> 16)
	}

	static func noise(_ x: Int, _ z: Int) -> Int {
		let n = Int32(truncatingIfNeeded: z) &* 57 &+ Int32(truncatingIfNeeded: x)
		let m = n ^ (n << 13)
		let v = Int32.max & ((m &* m &* 15731 &+ 789221) &* m &+ 1376312589)
		return Int(v >> 19) & 0xFF
	}
}
