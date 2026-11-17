/// A player option the server set with SET_INTERACTION (rt4 `Player.options` / `secondaryOptions`).
public struct PlayerOption: Equatable {
	public var text: String
	/// rt4 `Player.secondaryOptions`: shown below the other options (the server's "not the default" flag).
	public var secondary: Bool
}

/// Ports of rt4's menu building for the 3D world: `MiniMenu.addEntries` (walk entry and one block per
/// picked entity), `addNpcEntries`, `addPlayerEntries` and `getCombatLevelColor`.
///
/// A picked npc or player that stands exactly on its tile also lists every other actor inside its
/// footprint (rt4 draws only one of them, see `WorldView.oneActorPerTile`): `addStacked`.
enum MenuBuilder {
	/// rt4 `MiniMenu.getCombatLevelColor` (colour tags the font renders).
	static func combatLevelColor(other: Int, own: Int) -> String {
		let delta = own - other
		if delta < -9 { return "<col=ff0000>" }
		if delta < -6 { return "<col=ff3000>" }
		if delta < -3 { return "<col=ff7000>" }
		if delta < 0 { return "<col=ffb000>" }
		if delta > 9 { return "<col=00ff00>" }
		if delta > 6 { return "<col=40ff00>" }
		if delta <= 3 { return delta > 0 ? "<col=c0ff00>" : "<col=ffff00>" }
		return "<col=80ff00>"
	}

	/// rt4 `Player.getName` / `JagString.toTitleCase`: underscores become spaces, words capitalised.
	static func displayName(_ a: PlayerAppearance) -> String {
		guard let raw = a.name else { return "" }
		var out = ""
		var upper = true
		for ch in raw {
			if ch == "_" { out.append(" "); upper = true; continue }
			out.append(upper ? Character(ch.uppercased()) : ch)
			upper = false
		}
		return out
	}

	/// rt4 `MiniMenu.addEntries`: the walk entry, then one block per picked entity, in pick order.
	/// `tile` is the scene tile under the touch (nil when over the sky).
	static func build(world: WorldView, pick: WorldPick, walkText: String, playerOptions: [PlayerOption?], target: TargetMode? = nil) -> Menu {
		var menu = Menu()
		let tile = pick.tile ?? (x: -1, z: -1)
		switch target {
		case .use?:
			break // rt4: no walk entry while an item is selected
		case let .spell(_, _, mask, _, verb, _)? where mask & 0x40 != 0:
			// rt4 action 11: the spell targets a ground tile (key 1 = the tile is already known).
			menu.add(op: verb, base: " ->", action: Menu.Action.spellOnTile, key: 1, x: tile.x, z: tile.z)
		default:
			menu.add(op: walkText, base: "", action: Menu.Action.walkHere, key: 0, x: tile.x, z: tile.z)
		}

		var previous: Int64 = -1
		let plane = world.plane
		for key in pick.hits where key != previous {
			previous = key
			let x = Int(key & 0x7F), z = Int((key >> 7) & 0x7F)
			let type = Int((key >> 29) & 3)
			let id = Int((key >> 32) & Int64(Int32.max))
			switch type {
			case 2:
				guard let scene = world.scene, scene.isLocValid(level: plane, x: x, z: z, key: key),
				      let base = (try? world.store.loc(id)) ?? nil,
				      let loc = world.env.resolve(base, store: world.store) else { continue }
				addLoc(&menu, loc, key: key, x: x, z: z, target: target)
			case 1:
				guard let a = world.ctx.npcs[id] else { continue }
				addStacked(&menu, picked: a, isNpc: true, index: id, world: world, options: playerOptions, target: target)
				addNpc(&menu, a, index: id, world: world, target: target)
			case 0:
				guard let a = world.ctx.players[id] else { continue }
				addStacked(&menu, picked: a, isNpc: false, index: id, world: world, options: playerOptions, target: target)
				addPlayer(&menu, a, index: id, world: world, options: playerOptions, target: target)
			case 3:
				addObjs(&menu, world: world, x: x, z: z, target: target)
			default:
				break
			}
		}
		menu.sort()
		return menu
	}

