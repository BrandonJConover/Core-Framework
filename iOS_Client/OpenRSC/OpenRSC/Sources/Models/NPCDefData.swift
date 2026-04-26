// Loads NpcDefs.json (server-side authoritative NPC definitions) and exposes
// the per-NPC sprite array. Each NPCDef has 12 sprite slots (head, shirt, pants,
// shield, weapon, hat, body, legs, gloves, boots, amulet, cape) where each
// slot is an animation index into AnimationTable (or -1 if unused).
//
// At runtime, the Java client maps animation index -> animation.number ->
// sprite-archive ID via AnimationTable.assignNumbers().

import Foundation

struct NPCDefData {
    let id: Int
    let name: String
    let description: String
    let combatLevel: Int
    /// 12-slot animation indices (head, shirt, pants, shield, weapon, hat, body, legs, gloves, boots, amulet, cape)
    let sprites: [Int]
    let hairColour: Int32
    let topColour: Int32
    let bottomColour: Int32
    let skinColour: Int32
    let walkModel: Int
    let combatSprite: Int
}

enum NPCDefTable {
    private(set) static var defs: [NPCDefData] = []
    static var isLoaded: Bool { !defs.isEmpty }

    static func loadIfNeeded() {
        guard defs.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "NpcDefs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("[NPCDefData] NpcDefs.json not found in bundle")
            return
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["npcs"] as? [[String: Any]] else {
            print("[NPCDefData] JSON parse failed")
            return
        }
        var parsed: [NPCDefData] = []
        parsed.reserveCapacity(arr.count)
        for j in arr {
            let sprites: [Int] = (1...12).map { idx in (j["sprites\(idx)"] as? Int) ?? -1 }
            parsed.append(NPCDefData(
                id: (j["id"] as? Int) ?? 0,
                name: (j["name"] as? String) ?? "NPC",
                description: (j["description"] as? String) ?? "",
                combatLevel: (j["combatlvl"] as? Int) ?? 0,
                sprites: sprites,
                hairColour: Int32(truncatingIfNeeded: (j["hairColour"] as? Int) ?? 0),
                topColour: Int32(truncatingIfNeeded: (j["topColour"] as? Int) ?? 0),
                bottomColour: Int32(truncatingIfNeeded: (j["bottomColour"] as? Int) ?? 0),
                skinColour: Int32(truncatingIfNeeded: (j["skinColour"] as? Int) ?? 0),
                walkModel: (j["walkModel"] as? Int) ?? 6,
                combatSprite: (j["combatSprite"] as? Int) ?? 5
            ))
        }
        defs = parsed
        print("[NPCDefData] Loaded \(defs.count) NPC defs from NpcDefs.json")
    }

    static func get(_ id: Int) -> NPCDefData? {
        guard id >= 0 && id < defs.count else { return nil }
        return defs[id]
    }
}
