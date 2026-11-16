/// A player option the server set with SET_INTERACTION (rt4 `Player.options` / `secondaryOptions`).
public struct PlayerOption: Equatable {
	public var text: String
	/// rt4 `Player.secondaryOptions`: shown below the other options (the server's "not the default" flag).
	public var secondary: Bool
}

/// Ports of rt4's menu building for the 3D world: `MiniMenu.addEntries` (walk entry and one block per
/// picked entity), `addNpcEntries`, `addPlayerEntries` and `getCombatLevelColor`.
///
/// Not ported: the "stacked entities" branch that lists every npc and player on the clicked tile (rt4
/// draws only one actor per tile, this port draws all of them, so each one is picked on its own), the
/// "Use" / target-spell modes (item use) and the shift-click and examine options of components.
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
	static func build(world: WorldView, pick: WorldPick, walkText: String, playerOptions: [PlayerOption?]) -> Menu {
		var menu = Menu()
		let tile = pick.tile ?? (x: -1, z: -1)
		menu.add(op: walkText, base: "", action: Menu.Action.walkHere, key: 0, x: tile.x, z: tile.z)

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
				addLoc(&menu, loc, key: key, x: x, z: z)
			case 1:
				guard let a = world.ctx.npcs[id] else { continue }
				addNpc(&menu, a, index: id, world: world)
			case 0:
				guard let a = world.ctx.players[id] else { continue }
				addPlayer(&menu, a, index: id, world: world, options: playerOptions)
			case 3:
				addObjs(&menu, world: world, x: x, z: z)
			default:
				break
			}
		}
		menu.sort()
		return menu
	}

	/// The loc block of rt4 `addEntries` (ops 4 down to 0, then Examine).
	static func addLoc(_ menu: inout Menu, _ loc: LocType, key: Int64, x: Int, z: Int) {
		let base = "<col=00ffff>" + loc.name
		for i in stride(from: 4, through: 0, by: -1) {
			guard let op = loc.ops[i] else { continue }
			menu.add(op: op, base: base, action: Menu.Action.loc[i], key: key, x: x, z: z)
		}
		menu.add(op: "Examine", base: base, action: Menu.Action.locExamine, key: Int64(loc.id), x: x, z: z)
	}

	/// rt4 `MiniMenu.addNpcEntries`.
	static func addNpc(_ menu: inout Menu, _ a: PathingActor, index: Int, world: WorldView) {
		guard menu.count < 400, let type = a.npcType, type.interactive else { return }
		var name = type.name
		let own = world.ownCombatLevel
		if type.combatLevel != 0 {
			name += combatLevelColor(other: type.combatLevel, own: own) + " (level: \(type.combatLevel))"
		}
		let base = "<col=ffff00>" + name
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
	static func addPlayer(_ menu: inout Menu, _ a: PathingActor, index: Int, world: WorldView, options: [PlayerOption?]) {
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
		for slot in stride(from: 7, through: 0, by: -1) {
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
	static func addObjs(_ menu: inout Menu, world: WorldView, x: Int, z: Int) {
		for stack in world.groundObjects(x: x, z: z).reversed() {
			guard let t = (try? world.store.objResolved(stack.type)) ?? nil else { continue }
			let base = "<col=ff9040>" + t.name
			for i in stride(from: 4, through: 0, by: -1) {
				guard let op = t.ops[i] else { continue }
				menu.add(op: op, base: base, action: Menu.Action.obj[i], key: Int64(stack.type), x: x, z: z)
			}
			menu.add(op: "Examine", base: base, action: Menu.Action.objExamine, key: Int64(stack.type), x: x, z: z)
		}
	}
}
