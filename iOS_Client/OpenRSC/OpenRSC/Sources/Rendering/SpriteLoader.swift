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

class SpriteLoader: @unchecked Sendable {
    internal(set) var sprites: [Int: GameSprite] = [:]
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
}
