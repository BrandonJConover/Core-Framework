import Foundation

/// Names (and stack sizes) over items lying on the ground. Valuable stacks are coloured by worth, a hide list
/// removes clutter and a highlight list marks items you want to spot.
public final class GroundItemsPlugin: ClientPlugin {
	public let id = "groundItems"
	public let name = "Ground Items"
	public let summary = "Item names and quantities over ground items; highlights valuable stacks."
	public var enabled = false
	public let config = PluginConfig([
		.toggle("showQuantity", "Show quantity", true),
		.number("highlightValue", "Highlight stacks worth at least (gp)", 10_000, min: 0, max: 100_000_000, help: "0 turns value highlighting off. Value is the shop value times the amount."),
		.number("hideBelow", "Hide stacks worth less than (gp)", 0, min: 0, max: 1_000_000),
		.number("maxDistance", "Show within (tiles)", 12, min: 2, max: 30),
		.toggle("showValue", "Show value", false),
		.list("hidden", "Hidden items", [], help: "One name per line; * at the start or end matches any text."),
		.list("highlighted", "Highlighted items", [], help: "One name per line."),
	])
	public var subscriptions: PluginSubscription { [.overlayScene] }

	public init() {}

	public enum Tier: Equatable { case normal, valuable, highlighted }

	/// How a stack is shown, nil when it is hidden. Pure so it can be tested.
	public static func classify(name: String, value: Int, hidden: [String], highlighted: [String], highlightValue: Int, hideBelow: Int) -> Tier? {
		if PluginMatch.any(highlighted, name) { return .highlighted }
		if PluginMatch.any(hidden, name) { return nil }
		if value < hideBelow { return nil }
		if highlightValue > 0 && value >= highlightValue { return .valuable }
		return .normal
	}

	public static func colour(_ t: Tier, value: Int) -> UInt32 {
		switch t {
		case .highlighted: return 0xFF40FF
		case .valuable: return value >= 1_000_000 ? 0x40FF40 : 0x40E0FF
		case .normal: return 0xFFFFFF
		}
	}

	public func drawOverlay(_ layer: OverlayLayer, _ canvas: OverlayCanvas, into r: inout Raster) {
		guard layer == .scene, canvas.canProject, let me = canvas.ctx.selfActor else { return }
		let ctx = canvas.ctx
		let plane = ctx.plane
		let maxD = config.int("maxDistance")
		let hidden = config.list("hidden"), highlighted = config.list("highlighted")
		let highlightValue = config.int("highlightValue"), hideBelow = config.int("hideBelow")
		let showQty = config.bool("showQuantity"), showValue = config.bool("showValue")
		var drawn = 0
		for (key, stack) in ctx.groundStacks.sorted(by: { $0.key < $1.key }) where key >> 16 == plane {
			let x = (key >> 8) & 0xFF, z = key & 0xFF
			guard abs(x - me.tileX) <= maxD, abs(z - me.tileZ) <= maxD, let p = canvas.projectTileCenter(x: x, z: z, height: 0) else { continue }
			var line = 0
			for g in stack.reversed() {
				guard let item = ctx.item(g.type) else { continue }
				let value = item.cost * max(g.amount, 1)
				guard let tier = Self.classify(name: item.name, value: value, hidden: hidden, highlighted: highlighted, highlightValue: highlightValue, hideBelow: hideBelow) else { continue }
				var text = item.name
				if showQty && g.amount > 1 { text += " (\(PluginFormat.quantity(g.amount)))" }
				if showValue && value > 1 { text += " \(PluginFormat.quantity(value)) gp" }
				canvas.drawText(text, x: p.x, y: p.y - 4 - line * 12, color: Self.colour(tier, value: value), into: &r)
				line += 1
				drawn += 1
				if drawn > 120 { return }
			}
		}
	}
}
