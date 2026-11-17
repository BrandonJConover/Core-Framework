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
	/// REBUILD_REGION only: the 4 x 13 x 13 chunk template, indexed `(level * 13 + x) * 13 + z`. Each entry is -1 (no
	/// chunk) or `rotation << 1 | chunkZ << 3 | chunkX << 14 | level << 24` of the 8x8 tile chunk copied there.
	public var chunks: [Int]?

	/// True for a dynamic (instanced) region.
	public var isDynamic: Bool { chunks != nil }

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

	/// REBUILD_REGION (opcode 214): the dynamic branch of rt4 `Protocol.readRebuildPacket`.
	public init(dynamicPayload payload: [UInt8]) throws {
		var p = Packet(payload)
		localX = try p.ig2add()
		zoneX = try p.ig2add()
		plane = try p.g1sub()
		localZ = try p.ig2add()
		// rt4 `accessBits`: 1 flag bit per chunk, then 26 bits when it is set.
		var bit = p.offset * 8
		func bits(_ n: Int) throws -> Int {
			var v = 0
			for _ in 0..<n {
				guard bit >> 3 < payload.count else { throw PacketUnderflow(offset: bit >> 3, wanted: 1, size: payload.count) }
				v = v << 1 | Int(payload[bit >> 3] >> (7 - UInt8(bit & 7))) & 1
				bit += 1
			}
			return v
		}
		var table = [Int](repeating: -1, count: 4 * 13 * 13)
		for level in 0..<4 {
			for x in 0..<13 {
				for z in 0..<13 {
					if try bits(1) == 1 { table[(level * 13 + x) * 13 + z] = try bits(26) }
				}
			}
		}
		p.offset = (bit + 7) >> 3
		let keyCount = (payload.count - p.offset) / 16
		var keys: [[Int32]] = []
		for _ in 0..<keyCount { keys.append([try p.mg4(), try p.mg4(), try p.mg4(), try p.mg4()]) }
		xteaKeys = keys
		zoneZ = try p.g2()
		chunks = table
	}

	/// The map squares rt4 loads around the central zone (same order as `xteaKeys`). For a dynamic region these are the
	/// squares the chunks are copied from, in order of first use (level, then x, then z).
	public var regions: [Region] {
		var out: [Region] = []
		if let table = chunks {
			var seen = Set<Int>()
			for packed in table where packed != -1 {
				let region = Region(x: (packed >> 14 & 0x3FF) / 8, z: (packed >> 3 & 0x7FF) / 8)
				if seen.insert(region.id).inserted { out.append(region) }
			}
			return out
		}
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
