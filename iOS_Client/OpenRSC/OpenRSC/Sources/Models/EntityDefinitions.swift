// Minimal entity definitions stub for iOS client
// (Full EntityHandler.java port — minimal version for compilation)

import Foundation

struct TileDef {
    let colour: Int32
    var tileValue: Int = 0
    var objectType: Int = 0

    init(colour: Int32, tileValue: Int = 0, objectType: Int = 0) {
        self.colour = colour
        self.tileValue = tileValue
        self.objectType = objectType
    }
}

struct DoorDef {
    let name: String
    let description: String
    let command1: String
    let command2: String
    let doorType: Int
    let modelVar1: Int
    let modelVar2: Int
    let modelVar3: Int
    let unknown: Int

    init(name: String,
         description: String = "",
         command1: String = "WalkTo",
         command2: String = "Examine",
         doorType: Int = 0,
         modelVar1: Int = 100,
         modelVar2: Int = 0,
         modelVar3: Int = 0,
         unknown: Int = 0) {
        self.name = name
        self.description = description
        self.command1 = command1
        self.command2 = command2
        self.doorType = doorType
        self.modelVar1 = modelVar1
        self.modelVar2 = modelVar2
        self.modelVar3 = modelVar3
        self.unknown = unknown
    }

    var wallObjectHeight: Int { modelVar1 }
    var frontTexture: Int { modelVar2 }
    var backTexture: Int { modelVar3 }
}

struct ObjectDef {
    let name: String
    let description: String
    let command1: String
    let command2: String
    let type: Int
    let width: Int
    let height: Int
    let objectModel: Int
    let modelName: String
    let groundItemVar: Int

    init(name: String,
         description: String = "",
         command1: String = "WalkTo",
         command2: String = "Examine",
         type: Int = 0,
         width: Int = 1,
         height: Int = 1,
         objectModel: Int = 0,
         modelName: String = "",
         groundItemVar: Int = 0) {
        self.name = name
        self.description = description
        self.command1 = command1
        self.command2 = command2
        self.type = type
        self.width = width
        self.height = height
        self.objectModel = objectModel
        self.modelName = modelName
        self.groundItemVar = groundItemVar
    }
}

struct NPCDef {
    let name: String
    let combatLevel: Int = 1
}

struct ItemDef {
    let name: String = "Item"
}

enum EntityDefinitions {
    static let TRANSPARENT: Int32 = 12345678

    // Minimal fallback tile set used only if TileDef.xml is unavailable.
    private static let fallbackTiles: [TileDef] = (0..<25).map { i in
        let baseColor: Int32 = Int32(bitPattern: 0xFF808080)
        let color = baseColor &+ Int32(i * 0x101010)
        return TileDef(colour: color, tileValue: i, objectType: 0)
    }

    private(set) static var tiles: [TileDef] = fallbackTiles
    static let elevations: [ElevationDef] = [ElevationDef()]
    private static var didTryLoadingTiles = false
    private(set) static var doors: [DoorDef] = [DoorDef(name: "Door")]
    private(set) static var objects: [ObjectDef] = [ObjectDef(name: "Object")]
    static let npcs: [NPCDef] = [NPCDef(name: "NPC")]
    static let items: [ItemDef] = [ItemDef()]

    static var tileCount: Int {
        loadTileDefinitionsIfNeeded()
        return tiles.count
    }

    static var doorCount: Int {
        loadDoorDefinitionsIfNeeded()
        return doors.count
    }

    static var objectCount: Int {
        loadObjectDefinitionsIfNeeded()
        return objects.count
    }

    static func getTileDef(_ id: Int) -> TileDef? {
        loadTileDefinitionsIfNeeded()
        guard id >= 0 && id < tiles.count else { return nil }
        return tiles[id]
    }

    static func getDoorDef(_ id: Int) -> DoorDef? {
        loadDoorDefinitionsIfNeeded()
        guard id >= 0 && id < doors.count else { return nil }
        return doors[id]
    }

    static func getObjectDef(_ id: Int) -> ObjectDef? {
        loadObjectDefinitionsIfNeeded()
        guard id >= 0 && id < objects.count else { return nil }
        return objects[id]
    }

    static func getNPCDef(_ id: Int) -> NPCDef? {
        guard id >= 0 && id < npcs.count else { return nil }
        return npcs[id]
    }

    static func getItemDef(_ id: Int) -> ItemDef? {
        guard id >= 0 && id < items.count else { return nil }
        return items[id]
    }

