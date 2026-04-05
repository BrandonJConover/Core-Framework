import Foundation
import Compression

/// Reads .orsc sprite archive files.
/// Supports both ZIP format (Authentic_Sprites.orsc) and GZIP format (custom archives).
final class SpriteArchiveReader {

    // MARK: - Data Types

    /// Sprite entry type matching Java Entry.TYPE
    enum EntryType: Int {
        case sprite = 0
        case playerPart = 1
        case playerEquippableHasCombat = 2
        case playerEquippableNoCombat = 3
        case npc = 4

        var hasLayers: Bool {
            switch self {
            case .playerPart, .playerEquippableHasCombat, .playerEquippableNoCombat:
                return true
            case .sprite, .npc:
                return false
            }
        }
    }

    /// Equipment layer matching Java Frame.LAYER
    enum SpriteLayer: Int {
        case headNoSkin = 0
        case bodyNoSkin = 1
        case legsNoSkin = 2
        case mainHand = 3
        case offHand = 4
        case headWithSkin = 5
        case bodyWithSkin = 6
        case legsWithSkin = 7
        case neck = 8
        case boots = 9
        case gloves = 10
        case cape = 11
    }

    /// A single sprite frame with pixel data
    struct SpriteFrame {
        let width: Int
        let height: Int
        let useShift: Bool
        let offsetX: Int
        let offsetY: Int
        let boundWidth: Int
        let boundHeight: Int
        var pixels: [Int32]
    }

    /// A sprite entry (one or more animation frames)
    struct SpriteEntry {
        let id: String
        let type: EntryType
        let layer: SpriteLayer?
        var frames: [SpriteFrame]
    }

    /// A named collection of sprite entries
    struct SpriteSubspace {
        let name: String
        var entries: [SpriteEntry]
    }

    /// Top-level sprite archive workspace
    struct SpriteWorkspace {
        let name: String
        var subspaces: [SpriteSubspace]

        /// Flat array of all sprites indexed by numeric ID
        var indexedSprites: [Int: SpriteFrame] = [:]

        func findEntry(subspace: String, entryId: String) -> SpriteEntry? {
            guard let sub = subspaces.first(where: { $0.name.lowercased() == subspace.lowercased() }) else {
                return nil
            }
            return sub.entries.first(where: { $0.id == entryId })
        }

        var allEntries: [SpriteEntry] {
            subspaces.flatMap { $0.entries }
        }

        var totalFrameCount: Int {
            allEntries.reduce(0) { $0 + $1.frames.count }
        }
    }

    // MARK: - Binary Reader

    private struct BinaryReader {
        let data: Data
        var position: Int = 0

        var remaining: Int { data.count - position }

        mutating func readByte() -> UInt8? {
            guard position < data.count else { return nil }
            let value = data[data.startIndex + position]
            position += 1
            return value
        }

        mutating func readInt32() -> Int32? {
            guard position + 4 <= data.count else { return nil }
            let b0 = Int32(data[data.startIndex + position])
            let b1 = Int32(data[data.startIndex + position + 1])
            let b2 = Int32(data[data.startIndex + position + 2])
            let b3 = Int32(data[data.startIndex + position + 3])
            position += 4
            return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        }

        mutating func readUnsignedShort() -> UInt16? {
            guard position + 2 <= data.count else { return nil }
            let hi = UInt16(data[data.startIndex + position])
            let lo = UInt16(data[data.startIndex + position + 1])
            position += 2
            return hi << 8 | lo
        }

        mutating func readSignedShort() -> Int16? {
            guard let unsigned = readUnsignedShort() else { return nil }
            return Int16(bitPattern: unsigned)
        }

        mutating func readNullTerminatedString() -> String? {
            var bytes: [UInt8] = []
            while position < data.count {
                let byte = data[data.startIndex + position]
                position += 1
                if byte == 0 { break }
                bytes.append(byte)
            }
            return String(bytes: bytes, encoding: .utf8)
        }
    }

    // MARK: - Archive Reading

    func readArchive(from url: URL) -> SpriteWorkspace? {
        guard let data = try? Data(contentsOf: url) else {
            print("SpriteArchiveReader: Failed to read file at \(url.path)")
            return nil
        }
        return readArchive(from: data, name: url.deletingPathExtension().lastPathComponent)
    }

    func readArchive(from data: Data, name: String) -> SpriteWorkspace? {
        guard data.count > 4 else { return nil }

        // Detect format: ZIP starts with "PK" (0x50 0x4B)
        if data[0] == 0x50 && data[1] == 0x4B {
            return readZipArchive(data: data, name: name)
        }

        // GZIP starts with 0x1F 0x8B
        if data[0] == 0x1F && data[1] == 0x8B {
            return readGzipArchive(data: data, name: name)
        }

        print("SpriteArchiveReader: Unknown archive format for '\(name)'")
        return nil
    }

