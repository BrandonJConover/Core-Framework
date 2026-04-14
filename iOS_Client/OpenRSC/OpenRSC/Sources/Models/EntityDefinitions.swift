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
    let doorType: Int = 0
    let wallObjectHeight: Int = 100
}

struct ObjectDef {
    let name: String
    let type: Int = 0
    let width: Int = 1
    let height: Int = 1
    let objectModel: Int = 0
    let groundItemVar: Int = 0
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

    // Minimal tile set
    static let tiles: [TileDef] = (0..<25).map { i in
        let baseColor: Int32 = Int32(bitPattern: 0xFF808080)
        let color = baseColor &+ Int32(i * 0x101010)
        return TileDef(colour: color, tileValue: i, objectType: 0)
    }

    static let elevations: [ElevationDef] = [ElevationDef()]
    static let doors: [DoorDef] = [DoorDef(name: "Door")]
    static let objects: [ObjectDef] = [ObjectDef(name: "Object")]
    static let npcs: [NPCDef] = [NPCDef(name: "NPC")]
    static let items: [ItemDef] = [ItemDef()]

    static func getTileDef(_ id: Int) -> TileDef? {
        guard id >= 0 && id < tiles.count else { return nil }
        return tiles[id]
    }

    static func getDoorDef(_ id: Int) -> DoorDef? {
        guard id >= 0 && id < doors.count else { return nil }
        return doors[id]
    }

    static func getObjectDef(_ id: Int) -> ObjectDef? {
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
}

struct ElevationDef {
    let unknown1: Int = 0
    let unknown2: Int = 0
}
