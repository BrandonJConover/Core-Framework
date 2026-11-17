import Foundation

/// Helpers for plugins that edit a menu. Index 0 is always Cancel and the last entry is the default (tap) action.
public extension Menu {
	/// The plain target of entry `i` ("Banker" for "<col=ffff00>Banker<col=ffb000> (level: 5)").
	func target(_ i: Int) -> String { PluginFormat.plainTarget(entries[i].base) }

	/// Makes entry `i` the default entry by moving it to the end. Cancel (index 0) cannot move.
	mutating func promote(_ i: Int) {
		guard i > 0, i < entries.count - 1 else { return }
		entries.append(entries.remove(at: i))
	}

	/// Moves entry `i` to just above Cancel, the last place a tap would pick.
	mutating func demote(_ i: Int) {
		guard i > 1, i < entries.count else { return }
		entries.insert(entries.remove(at: i), at: 1)
	}

	/// Removes entry `i` (never Cancel).
	mutating func remove(at i: Int) {
		guard i > 0, i < entries.count else { return }
		entries.remove(at: i)
	}

	/// Replaces the entry's verb and optionally its target text; the action and key stay, so it still does the same thing.
	mutating func rename(_ i: Int, op: String? = nil, base: String? = nil) {
		guard i > 0, i < entries.count else { return }
		if let op { entries[i].op = op }
		if let base { entries[i].base = base }
	}

	/// Adds an entry just above Cancel, or as the new default (last) entry with `atTop`.
	mutating func insert(_ e: Entry, atTop: Bool = false) {
		guard entries.count < 500 else { return }
		if atTop { entries.append(e) } else { entries.insert(e, at: 1) }
	}
}
