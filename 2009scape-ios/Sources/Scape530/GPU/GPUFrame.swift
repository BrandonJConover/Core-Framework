import Foundation

/// Directional light of rt4's GL path (`FogManager.initDefaults`): not used by the tier 1 shader (colours
/// are baked), carried so the HD tiers can light `GPUVertex.base` with `GPUVertex.n*` from the same source.
public struct GPULighting: Equatable {
	/// Unit vector pointing towards the light in GPU world space (y up). rt4: `(-50, -60, -50)` in its y-down space.
	public var direction: (x: Float, y: Float, z: Float) = {
		let x: Float = -50, y: Float = 60, z: Float = -50
		let l = (x * x + y * y + z * z).squareRoot()
		return (x / l, y / l, z / l)
	}()
	/// rt4 `setLightParams` defaults.
	public var ambient: Float = 1.1523438
	public var diffuse: Float = 0.69921875
	public var color = 0xFFFFFF
	public init() {}
	public static func == (a: GPULighting, b: GPULighting) -> Bool {
		a.direction == b.direction && a.ambient == b.ambient && a.diffuse == b.diffuse && a.color == b.color
	}
}

/// Everything the Metal renderer needs for one frame, produced by `WorldView` on the game thread.
public struct GPUFrame {
	public var camera: GPUCamera
	/// The 3D viewport in game pixels (raster coordinates).
	public var viewport: (x: Int, y: Int, w: Int, h: Int)
	public var settings: GPURenderSettings
	public var fog: GPUFog
	public var lighting = GPULighting()
	/// Static chunks and ranges that survived culling.
	public var list: GPUDrawList
	/// Per-frame geometry in world space: actors, animated locs, graphics, projectiles.
	public var dynamic: GPUMeshStream
	/// Texture ids the frame uses (static chunks in the list plus the dynamic geometry).
	public var usedTextures: Set<Int>
	/// Rasteriser gamma (a change invalidates cached textures and palette).
	public var brightness: Float
	/// Incremented whenever `WorldView` adopts a new scene; chunk ids restart with it.
	public var sceneGeneration: Int
	/// Chunks of the scene still to be baked (the first frames after a region load).
	public var pendingChunks = 0

	public init(camera: GPUCamera, viewport: (x: Int, y: Int, w: Int, h: Int), settings: GPURenderSettings, fog: GPUFog,
	            list: GPUDrawList, dynamic: GPUMeshStream, usedTextures: Set<Int>, brightness: Float, sceneGeneration: Int) {
		self.camera = camera; self.viewport = viewport; self.settings = settings; self.fog = fog
		self.list = list; self.dynamic = dynamic; self.usedTextures = usedTextures; self.brightness = brightness
		self.sceneGeneration = sceneGeneration
	}

	public var clearColor: (r: Float, g: Float, b: Float) {
		let c = settings.fogColor
		return (Float((c >> 16) & 0xFF) / 255, Float((c >> 8) & 0xFF) / 255, Float(c & 0xFF) / 255)
	}

	/// Number of floats in `uniforms`.
	public static let uniformCount = 36

	/// The shader's uniform block as floats (matches `SceneUniforms` in the Metal source):
	/// `viewProjection` (16, column-major), `eye` (4), `fogColor` (4), `fogParams` (4: start, end, enabled, 0),
	/// `lightDirection` (4), `lightParams` (4: ambient, diffuse, 0, 0).
	public var uniforms: [Float] {
		var u = camera.viewProjection.m
		let e = camera.position
		u += [e.x, e.y, e.z, 1]
		let f = fog.color
		u += [Float((f >> 16) & 0xFF) / 255, Float((f >> 8) & 0xFF) / 255, Float(f & 0xFF) / 255, 1]
		u += [fog.start, fog.end, fog.enabled ? 1 : 0, 0]
		u += [lighting.direction.x, lighting.direction.y, lighting.direction.z, 0]
		u += [lighting.ambient, lighting.diffuse, 0, 0]
		return u
	}
}
