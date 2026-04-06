import Foundation
import UIKit

/// Manages sprite loading, caching, and rendering.
/// Handles player, NPC, item, and object sprites.
final class SpriteManager {
    static let shared = SpriteManager()

    // Sprite caches
    private var spriteCache: [String: Sprite] = [:]
    private var animationCache: [String: SpriteAnimation] = [:]
    private var imageCache: [String: UIImage] = [:]

    // Archive-loaded sprites indexed by numeric ID (matching Java sprite indices)
    private(set) var indexedSprites: [Int: Sprite] = [:]
    private(set) var isLoaded = false
    private(set) var totalSpritesLoaded = 0

    // LRU eviction
    private var accessOrder: [String] = []
    private let maxCacheSize = 500

    // Sprite sheet dimensions
    private let tileSize = 32

    private init() {
        loadDefaultSprites()
    }

    /// Loads sprites from a .orsc archive file.
    func loadArchive(from url: URL) {
        let reader = SpriteArchiveReader()
        guard let workspace = reader.readArchive(from: url) else {
            print("SpriteManager: Failed to load archive from \(url.lastPathComponent)")
            return
        }

        for (index, frame) in workspace.indexedSprites {
            let sprite = frame.toSprite(id: "\(index)")
            indexedSprites[index] = sprite
            addToCache(id: "archive_\(index)", sprite: sprite)
        }

        totalSpritesLoaded = indexedSprites.count
        isLoaded = true
        print("SpriteManager: Loaded \(totalSpritesLoaded) sprites from \(url.lastPathComponent)")
    }

    /// Gets a sprite by its numeric archive index.
    func getSpriteByIndex(_ index: Int) -> Sprite? {
        return indexedSprites[index]
    }

    func getGuiSprite(_ part: GuiPart) -> Sprite? {
        getSpriteByIndex(part.spriteIndex)
    }

    func getGuiImage(_ part: GuiPart) -> UIImage? {
        guard let sprite = getGuiSprite(part) else { return nil }
        return image(for: sprite, cacheKey: "gui_\(part.rawValue)")
    }

    /// Public helper to render any sprite as a UIImage.
    func imageForSprite(_ sprite: Sprite) -> UIImage? {
        return image(for: sprite, cacheKey: "sprite_\(sprite.id)")
    }

    /// Loads default/placeholder sprites.
    private func loadDefaultSprites() {
        // Create placeholder sprites for common entities
        createPlaceholderSprite(id: "player_idle", width: 32, height: 48, color: .rgb(200, 150, 100))
        createPlaceholderSprite(id: "player_walk_0", width: 32, height: 48, color: .rgb(200, 150, 100))
        createPlaceholderSprite(id: "player_walk_1", width: 32, height: 48, color: .rgb(190, 140, 90))
        createPlaceholderSprite(id: "player_attack", width: 48, height: 48, color: .rgb(220, 160, 110))

        createPlaceholderSprite(id: "npc_default", width: 32, height: 48, color: .rgb(100, 150, 200))
        createPlaceholderSprite(id: "item_default", width: 24, height: 24, color: .rgb(200, 200, 50))
        createPlaceholderSprite(id: "object_default", width: 32, height: 32, color: .rgb(100, 80, 60))

        // Create walking animation
        let walkFrames = [getSprite(id: "player_walk_0")!, getSprite(id: "player_walk_1")!]
        animationCache["player_walk"] = SpriteAnimation(frames: walkFrames, frameDuration: 0.2)
    }

