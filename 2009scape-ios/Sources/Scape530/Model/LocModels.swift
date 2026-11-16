import Foundation

/// Terrain context for hillskewed locs (rt4 `LocType.method3428` args):
/// the tile height grid(s), the loc's offset in scene units, and the base
/// height of its tile.
public struct LocTerrain {
	public var heights: [[Int]]
	/// Secondary (bridge / upper level) grid used by hillskew types 4 and 5.
	public var upper: [[Int]]?
	public var x: Int
	public var baseY: Int
	public var z: Int

	public init(heights: [[Int]], upper: [[Int]]? = nil, x: Int, baseY: Int, z: Int) {
		self.heights = heights; self.upper = upper; self.x = x; self.baseY = baseY; self.z = z
	}
}

/// Builds and caches scenery models, the software path of rt4 `LocType`
/// (`getRawModel`, `method3428` for static locs, `method3429` for animated
/// ones) plus its model caches (`LocTypeList.aClass99_24/14/36`).
///
/// Returned `SoftwareModel`s may be shared with the cache: copy before
/// mutating. Terrain fitting returns a copy, so the cache stays intact.
public final class LocModelBuilder {
	public let store: ConfigStore
	/// Replaces `Rasteriser.textureProvider.method3236` (is this texture usable?).
	public var textureAvailable: (Int) -> Bool

	/// rt4 `aClass99_24` for raw models: keyed by model id (+65536 when mirrored).
	private var rawCache: [Int: RawModel] = [:]
	/// rt4 `aClass99_14`: lit models for static locs.
	private var staticCache: [Int: SoftwareModel] = [:]
	/// rt4 `aClass99_36`: lit models for animated locs.
	private var animatedCache: [Int: SoftwareModel] = [:]

	public init(store: ConfigStore, textureAvailable: @escaping (Int) -> Bool = { _ in true }) {
		self.store = store
		self.textureAvailable = textureAvailable
	}

	public func clearCaches() {
		rawCache = [:]; staticCache = [:]; animatedCache = [:]
	}

	/// Raw (cached, shared) model `id`, optionally mirrored (rt4 `getRawModel` inner loop).
	private func baseModel(_ id: Int, mirrored: Bool) throws -> RawModel? {
		let key = mirrored ? id + 65536 : id
		if let m = rawCache[key] { return m }
		guard let raw = try store.rawModel(id & 0xFFFF) else { return nil }
		var m = raw
		if mirrored {
			m = raw.copy()
			m.mirrorZ()
		}
		rawCache[key] = m
		return m
	}

	/// rt4 `LocType.getRawModel(rotation, shape)`: the unlit model for a loc
	/// of the given shape and rotation (0...3, +4 for the "rotated half-turn"
	/// variants), with merge, mirror, rotation, recolour, retexture, resize and
	/// offset applied. Always a fresh instance, or nil if the loc has no model
	/// for that shape.
	public func rawModel(for loc: LocType, shape: Int, rotation: Int) throws -> RawModel? {
		var mirrored = loc.mirror
		if shape == 2 && rotation > 3 { mirrored.toggle() }
		var source: RawModel
		if let shapes = loc.shapes {
			guard let models = loc.models, let index = shapes.firstIndex(of: shape), index < models.count,
				let m = try baseModel(models[index], mirrored: mirrored) else { return nil }
			source = m
		} else {
			guard shape == 10, let models = loc.models, !models.isEmpty else { return nil }
			var parts: [RawModel?] = []
			for id in models {
				guard let m = try baseModel(id, mirrored: mirrored) else { return nil }
				parts.append(m)
			}
			source = parts.count > 1 ? RawModel(merging: parts, count: parts.count) : parts[0]!
		}

		let resized = loc.resize[0] != 128 || loc.resize[1] != 128 || loc.resize[2] != 128
		let moved = loc.offset[0] != 0 || loc.offset[1] != 0 || loc.offset[2] != 0
		let m = source.copy()
		if shape == 4 && rotation > 3 {
			m.rotateY45()
			m.translate(45, 0, -45)
		}
		switch rotation & 3 {
		case 1: m.rotateY90()
		case 2: m.rotateY180()
		case 3: m.rotateY270()
		default: break
		}
		// rt4 `recol_p` (recolour from the client palette) is not modelled: it
		// stays at the all-zero default palette in rt4 unless a script sets it.
		for (from, to) in loc.recolours.sorted(by: { $0.key < $1.key }) { m.recolor(from, to) }
		for (from, to) in loc.retextures.sorted(by: { $0.key < $1.key }) { m.retexture(from, to) }
		if resized { m.resize(loc.resize[0], loc.resize[1], loc.resize[2]) }
		if moved { m.translate(loc.offset[0], loc.offset[1], loc.offset[2]) }
		return m
	}

	private func cacheKey(_ loc: LocType, shape: Int, rotation: Int) -> Int {
		let base = (loc.id << 10) + rotation
		return loc.shapes == nil ? base : base + (shape << 3)
	}

	private func lit(_ raw: RawModel, _ loc: LocType) -> SoftwareModel {
		SoftwareModel(raw, ambient: loc.ambient + 64, contrast: loc.contrast * 5 + 768, x: -50, y: -10, z: -50, textureAvailable: textureAvailable)
	}

	/// rt4 `LocType.method3428` (software path): the lit model for a static
	/// scenery object, fitted to the terrain when the loc has a hillskew type
	/// and `terrain` is given. Nil when the loc has no model for `shape`.
	public func model(for loc: LocType, shape: Int, rotation: Int, terrain: LocTerrain? = nil) throws -> SoftwareModel? {
		let key = cacheKey(loc, shape: shape, rotation: rotation)
		var model = staticCache[key]
		if model == nil {
			guard let raw = try rawModel(for: loc, shape: shape, rotation: rotation) else { return nil }
			raw.resetBones()
			if shape == 10 && rotation > 3 { raw.rotateY45() }
			model = lit(raw, loc)
			staticCache[key] = model
		}
		guard let m = model else { return nil }
		return fit(m, loc, terrain)
	}

	/// rt4 `LocType.method3429` (software path, without the `SeqType` frame
	/// application): the lit base model for an animated loc. Unlike the static
	/// path the half-turn variant is applied to the lit model.
	public func animatedBase(for loc: LocType, shape: Int, rotation: Int, terrain: LocTerrain? = nil) throws -> SoftwareModel? {
		let key = cacheKey(loc, shape: shape, rotation: rotation)
		var model = animatedCache[key]
		if model == nil {
			guard let raw = try rawModel(for: loc, shape: shape, rotation: rotation) else { return nil }
			model = lit(raw, loc)
			animatedCache[key] = model
		}
		guard var m = model else { return nil }
		if shape == 10 && rotation > 3 {
			m = m.copy()
			m.rotateY(256)
		}
		return fit(m, loc, terrain)
	}

	private func fit(_ m: SoftwareModel, _ loc: LocType, _ terrain: LocTerrain?) -> SoftwareModel {
		guard loc.hillskewType != 0, let t = terrain else { return m }
		return m.fitToTerrain(type: loc.hillskewType, amount: loc.hillskewAmount, heights: t.heights, upper: t.upper, x: t.x, baseY: t.baseY, z: t.z)
	}
}
