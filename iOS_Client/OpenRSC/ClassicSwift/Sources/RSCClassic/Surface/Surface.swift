// 2D software raster: port of rsc-c's surface.c (RENDER_SW path).
//
// Pixels are 0xRRGGBB in Int32, row-major, `width` per row. Functions keep the
// C names (camel-cased) and the C arithmetic so output matches pixel for pixel.

import Foundation

/// Calls the Surface makes back into the game client (mudclient in C).
public protocol SurfaceHost: AnyObject {
    func drawMagicBubble(x: Int, y: Int, width: Int, height: Int, id: Int)
    func drawGroundItem(x: Int, y: Int, width: Int, height: Int, id: Int)
    func drawNpc(x: Int, y: Int, width: Int, height: Int, id: Int, tx: Int, ty: Int)
    func drawPlayer(x: Int, y: Int, width: Int, height: Int, id: Int, tx: Int, ty: Int)
    func drawItem(x: Int, y: Int, slotWidth: Int, slotHeight: Int, itemId: Int)
    func formatItemAmount(_ amount: Int) -> String
    func inventoryCount(itemId: Int) -> Int
    var isTouch: Bool { get }
    var ranTargetFps: Int { get }
}

public enum FontStyle: Int {
    case regular11 = 0, bold12, regular12, bold13, bold14, bold16, bold20, bold24
}

public final class Surface {
    public static let sleepWidth = 255
    public static let sleepHeight = 40
    public static let itemGridSlotWidth = 49
    public static let itemGridSlotHeight = 34
    public static let scrollbarTopColour: Int32 = 0x7272b0
    public static let scrollbarBottomColour: Int32 = 0x0e0e3e
    public static let scrubLeftColour: Int32 = 0xc8d0e8
    public static let scrubMiddleColour: Int32 = 0x6081b8
    public static let scrubRightColour: Int32 = 0x355f73
    public static let minimapSpriteWidth = 285

    public let limit: Int
    public let width: Int
    public let height: Int
    public let pixels: UnsafeMutablePointer<Int32>

    public var spritePixels: [[Int32]?]
    public var spriteColours: [[UInt8]?]
    public var spritePalette: [[Int32]?]
    public var spriteWidth: [Int]
    public var spriteHeight: [Int]
    public var spriteWidthFull: [Int]
    public var spriteHeightFull: [Int]
    public var spriteTranslate: [Bool]
    public var spriteTranslateX: [Int]
    public var spriteTranslateY: [Int]

    public var interlace = false
    public var drawStringShadow = false

    public var boundsMinX = 0
    public var boundsMinY = 0
    public var boundsMaxX: Int
    public var boundsMaxY: Int

    /// Fonts loaded from jagex.jag (game_fonts in C), indexed by FontStyle.
    public var fonts: [[Int8]] = []

    public weak var host: SurfaceHost?
    public var spriteUtil = 2100
    public var spriteItem = 2150

    // Minimap rotation scratch rows.
    var rotations0: [Int] = []
    var rotations1: [Int] = []
    var rotations2: [Int] = []
    var rotations3: [Int] = []
    var rotations4: [Int] = []
    var rotations5: [Int] = []

    // Debug counters kept for parity with an_int_346..348.
    var anInt346 = 0
    var anInt347 = 0
    var anInt348 = 0

    /// Shared 32k histogram used by screenRasterToPaletteSprite.
    var texturePixels = [Int32](repeating: 0, count: 32 * 1024)

    public init(width: Int, height: Int, limit: Int) {
        self.width = width
        self.height = height
        self.limit = limit
        boundsMaxX = width
        boundsMaxY = height
        pixels = .allocate(capacity: width * height)
        pixels.initialize(repeating: 0, count: width * height)
        spritePixels = Array(repeating: nil, count: limit)
        spriteColours = Array(repeating: nil, count: limit)
        spritePalette = Array(repeating: nil, count: limit)
        spriteWidth = Array(repeating: 0, count: limit)
        spriteHeight = Array(repeating: 0, count: limit)
        spriteWidthFull = Array(repeating: 0, count: limit)
        spriteHeightFull = Array(repeating: 0, count: limit)
        spriteTranslate = Array(repeating: false, count: limit)
        spriteTranslateX = Array(repeating: 0, count: limit)
        spriteTranslateY = Array(repeating: 0, count: limit)
    }

    deinit {
        pixels.deallocate()
    }

    public var pixelBuffer: UnsafeMutableBufferPointer<Int32> {
        UnsafeMutableBufferPointer(start: pixels, count: width * height)
    }

    // MARK: - Bounds

    public func setBounds(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        boundsMinX = max(minX, 0)
        boundsMinY = max(minY, 0)
        boundsMaxX = min(maxX, width)
        boundsMaxY = min(maxY, height)
    }

