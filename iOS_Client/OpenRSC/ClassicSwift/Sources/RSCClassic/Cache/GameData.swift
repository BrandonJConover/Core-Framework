// Item, NPC, object, wall, tile, spell and prayer definitions from
// config<N>.jag (string.dat + integer.dat). Port of rsc-c's game-data.c.

import Foundation

public enum RSCConstants {
    /// rsc-c's COLOUR_TRANSPARENT (INT16_MAX): "no fill" for faces.
    public static let colourTransparent = Int(Int16.max)
    /// The value the cache uses for transparent fills.
    static let jagexTransparent = 12345678
    public static let npcSpriteCount = 12
}

public struct ItemConfig {
    public var name: String
    public var description: String
    public var command: String
    public var sprite: Int
    public var basePrice: Int
    public var stackable: Int
    public var wearable: Int
    public var mask: Int
    public var special: Int
    public var members: Int
}

public struct NpcConfig {
    public var name: String
    public var description: String
    public var attack = 0, strength = 0, hits = 0, defense = 0, attackable = 0
    public var sprites = [Int](repeating: 0, count: RSCConstants.npcSpriteCount)
    public var hairColour = 0, topColour = 0, bottomColour = 0, skinColour = 0
    public var width = 0, height = 0
    public var walkSpeed = 0, combatSpeed = 0, combatWidth = 0
    public var command = ""
}

public struct TextureConfig {
    public var name: String
    public var subtypeName: String
}

public struct AnimationConfig {
    public var name: String
    public var colour = 0, gender = 0, hasA = 0, hasF = 0, fileId = 0
}

public struct ObjectConfig {
    public var name: String
    public var description: String
    public var command1 = "", command2 = ""
    public var modelIndex = 0
    public var width = 0, height = 0, type = 0, elevation = 0
}

public struct WallConfig {
    public var name: String
    public var description: String
    public var command1 = "", command2 = ""
    public var height = 0
    public var textureFront = 0, textureBack = 0
    public var blocking = 0, interactive = 0
}

public struct RoofConfig {
    public var height: Int
    public var fill: Int
}

public struct TileConfig {
    public var decoration: Int
    public var type: Int
    public var blocking: Int
}

public struct SpellConfig {
    public struct Rune {
        public var id = 0
        public var count = 0
    }
    public var name: String
    public var description: String
    public var level = 0, runesRequired = 0, type = 0
    public var runes: [Rune] = []
}

public struct PrayerConfig {
    public var name: String
    public var description: String
    public var level = 0, drain = 0
}

public struct GameData {
    public var items: [ItemConfig] = []
    public var npcs: [NpcConfig] = []
    public var textures: [TextureConfig] = []
    public var animations: [AnimationConfig] = []
    public var objects: [ObjectConfig] = []
    public var modelNames: [String] = []
    public var walls: [WallConfig] = []
    public var roofs: [RoofConfig] = []
    public var tiles: [TileConfig] = []
    public var projectileSprite = 0
    public var spells: [SpellConfig] = []
    public var prayers: [PrayerConfig] = []

    /// Highest item sprite id + 1 (rsc-c's item_sprite_count).
    public var itemSpriteCount: Int {
        (items.map(\.sprite).max() ?? -1) + 1
    }

    public init() {}

