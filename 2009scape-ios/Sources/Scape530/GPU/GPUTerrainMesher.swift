import Foundation

/// Terrain tiles of a `Scene` as GPU triangles, taking the software scene's decoded tiles as they are:
/// per-corner lit HSL16 colours (underlay blend and shadows already applied by `Scene.loadMapSquares`),
/// overlay shapes (`ShapedTile`) and texture ids. Vertex normals come from the height field exactly as
/// rt4's GL path computes them (`SceneGraph`, the `anIntArray` gradients with the constant 256), flipped
/// to this renderer's up-pointing Y.
///
/// Not ported from rt4's GL terrain: the alpha-blended overlay edge list (`GlTile.blend`), which softens
/// the underlay/overlay borders. The software tile shapes already carry the hard borders; the HD tier
/// can add the blend pass on top of this mesh.
enum GPUTerrainMesher {
	static let skip = 12345678

	/// Smooth ground normal at a tile corner (rt4: `(dx, 256, dz) / len` with `len = |(dx, 256, dz)|`, Y up).
	static func cornerNormal(_ h: [[Int]], _ x: Int, _ z: Int) -> (Float, Float, Float) {
		let w = h.count - 1, l = (h.first?.count ?? 1) - 1
		func at(_ i: Int, _ j: Int) -> Int { h[min(max(i, 0), w)][min(max(j, 0), l)] }
		let dx = Float(at(x + 1, z) - at(x - 1, z)), dz = Float(at(x, z + 1) - at(x, z - 1))
		let len = (dx * dx + dz * dz + 65536).squareRoot()
		return (dx / len, 256 / len, dz / len)
	}

	/// Normal at an arbitrary point of tile (`tx`, `tz`), bilinear over the four corner normals.
	static func normal(_ h: [[Int]], tx: Int, tz: Int, fx: Float, fz: Float) -> (Float, Float, Float) {
		let a = cornerNormal(h, tx, tz), b = cornerNormal(h, tx + 1, tz)
		let c = cornerNormal(h, tx + 1, tz + 1), d = cornerNormal(h, tx, tz + 1)
		func mix(_ p: Float, _ q: Float, _ t: Float) -> Float { p + (q - p) * t }
		let x = mix(mix(a.0, b.0, fx), mix(d.0, c.0, fx), fz)
		let y = mix(mix(a.1, b.1, fx), mix(d.1, c.1, fx), fz)
		let z = mix(mix(a.2, b.2, fx), mix(d.2, c.2, fx), fz)
		let len = max((x * x + y * y + z * z).squareRoot(), 1e-6)
		return (x / len, y / len, z / len)
	}

	/// Emits one tile's ground (plain or shaped) into `out.opaque`.
	static func append(tile: SceneTile, scene: Scene, palette: GPUPalette, into out: inout GPUMeshStream, bounds: inout GPUBounds) {
		if let p = tile.plainTile {
			appendPlain(p, level: tile.heightLevel, x: tile.x, z: tile.z, scene: scene, palette: palette, into: &out, bounds: &bounds)
		} else if let s = tile.shapedTile {
			appendShaped(s, level: tile.heightLevel, x: tile.x, z: tile.z, scene: scene, palette: palette, into: &out, bounds: &bounds)
		}
	}

	private static func vertex(_ x: Int, _ y: Int, _ z: Int, n: (Float, Float, Float), u: Float, v: Float, color: UInt32, base: UInt32, material: UInt16) -> GPUVertex {
		GPUVertex(x: Float(x), y: Float(-y), z: Float(z), nx: n.0, ny: n.1, nz: n.2, u: u, v: v,
		          color: color, base: base, material: material, flags: GPUVertex.flagTerrain)
	}

	/// The lit colour of a terrain corner for a triangle that is textured (grey shade) or not (palette).
	private static func colours(_ hsl: Int, textured: Bool, palette: GPUPalette) -> (lit: UInt32, base: UInt32) {
		if textured { return (GPUPalette.shade(hsl), GPUVertex.rgba(255, 255, 255)) }
		let c = palette.rgba(hsl)
		return (c, c)
	}

