import Foundation

/// The client state a legacy IF1 script (CS1) reads (rt4 `PlayerSkillXpTable`, `VarpDomain`, `Player`, the
/// component inventories and the camera origin). `InterfaceScriptHost` answers from the live `GameState`.
public protocol Cs1Source: AnyObject {
	/// rt4 `PlayerSkillXpTable.boostedLevels[skill]`.
	func cs1BoostedLevel(_ skill: Int) -> Int
	/// rt4 `PlayerSkillXpTable.baseLevels[skill]`.
	func cs1BaseLevel(_ skill: Int) -> Int
	/// rt4 `PlayerSkillXpTable.experience[skill]`.
	func cs1Experience(_ skill: Int) -> Int
	/// rt4 `Component.objCounts` summed over the slots of component `component` holding object `obj` (0 when
	/// absent, or when the object is members-only on a free world).
	func cs1ItemCount(component: Int, obj: Int) -> Int
	/// rt4 `VarpDomain.activeVarps[id]`.
	func cs1Varp(_ id: Int) -> Int
	/// rt4 `VarpDomain.getVarbit`.
	func cs1Varbit(_ id: Int) -> Int
	/// rt4 `PlayerList.self.combatLevel`.
	func cs1CombatLevel() -> Int
	/// rt4 `Player.runEnergy` / `Player.weight`.
	func cs1RunEnergy() -> Int
	func cs1Weight() -> Int
	/// Absolute tile of the local player (rt4 `(xFine >> 7) + Camera.originX`, and z).
	func cs1TileX() -> Int
	func cs1TileZ() -> Int
	/// rt4 `Player.lastLogAddress` rendered for `%dns` (empty when unknown).
	func cs1LastLogAddress() -> String
}

/// rt4 `Cs1ScriptRunner.run` / `interpolate` / `isTrue`: the IF1 script language that gates a component's active
/// state and fills `%1`..`%5` in its text.
public enum Cs1 {
	/// rt4 `PlayerSkillXpTable.ENABLED_SKILLS` (the 25th slot is unused).
	static let skillCount = 25

	/// rt4 `Cs1ScriptRunner.run`: runs script `index` of `component` and returns its accumulator, -2 when the
	/// component has no such script, -1 when it is malformed (rt4 catches the exception).
	public static func run(_ index: Int, _ component: Component, _ src: Cs1Source) -> Int {
		guard index >= 0, index < component.cs1Scripts.count else { return -2 }
		let script = component.cs1Scripts[index]
		var pc = 0
		var accumulatorMode = 0
		var accumulator = 0
		func next() -> Int? {
			guard pc < script.count else { return nil }
			defer { pc += 1 }
			return script[pc]
		}
		func skill() -> Int? {
			guard let s = next(), s >= 0, s < skillCount else { return nil }
			return s
		}
		while true {
			var value = 0
			guard let opcode = next() else { return -1 }
			var nextMode = 0
			if opcode == 0 { return accumulator }
			if opcode == 15 { nextMode = 1 }
			if opcode == 16 { nextMode = 2 }
			if opcode == 17 { nextMode = 3 }
			switch opcode {
			case 1: guard let s = skill() else { return -1 }; value = src.cs1BoostedLevel(s)
			case 2: guard let s = skill() else { return -1 }; value = src.cs1BaseLevel(s)
			case 3: guard let s = skill() else { return -1 }; value = src.cs1Experience(s)
			case 4, 10:
				// rt4 reads the interface and component halves, then the object (-1: none).
				guard let hi = next(), let lo = next(), let obj = next() else { return -1 }
				let count = obj == -1 ? 0 : src.cs1ItemCount(component: (hi << 16) + lo, obj: obj)
				if opcode == 4 { value += count } else if count > 0 { value = 999_999_999 }
			case 5: guard let v = next() else { return -1 }; value = src.cs1Varp(v)
			case 6:
				guard let s = skill() else { return -1 }
				let base = src.cs1BaseLevel(s)
				guard base >= 1, base - 1 < InterfaceScriptHost.xpLevelLookup.count else { return -1 }
				value = InterfaceScriptHost.xpLevelLookup[base - 1]
			case 7: guard let v = next() else { return -1 }; value = src.cs1Varp(v) * 100 / 46875
			case 8: value = src.cs1CombatLevel()
			case 9: for s in 0..<(skillCount - 1) { value += src.cs1BaseLevel(s) }
			case 11: value = src.cs1RunEnergy()
			case 12: value = src.cs1Weight()
			case 13:
				guard let v = next(), let bit = next() else { return -1 }
				let varp = src.cs1Varp(v)
				value = (1 << (bit & 31)) & varp == 0 ? 0 : 1
			case 14: guard let v = next() else { return -1 }; value = src.cs1Varbit(v)
			case 18: value = src.cs1TileX()
			case 19: value = src.cs1TileZ()
			case 20: guard let v = next() else { return -1 }; value = v
			default: break
			}
			if nextMode == 0 {
				switch accumulatorMode {
				case 0: accumulator = accumulator &+ value
				case 1: accumulator = accumulator &- value
				case 2: if value != 0 { accumulator /= value }
				default: accumulator = accumulator &* value
				}
				accumulatorMode = 0
			} else {
				accumulatorMode = nextMode
			}
		}
	}

	/// rt4 `Cs1ScriptRunner.interpolate`: `%1`..`%5` become the result of scripts 0..4, `%dns` the last login address.
	public static func interpolate(_ component: Component, _ text: String, _ src: Cs1Source) -> String {
		guard text.contains("%") else { return text }
		var text = text
		for n in 1...5 where text.contains("%\(n)") {
			text = text.replacingOccurrences(of: "%\(n)", with: String(run(n - 1, component, src)))
		}
		if text.contains("%dns") { text = text.replacingOccurrences(of: "%dns", with: src.cs1LastLogAddress()) }
		return text
	}

	/// rt4 `Cs1ScriptRunner.isTrue`: every comparison holds. Comparison opcode 2 is "value < operand", 3 is
	/// "value > operand", 4 is "value != operand" and anything else "value == operand". A component without
	/// comparisons is never active.
	public static func isTrue(_ component: Component, _ src: Cs1Source) -> Bool {
		guard !component.cs1Comparisons.isEmpty else { return false }
		for (i, cmp) in component.cs1Comparisons.enumerated() {
			let value = run(i, component, src)
			switch cmp.opcode {
			case 2: if cmp.operand <= value { return false }
			case 3: if value <= cmp.operand { return false }
			case 4: if value == cmp.operand { return false }
			default: if cmp.operand != value { return false }
			}
		}
		return true
	}
}