    /// Parses config<version>.jag. `members` swaps members items for the
    /// "Members object" placeholder when false, as the C client does.
    public init(config: JagArchive, members: Bool, version: Int) throws {
        guard let strings = try config.file("string.dat"),
              let integers = try config.file("integer.dat") else {
            throw JagArchiveError.badLength(expected: 1, actual: 0)
        }
        var r = Reader(strings: strings, integers: integers)

        let itemCount = r.u16()
        items = (0..<itemCount).map { _ in
            ItemConfig(name: "", description: "", command: "", sprite: 0, basePrice: 0,
                       stackable: 0, wearable: 0, mask: 0, special: 0, members: 0)
        }
        for i in 0..<itemCount { items[i].name = r.string() }
        for i in 0..<itemCount { items[i].description = r.string() }
        for i in 0..<itemCount { items[i].command = r.string() }
        for i in 0..<itemCount { items[i].sprite = r.u16() }
        for i in 0..<itemCount { items[i].basePrice = version < 49 ? r.u16() : r.int() }
        for i in 0..<itemCount { items[i].stackable = r.u8() }
        for _ in 0..<itemCount { _ = r.u8() } // unused
        for i in 0..<itemCount { items[i].wearable = r.u16() }
        for i in 0..<itemCount { items[i].mask = r.int() }
        for i in 0..<itemCount { items[i].special = version < 49 ? 0 : r.u8() }
        for i in 0..<itemCount { items[i].members = version < 49 ? 0 : r.u8() }
        if !members {
            for i in 0..<itemCount where items[i].members == 1 {
                items[i].name = "Members object"
                items[i].description = "You need to be a member to use this object"
                items[i].basePrice = 0
                items[i].command = ""
                items[i].wearable = 0
                items[i].special = 1
            }
        }

        let npcCount = r.u16()
        npcs = (0..<npcCount).map { _ in NpcConfig(name: "", description: "") }
        for i in 0..<npcCount { npcs[i].name = r.string() }
        for i in 0..<npcCount { npcs[i].description = r.string() }
        for i in 0..<npcCount { npcs[i].attack = r.u8() }
        for i in 0..<npcCount { npcs[i].strength = r.u8() }
        for i in 0..<npcCount { npcs[i].hits = r.u8() }
        for i in 0..<npcCount { npcs[i].defense = r.u8() }
        for i in 0..<npcCount { npcs[i].attackable = r.u8() }
        for i in 0..<npcCount {
            for j in 0..<RSCConstants.npcSpriteCount {
                let sprite = r.u8()
                npcs[i].sprites[j] = sprite == 255 ? -1 : sprite
            }
        }
        for i in 0..<npcCount { npcs[i].hairColour = r.int() }
        for i in 0..<npcCount { npcs[i].topColour = r.int() }
        for i in 0..<npcCount { npcs[i].bottomColour = r.int() }
        for i in 0..<npcCount { npcs[i].skinColour = r.int() }
        for i in 0..<npcCount { npcs[i].width = r.u16() }
        for i in 0..<npcCount { npcs[i].height = r.u16() }
        for i in 0..<npcCount { npcs[i].walkSpeed = r.u8() }
        for i in 0..<npcCount { npcs[i].combatSpeed = r.u8() }
        for i in 0..<npcCount { npcs[i].combatWidth = r.u8() }
        for i in 0..<npcCount { npcs[i].command = version < 57 ? "" : r.string() }

        let textureCount = r.u16()
        textures = (0..<textureCount).map { _ in TextureConfig(name: "", subtypeName: "") }
        for i in 0..<textureCount { textures[i].name = r.string() }
        for i in 0..<textureCount { textures[i].subtypeName = r.string() }

        let animationCount = r.u16()
        animations = (0..<animationCount).map { _ in AnimationConfig(name: "") }
        for i in 0..<animationCount { animations[i].name = r.string().lowercased() }
        for i in 0..<animationCount { animations[i].colour = r.int() }
        for i in 0..<animationCount { animations[i].gender = r.u8() }
        for i in 0..<animationCount { animations[i].hasA = r.u8() }
        for i in 0..<animationCount { animations[i].hasF = r.u8() }
        for i in 0..<animationCount { animations[i].fileId = r.u8() }

        let objectCount = r.u16()
        objects = (0..<objectCount).map { _ in ObjectConfig(name: "", description: "") }
        for i in 0..<objectCount { objects[i].name = r.string() }
        for i in 0..<objectCount { objects[i].description = r.string() }
        for i in 0..<objectCount { objects[i].command1 = r.string() }
        for i in 0..<objectCount { objects[i].command2 = r.string() }
        for i in 0..<objectCount { objects[i].modelIndex = modelIndex(r.string()) }
        for i in 0..<objectCount { objects[i].width = r.u8() }
        for i in 0..<objectCount { objects[i].height = r.u8() }
        for i in 0..<objectCount { objects[i].type = r.u8() }
        for i in 0..<objectCount { objects[i].elevation = r.u8() }

        let wallCount = r.u16()
        walls = (0..<wallCount).map { _ in WallConfig(name: "", description: "") }
        for i in 0..<wallCount { walls[i].name = r.string() }
        for i in 0..<wallCount { walls[i].description = r.string() }
        for i in 0..<wallCount { walls[i].command1 = r.string() }
        for i in 0..<wallCount { walls[i].command2 = r.string() }
        for i in 0..<wallCount { walls[i].height = r.u16() }
        for i in 0..<wallCount { walls[i].textureFront = Self.fill(r.int()) }
        for i in 0..<wallCount { walls[i].textureBack = Self.fill(r.int()) }
        for i in 0..<wallCount { walls[i].blocking = r.u8() }
        for i in 0..<wallCount { walls[i].interactive = r.u8() }

        let roofCount = r.u16()
        roofs = (0..<roofCount).map { _ in RoofConfig(height: 0, fill: 0) }
        for i in 0..<roofCount { roofs[i].height = r.u8() }
        for i in 0..<roofCount { roofs[i].fill = r.u8() }

        let tileCount = r.u16()
        tiles = (0..<tileCount).map { _ in TileConfig(decoration: 0, type: 0, blocking: 0) }
        for i in 0..<tileCount { tiles[i].decoration = Self.fill(r.int()) }
        for i in 0..<tileCount { tiles[i].type = r.u8() }
        for i in 0..<tileCount { tiles[i].blocking = r.u8() }

        projectileSprite = r.u16()

        let spellCount = r.u16()
        spells = (0..<spellCount).map { _ in SpellConfig(name: "", description: "") }
        for i in 0..<spellCount { spells[i].name = r.string() }
        for i in 0..<spellCount { spells[i].description = r.string() }
        for i in 0..<spellCount { spells[i].level = r.u8() }
        for i in 0..<spellCount { spells[i].runesRequired = r.u8() }
        for i in 0..<spellCount { spells[i].type = r.u8() }
        for i in 0..<spellCount {
            let amount = r.u8()
            spells[i].runes = (0..<amount).map { _ in SpellConfig.Rune(id: r.u16(), count: 0) }
        }
        for i in 0..<spellCount {
            let amount = r.u8()
            for j in 0..<amount {
                let count = r.u8()
                if j < spells[i].runes.count { spells[i].runes[j].count = count }
            }
        }

        let prayerCount = r.u16()
        prayers = (0..<prayerCount).map { _ in PrayerConfig(name: "", description: "") }
        for i in 0..<prayerCount { prayers[i].name = r.string() }
        for i in 0..<prayerCount { prayers[i].description = r.string() }
        for i in 0..<prayerCount { prayers[i].level = r.u8() }
        for i in 0..<prayerCount { prayers[i].drain = r.u8() }
    }