    // MARK: - ZIP Archive Reading (Authentic_Sprites.orsc format)

    /// Reads a ZIP-format .orsc archive where each entry is a packed Sprite (Java format).
    /// Entry names are numeric indices (0, 1, 2, ...).
    private func readZipArchive(data: Data, name: String) -> SpriteWorkspace? {
        // Write to temp file for ZipArchive access (Foundation doesn't have in-memory ZIP)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("orsc")

        do {
            try data.write(to: tempURL)
        } catch {
            print("SpriteArchiveReader: Failed to write temp file: \(error)")
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        return readZipFile(at: tempURL, name: name)
    }

    private func readZipFile(at url: URL, name: String) -> SpriteWorkspace? {
        guard let archive = ZipArchiveReader(url: url) else {
            print("SpriteArchiveReader: Failed to open ZIP archive")
            return nil
        }

        let entryNames = archive.entryNames.sorted { a, b in
            // Sort numerically (0, 1, 2, ..., 10, 11, ...)
            (Int(a) ?? Int.max) < (Int(b) ?? Int.max)
        }

        var indexedSprites: [Int: SpriteFrame] = [:]
        var spriteEntries: [SpriteEntry] = []

        for entryName in entryNames {
            guard let entryData = archive.readEntry(named: entryName) else { continue }
            guard let frame = readPackedSprite(data: entryData) else { continue }

            let entry = SpriteEntry(
                id: entryName,
                type: .sprite,
                layer: nil,
                frames: [frame]
            )
            spriteEntries.append(entry)

            if let index = Int(entryName) {
                indexedSprites[index] = frame
            }
        }

        let subspace = SpriteSubspace(name: "sprites", entries: spriteEntries)
        var workspace = SpriteWorkspace(name: name, subspaces: [subspace])
        workspace.indexedSprites = indexedSprites

        print("SpriteArchiveReader: Loaded ZIP archive '\(name)' with \(spriteEntries.count) sprites")
        return workspace
    }

    /// Reads a packed sprite in Java Sprite.pack() format:
    /// int width, int height, byte shift, int xShift, int yShift, int something1, int something2, int[w*h] pixels
    private func readPackedSprite(data: Data) -> SpriteFrame? {
        var reader = BinaryReader(data: data)

        guard let width = reader.readInt32(),
              let height = reader.readInt32(),
              let shiftByte = reader.readByte(),
              let xShift = reader.readInt32(),
              let yShift = reader.readInt32(),
              let boundWidth = reader.readInt32(),
              let boundHeight = reader.readInt32() else {
            return nil
        }

        let w = Int(width)
        let h = Int(height)
        guard w > 0, w < 4096, h > 0, h < 4096 else { return nil }

        let pixelCount = w * h
        guard reader.remaining >= pixelCount * 4 else { return nil }

        var pixels = [Int32](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            guard let pixel = reader.readInt32() else { break }
            pixels[i] = pixel
        }

        return SpriteFrame(
            width: w,
            height: h,
            useShift: shiftByte == 1,
            offsetX: Int(xShift),
            offsetY: Int(yShift),
            boundWidth: Int(boundWidth),
            boundHeight: Int(boundHeight),
            pixels: pixels
        )
    }

    // MARK: - GZIP Archive Reading (custom sprite format)

    private func readGzipArchive(data: Data, name: String) -> SpriteWorkspace? {
        guard let decompressed = decompressGzip(data) else {
            print("SpriteArchiveReader: Failed to decompress GZIP archive '\(name)'")
            return nil
        }

        var reader = BinaryReader(data: decompressed)

        guard let subspaceCount = reader.readByte() else { return nil }

        var subspaces: [SpriteSubspace] = []
        for i in 0..<Int(subspaceCount) {
            guard let subspaceName = reader.readNullTerminatedString() else {
                print("SpriteArchiveReader: Failed to read subspace name at index \(i)")
                break
            }
            if let subspace = readGzipSubspace(reader: &reader, name: subspaceName) {
                subspaces.append(subspace)
            }
        }

        return SpriteWorkspace(name: name, subspaces: subspaces)
    }

    private func readGzipSubspace(reader: inout BinaryReader, name: String) -> SpriteSubspace? {
        guard let entryCount = reader.readUnsignedShort() else { return nil }

        var entries: [SpriteEntry] = []
        for _ in 0..<Int(entryCount) {
            guard let entryName = reader.readNullTerminatedString(),
                  let typeByte = reader.readByte() else { break }

            let entryType = EntryType(rawValue: Int(typeByte)) ?? .sprite

            var layer: SpriteLayer? = nil
            if entryType.hasLayers {
                if let layerByte = reader.readByte() {
                    layer = SpriteLayer(rawValue: Int(layerByte))
                }
            }

            guard let frameCount = reader.readByte() else { break }

            var entry = SpriteEntry(id: entryName, type: entryType, layer: layer, frames: [])
            readGzipEntryFrames(reader: &reader, entry: &entry, frameCount: Int(frameCount))
            entries.append(entry)
        }

        return SpriteSubspace(name: name, entries: entries)
    }

    private func readGzipEntryFrames(reader: inout BinaryReader, entry: inout SpriteEntry, frameCount: Int) {
        guard let tableSizeByte = reader.readByte() else { return }
        let tableSize = Int(tableSizeByte) + 1

        var colorTable = [Int32](repeating: 0, count: tableSize)
        for i in 0..<tableSize {
            guard let r = reader.readByte(),
                  let g = reader.readByte(),
                  let b = reader.readByte() else { return }
            colorTable[i] = Int32(r) << 16 | Int32(g) << 8 | Int32(b)
        }

        var frames: [SpriteFrame] = []
        for _ in 0..<frameCount {
            guard let width = reader.readUnsignedShort(),
                  let height = reader.readUnsignedShort(),
                  let shiftByte = reader.readByte(),
                  let offsetX = reader.readSignedShort(),
                  let offsetY = reader.readSignedShort(),
                  let boundWidth = reader.readUnsignedShort(),
                  let boundHeight = reader.readUnsignedShort() else { break }

            let pixelCount = Int(width) * Int(height)
            var pixels = [Int32](repeating: 0, count: pixelCount)

            for p in 0..<pixelCount {
                guard let colorIndex = reader.readByte() else { break }
                let idx = Int(colorIndex) & 0xFF
                if idx < tableSize {
                    pixels[p] = colorTable[idx]
                }
            }

            frames.append(SpriteFrame(
                width: Int(width),
                height: Int(height),
                useShift: shiftByte == 1,
                offsetX: Int(offsetX),
                offsetY: Int(offsetY),
                boundWidth: Int(boundWidth),
                boundHeight: Int(boundHeight),
                pixels: pixels
            ))
        }

        entry.frames = frames
    }

    // MARK: - GZIP Decompression

    private func decompressGzip(_ data: Data) -> Data? {
        guard data.count >= 10, data[0] == 0x1f, data[1] == 0x8b, data[2] == 0x08 else {
            return nil
        }

        let flags = data[3]
        var pos = 10

        if flags & 0x04 != 0 {
            guard pos + 2 <= data.count else { return nil }
            let extraLen = Int(data[pos]) | Int(data[pos + 1]) << 8
            pos += 2 + extraLen
        }
        if flags & 0x08 != 0 {
            while pos < data.count && data[pos] != 0 { pos += 1 }
            pos += 1
        }
        if flags & 0x10 != 0 {
            while pos < data.count && data[pos] != 0 { pos += 1 }
            pos += 1
        }
        if flags & 0x02 != 0 { pos += 2 }

        guard pos < data.count else { return nil }

        let deflateEnd = max(pos, data.count - 8)
        let deflateData = data[pos..<deflateEnd]

        return decompressRawDeflate(deflateData)
    }

    private func decompressRawDeflate(_ data: Data) -> Data? {
        let inputSize = data.count
        guard inputSize > 0 else { return nil }

        let chunkSize = 65536
        var output = Data()

        return data.withUnsafeBytes { (inputBuffer: UnsafeRawBufferPointer) -> Data? in
            guard let baseAddress = inputBuffer.baseAddress else { return nil }
            let inputPtr = baseAddress.assumingMemoryBound(to: UInt8.self)

            var stream = compression_stream(
                dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
                dst_size: 0,
                src_ptr: inputPtr,
                src_size: 0,
                state: nil
            )
            let initStatus = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            guard initStatus == COMPRESSION_STATUS_OK else { return nil }
            defer { compression_stream_destroy(&stream) }

            stream.src_ptr = inputPtr
            stream.src_size = inputSize

            let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { outputBuffer.deallocate() }

            var status: compression_status

            repeat {
                stream.dst_ptr = outputBuffer
                stream.dst_size = chunkSize

                status = compression_stream_process(&stream, 0)

                let outputCount = chunkSize - stream.dst_size
                if outputCount > 0 {
                    output.append(outputBuffer, count: outputCount)
                }

                if status == COMPRESSION_STATUS_ERROR { return nil }
            } while status == COMPRESSION_STATUS_OK

            stream.dst_ptr = outputBuffer
            stream.dst_size = chunkSize
            status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            let finalCount = chunkSize - stream.dst_size
            if finalCount > 0 {
                output.append(outputBuffer, count: finalCount)
            }

            return output.isEmpty ? nil : output
        }
    }
}

// MARK: - Minimal ZIP Reader (no external dependencies)

/// Simple ZIP archive reader for .orsc files.
/// Reads uncompressed and DEFLATE-compressed entries.
final class ZipArchiveReader {
    private let data: Data
    private var entries: [String: (offset: Int, compressedSize: Int, uncompressedSize: Int, method: UInt16)] = [:]

