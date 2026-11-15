import Foundation

/// Error thrown when a read runs past the end of a `Packet`.
public struct PacketUnderflow: Error, CustomStringConvertible {
	public let offset: Int
	public let wanted: Int
	public let size: Int
	public var description: String { "packet underflow: wanted \(wanted) at \(offset) of \(size)" }
}

/// Port of rt4 `Buffer`: a big-endian byte cursor used for both packets and
/// cache data. Method names follow rt4 (g1/g2/p1/p2...) so ports from
/// `reference/rt4-client` stay line-for-line comparable.
///
/// Reads are bounds-checked and throw instead of trapping, because the data
/// comes from the network and from cache files we do not control.
public struct Packet {
	public var data: [UInt8]
	public var offset: Int

	public init(_ data: [UInt8], offset: Int = 0) {
		self.data = data
		self.offset = offset
	}

	public init(capacity: Int) {
		self.data = []
		self.data.reserveCapacity(capacity)
		self.offset = 0
	}

	public var remaining: Int { data.count - offset }

	@inline(__always)
	private mutating func take(_ n: Int) throws -> Int {
		guard n >= 0, offset + n <= data.count else {
			throw PacketUnderflow(offset: offset, wanted: n, size: data.count)
		}
		let start = offset
		offset += n
		return start
	}

	// MARK: reads

	public mutating func g1() throws -> Int { Int(data[try take(1)]) }
	public mutating func g1b() throws -> Int { Int(Int8(bitPattern: data[try take(1)])) }
	public mutating func g1add() throws -> Int { Int(data[try take(1)] &- 128) }
	public mutating func g1neg() throws -> Int { Int(0 &- data[try take(1)]) }
	public mutating func g1sub() throws -> Int { Int(128 &- data[try take(1)]) }

	public mutating func g2() throws -> Int {
		let i = try take(2)
		return Int(data[i]) << 8 | Int(data[i + 1])
	}

	public mutating func g2b() throws -> Int {
		let v = try g2()
		return v > 32767 ? v - 0x10000 : v
	}

	public mutating func g2add() throws -> Int {
		let i = try take(2)
		return Int(data[i]) << 8 | Int(data[i + 1] &- 128)
	}

	public mutating func ig2() throws -> Int {
		let i = try take(2)
		return Int(data[i + 1]) << 8 | Int(data[i])
	}

	public mutating func ig2add() throws -> Int {
		let i = try take(2)
		return Int(data[i + 1]) << 8 | Int(data[i] &- 128)
	}

	public mutating func g3() throws -> Int {
		let i = try take(3)
		return Int(data[i]) << 16 | Int(data[i + 1]) << 8 | Int(data[i + 2])
	}

	/// Signed 32-bit read, matching Java `int`.
	public mutating func g4() throws -> Int32 {
		let i = try take(4)
		let u = UInt32(data[i]) << 24 | UInt32(data[i + 1]) << 16 | UInt32(data[i + 2]) << 8 | UInt32(data[i + 3])
		return Int32(bitPattern: u)
	}

	public mutating func ig4() throws -> Int32 {
		let i = try take(4)
		let u = UInt32(data[i + 3]) << 24 | UInt32(data[i + 2]) << 16 | UInt32(data[i + 1]) << 8 | UInt32(data[i])
		return Int32(bitPattern: u)
	}

	public mutating func mg4() throws -> Int32 {
		let i = try take(4)
		let u = UInt32(data[i + 1]) << 24 | UInt32(data[i]) << 16 | UInt32(data[i + 3]) << 8 | UInt32(data[i + 2])
		return Int32(bitPattern: u)
	}

	public mutating func img4() throws -> Int32 {
		let i = try take(4)
		let u = UInt32(data[i + 2]) << 24 | UInt32(data[i + 3]) << 16 | UInt32(data[i]) << 8 | UInt32(data[i + 1])
		return Int32(bitPattern: u)
	}

	public mutating func g8() throws -> Int64 {
		let hi = UInt64(UInt32(bitPattern: try g4()))
		let lo = UInt64(UInt32(bitPattern: try g4()))
		return Int64(bitPattern: hi << 32 | lo)
	}

	/// rt4 `gsmart`: signed smart, range -16384...16383.
	public mutating func gsmart() throws -> Int {
		guard offset < data.count else { throw PacketUnderflow(offset: offset, wanted: 1, size: data.count) }
		return data[offset] < 128 ? try g1() - 64 : try g2() - 0xC000
	}

	/// rt4 `gsmarts`: unsigned smart, range 0...32767.
	public mutating func gsmarts() throws -> Int {
		guard offset < data.count else { throw PacketUnderflow(offset: offset, wanted: 1, size: data.count) }
		return data[offset] >= 128 ? try g2() - 0x8000 : try g1()
	}

	public mutating func gVarSmart() throws -> Int {
		var value = try gsmarts()
		var acc = 0
		while value == 32767 {
			value = try gsmarts()
			acc += 32767
		}
		return acc + value
	}

	/// NUL-terminated cp1252 string (rt4 `gjstr`).
	public mutating func gjstr() throws -> String {
		let start = offset
		guard let end = data[start...].firstIndex(of: 0) else {
			throw PacketUnderflow(offset: offset, wanted: 1, size: data.count)
		}
		offset = end + 1
		return Cp1252.decode(data[start..<end])
	}