	static func appendPlain(_ t: PlainTile, level: Int, x: Int, z: Int, scene: Scene, palette: GPUPalette, into out: inout GPUMeshStream, bounds: inout GPUBounds) {
		let h = scene.tileHeights[level]
		let x0 = x << 7, z0 = z << 7
		let y00 = h[x][z], y10 = h[x + 1][z], y11 = h[x + 1][z + 1], y01 = h[x][z + 1]
		let textured = t.texture != -1
		let material = textured ? UInt16(truncatingIfNeeded: t.texture + 1) : 0
		func n(_ i: Int, _ j: Int) -> (Float, Float, Float) { cornerNormal(h, i, j) }
		func add(_ v: GPUVertex) { bounds.add(v); out.opaque.append(v) }

		// Triangle 1: (NE, NW, SE), software `fillGouraudTriangle(c, d, b)`.
		if textured || t.colorNE != skip {
			// Flat tiles map the texture from the SW corner; sloped ones from NE (rt4 picks the vertex triple).
			let uvNE = t.flat ? (1, 1) : (0, 0), uvNW = t.flat ? (0, 1) : (1, 0), uvSE = t.flat ? (1, 0) : (0, 1)
			let cNE = colours(t.colorNE, textured: textured, palette: palette)
			let cNW = colours(t.colorNW, textured: textured, palette: palette)
			let cSE = colours(t.colorSE, textured: textured, palette: palette)
			add(vertex(x0 + 128, y11, z0 + 128, n: n(x + 1, z + 1), u: Float(uvNE.0), v: Float(uvNE.1), color: cNE.lit, base: cNE.base, material: material))
			add(vertex(x0, y01, z0 + 128, n: n(x, z + 1), u: Float(uvNW.0), v: Float(uvNW.1), color: cNW.lit, base: cNW.base, material: material))
			add(vertex(x0 + 128, y10, z0, n: n(x + 1, z), u: Float(uvSE.0), v: Float(uvSE.1), color: cSE.lit, base: cSE.base, material: material))
		}
		// Triangle 2: (SW, SE, NW).
		if textured || t.colorSW != skip {
			let cSW = colours(t.colorSW, textured: textured, palette: palette)
			let cSE = colours(t.colorSE, textured: textured, palette: palette)
			let cNW = colours(t.colorNW, textured: textured, palette: palette)
			add(vertex(x0, y00, z0, n: n(x, z), u: 0, v: 0, color: cSW.lit, base: cSW.base, material: material))
			add(vertex(x0 + 128, y10, z0, n: n(x + 1, z), u: 1, v: 0, color: cSE.lit, base: cSE.base, material: material))
			add(vertex(x0, y01, z0 + 128, n: n(x, z + 1), u: 0, v: 1, color: cNW.lit, base: cNW.base, material: material))
		}
	}

	static func appendShaped(_ s: ShapedTile, level: Int, x: Int, z: Int, scene: Scene, palette: GPUPalette, into out: inout GPUMeshStream, bounds: inout GPUBounds) {
		let h = scene.tileHeights[level]
		let baseX = x << 7, baseZ = z << 7
		func add(_ v: GPUVertex) { bounds.add(v); out.opaque.append(v) }
		for i in 0..<s.triA.count {
			let ids = [s.triA[i], s.triB[i], s.triC[i]]
			let cols = [s.colorA[i], s.colorB[i], s.colorC[i]]
			let tex = s.textures?[i] ?? -1
			let textured = tex != -1
			if !textured && cols[0] == skip { continue }
			let material = textured ? UInt16(truncatingIfNeeded: tex + 1) : 0
			for k in 0..<3 {
				let vi = ids[k]
				let px = s.vertexX[vi], py = s.vertexY[vi], pz = s.vertexZ[vi]
				// Flat tiles map from the tile's SW/SE/NW corners (vertices 0, 1, 3); others from the triangle itself.
				var u: Float, v: Float
				if s.flat {
					u = Float(px - baseX) / 128
					v = Float(pz - baseZ) / 128
				} else {
					u = k == 1 ? 1 : 0
					v = k == 2 ? 1 : 0
				}
				if !textured { u = 0; v = 0 }
				let c = colours(cols[k], textured: textured, palette: palette)
				let n = normal(h, tx: x, tz: z, fx: Float(px - baseX) / 128, fz: Float(pz - baseZ) / 128)
				add(vertex(px, py, pz, n: n, u: u, v: v, color: c.lit, base: c.base, material: material))
			}
		}
	}
}
