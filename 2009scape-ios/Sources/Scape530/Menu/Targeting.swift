import Foundation

/// A target mode (rt4 `MiniMenu`): an inventory item chosen with "Use", or a spell/component with a target
/// mask waiting for its target. While set, the world and inventory menus offer "Use X -> Y" / "Cast X -> Y".
public enum TargetMode: Equatable {
	/// rt4 `anInt5014 == 1`: `component`/`slot`/`itemId` are `MiniMap.anInt5062`, `anInt4370`, `anInt4997`;
	/// `label` is `aClass100_203` ("<col=ff9040>Name<col=ffffff>").
	case use(component: Int, slot: Int, itemId: Int, label: String)
	/// rt4 `aBoolean302`: `component`/`child` are `anInt2512`/`anInt506`, `mask` the target mask (1 ground item,
	/// 2 npc, 4 loc, 8 player, 0x10 inventory item, 0x20 component, 0x40 tile), `param` `anInt3039`, `verb`
	/// `aClass100_545` and `label` `aClass100_466`.
	case spell(component: Int, child: Int, mask: Int, param: Int, verb: String, label: String)

	/// rt4 `MiniMenu.method471`: the hover text while only "Cancel" is left.
	public var hint: String {
		switch self {
		case .use(_, _, _, let label): return "Use " + label + " ->"
		case .spell(_, _, _, _, let verb, let label): return verb + " " + label + " ->"
		}
	}
}

/// Inventory slot interaction (rt4 `MiniMenu.addComponentEntries` for type 2), target selection and drags.
extension GameClient {
	typealias InventoryHit = (component: Component, slot: Int, x: Int, y: Int)

	/// The inventory slot under (x, y) among the components drawn last frame (top-most first).
	func inventorySlot(atX x: Int, y: Int) -> InventoryHit? {
		for d in ui.drawn.reversed() where d.component.type == 2 && x >= d.x && y >= d.y && x < d.x + d.w && y < d.y + d.h {
			let c = d.component
			guard let o = ui.origins[c.ref] else { continue }
			var slot = 0
			for row in 0..<c.baseHeight {
				for col in 0..<c.baseWidth {
					var sx = o.x + col * (c.invMarginX + 32), sy = o.y + row * (c.invMarginY + 32)
					if slot < 20, slot < c.invSprites.count, let e = c.invSprites[slot] { sx += e.x; sy += e.y }
					if x >= sx && x < sx + 32 && y >= sy && y < sy + 32 { return (c, slot, sx, sy) }
					slot += 1
				}
			}
		}
		return nil
	}

	func inventoryItem(_ c: Component, _ slot: Int) -> ServerMessage.InvItem? {
		guard let it = host.game.interfaces.invSlots[c.id]?[slot], it.id >= 0 else { return nil }
		return it
	}

	/// The options of one inventory slot, in rt4's order (the last entry is the default).
	func inventorySlotMenu(_ c: Component, slot: Int, item: ServerMessage.InvItem) -> Menu {
		var menu = Menu()
		guard let obj = (try? store.objResolved(item.id)) ?? nil else { return menu }
		let base = "<col=ff9040>" + obj.name
		let opsOn = (c.events >> 30) & 1 != 0, useOn = (c.events >> 31) & 1 != 0
		func add(_ op: String, _ action: Int, base b: String? = nil) {
			menu.add(op: op, base: b ?? base, action: action, key: Int64(item.id), x: slot, z: c.id)
		}
		switch interaction.target {
		case let .use(comp, selected, _, label)?:
			if opsOn && !(comp == c.id && selected == slot) { add("Use", Menu.Action.useOnItem, base: label + " -> " + base) }
		case let .spell(_, _, mask, param, verb, label)?:
			let paramOK = param == -1 || obj.params[param] != nil
			if opsOn && mask & 0x10 != 0 && paramOK { add(verb, Menu.Action.spellOnItem, base: label + " -> " + base) }
		case nil:
			if opsOn {
				for i in [4, 3] { if let op = obj.iops[i] { add(op, Menu.Action.itemOps[i]) } }
			}
			if useOn { add("Use", Menu.Action.selectUse) }
			if opsOn {
				for i in [2, 1, 0] { if let op = obj.iops[i] { add(op, Menu.Action.itemOps[i]) } }
			}
			for i in stride(from: min(4, c.invOptions.count - 1), through: 0, by: -1) {
				if let op = c.invOptions[i] { add(op, Menu.Action.invOptions[i]) }
			}
			add("Examine", Menu.Action.itemExamine)
		}
		menu.sort()
		return menu
	}

