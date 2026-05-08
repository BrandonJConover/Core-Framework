// Loads sprites_v2.dat — a flat binary produced from Authentic_Sprites.orsc
// by tools/make_sprites_v2.py. Container format (all big-endian):
//
//   4B magic 'SPR2' (0x53505232)
//   4B count
//   count * 32B index entries:
//     4B spriteID | 4B pixelOffset
//     4B width    | 4B height
//     1B requiresShift | 3B padding
//     4B xShift   | 4B yShift
//     4B authenticWidth (something1) | 4B authenticHeight (something2)
//   pixel pool: concatenated ARGB pixels (4B each, big-endian)

import Foundation

struct GameSprite {
    let width: Int
    let height: Int
    let pixels: [Int32]       // ARGB
    let requiresShift: Bool
    let xShift: Int
    let yShift: Int
    /// Java something1 — authentic bounding-box width (before shift/trim)
    let authenticWidth: Int
    /// Java something2 — authentic bounding-box height
    let authenticHeight: Int
}

struct TerrainTextureBuffer {
    let index: Int
    let spriteID: Int
    let width: Int
    let height: Int
    /// Expanded ARGB pixels remapped through the Java-style 256-colour palette.
    let pixels: [Int32]
    /// Java dictionary/palette. Kept for the later scanline-rasterizer pass.
    let palette: [Int32]
    /// One byte per source pixel, indexing into `palette`.
    let indices: Data
    /// Java `sprite.getSomething1() / 64 - 1`: 0 for normal, 1+ for large.
    let type: Int
}

class SpriteLoader: @unchecked Sendable {
    static let terrainTextureBaseID = 3225

    private(set) var sprites: [Int: GameSprite] = [:]
    var isLoaded: Bool { !sprites.isEmpty }

    func loadArchive() {
        guard let path = Bundle.main.path(forResource: "sprites_v2", ofType: "dat"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("[Sprites] sprites_v2.dat not found in bundle")
            return
        }
        parse([UInt8](data))
        print("[Sprites] Loaded \(sprites.count) sprites from sprites_v2.dat")
    }

    /// Internal entry-point used by tests to feed raw archive bytes without Bundle.
    func parseBytes(_ b: [UInt8]) {
        parse(b)
    }

    private func parse(_ b: [UInt8]) {
        guard b.count >= 8,
              b[0] == 0x53, b[1] == 0x50, b[2] == 0x52, b[3] == 0x32 else { // 'SPR2'
            print("[Sprites] Bad magic in sprites_v2.dat")
            return
        }
        let count = beInt(b, 4)
        let indexStart = 8
        // Entry layout: id(4)+off(4)+w(4)+h(4)+req(1)+pad(3)+xs(4)+ys(4)+authW(4)+authH(4) = 36B
        let entrySize = 36
        let pixelBase = indexStart + count * entrySize
        guard b.count >= pixelBase else { return }

        for i in 0..<count {
            let e = indexStart + i * entrySize
            let id = beInt(b, e + 0)
            let offset = beInt(b, e + 4)
            let w = beInt(b, e + 8)
            let h = beInt(b, e + 12)
            let requiresShift = b[e + 16] != 0
            let xs = beInt(b, e + 20)
            let ys = beInt(b, e + 24)
            let authW = beInt(b, e + 28)
            let authH = beInt(b, e + 32)

            guard w > 0 && h > 0 else { continue }
            let pixelCount = w * h
            let pixelStart = pixelBase + offset
            guard pixelStart + pixelCount * 4 <= b.count else { continue }

            var pixels = [Int32](repeating: 0, count: pixelCount)
            var p = pixelStart
            for j in 0..<pixelCount {
                let argb = (Int32(b[p]) << 24) | (Int32(b[p+1]) << 16) | (Int32(b[p+2]) << 8) | Int32(b[p+3])
                pixels[j] = argb
                p += 4
            }
            sprites[id] = GameSprite(
                width: w, height: h, pixels: pixels,
                requiresShift: requiresShift,
                xShift: xs, yShift: ys,
                authenticWidth: authW, authenticHeight: authH
            )
        }
    }

    private func beInt(_ b: [UInt8], _ i: Int) -> Int {
        let u = (UInt32(b[i]) << 24) | (UInt32(b[i+1]) << 16) | (UInt32(b[i+2]) << 8) | UInt32(b[i+3])
        return Int(Int32(bitPattern: u))
    }

    // MARK: - Accessors

    func getSprite(_ id: Int) -> GameSprite? { sprites[id] }

    /// Copy loaded sprites into a GraphicsController's sprite atlas so that
    /// Scene.drawEntity() can access them by archive ID.
    func bridgeInto(_ graphics: GraphicsController) {
        for (id, gs) in sprites {
            guard id >= 0 && id < graphics.sprites.count else { continue }
            graphics.sprites[id] = Sprite(
                pixels: gs.pixels,
                width: Int32(gs.width),
                height: Int32(gs.height),
                cropX: Int32(gs.xShift),
                cropY: Int32(gs.yShift)
            )
        }
        print("[Sprites] Bridged \(sprites.count) sprites into GraphicsController (atlas size \(graphics.sprites.count))")
    }

    /// Builds the Java mudclient terrain texture buffers from the authentic
    /// sprite range beginning at `spriteTexture` (3225). The desktop client
    /// quantises each sprite to a 256-entry palette plus byte indices before
    /// handing it to Scene.loadTexture; we keep both that compact form and an
    /// expanded ARGB copy for the current iOS placeholder rasterizer.
    func terrainTextureBuffers(startID: Int = SpriteLoader.terrainTextureBaseID) -> [TerrainTextureBuffer] {
        var out: [TerrainTextureBuffer] = []
        var textureIndex = 0

        while let sprite = sprites[startID + textureIndex] {
            out.append(makeTerrainTextureBuffer(index: textureIndex, spriteID: startID + textureIndex, sprite: sprite))
            textureIndex += 1
        }

        return out
    }

