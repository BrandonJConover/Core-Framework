/// Route search on the 104x104 scene grid. Port of rt4 `PathFinder`
/// (`findPath` dispatching to `findPathN` for size 1, `findPath2` and
/// `findPath1` for size 3+) and of `ClientProt.method3502`, which turns the
/// found route into the walk packet.
public final class PathFinder {
	/// Which packet the route is sent as (the `arg` rt4 passes down to
	/// `method3502`): 0 MOVE_GAMECLICK, 1 MOVE_MINIMAPCLICK, 2 opcode 77
	/// (walk to interact with a target; same layout as GAMECLICK).
	public enum WalkType: Int {
		case gameClick = 0
		case minimapClick = 1
		case interact = 2
	}

	/// What the route should end at. Mirrors the argument bundle rt4 hands to
	/// `PathFinder.findPath`: a plain tile, a rectangle (loc/entity) with the
	/// sides that may not be used, or a wall/decoration shape.
	public struct Target {
		public var destX: Int
		public var destZ: Int
		/// 0 for a plain tile target (no rectangle test).
		public var destWidth = 0
		public var destLength = 0
		/// 4-bit mask (1 north, 2 east, 4 south, 8 west): faces of the rectangle one may not stand next to.
		public var blockedSides = 0
		/// 0 = none, else `shape + 1` of a wall/decor loc (rt4 passes shape+1).
		public var destType = 0
		public var destAngle = 0

		/// Walk to a tile (rt4 `findPath(.., width 0, type 0)`).
		public static func tile(x: Int, z: Int) -> Target { Target(destX: x, destZ: z) }

		/// Walk next to / onto a 1x1 entity (rt4 npc/player click: width 1, length 1).
		public static func entity(x: Int, z: Int, size: Int = 1) -> Target {
			Target(destX: x, destZ: z, destWidth: size, destLength: size)
		}

		/// rt4 `PathFinder.findPathToLoc`: scenery (shapes 10, 11, 22) is a rectangle
		/// whose blocked sides rotate with the loc; anything else is a wall or
		/// wall decoration reached through `isAtWall`/`isAtWallDecor`.
		public static func loc(shape: Int, angle: Int, x: Int, z: Int, type: LocType) -> Target {
			if shape == 10 || shape == 11 || shape == 22 {
				let evenAngle = angle == 0 || angle == 2
				var sides = type.blockSides
				if angle != 0 { sides = ((sides << angle) & 0xF) + (sides >> (4 - angle)) }
				return Target(destX: x, destZ: z,
				              destWidth: evenAngle ? type.width : type.length,
				              destLength: evenAngle ? type.length : type.width,
				              blockedSides: sides)
			}
			return Target(destX: x, destZ: z, destType: shape + 1, destAngle: angle)
		}
	}

	public struct Route {
		/// Turn points in walking order (first = nearest the start), scene tiles
		/// (0..<104). The last point is where the walk ends.
		public var waypoints: [(x: Int, z: Int)]
		/// rt4 `anInt4364`: true when the target was not reached and the route
		/// goes to the closest reachable tile (the "nearest tile" fallback).
		public var partial: Bool
	}

	/// The fields `ClientProt.method3502` writes, with coordinates already in
	/// world tiles. `deltas` are relative to the first step.
	public struct WalkPacketFields {
		/// ClientProt opcode: moveGameclick (215), moveMinimapclick (39) or 77.
		public var opcode: Int
		/// First payload byte (p1add): CTRL held = run toggle.
		public var running: Bool
		public var firstX: Int
		public var firstZ: Int
		/// (x - firstX, z - firstZ) for the following points, at most 24.
		public var deltas: [(dx: Int, dz: Int)]
		/// The size byte rt4 writes after the opcode.
		public var payloadLength: Int { 2 * (deltas.count + 1) + 3 + (opcode == ClientProt.moveMinimapclick ? 14 : 0) }
		/// Destination for the client's red map flag (`mapFlagX/Z`, scene tiles).
		public var flag: (x: Int, z: Int)
	}

