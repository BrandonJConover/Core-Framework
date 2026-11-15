import Foundation

/// Reader for the on-disk `main_file_cache.dat2` + `.idxN` layout
/// (rt4 `Cache`). Used for a bundled offline cache and for tests.
public final class DiskCache {
	public static let sectorSize = 520

	let dat: Data
	var indexes: [Int: Data] = [:]
	public let directory: URL

	public init(directory: URL) throws {
		self.directory = directory
		dat = try Data(contentsOf: directory.appendingPathComponent("main_file_cache.dat2"), options: .alwaysMapped)
	}

	func index(_ archive: Int) -> Data? {
		if let d = indexes[archive] { return d }
		let url = directory.appendingPathComponent("main_file_cache.idx\(archive)")
		guard let d = try? Data(contentsOf: url) else { return nil }
		indexes[archive] = d
		return d
	}

	/// Number of group slots in an archive's idx file.
	public func groupSlots(archive: Int) -> Int {
		(index(archive)?.count ?? 0) / 6
	}

	/// The raw stored bytes for a group (container + version trailer), or nil.
	public func read(archive: Int, group: Int) -> [UInt8]? {
		guard let idx = index(archive), idx.count >= group * 6 + 6 else { return nil }
		let e = idx.startIndex + group * 6
		let size = Int(idx[e]) << 16 | Int(idx[e + 1]) << 8 | Int(idx[e + 2])
		var sector = Int(idx[e + 3]) << 16 | Int(idx[e + 4]) << 8 | Int(idx[e + 5])
		let sectors = dat.count / DiskCache.sectorSize
		guard size > 0, sector > 0, sector <= sectors else { return nil }

		let extended = group > 0xFFFF
		let header = extended ? 10 : 8
		let payload = DiskCache.sectorSize - header
		var out = [UInt8]()
		out.reserveCapacity(size)
		var chunk = 0
		while out.count < size {
			guard sector > 0, sector <= sectors else { return nil }
			let base = dat.startIndex + sector * DiskCache.sectorSize
			let n = min(size - out.count, payload)
			var h = base
			let g: Int
			if extended {
				g = Int(dat[h]) << 24 | Int(dat[h + 1]) << 16 | Int(dat[h + 2]) << 8 | Int(dat[h + 3])
				h += 4
			} else {
				g = Int(dat[h]) << 8 | Int(dat[h + 1])
				h += 2
			}
			let c = Int(dat[h]) << 8 | Int(dat[h + 1])
			let next = Int(dat[h + 2]) << 16 | Int(dat[h + 3]) << 8 | Int(dat[h + 4])
			let a = Int(dat[h + 5])
			guard g == group, c == chunk, a == archive else { return nil }
			out.append(contentsOf: dat[(base + header)..<(base + header + n)])
			chunk += 1
			sector = next
		}
		return out
	}
}
