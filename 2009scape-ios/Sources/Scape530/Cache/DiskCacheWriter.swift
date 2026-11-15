import Foundation

/// Writes groups into the standard `main_file_cache.dat2` + `.idxN` layout
/// (rt4 `Cache.write`), so `DiskCache` and other tools can read the result.
/// New data is always appended as fresh sectors; old sectors of a rewritten
/// group are simply orphaned, which is what rt4 does when a group grows.
public final class DiskCacheWriter {
	public let directory: URL
	private let dat: FileHandle
	private var sectors: Int
	private var indexes: [Int: FileHandle] = [:]

	public init(directory: URL) throws {
		self.directory = directory
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let datURL = directory.appendingPathComponent("main_file_cache.dat2")
		if !FileManager.default.fileExists(atPath: datURL.path) {
			// Sector 0 is reserved (a 0 pointer means "none").
			FileManager.default.createFile(atPath: datURL.path, contents: Data(count: DiskCache.sectorSize))
		}
		dat = try FileHandle(forUpdating: datURL)
		let size = Int(try dat.seekToEnd())
		sectors = max(1, (size + DiskCache.sectorSize - 1) / DiskCache.sectorSize)
	}

	deinit {
		try? dat.close()
		for h in indexes.values { try? h.close() }
	}

	func indexHandle(_ archive: Int) throws -> FileHandle {
		if let h = indexes[archive] { return h }
		let url = directory.appendingPathComponent("main_file_cache.idx\(archive)")
		if !FileManager.default.fileExists(atPath: url.path) {
			FileManager.default.createFile(atPath: url.path, contents: Data())
		}
		let h = try FileHandle(forUpdating: url)
		indexes[archive] = h
		return h
	}

	/// Stores `data` (a container with its 2-byte version trailer) for a group.
	public func write(archive: Int, group: Int, data: [UInt8]) throws {
		let extended = group > 0xFFFF
		let header = extended ? 10 : 8
		let payload = DiskCache.sectorSize - header
		let first = sectors
		let count = max(1, (data.count + payload - 1) / payload)
		var out = [UInt8]()
		out.reserveCapacity(count * DiskCache.sectorSize)
		for chunk in 0..<count {
			let sector = first + chunk
			let next = chunk == count - 1 ? 0 : sector + 1
			var h = Packet(capacity: header)
			if extended { h.p4(group) } else { h.p2(group) }
			h.p2(chunk)
			h.p3(next)
			h.p1(archive)
			out += h.written
			let start = chunk * payload
			let end = min(start + payload, data.count)
			out += data[start..<end]
			out += [UInt8](repeating: 0, count: payload - (end - start))
		}
		try dat.seek(toOffset: UInt64(first * DiskCache.sectorSize))
		try dat.write(contentsOf: Data(out))
		sectors += count

		var e = Packet(capacity: 6)
		e.p3(data.count)
		e.p3(first)
		let idx = try indexHandle(archive)
		let end = Int(try idx.seekToEnd())
		if end < group * 6 {
			try idx.write(contentsOf: Data(count: group * 6 - end))
		}
		try idx.seek(toOffset: UInt64(group * 6))
		try idx.write(contentsOf: Data(e.written))
	}

	public func synchronize() throws {
		try dat.synchronize()
		for h in indexes.values { try h.synchronize() }
	}
}
