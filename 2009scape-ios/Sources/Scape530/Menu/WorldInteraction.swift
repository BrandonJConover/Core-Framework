import Foundation

/// The state of touch interaction with the 3D world: the open menu, the click cross, the server's player
/// options and walk text. rt4 keeps these as statics in `MiniMenu`, `Cross` and `Player`.
public final class WorldInteraction {
	/// An open menu (rt4 `Cs1ScriptRunner.aBoolean108` with `InterfaceList.anInt4271/5138/761/436`).
	public struct Popup {
		public var menu: Menu
		public var x: Int, y: Int, width: Int, height: Int
	}

	/// rt4 `Cross`: the click marker (type 1 yellow for walking, 2 red for actions) animating for 400 ms.
	public struct Cross {
		public var type = 0
		public var milliseconds = 0
		public var x = 0, y = 0
	}

	public internal(set) var popup: Popup?
	/// Target mode (rt4 `MiniMenu.anInt5014` "Use" / `aBoolean302` spell): set by selecting an item's "Use" or a
	/// spell, cleared by any action or a tap that finds nothing to target.
	public internal(set) var target: TargetMode?
	/// A long press on a draggable inventory slot that may turn into a drag (see `GameClient.dragMove`).
	var dragCandidate: (component: Int, slot: Int, x: Int, y: Int)?
	/// Client cycles since the last slot activation, for the pressed highlight (rt4 `MiniMenu.anInt2043`).
	var pressedCycles = 0
	public internal(set) var cross = Cross()
	/// rt4 `Player.options` (8 slots) set by SET_INTERACTION.
	public internal(set) var playerOptions = [PlayerOption?](repeating: nil, count: 8)
	/// rt4 `MiniMenu.walkText` ("Walk here" unless the server changed it).
	public internal(set) var walkText = "Walk here"
	/// The pointer, for highlighting menu entries (rt4 `Mouse.lastMouseX/Y`).
	public var pointer = (x: -1, y: -1)
	/// What a tap at the held finger would do (rt4 `MiniMenu.method471`, the top-left line shown on hover):
	/// the default menu entry plus "/ N more options". Nil when no finger is held over the world.
	public internal(set) var preview: String?
	/// Every message the interaction sent, for tests and debugging.
	public var onSend: ((ClientMessage) -> Void)?

	public init() {}

	public var isMenuOpen: Bool { popup != nil }

	func reset() {
		popup = nil
		target = nil
		dragCandidate = nil
		cross = Cross()
		playerOptions = [PlayerOption?](repeating: nil, count: 8)
		walkText = "Walk here"
		preview = nil
	}

	/// One client cycle: rt4 `Protocol` advances the cross by 20 ms and hides it after 400.
	func cycle() {
		guard cross.type != 0 else { return }
		cross.milliseconds += 20
		if cross.milliseconds >= 400 { cross.type = 0 }
	}

	/// SET_INTERACTION and SET_WALK_TEXT (rt4 `Protocol`).
	func handle(_ m: ServerMessage) {
		switch m {
		case let .setInteraction(slot, option, _, top):
			guard slot >= 1, slot <= 8 else { return }
			playerOptions[slot - 1] = option.map { PlayerOption(text: $0, secondary: !top) }
		case .setWalkText(let t):
			walkText = t ?? "Walk here"
		default:
			break
		}
	}
}

// MARK: GameClient input

extension GameClient {
	/// A tap over the 3D world: the default action, the last entry of the menu (rt4 left click ->
	/// `MiniMenu.method1372` -> `doAction(size - 1)`). Returns false when the point is not over the world.
	func worldTap(x: Int, y: Int) -> Bool {
		if let p = interaction.popup { selectMenuEntry(p, x: x, y: y); return true }
		if let t = minimapTileAt(x: x, y: y) { return walkToMinimapTile(t.tileX, t.tileZ) }
		guard isOverWorld(x: x, y: y), let (menu, _) = buildMenu(x: x, y: y) else { return false }
		leftClick(menu, x: x, y: y)
		return true
	}

