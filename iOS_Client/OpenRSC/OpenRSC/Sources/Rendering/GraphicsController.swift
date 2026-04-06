import Foundation

// MARK: - RSSprite

/// Represents a sprite's pixel data and layout metadata, mirroring the Java `Sprite` class.
struct RSSprite {
    var pixels: [Int32]     // ARGB pixel data
    var width: Int
    var height: Int
    var xShift: Int = 0
    var yShift: Int = 0
    var boundWidth: Int = 0
    var boundHeight: Int = 0
    var requiresShift: Bool = false
    // Color manipulation fields (named to match Java Sprite.getSomething1/2)
    var something1: Int = 0
    var something2: Int = 0
}

// MARK: - GraphicsController

/// Software rasterizer ported from the Java desktop client's `GraphicsController`.
/// Provides rendering primitives (lines, boxes, sprites) that write into a CPU-side
/// ARGB framebuffer. The framebuffer is later uploaded to a Metal texture for display.
final class GraphicsController {

    // MARK: Framebuffer

    /// Raw pixel data in ARGB format (0xAARRGGBB). Index = y * width2 + x.
    var pixelData: [UInt32]
    let width2: Int
    let height2: Int

    // MARK: Clip rectangle

    var clipTop: Int = 0
    var clipLeft: Int = 0
    var clipRight: Int
    var clipBottom: Int

    // MARK: Sprite storage

    var sprites: [RSSprite?]
    var spriteCount: Int

    // MARK: Interlace flag (kept for parity; always false on iOS)

    var interlace: Bool = false

    // MARK: - Init

    init(width: Int, height: Int, spriteCount: Int) {
        self.width2 = width
        self.height2 = height
        self.clipRight = width
        self.clipBottom = height
        self.pixelData = [UInt32](repeating: 0, count: width * height)
        self.spriteCount = spriteCount
        self.sprites = [RSSprite?](repeating: nil, count: spriteCount)
    }

    // MARK: - Clip helpers

    /// Resets the clip rectangle to the full framebuffer. Matches Java `clearClip`.
    func clearClip() {
        clipTop = 0
        clipLeft = 0
        clipRight = width2
        clipBottom = height2
    }

    /// Sets a custom clip rectangle.
    func setClip(top: Int, left: Int, right: Int, bottom: Int) {
        clipTop = top
        clipLeft = left
        clipRight = right
        clipBottom = bottom
    }

    // MARK: - 1. blackScreen

    /// Fills the entire framebuffer with opaque black (0xFF000000).
    @inlinable
    func blackScreen() {
        let count = width2 * height2
        pixelData.withUnsafeMutableBufferPointer { buf in
            for i in 0..<count {
                buf[i] = 0xFF00_0000
            }
        }
    }

    // MARK: - 2. drawLineHoriz

    /// Draws a horizontal line at `y` from `x` spanning `width` pixels.
    @inlinable
    func drawLineHoriz(x: Int, y: Int, width: Int, color: UInt32) {
        guard y >= clipTop, y < clipBottom else { return }

        var x = x
        var width = width

        if x < clipLeft {
            width -= (clipLeft - x)
            x = clipLeft
        }
        if x + width > clipRight {
            width = clipRight - x
        }
        guard width > 0 else { return }

        let offset = x + width2 * y
        pixelData.withUnsafeMutableBufferPointer { buf in
            for i in 0..<width {
                buf[offset + i] = color
            }
        }
    }

    // MARK: - 3. drawLineVert

    /// Draws a vertical line at `x` from `y` spanning `height` pixels.
    @inlinable
    func drawLineVert(x: Int, y: Int, height: Int, color: UInt32) {
        guard x >= clipLeft, x < clipRight else { return }

        var y = y
        var height = height

        if y < clipTop {
            height -= (clipTop - y)
            y = clipTop
        }
        if y + height > clipBottom {
            height = clipBottom - y
        }
        guard height > 0 else { return }

        let offset = x + width2 * y
        pixelData.withUnsafeMutableBufferPointer { buf in
            for i in 0..<height {
                buf[offset + width2 * i] = color
            }
        }
    }

