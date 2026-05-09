// Loads NPC definitions from NpcDefs.json at app launch.
// Each NPC has a 12-slot sprite array (head, shirt, pants, shield, weapon,
// hat, body, legs, gloves, boots, amulet, cape). Each slot is an animation
// ID (-1 means unused). AnimationDefs.animations[animID].number gives the
// base sprite index in sprites.dat.

import Foundation

struct NPCDefinition {
    let id: Int
    let name: String
    let description: String
    let command: String
    let command2: String
    let attack: Int
    let strength: Int
    let hits: Int
    let defense: Int
    let combatLevel: Int
    let attackable: Bool
    let aggressive: Bool
    let respawnTime: Int
    /// 12 animation IDs — head, shirt, pants, shield, weapon, hat, body, legs, gloves, boots, amulet, cape
    let sprites: [Int]
    let hairColour: Int
    let topColour: Int
    let bottomColour: Int
    let skinColour: Int
    let camera1: Int
    let camera2: Int
    let walkModel: Int
    let combatModel: Int
    let combatSprite: Int
}

enum NPCDefinitions {
    private(set) static var defs: [NPCDefinition] = []
    static var isLoaded: Bool { !defs.isEmpty }

    static func loadArchive() {
        guard let path = Bundle.main.path(forResource: "NpcDefs", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("[NPCDef] NpcDefs.json not found in bundle")
            return
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["npcs"] as? [[String: Any]] else {
            print("[NPCDef] JSON parse failed")
            return
        }
        var parsed: [NPCDefinition] = []
        parsed.reserveCapacity(arr.count)
        for j in arr {
            let sprites: [Int] = (1...12).map { idx in
                (j["sprites\(idx)"] as? Int) ?? -1
            }
            let attackableInt = (j["attackable"] as? Int) ?? 0
            let aggressiveInt = (j["aggressive"] as? Int) ?? 0
            parsed.append(NPCDefinition(
                id: (j["id"] as? Int) ?? 0,
                name: (j["name"] as? String) ?? "NPC",
                description: (j["description"] as? String) ?? "",
                command: (j["command"] as? String) ?? "",
                command2: (j["command2"] as? String) ?? "",
                attack: (j["attack"] as? Int) ?? 0,
                strength: (j["strength"] as? Int) ?? 0,
                hits: (j["hits"] as? Int) ?? 0,
                defense: (j["defense"] as? Int) ?? 0,
                combatLevel: (j["combatlvl"] as? Int) ?? 0,
                attackable: attackableInt != 0,
                aggressive: aggressiveInt != 0,
                respawnTime: (j["respawnTime"] as? Int) ?? 0,
                sprites: sprites,
                hairColour: (j["hairColour"] as? Int) ?? 0,
                topColour: (j["topColour"] as? Int) ?? 0,
                bottomColour: (j["bottomColour"] as? Int) ?? 0,
                skinColour: (j["skinColour"] as? Int) ?? 0,
                camera1: (j["camera1"] as? Int) ?? 0,
                camera2: (j["camera2"] as? Int) ?? 0,
                walkModel: (j["walkModel"] as? Int) ?? 6,
                combatModel: (j["combatModel"] as? Int) ?? 6,
                combatSprite: (j["combatSprite"] as? Int) ?? 5
            ))
        }
        defs = parsed
        print("[NPCDef] Loaded \(defs.count) NPC definitions")
    }

    static func get(_ id: Int) -> NPCDefinition? {
        guard id >= 0 && id < defs.count else { return nil }
        return defs[id]
    }

    static func upsert(_ def: NPCDefinition) {
        guard def.id >= 0 else { return }
        if def.id >= defs.count {
            defs.append(contentsOf: (defs.count...def.id).map { placeholder(id: $0) })
        }
        defs[def.id] = def
    }

    private static func placeholder(id: Int) -> NPCDefinition {
        NPCDefinition(
            id: id,
            name: "NPC \(id)",
            description: "",
            command: "",
            command2: "",
            attack: 0,
            strength: 0,
            hits: 0,
            defense: 0,
            combatLevel: 0,
            attackable: false,
            aggressive: false,
            respawnTime: 0,
            sprites: Array(repeating: -1, count: 12),
            hairColour: 0,
            topColour: 0,
            bottomColour: 0,
            skinColour: 0,
            camera1: 0,
            camera2: 0,
            walkModel: 6,
            combatModel: 6,
            combatSprite: 5
        )
    }

    /// Reproduces mudclient.loadEntitiesAuthentic() — assigns sprite-archive offsets
    /// to each AnimationDef.number. Each unique animation name consumes 27 sprite
    /// slots (15 walk + 3 combat-A + 9 combat-F). Range 1998..<3300 is reserved
    /// for UI sprites and skipped.
    static func assignAnimationNumbers() {
        var animationNumber = 0
        let n = AnimationDefs.animations.count
        var nameToNumber: [String: Int] = [:]
        for i in 0..<n {
            let name = AnimationDefs.animations[i].name.lowercased()
            if let existing = nameToNumber[name] {
                AnimationDefs.animations[i].number = existing
                continue
            }
            AnimationDefs.animations[i].number = animationNumber
            nameToNumber[name] = animationNumber
            animationNumber += 27
            if animationNumber == 1998 {
                animationNumber = 3300
            }
        }
        print("[AnimDef] Assigned numbers to \(n) animations, final=\(animationNumber)")
    }
}
