import Foundation

/// One vertex of the GPU scene renderer. Platform independent (no Metal import): the app uploads arrays
/// of these verbatim and describes the layout with the offsets in `GPUVertex.layout`.
///
/// World space is rt4's scene space with Y flipped to point up: `x` east, `y` up (`-rt4 y`), `z` north,
/// 128 units per tile. Meshes are plain triangle lists (three vertices per triangle, no index buffer),
/// wound counter-clockwise as seen on screen for faces the software rasteriser would draw (`cross > 0`),
/// so the GPU culls back faces with `frontFacing = .counterClockwise`.
public struct GPUVertex: Equatable {
	public var x: Float, y: Float, z: Float
	/// Unit normal in the same space (kept for the lighting tiers; tier 1 shades with `color`).
	public var nx: Float, ny: Float, nz: Float
	/// Texture coordinates; 1.0 is one repeat of the texture.
	public var u: Float, v: Float
	/// The software renderer's lit colour as RGBA8 (R in the lowest byte); alpha 255 is opaque.
	/// For textured faces this is a grey shade (lightness / 128) that multiplies the texel.
	public var color: UInt32
	/// The unlit base colour (RGBA8): the model's own face colour before lighting, white when textured.
	/// HD lighting tiers shade this with `nx/ny/nz` instead of using `color`.
	public var base: UInt32
	/// 0 for none, else `textureId + 1` (index into the material table).
	public var material: UInt16
	/// `GPUVertex.flagDecal` etc.
	public var flags: UInt16

	/// Ground-hugging geometry that should win depth ties against the terrain.
	public static let flagDecal: UInt16 = 1
	/// Terrain (not a model): HD tiers blend ground textures and shadows only here.
	public static let flagTerrain: UInt16 = 2

	public init(x: Float, y: Float, z: Float, nx: Float, ny: Float, nz: Float, u: Float, v: Float,
	            color: UInt32, base: UInt32, material: UInt16, flags: UInt16) {
		self.x = x; self.y = y; self.z = z; self.nx = nx; self.ny = ny; self.nz = nz
		self.u = u; self.v = v; self.color = color; self.base = base; self.material = material; self.flags = flags
	}

	/// Byte layout for a vertex descriptor.
	public enum layout {
		public static let position = 0       // 3 x Float
		public static let normal = 12        // 3 x Float
		public static let uv = 24            // 2 x Float
		public static let color = 32         // 4 x UInt8 normalised
		public static let base = 36          // 4 x UInt8 normalised
		public static let materialFlags = 40 // 2 x UInt16
		public static var stride: Int { MemoryLayout<GPUVertex>.stride }
	}

	@inline(__always) public static func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) -> UInt32 {
		UInt32(truncatingIfNeeded: r & 0xFF) | UInt32(truncatingIfNeeded: g & 0xFF) << 8 | UInt32(truncatingIfNeeded: b & 0xFF) << 16 | UInt32(truncatingIfNeeded: a & 0xFF) << 24
	}
	/// `0xRRGGBB` to RGBA8.
	@inline(__always) public static func rgba(rgb: Int, alpha: Int = 255) -> UInt32 {
		rgba((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF, alpha)
	}
	public var r: Int { Int(color & 0xFF) }
	public var g: Int { Int((color >> 8) & 0xFF) }
	public var b: Int { Int((color >> 16) & 0xFF) }
	public var a: Int { Int((color >> 24) & 0xFF) }
}

/// Axis-aligned box in GPU world space.
public struct GPUBounds: Equatable {
	public var minX = Float.greatestFiniteMagnitude, minY = Float.greatestFiniteMagnitude, minZ = Float.greatestFiniteMagnitude
	public var maxX = -Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude
	public init() {}
	public init(minX: Float, minY: Float, minZ: Float, maxX: Float, maxY: Float, maxZ: Float) {
		self.minX = minX; self.minY = minY; self.minZ = minZ; self.maxX = maxX; self.maxY = maxY; self.maxZ = maxZ
	}
	public var isEmpty: Bool { minX > maxX }
	public mutating func add(_ x: Float, _ y: Float, _ z: Float) {
		minX = min(minX, x); maxX = max(maxX, x)
		minY = min(minY, y); maxY = max(maxY, y)
		minZ = min(minZ, z); maxZ = max(maxZ, z)
	}
	public mutating func add(_ v: GPUVertex) { add(v.x, v.y, v.z) }
	public mutating func add(_ o: GPUBounds) {
		guard !o.isEmpty else { return }
		add(o.minX, o.minY, o.minZ); add(o.maxX, o.maxY, o.maxZ)
	}
}

