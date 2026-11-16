/// rt4 `ShapedTile` (client!fg): a terrain tile whose overlay has one of the
/// 12 shapes (half, diagonal, corner...) rotated 0...3. The shape tables
/// below are verbatim from rt4.
public final class ShapedTile {
	/// rt4 `anIntArrayArray12`: vertex ids (1...16) used by each shape.
	static let vertexIds: [[Int]] = [
		[1, 3, 5, 7], [1, 3, 5, 7], [1, 3, 5, 7], [1, 3, 5, 7, 6], [1, 3, 5, 7, 6], [1, 3, 5, 7, 6],
		[1, 3, 5, 7, 6], [1, 3, 5, 7, 2, 6], [1, 3, 5, 7, 2, 8], [1, 3, 5, 7, 2, 8], [1, 3, 5, 7, 11, 12],
		[1, 3, 5, 7, 11, 12], [1, 3, 5, 7, 13, 14],
	]
	/// rt4 `anIntArrayArray13`: triangles as (0 = underlay / 1 = overlay, a, b, c).
	static let triangles: [[Int]] = [
		[0, 1, 2, 3, 0, 0, 1, 3], [1, 1, 2, 3, 1, 0, 1, 3], [0, 1, 2, 3, 1, 0, 1, 3],
		[0, 0, 1, 2, 0, 0, 2, 4, 1, 0, 4, 3], [0, 0, 1, 4, 0, 0, 4, 3, 1, 1, 2, 4],
		[0, 0, 4, 3, 1, 0, 1, 2, 1, 0, 2, 4], [0, 1, 2, 4, 1, 0, 1, 4, 1, 0, 4, 3],
		[0, 4, 1, 2, 0, 4, 2, 5, 1, 0, 4, 5, 1, 0, 5, 3], [0, 4, 1, 2, 0, 4, 2, 3, 0, 4, 3, 5, 1, 0, 4, 5],
		[0, 0, 4, 5, 1, 4, 1, 2, 1, 4, 2, 3, 1, 4, 3, 5],
		[0, 0, 1, 5, 0, 1, 4, 5, 0, 1, 2, 4, 1, 0, 5, 3, 1, 5, 4, 3, 1, 4, 2, 3],
		[1, 0, 1, 5, 1, 1, 4, 5, 1, 1, 2, 4, 0, 0, 5, 3, 0, 5, 4, 3, 0, 4, 2, 3],
		[1, 0, 5, 4, 1, 0, 1, 5, 0, 0, 4, 3, 0, 4, 5, 3, 0, 5, 2, 3, 0, 1, 2, 5],
	]

	public let shape: Int
	public let rotation: Int
	/// rt4 `anInt1969`, `anInt1968`: HSL16 minimap colours (underlay, overlay).
	public let underlayMinimapHsl: Int
	public let overlayMinimapHsl: Int
	/// rt4 `aBoolean113`: all four corners the same height.
	public var flat = true
	/// rt4 `anIntArray168/160/163`: vertex X, Y, Z in fine tile units (X/Z absolute in the scene).
	public let vertexX: [Int]
	public let vertexY: [Int]
	public let vertexZ: [Int]
	/// rt4 `anIntArray166/162/158`: triangle vertex indices.
	public let triA: [Int]
	public let triB: [Int]
	public let triC: [Int]
	/// rt4 `anIntArray167/172/171`: per-triangle HSL16 colours at A, B, C (12345678 = skip).
	public let colorA: [Int]
	public let colorB: [Int]
	public let colorC: [Int]
	/// rt4 `anIntArray161`: per-triangle texture id (-1 = none), nil when the tile has no texture.
	public var textures: [Int]?