    var entryNames: [String] { Array(entries.keys) }

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.data = data
        if !parseDirectory() { return nil }
    }

    init?(data: Data) {
        self.data = data
        if !parseDirectory() { return nil }
    }

    func readEntry(named name: String) -> Data? {
        guard let entry = entries[name] else { return nil }

        // Read local file header to get actual data offset
        let localOffset = entry.offset
        guard localOffset + 30 <= data.count else { return nil }

        // Verify local file header signature (0x04034b50)
        guard data[localOffset] == 0x50, data[localOffset + 1] == 0x4B,
              data[localOffset + 2] == 0x03, data[localOffset + 3] == 0x04 else {
            return nil
        }

        let fileNameLen = Int(readUInt16(at: localOffset + 26))
        let extraLen = Int(readUInt16(at: localOffset + 28))
        let dataStart = localOffset + 30 + fileNameLen + extraLen

        guard dataStart + entry.compressedSize <= data.count else { return nil }

        let compressedData = data[dataStart..<(dataStart + entry.compressedSize)]

        if entry.method == 0 {
            // Stored (uncompressed)
            return Data(compressedData)
        } else if entry.method == 8 {
            // Deflate
            return decompressDeflate(Data(compressedData), expectedSize: entry.uncompressedSize)
        }

        return nil
    }

