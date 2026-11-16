/// Walkability flags for one level of the 104x104 scene, and the geometric
/// reach checks the path finder uses. Port of rt4 `CollisionMap` (`client!mj`).
///
/// Flag bits (as in rt4; `Flag` names them). A wall bit says "this tile edge or
/// corner is walled": 0x1 NW corner, 0x2 north edge, 0x4 NE corner, 0x8 east
/// edge, 0x10 SE corner, 0x20 south edge, 0x40 SW corner, 0x80 west edge.
/// The same bits shifted left by 9 (0x200...0x10000) block projectiles.
/// 0x100 is solid scenery, 0x20000 scenery that also blocks projectiles,
/// 0x40000 ground decor, 0x200000 floor blocked (tile render flag 1) and
/// 0x1000000 marks a tile whose map square has not been loaded yet (set by
/// `clear`, removed by `markLoaded` as rt4's map-square loader does).
public final class CollisionMap {
	/// Named flag constants (rt4 uses the raw numbers inline).
	public enum Flag {
		public static let wallNorthWest = 0x1
		public static let wallNorth = 0x2
		public static let wallNorthEast = 0x4
		public static let wallEast = 0x8
		public static let wallSouthEast = 0x10
		public static let wallSouth = 0x20
		public static let wallSouthWest = 0x40
		public static let wallWest = 0x80
		public static let scenery = 0x100
		/// Projectile bits are the wall bits << 9.
		public static let projectileShift = 9
		public static let sceneryProjectile = 0x20000
		public static let groundDecor = 0x40000
		public static let floorBlocked = 0x200000
		/// Value `clear` writes for tiles outside the playable interior.
		public static let outside = 0xFFFFFF
		/// Bit `clear` sets on the interior until its map square is loaded.
		public static let unloaded = 0x1000000

		/// Movement masks the BFS tests (rt4 literals 0x12C0108 etc.).
		static let blockW = 0x12C0108
		static let blockE = 0x12C0180
		static let blockS = 0x12C0102
		static let blockN = 0x12C0120
		static let blockSW = 0x12C010E
		static let blockSE = 0x12C0183
		static let blockNW = 0x12C0138
		static let blockNE = 0x12C01E0
	}

	public let width: Int
	public let length: Int
	/// Column-major like rt4 (`flags[x][z]`), flattened: index `x * length + z`.
	public private(set) var flags: [Int]

	public init(width: Int = 104, length: Int = 104) {
		self.width = width
		self.length = length
		self.flags = [Int](repeating: 0, count: width * length)
		clear()
	}

	/// Flag value at a tile; tiles outside the array read as fully blocked
	/// (rt4 would throw there, the path finder never asks).
	@inline(__always)
	public subscript(x: Int, z: Int) -> Int {
		if x < 0 || z < 0 || x >= width || z >= length { return Flag.outside }
		return flags[x * length + z]
	}

	/// rt4 `clear`: border tiles (and the 5 tiles at the far edges) are fully
	/// blocked, the interior is "loaded, open".
	public func clear() {
		for x in 0..<width {
			for z in 0..<length {
				if x == 0 || z == 0 || x >= width - 5 || length - 5 <= z {
					flags[x * length + z] = 16777215
				} else {
					flags[x * length + z] = 16777216
				}
			}
		}
	}

	@inline(__always) private func flag(_ f: Int, _ x: Int, _ z: Int) {
		guard x >= 0, z >= 0, x < width, z < length else { return }
		flags[x * length + z] |= f
	}

	@inline(__always) private func unflag(_ f: Int, _ x: Int, _ z: Int) {
		guard x >= 0, z >= 0, x < width, z < length else { return }
		flags[x * length + z] &= ~f
	}

	// MARK: flagging

	/// rt4 map-square loading (`SceneGraph.method2203`): clears the "not loaded"
	/// bit on a tile; rt4 only does so for tiles 1...102.
	public func markLoaded(x: Int, z: Int) {
		guard x > 0, z > 0, x < 103, z < 103 else { return }
		flags[x * length + z] &= 0xFEFFFFFF
	}

