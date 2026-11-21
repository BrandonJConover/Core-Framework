// RuneScape Classic .jag archives. Port of rsc-c's mudclient_read_data_file
// and utility.c's load_data/unpack_data.
//
// File layout: 6-byte header (uint24 size, uint24 compressed size), then the
// body, bzip2-compressed as a whole when the sizes differ. The body starts
// with a uint16 entry count and 10 bytes per entry (uint32 name hash, uint24
// size, uint24 stored size), followed by each entry's data, itself
// bzip2-compressed when its two sizes differ.

import Foundation

public enum JagArchiveError: Error {
    case badLength(expected: Int, actual: Int)
}

public struct JagArchive {
    public struct Entry {
        public let hash: UInt32
        public let size: Int
        public let storedSize: Int
        public let offset: Int
    }

    public let body: [UInt8]
    public let entries: [Entry]

    public init(fileBytes: [UInt8]) throws {
        guard fileBytes.count >= 6 else { throw BZip2Error.unexpectedEOF }
        let size = Int(fileBytes[0]) << 16 | Int(fileBytes[1]) << 8 | Int(fileBytes[2])
        let compressed = Int(fileBytes[3]) << 16 | Int(fileBytes[4]) << 8 | Int(fileBytes[5])
        let raw = Array(fileBytes[6..<min(fileBytes.count, 6 + compressed)])

        if size != compressed {
            body = try BZip2.decompress(raw, outputSize: size)
        } else {
            body = raw
        }
        guard body.count == size, size >= 2 else {
            throw JagArchiveError.badLength(expected: size, actual: body.count)
        }

        let count = Int(body[0]) << 8 | Int(body[1])
        var offset = 2 + count * 10
        var entries = [Entry]()
        entries.reserveCapacity(count)

        for i in 0..<count {
            let b = 2 + i * 10
            let hash = UInt32(body[b]) << 24 | UInt32(body[b + 1]) << 16
                | UInt32(body[b + 2]) << 8 | UInt32(body[b + 3])
            let entrySize = Int(body[b + 4]) << 16 | Int(body[b + 5]) << 8 | Int(body[b + 6])
            let stored = Int(body[b + 7]) << 16 | Int(body[b + 8]) << 8 | Int(body[b + 9])
            entries.append(Entry(hash: hash, size: entrySize, storedSize: stored, offset: offset))
            offset += stored
        }

        self.entries = entries
    }

    public init(contentsOf url: URL) throws {
        try self.init(fileBytes: [UInt8](try Data(contentsOf: url)))
    }

    /// Jagex's file name hash (case-insensitive).
    public static func hash(_ name: String) -> UInt32 {
        var hash: UInt32 = 0
        for scalar in name.uppercased().unicodeScalars {
            hash = hash &* 61 &+ UInt32(scalar.value) &- 32
        }
        return hash
    }

    public func contains(_ name: String) -> Bool {
        let wanted = Self.hash(name)
        return entries.contains { $0.hash == wanted }
    }

    /// Returns the named entry's bytes, or nil if the archive doesn't hold it.
    public func file(_ name: String) throws -> [UInt8]? {
        let wanted = Self.hash(name)
        guard let entry = entries.first(where: { $0.hash == wanted }) else {
            return nil
        }
        let slice = Array(body[entry.offset..<(entry.offset + entry.storedSize)])
        if entry.size != entry.storedSize {
            return try BZip2.decompress(slice, outputSize: entry.size)
        }
        return slice
    }
}
