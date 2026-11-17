import Foundation

/// A plain-data `QuestFacts`: the plugin fills one per game tick, tests and bots build their own.
public struct QuestFactsSnapshot: QuestFacts {
	public var varps: [Int: Int] = [:]
	public var varbits: [Int: Int] = [:]
	public var inventory: [Int: Int] = [:]
	public var worn: [Int: Int] = [:]
	public var bank: [Int: Int] = [:]
	public var flags: Set<String> = []
	/// Last journal seen per quest name.
	public var journals: [String: QuestJournal] = [:]

	public init() {}

	public func varp(_ id: Int) -> Int { varps[id] ?? 0 }
	public func varbit(_ id: Int) -> Int { varbits[id] ?? 0 }
	public func carried(_ item: Int) -> Int { (inventory[item] ?? 0) + (worn[item] ?? 0) }
	public func banked(_ item: Int) -> Int { bank[item] ?? 0 }
	public func flag(_ name: String) -> Bool { flags.contains(name) }
	public func journal(of quest: String) -> QuestJournal? { journals[quest] }

	/// Adds `count` of an item to the backpack.
	public mutating func give(_ item: Int, _ count: Int = 1) { inventory[item, default: 0] += count }
}

/// The rt4 inventory ids of the 2009 interfaces.
public enum QuestContainers {
	public static let backpack = 93, equipment = 94, bank = 95
}

public extension QuestFactsSnapshot {
	/// Folds the client's inventories (`GameState.inventories`) and varps into counts.
	static func from(varps: [Int: Int32], inventories: [Int: [Int: ServerMessage.InvItem]]) -> QuestFactsSnapshot {
		var s = QuestFactsSnapshot()
		for (k, v) in varps { s.varps[k] = Int(v) }
		func count(_ inv: Int) -> [Int: Int] {
			var out: [Int: Int] = [:]
			for it in (inventories[inv] ?? [:]).values where it.id >= 0 { out[it.id, default: 0] += max(Int(it.count), 1) }
			return out
		}
		s.inventory = count(QuestContainers.backpack)
		s.worn = count(QuestContainers.equipment)
		s.bank = count(QuestContainers.bank)
		return s
	}
}