    /// rsc-c's game_data_get_model_index: models are named, "na" is model 0
    /// (no model) and new names are appended.
    public mutating func modelIndex(_ name: String) -> Int {
        let lower = name.lowercased()
        if lower == "na" { return 0 }
        if let index = modelNames.firstIndex(of: lower) { return index }
        modelNames.append(lower)
        return modelNames.count - 1
    }

    private static func fill(_ value: Int) -> Int {
        value == RSCConstants.jagexTransparent ? RSCConstants.colourTransparent : value
    }

    private struct Reader {
        let strings: [UInt8]
        let integers: [UInt8]
        var stringOffset = 0
        var offset = 0

        mutating func u8() -> Int {
            defer { offset += 1 }
            return Int(integers[offset])
        }

        mutating func u16() -> Int {
            defer { offset += 2 }
            return Int(integers[offset]) << 8 | Int(integers[offset + 1])
        }

        /// Signed 32-bit, with Jagex's "values above 99999999 are negative" rule.
        mutating func int() -> Int {
            defer { offset += 4 }
            let raw = UInt32(integers[offset]) << 24 | UInt32(integers[offset + 1]) << 16
                | UInt32(integers[offset + 2]) << 8 | UInt32(integers[offset + 3])
            let value = Int(Int32(bitPattern: raw))
            return value > 99_999_999 ? 99_999_999 - value : value
        }

        mutating func string() -> String {
            let start = stringOffset
            while strings[stringOffset] != 0 { stringOffset += 1 }
            let text = String(decoding: strings[start..<stringOffset].map { $0 }, as: Latin1.self)
            stringOffset += 1
            return text
        }
    }
}

/// ISO-8859-1 decoding (the cache's strings are single-byte).
enum Latin1: Unicode.Encoding {
    typealias CodeUnit = UInt8
    typealias EncodedScalar = CollectionOfOne<UInt8>
    static var encodedReplacementCharacter: EncodedScalar { CollectionOfOne(0x3f) }
    static func decode(_ content: EncodedScalar) -> Unicode.Scalar { Unicode.Scalar(content.first!) }
    static func encode(_ content: Unicode.Scalar) -> EncodedScalar? {
        content.value < 256 ? CollectionOfOne(UInt8(content.value)) : nil
    }
    struct ForwardParser: Unicode.Parser {
        typealias Encoding = Latin1
        init() {}
        mutating func parseScalar<I: IteratorProtocol>(from input: inout I)
            -> Unicode.ParseResult<EncodedScalar> where I.Element == UInt8 {
            guard let byte = input.next() else { return .emptyInput }
            return .valid(CollectionOfOne(byte))
        }
    }
    typealias ReverseParser = ForwardParser
}