	/// The (dx, dz, flag) edits rt4 `flagWall` makes for a wall shape (0 straight,
	/// 1/3 corners, 2 L) and rotation. Projectile bits are these flags << 9.
	private static func wallEdits(shape: Int, angle: Int) -> [(Int, Int, Int)] {
		switch shape {
		case 0:
			switch angle {
			case 0: return [(0, 0, 128), (-1, 0, 8)]
			case 1: return [(0, 0, 2), (0, 1, 32)]
			case 2: return [(0, 0, 8), (1, 0, 128)]
			case 3: return [(0, 0, 32), (0, -1, 2)]
			default: return []
			}
		case 1, 3:
			switch angle {
			case 0: return [(0, 0, 1), (-1, 1, 16)]
			case 1: return [(0, 0, 4), (1, 1, 64)]
			case 2: return [(0, 0, 16), (1, -1, 1)]
			case 3: return [(0, 0, 64), (-1, -1, 4)]
			default: return []
			}
		case 2:
			switch angle {
			case 0: return [(0, 0, 130), (-1, 0, 8), (0, 1, 32)]
			case 1: return [(0, 0, 10), (0, 1, 32), (1, 0, 128)]
			case 2: return [(0, 0, 40), (1, 0, 128), (0, -1, 2)]
			case 3: return [(0, 0, 160), (0, -1, 2), (-1, 0, 8)]
			default: return []
			}
		default:
			return []
		}
	}

	/// rt4 `flagWall(angle, shape, blocksProjectiles, z, x)`.
	public func flagWall(angle: Int, shape: Int, blocksProjectiles: Bool, x: Int, z: Int) {
		for (dx, dz, f) in Self.wallEdits(shape: shape, angle: angle) { flag(f, x + dx, z + dz) }
		if blocksProjectiles {
			for (dx, dz, f) in Self.wallEdits(shape: shape, angle: angle) { flag(f << Flag.projectileShift, x + dx, z + dz) }
		}
	}

	/// rt4 `unflagWall`.
	public func unflagWall(angle: Int, shape: Int, blocksProjectiles: Bool, x: Int, z: Int) {
		for (dx, dz, f) in Self.wallEdits(shape: shape, angle: angle) { unflag(f, x + dx, z + dz) }
		if blocksProjectiles {
			for (dx, dz, f) in Self.wallEdits(shape: shape, angle: angle) { unflag(f << Flag.projectileShift, x + dx, z + dz) }
		}
	}

	/// rt4 `flagScenery(x, blocksProjectiles, z, width, length)`: the caller has
	/// already swapped width/length for odd rotations.
	public func flagScenery(x: Int, z: Int, width w: Int, length l: Int, blocksProjectiles: Bool) {
		let f = blocksProjectiles ? 131328 : 256
		for x0 in x..<max(x, x + w) where x0 >= 0 && x0 < width {
			for z0 in z..<max(z, z + l) where z0 >= 0 && z0 < length { flag(f, x0, z0) }
		}
	}

	/// rt4 `unflagScenery`: swaps width/length itself for rotations 1 and 3.
	public func unflagScenery(x: Int, z: Int, width w: Int, length l: Int, angle: Int, blocksProjectiles: Bool) {
		let f = blocksProjectiles ? 131328 : 256
		let (w, l) = (angle == 1 || angle == 3) ? (l, w) : (w, l)
		for x0 in x..<max(x, x + w) where x0 >= 0 && x0 < width {
			for z0 in z..<max(z, z + l) where z0 >= 0 && z0 < length { unflag(f, x0, z0) }
		}
	}

	/// rt4 `flagGroundDecor`.
	public func flagGroundDecor(x: Int, z: Int) { flag(Flag.groundDecor, x, z) }
	/// rt4 `unflagGroundDecor`.
	public func unflagGroundDecor(x: Int, z: Int) { unflag(Flag.groundDecor, x, z) }
	/// rt4 `flagTile`: floor blocked by the map's tile render flag 1.
	public func flagTile(x: Int, z: Int) { flag(Flag.floorBlocked, x, z) }

