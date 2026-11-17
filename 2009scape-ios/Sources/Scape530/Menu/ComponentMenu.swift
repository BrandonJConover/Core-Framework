import Foundation

/// The right-click (long-press) menu of interface components: rt4 `MiniMenu.addComponentEntries` for if3
/// components. Every drawn component under the point that has an enabled option adds its entries (options
/// 6-10 first, then 1-5, then "Continue"), so the default (last) entry is the lowest option of the top-most
/// component. Bank slots, shop stock and dialogue options rely on this for "Withdraw-X", "Value", ...
extension Menu.Action {
	/// Component options 1-5 (`MiniMenu` action 9) and 6-10 (action 1003); `key` is the 1-based option number,
	/// `x` the child index (-1 static) and `z` the component id.
	public static let componentOp = 9, componentOpHigh = 1003
	/// "Continue" of a pause button (rt4 action 41).
	public static let componentContinue = 41
}

extension GameClient {
	/// The menu for components under (x, y), or nil when none has an option.
	func componentMenu(x: Int, y: Int) -> Menu? {
		var menu = Menu()
		let p = (x: x, y: y)
		for d in ui.drawn where host.inside(d, p) {
			let c = d.component
			guard c.if3 else { continue }
			if c.type == 0 && c.noClickThrough { menu.reset() }
			func add(_ op: String, _ action: Int, _ number: Int) {
				menu.add(op: op, base: c.optionBase, action: action, key: Int64(number), x: c.childIndex, z: c.id)
			}
			for i in stride(from: 9, through: 5, by: -1) {
				if let t = host.optionText(c, i) { add(t, Menu.Action.componentOpHigh, i + 1) }
			}
			for i in stride(from: 4, through: 0, by: -1) {
				if let t = host.optionText(c, i) { add(t, Menu.Action.componentOp, i + 1) }
			}
			if c.events & 1 != 0 { add("Continue", Menu.Action.componentContinue, 0) }
		}
		guard menu.count > 1 else { return nil }
		menu.sort()
		return menu
	}

	/// Runs a component menu entry.
	func doComponentAction(_ e: Menu.Entry) {
		let ref = ComponentRef(id: e.z, child: e.x)
		if e.action == Menu.Action.componentContinue {
			send(.ifContinue(component: e.z, child: e.x))
		} else if let c = host.component(ref) {
			host.clickOption(c, op: Int(e.key))
		}
		finishAction()
	}
}
