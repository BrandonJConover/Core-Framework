// Port of Client_Base/src/orsc/graphics/two/GraphicsController.java
// Rasterization subset only — no font/menu/panel drawing.

import Foundation

// MARK: - Sprite

struct Sprite {
    var pixels: [Int32]
    var width: Int32
    var height: Int32
    var cropX: Int32   // analogous to Java xShift / getSomething1
    var cropY: Int32   // analogous to Java yShift / getSomething2

    init(pixels: [Int32] = [], width: Int32 = 0, height: Int32 = 0,
         cropX: Int32 = 0, cropY: Int32 = 0) {
        self.pixels = pixels
        self.width  = width
        self.height = height
        self.cropX  = cropX
        self.cropY  = cropY
    }
}

// MARK: - GraphicsController

final class GraphicsController {

    // MARK: Constants

    static let gameWidth:  Int32 = 512
    static let gameHeight: Int32 = 334

    // MARK: State fields

    /// The framebuffer — packed 0x00RRGGBB (black = 0)
    var pixelData: [Int32]

    /// Canvas dimensions
    var width2:  Int32
    var height2: Int32

    /// Scissor / clip rectangle
    var clipLeft:   Int32
    var clipTop:    Int32
    var clipRight:  Int32
    var clipBottom: Int32

    /// Sprite atlas (entries may be nil / unloaded)
    var sprites: [Sprite?]

    /// Interlaced-render flag (mirrors Java `interlace`)
    var interlace: Bool = false

    // MARK: - Initialiser

    /// Mirrors `GraphicsController(int width, int height, int spriteCount)`
    init(width: Int32, height: Int32, spriteCount: Int = 0) {
        self.width2      = width
        self.height2     = height
        self.clipLeft    = 0
        self.clipTop     = 0
        self.clipRight   = width
        self.clipBottom  = height
        self.pixelData   = [Int32](repeating: 0, count: Int(width * height))
        self.sprites     = [Sprite?](repeating: nil, count: spriteCount)
    }

    // MARK: - Clip helpers

    /// Resets clip rect to the full canvas.
    func clearClip() {
        // For a class, properties are reference-mutable without 'mutating'
        // but the compiler sees them as let captures inside a non-mutating func;
        // use an explicit cast via the stored properties directly.
        clipLeft   = 0
        clipTop    = 0
        clipRight  = width2
        clipBottom = height2
    }

    /// Sets clip rect, clamped to canvas bounds.
    func setClip(clipLeft: Int32, clipRight: Int32, clipBottom: Int32, clipTop: Int32) {
        var cl = clipLeft;   if cl < 0          { cl = 0 }
        var cr = clipRight;  if cr > width2      { cr = width2 }
        var ct = clipTop;    if ct < 0           { ct = 0 }
        var cb = clipBottom; if cb > height2     { cb = height2 }
        self.clipLeft   = cl
        self.clipRight  = cr
        self.clipTop    = ct
        self.clipBottom = cb
    }

    // MARK: - blackScreen

    /// Fills the entire framebuffer with 0 (black).
    /// Mirrors `blackScreen(boolean)` — always does the full fill (non-interlaced path).
    func blackScreen() {
        let total = Int(height2 * width2)
        pixelData.withUnsafeMutableBufferPointer { buf in
            for i in 0 ..< total {
                buf[i] = 0
            }
        }
    }

    // MARK: - drawLineHoriz

    /// Draws a horizontal line.
    /// Mirrors `drawLineHoriz(int x, int y, int width, int color)`.
    func drawLineHoriz(x: Int32, y: Int32, width: Int32, rgb: Int32) {
        guard clipTop <= y && y < clipBottom else { return }

        var lx = x
        var lw = width

        if clipLeft > lx {
            lw -= clipLeft - lx
            lx  = clipLeft
        }
        if lx + lw > clipRight {
            lw = clipRight - lx
        }
        guard lw > 0 else { return }

        let offset = Int(lx + width2 * y)
        pixelData.withUnsafeMutableBufferPointer { buf in
            for xi in 0 ..< Int(lw) {
                buf[offset + xi] = rgb
            }
        }
    }

    // MARK: - drawLineVert