    /// Creates a placeholder colored sprite.
    private func createPlaceholderSprite(id: String, width: Int, height: Int, color: UInt32) {
        var pixels = [UInt32](repeating: color, count: width * height)

        // Add simple shading
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x

                // Darker at bottom
                if y > height * 3 / 4 {
                    pixels[index] = darken(color, by: 0.2)
                }
                // Lighter at top
                else if y < height / 4 {
                    pixels[index] = lighten(color, by: 0.1)
                }

                // Edge darkening
                if x == 0 || x == width - 1 || y == 0 || y == height - 1 {
                    pixels[index] = darken(pixels[index], by: 0.3)
                }
            }
        }

        spriteCache[id] = Sprite(id: id, width: width, height: height, pixels: pixels)
    }

    /// Gets a sprite by ID.
    func getSprite(id: String) -> Sprite? {
        if let sprite = spriteCache[id] {
            updateAccessOrder(id)
            return sprite
        }
        return nil
    }

    /// Gets an animation by ID.
    func getAnimation(id: String) -> SpriteAnimation? {
        return animationCache[id]
    }

    /// Loads a sprite from image data.
    func loadSprite(id: String, from imageData: Data) -> Sprite? {
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height

        var pixels = [UInt32](repeating: 0, count: width * height)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )

        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let sprite = Sprite(id: id, width: width, height: height, pixels: pixels)
        addToCache(id: id, sprite: sprite)

        return sprite
    }

    /// Loads a sprite sheet and extracts individual sprites.
    func loadSpriteSheet(id: String, from imageData: Data, tileWidth: Int, tileHeight: Int) -> [Sprite] {
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            return []
        }

        let sheetWidth = cgImage.width
        let sheetHeight = cgImage.height
        let columns = sheetWidth / tileWidth
        let rows = sheetHeight / tileHeight

        var allPixels = [UInt32](repeating: 0, count: sheetWidth * sheetHeight)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &allPixels,
            width: sheetWidth,
            height: sheetHeight,
            bitsPerComponent: 8,
            bytesPerRow: sheetWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))

        var sprites: [Sprite] = []

        for row in 0..<rows {
            for col in 0..<columns {
                var tilePixels = [UInt32](repeating: 0, count: tileWidth * tileHeight)

                for y in 0..<tileHeight {
                    for x in 0..<tileWidth {
                        let srcX = col * tileWidth + x
                        let srcY = row * tileHeight + y
                        let srcIndex = srcY * sheetWidth + srcX
                        let dstIndex = y * tileWidth + x
                        tilePixels[dstIndex] = allPixels[srcIndex]
                    }
                }

                let tileId = "\(id)_\(row)_\(col)"
                let sprite = Sprite(id: tileId, width: tileWidth, height: tileHeight, pixels: tilePixels)
                sprites.append(sprite)
                addToCache(id: tileId, sprite: sprite)
            }
        }

        return sprites
    }

    /// RSC sprite index constants (matching Java mudclient.java)
    static let spriteMedia = 2000
    static let spriteUtil = 2100
    static let spriteItem = 2150
    static let spriteLogo = 3150
    static let spriteProjectile = 3160
    static let spriteTexture = 3225

    enum GuiPart: String, CaseIterable {
        case menuBar
        case socialTab
        case minimapTab
        case settingsTab
        case skillsTab
        case bagTab
        case spellTab
        case compass
        case checkMark
        case xMark
        case equipTab

        var spriteIndex: Int {
            switch self {
            case .menuBar:
                return SpriteManager.spriteMedia
            case .socialTab:
                return SpriteManager.spriteMedia + 5
            case .minimapTab:
                return SpriteManager.spriteMedia + 2
            case .settingsTab:
                return SpriteManager.spriteMedia + 6
            case .skillsTab:
                return SpriteManager.spriteMedia + 3
            case .bagTab:
                return SpriteManager.spriteMedia + 1
            case .spellTab:
                return SpriteManager.spriteMedia + 4
            case .compass:
                return SpriteManager.spriteMedia + 24
            case .checkMark:
                return SpriteManager.spriteMedia + 27
            case .xMark:
                return SpriteManager.spriteMedia + 28
            case .equipTab:
                return SpriteManager.spriteMedia + 7
            }
        }
    }

    /// Gets a player sprite based on appearance.
    func getPlayerSprite(appearance: PlayerAppearance?, direction: Int, isWalking: Bool, animationFrame: Int) -> Sprite? {
        if let app = appearance {
            let spriteIndex = app.headSprite + Self.spriteMedia
            if let archiveSprite = getSpriteByIndex(spriteIndex) {
                return archiveSprite
            }
        }
        return nil
    }

    /// Gets an NPC sprite.
    func getNpcSprite(npcId: Int, direction: Int, animation: Int) -> Sprite? {
        if let archiveSprite = getSpriteByIndex(npcId + Self.spriteMedia) {
            return archiveSprite
        }
        return nil
    }

    /// Gets an item sprite.
    func getItemSprite(itemId: Int) -> Sprite? {
        if let appearanceId = ItemDefinitions.appearanceId(itemId: itemId),
           let archiveSprite = getSpriteByIndex(appearanceId + Self.spriteItem) {
            return archiveSprite
        }

        if let archiveSprite = getSpriteByIndex(itemId + Self.spriteItem) {
            return archiveSprite
        }
        return nil
    }

    /// Gets a scenery object sprite.
    func getObjectSprite(objectId: Int) -> Sprite? {
        if let archiveSprite = getSpriteByIndex(objectId + Self.spriteMedia) {
            return archiveSprite
        }
        return nil
    }

    // MARK: - Cache Management

    private func addToCache(id: String, sprite: Sprite) {
        if spriteCache.count >= maxCacheSize {
            evictLRU()
        }
        spriteCache[id] = sprite
        updateAccessOrder(id)
    }

    private func updateAccessOrder(_ id: String) {
        accessOrder.removeAll { $0 == id }
        accessOrder.append(id)
    }

    private func evictLRU() {
        guard let oldestId = accessOrder.first else { return }
        spriteCache.removeValue(forKey: oldestId)
        accessOrder.removeFirst()
    }

    private func image(for sprite: Sprite, cacheKey: String) -> UIImage? {
        if let cached = imageCache[cacheKey] {
            return cached
        }

        let canvasWidth = sprite.canvasWidth
        let canvasHeight = sprite.canvasHeight
        guard canvasWidth > 0, canvasHeight > 0 else { return nil }

        var pixels = [UInt32](repeating: 0, count: canvasWidth * canvasHeight)
        let drawOffsetX = sprite.useShift ? sprite.offsetX : 0
        let drawOffsetY = sprite.useShift ? sprite.offsetY : 0

        for y in 0..<sprite.height {
            let destinationY = y + drawOffsetY
            guard destinationY >= 0 && destinationY < canvasHeight else { continue }

            for x in 0..<sprite.width {
                let destinationX = x + drawOffsetX
                guard destinationX >= 0 && destinationX < canvasWidth else { continue }
                pixels[destinationY * canvasWidth + destinationX] = sprite.getPixel(x: x, y: y)
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        let pixelData = pixels.withUnsafeBytes { Data($0) }

        guard let provider = CGDataProvider(data: pixelData as CFData),
              let cgImage = CGImage(
                width: canvasWidth,
                height: canvasHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: canvasWidth * MemoryLayout<UInt32>.size,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }

        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        imageCache[cacheKey] = image
        return image
    }

    /// Clears the sprite cache.
    func clearCache() {
        spriteCache.removeAll()
        accessOrder.removeAll()
        imageCache.removeAll()
        loadDefaultSprites()
    }

    // MARK: - Color Utilities

    private func darken(_ color: UInt32, by amount: Double) -> UInt32 {
        let a = color.alpha
        let r = UInt8(Double(color.red) * (1.0 - amount))
        let g = UInt8(Double(color.green) * (1.0 - amount))
        let b = UInt8(Double(color.blue) * (1.0 - amount))
        return .argb(a, r, g, b)
    }

    private func lighten(_ color: UInt32, by amount: Double) -> UInt32 {
        let a = color.alpha
        let r = UInt8(min(255, Double(color.red) * (1.0 + amount)))
        let g = UInt8(min(255, Double(color.green) * (1.0 + amount)))
        let b = UInt8(min(255, Double(color.blue) * (1.0 + amount)))
        return .argb(a, r, g, b)
    }
}

// MARK: - Sprite

/// Represents a single sprite image.
struct Sprite {
    let id: String
    let width: Int
    let height: Int
    let pixels: [UInt32]
    var useShift: Bool = false
    var offsetX: Int = 0
    var offsetY: Int = 0
    var boundWidth: Int = 0
    var boundHeight: Int = 0

    var canvasWidth: Int {
        useShift && boundWidth > 0 ? max(width, boundWidth) : width
    }

    var canvasHeight: Int {
        useShift && boundHeight > 0 ? max(height, boundHeight) : height
    }

    /// Gets pixel at coordinates, or transparent if out of bounds.
    func getPixel(x: Int, y: Int) -> UInt32 {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return 0x00000000 // Transparent
        }
        return pixels[y * width + x]
    }

    /// Creates a horizontally flipped version.
    func flippedHorizontally() -> Sprite {
        var flipped = [UInt32](repeating: 0, count: pixels.count)
        for y in 0..<height {
            for x in 0..<width {
                flipped[y * width + x] = pixels[y * width + (width - 1 - x)]
            }
        }
        return Sprite(id: id + "_flipped", width: width, height: height, pixels: flipped)
    }

    /// Creates a tinted version.
    func tinted(with color: UInt32) -> Sprite {
        let tintR = Double(color.red) / 255.0
        let tintG = Double(color.green) / 255.0
        let tintB = Double(color.blue) / 255.0

        var tinted = [UInt32](repeating: 0, count: pixels.count)
        for i in 0..<pixels.count {
            let pixel = pixels[i]
            let a = pixel.alpha
            let r = UInt8(Double(pixel.red) * tintR)
            let g = UInt8(Double(pixel.green) * tintG)
            let b = UInt8(Double(pixel.blue) * tintB)
            tinted[i] = .argb(a, r, g, b)
        }
        return Sprite(id: id + "_tinted", width: width, height: height, pixels: tinted)
    }
}