    // MARK: - Private

    private func parseDirectory() -> Bool {
        // Find End of Central Directory record (search from end)
        var eocdOffset = -1
        let searchStart = max(0, data.count - 65557) // Max comment size + EOCD size

        for i in stride(from: data.count - 22, through: searchStart, by: -1) {
            if data[i] == 0x50 && data[i + 1] == 0x4B &&
               data[i + 2] == 0x05 && data[i + 3] == 0x06 {
                eocdOffset = i
                break
            }
        }

        guard eocdOffset >= 0 else { return false }

        let totalEntries = Int(readUInt16(at: eocdOffset + 10))
        let cdOffset = Int(readUInt32(at: eocdOffset + 16))

        var pos = cdOffset
        for _ in 0..<totalEntries {
            guard pos + 46 <= data.count else { break }

            // Central directory header signature (0x02014b50)
            guard data[pos] == 0x50, data[pos + 1] == 0x4B,
                  data[pos + 2] == 0x01, data[pos + 3] == 0x02 else { break }

            let method = readUInt16(at: pos + 10)
            let compressedSize = Int(readUInt32(at: pos + 20))
            let uncompressedSize = Int(readUInt32(at: pos + 24))
            let fileNameLen = Int(readUInt16(at: pos + 28))
            let extraLen = Int(readUInt16(at: pos + 30))
            let commentLen = Int(readUInt16(at: pos + 32))
            let localHeaderOffset = Int(readUInt32(at: pos + 42))

            let nameStart = pos + 46
            guard nameStart + fileNameLen <= data.count else { break }
            let nameData = data[nameStart..<(nameStart + fileNameLen)]
            let name = String(data: nameData, encoding: .utf8) ?? ""

            entries[name] = (
                offset: localHeaderOffset,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                method: method
            )

            pos = nameStart + fileNameLen + extraLen + commentLen
        }

        return !entries.isEmpty
    }

    private func readUInt16(at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 |
        UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private func decompressDeflate(_ compressed: Data, expectedSize: Int) -> Data? {
        let inputSize = compressed.count
        guard inputSize > 0 else { return nil }

        let outputSize = max(expectedSize, inputSize * 4)
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outputSize)
        defer { outputBuffer.deallocate() }

        let result = compressed.withUnsafeBytes { (inputBuffer: UnsafeRawBufferPointer) -> Int in
            guard let inputPtr = inputBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_decode_buffer(
                outputBuffer, outputSize,
                inputPtr, inputSize,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard result > 0 else { return nil }
        return Data(bytes: outputBuffer, count: result)
    }
}

// MARK: - Convert SpriteFrame to renderable Sprite

extension SpriteArchiveReader.SpriteFrame {
    /// Converts RSC pixel format (0 = transparent, non-zero = RGB) to ARGB.
    func toRenderablePixels() -> [UInt32] {
        pixels.map { pixel in
            if pixel == 0 {
                return 0x00000000 // Transparent
            }
            return 0xFF000000 | UInt32(bitPattern: pixel)
        }
    }

    func toSprite(id: String) -> Sprite {
        Sprite(
            id: id,
            width: width,
            height: height,
            pixels: toRenderablePixels(),
            useShift: useShift,
            offsetX: offsetX,
            offsetY: offsetY,
            boundWidth: boundWidth,
            boundHeight: boundHeight
        )
    }
}
