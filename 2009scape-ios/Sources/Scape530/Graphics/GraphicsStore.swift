/// Sprite and font access on top of `ConfigStore`'s group cache.
/// rt4: sprites are archive 8 (one group per sprite sheet, looked up by name),
/// font metrics are archive 13 under the same group id as the glyph sheet.
extension ConfigStore {
	public enum GraphicsArchive {
		public static let interfaces = 3
		public static let sprites = 8
		public static let fontMetrics = 13
	}

	public func sprite(_ id: Int) throws -> SpriteSheet? {
		let key = "sprite#\(id)"
		if let s = cache[key] as? SpriteSheet { return s }
		guard let data = try files(archive: GraphicsArchive.sprites, group: id)[0] else { return nil }
		let s = try SpriteSheet(data)
		cache[key] = s
		return s
	}

	public func spriteId(named name: String) throws -> Int? {
		try index(GraphicsArchive.sprites).group(named: name)
	}

	public func sprite(named name: String) throws -> SpriteSheet? {
		guard let id = try spriteId(named: name) else { return nil }
		return try sprite(id)
	}

	/// Fonts by sprite group id (interface components reference fonts this way).
	public func font(_ id: Int) throws -> BitmapFont? {
		let key = "font#\(id)"
		if let f = cache[key] as? BitmapFont { return f }
		guard let sheet = try sprite(id), let metrics = try files(archive: GraphicsArchive.fontMetrics, group: id)[0] else { return nil }
		let f = BitmapFont(metrics: metrics, glyphs: sheet)
		cache[key] = f
		return f
	}

	public func font(named name: String) throws -> BitmapFont? {
		guard let id = try spriteId(named: name) else { return nil }
		return try font(id)
	}
}