    /// Draws a vertical line.
    /// Mirrors `drawLineVert(int x, int y, int color, int height)`.
    func drawLineVert(x: Int32, y: Int32, height: Int32, rgb: Int32) {
        guard clipLeft <= x && x < clipRight else { return }

        var ly = y
        var lh = height

        if ly < clipTop {
            lh -= clipTop - ly
            ly  = clipTop
        }
        if ly + lh > clipBottom {
            lh = clipBottom - ly
        }
        guard lh > 0 else { return }

        let pxOffset = Int(x + width2 * ly)
        let stride   = Int(width2)
        pixelData.withUnsafeMutableBufferPointer { buf in
            for i in 0 ..< Int(lh) {
                buf[pxOffset + stride * i] = rgb
            }
        }
    }

    // MARK: - drawBox

    /// Draws a filled (opaque) axis-aligned rectangle.
    /// Mirrors `drawBox(int xr, int yr, int widthh, int height, int color)`.
    func drawBox(x: Int32, y: Int32, width: Int32, height: Int32, rgb: Int32) {
        var xr = x;   var yr = y
        var w  = width; var h  = height

        if xr < clipLeft   { w  -= clipLeft - xr; xr = clipLeft }
        if yr < clipTop    { h  -= clipTop  - yr; yr = clipTop  }
        if yr + h > clipBottom { h = clipBottom - yr }
        if xr + w > clipRight  { w = clipRight  - xr }

        guard w > 0 && h > 0 else { return }

        var lineSkip: Int32 = width2 - w
        var yStep:    Int32 = 1

        if interlace {
            lineSkip += width2
            if (yr & 1) != 0 { h -= 1; yr += 1 }
            yStep = 2
        }

        var pxHead = Int(xr + width2 * yr)
        let skip   = Int(lineSkip)
        let cols   = Int(w)

        pixelData.withUnsafeMutableBufferPointer { buf in
            var yi: Int32 = -h
            while yi < 0 {
                for _ in 0 ..< cols {
                    buf[pxHead] = rgb
                    pxHead += 1
                }
                pxHead += skip
                yi += yStep
            }
        }
    }

    // MARK: - drawBoxAlpha

    /// Draws an alpha-blended filled rectangle.
    /// Mirrors `drawBoxAlpha(int x, int y, int width, int height, int color, int alpha)`.
    /// `alpha` is in [0, 256] where 256 = fully opaque.
    func drawBoxAlpha(x: Int32, y: Int32, width: Int32, height: Int32, rgb: Int32, alpha: Int32) {
        var lx = x;  var ly = y
        var lw = width; var lh = height

        if ly < clipTop    { lh -= clipTop  - ly; ly = clipTop  }
        if clipLeft > lx   { lw -= clipLeft - lx; lx = clipLeft }
        if clipRight  < lx + lw { lw = clipRight  - lx }
        if clipBottom < lh + ly { lh = clipBottom - ly }

        guard lw > 0 && lh > 0 else { return }

        let mixOld: Int32 = 256 - alpha
        // Pre-multiplied source components (mirrors Java)
        let n3 = alpha * ((rgb >> 16) & 0xFF)       // red
        let n2 = ((rgb & 0x0000FF00) >> 8) * alpha  // green
        let n1 = alpha * (rgb & 0xFF)               // blue

        var lineStride: Int32 = width2 - lw
        var yStep: Int32 = 1

        if interlace {
            if (ly & 1) != 0 { lh -= 1; ly += 1 }
            lineStride += width2
            yStep = 2
        }

        var pxi = Int(lx + width2 * ly)
        let stride = Int(lineStride)
        let cols   = Int(lw)

        pixelData.withUnsafeMutableBufferPointer { buf in
            var yi: Int32 = 0
            while yi < lh {
                for _ in 0 ..< cols {
                    let old = buf[pxi]
                    let o1 = mixOld * (old & 0xFF)
                    let o3 = mixOld * ((0x00FF0000 & old) >> 16)
                    let o2 = mixOld * ((0x0000FF00 & old) >> 8)
                    let result = ((o1 + n1) >> 8) | (((o2 + n2) >> 8) << 8) | (((n3 + o3) >> 8) << 16)
                    buf[pxi] = result
                    pxi += 1
                }
                pxi += stride
                yi  += yStep
            }
        }
    }

    // MARK: - plot_tran_scale (inner rasterizer)