    public func resetBounds() {
        boundsMinX = 0
        boundsMinY = 0
        boundsMaxX = width
        boundsMaxY = height
    }

    // MARK: - Primitives

    public func blackScreen() {
        let area = width * height
        if !interlace {
            pixels.update(repeating: 0, count: area)
            return
        }
        var index = 0
        for _ in stride(from: -height, to: 0, by: 2) {
            for _ in 0..<width {
                pixels[index] = 0
                index += 1
            }
            index += width
        }
    }

    public func drawCircle(x: Int, y: Int, radius: Int, colour: Int32, alpha: Int) {
        let backgroundAlpha = 256 - alpha
        let c = Int(colour)
        let red = ((c >> 16) & 0xff) * alpha
        let green = ((c >> 8) & 0xff) * alpha
        let blue = (c & 0xff) * alpha

        var top = y - radius
        if top < 0 { top = 0 }
        var bottom = y + radius
        if bottom >= height { bottom = height - 1 }

        var yInc = 1
        if interlace {
            yInc = 2
            if top & 1 != 0 { top += 1 }
        }

        var yy = top
        while yy <= bottom {
            let l3 = yy - y
            let i4 = Int(Double(Int32(truncatingIfNeeded: radius * radius - l3 * l3)).squareRoot())
            var j4 = x - i4
            if j4 < 0 { j4 = 0 }
            var k4 = x + i4
            if k4 >= width { k4 = width - 1 }
            var index = j4 + yy * width
            var i = j4
            while i <= k4 {
                let p = Int(pixels[index])
                let br = ((p >> 16) & 0xff) * backgroundAlpha
                let bg = ((p >> 8) & 0xff) * backgroundAlpha
                let bb = (p & 0xff) * backgroundAlpha
                pixels[index] = Int32(truncatingIfNeeded: (((red + br) >> 8) << 16) + (((green + bg) >> 8) << 8) + ((blue + bb) >> 8))
                index += 1
                i += 1
            }
            yy += yInc
        }
    }

    public func drawBoxAlpha(x: Int, y: Int, width w: Int, height h: Int, colour: Int32, alpha: Int) {
        var x = x, y = y, w = w, h = h
        if x < boundsMinX { w -= boundsMinX - x; x = boundsMinX }
        if y < boundsMinY { h -= boundsMinY - y; y = boundsMinY }
        if x + w > boundsMaxX { w = boundsMaxX - x }
        if y + h > boundsMaxY { h = boundsMaxY - y }

        let c = Int(colour)
        let red = ((c >> 16) & 0xff) * alpha
        let green = ((c >> 8) & 0xff) * alpha
        let blue = (c & 0xff) * alpha
        let backgroundAlpha = 256 - alpha

        var offset = width - w
        var yInc = 1
        if interlace {
            yInc = 2
            offset += width
            if y & 1 != 0 { y += 1; h -= 1 }
        }

        var index = x + y * width
        for _ in stride(from: 0, to: h, by: yInc) {
            for _ in stride(from: -w, to: 0, by: 1) {
                let p = Int(pixels[index])
                let br = ((p >> 16) & 0xff) * backgroundAlpha
                let bg = ((p >> 8) & 0xff) * backgroundAlpha
                let bb = (p & 0xff) * backgroundAlpha
                pixels[index] = Int32(truncatingIfNeeded: (((red + br) >> 8) << 16) + (((green + bg) >> 8) << 8) + ((blue + bb) >> 8))
                index += 1
            }
            index += offset
        }
    }

    public func drawGradient(x: Int, y: Int, width w: Int, height h: Int, topColour: Int32, bottomColour: Int32) {
        var x = x, y = y, w = w, h = h
        if x < boundsMinX { w -= boundsMinX - x; x = boundsMinX }
        if x + w > boundsMaxX { w = boundsMaxX - x }

        let bc = Int(bottomColour), tc = Int(topColour)
        let bottomRed = (bc >> 16) & 0xff, bottomGreen = (bc >> 8) & 0xff, bottomBlue = bc & 0xff
        let topRed = (tc >> 16) & 0xff, topGreen = (tc >> 8) & 0xff, topBlue = tc & 0xff

        var offset = width - w
        var yInc = 1
        if interlace {
            yInc = 2
            offset += width
            if y & 1 != 0 { y += 1; h -= 1 }
        }

        var index = x + y * width
        for i in stride(from: 0, to: h, by: yInc) {
            if i + y >= boundsMinY && i + y < boundsMaxY {
                let colour = Int32(truncatingIfNeeded:
                    (((bottomRed * i + topRed * (h - i)) / h) << 16) +
                    (((bottomGreen * i + topGreen * (h - i)) / h) << 8) +
                    ((bottomBlue * i + topBlue * (h - i)) / h))
                for _ in stride(from: -w, to: 0, by: 1) {
                    pixels[index] = colour
                    index += 1
                }
                index += offset
            } else {
                index += width
            }
        }
    }

