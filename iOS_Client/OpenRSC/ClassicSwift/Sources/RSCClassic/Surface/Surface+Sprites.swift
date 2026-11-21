// Sprite loading, conversion and drawing from rsc-c's surface.c.

import Foundation

public enum SpriteError: Error {
    case badTGA(String)
}

extension Surface {
    // MARK: - Loading

    /// Loads one or more frames from a Jagex .dat sprite file plus index.dat.
    public func parseSprite(id spriteId: Int, spriteData: [UInt8], indexData: [UInt8], frameCount: Int) {
        func u16(_ d: [UInt8], _ o: Int) -> Int { Int(d[o]) << 8 | Int(d[o + 1]) }

        var indexOffset = u16(spriteData, 0)
        let fullWidth = u16(indexData, indexOffset); indexOffset += 2
        let fullHeight = u16(indexData, indexOffset); indexOffset += 2
        let colourCount = Int(indexData[indexOffset]); indexOffset += 1

        var colours = [Int32](repeating: 0, count: 256)
        colours[0] = Colour.magenta
        var i = 0
        while i < colourCount - 1 {
            colours[i + 1] = Int32(indexData[indexOffset]) << 16 | Int32(indexData[indexOffset + 1]) << 8 | Int32(indexData[indexOffset + 2])
            indexOffset += 3
            i += 1
        }

        var spriteOffset = 2
        for id in spriteId..<(spriteId + frameCount) {
            spriteTranslateX[id] = Int(indexData[indexOffset]); indexOffset += 1
            spriteTranslateY[id] = Int(indexData[indexOffset]); indexOffset += 1
            spriteWidth[id] = Int(Int16(truncatingIfNeeded: u16(indexData, indexOffset))); indexOffset += 2
            spriteHeight[id] = Int(Int16(truncatingIfNeeded: u16(indexData, indexOffset))); indexOffset += 2
            let type = indexData[indexOffset]; indexOffset += 1
            let w = spriteWidth[id], h = spriteHeight[id]
            let area = w * h

            var data = [UInt8](repeating: 0, count: area)
            spriteWidthFull[id] = fullWidth
            spriteHeightFull[id] = fullHeight
            spritePixels[id] = nil
            var translate = spriteTranslateX[id] != 0 || spriteTranslateY[id] != 0

            if type == 0 {
                for j in 0..<area {
                    data[j] = spriteData[spriteOffset]; spriteOffset += 1
                    if data[j] == 0 { translate = true }
                }
            } else if type == 1 {
                for x in 0..<w {
                    for y in 0..<h {
                        let index = x + y * w
                        data[index] = spriteData[spriteOffset]; spriteOffset += 1
                        if data[index] == 0 { translate = true }
                    }
                }
            }

            spriteTranslate[id] = translate
            spriteColours[id] = data
            // C copies colour_count entries; indices past that read zeroed memory.
            var palette = [Int32](repeating: 0, count: 256)
            for k in 0..<colourCount { palette[k] = colours[k] }
            spritePalette[id] = palette
        }
    }

    /// Loads an 8-bit colour-mapped TGA (custom media versions), optionally split into frames.
    public func parseSpriteTGA(id spriteId: Int, data buffer: [UInt8], columns: Int, rows: Int) throws {
        var offset = 0
        func u8() -> Int { defer { offset += 1 }; return Int(buffer[offset]) }
        func u16le() -> Int { defer { offset += 2 }; return Int(buffer[offset]) | Int(buffer[offset + 1]) << 8 }

        let imageIdLength = u8()
        guard u8() == 1 else { throw SpriteError.badTGA("colour map type") }
        let imageType = u8()
        guard imageType == 1 || imageType == 9 else { throw SpriteError.badTGA("image type") }
        guard u16le() == 0 else { throw SpriteError.badTGA("colour map start") }
        let colourMapLength = u16le()
        guard u8() == 24 else { throw SpriteError.badTGA("colour map bpp") }
        guard u16le() == 0, u16le() == 0 else { throw SpriteError.badTGA("origin") }
        let w = u16le()
        let h = u16le()
        guard u8() == 8 else { throw SpriteError.badTGA("bpp") }
        _ = u8()
        offset += imageIdLength

        var map = [Int32](repeating: 0, count: max(colourMapLength + 1, 256))
        for i in 0..<colourMapLength {
            let b = Int32(buffer[offset]), g = Int32(buffer[offset + 1]), r = Int32(buffer[offset + 2])
            offset += 3
            map[i] = (r << 16) + (g << 8) + b
            if map[i] == 0 { map[i] = 1 }
        }

        let fullSize = w * h
        var px = [UInt8](repeating: 0, count: fullSize)
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in 0..<w { px[y * w + x] = buffer[offset + x] }
            offset += w
        }

