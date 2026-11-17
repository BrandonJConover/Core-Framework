import Foundation

/// Option menus of if3 components (rt4 `MiniMenu.addComponentEntries`, the if3 half): options 6...10 as action 1003,
/// the target verb as action 32, options 1...5 as action 9, "Cancel" first and the lowest option last (the default).
extension GameClient {
	/// The top-most drawn if3 component under (x, y) with an enabled option or a target verb.
	func optionComponent(atX x: Int, y: Int) -> Component? {
		var layerBlocked = false
		for d in ui.drawn.reversed() where x >= d.x && y >= d.y && x < d.x + d.w && y < d.y + d.h {
			let c = d.component
			guard c.if3 else { continue }
			if (0..<min(c.ops.count, 10)).contains(where: { host.optionText(c, $0) != nil }) || targetVerb(c) != nil { return c }
			if c.type == 0 && c.noClickThrough { layerBlocked = true }
			if layerBlocked { return nil }
		}
		return nil
	}

	/// rt4 order of the entries of one if3 component. Empty (just Cancel) when it has nothing to offer or while a
	/// target is being chosen (the targeting entries live in `componentTargetTap`).
	func componentMenu(_ c: Component) -> Menu {
		var menu = Menu()
		guard interaction.target == nil else { return menu }
		func add(_ op: String, _ action: Int, key: Int) {
			menu.add(op: op, base: c.optionBase, action: action, key: Int64(key), x: c.childIndex, z: c.id)
		}
		for i in stride(from: 9, through: 5, by: -1) {
			if let t = host.optionText(c, i) { add(t, Menu.Action.componentOpHigh, key: i + 1) }
		}
		if let verb = targetVerb(c) { add(verb, Menu.Action.selectSpell, key: 0) }
		for i in stride(from: 4, through: 0, by: -1) {
			if let t = host.optionText(c, i) { add(t, Menu.Action.componentOp, key: i + 1) }
		}
		menu.sort()
		return menu
	}

	/// A long press on an if3 component opens its option menu (rt4 right click). False when it has no options.
	func openComponentMenu(x: Int, y: Int) -> Bool {
		guard let c = optionComponent(atX: x, y: y) else { return false }
		let menu = componentMenu(c)
		guard menu.count > 1 else { return false }
		openMenu(menu, atX: x, y: y)
		return true
	}

	/// A tap on an if3 component in single mouse button mode, or whose default option is 6...10, opens the menu
	/// instead of running the default option (rt4 `Protocol`: the left click becomes a right click). The press hooks
	/// still run. False when the tap should go on as a plain click.
	func openComponentMenuOnTap(x: Int, y: Int, hooks: Bool) -> Bool {
		guard let c = optionComponent(atX: x, y: y) else { return false }
		let menu = componentMenu(c)
		guard menu.count > 1, leftClickOpensMenu(menu) else { return false }
		host.tap(x: x, y: y, hooks: hooks, perform: false)
		openMenu(menu, atX: x, y: y)
		return true
	}
}
