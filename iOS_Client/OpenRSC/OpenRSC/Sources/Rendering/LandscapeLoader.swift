// Loads real terrain data from landscape.dat (compressed sector archive)
// Format: 'LAND'[4B uncompressed size][zlib compressed data]
// Uncompressed: [4B count][count * (1B plane, 2B sectorX, 2B sectorY)][count * 23040B tile data]
// Each sector: 48x48 tiles, 10 bytes per tile

import Foundation
import Compression

struct LandscapeTile {
    let groundElevation: Int
    let groundTexture: Int
    let groundOverlay: Int
    let roofTexture: Int
    let horizontalWall: Int
    let verticalWall: Int
    let diagonalWalls: Int
}

final class LandscapeLoader: @unchecked Sendable {
    // Sector data indexed by "plane_sectorX_sectorY"
    private var sectorData: [String: Data] = [:]

    func loadArchive() {
        let paths: [String] = [
            Bundle.main.path(forResource: "landscape", ofType: "dat") ?? "",
            Bundle.main.path(forResource: "Authentic_Landscape", ofType: "orsc") ?? "",
        ]

        for path in paths where !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            print("[Landscape] Found: \(URL(fileURLWithPath: path).lastPathComponent)")
            if path.hasSuffix(".dat") {
                loadCompressedDat(path: path)
            }
            return
        }
        print("[Landscape] Archive not found — fallback colors")
    }

    private func loadCompressedDat(path: String) {
        guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
        guard fileData.count > 12 else { return }

        let bytes = [UInt8](fileData)
        // Check magic 'LAND'
        guard bytes[0] == 0x4C, bytes[1] == 0x41, bytes[2] == 0x4E, bytes[3] == 0x44 else {
            print("[Landscape] Bad magic")
            return
        }

        let uncompSize = Int(bytes[4]) << 24 | Int(bytes[5]) << 16 | Int(bytes[6]) << 8 | Int(bytes[7])
        let compressed = Data(bytes[8...])

        // Decompress using zlib
        guard let decompressed = zlibDecompress(compressed, expectedSize: uncompSize) else {
            print("[Landscape] Decompression failed")
            return
        }

        let data = [UInt8](decompressed)
        guard data.count >= 4 else { return }

        let count = Int(data[0]) << 24 | Int(data[1]) << 16 | Int(data[2]) << 8 | Int(data[3])
        let indexSize = 4 + count * 5
        let tileDataStart = indexSize
        let sectorSize = 48 * 48 * 10  // 23040

        guard data.count >= tileDataStart + count * sectorSize else {
            print("[Landscape] Data too short: need \(tileDataStart + count * sectorSize), have \(data.count)")
            return
        }

        for i in 0..<count {
            let idx = 4 + i * 5
            let plane = Int(data[idx])
            let sx = Int(data[idx + 1]) << 8 | Int(data[idx + 2])
            let sy = Int(data[idx + 3]) << 8 | Int(data[idx + 4])

            let offset = tileDataStart + i * sectorSize
            let key = "\(plane)_\(sx)_\(sy)"
            sectorData[key] = Data(data[offset..<(offset + sectorSize)])
        }
        print("[Landscape] Loaded \(sectorData.count) sectors")
    }

    private func zlibDecompress(_ input: Data, expectedSize: Int) -> Data? {
        // Python's zlib.compress() produces zlib format: 2-byte header + deflate stream + 4-byte adler32
        // Apple's COMPRESSION_ZLIB expects raw deflate only — strip the wrapper
        let rawDeflate: Data
        let bytes = [UInt8](input)
        if bytes.count > 6 && (bytes[0] == 0x78) {
            // Zlib header detected (0x78 0x01/0x5E/0x9C/0xDA) — strip 2-byte header and 4-byte checksum
            rawDeflate = Data(bytes[2..<(bytes.count - 4)])
            print("[Landscape] Stripped zlib wrapper: \(input.count) → \(rawDeflate.count) bytes")
        } else {
            rawDeflate = input
        }

        var output = Data(count: expectedSize)
        let result = output.withUnsafeMutableBytes { outBuf -> Int in
            rawDeflate.withUnsafeBytes { inBuf -> Int in
                guard let src = inBuf.baseAddress,
                      let dst = outBuf.baseAddress else { return 0 }
                let written = compression_decode_buffer(
                    dst.assumingMemoryBound(to: UInt8.self), expectedSize,
                    src.assumingMemoryBound(to: UInt8.self), rawDeflate.count,
                    nil, COMPRESSION_ZLIB
                )
                return written
            }
        }
        guard result == expectedSize else {
            print("[Landscape] Decompressed \(result) bytes, expected \(expectedSize)")
            return nil
        }
        return output
    }

    // Get tile at absolute world coordinates
    func getTile(worldX: Int, worldZ: Int, plane: Int = 0) -> LandscapeTile? {
        let sx = worldX / 48
        let sz = worldZ / 48
        let localX = worldX % 48
        let localZ = worldZ % 48

        let key = "\(plane)_\(sx)_\(sz)"
        guard let data = sectorData[key] else { return nil }

        let bytes = [UInt8](data)
        let idx = (localX * 48 + localZ) * 10
        guard idx + 9 < bytes.count else { return nil }

        return LandscapeTile(
            groundElevation: Int(Int8(bitPattern: bytes[idx])),
            groundTexture: Int(bytes[idx + 1]),
            groundOverlay: Int(Int8(bitPattern: bytes[idx + 2])),
            roofTexture: Int(bytes[idx + 3]),
            horizontalWall: Int(bytes[idx + 4]),
            verticalWall: Int(bytes[idx + 5]),
            diagonalWalls: Int(bytes[idx + 6]) << 24 | Int(bytes[idx + 7]) << 16 | Int(bytes[idx + 8]) << 8 | Int(bytes[idx + 9])
        )
    }

    var isLoaded: Bool { !sectorData.isEmpty }

    // MARK: - Tile color mapping (matches Java TileDef colors)

    static func tileColor(overlay: Int, texture: Int, elevation: Int) -> Int32 {
        switch overlay {
        case -6, 0:
            let g = min(255, 100 + texture * 3)
            let v = (elevation & 0xF) * 2
            return packRGB(r: 20 + v, g: g + v, b: 10)
        case 1:  return packRGB(r: 120, g: 120, b: 120)
        case 2:  return packRGB(r: 40, g: 80, b: 160)
        case 3:  return packRGB(r: 30, g: 60, b: 140)
        case 4:  return packRGB(r: 40, g: 80, b: 160)
        case 5:  return packRGB(r: 180, g: 40, b: 40)
        case 6:  return packRGB(r: 140, g: 120, b: 80)
        case 7:  return packRGB(r: 100, g: 90, b: 70)
        case 8:  return packRGB(r: 60, g: 60, b: 60)
        case 9:  return packRGB(r: 180, g: 170, b: 130)
        case 10: return packRGB(r: 150, g: 140, b: 100)
        case 11: return packRGB(r: 160, g: 160, b: 160)
        case 12: return packRGB(r: 200, g: 180, b: 140)
        default:
            if overlay < 0 { return packRGB(r: 80, g: 80, b: 80) }
            return packRGB(r: 100 + (overlay * 7) % 100, g: 80 + (overlay * 13) % 100, b: 60)
        }
    }

    static func packRGB(r: Int, g: Int, b: Int) -> Int32 {
        Int32(bitPattern: 0xFF000000 | UInt32(r & 0xFF) << 16 | UInt32(g & 0xFF) << 8 | UInt32(b & 0xFF))
    }
}