    /// Scaled sprite blit with per-pixel alpha blending; black (0) is transparent.
    /// Mirrors `plot_tran_scale(int heightStep, int srcStartY, int destWidth,
    ///   byte dummy1, int scaleY, int spriteWidth, int scaleX, int height,
    ///   int destHead, int[] src, int dummy2, int srcStartX,
    ///   int destRowStride, int alpha, int[] dest)`.
    ///
    /// - Parameters:
    ///   - heightStep:    destination-height divisor (1 or 2 for interlace)
    ///   - srcStartY:     first source row << 16
    ///   - destWidth:     destination column count
    ///   - scaleY:        source rows per destination row << 16
    ///   - spriteWidth:   source pixel data row stride
    ///   - scaleX:        source columns per destination column << 16
    ///   - height:        destination height * heightStep
    ///   - destHead:      starting index into pixelData
    ///   - src:           source pixel array
    ///   - srcStartX:     first source column << 16
    ///   - destRowStride: pixels to skip between output rows
    ///   - alpha:         opacity [0-256]
    func plot_tran_scale(heightStep: Int32, srcStartY: Int32, destWidth: Int32,
                         scaleY: Int32, spriteWidth: Int32, scaleX: Int32,
                         height: Int32, destHead: Int32,
                         src: [Int32], srcStartX: Int32,
                         destRowStride: Int32, alpha: Int32) {
        let alphaInverse: Int32 = 256 - alpha

        var srcY      = srcStartY
        var dstHead   = Int(destHead)
        let rowStride = Int(destRowStride)
        let srcW      = Int(spriteWidth)

        pixelData.withUnsafeMutableBufferPointer { dstBuf in
            src.withUnsafeBufferPointer { srcBuf in
                var i: Int32 = -height
                while i < 0 {
                    let rowOffset = Int(srcY >> 16) * srcW
                    srcY += scaleY

                    var srcX = srcStartX
                    var j: Int32 = -destWidth
                    while j < 0 {
                        let newColor = srcBuf[rowOffset + Int(srcX >> 16)]
                        srcX += scaleX
                        if newColor == 0 {
                            dstHead += 1
                        } else {
                            let oldColor = dstBuf[dstHead]
                            // Mirrors Java:
                            // bitwiseAnd(bitwiseAnd(0xFF00,old)*alphaInv + bitwiseAnd(0xFF00,new)*alpha, 0xFF0000)
                            // + bitwiseAnd(bitwiseAnd(new,0xFF00FF)*alpha + alphaInv*bitwiseAnd(0xFF00FF,old), -16711936) >> 8
                            let greenBlend = (((oldColor & 0x0000FF00) &* alphaInverse) &+
                                              ((newColor & 0x0000FF00) &* alpha)) & 0x00FF0000
                            let rbBlend    = (((newColor & 0x00FF00FF) &* alpha) &+
                                              (alphaInverse &* (oldColor & 0x00FF00FF))) & Int32(bitPattern: 0xFF00FF00)
                            dstBuf[dstHead] = (greenBlend | rbBlend) >> 8
                            dstHead += 1
                        }
                        j += 1
                    }

                    dstHead += rowStride
                    i += heightStep
                }
            }
        }
    }

    // MARK: - spriteClipping

    /// Scaled sprite blit (alpha-blended) matching the Java `spriteClipping` that
    /// draws `Sprite sprite` at destination rectangle `(dstX, dstY, destWidth, destHeight)`.
    /// The original Java signature (non-shift path):
    ///   `spriteClipping(Sprite sprite, byte var2, int height, int var4,
    ///                   int width, int var6, int alpha)`
    /// where var4=dstX, var6=dstY.
    func spriteClipping(sprite: Sprite, dstX: Int32, dstY: Int32,
                        destWidth: Int32, destHeight: Int32,
                        alpha: Int32) {
        let sprW = sprite.width
        let sprH = sprite.height
        guard sprW > 0 && sprH > 0 && destWidth > 0 && destHeight > 0 else { return }

        let scaleX: Int32 = (sprW << 16) / destWidth
        var scaleY: Int32 = (sprH << 16) / destHeight
        var srcStartX: Int32 = 0  // var10
        var srcStartY: Int32 = 0  // var11
        var var4    = dstX
        var var6    = dstY
        var width   = destWidth
        var height  = destHeight

        // Destination base pixel index
        var var14: Int32 = var6 * width2 + var4
        var var16: Int32

        // Clip top
        if clipTop > var6 {
            var16    = clipTop - var6
            height  -= var16
            var6     = 0
            var14   += width2 * var16
            srcStartY += scaleY * var16
        }

        var rowStride: Int32 = width2 - width

        // Clip left
        if var4 < clipLeft {
            var16      = clipLeft - var4
            var4       = 0
            srcStartX += var16 * scaleX
            var14     += var16
            width     -= var16
            rowStride += var16
        }

        // Clip bottom
        if var6 + height >= clipBottom {
            height -= 1 + height + (var6 - clipBottom)
        }

        // Clip right
        if var4 + width >= clipRight {
            var16      = 1 + var4 + (width - clipRight)
            rowStride += var16
            width     -= var16
        }

        var heightStep: Int32 = 1
        if interlace {
            scaleY    += scaleY
            rowStride += width2
            if (var6 & 1) != 0 {
                var14  += width2
                height -= 1
            }
            heightStep = 2
        }

        guard width > 0 && height > 0 else { return }

        plot_tran_scale(
            heightStep:   heightStep,
            srcStartY:    srcStartY,
            destWidth:    width,
            scaleY:       scaleY,
            spriteWidth:  sprW,
            scaleX:       scaleX,
            height:       height,
            destHead:     var14,
            src:          sprite.pixels,
            srcStartX:    srcStartX,
            destRowStride: rowStride,
            alpha:        alpha
        )
    }

