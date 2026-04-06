import Foundation

enum ItemDefinitions {
    static func isStackable(itemId: Int) -> Bool {
        shared.stackableItemIds.contains(itemId)
    }

    static func appearanceId(itemId: Int) -> Int? {
        shared.appearanceByItemId[itemId]
    }

    private static let shared = Store()

    private final class Store {
        let stackableItemIds: Set<Int>
        let appearanceByItemId: [Int: Int]

        init(bundle: Bundle = .main) {
            let definitions = Self.loadDefinitions(bundle: bundle)
            stackableItemIds = Set(definitions.compactMap { definition in
                definition.isStackable != 0 ? definition.id : nil
            })
            appearanceByItemId = Dictionary(uniqueKeysWithValues: definitions.map { definition in
                (definition.id, definition.appearanceID)
            })
        }

        private static func loadDefinitions(bundle: Bundle) -> [ItemDefinitionEntry] {
            guard let url = bundle.url(forResource: "ItemDefs", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let document = try? JSONDecoder().decode(ItemDefinitionsDocument.self, from: data) else {
                print("[ItemDefinitions] Failed to load bundled ItemDefs.json")
                return []
            }

            return document.item
        }
    }
}

private struct ItemDefinitionsDocument: Decodable {
    let item: [ItemDefinitionEntry]
}

private struct ItemDefinitionEntry: Decodable {
    let id: Int
    let isStackable: Int
    let appearanceID: Int
}