	// MARK: reach checks

	/// rt4 `isAtWall`. NB rt4's parameter names are swapped relative to meaning:
	/// `srcX/srcZ` are the path TARGET tile (the loc), `destX/destZ` the BFS
	/// tile being tested. `destType` is the wall shape (0 straight, 2 L, 9 diag;
	/// the caller passes the packed `shape`), `destAngle` its rotation.
	public func isAtWall(srcZ: Int, destX: Int, destZ: Int, srcX: Int, destType: Int, size: Int, destAngle: Int) -> Bool {
		if size == 1 {
			if destX == srcX && destZ == srcZ { return true }
		} else if destX <= srcX && destX + size - 1 >= srcX && srcZ <= size + srcZ - 1 {
			return true
		}
		let endZ = destZ, startX = srcX, startZ = srcZ, endX = destX
		let b120 = 0x12C0120, b102 = 0x12C0102, b108 = 0x12C0108, b180 = 0x12C0180
		if size == 1 {
			if destType == 0 {
				if destAngle == 0 {
					if endX == startX - 1 && endZ == startZ { return true }
					if endX == startX && startZ + 1 == endZ && (self[endX, endZ] & b120) == 0 { return true }
					if startX == endX && startZ - 1 == endZ && (self[endX, endZ] & b102) == 0 { return true }
				} else if destAngle == 1 {
					if startX == endX && endZ == startZ + 1 { return true }
					if startX - 1 == endX && startZ == endZ && (self[endX, endZ] & b108) == 0 { return true }
					if endX == startX + 1 && endZ == startZ && (self[endX, endZ] & b180) == 0 { return true }
				} else if destAngle == 2 {
					if startX + 1 == endX && endZ == startZ { return true }
					if startX == endX && endZ == startZ + 1 && (self[endX, endZ] & b120) == 0 { return true }
					if startX == endX && startZ - 1 == endZ && (self[endX, endZ] & b102) == 0 { return true }
				} else if destAngle == 3 {
					if endX == startX && startZ - 1 == endZ { return true }
					if startX - 1 == endX && startZ == endZ && (self[endX, endZ] & b108) == 0 { return true }
					if startX + 1 == endX && endZ == startZ && (self[endX, endZ] & b180) == 0 { return true }
				}
			}
			if destType == 2 {
				if destAngle == 0 {
					if endX == startX - 1 && startZ == endZ { return true }
					if endX == startX && endZ == startZ + 1 { return true }
					if endX == startX + 1 && endZ == startZ && (self[endX, endZ] & b180) == 0 { return true }
					if startX == endX && endZ == startZ - 1 && (self[endX, endZ] & b102) == 0 { return true }
				} else if destAngle == 1 {
					if endX == startX - 1 && startZ == endZ && (self[endX, endZ] & b108) == 0 { return true }
					if startX == endX && startZ + 1 == endZ { return true }
					if endX == startX + 1 && startZ == endZ { return true }
					if startX == endX && endZ == startZ - 1 && (self[endX, endZ] & b102) == 0 { return true }
				} else if destAngle == 2 {
					if endX == startX - 1 && startZ == endZ && (self[endX, endZ] & b108) == 0 { return true }
					if startX == endX && endZ == startZ + 1 && (self[endX, endZ] & b120) == 0 { return true }
					if startX + 1 == endX && startZ == endZ { return true }
					if endX == startX && startZ - 1 == endZ { return true }
				} else if destAngle == 3 {
					if endX == startX - 1 && startZ == endZ { return true }
					if endX == startX && startZ + 1 == endZ && (self[endX, endZ] & b120) == 0 { return true }
					if endX == startX + 1 && startZ == endZ && (self[endX, endZ] & b180) == 0 { return true }
					if endX == startX && endZ == startZ - 1 { return true }
				}
			}
			if destType == 9 {
				if endX == startX && startZ + 1 == endZ && (self[endX, endZ] & 0x20) == 0 { return true }
				if endX == startX && endZ == startZ - 1 && (self[endX, endZ] & 0x2) == 0 { return true }
				if endX == startX - 1 && endZ == startZ && (self[endX, endZ] & 0x8) == 0 { return true }
				return startX + 1 == endX && startZ == endZ && (self[endX, endZ] & 0x80) == 0
			}
		} else {
			let x1 = size + endX - 1
			let z1 = endZ + size - 1
			if destType == 0 {
				if destAngle == 0 {
					if endX == startX - size && endZ <= startZ && startZ <= z1 { return true }
					if endX <= startX && x1 >= startX && startZ + 1 == endZ && (self[startX, endZ] & b120) == 0 { return true }
					if endX <= startX && x1 >= startX && startZ - size == endZ && (self[startX, z1] & b102) == 0 { return true }
				} else if destAngle == 1 {
					if startX >= endX && startX <= x1 && startZ + 1 == endZ { return true }
					if endX == startX - size && endZ <= startZ && z1 >= startZ && (self[x1, startZ] & b108) == 0 { return true }
					if endX == startX + 1 && endZ <= startZ && z1 >= startZ && (self[endX, startZ] & b180) == 0 { return true }
				} else if destAngle == 2 {
					if startX + 1 == endX && endZ <= startZ && startZ <= z1 { return true }
					if startX >= endX && x1 >= startX && endZ == startZ + 1 && (self[startX, endZ] & b120) == 0 { return true }
					if startX >= endX && x1 >= startX && startZ - size == endZ && (self[startX, z1] & b102) == 0 { return true }
				} else if destAngle == 3 {
					if endX <= startX && x1 >= startX && startZ - size == endZ { return true }
					if endX == startX - size && startZ >= endZ && z1 >= startZ && (self[x1, startZ] & b108) == 0 { return true }
					if startX + 1 == endX && endZ <= startZ && startZ <= z1 && (self[endX, startZ] & b180) == 0 { return true }
				}
			}
			if destType == 2 {
				if destAngle == 0 {
					if endX == startX - size && startZ >= endZ && startZ <= z1 { return true }
					if endX <= startX && x1 >= startX && endZ == startZ + 1 { return true }
					if startX + 1 == endX && startZ >= endZ && startZ <= z1 && (self[endX, startZ] & b180) == 0 { return true }
					if startX >= endX && x1 >= startX && startZ - size == endZ && (self[startX, z1] & b102) == 0 { return true }
				} else if destAngle == 1 {
					if endX == startX - size && startZ >= endZ && startZ <= z1 && (self[x1, startZ] & b108) == 0 { return true }
					if endX <= startX && x1 >= startX && endZ == startZ + 1 { return true }
					if startX + 1 == endX && startZ >= endZ && startZ <= z1 { return true }
					if startX >= endX && startX <= x1 && endZ == startZ - size && (self[startX, z1] & b102) == 0 { return true }
				} else if destAngle == 2 {
					if startX - size == endX && endZ <= startZ && z1 >= startZ && (self[x1, startZ] & b108) == 0 { return true }
					if endX <= startX && startX <= x1 && endZ == startZ + 1 && (self[startX, endZ] & b120) == 0 { return true }
					if endX == startX + 1 && endZ <= startZ && startZ <= z1 { return true }
					if endX <= startX && x1 >= startX && startZ - size == endZ { return true }
				} else if destAngle == 3 {
					if startX - size == endX && startZ >= endZ && startZ <= z1 { return true }
					if endX <= startX && startX <= x1 && startZ + 1 == endZ && (self[startX, endZ] & b120) == 0 { return true }
					if endX == startX + 1 && startZ >= endZ && startZ <= z1 && (self[endX, startZ] & b180) == 0 { return true }
					if endX <= startX && x1 >= startX && startZ - size == endZ { return true }
				}
			}
			if destType == 9 {
				if endX <= startX && startX <= x1 && endZ == startZ + 1 && (self[startX, endZ] & b120) == 0 { return true }
				if startX >= endX && startX <= x1 && endZ == startZ - size && (self[startX, z1] & b102) == 0 { return true }
				if startX - size == endX && startZ >= endZ && startZ <= z1 && (self[x1, startZ] & b108) == 0 { return true }
				return endX == startX + 1 && startZ >= endZ && z1 >= startZ && (self[endX, startZ] & b180) == 0
			}
		}
		return false
	}

