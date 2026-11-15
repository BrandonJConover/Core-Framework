/// JS5 (on-demand cache) wire protocol, ported from rt4 `client.js5Connect`
/// and `Js5NetQueue`.
public enum Js5Protocol {
	public static let revision = 530

	/// First bytes on a fresh JS5 socket: [15][revision:4]. Server answers one
	/// status byte (0 = OK, 6 = out of date, ...).
	public static func handshake(revision: Int = revision) -> [UInt8] {
		var p = Packet(capacity: 5)
		p.p1(15)
		p.p4(revision)
		return p.written
	}

	/// What `Js5NetQueue.start` sends right after the handshake succeeds:
	/// [6][0,0,3] then the logged-in/out state ([2] logged in, [3] logged out).
	public static func sessionStart(loggedIn: Bool) -> [UInt8] {
		[6, 0, 0, 3, loggedIn ? 2 : 3, 0, 0, 0]
	}

	/// [urgent ? 1 : 0][archive:1][group:2]
	public static func request(archive: Int, group: Int, urgent: Bool = true) -> [UInt8] {
		[urgent ? 1 : 0, UInt8(truncatingIfNeeded: archive), UInt8(truncatingIfNeeded: group >> 8), UInt8(truncatingIfNeeded: group)]
	}

	public struct Response: Equatable {
		public let archive: Int
		public let group: Int
		public let prefetch: Bool
		/// The full container (compression byte + lengths + data), no version trailer.
		public let container: [UInt8]
	}

	public struct ProtocolError: Error, CustomStringConvertible {
		public let description: String
	}

	/// Incremental response decoder. Responses arrive as an 8-byte header
	/// [archive:1][group:2][compression|0x80 prefetch:1][length:4] followed by
	/// the container body, chunked into 512-byte blocks where every block after
	/// the first starts with a 0xFF marker byte.
	public struct ResponseParser {
		private var header: [UInt8] = []
		private var current: (archive: Int, group: Int, prefetch: Bool, buf: [UInt8], total: Int)?
		private var blockPosition = 0
		public var xorKey: UInt8 = 0

		public init() {}

		public mutating func feed<C: Collection>(_ bytes: C) throws -> [Response] where C.Element == UInt8 {
			var out: [Response] = []
			for raw in bytes {
				let b = raw ^ xorKey
				if var c = current {
					if blockPosition == 512 {
						guard b == 0xFF else { throw ProtocolError(description: "missing 0xFF block marker") }
						blockPosition = 1
						continue
					}
					c.buf.append(b)
					blockPosition += 1
					if c.buf.count == c.total {
						out.append(Response(archive: c.archive, group: c.group, prefetch: c.prefetch, container: c.buf))
						current = nil
					} else {
						current = c
					}
					continue
				}
				header.append(b)
				if header.count == 8 {
					let archive = Int(header[0])
					let group = Int(header[1]) << 8 | Int(header[2])
					let compression = Int(header[3] & 0x7F)
					let prefetch = header[3] & 0x80 != 0
					let len = Int(header[4]) << 24 | Int(header[5]) << 16 | Int(header[6]) << 8 | Int(header[7])
					let total = len + (compression == 0 ? 5 : 9)
					var buf = [UInt8]()
					buf.reserveCapacity(total)
					buf.append(header[3] & 0x7F)
					buf.append(contentsOf: header[4..<8])
					header.removeAll(keepingCapacity: true)
					blockPosition = 8
					if buf.count == total {
						out.append(Response(archive: archive, group: group, prefetch: prefetch, container: buf))
					} else {
						current = (archive, group, prefetch, buf, total)
					}
				}
			}
			return out
		}
	}
}