    // MARK: - 4. drawBox (filled rectangle)

    /// Fills a rectangle with `color`. Matches Java `drawBox`.
    @inlinable
    func drawBox(x: Int, y: Int, width: Int, height: Int, color: UInt32) {
        var x = x, y = y, w = width, h = height

        if x < clipLeft { w -= (clipLeft - x); x = clipLeft }
        if y < clipTop  { h -= (clipTop  - y); y = clipTop  }
        if y + h > clipBottom { h = clipBottom - y }
        if x + w > clipRight  { w = clipRight  - x }
        guard w > 0, h > 0 else { return }

        let lineSkip = width2 - w
        var head = x + width2 * y

        pixelData.withUnsafeMutableBufferPointer { buf in
            for _ in 0..<h {
                for _ in 0..<w {
                    buf[head] = color
                    head += 1
                }
                head += lineSkip
            }
        }
    }

    // MARK: - 5. drawBoxAlpha (alpha-blended filled rectangle)

    /// Alpha-blended filled rectangle.  `alpha` is 0..256 (not 0..255).
    /// Blend: `result_channel = existing_channel + ((color_channel - existing_channel) * alpha) / 256`
    /// Ported from Java `drawBoxAlpha`.
    @inlinable
    func drawBoxAlpha(x: Int, y: Int, width: Int, height: Int, color: UInt32, alpha: Int) {
        var x = x, y = y, w = width, h = height

        if y < clipTop  { h -= (clipTop  - y); y = clipTop  }
        if x < clipLeft { w -= (clipLeft - x); x = clipLeft }
        if x + w > clipRight  { w = clipRight  - x }
        if y + h > clipBottom { h = clipBottom - y }
        guard w > 0, h > 0 else { return }

        let mixOld = 256 - alpha
        let srcR = alpha * Int((color >> 16) & 0xFF)
        let srcG = alpha * Int((color >>  8) & 0xFF)
        let srcB = alpha * Int( color        & 0xFF)

        let lineStride = width2 - w
        var pxi = x + width2 * y

        pixelData.withUnsafeMutableBufferPointer { buf in
            for _ in 0..<h {
                for _ in 0..<w {
                    let existing = buf[pxi]
                    let oR = mixOld * Int((existing >> 16) & 0xFF)
                    let oG = mixOld * Int((existing >>  8) & 0xFF)
                    let oB = mixOld * Int( existing        & 0xFF)
                    let blended = UInt32((oR + srcR) >> 8) << 16
                                | UInt32((oG + srcG) >> 8) <<  8
                                | UInt32((oB + srcB) >> 8)
                    buf[pxi] = blended
                    pxi += 1
                }
                pxi += lineStride
            }
        }
    }

    // MARK: - 6. drawBoxBorder (rectangle outline)

    /// Draws a 1-pixel rectangle outline.
    @inlinable
    func drawBoxBorder(x: Int, y: Int, width: Int, height: Int, color: UInt32) {
        drawLineHoriz(x: x, y: y, width: width, color: color)
        drawLineHoriz(x: x, y: y + height - 1, width: width, color: color)
        drawLineVert(x: x, y: y, height: height, color: color)
        drawLineVert(x: x + width - 1, y: y, height: height, color: color)
    }

    // MARK: - 7. drawEntity

    /// Renders a billboard sprite from the sprite array, scaled to the given dimensions.
    /// `perspective` and `var8` are kept for call-site parity but the current Java
    /// implementation simply forwards to the scaled `drawSprite`.
    func drawEntity(index: Int, x: Int, y: Int, width: Int, height: Int, perspective: Int = 0, var8: Int = 0) {
        guard index >= 0, index < sprites.count, let sprite = sprites[index] else { return }
        drawSpriteScaled(sprite: sprite, x: x, y: y, destWidth: width, destHeight: height)
    }

    // MARK: - 8. spriteClipping (scaled sprite blit with transparency)