	/// rt4 `isAtWallDecor`: reach check for wall decorations (types 6/7 diagonal
	/// decor, 8 both). Parameter naming as in `isAtWall` (src = target).
	public func isAtWallDecor(srcZ: Int, destType: Int, srcX: Int, destZ: Int, size: Int, destAngle angleIn: Int, destX: Int) -> Bool {
		var destAngle = angleIn
		if size == 1 {
			if srcX == destX && srcZ == destZ { return true }
		} else if destX <= srcX && size + destX - 1 >= srcX && srcZ + size - 1 >= srcZ {
			return true
		}
		let endX = destX, startZ = srcZ, startX = srcX, endZ = destZ
		if size == 1 {
			if destType == 6 || destType == 7 {
				if destType == 7 { destAngle = (destAngle + 2) & 0x3 }
				if destAngle == 0 {
					if endX == startX + 1 && startZ == endZ && (self[endX, endZ] & 0x80) == 0 { return true }
					if startX == endX && endZ == startZ - 1 && (self[endX, endZ] & 0x2) == 0 { return true }
				} else if destAngle == 1 {
					if endX == startX - 1 && startZ == endZ && (self[endX, endZ] & 0x8) == 0 { return true }
					if startX == endX && endZ == startZ - 1 && (self[endX, endZ] & 0x2) == 0 { return true }
				} else if destAngle == 2 {
					if endX == startX - 1 && endZ == startZ && (self[endX, endZ] & 0x8) == 0 { return true }
					if startX == endX && startZ + 1 == endZ && (self[endX, endZ] & 0x20) == 0 { return true }
				} else if destAngle == 3 {
					if endX == startX + 1 && endZ == startZ && (self[endX, endZ] & 0x80) == 0 { return true }
					if startX == endX && endZ == startZ + 1 && (self[endX, endZ] & 0x20) == 0 { return true }
				}
			}
			if destType == 8 {
				if endX == startX && startZ + 1 == endZ && (self[endX, endZ] & 0x20) == 0 { return true }
				if endX == startX && startZ - 1 == endZ && (self[endX, endZ] & 0x2) == 0 { return true }
				if startX - 1 == endX && endZ == startZ && (self[endX, endZ] & 0x8) == 0 { return true }
				return endX == startX + 1 && startZ == endZ && (self[endX, endZ] & 0x80) == 0
			}
		} else {
			let x1 = endX + size - 1
			let z1 = endZ + size - 1
			if destType == 6 || destType == 7 {
				if destType == 7 { destAngle = (destAngle + 2) & 0x3 }
				if destAngle == 0 {
					if startX + 1 == endX && endZ <= startZ && startZ <= z1 && (self[endX, startZ] & 0x80) == 0 { return true }
					if startX >= endX && x1 >= startX && startZ - size == endZ && (self[startX, z1] & 0x2) == 0 { return true }
				} else if destAngle == 1 {
					if startX - size == endX && startZ >= endZ && z1 >= startZ && (self[x1, startZ] & 0x8) == 0 { return true }
					if startX >= endX && x1 >= startX && startZ - size == endZ && (self[startX, z1] & 0x2) == 0 { return true }
				} else if destAngle == 2 {
					if endX == startX - size && startZ >= endZ && startZ <= z1 && (self[x1, startZ] & 0x8) == 0 { return true }
					if endX <= startX && startX <= x1 && endZ == startZ + 1 && (self[startX, endZ] & 0x20) == 0 { return true }
				} else if destAngle == 3 {
					if startX + 1 == endX && endZ <= startZ && startZ <= z1 && (self[endX, startZ] & 0x80) == 0 { return true }
					if startX >= endX && startX <= x1 && endZ == startZ + 1 && (self[startX, endZ] & 0x20) == 0 { return true }
				}
			}
			if destType == 8 {
				if endX <= startX && x1 >= startX && endZ == startZ + 1 && (self[startX, endZ] & 0x20) == 0 { return true }
				if startX >= endX && x1 >= startX && endZ == startZ - size && (self[startX, z1] & 0x2) == 0 { return true }
				if endX == startX - size && endZ <= startZ && z1 >= startZ && (self[x1, startZ] & 0x8) == 0 { return true }
				return endX == startX + 1 && startZ >= endZ && startZ <= z1 && (self[endX, startZ] & 0x80) == 0
			}
		}
		return false
	}

