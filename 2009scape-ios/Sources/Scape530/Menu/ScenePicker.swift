/// The static picking state rt4 keeps while it draws the scene with the mouse
/// over the viewport: `RawModel.allowInput`, the mouse point relative to the
/// viewport centre (`GlModel.anInt3582` / `RawModel.anInt1053`), the list of
/// entity keys under the mouse (`Model.aLongArray11` + `MiniMenu.anInt7`) and the
/// ground-tile pick request (`MiniMenu.aBoolean187`, `anInt2388/3259`) with its
/// result (`MiniMenu.anInt1742/2954`).
///
/// rt4 (`ScriptRunner.method4326`) resets this before every scene draw. Here a
/// pick is a dedicated scene draw (`WorldView.pick`) that fills it.
public final class ScenePicker {
	public static let shared = ScenePicker()

	/// rt4 `RawModel.allowInput`: the mouse is inside the viewport, entity picking is on.
	public var allowInput = false
	/// Mouse point relative to the viewport centre (rt4 `anInt3582` / `anInt1053`).
	public var mouseX = 0, mouseY = 0
	/// Keys of the entities (and locs) under the mouse, in draw order (far to near).
	public private(set) var hits: [Int64] = []

	/// rt4 `MiniMenu.aBoolean187`: a ground tile pick is wanted during this draw.
	public var tileRequested = false
	/// rt4 `MiniMenu.anInt3902`: highest level whose tiles may be picked.
	public var tileMaxLevel = 3
	/// Result of the tile pick: the scene tile under the mouse, or -1.
	public var tileX = -1, tileZ = -1

	init() {}

	/// Clears everything before a draw (rt4 sets `anInt7 = 0` and the flags).
	public func reset() {
		hits.removeAll(keepingCapacity: true)
		tileX = -1
		tileZ = -1
	}

	/// rt4 `Model.aLongArray11[MiniMenu.anInt7++] = key`.
	func add(_ key: Int64) {
		if hits.count < 1000 { hits.append(key) }
	}

	/// rt4 `SceneGraph.method583`: is the point inside the screen triangle? (A bounding
	/// test first, then three edge-side products, exactly as rt4 does it.)
	static func pointInTriangle(_ x: Int, _ y: Int, _ y1: Int, _ y2: Int, _ y3: Int, _ x1: Int, _ x2: Int, _ x3: Int) -> Bool {
		if y < y1 && y < y2 && y < y3 { return false }
		if y > y1 && y > y2 && y > y3 { return false }
		if x < x1 && x < x2 && x < x3 { return false }
		if x > x1 && x > x2 && x > x3 { return false }
		let a = Int32(truncatingIfNeeded: (y - y1) * (x2 - x1) - (x - x1) * (y2 - y1))
		let b = Int32(truncatingIfNeeded: (y - y3) * (x1 - x3) - (x - x3) * (y1 - y3))
		let c = Int32(truncatingIfNeeded: (y - y2) * (x3 - x2) - (x - x2) * (y3 - y2))
		return a &* c > 0 && c &* b > 0
	}

	/// rt4 `SceneGraph.method583` applied to a tile triangle while a tile pick is requested.
	@inline(__always)
	func testTile(_ cx: Int, _ cy: Int, _ y1: Int, _ y2: Int, _ y3: Int, _ x1: Int, _ x2: Int, _ x3: Int, tileX tx: Int, tileZ tz: Int) {
		if tileRequested && Self.pointInTriangle(mouseX + cx, mouseY + cy, y1, y2, y3, x1, x2, x3) {
			tileX = tx
			tileZ = tz
		}
	}
}
