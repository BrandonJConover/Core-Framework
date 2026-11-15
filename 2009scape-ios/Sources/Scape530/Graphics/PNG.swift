/// Minimal PNG writer (RGB, stored deflate blocks) so tests and tools can
/// dump a `Raster` without platform image APIs.
public enum PNG {
	public static func encode(_ r: Raster) -> [UInt8] {
		var raw = [UInt8]()
		raw.reserveCapacity((r.width * 3 + 1) * r.height)
		for y in 0..<r.height {
			raw.append(0)
			for x in 0..<r.width {
				let c = r.pixels[y * r.width + x]
				raw.append(UInt8(truncatingIfNeeded: c >> 16))
				raw.append(UInt8(truncatingIfNeeded: c >> 8))
				raw.append(UInt8(truncatingIfNeeded: c))
			}
		}
		var z: [UInt8] = [0x78, 0x01]
		var i = 0
		repeat {
			let n = min(65535, raw.count - i)
			let last: UInt8 = i + n >= raw.count ? 1 : 0
			z.append(last)
			z += [UInt8(n & 0xFF), UInt8(n >> 8), UInt8(~n & 0xFF), UInt8((~n >> 8) & 0xFF)]
			z += raw[i..<i + n]
			i += n
		} while i < raw.count
		var a: UInt32 = 1, b: UInt32 = 0
		for byte in raw {
			a = (a + UInt32(byte)) % 65521
			b = (b + a) % 65521
		}
		z += be32(b << 16 | a)

		var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
		out += chunk("IHDR", be32(UInt32(r.width)) + be32(UInt32(r.height)) + [8, 2, 0, 0, 0])
		out += chunk("IDAT", z)
		out += chunk("IEND", [])
		return out
	}

	static func be32(_ v: UInt32) -> [UInt8] {
		[UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
	}

	static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
		let t = Array(type.utf8)
		return be32(UInt32(data.count)) + t + data + be32(UInt32(bitPattern: Crc32.checksum(t + data)))
	}
}
