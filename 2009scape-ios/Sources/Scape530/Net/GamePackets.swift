/// One framed server -> client game packet.
public struct GamePacket: Equatable {
	public let opcode: Int
	public let payload: [UInt8]
}

/// Incremental framer for the in-game stream, mirroring rt4
/// `Protocol.readPacketInternal`: opcode (ISAAC-adjusted), then either a
/// fixed length from `ServerProt.lengths` or a 1/2-byte length prefix.
public struct GamePacketFramer {
	public var cipher: IsaacRandom
	private var buffer: [UInt8] = []
	private var opcode = -1
	private var length = -1

	public struct UnknownOpcode: Error, CustomStringConvertible {
		public let opcode: Int
		public var description: String { "unknown server opcode \(opcode)" }
	}

	public init(cipher: IsaacRandom) {
		self.cipher = cipher
	}

	/// Starts mid-stream when the login reply already supplied the first header.
	public mutating func expect(opcode: Int, length: Int) {
		self.opcode = opcode
		self.length = length
	}

	public mutating func feed<C: Collection>(_ bytes: C) throws -> [GamePacket] where C.Element == UInt8 {
		buffer.append(contentsOf: bytes)
		var out: [GamePacket] = []
		var pos = 0
		while true {
			if opcode == -1 {
				guard pos < buffer.count else { break }
				opcode = (Int(buffer[pos]) - cipher.nextKey()) & 0xFF
				pos += 1
				length = ServerProt.lengths[opcode]
			}
			if length == -1 {
				guard pos < buffer.count else { break }
				length = Int(buffer[pos])
				pos += 1
			} else if length == -2 {
				guard pos + 1 < buffer.count else { break }
				length = Int(buffer[pos]) << 8 | Int(buffer[pos + 1])
				pos += 2
			}
			guard pos + length <= buffer.count else { break }
			out.append(GamePacket(opcode: opcode, payload: Array(buffer[pos..<pos + length])))
			pos += length
			opcode = -1
			length = -1
		}
		buffer.removeFirst(pos)
		return out
	}
}

/// REBUILD_NORMAL (opcode 162): static map region change. Port of the
/// non-dynamic branch of rt4 `Protocol.readRebuildPacket`.
public struct RebuildNormal: Equatable {
	/// Player position within the 104x104 scene.
	public var localX: Int
	public var localZ: Int
	/// Central zone (8x8 tile chunk) coordinates.
	public var zoneX: Int
	public var zoneZ: Int
	public var plane: Int
	/// XTEA keys for each map square's `l` (locations) group, in region order.
	public var xteaKeys: [[Int32]]

	public struct Region: Equatable {
		public let x: Int
		public let z: Int
		public var id: Int { x << 8 | z }
		/// JS5 archive 5 group names.
		public var mapGroupName: String { "m\(x)_\(z)" }
		public var locGroupName: String { "l\(x)_\(z)" }
	}

	public init(payload: [UInt8]) throws {
		var p = Packet(payload)
		localX = try p.g2add()
		let keyCount = (payload.count - p.offset) / 16
		var keys: [[Int32]] = []
		for _ in 0..<keyCount {
			keys.append([try p.mg4(), try p.mg4(), try p.mg4(), try p.mg4()])
		}
		xteaKeys = keys
		plane = try p.g1sub()
		zoneX = try p.g2()
		zoneZ = try p.g2add()
		localZ = try p.g2add()
	}

	/// The map squares rt4 loads around the central zone (same order as `xteaKeys`).
	public var regions: [Region] {
		var out: [Region] = []
		for x in ((zoneX - 6) / 8)...((zoneX + 6) / 8) {
			for z in ((zoneZ - 6) / 8)...((zoneZ + 6) / 8) {
				out.append(Region(x: x, z: z))
			}
		}
		return out
	}

	/// World tile of the player (rt4 Camera.originX/Z + local position).
	public var worldX: Int { (zoneX - 6) * 8 + localX }
	public var worldZ: Int { (zoneZ - 6) * 8 + localZ }
}