    func loadTerrainTextures(into scene: Scene, startID: Int = SpriteLoader.terrainTextureBaseID) -> Int {
        let buffers = terrainTextureBuffers(startID: startID)
        for texture in buffers {
            scene.loadTexture(index: texture.index, pixels: texture.pixels, type: texture.type, data: texture.indices)
        }

        if let last = buffers.last {
            print("[Textures] Loaded \(buffers.count) textures from spriteTexture range (\(startID)..\(last.spriteID))")
        } else {
            print("[Textures] No terrain textures found at spriteTexture base \(startID)")
        }
        return buffers.count
    }

    // Fallback direct blit for overhead map rendering.
    func drawSprite(_ id: Int, onto buffer: inout [Int32], bufferWidth: Int, bufferHeight: Int,
                    atX: Int, atY: Int, scale: Int = 1) {
        guard let sprite = sprites[id] else { return }
        for sy in 0..<sprite.height {
            for sx in 0..<sprite.width {
                let pixel = sprite.pixels[sy * sprite.width + sx]
                // RSC sprites store transparency as pixel == 0; alpha byte is
                // always 0 on disk — don't reject on it.
                if pixel == 0 { continue }
                // Force alpha to opaque so the framebuffer pixel is visible
                let opaque = pixel | Int32(bitPattern: 0xFF000000)
                for dy in 0..<scale {
                    for dx in 0..<scale {
                        let px = atX + sx * scale + dx
                        let py = atY + sy * scale + dy
                        if px >= 0 && px < bufferWidth && py >= 0 && py < bufferHeight {
                            buffer[py * bufferWidth + px] = opaque
                        }
                    }
                }
            }
        }
    }

    private func makeTerrainTextureBuffer(index: Int, spriteID: Int, sprite: GameSprite) -> TerrainTextureBuffer {
        let length = sprite.width * sprite.height
        var histogram = [Int](repeating: 0, count: 32768)
        var sourceRGB = [UInt32](repeating: 0, count: length)

        for i in 0..<length {
            var rgb = UInt32(bitPattern: sprite.pixels[i]) & 0x00FF_FFFF
            if rgb == 0 { rgb = 0x00FF_00FF }
            sourceRGB[i] = rgb
            histogram[quantizedIndex(rgb)] += 1
        }

        var palette = [Int32](repeating: 0, count: 256)
        var frequency = [Int](repeating: 0, count: 256)
        palette[0] = opaque(0x00FF_00FF)

        for q in 0..<histogram.count {
            let count = histogram[q]
            if count > frequency[255] {
                for slot in 1..<256 where count > frequency[slot] {
                    if slot < 255 {
                        for move in stride(from: 255, to: slot, by: -1) {
                            palette[move] = palette[move - 1]
                            frequency[move] = frequency[move - 1]
                        }
                    }

                    let red = (q & 0x7C00) << 9
                    let green = (q & 0x03E0) << 6
                    let blue = (q & 0x001F) << 3
                    let rgb = UInt32(red + green + blue + 0x040404)
                    palette[slot] = opaque(rgb & 0x00FF_FFFF)
                    frequency[slot] = count
                    break
                }
            }
            histogram[q] = -1
        }

        var indexed = [UInt8](repeating: 0, count: length)
        var expanded = [Int32](repeating: 0, count: length)

        for i in 0..<length {
            let rgb = sourceRGB[i]
            let q = quantizedIndex(rgb)
            var paletteIndex = histogram[q]

            if paletteIndex == -1 {
                var bestDistance = Int.max
                var bestIndex = 0
                let r = Int((rgb >> 16) & 0xFF)
                let g = Int((rgb >> 8) & 0xFF)
                let b = Int(rgb & 0xFF)

                for candidate in 0..<256 {
                    let pal = UInt32(bitPattern: palette[candidate]) & 0x00FF_FFFF
                    let pr = Int((pal >> 16) & 0xFF)
                    let pg = Int((pal >> 8) & 0xFF)
                    let pb = Int(pal & 0xFF)
                    let dr = r - pr
                    let dg = g - pg
                    let db = b - pb
                    let distance = dr * dr + dg * dg + db * db
                    if distance < bestDistance {
                        bestDistance = distance
                        bestIndex = candidate
                    }
                }

                paletteIndex = bestIndex
                histogram[q] = bestIndex
            }

            let safeIndex = max(0, min(255, paletteIndex))
            indexed[i] = UInt8(safeIndex)
            expanded[i] = palette[safeIndex]
        }

        let type = max(0, sprite.authenticWidth / 64 - 1)
        return TerrainTextureBuffer(
            index: index,
            spriteID: spriteID,
            width: sprite.width,
            height: sprite.height,
            pixels: expanded,
            palette: palette,
            indices: Data(indexed),
            type: type
        )
    }

    private func quantizedIndex(_ rgb: UInt32) -> Int {
        Int(((rgb & 0x00F8_0000) >> 9) | ((rgb & 0x0000_F800) >> 6) | ((rgb & 0x0000_00F8) >> 3))
    }

    private func opaque(_ rgb: UInt32) -> Int32 {
        Int32(bitPattern: 0xFF00_0000 | (rgb & 0x00FF_FFFF))
    }
}