	private var parents = [Int](repeating: 0, count: 104 * 104)
	private var costs = [Int](repeating: 0, count: 104 * 104)
	private var queueX = [Int](repeating: 0, count: 4096)
	private var queueZ = [Int](repeating: 0, count: 4096)
	public let collision: CollisionMap

	public init(collision: CollisionMap) { self.collision = collision }

	@inline(__always) private func i(_ x: Int, _ z: Int) -> Int { x * 104 + z }

	// MARK: search

	/// rt4 `findPath`. `src` and the target are scene tiles. Returns nil when no
	/// route exists (rt4 returns false), including the case where the fallback
	/// tile is the start tile.
	public func findPath(srcX: Int, srcZ: Int, size: Int, target t: Target, allowFallback: Bool) -> Route? {
		guard srcX >= 0, srcX < 104, srcZ >= 0, srcZ < 104 else { return nil }
		for k in 0..<(104 * 104) { parents[k] = 0; costs[k] = 99999999 }
		parents[i(srcX, srcZ)] = 99
		costs[i(srcX, srcZ)] = 0
		var x = srcX, z = srcZ
		queueX[0] = srcX; queueZ[0] = srcZ
		var read = 0, write = 1
		var found = false
		while read != write {
			x = queueX[read]; z = queueZ[read]
			read = (read + 1) & 0xFFF
			if x == t.destX && z == t.destZ { found = true; break }
			if t.destType != 0 {
				if (t.destType < 5 || t.destType == 10)
					&& collision.isAtWall(srcZ: t.destZ, destX: x, destZ: z, srcX: t.destX, destType: t.destType - 1, size: size, destAngle: t.destAngle) {
					found = true; break
				}
				if t.destType < 10
					&& collision.isAtWallDecor(srcZ: t.destZ, destType: t.destType - 1, srcX: t.destX, destZ: z, size: size, destAngle: t.destAngle, destX: x) {
					found = true; break
				}
			}
			if t.destWidth != 0 && t.destLength != 0
				&& collision.isInsideOrOutsideRect(destX: t.destX, z: z, x: x, size: size, destWidth: t.destWidth, destBlockedSides: t.blockedSides, destZ: t.destZ, destLength: t.destLength) {
				found = true; break
			}
			let cost = costs[i(x, z)] + 1
			expand(x: x, z: z, size: size, cost: cost, write: &write)
		}
		var partial = false
		if !found {
			if !allowFallback { return nil }
			// Nearest explored tile to the target rectangle (cost < 100 within a 10-tile box).
			var best = 1000, bestCost = 100
			let w = t.destWidth, l = t.destLength
			for tx in (t.destX - 10)...(t.destX + 10) {
				for tz in (t.destZ - 10)...(t.destZ + 10) {
					guard tx >= 0, tz >= 0, tx < 104, tz < 104, costs[i(tx, tz)] < 100 else { continue }
					var dx = 0, dz = 0
					if tx < t.destX { dx = t.destX - tx } else if tx > w + t.destX - 1 { dx = tx + 1 - w - t.destX }
					if t.destZ > tz { dz = t.destZ - tz } else if tz > t.destZ + l - 1 { dz = tz + 1 - t.destZ - l }
					let d = dx * dx + dz * dz
					if d < best || (d == best && costs[i(tx, tz)] < bestCost) {
						x = tx; z = tz; bestCost = costs[i(tx, tz)]; best = d
					}
				}
			}
			if best == 1000 { return nil }
			if x == srcX && z == srcZ { return nil }
			partial = true
		}
		// Walk back along the parent directions collecting turn points.
		var points: [(x: Int, z: Int)] = [(x, z)]
		var dir = parents[i(x, z)]
		var lastDir = dir
		while x != srcX || z != srcZ {
			if lastDir != dir {
				points.append((x, z))
				lastDir = dir
			}
			if (dir & 0x2) != 0 { x += 1 } else if (dir & 0x8) != 0 { x -= 1 }
			if (dir & 0x1) != 0 { z += 1 } else if (dir & 0x4) != 0 { z -= 1 }
			dir = parents[i(x, z)]
		}
		return Route(waypoints: points.reversed(), partial: partial)
	}

