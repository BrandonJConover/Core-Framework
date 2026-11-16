/// Fills collision maps from decoded map data, the way rt4 does while loading a
/// scene: `SceneGraph.method1169` flags floor-blocked tiles from the tile render
/// flags, then `SceneGraph.readLocs` -> `addLoc` flags each loc into the map of
/// its level (shifted down one level under a bridge).
public enum CollisionBuilder {
	/// One decoded 64x64 map square with its locs.
	public struct Square {
		public var terrain: MapSquare
		public var locs: [MapLoc]
		public init(terrain: MapSquare, locs: [MapLoc]) { self.terrain = terrain; self.locs = locs }
	}

	/// Builds the four per-level collision maps for the 104x104 scene whose south-west
	/// tile is world tile (`baseX`, `baseZ`). `locType` resolves a loc id (rt4
	/// `LocTypeList.get`; multi-locs are NOT resolved, as in rt4).
	public static func build(baseX: Int, baseZ: Int, squares: [Square], locType: (Int) throws -> LocType?) throws -> [CollisionMap] {
		let maps = (0..<4).map { _ in CollisionMap(width: 104, length: 104) }

		// Scene-wide render flags [level][x][z] (rt4 `SceneGraph.renderFlags`).
		var render = [[[UInt8]]](repeating: [[UInt8]](repeating: [UInt8](repeating: 0, count: 104), count: 104), count: 4)
		for sq in squares {
			let ox = sq.terrain.regionX * 64 - baseX, oz = sq.terrain.regionZ * 64 - baseZ
			for level in 0..<4 {
				for x in 0..<64 where ox + x >= 0 && ox + x < 104 {
					for z in 0..<64 where oz + z >= 0 && oz + z < 104 {
						maps[level].markLoaded(x: ox + x, z: oz + z)
						render[level][ox + x][oz + z] = UInt8(truncatingIfNeeded: sq.terrain.flags[level][x][z])
					}
				}
			}
		}

		// rt4 `method1169` (not underwater): floor-blocked tiles.
		for level in 0..<4 {
			for x in 0..<104 {
				for z in 0..<104 where (render[level][x][z] & 0x1) == 1 {
					var target = level
					if (render[1][x][z] & 0x2) == 2 { target = level - 1 }
					if target >= 0 { maps[target].flagTile(x: x, z: z) }
				}
			}
		}

		// rt4 `readLocs`.
		for sq in squares {
			let ox = sq.terrain.regionX * 64 - baseX, oz = sq.terrain.regionZ * 64 - baseZ
			for loc in sq.locs {
				let x = loc.x + ox, z = loc.z + oz
				guard x > 0, z > 0, x < 103, z < 103 else { continue }
				var marking = loc.level
				if (render[1][x][z] & 0x2) == 2 { marking -= 1 }
				guard marking >= 0, let type = try locType(loc.id) else { continue }
				flagLoc(maps[marking], type: type, shape: loc.shape, rotation: loc.rotation, x: x, z: z)
			}
		}
		return maps
	}

	/// Convenience: loads the squares covering the scene from the cache, using
	/// `keys(regionX, regionZ)` for the loc XTEA keys (all-zero keys mean plain).
	public static func build(store: ConfigStore, baseX: Int, baseZ: Int, keys: (Int, Int) -> [Int32]) throws -> [CollisionMap] {
		var squares: [Square] = []
		for rx in (baseX >> 6)...((baseX + 103) >> 6) {
			for rz in (baseZ >> 6)...((baseZ + 103) >> 6) {
				guard let terrain = try store.mapSquare(x: rx, z: rz) else { continue }
				let locs = try store.mapLocs(x: rx, z: rz, key: keys(rx, rz)) ?? []
				squares.append(Square(terrain: terrain, locs: locs))
			}
		}
		return try build(baseX: baseX, baseZ: baseZ, squares: squares, locType: { try store.loc($0) })
	}

	/// The collision part of rt4 `SceneGraph.addLoc`, by loc shape:
	/// 0-3 walls (`flagWall`), 9 diagonal wall and 10/11/12+ scenery/roofs
	/// (`flagScenery`, when blockwalk != 0), 22 ground decor (blockwalk == 1).
	/// Wall decorations (4-8) never block.
	public static func flagLoc(_ map: CollisionMap, type: LocType, shape: Int, rotation: Int, x: Int, z: Int) {
		let swap = rotation == 1 || rotation == 3
		let w = swap ? type.length : type.width
		let l = swap ? type.width : type.length
		switch shape {
		case 22:
			if type.blockWalk == 1 { map.flagGroundDecor(x: x, z: z) }
		case 10, 11:
			if type.blockWalk != 0 { map.flagScenery(x: x, z: z, width: w, length: l, blocksProjectiles: type.blockRange) }
		case 0, 1, 2, 3:
			if type.blockWalk != 0 { map.flagWall(angle: rotation, shape: shape, blocksProjectiles: type.blockRange, x: x, z: z) }
		case 9:
			if type.blockWalk != 0 { map.flagScenery(x: x, z: z, width: w, length: l, blocksProjectiles: type.blockRange) }
		case 12...:
			if type.blockWalk != 0 { map.flagScenery(x: x, z: z, width: w, length: l, blocksProjectiles: type.blockRange) }
		default:
			break
		}
	}
}
