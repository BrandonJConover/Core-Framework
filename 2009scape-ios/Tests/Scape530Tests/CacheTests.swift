import XCTest
@testable import Scape530

/// Runs against a real 2009scape cache when SCAPE530_CACHE points at a
/// directory holding main_file_cache.dat2 + idx files (see 2009scape-ios/README.md).
final class CacheTests: XCTestCase {
	func testTruncatedCacheSectorsFailSafely() throws {
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		let dataFile = dir.appendingPathComponent("main_file_cache.dat2")
		let indexFile = dir.appendingPathComponent("main_file_cache.idx0")
		try Data([0, 0, 2, 0, 0, 1]).write(to: indexFile)
		for count in [520, 525, 529] {
			try Data(repeating: 0, count: count).write(to: dataFile)
			let disk = try DiskCache(directory: dir)
			XCTAssertNil(disk.read(archive: 0, group: 0), "truncated sector at \(count) bytes")
			XCTAssertNil(disk.read(archive: 0, group: -1))
			XCTAssertNil(disk.read(archive: 0, group: Int.max))
		}
	}
	func cache() throws -> DiskCache {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else {
			throw XCTSkip("SCAPE530_CACHE not set")
		}
		return try DiskCache(directory: URL(fileURLWithPath: dir))
	}

	func testReferenceTablesDecode() throws {
		let c = try cache()
		XCTAssertEqual(c.groupSlots(archive: 255), 29)
		for a in 0..<29 {
			let raw = try XCTUnwrap(c.read(archive: 255, group: a))
			let idx = try Js5Index(container: Js5Container.stripVersion(raw))
			XCTAssertGreaterThan(idx.size, 0, "archive \(a)")
		}
	}

	/// Every config group (archive 2) and every model (archive 7) must match its
	/// CRC and decompress: covers both gzip and bzip2 on real data.
	func testConfigAndModelGroupsDecompress() throws {
		let c = try cache()
		for a in [2, 7] {
			let idx = try Js5Index(container: Js5Container.stripVersion(try XCTUnwrap(c.read(archive: 255, group: a))))
			for g in idx.groupIds {
				let container = Js5Container.stripVersion(try XCTUnwrap(c.read(archive: a, group: g)))
				XCTAssertEqual(Crc32.checksum(container), idx.groupChecksums[g], "\(a)/\(g)")
				let data = try Js5Container.decompress(container)
				let files = try Js5Group.unpack(data, index: idx, group: g)
				XCTAssertEqual(files.count, idx.groupSizes[g], "\(a)/\(g)")
			}
		}
	}
}
