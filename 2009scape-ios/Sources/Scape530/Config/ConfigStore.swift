import Foundation

/// Loads config types from a cache, mirroring which archive/group each rt4
/// `*TypeList` reads. Groups are decompressed once and kept, files decoded
/// lazily and memoised.
public final class ConfigStore {
	public enum Archive {
		public static let configs = 2
		public static let enums = 17
		public static let locs = 16
		public static let npcs = 18
		public static let objs = 19
		public static let seqs = 20
		public static let spotAnims = 21
		public static let varbits = 22
	}

	public enum ConfigGroup {
		public static let flu = 1
		public static let idk = 3
		public static let flo = 4
		public static let bas = 32
	}

	let source: (Int, Int) -> [UInt8]?
	var indexes: [Int: Js5Index] = [:]
	var groups: [Int: [Int: [UInt8]]] = [:]
	var cache: [String: Any] = [:]
	/// The cache directory this store reads, when it was made with `init(disk:)`.
	private var diskDirectory: URL?

	/// `source(archive, group)` returns the packed container (e.g. `DiskCache.read`).
	public init(source: @escaping (Int, Int) -> [UInt8]?) {
		self.source = source
	}

	public convenience init(disk: DiskCache) {
		self.init(source: { disk.read(archive: $0, group: $1) })
		diskDirectory = disk.directory
	}

	/// A second store over the same cache files that shares no mutable state with this one (own memo
	/// tables and disk handles), so another thread can use it while this one keeps running. Nil for
	/// stores made from a custom `source`.
	public func isolatedCopy() -> ConfigStore? {
		guard let dir = diskDirectory, let disk = try? DiskCache(directory: dir) else { return nil }
		return ConfigStore(disk: disk)
	}

	public func index(_ archive: Int) throws -> Js5Index {
		if let i = indexes[archive] { return i }
		guard let raw = source(255, archive) else { throw Js5Container.Failure("no reference table for archive \(archive)") }
		let i = try Js5Index(container: Js5Container.stripVersion(raw))
		indexes[archive] = i
		return i
	}

	public func files(archive: Int, group: Int) throws -> [Int: [UInt8]] {
		let key = archive << 16 | group
		if let g = groups[key] { return g }
		let idx = try index(archive)
		guard idx.isValid(group: group), let raw = source(archive, group) else { return [:] }
		let files = try Js5Group.unpack(try Js5Container.decompress(Js5Container.stripVersion(raw)), index: idx, group: group)
		groups[key] = files
		return files
	}

	public func file(archive: Int, group: Int, file: Int) throws -> [UInt8]? {
		try files(archive: archive, group: group)[file]
	}

	func load<T: ConfigType>(_ t: T.Type, _ id: Int, archive: Int, group: Int, file: Int) throws -> T? {
		let key = "\(T.self)#\(id)"
		if let v = cache[key] as? T { return v }
		guard let data = try self.file(archive: archive, group: group, file: file) else { return nil }
		let v = try T.decode(id: id, data)
		cache[key] = v
		return v
	}

	public func obj(_ id: Int) throws -> ObjType? { let l = ObjType.location(of: id); return try load(ObjType.self, id, archive: Archive.objs, group: l.group, file: l.file) }
	public func npc(_ id: Int) throws -> NpcType? { let l = NpcType.location(of: id); return try load(NpcType.self, id, archive: Archive.npcs, group: l.group, file: l.file) }
	public func loc(_ id: Int) throws -> LocType? { let l = LocType.location(of: id); return try load(LocType.self, id, archive: Archive.locs, group: l.group, file: l.file) }
	public func seq(_ id: Int) throws -> SeqType? { let l = SeqType.location(of: id); return try load(SeqType.self, id, archive: Archive.seqs, group: l.group, file: l.file) }
	public func spotAnim(_ id: Int) throws -> SpotAnimType? { let l = SpotAnimType.location(of: id); return try load(SpotAnimType.self, id, archive: Archive.spotAnims, group: l.group, file: l.file) }
	public func varbit(_ id: Int) throws -> VarbitType? { let l = VarbitType.location(of: id); return try load(VarbitType.self, id, archive: Archive.varbits, group: l.group, file: l.file) }
	public func enumType(_ id: Int) throws -> EnumType? { let l = EnumType.location(of: id); return try load(EnumType.self, id, archive: Archive.enums, group: l.group, file: l.file) }
	public func flo(_ id: Int) throws -> FloType? { try load(FloType.self, id, archive: Archive.configs, group: ConfigGroup.flo, file: id) }
	public func flu(_ id: Int) throws -> FluType? { try load(FluType.self, id, archive: Archive.configs, group: ConfigGroup.flu, file: id) }
	public func idk(_ id: Int) throws -> IdkType? { try load(IdkType.self, id, archive: Archive.configs, group: ConfigGroup.idk, file: id) }
	public func bas(_ id: Int) throws -> BasType? { try load(BasType.self, id, archive: Archive.configs, group: ConfigGroup.bas, file: id) }
}
