/// Hooks for a shell that draws the world/inventory menu itself (the iOS "mobile UI": big touch rows).
/// The entries are the same `Menu` the classic popup shows; this only exposes them and the way to run one.
public struct MenuRow: Equatable {
	/// Index into the menu, to pass to `GameClient.chooseMenuEntry`.
	public let index: Int
	/// "Talk-to <col=ffff00>Hans" with rt4 colour tags.
	public let text: String
	public let isCancel: Bool
}

extension GameClient {
	/// The open menu's rows, default action first and Cancel last (the order the classic popup draws).
	public var popupRows: [MenuRow]? {
		guard let p = interaction.popup else { return nil }
		return (0..<p.menu.count).reversed().map {
			MenuRow(index: $0, text: p.menu.text($0), isCancel: p.menu.entries[$0].action == Menu.Action.cancel)
		}
	}

	/// Runs entry `index` of the open menu and closes it. `clickX/Y` are game pixels (where the press began).
	public func chooseMenuEntry(_ index: Int, clickX: Int, clickY: Int) {
		guard let p = interaction.popup else { return }
		interaction.popup = nil
		mapInput(clickX, clickY) { doAction(p.menu, index, clickX: $0, clickY: $1) }
	}

	/// Tap-to-drop: runs the "Drop" option of the inventory item under (x, y). False if there is none.
	func dropTap(x: Int, y: Int) -> Bool {
		guard let hit = inventorySlot(atX: x, y: y), let item = inventoryItem(hit.component, hit.slot) else { return false }
		let menu = inventorySlotMenu(hit.component, slot: hit.slot, item: item)
		guard let i = menu.entries.firstIndex(where: { $0.op == "Drop" }) else { return false }
		doAction(menu, i, clickX: x, clickY: y)
		return true
	}
}
