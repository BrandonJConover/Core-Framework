import Foundation

struct ItemCommandOption: Identifiable, Equatable {
    let index: Int
    let label: String

    var id: Int { index }

    var isPrimaryTapAction: Bool {
        ItemDefinitions.isPrimaryTapCommand(label)
    }
}

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

    static func commandOptions(for id: Int) -> [ItemCommandOption] {
        (itemsById[id]?.commands ?? []).enumerated().compactMap { index, command in
            let label = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, label.lowercased() != "null" else { return nil }
            return ItemCommandOption(index: index, label: label)
        }
    }

    static func primaryTapCommand(for id: Int) -> ItemCommandOption? {
        commandOptions(for: id).first { $0.isPrimaryTapAction }
    }

    static func isPrimaryTapCommand(_ label: String) -> Bool {
        switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "eat", "drink", "bury", "light", "read", "open", "search", "rub", "empty":
            return true
        default:
            return false
        }
    }
}