    // MARK: - drawEntity

    /// Draws a billboard sprite at screen position (x, y) scaled to (width × height).
    /// Mirrors `drawEntity(int index, int x, int y, int width, int height, int var1, int var8)`.
    /// Uses `sprites[index]`; no-ops if the sprite is nil.
    func drawEntity(index: Int, x: Int32, y: Int32, width: Int32, height: Int32, perspective: Int32) {
        guard index >= 0 && index < sprites.count, let sprite = sprites[index] else { return }
        // Java delegates to drawSprite(sprite, x, y, width, height, 5924) which uses
        // the plot_scale_black_mask path (transparent on black = 0).
        drawSpriteScaled(sprite: sprite, x: x, y: y, destWidth: width, destHeight: height)
    }

    /// Tinted character-layer blit. Ports the gray/white-axis mask logic from
    /// Java GraphicsController.plot_trans_scale_with_2_masks (line 1007+):
    ///   - Source pixels with R==G==B (gray) get tinted by mask1 (multiplicative).
    ///   - Source pixels with R==255 && G==B (white axis) get tinted by mask2.
    ///   - Other colors pass through unchanged.
    /// Transparent pixels (full-zero) are skipped. The destination width/height
    /// are honoured so character layers match Java's drawSpriteClipping path.
    func drawEntityTinted(index: Int, x: Int32, y: Int32, width: Int32, height: Int32,
                          mask1: Int32, mask2: Int32, blueMask: Int32 = 0, mirrorX: Bool) {
        guard index >= 0 && index < sprites.count, let sprite = sprites[index] else { return }
        guard sprite.width > 0 && sprite.height > 0 && width > 0 && height > 0 else { return }
        let m1 = mask1 == 0 ? Int32(0xFFFFFF) : mask1
        let m2 = mask2 == 0 ? Int32(0xFFFFFF) : mask2
        let bm = blueMask == 0 ? Int32(0xFFFFFF) : blueMask
        let m1R = (Int(m1) >> 16) & 0xFF, m1G = (Int(m1) >> 8) & 0xFF, m1B = Int(m1) & 0xFF
        let m2R = (Int(m2) >> 16) & 0xFF, m2G = (Int(m2) >> 8) & 0xFF, m2B = Int(m2) & 0xFF
        let bmR = (Int(bm) >> 16) & 0xFF, bmG = (Int(bm) >> 8) & 0xFF, bmB = Int(bm) & 0xFF

        let sw = Int(sprite.width); let sh = Int(sprite.height)
        let dw = Int(width2); let dh = Int(height2)
        let outW = Int(width); let outH = Int(height)

        for dyLocal in 0..<outH {
            let dy = Int(y) + dyLocal
            if dy < 0 || dy >= dh { continue }
            let sy = min(sh - 1, (dyLocal * sh) / max(1, outH))
            let rowBase = dy * dw
            for dxLocal in 0..<outW {
                let dx = Int(x) + dxLocal
                if dx < 0 || dx >= dw { continue }

                let sx = min(sw - 1, (dxLocal * sw) / max(1, outW))
                let srcX = mirrorX ? (sw - 1 - sx) : sx
                let pixel = sprite.pixels[sy * sw + srcX]
                // RSC sprites are stored as 24-bit RGB with no alpha byte:
                // pixel == 0 (full black) signals transparency. Don't reject on
                // alpha == 0 — every non-transparent pixel has alpha = 0 on disk.
                if pixel == 0 { continue }

                var r = (Int(pixel) >> 16) & 0xFF
                var g = (Int(pixel) >> 8) & 0xFF
                var b = Int(pixel) & 0xFF

                if r == g && g == b {
                    // Gray pixel — tint with mask1 (e.g. hair/top/bottom layer color)
                    r = (r * m1R) >> 8
                    g = (g * m1G) >> 8
                    b = (b * m1B) >> 8
                } else if r == 255 && g == b {
                    // White-axis pixel — tint with mask2 (skin color)
                    r = (r * m2R) >> 8
                    g = (g * m2G) >> 8
                    b = (b * m2B) >> 8
                } else if bm != 0xFFFFFF && r == g && b != g {
                    let shifter = r * b
                    r = (bmR * shifter) >> 16
                    g = (bmG * shifter) >> 16
                    b = (bmB * shifter) >> 16
                }
                // else: pass through unchanged

                let outARGB = Int32(bitPattern: UInt32(0xFF000000) | (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b))
                pixelData[rowBase + dx] = outARGB
            }
        }
    }

