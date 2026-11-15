/// One 64x64 map square's terrain (`m{x}_{z}` in archive 5), decoded like
/// rt4 `SceneGraph.readTile` for the four levels. Heights are absolute world
/// heights in rt4 units (negative = up), already resolved for unstated tiles.
public struct MapSquare {
	public static let size = 64

	public let regionX: Int
	public let regionZ: Int
	/// [level][x][z]
	public var heights = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: 65), count: 65), count: 4)
	public var underlays = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: 64), count: 64), count: 4)
	/// Overlay FloType id + 1 (0 = none).
	public var overlays = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: 64), count: 64), count: 4)
	public var shapes = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: 64), count: 64), count: 4)
	public var rotations = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: 64), count: 64), count: 4)
	/// rt4 renderFlags: 1 = blocked, 2 = bridge (level shift), 4 = roof, 8 = force-lowest...
	public var flags = [[[Int]]](repeating: [[Int]](repeating: [Int](repeating: 0, count: 64), count: 64), count: 4)

	/// `data` is the decompressed `m{x}_{z}` group.
	public init(regionX: Int, regionZ: Int, data: [UInt8]) throws {
		self.regionX = regionX
		self.regionZ = regionZ
		var p = Packet(data)
		let baseX = regionX * 64, baseZ = regionZ * 64
		for level in 0..<4 {
			for x in 0..<64 {
				for z in 0..<64 {
					while true {
						let op = try p.g1()
						if op == 0 {
							heights[level][x][z] = level == 0
								? -PerlinNoise.tileHeight(baseZ + z + 556238, baseX + x + 932731) * 8
								: heights[level - 1][x][z] - 240
							break
						}
						if op == 1 {
							var h = try p.g1()
							if h == 1 { h = 0 }
							heights[level][x][z] = level == 0 ? -h * 8 : heights[level - 1][x][z] - h * 8
							break
						}
						if op <= 49 {
							overlays[level][x][z] = try p.g1()
							shapes[level][x][z] = (op - 2) / 4
							rotations[level][x][z] = (op - 2) & 3
						} else if op <= 81 {
							flags[level][x][z] = op - 49
						} else {
							underlays[level][x][z] = op - 81
						}
					}
				}
			}
		}
		// The 65th row/column (needed for the far tile edges) copies its neighbour,
		// the way rt4 fills edges from the next region when it is not loaded.
		for level in 0..<4 {
			for i in 0..<65 {
				heights[level][64][i] = heights[level][63][min(i, 63)]
				heights[level][i][64] = heights[level][min(i, 63)][63]
			}
		}
	}
}

/// Locations (`l{x}_{z}`, XTEA-encrypted) placed in a map square.
public struct MapLoc: Equatable {
	public var id: Int
	/// Local tile within the square.
	public var x: Int
	public var z: Int
	public var level: Int
	public var shape: Int
	public var rotation: Int

	/// rt4 `SceneGraph.readLocs`: delta-coded ids (gsmarts) and packed positions.
	public static func decode(_ data: [UInt8]) throws -> [MapLoc] {
		var p = Packet(data)
		var out: [MapLoc] = []
		var id = -1
		while true {
			let idDelta = try p.gVarSmart()
			if idDelta == 0 { break }
			id += idDelta
			var pos = 0
			while true {
				let posDelta = try p.gsmarts()
				if posDelta == 0 { break }
				pos += posDelta - 1
				let attrs = try p.g1()
				out.append(MapLoc(id: id, x: pos >> 6 & 0x3F, z: pos & 0x3F, level: pos >> 12, shape: attrs >> 2, rotation: attrs & 3))
			}
		}
		return out
	}
}
