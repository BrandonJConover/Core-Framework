// Loads GameObjectDef.xml for trees, rocks, doors, buildings.
// RSC uses 3D models for objects, but for a 2D isometric projection we
// can render objects as colored blocks + icon sprites from the sprites archive.

import Foundation

struct GameObjectDefinition {
    let id: Int
    let name: String
    let description: String
    let type: Int
    let width: Int
    let height: Int
    let modelID: String
}

enum GameObjectDefinitions {
    private(set) static var defs: [GameObjectDefinition] = []
    static var isLoaded: Bool { !defs.isEmpty }

    /// Minimal XML parser for GameObjectDef.xml — XML is produced by XStream and
    /// looks like:
    ///     <list>
    ///       <com.openrsc.GameObjectDef>
    ///         <name>Tree</name> ...
    ///       </com.openrsc.GameObjectDef>
    ///     </list>
    /// We only need name + dimensions for now.
    static func loadArchive() {
        guard let path = Bundle.main.path(forResource: "GameObjectDef", ofType: "xml"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("[ObjectDef] GameObjectDef.xml not found")
            return
        }
        // Lightweight regex-based extraction since XMLParser would be heavy for
        // the scope we need. We grab <name>...</name>, <width>, <height>, <type>
        // per <com.openrsc.client.entityhandling.defs.GameObjectDef> block.
        guard let xml = String(data: data, encoding: .utf8) else { return }
        var parsed: [GameObjectDefinition] = []
        // Split on closing tags to get per-object chunks
        let blocks = xml.components(separatedBy: "</com.openrsc.client.entityhandling.defs.GameObjectDef>")
        var idCounter = 0
        for block in blocks where block.contains("<name>") {
            let name = firstGroup(pattern: "<name>([^<]*)</name>", in: block) ?? ""
            let desc = firstGroup(pattern: "<description>([^<]*)</description>", in: block) ?? ""
            let type = Int(firstGroup(pattern: "<type>([^<]*)</type>", in: block) ?? "0") ?? 0
            let width = Int(firstGroup(pattern: "<width>([^<]*)</width>", in: block) ?? "1") ?? 1
            let height = Int(firstGroup(pattern: "<height>([^<]*)</height>", in: block) ?? "1") ?? 1
            let modelID = firstGroup(pattern: "<objectModel>([^<]*)</objectModel>", in: block) ?? ""
            parsed.append(GameObjectDefinition(
                id: idCounter, name: name, description: desc, type: type,
                width: width, height: height, modelID: modelID
            ))
            idCounter += 1
        }
        defs = parsed
        print("[ObjectDef] Loaded \(defs.count) object definitions")
    }

    static func get(_ id: Int) -> GameObjectDefinition? {
        guard id >= 0 && id < defs.count else { return nil }
        return defs[id]
    }

    private static func firstGroup(pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
