/// rt4 `Buffer.tinydec`: XTEA-decrypts a JS5 container in place, skipping the
/// 5-byte container header. Used for map (`l` / location) groups whose keys
/// arrive in the REBUILD_NORMAL packet.
public enum Xtea {
	public static func decryptContainer(_ data: inout [UInt8], key: [Int32]) {
		precondition(key.count == 4)
		let k = key.map { UInt32(bitPattern: $0) }
		let blocks = (data.count - 5) / 8
		var off = 5
		for _ in 0..<blocks {
			var v0 = readU32(data, off)
			var v1 = readU32(data, off + 4)
			var sum: UInt32 = 0xC6EF_3720
			for _ in 0..<32 {
				v1 &-= (k[Int((sum >> 11) & 3)] &+ sum) ^ (v0 &+ ((v0 >> 5) ^ (v0 << 4)))
				sum &-= 0x9E37_79B9
				v0 &-= (((v1 >> 5) ^ (v1 << 4)) &+ v1) ^ (k[Int(sum & 3)] &+ sum)
			}
			writeU32(&data, off, v0)
			writeU32(&data, off + 4, v1)
			off += 8
		}
	}

	@inline(__always)
	static func readU32(_ d: [UInt8], _ i: Int) -> UInt32 {
		UInt32(d[i]) << 24 | UInt32(d[i + 1]) << 16 | UInt32(d[i + 2]) << 8 | UInt32(d[i + 3])
	}

	@inline(__always)
	static func writeU32(_ d: inout [UInt8], _ i: Int, _ v: UInt32) {
		d[i] = UInt8(truncatingIfNeeded: v >> 24)
		d[i + 1] = UInt8(truncatingIfNeeded: v >> 16)
		d[i + 2] = UInt8(truncatingIfNeeded: v >> 8)
		d[i + 3] = UInt8(truncatingIfNeeded: v)
	}
}