    /// Scaled sprite blit with clipping and color-key transparency (pixel == 0 is transparent).
    /// Uses 16-bit fixed-point DDA for scaling, matching the Java `spriteClipping` method.
    /// `alpha` controls optional alpha blending (0 = fully opaque blit, >0 = blended).
    func spriteClipping(sprite: RSSprite, x: Int, y: Int, width destWidth: Int, height destHeight: Int,
                        alpha: Int = 0) {
        let spriteWidth  = sprite.width
        let spriteHeight = sprite.height

        var srcStartX: Int = 0
        var srcStartY: Int = 0
        var scaleX = (spriteWidth  << 16) / destWidth
        var scaleY = (spriteHeight << 16) / destHeight
        var x = x, y = y
        var width  = destWidth
        var height = destHeight

        // Handle shifted sprites (sprites with sub-region offsets)
        if sprite.requiresShift {
            let s1 = sprite.something1
            let s2 = sprite.something2
            guard s1 != 0, s2 != 0 else { return }

            scaleY = (s2 << 16) / destHeight
            y += (s2 + destHeight * sprite.yShift - 1) / s2
            x += (s1 + sprite.xShift * destWidth - 1) / s1
            scaleX = (s1 << 16) / destWidth

            if sprite.xShift * destWidth % s1 != 0 {
                srcStartX = (s1 - sprite.xShift * destWidth % s1 << 16) / destWidth
            }
            if sprite.yShift * destHeight % s2 != 0 {
                srcStartY = (s2 - sprite.yShift * destHeight % s2 << 16) / destHeight
            }

            width  = destWidth  * (sprite.width  - (srcStartX >> 16)) / s1
            height = destHeight * (sprite.height - (srcStartY >> 16)) / s2
        }

        var destHead = y * width2 + x

        // Top clipping
        if y < clipTop {
            let lost = clipTop - y
            height -= lost
            destHead += width2 * lost
            srcStartY += scaleY * lost
        }

        var destRowStride = width2 - width

        // Left clipping
        if x < clipLeft {
            let lost = clipLeft - x
            srcStartX += lost * scaleX
            destHead += lost
            width -= lost
            destRowStride += lost
        }

        // Bottom clipping
        if y + height >= clipBottom {
            height -= (y + height - clipBottom + 1)
        }

        // Right clipping
        if x + width >= clipRight {
            let lost = x + width - clipRight + 1
            destRowStride += lost
            width -= lost
        }

        guard width > 0, height > 0 else { return }

        if alpha > 0 {
            plotTranScale(
                srcPixels: sprite.pixels, srcWidth: spriteWidth,
                srcStartX: srcStartX, srcStartY: srcStartY,
                scaleX: scaleX, scaleY: scaleY,
                destWidth: width, destHeight: height,
                destHead: destHead, destRowStride: destRowStride,
                alpha: alpha
            )
        } else {
            plotScaleBlackMask(
                srcPixels: sprite.pixels, srcWidth: spriteWidth,
                srcStartX: srcStartX, srcStartY: srcStartY,
                scaleX: scaleX, scaleY: scaleY,
                destWidth: width, destHeight: height,
                destHead: destHead, destRowStride: destRowStride
            )
        }
    }

    // MARK: - Scaled drawSprite (used by drawEntity)