	/// rt4 `Protocol` left click (`MiniMenu.method1372`): the default entry runs, unless single mouse button mode
	/// (varp client code 5) asks for the menu whenever there is a choice, or the default entry is an if3 option 6...10,
	/// when the click is handled as a right click (`ScriptRunner.method3901` opens the menu).
	func leftClick(_ menu: Menu, x: Int, y: Int) {
		if leftClickOpensMenu(menu) {
			openMenu(menu, atX: x, y: y)
		} else {
			doAction(menu, menu.top, clickX: x, clickY: y)
		}
	}

	func leftClickOpensMenu(_ menu: Menu) -> Bool {
		(host.varpClient.mouseButtons == 1 && menu.count > 2) || menu.topIsHighComponentOp
	}

	/// A long press over the world opens the menu at the touch point (rt4 right click -> `method3901`).
	/// Returns false when the point is not over the world.
	@discardableResult
	public func longPress(x: Int, y: Int) -> Bool {
		if interaction.popup != nil { interaction.popup = nil }
		if screen == .game, openInventoryMenu(x: x, y: y) { return true }
		if screen == .game, openComponentMenu(x: x, y: y) { return true }
		guard screen == .game, isOverWorld(x: x, y: y), let (menu, _) = buildMenu(x: x, y: y) else { return false }
		openMenu(menu, atX: x, y: y)
		return true
	}

	/// Touch (or hover) at (x, y) in game pixels: shows, at the top left, the action a tap there would run,
	/// like rt4 does for the hovered entry ("Walk here", "Talk-to Hans / 2 more options"). Costs one picking pass.
	public func previewTap(x: Int, y: Int) {
		interaction.preview = nil
		guard screen == .game, interaction.popup == nil, isOverWorld(x: x, y: y), let (menu, _) = buildMenu(x: x, y: y) else { return }
		interaction.preview = menu.hoverText
	}

	/// The finger lifted or moved off (a drag steers the camera instead): hides the preview.
	public func clearPreview() { interaction.preview = nil }

	/// Closes the menu without choosing (rt4 clicks outside the menu).
	public func dismissMenu() { interaction.popup = nil }

	/// Entries for a touch point, via a picking draw of the scene (rt4 builds them every frame).
	func buildMenu(x: Int, y: Int) -> (Menu, WorldPick)? {
		guard let v = viewport, let pick = world.pick(x: x, y: y, rect: v) else { return nil }
		let menu = MenuBuilder.build(world: world, pick: pick, walkText: interaction.walkText, playerOptions: interaction.playerOptions, target: interaction.target)
		return (menu, pick)
	}

	/// rt4 `ScriptRunner.method3901`: sizes the menu to its widest entry and keeps it on screen.
	func openMenu(_ menu: Menu, atX x: Int, y: Int) {
		guard let font = try? store.font(named: "b12_full") else { return }
		var w = font.stringWidth("Choose Option")
		for i in 0..<menu.count { w = max(w, font.stringWidth(menu.text(i))) }
		let h = menu.count * 15 + 21
		w += 8
		var top = y
		var left = x - w / 2
		if top + h > lastSize.h { top = lastSize.h - h }
		if lastSize.w < left + w { left = lastSize.w - w }
		left = max(left, 0)
		top = max(top, 0)
		interaction.popup = WorldInteraction.Popup(menu: menu, x: left, y: top, width: w, height: menu.count * 15 + 22)
	}

	/// rt4 `Protocol` click handling while the menu is open: the entry under the click runs, then the menu closes.
	func selectMenuEntry(_ p: WorldInteraction.Popup, x: Int, y: Int) {
		interaction.popup = nil
		for i in 0..<p.menu.count {
			let rowY = (p.menu.count - i - 1) * 15 + p.y + 31
			if x > p.x && p.x + p.width > x && rowY - 13 < y && rowY + 3 > y {
				doAction(p.menu, i, clickX: x, clickY: y)
				return
			}
		}
	}