	/// A tap on an inventory slot runs its default action; in target mode it picks the item as the target.
	/// Returns false when no inventory slot is under the finger.
	func inventoryTap(x: Int, y: Int) -> Bool {
		guard let hit = inventorySlot(atX: x, y: y) else { return false }
		if let item = inventoryItem(hit.component, hit.slot) {
			let menu = inventorySlotMenu(hit.component, slot: hit.slot, item: item)
			doAction(menu, menu.top, clickX: x, clickY: y)
		} else {
			cancelTarget()
		}
		return true
	}

	/// A long press on a slot opens its menu (rt4 right click) and arms a possible drag.
	func openInventoryMenu(x: Int, y: Int) -> Bool {
		guard let hit = inventorySlot(atX: x, y: y) else { return false }
		interaction.dragCandidate = nil
		guard let item = inventoryItem(hit.component, hit.slot) else { return true }
		let menu = inventorySlotMenu(hit.component, slot: hit.slot, item: item)
		openMenu(menu, atX: x, y: y)
		if (hit.component.events >> 28) & 1 != 0 || (hit.component.events >> 29) & 1 != 0 {
			interaction.dragCandidate = (hit.component.id, hit.slot, x, y)
		}
		return true
	}

	// MARK: drag (rt4 `Protocol` clickedInventoryComponent, MOVE_ITEM)

	public var isDraggingItem: Bool { host.game.interfaces.inventoryUI.dragging != nil }

	/// The finger moved after a long press on a draggable slot: past 5 pixels (rt4) the menu closes and the
	/// item follows the finger at half opacity.
	public func dragMove(x: Int, y: Int) {
		guard let cand = interaction.dragCandidate else { return }
		var dx = x - cand.x, dy = y - cand.y
		if host.game.interfaces.inventoryUI.dragging == nil {
			guard abs(dx) > 5 || abs(dy) > 5 else { return }
			interaction.popup = nil
		}
		if abs(dx) < 5 { dx = 0 }
		if abs(dy) < 5 { dy = 0 }
		host.game.interfaces.inventoryUI.dragging = (cand.component, cand.slot, dx, dy)
	}

	/// The finger lifted: over another slot of the same inventory the item moves there (swapped locally, then
	/// MOVE_ITEM is sent); anywhere else the drag is dropped.
	public func dragEnd(x: Int, y: Int) {
		defer {
			interaction.dragCandidate = nil
			host.game.interfaces.inventoryUI.dragging = nil
		}
		guard let cand = interaction.dragCandidate, host.game.interfaces.inventoryUI.dragging != nil,
			let hit = inventorySlot(atX: x, y: y), hit.component.id == cand.component, hit.slot != cand.slot else { return }
		var slots = host.game.interfaces.invSlots[cand.component] ?? [:]
		if (hit.component.events >> 29) & 1 != 0 {
			slots[hit.slot] = slots[cand.slot]
			slots[cand.slot] = nil
		} else {
			(slots[cand.slot], slots[hit.slot]) = (slots[hit.slot], slots[cand.slot])
		}
		host.game.interfaces.invSlots[cand.component] = slots
		sendOp(.moveItem(component: cand.component, from: cand.slot, to: hit.slot, insert: false))
	}

	/// One client cycle of the pressed-slot highlight (15 cycles, rt4 `MiniMenu.anInt2043`).
	func cycleInventoryUI() {
		guard host.game.interfaces.inventoryUI.pressed != nil else { return }
		interaction.pressedCycles += 1
		if interaction.pressedCycles >= 15 { host.game.interfaces.inventoryUI.pressed = nil }
	}

	func markPressed(component: Int, slot: Int) {
		host.game.interfaces.inventoryUI.pressed = (component, slot)
		interaction.pressedCycles = 0
	}

	// MARK: target mode

