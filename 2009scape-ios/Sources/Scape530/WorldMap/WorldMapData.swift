import Foundation

/// One rectangle of a world map's display area, in world tiles (rt4 `MapChunk`).
public struct WorldMapArea: Equatable {
	public var minX: Int, minZ: Int, maxX: Int, maxZ: Int

	func contains(x: Int, z: Int) -> Bool { x >= minX && x <= maxX && z >= minZ && z <= maxZ }
}

/// A world map definition from the `details` group of archive 23 (rt4 `Map`): the main map, the
/// dungeon maps and so on.
public struct WorldMapDefinition {
	/// The archive group holding the map's data files (rt4 `Map.group`), e.g. "main".
	public let group: String
	/// The name shown to the player (rt4 `Map.name`).
	public let name: String
	/// The map's default centre, in 64 tile chunks (rt4 `originX`/`originZ`).
	public let originX: Int, originZ: Int
	/// -1 for none (rt4 `backgroundColor`): drawn outside the mapped area instead of the chequerboard.
	public let backgroundColor: Int
	public let valid: Bool
	/// 37, 50, 75, 100 or 200 (percent), 0 for the default.
	public let defaultZoom: Int
	public let areas: [WorldMapArea]
	/// The bounding box of `areas` (rt4 `computeBounds`).
	public let minX: Int, minZ: Int, maxX: Int, maxZ: Int

	init(_ data: [UInt8]) throws {
		var p = Packet(data)
		group = try p.gjstr()
		name = try p.gjstr()
		originX = try p.g2()
		originZ = try p.g2()
		backgroundColor = Int(try p.g4())
		valid = try p.g1() == 1
		var zoom = try p.g1()
		if zoom == 255 { zoom = 0 }
		defaultZoom = zoom
		let n = try p.g1()
		var list: [WorldMapArea] = []
		var lo = (x: 12800, z: 12800), hi = (x: 0, z: 0)
		for _ in 0..<n {
			let a = WorldMapArea(minX: try p.g2(), minZ: try p.g2(), maxX: try p.g2(), maxZ: try p.g2())
			list.append(a)
			lo.z = min(lo.z, a.minZ); lo.x = min(lo.x, a.minX)
			hi.x = max(hi.x, a.maxX); hi.z = max(hi.z, a.maxZ)
		}
		areas = list
		minX = lo.x; minZ = lo.z; maxX = hi.x; maxZ = hi.z
	}

	/// rt4 `Map.method664`: is the tile inside the display area?
	public func contains(x: Int, z: Int) -> Bool {
		if x < minX || x > maxX || z < minZ || z > maxZ { return false }
		return areas.contains { $0.contains(x: x, z: z) }
	}
}

/// Text labels of a map (rt4 `MapElementList`, from the `<group>_labels` group).
struct WorldMapLabels {
	var names: [String] = []
	/// bits 0-1: size class, 0x4, 0x8: drawn on the map, 0x10: left out of the search list.
	var flags: [Int] = []
	var x: [Int] = []
	var z: [Int] = []
	/// -1 for the size class's default colour.
	var colour: [Int] = []

	var count: Int { names.count }
	func isDrawn(_ i: Int) -> Bool { (flags[i] & 0x8) != 0 }
	func sizeClass(_ i: Int) -> Int { flags[i] & 0x3 }
	func isListed(_ i: Int) -> Bool { (flags[i] & 0x10) == 0 }
}

/// A map function placed on the map (rt4 `MapElement`); positions are the chunk's corner like rt4 stores.
struct WorldMapElement {
	var id: Int
	var x: Int
	var z: Int
}

/// The decoded data of the loaded map, per 64x64 chunk (rt4 `WorldMap.aByteArrayArrayArray*`).
/// All arrays are indexed `[chunkX][chunkZ]` with chunk z counted from the top (north) of the map and each chunk
/// holding 4096 entries at `(z & 63) << 6 | (x & 63)`.
struct WorldMapChunks {
	typealias Grid<T> = [[[T]?]]
	/// Palette colour per tile (rt4 `anIntArrayArrayArray17`), 0 for none.
	var ground: Grid<Int32>
	/// Overlay id and shape/rotation (rt4 arrays 3 and 8), and the second overlay (12 and 10).
	var overlay: Grid<UInt8>, overlayShape: Grid<UInt8>
	var overlay2: Grid<UInt8>, overlay2Shape: Grid<UInt8>
	/// Wall line type per tile (rt4 array 7).
	var lines: Grid<UInt8>
	/// Map scene: `id (14 bits) | angle << 14 | width << 16 | height << 20`.
	var scenery: Grid<Int32>
	/// loc id + 1 of the tile's map function (rt4 `underlayColors`, misnamed).
	var icons: Grid<Int32>

	init(chunksX: Int, chunksZ: Int) {
		func grid<T>(_: T.Type) -> Grid<T> { Array(repeating: Array(repeating: nil, count: chunksZ), count: chunksX) }
		ground = grid(Int32.self)
		overlay = grid(UInt8.self); overlayShape = grid(UInt8.self)
		overlay2 = grid(UInt8.self); overlay2Shape = grid(UInt8.self)
		lines = grid(UInt8.self)
		scenery = grid(Int32.self)
		icons = grid(Int32.self)
	}
}

extension ConfigStore {
	public enum WorldMapArchive {
		public static let archive = 23
	}

	/// rt4 `MapList.init`: every map of the `details` group, in file order.
	public func worldMaps() throws -> [WorldMapDefinition] {
		if let c = cache["worldmaps"] as? [WorldMapDefinition] { return c }
		let idx = try index(WorldMapArchive.archive)
		guard let g = idx.group(named: "details") else { return [] }
		let files = try self.files(archive: WorldMapArchive.archive, group: g)
		let maps = try files.keys.sorted().map { try WorldMapDefinition(files[$0]!) }
		cache["worldmaps"] = maps
		return maps
	}

	/// rt4 `Js5.fetchFile(file, group)` by name in the world map archive.
	func worldMapFile(_ file: String, group: String) -> [UInt8]? {
		guard let idx = try? index(WorldMapArchive.archive), let g = idx.group(named: group),
		      let f = idx.file(named: file, inGroup: g),
		      let files = try? self.files(archive: WorldMapArchive.archive, group: g) else { return nil }
		return files[f]
	}

	func worldMapHasGroup(_ group: String) -> Bool {
		((try? index(WorldMapArchive.archive))?.group(named: group)) != nil
	}

	/// rt4 `MapElementList.create`.
	func worldMapLabels(group: String) -> WorldMapLabels {
		var out = WorldMapLabels()
		guard let idx = try? index(WorldMapArchive.archive), let g = idx.group(named: group),
		      let files = try? self.files(archive: WorldMapArchive.archive, group: g) else { return out }
		for k in files.keys.sorted() {
			var p = Packet(files[k]!)
			guard let name = try? p.gjstr(), let flags = try? p.g1b(), let x = try? p.g2(), let z = try? p.g2(), let colour = try? p.g4() else { continue }
			out.names.append(name)
			out.flags.append(flags & 0xFF)
			out.x.append(Int(Int16(truncatingIfNeeded: x)))
			out.z.append(Int(Int16(truncatingIfNeeded: z)))
			out.colour.append(Int(colour))
		}
		return out
	}
}
