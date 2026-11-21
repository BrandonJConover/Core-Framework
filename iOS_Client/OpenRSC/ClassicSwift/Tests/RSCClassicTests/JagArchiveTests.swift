import XCTest
@testable import RSCClassic

/// Every entry of every cache archive must decompress to the same bytes the
/// C engine produces (golden lists made by tools/jagdump.c).
final class JagArchiveTests: XCTestCase {
    func testAllArchivesMatchCEngine() throws {
        let goldenDir = TestPaths.golden.appendingPathComponent("jag")
        let files = try FileManager.default.contentsOfDirectory(atPath: goldenDir.path)
            .filter { $0.hasSuffix(".txt") }.sorted()
        XCTAssertFalse(files.isEmpty)

        for file in files {
            let archiveName = String(file.dropLast(4))
            let archive = try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent(archiveName))
            let lines = try String(contentsOf: goldenDir.appendingPathComponent(file), encoding: .utf8)
                .split(separator: "\n")
            XCTAssertEqual(archive.entries.count, lines.count, archiveName)

            for line in lines {
                let parts = line.split(separator: " ").compactMap { UInt32($0) }
                let entry = archive.entries[Int(parts[0])]
                XCTAssertEqual(entry.hash, parts[1], "\(archiveName) #\(parts[0]) hash")
                XCTAssertEqual(entry.size, Int(parts[2]), "\(archiveName) #\(parts[0]) size")

                let slice = Array(archive.body[entry.offset..<(entry.offset + entry.storedSize)])
                let bytes = entry.size == entry.storedSize
                    ? slice : try BZip2.decompress(slice, outputSize: entry.size)
                XCTAssertEqual(fnv1a(bytes), parts[3], "\(archiveName) #\(parts[0]) contents")
            }
        }
    }

    func testNameHash() throws {
        let archive = try JagArchive(contentsOf: TestPaths.cache.appendingPathComponent("config85.jag"))
        XCTAssertTrue(archive.contains("string.dat"))
        XCTAssertTrue(archive.contains("INTEGER.DAT"))
    }
}