	/// rt4 `isInsideRect` (private): do two rectangles overlap.
	private func isInsideRect(_ a0: Int, _ a1: Int, _ a2: Int, _ a3: Int, _ a4: Int, _ a5: Int, _ a6: Int, _ a7: Int) -> Bool {
		if a1 + a2 > a7 && a2 < a0 + a7 {
			return a3 + a5 > a4 && a6 + a4 > a5
		}
		return false
	}

	/// rt4 `isOutsideRect` (private): is the actor rectangle (x,z,size) flush
	/// against an unblocked side of the destination rectangle.
	private func isOutsideRect(_ a0: Int, _ z1: Int, _ a2: Int, _ destBlockedSides: Int, _ a4: Int, _ a5: Int, _ destZ: Int, _ a7: Int, _ destLength: Int) -> Bool {
		let l9 = a5 + a7
		let destZ1 = destZ + destLength
		let l22 = a2 + a0
		let l27 = z1 + a4
		if a5 >= a0 && a5 < l22 {
			if destZ1 == z1 && (destBlockedSides & 0x4) == 0 {
				var z0 = a5
				let end = l22 >= l9 ? l9 : l22
				while end > z0 {
					if (self[z0, destZ1 - 1] & 0x2) == 0 { return true }
					z0 += 1
				}
			} else if l27 == destZ && (destBlockedSides & 0x1) == 0 {
				var z0 = a5
				let end = l9 > l22 ? l22 : l9
				while end > z0 {
					if (self[z0, destZ] & 0x20) == 0 { return true }
					z0 += 1
				}
			}
		} else if l9 > a0 && l9 <= l22 {
			if z1 == destZ1 && (destBlockedSides & 0x4) == 0 {
				for z0 in a0..<l9 where (self[z0, destZ1 - 1] & 0x2) == 0 { return true }
			} else if destZ == l27 && (destBlockedSides & 0x1) == 0 {
				for z0 in a0..<l9 where (self[z0, destZ] & 0x20) == 0 { return true }
			}
		} else if destZ >= z1 && l27 > destZ {
			if l9 == a0 && (destBlockedSides & 0x8) == 0 {
				var z0 = destZ
				let end = l27 >= destZ1 ? destZ1 : l27
				while z0 < end {
					if (self[l9 - 1, z0] & 0x8) == 0 { return true }
					z0 += 1
				}
			} else if a5 == l22 && (destBlockedSides & 0x2) == 0 {
				var z0 = destZ
				let end = l27 < destZ1 ? l27 : destZ1
				while z0 < end {
					if (self[a5, z0] & 0x80) == 0 { return true }
					z0 += 1
				}
			}
		} else if z1 < destZ1 && l27 >= destZ1 {
			if l9 == a0 && (destBlockedSides & 0x8) == 0 {
				for z0 in z1..<destZ1 where (self[l9 - 1, z0] & 0x8) == 0 { return true }
			} else if l22 == a5 && (destBlockedSides & 0x2) == 0 {
				for z0 in z1..<destZ1 where (self[a5, z0] & 0x80) == 0 { return true }
			}
		}
		return false
	}

