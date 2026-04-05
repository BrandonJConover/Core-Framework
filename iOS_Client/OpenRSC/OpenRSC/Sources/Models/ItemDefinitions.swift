import Foundation

enum ItemDefinitions {
    static func isStackable(itemId: Int) -> Bool {
        shared.stackableItemIds.contains(itemId)
    }

    private static let shared = Store()

    private final class Store {
        let stackableItemIds: Set<Int>

        init(bundle: Bundle = .main) {
            stackableItemIds = Self.loadStackableItemIds(bundle: bundle)
        }

        private static func loadStackableItemIds(bundle: Bundle) -> Set<Int> {
            guard let url = bundle.url(forResource: "ItemDefs", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let document = try? JSONDecoder().decode(ItemDefinitionsDocument.self, from: data) else {
                print("[ItemDefinitions] Failed to load bundled ItemDefs.json")
                return []
            }

            return Set(document.item.compactMap { definition in
                definition.isStackable != 0 ? definition.id : nil
            })
        }
    }
}

private struct ItemDefinitionsDocument: Decodable {
    let item: [ItemDefinitionEntry]
}

private struct ItemDefinitionEntry: Decodable {
    let id: Int
    let isStackable: Int
}
