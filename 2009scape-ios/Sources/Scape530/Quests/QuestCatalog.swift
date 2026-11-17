import Foundation

/// Every authored quest guide. The data lives in the `QuestCatalog+*.swift` files, one per area.
public enum QuestCatalog {
	public static let all: [QuestDef] = lumbridge + draynor + varrock + falador + portSarimAlKharid + goblinVillage

	public static let byId: [String: QuestDef] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

	/// Varbit ids that step conditions read besides the list varbits (the plugin decodes these through the cache).
	public static let extraVarbits: [Int] = varbits(in: all)

	public static func varbits(in defs: [QuestDef]) -> [Int] {
		var out = Set<Int>()
		func scan(_ c: QuestCondition) {
			switch c {
			case .varbit(let id, _): out.insert(id)
			case .not(let i): scan(i)
			case .any(let l), .all(let l): l.forEach(scan)
			default: break
			}
		}
		for d in defs {
			d.steps.forEach { $0.when.forEach(scan) }
			d.latches.forEach { $0.when.forEach(scan) }
		}
		return out.sorted()
	}

	/// Item ids of every quest item, for icons and tests.
	public static var itemIds: Set<Int> { Set(all.flatMap { $0.steps.flatMap { $0.items.map(\.id) } }) }
}