	/// rt4 `MiniMenu.method1294`: leaves target mode; a spell's `onUseWith` hook runs.
	public func cancelTarget() {
		if case let .spell(comp, child, _, _, _, _)? = interaction.target,
			let c = host.component(ComponentRef(id: comp, child: child)), let args = c.hooks["onUseWith"] {
			var req = ScriptRequest(args: args)
			req.source = c.ref
			host.run(req)
		}
		interaction.target = nil
		host.game.interfaces.inventoryUI.useSelected = nil
	}

	/// rt4 `MiniMenu.method4246` (action 32): a spell or other target component is selected.
	func enterSpell(_ c: Component) {
		cancelTarget()
		if let args = c.hooks["onUse"] {
			var req = ScriptRequest(args: args)
			req.source = c.ref
			host.run(req)
		}
		let label = c.if3 ? c.optionBase + "<col=ffffff>" : "<col=00ff00>" + c.optionSuffix + "<col=ffffff>"
		interaction.target = .spell(component: c.id, child: c.childIndex, mask: (c.events >> 11) & 0x7F, param: c.targetParam,
			verb: c.optionCircumfix, label: label)
	}

	/// rt4 `MiniMap.getTargetVerb`: the verb of a component that targets things, nil when it does not.
	func targetVerb(_ c: Component) -> String? {
		guard (c.events >> 11) & 0x7F != 0 else { return nil }
		let v = c.optionCircumfix
		return v.trimmingCharacters(in: .whitespaces).isEmpty ? nil : v
	}

	/// A tap on an interface component that is, or receives, a target: picks a spell (when the component has no
	/// enabled option of its own, as rt4's default entry order gives), or in spell mode delivers it to a
	/// component that accepts use targets (action 12).
	func componentTargetTap(x: Int, y: Int) -> Bool {
		guard let c = ui.hitTest(x: x, y: y), c.type != 2 else { return false }
		if case let .spell(comp, child, mask, _, _, _)? = interaction.target {
			if (c.events >> 22) & 1 != 0 && mask & 0x20 != 0 && c.buttonType == 0 {
				sendOp(.spellOnComponent(component: comp, child: child, targetComponent: c.id, targetChild: c.childIndex))
				cancelTarget()
				return true
			}
			return false
		}
		guard targetVerb(c) != nil else { return false }
		if c.if3 {
			for i in 0..<min(c.ops.count, 5) where host.optionText(c, i) != nil { return false }
		} else if c.buttonType != 2 {
			return false
		}
		enterSpell(c)
		return true
	}

	/// The hint line ("Use Item ->", "Cast Spell ->") drawn at the top left while in target mode.
	func drawTargetHint(into r: inout Raster) throws {
		guard let t = interaction.target, interaction.popup == nil, interaction.preview == nil, let font = try store.font(named: "b12_full") else { return }
		font.drawLeft(t.hint, x: 4, y: 15, color: 0xFFFFFF, shadow: 0, into: &r)
	}

	// MARK: actions (rt4 MiniMenu.doAction)

	/// The end of `doAction`: any action leaves target mode.
	func finishAction() {
		if interaction.target != nil { cancelTarget() }
	}