	/// Draws the open menu (rt4 `MiniMenu.drawA`, the software menu) and the click cross (`Player.method2310`).
	func drawInteraction(into r: inout Raster) throws {
		let c = interaction.cross
		if c.type != 0, let sheet = try store.sprite(named: "cross") {
			let frame = c.milliseconds / 100 + (c.type == 2 ? 4 : 0)
			if frame < sheet.frames.count { r.draw(sheet.frames[frame], x: c.x - 8, y: c.y - 8) }
		}
		if interaction.popup == nil, let text = interaction.preview, let font = try store.font(named: "b12_full") {
			font.drawLeft(text, x: 4, y: 15, color: 0xFFFFFF, shadow: 0, into: &r)
		}
		guard let p = interaction.popup, let font = try store.font(named: "b12_full") else { return }
		r.fillRect(p.x, p.y, p.width, p.height, 0x5D5447)
		r.fillRect(p.x + 1, p.y + 1, p.width - 2, 16, 0)
		r.drawRect(p.x + 1, p.y + 18, p.width - 2, p.height - 19, 0)
		font.drawLeft("Choose Option", x: p.x + 3, y: p.y + 14, color: 0x5D5447, shadow: -1, into: &r)
		let mouse = interaction.pointer
		for i in 0..<p.menu.count {
			let rowY = (p.menu.count - i - 1) * 15 + p.y + 31
			var color: UInt32 = 0xFFFFFF
			if p.x < mouse.x && mouse.x < p.x + p.width && rowY - 13 < mouse.y && mouse.y < rowY + 3 { color = 0xFFFF00 }
			font.drawLeft(p.menu.text(i), x: p.x + 3, y: rowY, color: color, shadow: 0, into: &r)
		}
	}

	// MARK: actions (rt4 MiniMenu.doAction)

	/// Runs entry `index` of `menu`: finds the walk route and sends the walk and action packets rt4 sends.
	func doAction(_ menu: Menu, _ index: Int, clickX: Int, clickY: Int) {
		guard index >= 0, index < menu.count else { return }
		let e = menu.entries[index]
		var action = e.action
		if action >= 2000 { action -= 2000 }
		let key = Int(truncatingIfNeeded: e.key)
		let origin = world.origin

		switch action {
		case Menu.Action.walkHere:
			guard e.x >= 0, e.z >= 0 else { return }
			walkTo(.tile(x: e.x, z: e.z), type: .gameClick, fallback: true, clickX: clickX, clickY: clickY, cross: 1)

		case _ where Menu.Action.npc.contains(action):
			guard let tile = world.npcTile(key) else { return }
			approach(.entity(x: tile.x, z: tile.z), clickX: clickX, clickY: clickY)
			sendOp(.opNpc(option: Menu.Action.npc.firstIndex(of: action)! + 1, index: key))

		case Menu.Action.npcExamine:
			setCross(2, clickX, clickY)
			if let id = world.npcTypeId(key) { sendOp(.examineNpc(typeId: id)) }

		case _ where Menu.Action.player.contains(action):
			guard let tile = world.playerTile(key) else { return }
			approach(.entity(x: tile.x, z: tile.z), clickX: clickX, clickY: clickY)
			sendOp(.opPlayer(action: action, index: key))

		case _ where Menu.Action.loc.contains(action):
			let id = Int((e.key >> 32) & Int64(Int32.max))
			if let type = (try? store.loc(id)) ?? nil {
				let shape = Int((e.key >> 14) & 0x1F), angle = Int((e.key >> 20) & 3)
				walkTo(.loc(shape: shape, angle: angle, x: e.x, z: e.z, type: type), type: .interact, fallback: true, clickX: clickX, clickY: clickY, cross: 2)
			}
			sendOp(.opLoc(option: Menu.Action.loc.firstIndex(of: action)! + 1, id: id, x: origin.x + e.x, z: origin.z + e.z))

		case Menu.Action.locExamine:
			setCross(2, clickX, clickY)
			sendOp(.examineLoc(id: key))

		case _ where Menu.Action.obj.contains(action):
			// rt4: try the exact tile first, then a 1x1 rectangle.
			if !walkTo(.tile(x: e.x, z: e.z), type: .interact, fallback: false, clickX: clickX, clickY: clickY, cross: 2) {
				walkTo(.entity(x: e.x, z: e.z), type: .interact, fallback: false, clickX: clickX, clickY: clickY, cross: 2)
			}
			sendOp(.opObj(option: Menu.Action.obj.firstIndex(of: action)! + 1, id: key, x: origin.x + e.x, z: origin.z + e.z))

		case Menu.Action.objExamine:
			setCross(2, clickX, clickY)
			sendOp(.examineObj(id: key))

		default:
			doTargetAction(menu, index, action: action, clickX: clickX, clickY: clickY)
			return
		}
		finishAction()
	}

