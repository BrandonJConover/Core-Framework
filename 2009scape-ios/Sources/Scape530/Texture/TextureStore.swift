import Foundation

/// Procedural textures for the software rasteriser.
///
/// rt4 builds `Js5GlTextureProvider(archive 9, archive 26, archive 8, ...)`:
/// archive 9 holds one texture definition per group (file 0), archive 26 group 0
/// holds per-texture metadata (flags, average colours), archive 8 holds the
/// sprites that sprite ops sample. `texels` mirrors `GlTexture.method4295`
/// (the software-path pixel builder): 128x128 (64x64 in low detail) 0xRRGGBB
/// texels, brightness-adjusted, with the optional 3x3 blur.
public final class TextureStore: TextureSource {
	public enum Archive {
		public static let textures = 9
		public static let metadata = 26
	}

	/// Per-texture metadata from archive 26 (rt4 `Js5GlTextureProvider` arrays).
	public struct Meta {
		public var defined = false
		public var flag90 = false
		/// rt4 `aBooleanArray91`: no transparent texels.
		public var opaque = false
		/// rt4 `aBooleanArray89`: always 64x64.
		public var forceLowDetail = false
		public var flag93 = false
		public var b59 = 0, b60 = 0, b61 = 0, b62 = 0
		/// HSL16 average colour.
		public var averageColor = 0
	}

	public struct SpritePixels {
		public let width: Int
		public let height: Int
		/// 0xRRGGBB (0 = transparent), canvas-sized.
		public let pixels: [Int]
	}

	let config: ConfigStore
	public var lowDetail: Bool { didSet { if oldValue != lowDetail { lock.lock(); cache = [:]; graphs = [:]; lock.unlock() } } }
	public private(set) var meta: [Meta] = []
	/// rt4 `Texture.brightnessMap` / `brightness`: shared mutable state, as in rt4.
	var brightnessMap = [Int](repeating: 0, count: 256)
	var brightness = -1.0
	private var graphs: [Int: TextureGraph] = [:]
	private var sprites: [Int: SpritePixels?] = [:]
	private var cache: [CacheKey: [Int32]] = [:]
	private let lock = NSRecursiveLock()
	/// Texture ids that failed to decode or generate, with the reason.
	public private(set) var failures: [Int: String] = [:]

	struct CacheKey: Hashable { let id: Int; let brightness: UInt32 }

	public init(config: ConfigStore, lowDetail: Bool = false) throws {
		self.config = config
		self.lowDetail = lowDetail
		guard let raw = try config.file(archive: Archive.metadata, group: 0, file: 0) else {
			throw TextureError("texture metadata (archive 26) missing")
		}
		var p = Packet(raw)
		let n = try p.g2()
		var m = [Meta](repeating: Meta(), count: n)
		for i in 0..<n { m[i].defined = try p.g1() == 1 }
		for i in 0..<n where m[i].defined { m[i].flag90 = try p.g1() == 1 }
		for i in 0..<n where m[i].defined { m[i].opaque = try p.g1() == 1 }
		for i in 0..<n where m[i].defined { m[i].forceLowDetail = try p.g1() == 1 }
		for i in 0..<n where m[i].defined { m[i].flag93 = try p.g1() == 1 }
		for i in 0..<n where m[i].defined { m[i].b59 = try p.g1b() & 0xFF }
		for i in 0..<n where m[i].defined { m[i].b60 = try p.g1b() & 0xFF }
		for i in 0..<n where m[i].defined { m[i].b62 = try p.g1b() & 0xFF }
		for i in 0..<n where m[i].defined { m[i].b61 = try p.g1b() & 0xFF }
		for i in 0..<n where m[i].defined { m[i].averageColor = try p.g2() }
		meta = m
	}

	/// Texture ids that have a definition in archive 9.
	public var definedIds: [Int] {
		let groups = (try? config.index(Archive.textures))?.groupIds ?? []
		return groups.filter { $0 < meta.count }.sorted()
	}

	// MARK: rt4 Texture statics

	/// rt4 `Texture.setBrightness`.
	func setBrightness(_ b: Double) {
		if brightness == b { return }
		for i in 0..<256 {
			let v = jint(pow(Double(i) / 255.0, b) * 255.0)
			brightnessMap[i] = v > 255 ? 255 : v
		}
		brightness = b
	}

	// MARK: sprites for sprite ops

	/// rt4 `SpriteLoader.loadSoftwareSpriteAutoDetect` + `trim`: the first frame on a full canvas.
	func spritePixels(_ id: Int) -> SpritePixels? {
		lock.lock(); defer { lock.unlock() }
		if let s = sprites[id] { return s }
		var result: SpritePixels?
		if let sheet = try? config.sprite(id), let f = sheet.frames.first {
			var px = [Int](repeating: 0, count: f.width * f.height)
			for y in 0..<f.innerHeight {
				for x in 0..<f.innerWidth {
					let dx = x + f.xOffset, dy = y + f.yOffset
					guard dx < f.width, dy < f.height else { continue }
					px[dy * f.width + dx] = Int(f.palette[Int(f.indices[y * f.innerWidth + x])] & 0xFFFFFF)
				}
			}
			result = SpritePixels(width: f.width, height: f.height, pixels: px)
		}
		sprites[id] = result
		return result
	}

	// MARK: generation

	func graph(_ id: Int) throws -> TextureGraph? {
		if let g = graphs[id] { return g }
		guard let data = try config.file(archive: Archive.textures, group: id, file: 0) else { return nil }
		let g = try TextureGraph(data)
		graphs[id] = g
		return g
	}

	private func size(_ id: Int) -> Int { isLowDetail(id) ? 64 : 128 }

	/// Build texels for `id`, throwing on a decode or generation failure.
	/// rt4 `GlTexture.method4295`; returns nil only when the texture has no definition.
	public func generate(_ id: Int, brightness b: Float) throws -> [Int32]? {
		lock.lock(); defer { lock.unlock() }
		let key = CacheKey(id: id, brightness: b.bitPattern)
		if let c = cache[key] { return c }
		guard id >= 0, id < meta.count, let g = try graph(id) else { return nil }
		let s = size(id)
		var px = g.render(store: self, size: s, brightness: Double(b), flip: true)
		if g.blur { px = TextureGraph.blur3x3(px, size: s) }
		cache[key] = px
		return px
	}

	/// rt4 `GlTexture.method4297`: used when one texture reads another (brightness 1.0, no flip).
	func nestedPixels(_ id: Int) -> [Int]? {
		guard id >= 0, id < meta.count, let g = try? graph(id) else { return nil }
		return g.render(store: self, size: size(id), brightness: 1.0, flip: false).map { Int($0) }
	}

	// MARK: TextureSource

	public func texels(_ id: Int, brightness: Float) -> [Int32]? {
		do { return try generate(id, brightness: brightness) } catch {
			lock.lock(); failures[id] = "\(error)"; lock.unlock()
			return nil
		}
	}

	/// rt4 `getAverageColor`.
	public func averageColor(_ id: Int) -> Int { id >= 0 && id < meta.count ? meta[id].averageColor : 0 }
	/// rt4 `isLowDetail`.
	public func isLowDetail(_ id: Int) -> Bool { lowDetail || (id >= 0 && id < meta.count && meta[id].forceLowDetail) }
	/// rt4 `isOpaque`.
	public func isOpaque(_ id: Int) -> Bool { id >= 0 && id < meta.count && meta[id].opaque }
}