    /// Scaled sprite blit (no alpha blending). Equivalent to the Java
    /// `drawSprite(Sprite, x, y, destWidth, destHeight, var5)`.
    func drawSpriteScaled(sprite: RSSprite, x: Int, y: Int, destWidth: Int, destHeight: Int) {
        let spriteWidth  = sprite.width
        let spriteHeight = sprite.height

        var srcStartX: Int = 0
        var srcStartY: Int = 0
        var scaleX = (spriteWidth  << 16) / destWidth
        var scaleY = (spriteHeight << 16) / destHeight
        var x = x, y = y
        var width  = destWidth
        var height = destHeight

        if sprite.requiresShift {
            let s1 = sprite.something1
            let s2 = sprite.something2
            guard s1 != 0, s2 != 0 else { return }

            if sprite.yShift * destHeight % s2 != 0 {
                srcStartY = (s2 - destHeight * sprite.yShift % s2 << 16) / destHeight
            }
            scaleX = (s1 << 16) / destWidth
            if sprite.xShift * destWidth % s1 != 0 {
                srcStartX = (s1 - sprite.xShift * destWidth % s1 << 16) / destWidth
            }
            x += (destWidth * sprite.xShift + s1 - 1) / s1
            scaleY = (s2 << 16) / destHeight
            y += (s2 + destHeight * sprite.yShift - 1) / s2
            height = (sprite.height - (srcStartY >> 16)) * destHeight / s2
            width  = destWidth * (sprite.width - (srcStartX >> 16)) / s1
        }

        var destHead = x + width2 * y

        // Top clip
        if y < clipTop {
            let lost = clipTop - y
            srcStartY += scaleY * lost
            height -= lost
            destHead += width2 * lost
        }

        var destRowStride = width2 - width

        // Bottom clip
        if y + height >= clipBottom {
            height -= (y + height - clipBottom + 1)
        }

        // Left clip
        if x < clipLeft {
            let lost = clipLeft - x
            width -= lost
            destRowStride += lost
            destHead += lost
            srcStartX += scaleX * lost
        }

        // Right clip
        if x + width >= clipRight {
            let lost = x + width - clipRight + 1
            destRowStride += lost
            width -= lost
        }

        guard width > 0, height > 0 else { return }

        plotScaleBlackMask(
            srcPixels: sprite.pixels, srcWidth: spriteWidth,
            srcStartX: srcStartX, srcStartY: srcStartY,
            scaleX: scaleX, scaleY: scaleY,
            destWidth: width, destHeight: height,
            destHead: destHead, destRowStride: destRowStride
        )
    }

    // MARK: - 9. drawSprite (unscaled 1:1 blit)

    /// Simple unscaled sprite blit with transparency (pixel == 0 is transparent).
    /// Matches Java `drawSprite(Sprite, x, y)`.
    func drawSprite(sprite: RSSprite, x: Int, y: Int) {
        var x = x, y = y

        if sprite.requiresShift {
            x += sprite.xShift
            y += sprite.yShift
        }

        var destHead = y * width2 + x
        var srcHead  = 0
        var sprHeight = sprite.height
        var sprWidth  = sprite.width
        var destRowSkip = width2 - sprWidth
        var srcRowSkip  = 0

        // Top clip
        if y < clipTop {
            let lost = clipTop - y
            sprHeight -= lost
            y = clipTop
            srcHead += lost * sprite.width
            destHead += lost * width2
        }

        // Bottom clip
        if y + sprHeight >= clipBottom {
            sprHeight -= (y + sprHeight - clipBottom + 1)
        }

        // Left clip
        if x < clipLeft {
            let lost = clipLeft - x
            sprWidth -= lost
            srcHead += lost
            destHead += lost
            srcRowSkip += lost
            destRowSkip += lost
        }

        // Right clip
        if x + sprWidth >= clipRight {
            let lost = x + sprWidth - clipRight + 1
            sprWidth -= lost
            srcRowSkip += lost
            destRowSkip += lost
        }

        guard sprWidth > 0, sprHeight > 0 else { return }

        pixelData.withUnsafeMutableBufferPointer { dest in
            sprite.pixels.withUnsafeBufferPointer { src in
                var di = destHead
                var si = srcHead
                for _ in 0..<sprHeight {
                    for _ in 0..<sprWidth {
                        let px = src[si]
                        si += 1
                        if px != 0 {
                            dest[di] = UInt32(bitPattern: px)
                        }
                        di += 1
                    }
                    si += srcRowSkip
                    di += destRowSkip
                }
            }
        }
    }

    // MARK: - 10. fade2black