	/// rt4 `gjstr2`: version byte (must be 0) then a NUL-terminated string.
	public mutating func gjstr2() throws -> String {
		let version = try g1()
		guard version == 0 else { throw PacketUnderflow(offset: offset, wanted: 0, size: data.count) }
		return try gjstr()
	}

	public mutating func gdata(_ n: Int) throws -> [UInt8] {
		let i = try take(n)
		return Array(data[i..<i + n])
	}

	// MARK: writes (always append at `offset`, growing as needed)

	@inline(__always)
	private mutating func put(_ b: UInt8) {
		if offset == data.count {
			data.append(b)
		} else {
			data[offset] = b
		}
		offset += 1
	}

	public mutating func p1(_ v: Int) { put(UInt8(truncatingIfNeeded: v)) }
	public mutating func p1add(_ v: Int) { put(UInt8(truncatingIfNeeded: v + 128)) }
	public mutating func p1sub(_ v: Int) { put(UInt8(truncatingIfNeeded: 128 - v)) }
	public mutating func p1neg(_ v: Int) { put(UInt8(truncatingIfNeeded: -v)) }

	public mutating func p2(_ v: Int) {
		put(UInt8(truncatingIfNeeded: v >> 8))
		put(UInt8(truncatingIfNeeded: v))
	}

	public mutating func p2add(_ v: Int) {
		put(UInt8(truncatingIfNeeded: v >> 8))
		put(UInt8(truncatingIfNeeded: v + 128))
	}

	public mutating func ip2(_ v: Int) {
		put(UInt8(truncatingIfNeeded: v))
		put(UInt8(truncatingIfNeeded: v >> 8))
	}

	public mutating func ip2add(_ v: Int) {
		put(UInt8(truncatingIfNeeded: v + 128))
		put(UInt8(truncatingIfNeeded: v >> 8))
	}

	public mutating func p3(_ v: Int) {
		put(UInt8(truncatingIfNeeded: v >> 16))
		put(UInt8(truncatingIfNeeded: v >> 8))
		put(UInt8(truncatingIfNeeded: v))
	}

	public mutating func p4(_ v: Int32) {
		let u = UInt32(bitPattern: v)
		put(UInt8(truncatingIfNeeded: u >> 24))
		put(UInt8(truncatingIfNeeded: u >> 16))
		put(UInt8(truncatingIfNeeded: u >> 8))
		put(UInt8(truncatingIfNeeded: u))
	}

	public mutating func p4(_ v: Int) { p4(Int32(truncatingIfNeeded: v)) }

	public mutating func ip4(_ v: Int) {
		put(UInt8(truncatingIfNeeded: v))
		put(UInt8(truncatingIfNeeded: v >> 8))
		put(UInt8(truncatingIfNeeded: v >> 16))
		put(UInt8(truncatingIfNeeded: v >> 24))
	}

	public mutating func p8(_ v: Int64) {
		p4(Int32(truncatingIfNeeded: v >> 32))
		p4(Int32(truncatingIfNeeded: v))
	}

	public mutating func pjstr(_ s: String) {
		pdata(Cp1252.encode(s))
		put(0)
	}

	public mutating func pdata<C: Collection>(_ bytes: C) where C.Element == UInt8 {
		for b in bytes { put(b) }
	}

	/// rt4 `psize1`: back-patch a 1-byte length `length` bytes before `offset`.
	public mutating func psize1(_ length: Int) {
		data[offset - length - 1] = UInt8(truncatingIfNeeded: length)
	}

	/// rt4 `psize2`-style back-patch for var-short packets.
	public mutating func psize2(_ length: Int) {
		data[offset - length - 2] = UInt8(truncatingIfNeeded: length >> 8)
		data[offset - length - 1] = UInt8(truncatingIfNeeded: length)
	}

	/// The bytes written so far (`data[0..<offset]`).
	public var written: [UInt8] { Array(data[0..<offset]) }
}

/// Windows-1252 as used by Jagex strings (rt4 `JagString`).
public enum Cp1252 {
	// 0x80...0x9F map to these code points; 0 means "undefined" (rendered as '?').
	static let high: [UInt16] = [
		0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
		0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017D, 0,
		0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
		0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178,
	]

	public static func decode<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
		var scalars = String.UnicodeScalarView()
		for b in bytes {
			if b >= 0x80 && b < 0xA0 {
				let cp = high[Int(b) - 0x80]
				scalars.append(Unicode.Scalar(cp == 0 ? 0x3F : cp)!)
			} else {
				scalars.append(Unicode.Scalar(b))
			}
		}
		return String(scalars)
	}

	public static func encode(_ s: String) -> [UInt8] {
		s.unicodeScalars.map { u in
			let v = u.value
			if v < 0x80 || (v >= 0xA0 && v <= 0xFF) { return UInt8(v) }
			if let i = high.firstIndex(of: UInt16(truncatingIfNeeded: v)), v <= 0xFFFF, high[i] != 0 {
				return UInt8(0x80 + i)
			}
			return 0x3F
		}
	}
}
