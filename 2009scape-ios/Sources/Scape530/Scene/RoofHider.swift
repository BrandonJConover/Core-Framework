import Foundation

/// A box of tiles whose roofs are hidden this frame (rt4 `ScriptRunner.anIntArray205/338/518/134/476`).
/// Occluders inside the box are dropped so they cannot hide what is now visible.
public struct RoofBox {
	/// rt4 `anIntArray205`: the highest roof tile height (rt4 units, negative is up); -1000000 when unused.
	public var height = -1_000_000
	/// rt4 `anIntArray338` / `518`: X extent in fine units.
	public var minX = 1_000_000, maxX = 0
	/// rt4 `anIntArray476` / `134`: Z extent in fine units.
	public var minZ = 1_000_000, maxZ = 0
	public init() {}
}

/// rt4's selective roof removal (`Preferences.removeRoofsSelectively`, mode 2 of `ScriptRunner.method4047`).
/// Each frame it flood-fills the roof tiles above the player (and above the point where the camera ray
/// enters a building) with the current frame stamp; `Scene.draw` then skips every tile of a level above the
/// player's whose stamp equals `hideValue`. Ported from `ScriptRunner.method4302` (per-frame driver),
/// `ScriptRunner.method4348` (the flood fill) and `SceneGraph.method2251` (wall side codes).
///
/// Not ported: mode 1 ("always remove", only reachable with `allLevelsVisible` off) and the free camera
/// branch of `method4302`; this client only has rt4's player-following camera (`cameraType == 1`).
final class RoofHider {
	/// rt4 `ScriptRunner.aByteArrayArrayArray15`: per tile the frame stamp that marked it.
	private(set) var mask = [[[UInt8]]](repeating: [[UInt8]](repeating: [UInt8](repeating: 0, count: 104), count: 104), count: 4)
	/// rt4 `ScriptRunner.anInt3325`: draw counter.
	private(set) var frame = 0
	private(set) var boxes = [RoofBox](repeating: RoofBox(), count: 2)
	/// rt4 `PathFinder.queueX/Z` reused as the flood queue: tile plus three shape codes of the edge crossed.
	private var queue = [(x: Int, z: Int, a: Int, b: Int, c: Int)](repeating: (0, 0, 0, 0, 0), count: 4096)

	/// The stamp `Scene.draw` compares against (rt4 `local387`).
	var hideValue: UInt8 { UInt8(truncatingIfNeeded: frame) }

	/// rt4 `ScriptRunner.method960` for mode 2: all tiles start as "stamped four frames ago".
	init() {
		let v = UInt8(truncatingIfNeeded: frame - 4)
		for l in 0..<4 { for x in 0..<104 { for z in 0..<104 { mask[l][x][z] = v } } }
	}

	/// rt4 `SceneGraph.method2251`: the wall side mask for a roof edge shape code (shape 18 or 19/21 plus rotation).
	private static func wallSide(_ code: Int) -> Int {
		let shape = code & 0x3F, rot = (code >> 6) & 3
		if shape == 18 { return 1 << rot }
		if shape == 19 || shape == 21 { return 16 << rot }
		return 0
	}

	/// rt4 `ScriptRunner.method4302`, called once per drawn frame before `Scene.draw`.
	/// - Parameters:
	///   - playerTile / cameraFine: scene tile of the player and the camera eye in fine units.
	///   - pitch: camera pitch (rt4 `Camera.cameraPitch`).
	func update(scene: Scene, plane: Int, playerTile: (x: Int, z: Int), cameraX: Int, cameraZ: Int, pitch: Int) {
		frame += 1
		let clear = UInt8(truncatingIfNeeded: frame - 4)
		let row = frame % 104
		for l in 0..<4 { for z in 0..<104 { mask[l][row][z] = clear } }
		guard plane != 3 else { return }
		boxes = [RoofBox(), RoofBox()]
		let px = playerTile.x, pz = playerTile.z
		guard px >= 0, pz >= 0, px < 104, pz < 104 else { return }
		if scene.renderFlags[plane][px][pz] & 4 != 0 { flood(scene, plane, px, pz, region: 0) }
		if pitch >= 310 { return }
		var cx = cameraX >> 7, cz = cameraZ >> 7
		guard cx >= 0, cz >= 0, cx < 104, cz < 104 else { return }
		let dz = abs(cz - pz), dx = abs(px - cx)
		func roof() -> Bool {
			guard scene.renderFlags[plane][cx][cz] & 4 != 0 else { return false }
			flood(scene, plane, cx, cz, region: 1)
			return true
		}
		if dx <= dz {
			guard dz != 0 else { return }
			var err = 32768
			let slope = dx * 65536 / dz
			while cz != pz {
				cz += cz < pz ? 1 : -1
				if roof() { break }
				err += slope
				if err >= 65536 {
					if px > cx { cx += 1 } else if px < cx { cx -= 1 }
					err -= 65536
					if roof() { break }
				}
			}
			return
		}
		var err = 32768
		let slope = dz * 65536 / dx
		while px != cx {
			cx += px > cx ? 1 : -1
			if roof() { break }
			err += slope
			if err >= 65536 {
				if cz < pz { cz += 1 } else if pz < cz { cz -= 1 }
				err -= 65536
				if roof() { break }
			}
		}
	}

