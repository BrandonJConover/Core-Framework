import Foundation

struct LandscapeTile {
    let groundElevation: Int
    let groundTexture: Int
    let groundOverlay: Int
    let roofTexture: Int
    let horizontalWall: Int
    let verticalWall: Int
    let diagonalWalls: Int
}

struct TileDecorDefinition {
    let color: Int
    let tileValue: Int
    let objectType: Int
}

final class TileDefinitions {
    static let shared = TileDefinitions()

    private let definitions: [Int: TileDecorDefinition]

    private init(bundle: Bundle = .main) {
        definitions = Self.loadDefinitions(bundle: bundle)
    }

    func definition(for overlayId: Int) -> TileDecorDefinition? {
        definitions[overlayId - 1]
    }

    private static func loadDefinitions(bundle: Bundle) -> [Int: TileDecorDefinition] {
        guard let url = bundle.url(forResource: "TileDef", withExtension: "xml"),
              let xml = try? String(contentsOf: url, encoding: .utf8) else {
            print("[TileDefinitions] Failed to load bundled TileDef.xml")
            return [:]
        }

        let pattern = #"<TileDef>\s*<colour>(-?\d+)</colour>\s*<unknown>(-?\d+)</unknown>\s*<objectType>(-?\d+)</objectType>\s*</TileDef>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [:]
        }

        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = regex.matches(in: xml, options: [], range: range)
        var results: [Int: TileDecorDefinition] = [:]

        for (index, match) in matches.enumerated() {
            guard match.numberOfRanges == 4,
                  let colorRange = Range(match.range(at: 1), in: xml),
                  let tileValueRange = Range(match.range(at: 2), in: xml),
                  let objectTypeRange = Range(match.range(at: 3), in: xml),
                  let color = Int(xml[colorRange]),
                  let tileValue = Int(xml[tileValueRange]),
                  let objectType = Int(xml[objectTypeRange]) else {
                continue
            }

            results[index] = TileDecorDefinition(
                color: color,
                tileValue: tileValue,
                objectType: objectType
            )
        }

        print("[TileDefinitions] Loaded \(results.count) tile definitions")
        return results
    }
}

final class LandscapeArchive {
    static let shared = LandscapeArchive()

    private struct SectorKey: Hashable {
        let plane: Int
        let sectionX: Int
        let sectionY: Int
    }

    private struct LandscapeSector {
        static let width = 48
        static let height = 48

        let tiles: [LandscapeTile]

        func tile(x: Int, y: Int) -> LandscapeTile? {
            guard x >= 0, x < Self.width, y >= 0, y < Self.height else { return nil }
            return tiles[x * Self.width + y]
        }
    }

    private let archive: ZipArchiveReader?
    private var sectorCache: [SectorKey: LandscapeSector] = [:]

    private init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "Authentic_Landscape", withExtension: "orsc"),
           let archive = ZipArchiveReader(url: url) {
            self.archive = archive
            print("[LandscapeArchive] Opened Authentic_Landscape.orsc with \(archive.entryNames.count) entries")
        } else {
            self.archive = nil
            print("[LandscapeArchive] Failed to open Authentic_Landscape.orsc")
        }
    }

    func tile(atWorldX worldX: Int, worldY: Int, plane: Int, centeredAt centerX: Int, centerY: Int) -> LandscapeTile? {
        let chunkX = (24 + centerX) / 48
        let chunkY = (24 + centerY) / 48
        let baseX = (chunkX - 1) * 48
        let baseY = (chunkY - 1) * 48

        let localX = worldX - baseX
        let localY = worldY - baseY

        guard localX >= 0, localX < 96, localY >= 0, localY < 96 else {
            return nil
        }

        let sectorIndex: Int
        let sectorX: Int
        let sectorY: Int
        let tileX: Int
        let tileY: Int

        switch (localX >= 48, localY >= 48) {
        case (false, false):
            sectorIndex = 0
            sectorX = chunkX - 1
            sectorY = chunkY - 1
            tileX = localX
            tileY = localY
        case (true, false):
            sectorIndex = 1
            sectorX = chunkX
            sectorY = chunkY - 1
            tileX = localX - 48
            tileY = localY
        case (false, true):
            sectorIndex = 2
            sectorX = chunkX - 1
            sectorY = chunkY
            tileX = localX
            tileY = localY - 48
        case (true, true):
            sectorIndex = 3
            sectorX = chunkX
            sectorY = chunkY
            tileX = localX - 48
            tileY = localY - 48
        }

        _ = sectorIndex
        let sector = loadSector(plane: plane, sectionX: sectorX, sectionY: sectorY)
        return sector.tile(x: tileX, y: tileY)
    }

    private func loadSector(plane: Int, sectionX: Int, sectionY: Int) -> LandscapeSector {
        let key = SectorKey(plane: plane, sectionX: sectionX, sectionY: sectionY)
        if let cached = sectorCache[key] {
            return cached
        }

        let loaded: LandscapeSector
        if let archive,
           let entryData = archive.readEntry(named: "h\(plane)x\(sectionX)y\(sectionY)"),
           let parsed = parseSector(entryData) {
            loaded = parsed
        } else {
            loaded = defaultSector(for: plane)
        }

        sectorCache[key] = loaded
        return loaded
    }

    private func parseSector(_ data: Data) -> LandscapeSector? {
        let expectedSize = LandscapeSector.width * LandscapeSector.height * 10
        guard data.count >= expectedSize else { return nil }

        var tiles: [LandscapeTile] = []
        tiles.reserveCapacity(LandscapeSector.width * LandscapeSector.height)

        var offset = 0
        while offset + 10 <= data.count && tiles.count < LandscapeSector.width * LandscapeSector.height {
            let diagonalWalls =
                (Int(data[offset + 6]) << 24) |
                (Int(data[offset + 7]) << 16) |
                (Int(data[offset + 8]) << 8) |
                Int(data[offset + 9])

            tiles.append(
                LandscapeTile(
                    groundElevation: Int(data[offset]),
                    groundTexture: Int(data[offset + 1]),
                    groundOverlay: Int(data[offset + 2]),
                    roofTexture: Int(data[offset + 3]),
                    horizontalWall: Int(data[offset + 4]),
                    verticalWall: Int(data[offset + 5]),
                    diagonalWalls: diagonalWalls
                )
            )
            offset += 10
        }

        guard tiles.count == LandscapeSector.width * LandscapeSector.height else {
            return nil
        }

        return LandscapeSector(tiles: tiles)
    }

    private func defaultSector(for plane: Int) -> LandscapeSector {
        let defaultOverlay = (plane == 0 || plane == 3) ? 250 : 8
        let tile = LandscapeTile(
            groundElevation: 0,
            groundTexture: 0,
            groundOverlay: defaultOverlay,
            roofTexture: 0,
            horizontalWall: 0,
            verticalWall: 0,
            diagonalWalls: 0
        )
        return LandscapeSector(
            tiles: Array(repeating: tile, count: LandscapeSector.width * LandscapeSector.height)
        )
    }
}
