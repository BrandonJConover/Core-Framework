/// Map squares from archive 5, by the group names rt4 builds in
/// `Protocol` REBUILD handling (`m{x}_{z}`, `l{x}_{z}`).
extension ConfigStore {
	public static let mapsArchive = 5

	public func mapSquare(x: Int, z: Int) throws -> MapSquare? {
		let key = "map#\(x)_\(z)"
		if let m = cache[key] as? MapSquare { return m }
		guard let g = try index(Self.mapsArchive).group(named: "m\(x)_\(z)"),
		      let raw = source(Self.mapsArchive, g) else { return nil }
		let m = try MapSquare(regionX: x, regionZ: z, data: try Js5Container.decompress(Js5Container.stripVersion(raw)))
		cache[key] = m
		return m
	}

	/// Locs need the region's XTEA key from REBUILD_NORMAL (all zero = plain).
	public func mapLocs(x: Int, z: Int, key: [Int32]) throws -> [MapLoc]? {
		guard let g = try index(Self.mapsArchive).group(named: "l\(x)_\(z)"),
		      let raw = source(Self.mapsArchive, g) else { return nil }
		var c = Js5Container.stripVersion(raw)
		if key.contains(where: { $0 != 0 }) { Xtea.decryptContainer(&c, key: key) }
		return try MapLoc.decode(try Js5Container.decompress(c))
	}
}