    /// Darkens every pixel towards black. Applies an approximate 87.5% brightness reduction:
    ///   result = (px >>> 1) + (px >>> 3) + (px >>> 4) — matching the Java `fade2black`.
    @inlinable
    func fade2black() {
        let count = width2 * height2
        pixelData.withUnsafeMutableBufferPointer { buf in
            for i in 0..<count {
                let px = buf[i] & 0x00FF_FFFF
                let a = (px >> 1) & 0x7F7F7F
                let b = (px >> 2) & 0x3F3F3F
                let c = (px >> 3) & 0x1F1F1F
                let d = (px >> 4) & 0x0F0F0F
                buf[i] = a + b + c + d
            }
        }
    }

    // MARK: - 11. drawString (stub)

    /// Simplified text rendering stub. The iOS client uses SwiftUI overlays for text,
    /// so this is a no-op placeholder that maintains API compatibility with the Java client.
    func drawString(_ text: String, x: Int, y: Int, color: UInt32, font: Int) {
        // No-op: text rendering is handled by SwiftUI on iOS.
        // A bitmap font renderer can be plugged in here if needed for in-framebuffer text.
    }

    // MARK: - Internal rasterizer kernels

    /// Scaled blit with color-key transparency (skip pixels == 0). No alpha blending.
    /// Mirrors Java `plot_scale_black_mask`.
    @inlinable
    internal func plotScaleBlackMask(
        srcPixels: [Int32], srcWidth: Int,
        srcStartX: Int, srcStartY: Int,
        scaleX: Int, scaleY: Int,
        destWidth: Int, destHeight: Int,
        destHead: Int, destRowStride: Int
    ) {
        let firstColumn = srcStartX
        var srcY = srcStartY
        var dh = destHead

        pixelData.withUnsafeMutableBufferPointer { dest in
            srcPixels.withUnsafeBufferPointer { src in
                for _ in 0..<destHeight {
                    let srcRowOffset = (srcY >> 16) * srcWidth
                    srcY += scaleY
                    var srcX = firstColumn

                    for _ in 0..<destWidth {
                        let color = src[(srcX >> 16) + srcRowOffset]
                        srcX += scaleX
                        if color != 0 {
                            dest[dh] = UInt32(bitPattern: color)
                        }
                        dh += 1
                    }
                    dh += destRowStride
                }
            }
        }
    }

    /// Scaled blit with color-key transparency and alpha blending.
    /// Mirrors Java `plot_tran_scale`.
    @inlinable
    internal func plotTranScale(
        srcPixels: [Int32], srcWidth: Int,
        srcStartX: Int, srcStartY: Int,
        scaleX: Int, scaleY: Int,
        destWidth: Int, destHeight: Int,
        destHead: Int, destRowStride: Int,
        alpha: Int
    ) {
        let alphaInv = 256 - alpha
        let firstColumn = srcStartX
        var srcY = srcStartY
        var dh = destHead

        pixelData.withUnsafeMutableBufferPointer { dest in
            srcPixels.withUnsafeBufferPointer { src in
                for _ in 0..<destHeight {
                    let srcRowOffset = (srcY >> 16) * srcWidth
                    srcY += scaleY
                    var srcX = firstColumn

                    for _ in 0..<destWidth {
                        let newColor = src[(srcX >> 16) + srcRowOffset]
                        srcX += scaleX
                        if newColor == 0 {
                            dh += 1
                        } else {
                            let nc = UInt32(bitPattern: newColor)
                            let oc = dest[dh]
                            // Blend each channel: result = (old * alphaInv + new * alpha) >> 8
                            let rr = (Int((oc >> 16) & 0xFF) * alphaInv + Int((nc >> 16) & 0xFF) * alpha) >> 8
                            let gg = (Int((oc >>  8) & 0xFF) * alphaInv + Int((nc >>  8) & 0xFF) * alpha) >> 8
                            let bb = (Int( oc        & 0xFF) * alphaInv + Int( nc        & 0xFF) * alpha) >> 8
                            dest[dh] = UInt32(rr) << 16 | UInt32(gg) << 8 | UInt32(bb)
                            dh += 1
                        }
                    }
                    dh += destRowStride
                }
            }
        }
    }
}
