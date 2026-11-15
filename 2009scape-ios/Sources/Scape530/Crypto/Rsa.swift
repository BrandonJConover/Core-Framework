/// Minimal unsigned big integer, just enough for the login block's RSA step
/// (`Buffer.rsaenc`: m^e mod n with a 1024-bit modulus). Speed is irrelevant
/// here (one modpow per login), so it favours obviously-correct algorithms.
public struct BigUInt: Equatable, Comparable {
	/// Little-endian 32-bit limbs, no trailing zero limbs.
	public private(set) var limbs: [UInt32]

	public init(limbs: [UInt32]) {
		self.limbs = limbs
		normalize()
	}

	public init(_ v: UInt64) {
		self.init(limbs: [UInt32(truncatingIfNeeded: v), UInt32(truncatingIfNeeded: v >> 32)])
	}

	/// Big-endian magnitude bytes (Java `new BigInteger(bytes)` for positive input).
	public init<C: Collection>(bigEndian bytes: C) where C.Element == UInt8 {
		var l: [UInt32] = []
		var cur: UInt32 = 0
		var shift: UInt32 = 0
		for b in bytes.reversed() {
			cur |= UInt32(b) << shift
			shift += 8
			if shift == 32 {
				l.append(cur)
				cur = 0
				shift = 0
			}
		}
		if shift > 0 { l.append(cur) }
		self.init(limbs: l)
	}

	public init?(decimal: String) {
		var r = BigUInt(limbs: [])
		for ch in decimal.utf8 {
			guard ch >= 48 && ch <= 57 else { return nil }
			r = r.mulSmall(10).addSmall(UInt32(ch - 48))
		}
		self = r
	}

	public var isZero: Bool { limbs.isEmpty }
	public var bitWidth: Int {
		guard let top = limbs.last else { return 0 }
		return limbs.count * 32 - top.leadingZeroBitCount
	}

	private mutating func normalize() {
		while let last = limbs.last, last == 0 { limbs.removeLast() }
	}

	func bit(_ i: Int) -> Bool {
		let w = i / 32
		return w < limbs.count && (limbs[w] >> UInt32(i % 32)) & 1 == 1
	}

	func mulSmall(_ m: UInt32) -> BigUInt {
		var out: [UInt32] = []
		var carry: UInt64 = 0
		for l in limbs {
			let p = UInt64(l) * UInt64(m) + carry
			out.append(UInt32(truncatingIfNeeded: p))
			carry = p >> 32
		}
		if carry > 0 { out.append(UInt32(carry)) }
		return BigUInt(limbs: out)
	}

	func addSmall(_ a: UInt32) -> BigUInt {
		var out = limbs
		var carry = UInt64(a)
		var i = 0
		while carry > 0 {
			if i == out.count { out.append(0) }
			let s = UInt64(out[i]) + carry
			out[i] = UInt32(truncatingIfNeeded: s)
			carry = s >> 32
			i += 1
		}
		return BigUInt(limbs: out)
	}

	public static func < (lhs: BigUInt, rhs: BigUInt) -> Bool {
		if lhs.limbs.count != rhs.limbs.count { return lhs.limbs.count < rhs.limbs.count }
		for i in stride(from: lhs.limbs.count - 1, through: 0, by: -1) where lhs.limbs[i] != rhs.limbs[i] {
			return lhs.limbs[i] < rhs.limbs[i]
		}
		return false
	}

	static func - (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
		var out = lhs.limbs
		var borrow: Int64 = 0
		for i in 0..<out.count {
			var d = Int64(out[i]) - borrow - (i < rhs.limbs.count ? Int64(rhs.limbs[i]) : 0)
			borrow = 0
			if d < 0 { d += 1 << 32; borrow = 1 }
			out[i] = UInt32(d)
		}
		return BigUInt(limbs: out)
	}

	static func * (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
		if lhs.isZero || rhs.isZero { return BigUInt(limbs: []) }
		var out = [UInt32](repeating: 0, count: lhs.limbs.count + rhs.limbs.count)
		for i in 0..<lhs.limbs.count {
			var carry: UInt64 = 0
			let a = UInt64(lhs.limbs[i])
			for j in 0..<rhs.limbs.count {
				let t = a * UInt64(rhs.limbs[j]) + UInt64(out[i + j]) + carry
				out[i + j] = UInt32(truncatingIfNeeded: t)
				carry = t >> 32
			}
			out[i + rhs.limbs.count] = UInt32(carry)
		}
		return BigUInt(limbs: out)
	}

	private func shiftedLeftOne(orBit: Bool) -> BigUInt {
		var out: [UInt32] = []
		var carry: UInt32 = orBit ? 1 : 0
		for l in limbs {
			out.append(l << 1 | carry)
			carry = l >> 31
		}
		if carry != 0 { out.append(carry) }
		return BigUInt(limbs: out)
	}

	static func % (lhs: BigUInt, m: BigUInt) -> BigUInt {
		precondition(!m.isZero)
		var r = BigUInt(limbs: [])
		for i in stride(from: lhs.bitWidth - 1, through: 0, by: -1) {
			r = r.shiftedLeftOne(orBit: lhs.bit(i))
			if !(r < m) { r = r - m }
		}
		return r
	}

	public func power(_ e: BigUInt, modulus m: BigUInt) -> BigUInt {
		var result = BigUInt(1) % m
		let base = self % m
		for i in stride(from: e.bitWidth - 1, through: 0, by: -1) {
			result = (result * result) % m
			if e.bit(i) { result = (result * base) % m }
		}
		return result
	}

	/// Java `BigInteger.toByteArray()` for a non-negative value: minimal
	/// big-endian two's complement, so a leading 0x00 appears when the top bit
	/// of the magnitude is set.
	public func javaByteArray() -> [UInt8] {
		var bytes: [UInt8] = []
		for l in limbs.reversed() {
			bytes += [UInt8(truncatingIfNeeded: l >> 24), UInt8(truncatingIfNeeded: l >> 16),
			          UInt8(truncatingIfNeeded: l >> 8), UInt8(truncatingIfNeeded: l)]
		}
		while let f = bytes.first, f == 0 { bytes.removeFirst() }
		if bytes.isEmpty || bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
		return bytes
	}
}

/// rt4 `Buffer.rsaenc`.
public struct RsaKey {
	public let exponent: BigUInt
	public let modulus: BigUInt

	public init(exponent: BigUInt, modulus: BigUInt) {
		self.exponent = exponent
		self.modulus = modulus
	}

	/// The key compiled into 2009scape's rt4 client (`GlobalConfig`).
	public static let scape2009 = RsaKey(
		exponent: BigUInt(65537),
		modulus: BigUInt(decimal: "96982303379631821170939875058071478695026608406924780574168393250855797534862289546229721580153879336741968220328805101128831071152160922518190059946555203865621183480223212969502122536662721687753974815205744569357388338433981424032996046420057284324856368815997832596174397728134370577184183004453899764051")!
	)

	/// Encrypts `plaintext` (interpreted as a signed big-endian Java
	/// BigInteger; callers start the block with a small positive byte) and
	/// returns `[len] + ciphertext`, exactly what rsaenc leaves in the buffer.
	public func encryptBlock(_ plaintext: [UInt8]) -> [UInt8] {
		let c = BigUInt(bigEndian: plaintext).power(exponent, modulus: modulus).javaByteArray()
		return [UInt8(truncatingIfNeeded: c.count)] + c
	}
}
