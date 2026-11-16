extension ConfigStore {
	/// Archive 7 holds one group per model (group = model id, file 0).
	public static let modelsArchive = 7

	/// Decoded model (rt4 `RawModel.create(Js5, id)`), memoised. Callers that
	/// mutate (recolour, merge, rotate) must `copy()` first; the cached
	/// instance is shared.
	public func rawModel(_ id: Int) throws -> RawModel? {
		let key = "RawModel#\(id)"
		if let m = cache[key] as? RawModel { return m }
		guard let data = try file(archive: ConfigStore.modelsArchive, group: id, file: 0) else { return nil }
		let m = try RawModel(data: data)
		cache[key] = m
		return m
	}
}
