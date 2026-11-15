/// Decoded JS5 reference table (archive 255, group = archive id).
/// Port of rt4 `Js5Index`.
public struct Js5Index {
	public let checksum: Int32
	public let protocolVersion: Int
	public let version: Int32
	public let groupIds: [Int]
	public let capacity: Int
	public private(set) var groupNameHashes: [Int32]?
	public private(set) var groupChecksums: [Int32]
	public private(set) var groupVersions: [Int32]
	public private(set) var groupSizes: [Int]
	public private(set) var groupCapacities: [Int]
	/// nil for a group whose file ids are exactly 0..<size.
	public private(set) var fileIds: [[Int]?]
	public private(set) var fileNameHashes: [[Int32]]?

	public var size: Int { groupIds.count }

	/// `raw` is the packed container as served/stored (CRC computed over it).
	public init(container raw: [UInt8], expectedChecksum: Int32? = nil) throws {
		checksum = Crc32.checksum(raw)
		if let e = expectedChecksum, e != checksum {
			throw Js5Container.Failure("index checksum mismatch \(checksum) != \(e)")
		}
		var p = Packet(try Js5Container.decompress(raw))
		protocolVersion = try p.g1()
		guard protocolVersion == 5 || protocolVersion == 6 else {
			throw Js5Container.Failure("unsupported index protocol \(protocolVersion)")
		}
		version = protocolVersion >= 6 ? try p.g4() : 0
		let named = try p.g1() != 0
		let size = try p.g2()
		var ids = [Int](repeating: 0, count: size)
		var acc = 0
		var maxId = -1
		for i in 0..<size {
			acc += try p.g2()
			ids[i] = acc
			maxId = max(maxId, acc)
		}
		groupIds = ids
		capacity = maxId + 1
		groupChecksums = [Int32](repeating: 0, count: capacity)
		groupVersions = [Int32](repeating: 0, count: capacity)
		groupSizes = [Int](repeating: 0, count: capacity)
		groupCapacities = [Int](repeating: 0, count: capacity)
		fileIds = [[Int]?](repeating: nil, count: capacity)

		if named {
			var h = [Int32](repeating: -1, count: capacity)
			for g in ids { h[g] = try p.g4() }
			groupNameHashes = h
		}
		for g in ids { groupChecksums[g] = try p.g4() }
		for g in ids { groupVersions[g] = try p.g4() }
		for g in ids { groupSizes[g] = try p.g2() }
		for g in ids {
			let n = groupSizes[g]
			var files = [Int](repeating: 0, count: n)
			var a = 0
			var m = -1
			for f in 0..<n {
				a += try p.g2()
				files[f] = a
				m = max(m, a)
			}
			groupCapacities[g] = m + 1
			fileIds[g] = (m + 1 == n) ? nil : files
		}
		if named {
			var all = [[Int32]](repeating: [], count: capacity)
			for g in ids {
				var hashes = [Int32](repeating: -1, count: groupCapacities[g])
				for f in 0..<groupSizes[g] {
					let id = fileIds[g]?[f] ?? f
					hashes[id] = try p.g4()
				}
				all[g] = hashes
			}
			fileNameHashes = all
		}
	}

	public func isValid(group: Int) -> Bool {
		group >= 0 && group < capacity && groupSizes[group] > 0
	}

	/// rt4 `Js5.hashJagString`-style name lookup (Java `String.hashCode` over lowercase cp1252).
	public static func nameHash(_ name: String) -> Int32 {
		var h: Int32 = 0
		for b in Cp1252.encode(name.lowercased()) {
			h = h &* 31 &+ Int32(b)
		}
		return h
	}

	public func group(named name: String) -> Int? {
		guard let hashes = groupNameHashes else { return nil }
		let h = Js5Index.nameHash(name)
		return groupIds.first { hashes[$0] == h }
	}

	public func file(named name: String, inGroup g: Int) -> Int? {
		guard let hashes = fileNameHashes?[g] else { return nil }
		let h = Js5Index.nameHash(name)
		return hashes.firstIndex(of: h)
	}
}

/// Splits an uncompressed group into its files. Port of rt4 `Js5.unpackGroup`.
public enum Js5Group {
	public static func unpack(_ uncompressed: [UInt8], index: Js5Index, group: Int) throws -> [Int: [UInt8]] {
		let n = index.groupSizes[group]
		let ids = index.fileIds[group]
		if n <= 1 {
			return [ids?[0] ?? 0: uncompressed]
		}
		guard let last = uncompressed.last else { throw Js5Container.Failure("empty group") }
		let stripes = Int(last)
		let tableStart = uncompressed.count - 1 - n * stripes * 4
		guard tableStart >= 0 else { throw Js5Container.Failure("bad stripe table") }
		var p = Packet(uncompressed, offset: tableStart)
		var lens = [Int](repeating: 0, count: n)
		for _ in 0..<stripes {
			var len = 0
			for f in 0..<n {
				len += Int(try p.g4())
				lens[f] += len
			}
		}
		var files = lens.map { [UInt8]().reserved($0) }
		p.offset = tableStart
		var pos = 0
		for _ in 0..<stripes {
			var len = 0
			for f in 0..<n {
				len += Int(try p.g4())
				guard len >= 0, pos + len <= tableStart else { throw Js5Container.Failure("stripe overrun") }
				files[f].append(contentsOf: uncompressed[pos..<pos + len])
				pos += len
			}
		}
		var out: [Int: [UInt8]] = [:]
		for f in 0..<n { out[ids?[f] ?? f] = files[f] }
		return out
	}
}

extension Array {
	func reserved(_ n: Int) -> Array {
		var a = self
		a.reserveCapacity(n)
		return a
	}
}