    private static func loadTileDefinitionsIfNeeded() {
        guard !didTryLoadingTiles else { return }
        didTryLoadingTiles = true
        guard let path = Bundle.main.path(forResource: "TileDef", ofType: "xml"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let xml = String(data: data, encoding: .utf8) else {
            return
        }

        let blockPattern = #"<(?:[A-Za-z0-9_.]+\.)?TileDef>([\s\S]*?)</(?:[A-Za-z0-9_.]+\.)?TileDef>"#
        let parsed = allGroups(pattern: blockPattern, in: xml).compactMap { block -> TileDef? in
            guard let colourText = firstGroup(pattern: "<colour>([^<]*)</colour>", in: block),
                  let colour = Int32(colourText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }

            return TileDef(
                colour: colour,
                tileValue: Int(firstGroup(pattern: "<unknown>([^<]*)</unknown>", in: block) ?? "0") ?? 0,
                objectType: Int(firstGroup(pattern: "<objectType>([^<]*)</objectType>", in: block) ?? "0") ?? 0
            )
        }

        if !parsed.isEmpty {
            tiles = parsed
            print("[TileDef] Loaded \(tiles.count) tile definitions")
        }
    }

    private static func loadDoorDefinitionsIfNeeded() {
        guard doors.count == 1, doors[0].name == "Door",
              let path = Bundle.main.path(forResource: "DoorDef", ofType: "xml"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let xml = String(data: data, encoding: .utf8) else {
            return
        }

        let blockPattern = #"<(?:[A-Za-z0-9_.]+\.)?DoorDef>([\s\S]*?)</(?:[A-Za-z0-9_.]+\.)?DoorDef>"#
        let parsed = allGroups(pattern: blockPattern, in: xml).compactMap { block -> DoorDef? in
            guard block.contains("<name>") else { return nil }
            let name = firstGroup(pattern: "<name>([^<]*)</name>", in: block) ?? ""
            return DoorDef(
                name: xmlUnescaped(name),
                description: xmlUnescaped(firstGroup(pattern: "<description>([^<]*)</description>", in: block) ?? ""),
                command1: xmlUnescaped(firstGroup(pattern: "<command1>([^<]*)</command1>", in: block) ?? ""),
                command2: xmlUnescaped(firstGroup(pattern: "<command2>([^<]*)</command2>", in: block) ?? ""),
                doorType: Int(firstGroup(pattern: "<doorType>([^<]*)</doorType>", in: block) ?? "0") ?? 0,
                modelVar1: Int(firstGroup(pattern: "<modelVar1>([^<]*)</modelVar1>", in: block) ?? "100") ?? 100,
                modelVar2: Int(firstGroup(pattern: "<modelVar2>([^<]*)</modelVar2>", in: block) ?? "0") ?? 0,
                modelVar3: Int(firstGroup(pattern: "<modelVar3>([^<]*)</modelVar3>", in: block) ?? "0") ?? 0,
                unknown: Int(firstGroup(pattern: "<unknown>([^<]*)</unknown>", in: block) ?? "0") ?? 0
            )
        }

        if !parsed.isEmpty {
            doors = parsed
            print("[DoorDef] Loaded \(doors.count) door definitions")
        }
    }

    private static func loadObjectDefinitionsIfNeeded() {
        guard objects.count == 1, objects[0].name == "Object",
              let path = Bundle.main.path(forResource: "GameObjectDef", ofType: "xml"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let xml = String(data: data, encoding: .utf8) else {
            return
        }

        let blockPattern = #"<(?:[A-Za-z0-9_.]+\.)?GameObjectDef>([\s\S]*?)</(?:[A-Za-z0-9_.]+\.)?GameObjectDef>"#
        let parsed = allGroups(pattern: blockPattern, in: xml).compactMap { block -> ObjectDef? in
            guard block.contains("<name>") else { return nil }
            let modelName = xmlUnescaped(firstGroup(pattern: "<objectModel>([^<]*)</objectModel>", in: block) ?? "")
            return ObjectDef(
                name: xmlUnescaped(firstGroup(pattern: "<name>([^<]*)</name>", in: block) ?? ""),
                description: xmlUnescaped(firstGroup(pattern: "<description>([^<]*)</description>", in: block) ?? ""),
                command1: xmlUnescaped(firstGroup(pattern: "<command1>([^<]*)</command1>", in: block) ?? ""),
                command2: xmlUnescaped(firstGroup(pattern: "<command2>([^<]*)</command2>", in: block) ?? ""),
                type: Int(firstGroup(pattern: "<type>([^<]*)</type>", in: block) ?? "0") ?? 0,
                width: Int(firstGroup(pattern: "<width>([^<]*)</width>", in: block) ?? "1") ?? 1,
                height: Int(firstGroup(pattern: "<height>([^<]*)</height>", in: block) ?? "1") ?? 1,
                objectModel: Int(modelName) ?? 0,
                modelName: modelName,
                groundItemVar: Int(firstGroup(pattern: "<groundItemVar>([^<]*)</groundItemVar>", in: block) ?? "0") ?? 0
            )
        }

        if !parsed.isEmpty {
            objects = parsed
            print("[ObjectDef] Loaded \(objects.count) object definitions")
        }
    }

    private static func firstGroup(pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let match = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func allGroups(pattern: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return ns.substring(with: match.range(at: 1))
        }
    }

    private static func xmlUnescaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}

struct ElevationDef {
    let unknown1: Int = 0
    let unknown2: Int = 0
}