    public func drawBox(x: Int, y: Int, width w: Int, height h: Int, colour: Int32) {
        var x = x, y = y, w = w, h = h
        if x < boundsMinX { w -= boundsMinX - x; x = boundsMinX }
        if y < boundsMinY { h -= boundsMinY - y; y = boundsMinY }
        if x + w > boundsMaxX { w = boundsMaxX - x }
        if y + h > boundsMaxY { h = boundsMaxY - y }

        var offset = width - w
        var yInc = 1
        if interlace {
            yInc = 2
            offset += width
            if y & 1 != 0 { y += 1; h -= 1 }
        }

        var index = x + y * width
        for _ in stride(from: -h, to: 0, by: yInc) {
            for _ in stride(from: -w, to: 0, by: 1) {
                pixels[index] = colour
                index += 1
            }
            index += offset
        }
    }

    public func drawLineHorizontal(x: Int, y: Int, width w: Int, colour: Int32) {
        if y < boundsMinY || y >= boundsMaxY { return }
        var x = x, w = w
        if x < boundsMinX { w -= boundsMinX - x; x = boundsMinX }
        if x + w > boundsMaxX { w = boundsMaxX - x }
        let start = x + y * width
        var i = 0
        while i < w {
            pixels[start + i] = colour
            i += 1
        }
    }

    public func drawLineVertical(x: Int, y: Int, height h: Int, colour: Int32) {
        if x < boundsMinX || x >= boundsMaxX { return }
        var y = y, h = h
        if y < boundsMinY { h -= boundsMinY - y; y = boundsMinY }
        if y + h > boundsMaxY { h = boundsMaxY - y }
        let start = x + y * width
        var i = 0
        while i < h {
            pixels[start + i * width] = colour
            i += 1
        }
    }

    public func drawBorder(x: Int, y: Int, width w: Int, height h: Int, colour: Int32) {
        drawLineHorizontal(x: x, y: y, width: w, colour: colour)
        drawLineHorizontal(x: x, y: y + h - 1, width: w, colour: colour)
        drawLineVertical(x: x, y: y, height: h, colour: colour)
        drawLineVertical(x: x + w - 1, y: y, height: h, colour: colour)
    }

    public func setPixel(x: Int, y: Int, colour: Int32) {
        if x < boundsMinX || y < boundsMinY || x >= boundsMaxX || y >= boundsMaxY { return }
        pixels[x + y * width] = colour
    }

    public func fadeToBlack() {
        for i in 0..<(width * height) {
            let p = pixels[i] & 0xffffff
            pixels[i] = ((p >> 1) & 0x7f7f7f) + ((p >> 2) & 0x3f3f3f) + ((p >> 3) & 0x1f1f1f) + ((p >> 4) & 0xf0f0f)
        }
    }

    public func applyLoginFilter(backgroundHeight: Int) {
        fadeToBlack()
        fadeToBlack()
        drawBox(x: 0, y: 0, width: width, height: 6, colour: Colour.black)
        for i in stride(from: 6, through: 1, by: -1) {
            drawBlur(blurHeight: i, x: 0, y: i, width: width, height: 8)
        }
        drawBox(x: 0, y: backgroundHeight - 6, width: width, height: 20, colour: Colour.black)
        for i in stride(from: 6, through: 1, by: -1) {
            drawBlur(blurHeight: i, x: 0, y: backgroundHeight - 6 - i, width: width, height: 8)
        }
    }

    public func drawBlur(blurHeight: Int, x: Int, y: Int, width w: Int, height h: Int) {
        for xx in x..<(x + w) {
            for yy in y..<(y + h) {
                var r = 0, g = 0, b = 0, a = 0
                if xx >= 0 && xx < width {
                    for y2 in (yy - blurHeight)...(yy + blurHeight) where y2 >= 0 && y2 < height {
                        let p = Int(pixels[xx + width * y2])
                        r += (p >> 16) & 0xff
                        g += (p >> 8) & 0xff
                        b += p & 0xff
                        a += 1
                    }
                }
                pixels[xx + width * yy] = Int32(truncatingIfNeeded: ((r / a) << 16) + ((g / a) << 8) + (b / a))
            }
        }
    }

    /// Clears every sprite slot's 32-bit pixels and size (surface_clear).
    public func clear() {
        for i in 0..<limit {
            spritePixels[i] = nil
            spriteWidth[i] = 0
            spriteHeight[i] = 0
        }
    }
}