	/// Actions of inventory slots and the target modes. `menu.entries[index]` carries the item id in `key`, the
	/// slot in `x` and the component in `z` for inventory entries.
	func doTargetAction(_ menu: Menu, _ index: Int, action: Int, clickX: Int, clickY: Int) {
		let e = menu.entries[index]
		let key = Int(truncatingIfNeeded: e.key)
		let origin = world.origin
		let target = interaction.target
		var useC = 0, useSlot = 0, useItem = 0
		if case let .use(c, s, i, _)? = target { useC = c; useSlot = s; useItem = i }
		var spellC = 0, spellChild = -1
		if case let .spell(c, ch, _, _, _, _)? = target { spellC = c; spellChild = ch }

		func locTarget() -> Bool {
			let id = Int((e.key >> 32) & Int64(Int32.max))
			guard let type = (try? store.loc(id)) ?? nil else { return false }
			let shape = Int((e.key >> 14) & 0x1F), angle = Int((e.key >> 20) & 3)
			return walkTo(.loc(shape: shape, angle: angle, x: e.x, z: e.z, type: type), type: .interact, fallback: true, clickX: clickX, clickY: clickY, cross: 2)
		}
		func objTarget() {
			if !walkTo(.tile(x: e.x, z: e.z), type: .interact, fallback: false, clickX: clickX, clickY: clickY, cross: 2) {
				walkTo(.entity(x: e.x, z: e.z), type: .interact, fallback: false, clickX: clickX, clickY: clickY, cross: 2)
			}
		}
		let locId = Int((e.key >> 32) & Int64(Int32.max))

		switch action {
		case Menu.Action.selectUse:
			cancelTarget()
			let name = ((try? store.objResolved(key)) ?? nil)?.name ?? "null"
			interaction.target = .use(component: e.z, slot: e.x, itemId: key, label: "<col=ff9040>" + name + "<col=ffffff>")
			host.game.interfaces.inventoryUI.useSelected = (e.z, e.x)
			return
		case Menu.Action.useOnNpc where target != nil:
			if let tile = world.npcTile(key) {
				approach(.entity(x: tile.x, z: tile.z), clickX: clickX, clickY: clickY)
				sendOp(.useItemOnNpc(component: useC, slot: useSlot, itemId: useItem, npc: key))
			}
		case Menu.Action.useOnPlayer where target != nil:
			if let tile = world.playerTile(key) {
				approach(.entity(x: tile.x, z: tile.z), clickX: clickX, clickY: clickY)
				sendOp(.useItemOnPlayer(component: useC, slot: useSlot, itemId: useItem, player: key))
			}
		case Menu.Action.useOnLoc where target != nil:
			if locTarget() { sendOp(.useItemOnLoc(component: useC, slot: useSlot, itemId: useItem, locId: locId, x: origin.x + e.x, z: origin.z + e.z)) }
		case Menu.Action.useOnObj where target != nil:
			objTarget()
			sendOp(.useItemOnObj(component: useC, slot: useSlot, itemId: useItem, objId: key, x: origin.x + e.x, z: origin.z + e.z))
		case Menu.Action.useOnItem where target != nil:
			sendOp(.useItemOnItem(component: useC, slot: useSlot, itemId: useItem, targetComponent: e.z, targetSlot: e.x, targetItem: key))
			markPressed(component: e.z, slot: e.x)
		case Menu.Action.spellOnNpc where target != nil:
			if let tile = world.npcTile(key) {
				approach(.entity(x: tile.x, z: tile.z), clickX: clickX, clickY: clickY)
				sendOp(.spellOnNpc(component: spellC, child: spellChild, npc: key))
			}
		case Menu.Action.spellOnPlayer where target != nil:
			if let tile = world.playerTile(key) {
				approach(.entity(x: tile.x, z: tile.z), clickX: clickX, clickY: clickY)
				sendOp(.spellOnPlayer(component: spellC, child: spellChild, player: key))
			}
		case Menu.Action.spellOnLoc where target != nil:
			if locTarget() { sendOp(.spellOnLoc(component: spellC, child: spellChild, locId: locId, x: origin.x + e.x, z: origin.z + e.z)) }
		case Menu.Action.spellOnObj where target != nil:
			objTarget()
			sendOp(.spellOnObj(component: spellC, child: spellChild, objId: key, x: origin.x + e.x, z: origin.z + e.z))
		case Menu.Action.spellOnItem where target != nil:
			sendOp(.spellOnItem(component: spellC, child: spellChild, targetComponent: e.z, targetSlot: e.x, targetItem: key))
			markPressed(component: e.z, slot: e.x)
		case Menu.Action.spellOnTile where target != nil:
			setCross(2, clickX, clickY)
			sendOp(.spellOnTile(component: spellC, child: spellChild, x: origin.x + e.x, z: origin.z + e.z))
		case _ where Menu.Action.itemOps.contains(action) || Menu.Action.invOptions.contains(action):
			sendOp(.invItemOp(action: action, component: e.z, slot: e.x, itemId: key))
			markPressed(component: e.z, slot: e.x)
		case Menu.Action.itemExamine:
			sendOp(.examineObj(id: key))
			markPressed(component: e.z, slot: e.x)
		default:
			break // Cancel
		}
		finishAction()
	}
}
