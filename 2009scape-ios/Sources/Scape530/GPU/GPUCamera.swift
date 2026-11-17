import Foundation

/// The six planes of a view frustum (inward-pointing normals), for box culling.
public struct GPUFrustum {
	/// `a, b, c, d` per plane: a point is inside when `a x + b y + c z + d >= 0`.
	public var planes: [(a: Float, b: Float, c: Float, d: Float)]

	/// Gribb/Hartmann extraction for a depth range of 0...1 (Metal).
	public init(viewProjection vp: Mat4) {
		func row(_ i: Int) -> [Float] { [vp[i, 0], vp[i, 1], vp[i, 2], vp[i, 3]] }
		let r0 = row(0), r1 = row(1), r2 = row(2), r3 = row(3)
		func plane(_ s: Float, _ r: [Float], _ w: [Float]) -> (a: Float, b: Float, c: Float, d: Float) {
			let p = (w[0] + s * r[0], w[1] + s * r[1], w[2] + s * r[2], w[3] + s * r[3])
			let len = max((p.0 * p.0 + p.1 * p.1 + p.2 * p.2).squareRoot(), 1e-9)
			return (p.0 / len, p.1 / len, p.2 / len, p.3 / len)
		}
		planes = [
			plane(1, r0, r3), plane(-1, r0, r3),   // left, right
			plane(1, r1, r3), plane(-1, r1, r3),   // bottom, top
			plane(1, r2, [0, 0, 0, 0]),            // near (clip z >= 0)
			plane(-1, r2, r3),                     // far (clip z <= w)
		]
	}

	/// False only when the box is entirely outside one plane.
	public func intersects(_ b: GPUBounds) -> Bool {
		guard !b.isEmpty else { return false }
		for p in planes {
			let x = p.a >= 0 ? b.maxX : b.minX
			let y = p.b >= 0 ? b.maxY : b.minY
			let z = p.c >= 0 ? b.maxZ : b.minZ
			if p.a * x + p.b * y + p.c * z + p.d < 0 { return false }
		}
		return true
	}
}

/// The software renderer's camera as GPU matrices. The projection reproduces rt4's fixed focal length
/// (`512` game pixels, eye at the middle of the viewport) so a point lands on the same pixel as in the
/// software frame, and overlays, picking and the minimap compass stay valid.
///
/// Inputs are rt4's: eye position in scene fine units (`y` negative is up), `pitch` / `yaw` in 0...2047
/// (rt4 `Camera`), and the viewport size in game pixels.
public struct GPUCamera: Equatable {
	public var x: Int, y: Int, z: Int
	public var pitch: Int, yaw: Int
	/// Viewport size in game pixels and projection centre (rt4 `Rasteriser.centerX/Y`).
	public var width: Int, height: Int
	public var centerX: Int, centerY: Int
	/// rt4 clips at 50 units and draws up to `GlobalConfig.VIEW_DISTANCE`.
	public var near: Float = 50
	public var far: Float = 128 * 60
	/// rt4 focal length in pixels (`<< 9`).
	public static let focal: Float = 512

	public init(x: Int, y: Int, z: Int, pitch: Int, yaw: Int, width: Int, height: Int, centerX: Int? = nil, centerY: Int? = nil) {
		self.x = x; self.y = y; self.z = z; self.pitch = pitch; self.yaw = yaw
		self.width = width; self.height = height
		self.centerX = centerX ?? width / 2
		self.centerY = centerY ?? height / 2
	}

	/// Camera position in GPU world space.
	public var position: (x: Float, y: Float, z: Float) { (Float(x), Float(-y), Float(z)) }

	/// GPU world space (x east, y up, z north) to rt4 camera space (x right, y down, z forward):
	/// rt4's `xr/yv/zv` of `Scene.draw`.
	public var view: Mat4 {
		let sy = Float(MathTables.sin[yaw & 2047]) / 65536, cy = Float(MathTables.cos[yaw & 2047]) / 65536
		let sp = Float(MathTables.sin[pitch & 2047]) / 65536, cp = Float(MathTables.cos[pitch & 2047]) / 65536
		// Rows act on p = (x - eyeX, y_rt4 - eyeY, z - eyeZ):
		//   xr = z sinYaw + x cosYaw;  zr = z cosYaw - x sinYaw
		//   yv = y cosPitch - zr sinPitch;  zv = y sinPitch + zr cosPitch
		let rotation = Mat4(rows: [
			[cy, 0, sy, 0],
			[sp * sy, cp, -sp * cy, 0],
			[-cp * sy, sp, cp * cy, 0],
			[0, 0, 0, 1],
		])
		// rt4 y = -gpu y, then subtract the eye.
		let flip = Mat4(rows: [[1, 0, 0, 0], [0, -1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]])
		return rotation * Mat4.translation(-Float(x), -Float(y), -Float(z)) * flip
	}

	/// Perspective with rt4's pixel centre. Metal conventions: clip z in 0...w, NDC y up.
	public var projection: Mat4 {
		let w = Float(width), h = Float(height)
		let f = Self.focal
		let a = far / (far - near)
		let b = -far * near / (far - near)
		return Mat4(rows: [
			[2 * f / w, 0, 2 * Float(centerX) / w - 1, 0],
			[0, -2 * f / h, 1 - 2 * Float(centerY) / h, 0],
			[0, 0, a, b],
			[0, 0, 1, 0],
		])
	}

	public var viewProjection: Mat4 { projection * view }
	public var frustum: GPUFrustum { GPUFrustum(viewProjection: viewProjection) }

	/// Pixel position (viewport game pixels, y down) of a GPU world point, with its view depth; nil when
	/// it is nearer than the near plane.
	public func project(x px: Float, y py: Float, z pz: Float) -> (x: Float, y: Float, depth: Float)? {
		let c = viewProjection.transform(px, py, pz)
		guard c.w >= near else { return nil }
		let nx = c.x / c.w, ny = c.y / c.w
		return ((nx + 1) * 0.5 * Float(width), (1 - ny) * 0.5 * Float(height), c.w)
	}

	/// Same for an rt4 scene position (fine units, `y` negative is up), the form `WorldView.project` takes.
	public func project(rt4 x: Int, y: Int, z: Int) -> (x: Float, y: Float, depth: Float)? {
		project(x: Float(x), y: Float(-y), z: Float(z))
	}
}

/// Distance fog like rt4's `FogManager.setFogParams`: linear from `start` to `end` view-space units.
public struct GPUFog: Equatable {
	public var start: Float
	public var end: Float
	/// 0xRRGGBB
	public var color: Int
	public var enabled: Bool

	public init(start: Float, end: Float, color: Int, enabled: Bool) {
		self.start = start; self.end = end; self.color = color; self.enabled = enabled
	}

	/// rt4: `VIEW_DISTANCE = tiles * 128`, fade `tiles / 28 * 256`; fog runs from `end - 2 fade` to `end - fade`.
	public static func rt4(tiles: Int, color: Int, enabled: Bool) -> GPUFog {
		let view = Float(tiles * 128)
		let fade = Float(tiles) / 28 * 256
		return GPUFog(start: max(50, view - fade * 2), end: view - fade, color: color, enabled: enabled)
	}

	/// Fog factor 0 (clear) ... 1 (fully fogged) at a view depth.
	public func factor(depth: Float) -> Float {
		guard enabled, end > start else { return 0 }
		return min(1, max(0, (depth - start) / (end - start)))
	}
}