	/// The "stacked actors" branches of rt4 `MiniMenu.addEntries` (entity types 1 and 0): when the picked actor stands
	/// exactly on a tile (centre for odd sizes, corner for even ones; players only the centre), the npcs and then the
	/// players whose footprint lies inside its own are added first, so the picked actor ends up as the default entry.
	/// Arithmetic shifts on negative offsets are rt4's.
	static func addStacked(_ menu: inout Menu, picked a: PathingActor, isNpc: Bool, index: Int, world: WorldView, options: [PlayerOption?], target: TargetMode?) {
		let size = a.size
		let x0: Int, z0: Int
		if isNpc {
			guard (size & 1 == 0 && a.xFine & 0x7F == 0 && a.zFine & 0x7F == 0) || (size & 1 == 1 && a.xFine & 0x7F == 64 && a.zFine & 0x7F == 64) else { return }
			x0 = a.xFine + 64 - size * 64
			z0 = a.zFine - (size - 1) * 64
		} else {
			guard a.xFine & 0x7F == 64 && a.zFine & 0x7F == 64 else { return }
			x0 = a.xFine - (size - 1) * 64
			z0 = a.zFine + 64 - size * 64
		}
		for (id, n) in world.ctx.npcs.sorted(by: { $0.key < $1.key }) {
			let bx = n.xFine + 64 - n.size * 64, bz = n.zFine + 64 - n.size * 64
			if isNpc && n === a { continue }
			let zOK = isNpc ? z0 <= bz : bz >= z0
			if bx >= x0 && size - ((bx - x0) >> 7) >= n.size && zOK && n.size <= size - ((bz - z0) >> 7) {
				addNpc(&menu, n, index: id, world: world, target: target)
			}
		}
		for (id, q) in world.ctx.players.sorted(by: { $0.key < $1.key }) {
			let bx: Int, bz: Int
			if isNpc {
				bx = q.xFine + 64 - q.size * 64
				bz = q.zFine + 64 - q.size * 64
			} else {
				if q === a { continue }
				bx = q.xFine - (q.size - 1) * 64
				bz = q.zFine + 64 - q.size * 64
			}
			if bx >= x0 && q.size <= size - ((bx - x0) >> 7) && bz >= z0 && q.size <= size - ((bz - z0) >> 7) {
				addPlayer(&menu, q, index: id, world: world, options: options, target: target)
			}
		}
	}

	/// The loc block of rt4 `addEntries` (ops 4 down to 0, then Examine).
	static func addLoc(_ menu: inout Menu, _ loc: LocType, key: Int64, x: Int, z: Int, target: TargetMode? = nil) {
		let base = "<col=00ffff>" + loc.name
		switch target {
		case let .use(_, _, _, label)?:
			menu.add(op: "Use", base: label + " -> " + base, action: Menu.Action.useOnLoc, key: key, x: x, z: z)
			return
		case let .spell(_, _, mask, _, verb, label)?:
			if mask & 0x4 != 0 { menu.add(op: verb, base: label + " -> " + base, action: Menu.Action.spellOnLoc, key: key, x: x, z: z) }
			return
		case nil:
			break
		}
		for i in stride(from: 4, through: 0, by: -1) {
			guard let op = loc.ops[i] else { continue }
			menu.add(op: op, base: base, action: Menu.Action.loc[i], key: key, x: x, z: z)
		}
		menu.add(op: "Examine", base: base, action: Menu.Action.locExamine, key: Int64(loc.id), x: x, z: z)
	}

	/// rt4 `MiniMenu.addNpcEntries`.
	static func addNpc(_ menu: inout Menu, _ a: PathingActor, index: Int, world: WorldView, target: TargetMode? = nil) {
		guard menu.count < 400, let type = a.npcType, type.interactive else { return }
		var name = type.name
		let own = world.ownCombatLevel
		if type.combatLevel != 0 {
			name += combatLevelColor(other: type.combatLevel, own: own) + " (level: \(type.combatLevel))"
		}
		let base = "<col=ffff00>" + name
		switch target {
		case let .use(_, _, _, label)?:
			menu.add(op: "Use", base: label + " -> " + base, action: Menu.Action.useOnNpc, key: Int64(index))
			return
		case let .spell(_, _, mask, _, verb, label)?:
			if mask & 0x2 != 0 { menu.add(op: verb, base: label + " -> " + base, action: Menu.Action.spellOnNpc, key: Int64(index)) }
			return
		case nil:
			break
		}
		for i in stride(from: 4, through: 0, by: -1) {
			guard let op = type.ops[i], op.lowercased() != "attack" else { continue }
			menu.add(op: op, base: base, action: Menu.Action.npc[i], key: Int64(index))
		}
		// "Attack" goes last among the options, and below the others when the npc out-levels the player.
		for i in stride(from: 4, through: 0, by: -1) {
			guard let op = type.ops[i], op.lowercased() == "attack" else { continue }
			let demote = type.combatLevel > own ? 2000 : 0
			menu.add(op: op, base: base, action: Menu.Action.npc[i] + demote, key: Int64(index))
		}
		menu.add(op: "Examine", base: base, action: Menu.Action.npcExamine, key: Int64(index))
	}