	private func push(_ x: Int, _ z: Int, dir: Int, cost: Int, write: inout Int) {
		queueX[write] = x; queueZ[write] = z
		write = (write + 1) & 0xFFF
		parents[i(x, z)] = dir
		costs[i(x, z)] = cost
	}

	/// The eight neighbour tests of rt4 `findPathN` (size 1), `findPath2` (size 2)
	/// and `findPath1` (size 3+). The value stored in `parents` is the move that
	/// reached the tile, as bits: 1 = z+1, 2 = x+1, 4 = z-1, 8 = x-1 (so a tile
	/// reached by stepping west holds 2); walking back from the goal applies them
	/// as-is. 99 marks the start.
	private func expand(x: Int, z: Int, size s: Int, cost: Int, write: inout Int) {
		let c = collision
		if s == 1 {
			if x > 0 && parents[i(x - 1, z)] == 0 && (c[x - 1, z] & 0x12C0108) == 0 { push(x - 1, z, dir: 2, cost: cost, write: &write) }
			if x < 103 && parents[i(x + 1, z)] == 0 && (c[x + 1, z] & 0x12C0180) == 0 { push(x + 1, z, dir: 8, cost: cost, write: &write) }
			if z > 0 && parents[i(x, z - 1)] == 0 && (c[x, z - 1] & 0x12C0102) == 0 { push(x, z - 1, dir: 1, cost: cost, write: &write) }
			if z < 103 && parents[i(x, z + 1)] == 0 && (c[x, z + 1] & 0x12C0120) == 0 { push(x, z + 1, dir: 4, cost: cost, write: &write) }
			if x > 0 && z > 0 && parents[i(x - 1, z - 1)] == 0 && (c[x - 1, z - 1] & 0x12C010E) == 0 && (c[x - 1, z] & 0x12C0108) == 0 && (c[x, z - 1] & 0x12C0102) == 0 { push(x - 1, z - 1, dir: 3, cost: cost, write: &write) }
			if x < 103 && z > 0 && parents[i(x + 1, z - 1)] == 0 && (c[x + 1, z - 1] & 0x12C0183) == 0 && (c[x + 1, z] & 0x12C0180) == 0 && (c[x, z - 1] & 0x12C0102) == 0 { push(x + 1, z - 1, dir: 9, cost: cost, write: &write) }
			if x > 0 && z < 103 && parents[i(x - 1, z + 1)] == 0 && (c[x - 1, z + 1] & 0x12C0138) == 0 && (c[x - 1, z] & 0x12C0108) == 0 && (c[x, z + 1] & 0x12C0120) == 0 { push(x - 1, z + 1, dir: 6, cost: cost, write: &write) }
			if x < 103 && z < 103 && parents[i(x + 1, z + 1)] == 0 && (c[x + 1, z + 1] & 0x12C01E0) == 0 && (c[x + 1, z] & 0x12C0180) == 0 && (c[x, z + 1] & 0x12C0120) == 0 { push(x + 1, z + 1, dir: 12, cost: cost, write: &write) }
		} else if s == 2 {
			if x > 0 && parents[i(x - 1, z)] == 0 && (c[x - 1, z] & 0x12C010E) == 0 && (c[x - 1, z + 1] & 0x12C0138) == 0 { push(x - 1, z, dir: 2, cost: cost, write: &write) }
			if x < 102 && parents[i(x + 1, z)] == 0 && (c[x + 2, z] & 0x12C0183) == 0 && (c[x + 2, z + 1] & 0x12C01E0) == 0 { push(x + 1, z, dir: 8, cost: cost, write: &write) }
			if z > 0 && parents[i(x, z - 1)] == 0 && (c[x, z - 1] & 0x12C010E) == 0 && (c[x + 1, z - 1] & 0x12C0183) == 0 { push(x, z - 1, dir: 1, cost: cost, write: &write) }
			if z < 102 && parents[i(x, z + 1)] == 0 && (c[x, z + 2] & 0x12C0138) == 0 && (c[x + 1, z + 2] & 0x12C01E0) == 0 { push(x, z + 1, dir: 4, cost: cost, write: &write) }
			if x > 0 && z > 0 && parents[i(x - 1, z - 1)] == 0 && (c[x - 1, z] & 0x12C0138) == 0 && (c[x - 1, z - 1] & 0x12C010E) == 0 && (c[x, z - 1] & 0x12C0183) == 0 { push(x - 1, z - 1, dir: 3, cost: cost, write: &write) }
			if x < 102 && z > 0 && parents[i(x + 1, z - 1)] == 0 && (c[x + 1, z - 1] & 0x12C010E) == 0 && (c[x + 2, z - 1] & 0x12C0183) == 0 && (c[x + 2, z] & 0x12C01E0) == 0 { push(x + 1, z - 1, dir: 9, cost: cost, write: &write) }
			if x > 0 && z < 102 && parents[i(x - 1, z + 1)] == 0 && (c[x - 1, z + 1] & 0x12C010E) == 0 && (c[x - 1, z + 2] & 0x12C0138) == 0 && (c[x, z + 2] & 0x12C01E0) == 0 { push(x - 1, z + 1, dir: 6, cost: cost, write: &write) }
			if x < 102 && z < 102 && parents[i(x + 1, z + 1)] == 0 && (c[x + 1, z + 2] & 0x12C0138) == 0 && (c[x + 2, z + 2] & 0x12C01E0) == 0 && (c[x + 2, z + 1] & 0x12C0183) == 0 { push(x + 1, z + 1, dir: 12, cost: cost, write: &write) }
		} else {
			// findPath1: size 3 and up. `k` runs over the interior tiles of each edge.
			if x > 0 && parents[i(x - 1, z)] == 0 && (c[x - 1, z] & 0x12C010E) == 0 && (c[x - 1, s + z - 1] & 0x12C0138) == 0 {
				if (1..<max(1, s - 1)).allSatisfy({ (c[x - 1, z + $0] & 0x12C013E) == 0 }) { push(x - 1, z, dir: 2, cost: cost, write: &write) }
			}
			if x < 102 && parents[i(x + 1, z)] == 0 && (c[x + s, z] & 0x12C0183) == 0 && (c[x + s, z + s - 1] & 0x12C01E0) == 0 {
				if (1..<max(1, s - 1)).allSatisfy({ (c[x + s, z + $0] & 0x12C01E3) == 0 }) { push(x + 1, z, dir: 8, cost: cost, write: &write) }
			}
			if z > 0 && parents[i(x, z - 1)] == 0 && (c[x, z - 1] & 0x12C010E) == 0 && (c[x + s - 1, z - 1] & 0x12C0183) == 0 {
				if (1..<max(1, s - 1)).allSatisfy({ (c[x + $0, z - 1] & 0x12C018F) == 0 }) { push(x, z - 1, dir: 1, cost: cost, write: &write) }
			}
			if z < 102 && parents[i(x, z + 1)] == 0 && (c[x, z + s] & 0x12C0138) == 0 && (c[x + s - 1, z + s] & 0x12C01E0) == 0 {
				if (1..<max(1, s - 1)).allSatisfy({ (c[x + $0, z + s] & 0x12C01F8) == 0 }) { push(x, z + 1, dir: 4, cost: cost, write: &write) }
			}
			if x > 0 && z > 0 && parents[i(x - 1, z - 1)] == 0 && (c[x - 1, s + z - 2] & 0x12C0138) == 0 && (c[x - 1, z - 1] & 0x12C010E) == 0 && (c[x + s - 2, z - 1] & 0x12C0183) == 0 {
				if (1..<max(1, s - 1)).allSatisfy({ (c[x - 1, z + $0 - 1] & 0x12C013E) == 0 && (c[$0 + x - 1, z - 1] & 0x12C018F) == 0 }) { push(x - 1, z - 1, dir: 3, cost: cost, write: &write) }
			}
			if x < 102 && z > 0 && parents[i(x + 1, z - 1)] == 0 && (c[x + 1, z - 1] & 0x12C010E) == 0 && (c[x + s, z - 1] & 0x12C0183) == 0 && (c[x + s, z + s - 2] & 0x12C01E0) == 0 {
				if (1..<max(1, s - 1)).allSatisfy({ (c[x + s, z + $0 - 1] & 0x12C01E3) == 0 && (c[$0 + x + 1, z - 1] & 0x12C018F) == 0 }) { push(x + 1, z - 1, dir: 9, cost: cost, write: &write) }
			}
			if x > 0 && z < 102 && parents[i(x - 1, z + 1)] == 0 && (c[x - 1, z + 1] & 0x12C010E) == 0 && (c[x - 1, z + s] & 0x12C0138) == 0 && (c[x, z + s] & 0x12C01E0) == 0 {
				if (1..<max(1, s - 1)).allSatisfy({ (c[x - 1, z + $0 + 1] & 0x12C013E) == 0 && (c[$0 + x - 1, z + s] & 0x12C01F8) == 0 }) { push(x - 1, z + 1, dir: 6, cost: cost, write: &write) }
			}
			if x < 102 && z < 102 && parents[i(x + 1, z + 1)] == 0 && (c[x + 1, z + s] & 0x12C0138) == 0 && (c[x + s, z + s] & 0x12C01E0) == 0 && (c[x + s, z + 1] & 0x12C0183) == 0 {
				if (1..<max(1, s - 1)).allSatisfy({ (c[$0 + x + 1, z + s] & 0x12C01F8) == 0 && (c[x + s, $0 + z + 1] & 0x12C01E3) == 0 }) { push(x + 1, z + 1, dir: 12, cost: cost, write: &write) }
			}
		}
	}

