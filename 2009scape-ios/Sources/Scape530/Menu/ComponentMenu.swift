import Foundation

/// Option menus of if3 components (rt4 `MiniMenu.addComponentEntries`, the if3 half): options 6...10 as action 1003,
/// the target verb as action 32, options 1...5 as action 9, "Cancel" first and the lowest option last (the default).
/// A long press lists every drawn component under the point (if1 buttons and pause "Continue" too), so bank slots,
/// shop stock and dialogue options get "Withdraw-X", "Value", ...
extension Menu.Action {
	/// "Continue" of a pause button (rt4 action 41).
	public static let componentContinue = 41
}

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
		guard let menu = componentMenu(x: x, y: y) else { return false }
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

	/// The menu for components under (x, y), or nil when none has an option.
	func componentMenu(x: Int, y: Int) -> Menu? {
		guard interaction.target == nil else { return nil }
		var menu = Menu()
		let p = (x: x, y: y)
		for d in ui.drawn where host.inside(d, p) {
			let c = d.component
			if c.type == 0 && c.noClickThrough { menu.reset() }
			if !c.if3 {
				// if1 buttons (rt4 `MiniMenu.addComponentEntries`): one entry each, the component's own `option`.
				func addLegacy(_ op: String, _ action: Int) { menu.add(op: op, base: "", action: action, key: 0, x: -1, z: c.id) }
				let option = c.option ?? ""
				switch c.buttonType {
				case 1: addLegacy(option, 8)
				case 3: addLegacy("Close", 28)
				case 4: addLegacy(option, 59)
				case 5: addLegacy(option, 51)
				case 6: addLegacy(option, Menu.Action.componentContinue)
				default: break
				}
				continue
			}
			func add(_ op: String, _ action: Int, _ number: Int) {
				menu.add(op: op, base: c.optionBase, action: action, key: Int64(number), x: c.childIndex, z: c.id)
			}
			for i in stride(from: 9, through: 5, by: -1) {
				if let t = host.optionText(c, i) { add(t, Menu.Action.componentOpHigh, i + 1) }
			}
			if let verb = targetVerb(c) { add(verb, Menu.Action.selectSpell, 0) }
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
		if e.action == 8 || e.action == 59 || e.action == 51 {
			send(.ifButtonLegacy(component: e.z))
		} else if e.action == 28 {
			host.closeModals()
			send(.closeModal)
		} else if e.action == Menu.Action.componentContinue {
			send(.ifContinue(component: e.z, child: e.x))
		} else if let c = host.component(ref) {
			host.clickOption(c, op: Int(e.key))
		}
		finishAction()
	}
}
