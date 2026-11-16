/// The world right-click menu's entry list: rt4 `MiniMenu` (`ops`, `opBases`, `actions`, `keys`,
/// `intArgs1/2`, `size`) as an array of entries. Entry 0 is always "Cancel"; the entry at the end
/// is the default (left-click) action and is drawn at the top.
public struct Menu {
	public struct Entry: Equatable {
		/// rt4 `ops`: the verb ("Talk-to", "Walk here", "Cancel").
		public var op: String
		/// rt4 `opBases`: the coloured target ("<col=ffff00>Man<col=40ff00> (level: 2)").
		public var base: String
		/// rt4 `actions`: the `MiniMenu` action code; 2000 added to an "Attack" that is demoted below the other options.
		public var action: Int
		/// rt4 `keys`: scene key of the loc, or npc/player/object id in the low bits.
		public var key: Int64
		/// rt4 `intArgs1` / `intArgs2`: the scene tile (x, z) the entry refers to. For "Walk here" this is
		/// the tile under the touch (rt4 keeps the mouse position and resolves the tile on the next draw).
		public var x: Int, z: Int
	}

	/// rt4 `MiniMenu.ops` etc. in insertion order; `entries[0]` is Cancel.
	public private(set) var entries: [Entry] = []

	/// rt4 `MiniMenu` action codes used by this port.
	public enum Action {
		public static let walkHere = 60
		public static let cancel = 1005
		public static let npc = [17, 16, 4, 19, 2]
		public static let npcExamine = 1007
		public static let loc = [42, 50, 49, 46, 1001]
		public static let locExamine = 1004
		/// Per player-option slot (rt4 `MiniMenu.aShortArray2`).
		public static let player = [30, 6, 31, 29, 10, 44, 37, 57]
		public static let obj = [21, 34, 18, 20, 24]
		public static let objExamine = 1002
		// Target modes (rt4 `MiniMenu` "Use" and spell actions).
		public static let useOnPlayer = 1, useOnLoc = 14, useOnNpc = 26, useOnObj = 33, useOnItem = 40
		public static let spellOnPlayer = 15, spellOnLoc = 38, spellOnNpc = 45, spellOnObj = 39, spellOnItem = 3
		public static let spellOnComponent = 12, spellOnTile = 11
		/// Selecting a spell component (action 32) or an inventory item's "Use" (22).
		public static let selectSpell = 32, selectUse = 22
		/// Inventory slot options: the item's own `iops` 1...5 and the component's `invOptions` 1...5.
		public static let itemOps = [47, 5, 43, 35, 58]
		public static let invOptions = [25, 23, 48, 7, 13]
		public static let itemExamine = 1006
	}

	public init() { reset() }

	public var count: Int { entries.count }

	/// rt4 `Protocol` per-frame reset: only "Cancel" remains.
	public mutating func reset() {
		entries = [Entry(op: "Cancel", base: "", action: Action.cancel, key: 0, x: 0, z: 0)]
	}

	/// rt4 `MiniMenu.add` (the 500 entry cap included).
	public mutating func add(op: String, base: String, action: Int, key: Int64 = 0, x: Int = 0, z: Int = 0) {
		guard entries.count < 500 else { return }
		entries.append(Entry(op: op, base: base, action: action, key: key, x: x, z: z))
	}

	/// rt4 `MiniMenu.getOp`: "verb target" (the separator is a single space).
	public func text(_ i: Int) -> String {
		let e = entries[i]
		return e.base.isEmpty ? e.op : e.op + " " + e.base
	}

	/// rt4 `MiniMenu.sort`: bubble pass that sinks the examine/cancel style entries (action above 1000)
	/// below the interaction entries, keeping the rest in insertion order.
	public mutating func sort() {
		var sorted = false
		while !sorted {
			sorted = true
			var i = 0
			while i < entries.count - 1 {
				let a = entries[i].action, b = entries[i + 1].action
				if (a < 1000 && b > 1000) || (a > 7000 && b > a) {
					entries.swapAt(i, i + 1)
					sorted = false
				}
				i += 1
			}
		}
	}

	/// Replaces the target text of entry `i` (rt4 recolours "Walk here" under a player).
	mutating func setBase(_ i: Int, _ base: String) { entries[i].base = base }

	/// The default (left-click) entry: the last one (rt4 `MiniMenu.method1372` -> `doAction(size - 1)`).
	public var top: Int { entries.count - 1 }

	/// The text shown while hovering without the menu open (rt4 `MiniMenu.method471`):
	/// the default entry, with "/ N more options" when there are more than two entries.
	public var hoverText: String {
		var s = text(top)
		if entries.count > 2 { s += "<col=ffffff> / \(entries.count - 2) more options" }
		return s
	}
}
