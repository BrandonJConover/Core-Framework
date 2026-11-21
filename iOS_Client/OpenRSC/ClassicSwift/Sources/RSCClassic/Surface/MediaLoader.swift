// Font and 2D sprite loading: mudclient_load_jagex / mudclient_load_media from rsc-c.

import Foundation

public enum SpriteBase {
    public static let limit = 4000
    public static let media = 2000
    public static let util = media + 100
    public static let item = util + 50
    public static let logo = item + 1000
    public static let projectile = logo + 10
    public static let texture = projectile + 50
    public static let textureWorld = texture + 10
}

public enum MediaError: Error {
    case missing(String)
}

public enum MediaLoader {
    public static let fontFiles = ["h11p.jf", "h12b.jf", "h12p.jf", "h13b.jf", "h14b.jf", "h16b.jf", "h20b.jf", "h24b.jf"]

    /// Loads the eight fonts and (unless lowmem) the Jagex logo from jagex.jag.
    public static func loadJagex(_ archive: JagArchive, into surface: Surface, lowmem: Bool = false) throws {
        if !lowmem, let logo = try archive.file("logo.tga") {
            try surface.parseSpriteTGA(id: SpriteBase.limit - 1, data: logo, columns: 0, rows: 0)
        }
        var fonts: [[Int8]] = []
        for name in fontFiles {
            guard let data = try archive.file(name) else { break }
            fonts.append(data.map { Int8(bitPattern: $0) })
        }
        surface.fonts = fonts
    }

    /// Loads the 2D media sprites from a .dat-format media archive (version >= 28).
    public static func loadMedia(_ archive: JagArchive, into surface: Surface, gameData: GameData,
                                 version: Int = 59, lowmem: Bool = false) throws {
        guard version >= 28 else { throw MediaError.missing("TGA media archives are not supported yet") }
        guard let index = try archive.file("index.dat") else { throw MediaError.missing("index.dat") }

        func parse(_ id: Int, _ name: String, _ frames: Int) throws {
            guard let data = try archive.file(name) else { throw MediaError.missing(name) }
            surface.parseSprite(id: id, spriteData: data, indexData: index, frameCount: frames)
        }

        let media = SpriteBase.media
        if version < 59 { try parse(media, "inv1.dat", 1) }
        try parse(media + 1, "inv2.dat", 6)
        try parse(media + 9, "bubble.dat", 1)
        if !lowmem { try parse(media + 10, "runescape.dat", 1) }
        try parse(media + 11, "splat.dat", 3)
        try parse(media + 14, "icon.dat", 8)
        if !lowmem { try parse(media + 22, "hbar.dat", 1) }
        try parse(media + 23, "hbar2.dat", 1)
        try parse(media + 24, "compass.dat", 1)
        try parse(media + 25, "buttons.dat", 2)
        if version >= 59 {
            try parse(media + 27, "labels.dat", 6)
            try parse(media + 33, "inv3.dat", 6)
            try parse(media + 39, "message.dat", 1)
            try parse(media + 40, "keyboard.dat", 1)
        }
        try parse(SpriteBase.util, "scrollbar.dat", 2)
        try parse(SpriteBase.util + 2, "corners.dat", 4)
        try parse(SpriteBase.util + 6, "arrows.dat", 2)
        try parse(SpriteBase.projectile, "projectile.dat", gameData.projectileSprite)

        var remaining = gameData.itemSpriteCount
        var file = 1
        while remaining > 0 {
            let count = min(remaining, 30)
            try parse(SpriteBase.item + (file - 1) * 30, "objects\(file).dat", count)
            remaining -= 30
            file += 1
        }

        if version >= 59 {
            for i in 0..<6 { surface.loadSprite(id: media + 33 + i) }
            surface.loadSprite(id: media + 39)
        } else {
            surface.loadSprite(id: media)
        }
        surface.loadSprite(id: media + 9)
        for i in 11...26 { surface.loadSprite(id: media + i) }
        for i in 0..<gameData.projectileSprite { surface.loadSprite(id: SpriteBase.projectile + i) }
        for i in 0..<gameData.itemSpriteCount { surface.loadSprite(id: SpriteBase.item + i) }
    }
}

extension MediaLoader {
    /// mudclient_load_textures: draws each texture (plus its overlay subtype) to the raster, turns it into a
    /// palette sprite and hands it to the scene. Uses the top-left 128x128 of the surface as scratch.
    public static func loadTextures(_ archive: JagArchive, into surface: Surface, scene: Scene,
                                    gameData: GameData) throws {
        guard let index = try archive.file("index.dat") else { throw MediaError.missing("index.dat") }
        let count = gameData.textures.count
        scene.allocateTextures(count: count, length64: 7, length128: 11)
        let scratch = SpriteBase.texture
        for i in 0..<count {
            guard let data = try archive.file("\(gameData.textures[i].name).dat") else { continue }
            surface.parseSprite(id: scratch, spriteData: data, indexData: index, frameCount: 1)
            surface.drawBox(x: 0, y: 0, width: 128, height: 128, colour: Colour.magenta)
            surface.drawSprite(x: 0, y: 0, id: scratch)
            surface.spritePalette[scratch] = nil
            surface.spriteColours[scratch] = nil
            let size = surface.spriteWidthFull[scratch]
            let sub = gameData.textures[i].subtypeName
            if !sub.isEmpty && sub.utf8.count <= 250 {
                if let subData = try archive.file("\(sub).dat") {
                    surface.parseSprite(id: scratch, spriteData: subData, indexData: index, frameCount: 1)
                    surface.drawSprite(x: 0, y: 0, id: scratch)
                }
                surface.spritePalette[scratch] = nil
                surface.spriteColours[scratch] = nil
            }
            let world = SpriteBase.textureWorld + i
            surface.screenRasterToSprite(id: world, x: 0, y: 0, width: size, height: size)
            if var px = surface.spritePixels[world] {
                for j in 0..<(size * size) where px[j] == Colour.green { px[j] = Colour.magenta }
                surface.spritePixels[world] = px
            }
            surface.screenRasterToPaletteSprite(id: world)
            scene.defineTexture(i, colours: surface.spriteColours[world] ?? [], palette: surface.spritePalette[world] ?? [],
                                wide128: size / 64 - 1 != 0)
            surface.spritePixels[world] = nil
        }
    }
}
