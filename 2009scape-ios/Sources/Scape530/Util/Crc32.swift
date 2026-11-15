/// CRC-32 (IEEE, reflected) as used by rt4 `Buffer.crc32` for JS5 checksums.
public enum Crc32 {
	static let table: [UInt32] = (0..<256).map { n -> UInt32 in
		var c = UInt32(n)
		for _ in 0..<8 {
			c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
		}
		return c
	}

	public static func checksum<C: Collection>(_ bytes: C) -> Int32 where C.Element == UInt8 {
		var crc: UInt32 = 0xFFFF_FFFF
		for b in bytes {
			crc = (crc >> 8) ^ table[Int((crc ^ UInt32(b)) & 0xFF)]
		}
		return Int32(bitPattern: ~crc)
	}
}