	/// rt4 `ShapedTile(shape, rotation, texture, x, z, heights h0...h3, underlay colours u0...u3, overlay colours o0...o3, minimapUnderlay, minimapOverlay)`.
	/// Heights and colours are ordered (x,z), (x+1,z), (x+1,z+1), (x,z+1).
	public init(shape: Int, rotation: Int, texture: Int, x: Int, z: Int,
	            h: [Int], underlay u: [Int], overlay o: [Int], underlayMinimap: Int, overlayMinimap: Int) {
		if h[0] != h[1] || h[0] != h[2] || h[0] != h[3] { flat = false }
		self.shape = shape
		self.rotation = rotation
		underlayMinimapHsl = underlayMinimap
		overlayMinimapHsl = overlayMinimap
		let size = 128
		let half = size / 2, quarter = size / 4, threeQuarter = size * 3 / 4
		let ids = Self.vertexIds[shape]
		let n = ids.count
		var vx = [Int](repeating: 0, count: n), vy = vx, vz = vx
		var underlayColors = vx, overlayColors = vx
		let baseX = x * size, baseZ = z * size
		for i in 0..<n {
			var id = ids[i]
			if (id & 1) == 0 && id <= 8 { id = ((id - rotation - rotation - 1) & 7) + 1 }
			if id > 8 && id <= 12 { id = ((id - rotation - 9) & 3) + 9 }
			if id > 12 && id <= 16 { id = ((id - rotation - 13) & 3) + 13 }
			let px: Int, pz: Int, py: Int, pu: Int, po: Int
			switch id {
			case 1: px = baseX; pz = baseZ; py = h[0]; pu = u[0]; po = o[0]
			case 2: px = baseX + half; pz = baseZ; py = (h[0] + h[1]) >> 1; pu = (u[0] + u[1]) >> 1; po = (o[0] + o[1]) >> 1
			case 3: px = baseX + size; pz = baseZ; py = h[1]; pu = u[1]; po = o[1]
			case 4: px = baseX + size; pz = baseZ + half; py = (h[1] + h[2]) >> 1; pu = (u[1] + u[2]) >> 1; po = (o[1] + o[2]) >> 1
			case 5: px = baseX + size; pz = baseZ + size; py = h[2]; pu = u[2]; po = o[2]
			case 6: px = baseX + half; pz = baseZ + size; py = (h[2] + h[3]) >> 1; pu = (u[2] + u[3]) >> 1; po = (o[2] + o[3]) >> 1
			case 7: px = baseX; pz = baseZ + size; py = h[3]; pu = u[3]; po = o[3]
			case 8: px = baseX; pz = baseZ + half; py = (h[3] + h[0]) >> 1; pu = (u[3] + u[0]) >> 1; po = (o[3] + o[0]) >> 1
			case 9: px = baseX + half; pz = baseZ + quarter; py = (h[0] + h[1]) >> 1; pu = (u[0] + u[1]) >> 1; po = (o[0] + o[1]) >> 1
			case 10: px = baseX + threeQuarter; pz = baseZ + half; py = (h[1] + h[2]) >> 1; pu = (u[1] + u[2]) >> 1; po = (o[1] + o[2]) >> 1
			case 11: px = baseX + half; pz = baseZ + threeQuarter; py = (h[2] + h[3]) >> 1; pu = (u[2] + u[3]) >> 1; po = (o[2] + o[3]) >> 1
			case 12: px = baseX + quarter; pz = baseZ + half; py = (h[3] + h[0]) >> 1; pu = (u[3] + u[0]) >> 1; po = (o[3] + o[0]) >> 1
			case 13: px = baseX + quarter; pz = baseZ + quarter; py = h[0]; pu = u[0]; po = o[0]
			case 14: px = baseX + threeQuarter; pz = baseZ + quarter; py = h[1]; pu = u[1]; po = o[1]
			case 15: px = baseX + threeQuarter; pz = baseZ + threeQuarter; py = h[2]; pu = u[2]; po = o[2]
			default: px = baseX + quarter; pz = baseZ + threeQuarter; py = h[3]; pu = u[3]; po = o[3]
			}
			vx[i] = px; vy[i] = py; vz[i] = pz
			underlayColors[i] = pu; overlayColors[i] = po
		}
		vertexX = vx; vertexY = vy; vertexZ = vz

		let table = Self.triangles[shape]
		let count = table.count / 4
		var a = [Int](repeating: 0, count: count), b = a, c = a
		var ca = a, cb = a, cc = a
		var tex: [Int]? = texture != -1 ? [Int](repeating: 0, count: count) : nil
		var t = 0
		for i in 0..<count {
			let useOverlay = table[t]
			var va = table[t + 1], vb = table[t + 2], vc = table[t + 3]
			t += 4
			if va < 4 { va = (va - rotation) & 3 }
			if vb < 4 { vb = (vb - rotation) & 3 }
			if vc < 4 { vc = (vc - rotation) & 3 }
			a[i] = va; b[i] = vb; c[i] = vc
			if useOverlay == 0 {
				ca[i] = underlayColors[va]; cb[i] = underlayColors[vb]; cc[i] = underlayColors[vc]
				tex?[i] = -1
			} else {
				ca[i] = overlayColors[va]; cb[i] = overlayColors[vb]; cc[i] = overlayColors[vc]
				tex?[i] = texture
			}
		}
		triA = a; triB = b; triC = c
		colorA = ca; colorB = cb; colorC = cc
		textures = tex
	}
}