        if map[0] != Colour.magenta {
            var magentaIndex = 255
            for i in 1..<max(colourMapLength, 1) where map[i] == Colour.magenta {
                magentaIndex = i
                break
            }
            for i in 0..<fullSize {
                if map[Int(px[i])] == Colour.magenta { px[i] = 0; continue }
                if px[i] == 0 { px[i] = UInt8(magentaIndex) }
            }
            map[magentaIndex] = map[0]
            map[0] = Colour.magenta
        }

        func store(_ id: Int, _ colours: [UInt8], _ fw: Int, _ fh: Int) {
            spritePixels[id] = nil
            spriteColours[id] = colours
            spriteTranslate[id] = true
            spriteTranslateX[id] = 0
            spriteTranslateY[id] = 0
            spritePalette[id] = map
            spriteWidth[id] = fw
            spriteHeight[id] = fh
            spriteWidthFull[id] = fw
            spriteHeightFull[id] = fh
        }

        if rows <= 1 && columns <= 1 {
            store(spriteId, px, w, h)
            return
        }
        let frameWidth = w / columns
        let frameHeight = h / rows
        var id = spriteId
        for y in 0..<rows {
            for x in 0..<columns {
                var frame = [UInt8](repeating: 0, count: frameWidth * frameHeight)
                for i in 0..<frameHeight {
                    let src = x * frameWidth + (y * frameHeight + i) * w
                    for k in 0..<frameWidth { frame[i * frameWidth + k] = px[src + k] }
                }
                store(id, frame, frameWidth, frameHeight)
                id += 1
            }
        }
    }

    /// Decodes the run-length sleep-word image sent by the server.
    public func readSleepWord(id: Int, data: [UInt8]) {
        let w = Surface.sleepWidth, h = Surface.sleepHeight
        var px = [Int32](repeating: 0, count: w * h)
        spriteWidth[id] = w
        spriteHeight[id] = h
        spriteTranslateX[id] = 0
        spriteTranslateY[id] = 0
        spriteWidthFull[id] = w
        spriteHeightFull[id] = h
        spriteTranslate[id] = false

        var colour: Int32 = 0
        var packetOffset = 1
        var pixelIndex = 0
        while pixelIndex < w {
            let length = Int(data[packetOffset]); packetOffset += 1
            for _ in 0..<length { px[pixelIndex] = colour; pixelIndex += 1 }
            colour = Colour.white - colour
        }
        for _ in 1..<h {
            var x = 0
            while x < w {
                let length = Int(data[packetOffset]); packetOffset += 1
                for _ in 0..<length {
                    px[pixelIndex] = px[pixelIndex - w]
                    pixelIndex += 1
                    x += 1
                }
                if x < w {
                    px[pixelIndex] = Colour.white - px[pixelIndex - w]
                    pixelIndex += 1
                    x += 1
                }
            }
        }
        spritePixels[id] = px
    }

    /// Quantises a 32-bit sprite down to a 256-colour palette sprite.
    public func screenRasterToPaletteSprite(id: Int) {
        let size = spriteWidth[id] * spriteHeight[id]
        guard let src = spritePixels[id] else { return }

        func bucket(_ c: Int32) -> Int {
            let r: Int32 = (c & 0xf80000) >> 9
            let g: Int32 = (c & 0xf800) >> 6
            let b: Int32 = (c & 0xf8) >> 3
            return Int(r + g + b)
        }

        for i in 0..<size { texturePixels[bucket(src[i])] &+= 1 }

        var palette = [Int32](repeating: 0, count: 256)
        palette[0] = Colour.magenta
        var counts = [Int32](repeating: 0, count: 256)

        for i in 0..<32768 {
            let pixel = texturePixels[i]
            if pixel > counts[255] {
                for j in 1..<256 where pixel > counts[j] {
                    var k = 255
                    while k > j {
                        palette[k] = palette[k - 1]
                        counts[k] = counts[k - 1]
                        k -= 1
                    }
                    let ii = Int32(i)
                    let rBits: Int32 = (ii & 0x7c00) << 9
                    let gBits: Int32 = (ii & 0x3e0) << 6
                    let bBits: Int32 = (ii & 0x1f) << 3
                    palette[j] = rBits + gBits + bBits + 0x40404
                    counts[j] = pixel
                    break
                }
            }
            texturePixels[i] = -1
        }

        var colours = [UInt8](repeating: 0, count: size)
        for i in 0..<size {
            let c = src[i]
            let b = bucket(c)
            var tp = Int(texturePixels[b])
            if tp == -1 {
                var best = 999_999_999
                let r = Int((c >> 16) & 0xff), g = Int((c >> 8) & 0xff), bl = Int(c & 0xff)
                for j in 0..<256 {
                    let p = palette[j]
                    let pr = Int((p >> 16) & 0xff), pg = Int((p >> 8) & 0xff), pb = Int(p & 0xff)
                    let d = (r - pr) * (r - pr) + (g - pg) * (g - pg) + (bl - pb) * (bl - pb)
                    if d < best { best = d; tp = j }
                }
                texturePixels[b] = Int32(tp)
            }
            colours[i] = UInt8(truncatingIfNeeded: tp)
        }

        spriteColours[id] = colours
        spritePalette[id] = palette
        spritePixels[id] = nil
    }

    /// Expands a palette sprite to 32-bit (black becomes 1, magenta becomes transparent 0).
    public func paletteSpriteToRaster(id: Int, addAlpha: Bool = false) -> [Int32]? {
        guard let colours = spriteColours[id], let palette = spritePalette[id] else { return nil }
        let area = spriteWidth[id] * spriteHeight[id]
        var out = [Int32](repeating: 0, count: area)
        for i in 0..<area {
            var c = palette[Int(colours[i])]
            if c == 0 {
                c = 1
            } else if c == Colour.magenta {
                c = 0
            }
            if addAlpha && c != 0 { c = c &+ Int32(bitPattern: 0xff000000) }
            out[i] = c
        }
        return out
    }

    public func loadSprite(id: Int) {
        spritePixels[id] = paletteSpriteToRaster(id: id)
        spriteColours[id] = nil
    }

    public func screenRasterToSprite(id: Int, x: Int, y: Int, width w: Int, height h: Int) {
        setRasterSprite(id: id, w, h)
        var px = [Int32](repeating: 0, count: w * h)
        var i = 0
        for yy in y..<(y + h) {
            for xx in x..<(x + w) {
                px[i] = pixels[xx + yy * width]
                i += 1
            }
        }
        spritePixels[id] = px
    }

    /// Copies a screen region column by column (surface_draw_sprite_reversed).
    public func drawSpriteReversed(id: Int, x: Int, y: Int, width w: Int, height h: Int) {
        setRasterSprite(id: id, w, h)
        var px = [Int32](repeating: 0, count: w * h)
        var i = 0
        for xx in x..<(x + w) {
            for yy in y..<(y + h) {
                px[i] = pixels[xx + yy * width]
                i += 1
            }
        }
        spritePixels[id] = px
    }

    private func setRasterSprite(id: Int, _ w: Int, _ h: Int) {
        spriteWidth[id] = w
        spriteHeight[id] = h
        spriteTranslate[id] = false
        spriteTranslateX[id] = 0
        spriteTranslateY[id] = 0
        spriteWidthFull[id] = w
        spriteHeightFull[id] = h
        spriteColours[id] = nil
        spritePalette[id] = nil
    }

    // MARK: - Drawing

    public func drawSprite(x: Int, y: Int, id: Int) {
        var x = x, y = y
        if spriteTranslate[id] {
            x += spriteTranslateX[id]
            y += spriteTranslateY[id]
        }
        var destPos = x + y * width
        var srcPos = 0
        var w = spriteWidth[id]
        var h = spriteHeight[id]
        var destOffset = width - w
        var srcOffset = 0

        if y < boundsMinY {
            let clip = boundsMinY - y
            h -= clip; y = boundsMinY
            srcPos += clip * w
            destPos += clip * width
        }
        if y + h >= boundsMaxY { h -= y + h - boundsMaxY + 1 }
        if x < boundsMinX {
            let clip = boundsMinX - x
            w -= clip; x = boundsMinX
            srcPos += clip; destPos += clip
            srcOffset += clip; destOffset += clip
        }
        if x + w >= boundsMaxX {
            let clip = x + w - boundsMaxX + 1
            w -= clip
            srcOffset += clip; destOffset += clip
        }
        if w <= 0 || h <= 0 { return }

        var yInc = 1
        if interlace {
            yInc = 2
            destOffset += width
            srcOffset += spriteWidth[id]
            if y & 1 != 0 { destPos += width; h -= 1 }
        }

        if let src = spritePixels[id] {
            src.withUnsafeBufferPointer { s in
                for _ in stride(from: -h, to: 0, by: yInc) {
                    for _ in 0..<w {
                        let c = s[srcPos]; srcPos += 1
                        if c != 0 { pixels[destPos] = c }
                        destPos += 1
                    }
                    destPos += destOffset
                    srcPos += srcOffset
                }
            }
        } else if let colours = spriteColours[id], let palette = spritePalette[id] {
            for _ in stride(from: -h, to: 0, by: yInc) {
                for _ in 0..<w {
                    let index = colours[srcPos]; srcPos += 1
                    if index != 0 { pixels[destPos] = palette[Int(index)] }
                    destPos += 1
                }
                destPos += destOffset
                srcPos += srcOffset
            }
        }
    }

    /// Shared translate/scale setup for the scaled draw functions.
    private func scaledSetup(_ id: Int, _ x: inout Int, _ y: inout Int, _ w: inout Int, _ h: inout Int)
        -> (srcX: Int, srcY: Int, stepX: Int, stepY: Int) {
        var srcX = 0, srcY = 0
        var stepX = (spriteWidth[id] << 16) / w
        var stepY = (spriteHeight[id] << 16) / h
        if spriteTranslate[id] {
            let fw = spriteWidthFull[id], fh = spriteHeightFull[id]
            stepX = (fw << 16) / w
            stepY = (fh << 16) / h
            let tx = spriteTranslateX[id], ty = spriteTranslateY[id]
            x += (tx * w + fw - 1) / fw
            y += (ty * h + fh - 1) / fh
            if (tx * w) % fw != 0 { srcX = ((fw - ((tx * w) % fw)) << 16) / w }
            if (ty * h) % fh != 0 { srcY = ((fh - ((ty * h) % fh)) << 16) / h }
            w = (w * (spriteWidth[id] - (srcX >> 16))) / fw
            h = (h * (spriteHeight[id] - (srcY >> 16))) / fh
        }
        return (srcX, srcY, stepX, stepY)
    }

    /// Scaled clipping as in C. Note the C code resets x/y to 0 (not the bound) when clipping.
    private func scaledClip(_ x: inout Int, _ y: inout Int, _ w: inout Int, _ h: inout Int,
                            _ srcX: inout Int, _ srcY: inout Int, stepX: Int, stepY: inout Int)
        -> (destPos: Int, destOffset: Int, yInc: Int) {
        var destPos = x + y * width
        var destOffset = width - w
        if y < boundsMinY {
            let clip = boundsMinY - y
            h -= clip; y = 0
            destPos += clip * width
            srcY += stepY * clip
        }
        if y + h >= boundsMaxY { h -= y + h - boundsMaxY + 1 }
        if x < boundsMinX {
            let clip = boundsMinX - x
            w -= clip; x = 0
            destPos += clip
            srcX += stepX * clip
            destOffset += clip
        }
        if x + w >= boundsMaxX {
            let clip = x + w - boundsMaxX + 1
            w -= clip
            destOffset += clip
        }
        var yInc = 1
        if interlace {
            yInc = 2
            destOffset += width
            stepY += stepY
            if y & 1 != 0 { destPos += width; h -= 1 }
        }
        return (destPos, destOffset, yInc)
    }

    public func drawSpriteScale(x: Int, y: Int, width w: Int, height h: Int, id: Int) {
        var x = x, y = y, w = w, h = h
        let spriteW = spriteWidth[id]
        var (srcX, srcY, stepX, stepY) = scaledSetup(id, &x, &y, &w, &h)
        var (destPos, destOffset, yInc) = scaledClip(&x, &y, &w, &h, &srcX, &srcY, stepX: stepX, stepY: &stepY)
        guard let src = spritePixels[id] else { return }
        let startX = srcX
        for _ in stride(from: -h, to: 0, by: yInc) {
            let row = (srcY >> 16) * spriteW
            for _ in stride(from: -w, to: 0, by: 1) {
                let c = src[(srcX >> 16) + row]
                if c != 0 { pixels[destPos] = c }
                destPos += 1
                srcX += stepX
            }
            srcY += stepY
            srcX = startX
            destPos += destOffset
        }
    }

    public func drawEntitySprite(x: Int, y: Int, width w: Int, height h: Int, id: Int, tx: Int, ty: Int) {
        if id >= 50000 {
            host?.drawMagicBubble(x: x, y: y, width: w, height: h, id: id - 50000)
        } else if id >= 40000 {
            host?.drawGroundItem(x: x, y: y, width: w, height: h, id: id - 40000)
        } else if id >= 20000 {
            host?.drawNpc(x: x, y: y, width: w, height: h, id: id - 20000, tx: tx, ty: ty)
        } else if id >= 5000 {
            host?.drawPlayer(x: x, y: y, width: w, height: h, id: id - 5000, tx: tx, ty: ty)
        } else {
            drawSpriteScale(x: x, y: y, width: w, height: h, id: id)
        }
    }

    @inline(__always)
    static func blendAlpha(_ background: Int32, _ colour: Int32, _ alpha: Int32) -> Int32 {
        let backgroundAlpha = 256 &- alpha
        return (((colour & 0xff00ff) &* alpha &+ (background & 0xff00ff) &* backgroundAlpha) & -0xff0100
            &+ (((colour & 0x00ff00) &* alpha &+ (background & 0x00ff00) &* backgroundAlpha) & 0xff0000)) >> 8
    }

    public func drawSpriteAlpha(x: Int, y: Int, id: Int, alpha: Int) {
        var x = x, y = y
        if spriteTranslate[id] {
            x += spriteTranslateX[id]
            y += spriteTranslateY[id]
        }
        var destPos = x + y * width
        var srcPos = 0
        var h = spriteHeight[id]
        var w = spriteWidth[id]
        var destOffset = width - w
        var srcOffset = 0

        if y < boundsMinY {
            let clip = boundsMinY - y
            h -= clip; y = boundsMinY
            srcPos += clip * w
            destPos += clip * width
        }
        if y + h >= boundsMaxY { h -= y + h - boundsMaxY + 1 }
        if x < boundsMinX {
            let clip = boundsMinX - x
            w -= clip; x = boundsMinX
            srcPos += clip; destPos += clip
            srcOffset += clip; destOffset += clip
        }
        if x + w >= boundsMaxX {
            let clip = x + w - boundsMaxX + 1
            w -= clip
            srcOffset += clip; destOffset += clip
        }
        if w <= 0 || h <= 0 { return }

        var yInc = 1
        if interlace {
            yInc = 2
            destOffset += width
            srcOffset += spriteWidth[id]
            if y & 1 != 0 { destPos += width; h -= 1 }
        }

        let a = Int32(truncatingIfNeeded: alpha)
        if let src = spritePixels[id] {
            for _ in stride(from: -h, to: 0, by: yInc) {
                for _ in 0..<w {
                    let c = src[srcPos]; srcPos += 1
                    if c != 0 { pixels[destPos] = Surface.blendAlpha(pixels[destPos], c, a) }
                    destPos += 1
                }
                destPos += destOffset
                srcPos += srcOffset
            }
        } else if let colours = spriteColours[id], let palette = spritePalette[id] {
            for _ in stride(from: -h, to: 0, by: yInc) {
                for _ in 0..<w {
                    let index = colours[srcPos]; srcPos += 1
                    if index != 0 {
                        pixels[destPos] = Surface.blendAlpha(pixels[destPos], palette[Int(index)], a)
                    }
                    destPos += 1
                }
                destPos += destOffset
                srcPos += srcOffset
            }
        }
    }

    /// Only works with 32-bit (non-palette) sprites, like the C version.
    public func drawSpriteScaleAlpha(x: Int, y: Int, width w: Int, height h: Int, id: Int, alpha: Int) {
        var x = x, y = y, w = w, h = h
        let spriteW = spriteWidth[id]
        var (srcX, srcY, stepX, stepY) = scaledSetup(id, &x, &y, &w, &h)
        var (destPos, destOffset, yInc) = scaledClip(&x, &y, &w, &h, &srcX, &srcY, stepX: stepX, stepY: &stepY)
        guard let src = spritePixels[id] else { return }
        let a = Int32(truncatingIfNeeded: alpha)
        let startX = srcX
        for _ in stride(from: -h, to: 0, by: yInc) {
            let row = (srcY >> 16) * spriteW
            for _ in stride(from: -w, to: 0, by: 1) {
                let c = src[(srcX >> 16) + row]
                if c != 0 { pixels[destPos] = Surface.blendAlpha(pixels[destPos], c, a) }
                destPos += 1
                srcX += stepX
            }
            srcY += stepY
            srcX = startX
            destPos += destOffset
        }
    }

    /// Only works with 32-bit sprites: grey pixels are tinted by `colour`.
    public func drawSpriteScaleMask(x: Int, y: Int, width w: Int, height h: Int, id: Int, colour: Int32) {
        var x = x, y = y, w = w, h = h
        let spriteW = spriteWidth[id]
        var (srcX, srcY, stepX, stepY) = scaledSetup(id, &x, &y, &w, &h)
        var (destPos, destOffset, yInc) = scaledClip(&x, &y, &w, &h, &srcX, &srcY, stepX: stepX, stepY: &stepY)
        guard let src = spritePixels[id] else { return }
        let m = Int(colour)
        let mr = (m >> 16) & 0xff, mg = (m >> 8) & 0xff, mb = m & 0xff
        let startX = srcX
        for _ in stride(from: -h, to: 0, by: yInc) {
            let row = (srcY >> 16) * spriteW
            for _ in stride(from: -w, to: 0, by: 1) {
                let c = src[(srcX >> 16) + row]
                if c != 0 {
                    let ci = Int(c)
                    let r = (ci >> 16) & 0xff, g = (ci >> 8) & 0xff, b = ci & 0xff
                    if r == g && g == b {
                        pixels[destPos] = Int32(truncatingIfNeeded: (((r * mr) >> 8) << 16) + (((g * mg) >> 8) << 8) + ((b * mb) >> 8))
                    } else {
                        pixels[destPos] = c
                    }
                }
                destPos += 1
                srcX += stepX
            }
            srcY += stepY
            srcX = startX
            destPos += destOffset
        }
    }
}
