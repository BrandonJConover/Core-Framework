import Foundation

public struct PriceTotals: Equatable {
	public var inventory = 0
	public var equipment = 0
	public var bank = 0
	public var all: Int { inventory + equipment + bank }
}

/// Values on items: " (N gp)" on Examine entries and totals of the inventory, equipment and bank.
/// The cache only knows an item's shop value (the high alchemy base), so that is what is shown; a Grand
/// Exchange price feed can replace `price(for:)` later.
public final class ItemPricesPlugin: ClientPlugin {
	public let id = "itemPrices"
	public let name = "Item Prices"
	public let summary = "Shows an item's value on its Examine option, and the total value of what you carry."
	public var enabled = false
	public let config = PluginConfig([
		.toggle("examine", "Value on Examine", true),
		.toggle("total", "Show inventory total on screen", false),
	])
	public var subscriptions: PluginSubscription {
		var s: PluginSubscription = [.containers]
		if config.bool("examine") { s.insert(.menu) }
		if config.bool("total") { s.insert(.overlayHUD) }
		return s
	}

	/// rt4 inventory ids of the 2009 interfaces.
	public enum Container { public static let backpack = 93, equipment = 94, bank = 95 }

	private var totals_ = PriceTotals()
	private let lock = NSLock()
	public var totals: PriceTotals { lock.lock(); defer { lock.unlock() }; return totals_ }

	public init() {}

	public func price(for item: ItemInfo) -> Int { item.cost }

	public func startUp(_ ctx: PluginContext) { recompute(ctx) }
	public func onLogin(_ ctx: PluginContext) { lock.lock(); totals_ = PriceTotals(); lock.unlock() }
	public func onContainerChanged(_ change: ContainerChange, _ ctx: PluginContext) { recompute(ctx) }

	func recompute(_ ctx: PluginContext) {
		let inv = ctx.state.inventories
		func sum(_ id: Int) -> Int {
			(inv[id] ?? [:]).values.reduce(0) { acc, it in
				guard it.id >= 0, let info = ctx.item(it.id) else { return acc }
				return acc + price(for: info) * Int(it.count)
			}
		}
		let t = PriceTotals(inventory: sum(Container.backpack), equipment: sum(Container.equipment), bank: sum(Container.bank))
		lock.lock(); totals_ = t; lock.unlock()
	}

	public func modifyMenu(_ menu: inout Menu, source: MenuSource, _ ctx: PluginContext) {
		guard config.bool("examine") else { return }
		for i in 1..<max(menu.count, 1) {
			let e = menu.entries[i]
			guard e.action == Menu.Action.itemExamine || e.action == Menu.Action.objExamine, let info = ctx.item(Int(e.key)), info.cost > 0 else { continue }
			let suffix = " <col=ffffff>(\(PluginFormat.number(price(for: info))) gp)"
			if !e.base.hasSuffix(suffix) { menu.rename(i, base: e.base + suffix) }
		}
	}

	public func drawOverlay(_ layer: OverlayLayer, _ canvas: OverlayCanvas, into r: inout Raster) {
		guard layer == .hud, config.bool("total") else { return }
		let t = totals
		canvas.drawText("Carried: \(PluginFormat.number(t.inventory + t.equipment)) gp", x: canvas.viewport.x + 6, y: canvas.viewport.y + 60, color: 0xFFD060, centered: false, into: &r)
	}
}