	/// rt4 `isInsideOrOutsideRect`: has the actor (at x,z with `size`) reached
	/// the destination rectangle (destX, destZ, destWidth x destLength), either
	/// standing inside it or beside a side whose bit is not in `destBlockedSides`
	/// (bit 1 north face, 2 east, 4 south, 8 west) and with no wall in between.
	public func isInsideOrOutsideRect(destX: Int, z: Int, x: Int, size: Int, destWidth: Int, destBlockedSides: Int, destZ: Int, destLength: Int) -> Bool {
		if size > 1 {
			return isInsideRect(size, destWidth, destX, destLength, z, destZ, size, x)
				|| isOutsideRect(destX, destZ, destWidth, destBlockedSides, destLength, x, z, size, size)
		}
		let destX1 = destWidth + destX - 1
		let destZ1 = destZ + destLength - 1
		if destX <= x && destX1 >= x && destZ <= z && z <= destZ1 { return true }
		if destX - 1 == x && z >= destZ && z <= destZ1 && (self[x, z] & 0x8) == 0 && (destBlockedSides & 0x8) == 0 { return true }
		if x == destX1 + 1 && destZ <= z && destZ1 >= z && (self[x, z] & 0x80) == 0 && (destBlockedSides & 0x2) == 0 { return true }
		if z == destZ - 1 && destX <= x && destX1 >= x && (self[x, z] & 0x2) == 0 && (destBlockedSides & 0x4) == 0 { return true }
		return z == destZ1 + 1 && x >= destX && destX1 >= x && (self[x, z] & 0x20) == 0 && (destBlockedSides & 0x1) == 0
	}