/// Column-major 4x4 matrix (the layout Metal's `float4x4` expects: `m[column * 4 + row]`).
public struct Mat4: Equatable {
	public var m: [Float]
	public init(_ m: [Float]) { precondition(m.count == 16); self.m = m }
	public static let identity = Mat4([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

	@inline(__always) public subscript(row: Int, col: Int) -> Float {
		get { m[col * 4 + row] }
		set { m[col * 4 + row] = newValue }
	}

	public static func * (a: Mat4, b: Mat4) -> Mat4 {
		var r = [Float](repeating: 0, count: 16)
		for c in 0..<4 {
			for row in 0..<4 {
				var s: Float = 0
				for k in 0..<4 { s += a.m[k * 4 + row] * b.m[c * 4 + k] }
				r[c * 4 + row] = s
			}
		}
		return Mat4(r)
	}

	/// Row-major construction (reads like the maths).
	public init(rows: [[Float]]) {
		var r = [Float](repeating: 0, count: 16)
		for row in 0..<4 { for c in 0..<4 { r[c * 4 + row] = rows[row][c] } }
		self.init(r)
	}

	public static func translation(_ x: Float, _ y: Float, _ z: Float) -> Mat4 {
		Mat4(rows: [[1, 0, 0, x], [0, 1, 0, y], [0, 0, 1, z], [0, 0, 0, 1]])
	}

	/// Transforms a point (w = 1), returning clip coordinates.
	@inline(__always) public func transform(_ x: Float, _ y: Float, _ z: Float) -> (x: Float, y: Float, z: Float, w: Float) {
		(m[0] * x + m[4] * y + m[8] * z + m[12], m[1] * x + m[5] * y + m[9] * z + m[13],
		 m[2] * x + m[6] * y + m[10] * z + m[14], m[3] * x + m[7] * y + m[11] * z + m[15])
	}
}

/// Settings of the GPU renderer (tier 1). `nil` on `WorldView.gpuSettings` means the software renderer.
public struct GPURenderSettings: Equatable {
	/// How far the scene is drawn, in tiles from the camera. The software renderer uses 25; rt4's own GL
	/// renderer defaults to 28 (this fork's `GlobalConfig.TILE_DISTANCE` is 56). A loaded scene is only
	/// 104 tiles wide, so values past roughly 70 add nothing.
	public var drawDistanceTiles = 56
	public static let drawDistanceRange = 25...100
	/// MSAA sample count (1, 2 or 4; the app clamps to what the device supports).
	public var msaaSamples = 4
	/// Anisotropic filtering level for textures (1...16).
	public var anisotropy = 8
	/// Distance fog on or off (rt4 `Preferences.fogEnabled`).
	public var fogEnabled = true
	/// 0xRRGGBB; rt4 `FogManager.defaulFogColorRgb`.
	public var fogColor = 13156520
	public var texturesEnabled = true

	public init() {}

	public var clampedDrawDistance: Int { min(max(drawDistanceTiles, Self.drawDistanceRange.lowerBound), Self.drawDistanceRange.upperBound) }
}

/// A vertex-colour palette: rt4 HSL16 to RGB at a given brightness (the same table as the software
/// rasteriser, built by it).
public final class GPUPalette {
	public let brightness: Float
	/// 0xRRGGBB per HSL16 value.
	public let rgb: [UInt32]

	public init(brightness: Float) {
		self.brightness = brightness
		let r = Rasteriser3D(width: 1, height: 1)
		r.setBrightness(brightness, jitter: false)
		rgb = r.palette.map { UInt32(truncatingIfNeeded: $0) & 0xFFFFFF }
	}

	/// RGBA8 (opaque) of an HSL16 colour (the high lightness bits of lit gouraud values are ignored).
	@inline(__always) public func rgba(_ hsl: Int, alpha: Int = 255) -> UInt32 {
		let c = rgb[hsl & 0xFFFF]
		return GPUVertex.rgba(Int((c >> 16) & 0xFF), Int((c >> 8) & 0xFF), Int(c & 0xFF), alpha)
	}

	/// Grey RGBA8 shade for textured faces: the software rasteriser multiplies texels by `lightness / 128`.
	@inline(__always) public static func shade(_ lightness: Int, alpha: Int = 255) -> UInt32 {
		let g = min(255, max(0, lightness & 0x7F) * 255 / 128)
		return GPUVertex.rgba(g, g, g, alpha)
	}
}
