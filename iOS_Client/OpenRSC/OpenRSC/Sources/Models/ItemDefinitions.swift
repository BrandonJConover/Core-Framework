import Foundation

enum ItemDefinitions {
    private static let stackableIDs: Set<Int> = {
        guard let url = Bundle.main.url(forResource: "ItemDefs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["item"] as? [[String: Any]] else {
            return []
        }

        var ids = Set<Int>()
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
            if stackable {
                ids.insert(id)
            }
        }
        return ids
    }()

    static func isStackable(_ id: Int, noted: Bool = false) -> Bool {
        noted || stackableIDs.contains(id)
    }
}
