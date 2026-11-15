/// A JS5 container: `[compression:1][length:4]([uncompressedLength:4])data`,
/// optionally followed by a 2-byte group version trailer (ignored here).
/// Port of rt4 `Js5Compression.uncompress`.
public enum Js5Container {
	public enum Compression: Int {
		case none = 0
		case bzip2 = 1
		case gzip = 2
	}

	public struct Failure: Error, CustomStringConvertible {
		public let description: String
		init(_ d: String) { description = d }
	}

	public static func decompress(_ data: [UInt8]) throws -> [UInt8] {
		var p = Packet(data)
		let type = try p.g1()
		let len = Int(try p.g4())
		guard len >= 0 else { throw Failure("negative container length") }
		guard let compression = Compression(rawValue: type) else { throw Failure("unknown compression \(type)") }
		if compression == .none {
			return try p.gdata(len)
		}
		let ulen = Int(try p.g4())
		guard ulen >= 0 else { throw Failure("negative uncompressed length") }
		guard 9 + len <= data.count else { throw Failure("truncated container") }
		let body = data[9..<(9 + len)]
		switch compression {
		case .bzip2: return try Bzip2.decompress(body, expectedSize: ulen)
		case .gzip: return try Inflate.gunzipJs5(body, expectedSize: ulen)
		case .none: fatalError("unreachable")
		}
	}

	/// Container bytes without any version trailer (what the CRC covers).
	public static func stripVersion(_ data: [UInt8]) -> [UInt8] {
		guard data.count >= 5 else { return data }
		let type = Int(data[0])
		let len = Int(data[1]) << 24 | Int(data[2]) << 16 | Int(data[3]) << 8 | Int(data[4])
		let total = len + (type == 0 ? 5 : 9)
		return total <= data.count ? Array(data[0..<total]) : data
	}
}