    // MARK: - drawSpriteScaled  (plot_scale_black_mask path)

    /// Scaled sprite blit where pixel colour 0 is transparent (black mask).
    /// Matches the Java `drawSprite(Sprite, int x, int y, int destWidth, int destHeight, int)` ->
    /// `plot_scale_black_mask(...)` path used by `drawEntity`.
    func drawSpriteScaled(sprite: Sprite, x: Int32, y: Int32,
                          destWidth: Int32, destHeight: Int32) {
        let spriteWidth  = sprite.width
        let spriteHeight = sprite.height
        guard spriteWidth > 0 && spriteHeight > 0 && destWidth > 0 && destHeight > 0 else { return }

        let scaleX:    Int32 = (spriteWidth  << 16) / destWidth
        var scaleY:    Int32 = (spriteHeight << 16) / destHeight
        var srcStartX: Int32 = 0
        var srcStartY: Int32 = 0
        var lx = x; var ly = y
        var lw = destWidth; var lh = destHeight

        var destHead: Int32 = lx + width2 * ly

        // Clip top
        if ly < clipTop {
            let lost = clipTop - ly
            srcStartY += scaleY * lost
            lh        -= lost
            destHead  += width2 * lost
            ly         = 0
        }

        var destRowStride: Int32 = width2 - lw

        // Clip bottom
        if ly + lh >= clipBottom {
            lh -= ly - clipBottom + lh + 1
        }

        // Clip left
        if lx < clipLeft {
            let lost = clipLeft - lx
            lw            -= lost
            destRowStride += lost
            destHead      += lost
            lx             = 0
            srcStartX     += scaleX * lost
        }

        // Clip right
        if lx + lw >= clipRight {
            let lost = 1 + lx + (lw - clipRight)
            destRowStride += lost
            lw            -= lost
        }

        var heightStep: Int32 = 1
        if interlace {
            if (ly & 1) != 0 {
                lh       -= 1
                destHead += width2
            }
            destRowStride += width2
            heightStep     = 2
            scaleY        += scaleY
        }

        guard lw > 0 && lh > 0 else { return }

        let srcW      = Int(spriteWidth)
        var dstHead   = Int(destHead)
        let rowStride = Int(destRowStride)

        pixelData.withUnsafeMutableBufferPointer { dstBuf in
            sprite.pixels.withUnsafeBufferPointer { srcBuf in
                var srcY = srcStartY
                var i: Int32 = -lh
                while i < 0 {
                    let rowOffset = Int(srcY >> 16) * srcW
                    srcY += scaleY
                    var srcX = srcStartX
                    var j: Int32 = -lw
                    while j < 0 {
                        let color = srcBuf[rowOffset + Int(srcX >> 16)]
                        srcX += scaleX
                        if color != 0 {
                            dstBuf[dstHead] = color
                        }
                        dstHead += 1
                        j += 1
                    }
                    dstHead += rowStride
                    i += heightStep
                }
            }
        }
    }

    // MARK: - setPixel

    /// Sets a single pixel, clipped to the scissor rect.
    func setPixel(x: Int32, y: Int32, val: Int32) {
        guard clipLeft <= x && clipTop <= y && clipRight > x && clipBottom > y else { return }
        pixelData[Int(x + width2 * y)] = val
    }

    // MARK: - resize

    /// Resize the canvas (mirrors Java `resize(int, int)`).
    func resize(width: Int32, height: Int32) {
        self.width2      = width
        self.height2     = height
        self.clipRight   = width
        self.clipBottom  = height
        self.pixelData   = [Int32](repeating: 0, count: Int(width * height))
    }
}
