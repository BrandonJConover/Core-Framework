import Foundation

/// REBUILD_REGION scenes (rt4 `Protocol.readRebuildPacket(true)` then `LoginManager.rebuildMap`): the 104x104 scene is
/// assembled from 8x8 tile chunks copied out of the cache's map squares, each turned by its own rotation.
extension WorldView {
	/// rt4 `LoginManager.method1286`: the scene x offset (0...7 within the chunk) of a loc whose map-file tile is
	/// (`x`, `z`) after the chunk is turned `chunkRotation` quarter turns and the loc itself `locRotation`.
	static func dynamicLocX(chunkRotation: Int, locRotation: Int, x: Int, z: Int, width: Int, length: Int) -> Int {
		var w = width, l = length
		if locRotation & 1 == 1 { swap(&w, &l) }
		switch chunkRotation & 3 {
		case 0: return x
		case 1: return z
		case 2: return 7 + 1 - x - w
		default: return 7 + 1 - z - l
		}
	}

	/// rt4 `LoginManager.method4541`.
	static func dynamicLocZ(chunkRotation: Int, locRotation: Int, x: Int, z: Int, width: Int, length: Int) -> Int {
		var w = width, l = length
		if locRotation & 1 == 1 { swap(&w, &l) }
		switch chunkRotation & 3 {
		case 0: return z
		case 1: return 7 + 1 - x - w
		case 2: return 1 + 7 - l - z
		default: return x
		}
	}

	/// Builds the terrain, the locs and the collision of a dynamic region into `scene`; returns the number of locs that
	/// failed to place.
	static func buildDynamic(_ r: RebuildNormal, table: [Int], scene s: Scene, placer: LocPlacer, placed: inout [LocPlacement],
	                         out: BuiltWorld, store: ConfigStore) throws -> Int {
		// Map squares and loc files by region, with the XTEA key of the region in `r.regions` order.
		let regions = r.regions
		var squares: [Int: MapSquare] = [:]
		var locFiles: [Int: [MapLoc]] = [:]
		for (i, region) in regions.enumerated() {
			if let sq = try store.mapSquare(x: region.x, z: region.z) { squares[region.id] = sq }
			let key = i < r.xteaKeys.count ? r.xteaKeys[i] : [0, 0, 0, 0]
			locFiles[region.id] = (try? store.mapLocs(x: region.x, z: region.z, key: key)) ?? nil ?? []
		}
		var list: [LocPlacement] = []
		placer.onPlaced = { list.append($0) }
		var failures = 0
		var placedLocs: [CollisionBuilder.PlacedLoc] = []
		let terrain = try s.loadChunks(table, square: { squares[$0 << 8 | $1] }, centralPlane: r.plane) { scene in
			// rt4 `method4002`: per destination level and chunk, the locs of the source chunk, turned with it.
			for level in 0..<4 {
				for cx in 0..<13 {
					for cz in 0..<13 {
						let packed = table[(level * 13 + cx) * 13 + cz]
						guard packed != -1 else { continue }
						let srcLevel = packed >> 24 & 3, rotation = packed >> 1 & 3
						let chunkX = packed >> 14 & 0x3FF, chunkZ = packed >> 3 & 0x7FF
						guard let locs = locFiles[(chunkX / 8) << 8 | (chunkZ / 8)] else { continue }
						let x0 = (chunkX & 7) * 8, z0 = (chunkZ & 7) * 8
						for loc in locs where loc.level == srcLevel && loc.x >= x0 && loc.x < x0 + 8 && loc.z >= z0 && loc.z < z0 + 8 {
							guard let type = (try? store.loc(loc.id)) ?? nil else { continue }
							let x = dynamicLocX(chunkRotation: rotation, locRotation: loc.rotation, x: loc.x & 7, z: loc.z & 7, width: type.width, length: type.length) + cx * 8
							let z = dynamicLocZ(chunkRotation: rotation, locRotation: loc.rotation, x: loc.x & 7, z: loc.z & 7, width: type.width, length: type.length) + cz * 8
							guard x > 0, z > 0, x < 103, z < 103 else { continue }
							let turned = (loc.rotation + rotation) & 3
							do {
								try placer.addLoc(plane: level, locIndex: loc.id, shape: loc.shape, x: x, z: z, orientation: turned)
								placedLocs.append(CollisionBuilder.PlacedLoc(id: loc.id, level: level, x: x, z: z, shape: loc.shape, rotation: turned))
							} catch { failures += 1 }
						}
					}
				}
			}
		}
		out.collision = (try? CollisionBuilder.build(render: s.renderFlags, loaded: terrain.loaded, locs: placedLocs, locType: { try store.loc($0) }))
			?? (0..<4).map { _ in CollisionMap(width: 104, length: 104) }
		placed = list
		return failures
	}
}
