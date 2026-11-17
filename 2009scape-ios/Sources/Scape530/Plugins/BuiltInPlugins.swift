import Foundation

/// The plugins every client ships with, in the order the settings list shows them.
enum BuiltInPlugins {
	static func all() -> [ClientPlugin] {
		[
			MenuEntrySwapperPlugin(),
			GroundItemsPlugin(),
			TileIndicatorsPlugin(),
			XpDropsPlugin(),
			XpTrackerPlugin(),
			IdleNotifierPlugin(),
			ItemPricesPlugin(),
			BoostsPlugin(),
			QuestHelperPlugin(),
		]
	}
}

/// Name matching for plugin lists: case-insensitive, `*` at either end matches anything.
public enum PluginMatch {
	public static func name(_ pattern: String, _ name: String) -> Bool {
		var p = pattern.trimmingCharacters(in: .whitespaces).lowercased()
		let n = name.trimmingCharacters(in: .whitespaces).lowercased()
		if p.isEmpty { return false }
		let lead = p.hasPrefix("*"), trail = p.hasSuffix("*") && p.count > 1
		if lead { p.removeFirst() }
		if trail { p.removeLast() }
		if p.isEmpty { return true }
		if lead && trail { return n.contains(p) }
		if lead { return n.hasSuffix(p) }
		if trail { return n.hasPrefix(p) }
		return n == p
	}

	public static func any(_ patterns: [String], _ name: String) -> Bool { patterns.contains { Self.name($0, name) } }
}
