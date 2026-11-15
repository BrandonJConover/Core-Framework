/// Port of rt4 `IsaacRandom` (Bob Jenkins' ISAAC), used to scramble packet
/// opcodes.
///
/// 2009scape's rt4 build ships with `GlobalConfig.USE_ISAAC = false`, which
/// makes `nextKey()` always return 0. `enabled` mirrors that switch so the
/// cipher state is still built (and testable) but opcodes go out in the clear.
public struct IsaacRandom {
	public var enabled: Bool
	private var rsl = [UInt32](repeating: 0, count: 256)
	private var mem = [UInt32](repeating: 0, count: 256)
	private var a: UInt32 = 0
	private var b: UInt32 = 0
	private var c: UInt32 = 0
	private var count = 0

	public init(seed: [Int32], enabled: Bool = false) {
		self.enabled = enabled
		for (i, s) in seed.prefix(256).enumerated() {
			rsl[i] = UInt32(bitPattern: s)
		}
		initState()
	}

	/// Next opcode key. Always 0 when `enabled` is false (2009scape default).
	public mutating func nextKey() -> Int {
		guard enabled else { return 0 }
		return Int(Int32(bitPattern: nextRaw()))
	}

	/// The raw ISAAC stream, independent of `enabled` (for tests).
	public mutating func nextRaw() -> UInt32 {
		if count == 0 {
			isaac()
			count = 256
		}
		count -= 1
		return rsl[count]
	}

	private mutating func initState() {
		var h = [UInt32](repeating: 0x9E37_79B9, count: 8)

		func mix(_ h: inout [UInt32]) {
			h[0] ^= h[1] << 11; h[3] &+= h[0]; h[1] &+= h[2]
			h[1] ^= h[2] >> 2; h[4] &+= h[1]; h[2] &+= h[3]
			h[2] ^= h[3] << 8; h[5] &+= h[2]; h[3] &+= h[4]
			h[3] ^= h[4] >> 16; h[6] &+= h[3]; h[4] &+= h[5]
			h[4] ^= h[5] << 10; h[7] &+= h[4]; h[5] &+= h[6]
			h[5] ^= h[6] >> 4; h[0] &+= h[5]; h[6] &+= h[7]
			h[6] ^= h[7] << 8; h[1] &+= h[6]; h[7] &+= h[0]
			h[7] ^= h[0] >> 9; h[2] &+= h[7]; h[0] &+= h[1]
		}

		for _ in 0..<4 { mix(&h) }
		for i in stride(from: 0, to: 256, by: 8) {
			for j in 0..<8 { h[j] &+= rsl[i + j] }
			mix(&h)
			for j in 0..<8 { mem[i + j] = h[j] }
		}
		for i in stride(from: 0, to: 256, by: 8) {
			for j in 0..<8 { h[j] &+= mem[i + j] }
			mix(&h)
			for j in 0..<8 { mem[i + j] = h[j] }
		}
		isaac()
		count = 256
	}

	private mutating func isaac() {
		c &+= 1
		b &+= c
		for i in 0..<256 {
			let x = mem[i]
			switch i & 3 {
			case 0: a ^= a << 13
			case 1: a ^= a >> 6
			case 2: a ^= a << 2
			default: a ^= a >> 16
			}
			a &+= mem[(i + 128) & 0xFF]
			let y = mem[Int((x >> 2) & 0xFF)] &+ a &+ b
			mem[i] = y
			b = mem[Int((y >> 10) & 0xFF)] &+ x
			rsl[i] = b
		}
	}
}