	/// rt4 `ScriptRunner.method4348`: stamps the roof tiles reachable from (x, z) at the levels above `plane`.
	/// Walls and scenery of roof-edge shapes keep the edge tiles of a roof visible from the side.
	@discardableResult
	private func flood(_ scene: Scene, _ plane: Int, _ x0: Int, _ z0: Int, region: Int) -> Bool {
		let stamp = hideValue
		if mask[plane][x0][z0] == stamp { return false }
		let flags = scene.renderFlags
		guard flags[plane][x0][z0] & 4 != 0 else { return false }
		var head = 0, tail = 1
		queue[0] = (x0, z0, 0, 0, 0)
		mask[plane][x0][z0] = stamp
		func push(_ x: Int, _ z: Int, _ a: Int, _ b: Int, _ c: Int) {
			queue[tail] = (x, z, a, b, c)
			tail = (tail + 1) & 0xFFF
			mask[plane][x][z] = stamp
		}
		while head != tail {
			let q = queue[head]
			head = (head + 1) & 0xFFF
			let x = q.x, z = q.z
			let noRoof = flags[plane][x][z] & 4 == 0
			var marked = false
			if plane < 3 {
				levels: for l in (plane + 1)...3 {
					guard flags[l][x][z] & 8 == 0 else { continue }
					if noRoof, let t = scene.tiles[l][x][z] {
						if let w = t.wall {
							var m = Self.wallSide(q.a)
							if w.primaryMask == m || w.secondaryMask == m { continue }
							if q.b != 0 {
								m = Self.wallSide(q.b)
								if m == w.primaryMask || w.secondaryMask == m { continue }
							}
							if q.c != 0 {
								m = Self.wallSide(q.c)
								if m == w.primaryMask || m == w.secondaryMask { continue }
							}
						}
						for i in 0..<t.sceneryCount {
							guard let s = t.scenery[i] else { continue }
							var shape = Int(truncatingIfNeeded: (s.key >> 14) & 0x3F)
							if shape == 21 { shape = 19 }
							let code = shape | Int(truncatingIfNeeded: (s.key >> 20) & 3) << 6
							if code == q.a || (q.b != 0 && code == q.b) || (q.c != 0 && q.c == code) { continue levels }
						}
					}
					marked = true
					if let t = scene.tiles[l][x][z] {
						for i in 0..<t.sceneryCount {
							guard let s = t.scenery[i], s.xMax != s.xMin || s.zMax != s.zMin else { continue }
							for sx in s.xMin...s.xMax { for sz in s.zMin...s.zMax where sx >= 0 && sz >= 0 && sx < 104 && sz < 104 { mask[l][sx][sz] = stamp } }
						}
					}
					mask[l][x][z] = stamp
				}
			}
			if marked {
				let h = scene.tileHeights[plane + 1][x][z]
				if h > boxes[region].height { boxes[region].height = h }
				let fx = x << 7
				if fx < boxes[region].minX { boxes[region].minX = fx } else if boxes[region].maxX < fx { boxes[region].maxX = fx }
				let fz = z << 7
				if boxes[region].minZ > fz { boxes[region].minZ = fz } else if boxes[region].maxZ < fz { boxes[region].maxZ = fz }
			}
			guard !noRoof else { continue }
			// West, north-west, north, north-east, east, south-west, south, south-east (the codes are rt4's
			// packed shape|rotation<<6 pairs for the roof edge crossed: 0x12/0x52/0x92/0xD2 = shape 18, 0x13... = 19).
			if x >= 1 && mask[plane][x - 1][z] != stamp { push(x - 1, z, 0x12, 0xD3, 0x13) }
			if z + 1 < 104 {
				let n = z + 1
				if x - 1 >= 0 && mask[plane][x - 1][n] != stamp && flags[plane][x][n] & 4 == 0 && flags[plane][x - 1][n - 1] & 4 == 0 { push(x - 1, n, 0x12, 0x52, 0x13) }
				if mask[plane][x][n] != stamp { push(x, n, 0x52, 0x13, 0x53) }
				if x + 1 < 104 && mask[plane][x + 1][n] != stamp && flags[plane][x][n] & 4 == 0 && flags[plane][x + 1][n - 1] & 4 == 0 { push(x + 1, n, 0x52, 0x92, 0x53) }
			}
			if x + 1 < 104 && mask[plane][x + 1][z] != stamp { push(x + 1, z, 0x92, 0x53, 0x93) }
			if z - 1 >= 0 {
				let s = z - 1
				if x - 1 >= 0 && mask[plane][x - 1][s] != stamp && flags[plane][x][s] & 4 == 0 && flags[plane][x - 1][s + 1] & 4 == 0 { push(x - 1, s, 0xD2, 0x12, 0xD3) }
				if mask[plane][x][s] != stamp { push(x, s, 0xD2, 0x93, 0xD3) }
				if x + 1 < 104 && mask[plane][x + 1][s] != stamp && flags[plane][x][s] & 4 == 0 && flags[plane][x + 1][s + 1] & 4 == 0 { push(x + 1, s, 0x92, 0xD2, 0x93) }
			}
		}
		if boxes[region].height != -1_000_000 {
			boxes[region].height += 10
			boxes[region].minX -= 50; boxes[region].maxX += 50
			boxes[region].maxZ += 50; boxes[region].minZ -= 50
		}
		return true
	}
}