	func setCross(_ type: Int, _ x: Int, _ y: Int) {
		interaction.cross = WorldInteraction.Cross(type: type, milliseconds: 0, x: x, y: y)
	}

	func sendOp(_ m: ClientMessage) {
		interaction.onSend?(m)
		send(m)
	}

	/// A tap on the minimap: walk to that world tile with the minimap walk packet, falling back to the
	/// nearest reachable tile as rt4 does for minimap clicks.
	@discardableResult
	func walkToMinimapTile(_ tileX: Int, _ tileZ: Int) -> Bool {
		let o = world.origin
		let plane = world.plane
		guard let me = world.selfSceneTile, plane >= 0, plane < world.collision.count else { return false }
		let finder = PathFinder(collision: world.collision[plane])
		guard let route = finder.findPath(srcX: me.x, srcZ: me.z, size: me.size, target: .tile(x: tileX - o.x, z: tileZ - o.z), allowFallback: true),
			let last = route.waypoints.last else { return true }
		let message = PathFinder.walkMessage(route: route, originX: o.x, originZ: o.z, running: false, minimap: true)
		world.destinationFlag = last
		interaction.onSend?(message)
		send(message)
		return true
	}

	/// rt4 `PathFinder.findPath(... 1, ..., 2 ...)` towards an npc or player: walk up to it (no fallback tile).
	func approach(_ target: PathFinder.Target, clickX: Int, clickY: Int) {
		walkTo(target, type: .interact, fallback: false, clickX: clickX, clickY: clickY, cross: 2)
	}

	/// Finds a route on the player's plane and sends it as a walk packet (rt4 `PathFinder.findPath`
	/// ending in `ClientProt.method3502`). Returns false when no route exists. The red/yellow cross is
	/// placed whether or not a route was found for actions (rt4 sets it in the action) and only on
	/// success for plain walking.
	@discardableResult
	func walkTo(_ target: PathFinder.Target, type: PathFinder.WalkType, fallback: Bool, clickX: Int, clickY: Int, cross: Int) -> Bool {
		let plane = world.plane
		guard let me = world.selfSceneTile, plane >= 0, plane < world.collision.count else { return false }
		let finder = PathFinder(collision: world.collision[plane])
		let route = finder.findPath(srcX: me.x, srcZ: me.z, size: me.size, target: target, allowFallback: fallback)
		if cross == 2 || route != nil { setCross(cross, clickX, clickY) }
		guard let route = route, let last = route.waypoints.last else { return false }
		let o = world.origin
		let pts = route.waypoints.map { (x: o.x + $0.x, z: o.z + $0.z) }
		let message: ClientMessage = type == .interact
			? .walkInteract(destX: pts[pts.count - 1].x, destZ: pts[pts.count - 1].z, path: Array(pts.dropLast()), ctrlRun: false)
			: PathFinder.walkMessage(route: route, originX: o.x, originZ: o.z, running: false, minimap: false)
		world.destinationFlag = last
		interaction.onSend?(message)
		send(message)
		return true
	}
}