	// MARK: packet

	/// rt4 `ClientProt.method3502`: the fields of the walk packet for `route`.
	/// `originX/Z` is the scene's world base (rt4 `Camera.originX/Z`). rt4 sends at
	/// most the first 25 turn points (nearest first).
	public static func walkPacketFields(route: Route, originX: Int, originZ: Int, walkType: WalkType, running: Bool) -> WalkPacketFields {
		let pts = Array(route.waypoints.prefix(25))
		let first = pts[0]
		let opcode: Int
		switch walkType {
		case .gameClick: opcode = ClientProt.moveGameclick
		case .minimapClick: opcode = ClientProt.moveMinimapclick
		case .interact: opcode = 77
		}
		return WalkPacketFields(
			opcode: opcode, running: running,
			firstX: originX + first.x, firstZ: originZ + first.z,
			deltas: pts.dropFirst().map { (dx: $0.x - first.x, dz: $0.z - first.z) },
			flag: route.waypoints[route.waypoints.count - 1])
	}

	/// The same packet as the existing `ClientMessage.walk` case (not for
	/// `.interact`, whose opcode 77 that case cannot send).
	public static func walkMessage(route: Route, originX: Int, originZ: Int, running: Bool, minimap: Bool) -> ClientMessage {
		let pts = route.waypoints.map { (x: originX + $0.x, z: originZ + $0.z) }
		return .walk(destX: pts[pts.count - 1].x, destZ: pts[pts.count - 1].z, path: Array(pts.dropLast()), ctrlRun: running, minimap: minimap)
	}
}
