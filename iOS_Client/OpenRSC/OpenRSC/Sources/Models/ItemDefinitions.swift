import Foundation

enum ItemDefinitions {
    private struct ItemMeta {
        let stackable: Bool
        let commands: [String]
    }

    private static let itemsById: [Int: ItemMeta] = {
        guard let url = Bundle.main.url(forResource: "ItemDefs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["item"] as? [[String: Any]] else {
            return [:]
        }

        var parsed: [Int: ItemMeta] = [:]
        for item in items {
            guard let id = item["id"] as? Int else { continue }
            let stackable: Bool
            if let value = item["isStackable"] as? Int {
                stackable = value != 0
            } else if let value = item["isStackable"] as? Bool {
                stackable = value
            } else {
                stackable = false
            }

            let commands: [String]
            if let raw = item["command"] as? [String] {
                commands = raw
            } else if let raw = item["commands"] as? [String] {
                commands = raw
            } else if let raw = item["command"] as? String, !raw.isEmpty {
                commands = [raw]
            } else {
                commands = []
            }

            parsed[id] = ItemMeta(stackable: stackable, commands: commands)
        }
        return parsed
    }()

    private static let stackableIDs: Set<Int> = {
        Set(itemsById.compactMap { $0.value.stackable ? $0.key : nil })
    }()

    static func isStackable(_ id: Int, noted: Bool = false) -> Bool {
        noted || stackableIDs.contains(id)
    }

    static func commands(for id: Int) -> [String] {
        itemsById[id]?.commands ?? []
    }
}
