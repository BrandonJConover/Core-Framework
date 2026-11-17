import Foundation

/// Chooses which option a tap runs. A tap on something runs the default (last) menu entry; this plugin moves the
/// option a rule names to that place, so "Bank" can be the tap on bankers, while a
/// long press still lists everything.
public final class MenuEntrySwapperPlugin: ClientPlugin {
	public let id = "menuSwapper"
	public let name = "Menu Entry Swapper"
	public let summary = "Pick the option a tap runs for each target, for example Bank on bankers."
	public let defaultEnabled = true
	public var enabled = true
	public static let defaultRules = [
		"Banker=Bank",
		"Bank booth=Bank",
		"Furnace=Smelt",
		"Spinning wheel=Spin",
		"Anvil=Smith",
	]
	public let config = PluginConfig([
		.list("rules", "Rules", MenuEntrySwapperPlugin.defaultRules, help: "One per line as Target=Option. * at the start or end of a target matches any text; the target * matches everything."),
		.toggle("inventory", "Also swap inventory items", true, help: "For example Shark=Eat."),
	])
	public var subscriptions: PluginSubscription { [.menu] }

	public init() {}

	public struct Rule: Equatable {
		public var target: String
		public var option: String

		public init?(_ line: String) {
			guard let eq = line.firstIndex(of: "=") else { return nil }
			let t = line[..<eq].trimmingCharacters(in: .whitespaces)
			let o = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
			guard !t.isEmpty, !o.isEmpty else { return nil }
			target = t
			option = o
		}
	}

	public static func parse(_ lines: [String]) -> [Rule] { lines.compactMap(Rule.init) }

	/// Applies the first rule that matches an entry of the menu (top entries first). Returns true when the default entry
	/// is now the one a rule picked, whether it was moved or already there.
	@discardableResult
	public static func apply(_ rules: [Rule], to menu: inout Menu) -> Bool {
		guard menu.count > 1, !rules.isEmpty else { return false }
		var i = menu.count - 1
		while i >= 1 {
			let e = menu.entries[i]
			defer { i -= 1 }
			guard e.action != Menu.Action.walkHere, e.action != Menu.Action.cancel, !e.base.isEmpty else { continue }
			let target = menu.target(i)
			for rule in rules where PluginMatch.name(rule.target, target) || rule.target == "*" {
				// The option has to belong to the same target (same coloured text) as the entry that matched.
				guard let j = menu.entries.indices.last(where: { $0 >= 1 && menu.entries[$0].base == e.base && menu.entries[$0].op.caseInsensitiveCompare(rule.option) == .orderedSame }) else { continue }
				if j != menu.count - 1 { menu.promote(j) }
				return true
			}
		}
		return false
	}

	public func modifyMenu(_ menu: inout Menu, source: MenuSource, _ ctx: PluginContext) {
		if source == .inventory && !config.bool("inventory") { return }
		Self.apply(Self.parse(config.list("rules")), to: &menu)
	}
}
