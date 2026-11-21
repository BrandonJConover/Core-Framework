import Foundation

/// Brings an on-disk cache up to date from a JS5 server (rt4 `Js5MasterIndex`
/// + `CachedArchive` checks): fetch the master index, refresh any reference
/// table whose CRC changed, then fetch every group that is missing or whose
/// CRC/version does not match. Safe to rerun; it only downloads what differs.
public final class CacheUpdater {
	public struct Progress {
		public var archive: Int
		public var done: Int
		public var total: Int
	}

	public let directory: URL
	public let host: String
	public let port: Int

	public init(directory: URL, host: String, port: Int) {
		self.directory = directory
		self.host = host
		self.port = port
	}

	/// Downloads what is missing. `archives` limits the work (nil = all).
	/// Returns the number of groups fetched.
	@discardableResult
	public func run(archives: [Int]? = nil, progress: (Progress) -> Void = { _ in }) throws -> Int {
		let client = try Js5Client(host: host, port: port)
		let master = try client.masterIndex()
		// A previous full run against this exact master index already checked every group: skip the
		// per-group CRC pass (it reads and hashes the whole cache, ~30 s on a phone at every launch).
		let stamp = Self.stamp(master)
		let stampURL = directory.appendingPathComponent("js5-verified.txt")
		if archives == nil, let old = try? String(contentsOf: stampURL, encoding: .utf8), old == stamp,
		   FileManager.default.fileExists(atPath: directory.appendingPathComponent("main_file_cache.dat2").path) {
			return 0
		}
		let writer = try DiskCacheWriter(directory: directory)
		var local = try? DiskCache(directory: directory)
		var fetched = 0

		// 1. Reference tables.
		var tables: [Int: Js5Index] = [:]
		var staleTables: [Int] = []
		for a in archives ?? Array(master.indices) where a < master.count && master[a].crc != 0 {
			if let raw = local?.read(archive: 255, group: a),
			   let idx = try? Js5Index(container: Js5Container.stripVersion(raw), expectedChecksum: master[a].crc) {
				tables[a] = idx
			} else {
				staleTables.append(a)
			}
		}
		if !staleTables.isEmpty {
			for (a, container) in zip(staleTables, try client.fetch(staleTables.map { (255, $0) })) {
				tables[a] = try Js5Index(container: container, expectedChecksum: master[a].crc)
				try writer.write(archive: 255, group: a, data: container)
				fetched += 1
			}
			try writer.synchronize()
			local = try? DiskCache(directory: directory)
		}

		// 2. Groups.
		for a in tables.keys.sorted() {
			let idx = tables[a]!
			var wanted: [Int] = []
			for g in idx.groupIds {
				if let raw = local?.read(archive: a, group: g), raw.count >= 2 {
					let body = Js5Container.stripVersion(raw)
					let version = Int(raw[raw.count - 2]) << 8 | Int(raw[raw.count - 1])
					if Crc32.checksum(body) == idx.groupChecksums[g] && version == Int(idx.groupVersions[g]) & 0xFFFF { continue }
				}
				wanted.append(g)
			}
			var done = 0
			progress(Progress(archive: a, done: 0, total: wanted.count))
			var i = 0
			while i < wanted.count {
				let batch = Array(wanted[i..<min(i + 200, wanted.count)])
				let containers = try client.fetch(batch.map { (a, $0) })
				for (g, c) in zip(batch, containers) {
					guard Crc32.checksum(c) == idx.groupChecksums[g] else {
						throw Js5Container.Failure("archive \(a) group \(g): CRC mismatch from server")
					}
					let v = Int(idx.groupVersions[g]) & 0xFFFF
					try writer.write(archive: a, group: g, data: c + [UInt8(v >> 8), UInt8(v & 0xFF)])
				}
				done += batch.count
				fetched += batch.count
				i += batch.count
				progress(Progress(archive: a, done: done, total: wanted.count))
			}
		}
		try writer.synchronize()
		if archives == nil { try? stamp.write(to: stampURL, atomically: true, encoding: .utf8) }
		return fetched
	}

	/// Identifies a master index (every archive's CRC and version).
	static func stamp(_ master: [(crc: Int32, version: Int32)]) -> String {
		master.map { "\($0.crc):\($0.version)" }.joined(separator: ",")
	}
}