// MARK: - Sprite Animation

/// Represents an animated sprite sequence.
struct SpriteAnimation {
    let frames: [Sprite]
    let frameDuration: TimeInterval
    var isLooping: Bool = true

    /// Gets the current frame based on elapsed time.
    func getFrame(at time: TimeInterval) -> Sprite? {
        guard !frames.isEmpty else { return nil }

        let totalDuration = frameDuration * Double(frames.count)
        var adjustedTime = time

        if isLooping {
            adjustedTime = time.truncatingRemainder(dividingBy: totalDuration)
        } else {
            adjustedTime = min(time, totalDuration - 0.001)
        }

        let frameIndex = Int(adjustedTime / frameDuration) % frames.count
        return frames[frameIndex]
    }

    var totalDuration: TimeInterval {
        return frameDuration * Double(frames.count)
    }
}

// MARK: - Sprite Rendering Extension

extension GameRenderer {
    /// Draws a sprite at the given position.
    func drawSprite(_ sprite: Sprite, at x: Int, y: Int, alpha: UInt8 = 255) {
        for sy in 0..<sprite.height {
            let destY = y + sy
            guard destY >= 0 && destY < Self.height else { continue }

            for sx in 0..<sprite.width {
                let destX = x + sx
                guard destX >= 0 && destX < Self.width else { continue }

                let srcPixel = sprite.getPixel(x: sx, y: sy)
                let srcAlpha = srcPixel.alpha

                // Skip fully transparent pixels
                if srcAlpha == 0 { continue }

                let destIndex = destY * Self.width + destX

                if srcAlpha == 255 && alpha == 255 {
                    // Fully opaque - direct copy
                    pixelBuffer[destIndex] = srcPixel
                } else {
                    // Alpha blend
                    let effectiveAlpha = Int(srcAlpha) * Int(alpha) / 255
                    let destPixel = pixelBuffer[destIndex]

                    let srcR = Int(srcPixel.red)
                    let srcG = Int(srcPixel.green)
                    let srcB = Int(srcPixel.blue)
                    let dstR = Int(destPixel.red)
                    let dstG = Int(destPixel.green)
                    let dstB = Int(destPixel.blue)

                    let outR = UInt8((srcR * effectiveAlpha + dstR * (255 - effectiveAlpha)) / 255)
                    let outG = UInt8((srcG * effectiveAlpha + dstG * (255 - effectiveAlpha)) / 255)
                    let outB = UInt8((srcB * effectiveAlpha + dstB * (255 - effectiveAlpha)) / 255)

                    pixelBuffer[destIndex] = .argb(255, outR, outG, outB)
                }
            }
        }
    }

    /// Draws a sprite scaled to the given size.
    func drawSpriteScaled(_ sprite: Sprite, at x: Int, y: Int, width: Int, height: Int) {
        let scaleX = Float(sprite.width) / Float(width)
        let scaleY = Float(sprite.height) / Float(height)

        for dy in 0..<height {
            let destY = y + dy
            guard destY >= 0 && destY < Self.height else { continue }

            let srcY = Int(Float(dy) * scaleY)

            for dx in 0..<width {
                let destX = x + dx
                guard destX >= 0 && destX < Self.width else { continue }

                let srcX = Int(Float(dx) * scaleX)
                let srcPixel = sprite.getPixel(x: srcX, y: srcY)

                if srcPixel.alpha > 0 {
                    pixelBuffer[destY * Self.width + destX] = srcPixel
                }
            }
        }
    }

    /// Draws an animated sprite.
    func drawAnimation(_ animation: SpriteAnimation, at x: Int, y: Int, time: TimeInterval) {
        if let frame = animation.getFrame(at: time) {
            drawSprite(frame, at: x, y: y)
        }
    }
}
