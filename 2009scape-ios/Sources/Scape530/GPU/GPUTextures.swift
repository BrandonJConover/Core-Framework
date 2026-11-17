import Foundation

/// One entry of the material table, indexed by `GPUVertex.material` (`textureId + 1`; entry 0 is "no texture").
/// 16 bytes, uploaded as a buffer the fragment shader reads. Later tiers extend it (normal / specular maps,
/// water, scrolling) without touching the vertex format.
public struct GPUMaterial: Equatable {
	/// Layer in the texture array, or -1 while the texture is not uploaded (the shader then uses `average`).
	public var layer: Int32 = -1
	/// `flagCutout`: has fully transparent texels (alpha-tested / alpha-to-coverage).
	public var flags: UInt32 = 0
	/// The texture's average colour as RGBA8, the stand-in until it is uploaded.
	public var average: UInt32 = 0xFF80_8080
	public var reserved: UInt32 = 0
	public static let flagCutout: UInt32 = 1
	public init() {}
}

/// Textures for the GPU renderer: the same procedural textures the software rasteriser samples
/// (`TextureStore.texels`, at the same gamma), as 128 x 128 RGBA8 layers for a texture array. Layers are
/// produced on demand; the app uploads the ones the visible chunks use and fills `GPUMaterial.layer`.
public final class GPUTextureSet {
	/// Layer edge in texels (rt4's high detail size; 64 x 64 textures are doubled).
	public static let size = 128
	public let store: TextureStore
	public let brightness: Float
	let palette: GPUPalette
	/// Texture ids with a definition, in layer order.
	public let ids: [Int]
	public let layerOf: [Int: Int]

	public init(store: TextureStore, brightness: Float, palette: GPUPalette) {
		self.store = store
		self.brightness = brightness
		self.palette = palette
		ids = store.definedIds
		var m: [Int: Int] = [:]
		for (i, id) in ids.enumerated() { m[id] = i }
		layerOf = m
	}

	public var layerCount: Int { ids.count }

	/// RGBA8 rows (`size * size * 4` bytes) for texture `id`: row = texture v, column = u. A texel of 0 is
	/// transparent (as in the software rasteriser) unless the texture is flagged opaque. Nil when it cannot be generated.
	public func rgba(id: Int) -> [UInt8]? {
		guard let texels = store.texels(id, brightness: brightness) else { return nil }
		let n = Self.size
		let src = Int(Double(texels.count).squareRoot().rounded())
		guard src > 0, src * src == texels.count else { return nil }
		let opaque = store.isOpaque(id)
		var out = [UInt8](repeating: 0, count: n * n * 4)
		for y in 0..<n {
			for x in 0..<n {
				let t = Int(texels[(y * src / n) * src + (x * src / n)]) & 0xFFFFFF
				let o = (y * n + x) * 4
				out[o] = UInt8((t >> 16) & 0xFF)
				out[o + 1] = UInt8((t >> 8) & 0xFF)
				out[o + 2] = UInt8(t & 0xFF)
				out[o + 3] = (t == 0 && !opaque) ? 0 : 255
			}
		}
		return out
	}

	/// The material table for texture ids `0..<store.meta.count`: entry `id + 1`, with `layer` set for ids in
	/// `uploaded` (id to layer) and the average colour as fallback.
	public func materials(uploaded: [Int: Int] = [:]) -> [GPUMaterial] {
		var table = [GPUMaterial](repeating: GPUMaterial(), count: store.meta.count + 1)
		for id in 0..<store.meta.count {
			var m = GPUMaterial()
			m.layer = Int32(uploaded[id] ?? -1)
			m.average = palette.rgba(store.averageColor(id))
			if !store.isOpaque(id) { m.flags |= GPUMaterial.flagCutout }
			table[id + 1] = m
		}
		return table
	}
}