	/// rt4 `MiniMenu.addPlayerEntries`.
	static func addPlayer(_ menu: inout Menu, _ a: PathingActor, index: Int, world: WorldView, options: [PlayerOption?], target: TargetMode? = nil) {
		guard index != world.selfIndex, menu.count < 400, let ap = a.appearance else { return }
		let name = displayName(ap)
		let own = world.ownCombatLevel
		let label: String
		if ap.skillTotal == 0 {
			let color = combatLevelColor(other: ap.combatLevel, own: own)
			if ap.combatLevelWithSummoning > ap.combatLevel {
				label = name + color + " (level: \(ap.combatLevel)+\(ap.combatLevelWithSummoning - ap.combatLevel))"
			} else {
				label = name + color + " (level: \(ap.combatLevel))"
			}
		} else {
			label = name + " (skill: \(ap.skillTotal))"
		}
		switch target {
		case let .use(_, _, _, tlabel)?:
			menu.add(op: "Use", base: tlabel + " -> <col=ffffff>" + label, action: Menu.Action.useOnPlayer, key: Int64(index))
		case let .spell(_, _, mask, _, verb, tlabel)?:
			if mask & 0x8 != 0 { menu.add(op: verb, base: tlabel + " -> <col=ffffff>" + label, action: Menu.Action.spellOnPlayer, key: Int64(index)) }
		case nil:
			break
		}
		for slot in stride(from: 7, through: 0, by: -1) where target == nil {
			guard slot < options.count, let o = options[slot] else { continue }
			var offset = 0
			if o.text.lowercased() == "attack" {
				if ap.combatLevel > own { offset = 2000 }
			} else if o.secondary {
				offset = 2000
			}
			menu.add(op: o.text, base: "<col=ffffff>" + label, action: Menu.Action.player[slot] + offset, key: Int64(index))
		}
		// rt4 recolours the "Walk here" entry with the player under the cursor.
		if let w = menu.entries.firstIndex(where: { $0.action == Menu.Action.walkHere }) {
			menu.setBase(w, "<col=ffffff>" + label)
		}
	}

	/// The ground item block of rt4 `addEntries` (newest stack entry first, ops 4 down to 0, then Examine).
	static func addObjs(_ menu: inout Menu, world: WorldView, x: Int, z: Int, target: TargetMode? = nil) {
		for stack in world.groundObjects(x: x, z: z).reversed() {
			guard let t = (try? world.store.objResolved(stack.type)) ?? nil else { continue }
			let base = "<col=ff9040>" + t.name
			switch target {
			case let .use(_, _, _, label)?:
				menu.add(op: "Use", base: label + " -> " + base, action: Menu.Action.useOnObj, key: Int64(stack.type), x: x, z: z)
				continue
			case let .spell(_, _, mask, param, verb, label)?:
				let paramOK = param == -1 || t.params[param] != nil
				if mask & 0x1 != 0 && paramOK { menu.add(op: verb, base: label + " -> " + base, action: Menu.Action.spellOnObj, key: Int64(stack.type), x: x, z: z) }
				continue
			case nil:
				break
			}
			for i in stride(from: 4, through: 0, by: -1) {
				guard let op = t.ops[i] else { continue }
				menu.add(op: op, base: base, action: Menu.Action.obj[i], key: Int64(stack.type), x: x, z: z)
			}
			menu.add(op: "Examine", base: base, action: Menu.Action.objExamine, key: Int64(stack.type), x: x, z: z)
		}
	}
}