	/// rt4 `method3054`: line-of-walk test between two tiles (a Bresenham-style
	/// walk with 16.16 fixed point), true if no wall/scenery blocks the line.
	/// Used by rt4 for click-to-walk visibility checks.
	public func hasWalkLine(fromX arg2: Int, fromZ arg1: Int, toX arg3: Int, toZ arg0: Int) -> Bool {
		if arg3 == arg2 && arg0 == arg1 { return true }
		let l22 = arg1, l33 = arg2
		if l33 < 0 || width <= l33 || l22 < 0 || l22 >= length { return false }
		var l61 = arg0, l66 = arg3
		let dx = abs(l33 - l66)
		let dz = abs(l22 - l61)
		var frac = 32768
		if dx <= dz {
			let step = (dx * 65536) / dz
			while l61 != l22 {
				if l22 > l61 {
					if (self[l66, l61] & 0x12C0102) != 0 { return false }
					l61 += 1
				} else if l22 < l61 {
					if (self[l66, l61] & 0x12C0120) != 0 { return false }
					l61 -= 1
				}
				frac += step
				if frac >= 65536 {
					frac -= 65536
					if l66 < l33 {
						if (self[l66, l61] & 0x12C0108) != 0 { return false }
						l66 += 1
					} else if l66 > l33 {
						if (self[l66, l61] & 0x12C0180) != 0 { return false }
						l66 -= 1
					}
				}
			}
		} else {
			let step = (dz * 65536) / dx
			while l33 != l66 {
				if l66 < l33 {
					if (self[l66, l61] & 0x12C0108) != 0 { return false }
					l66 += 1
				} else if l33 < l66 {
					if (self[l66, l61] & 0x12C0180) != 0 { return false }
					l66 -= 1
				}
				frac += step
				if frac >= 65536 {
					frac -= 65536
					if l61 < l22 {
						if (self[l66, l61] & 0x12C0102) != 0 { return false }
						l61 += 1
					} else if l22 < l61 {
						if (self[l66, l61] & 0x12C0120) != 0 { return false }
						l61 -= 1
					}
				}
			}
		}
		return (self[l33, l22] & 0x1240100) == 0
	}
}
