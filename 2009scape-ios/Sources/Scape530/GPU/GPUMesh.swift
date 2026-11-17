import Foundation

/// Triangle-list vertex streams in two passes: opaque (depth-written) and translucent (blended after).
public struct GPUMeshStream {
	public var opaque: [GPUVertex] = []
	public var blend: [GPUVertex] = []
	public init() {}
	public var isEmpty: Bool { opaque.isEmpty && blend.isEmpty }
	public mutating func removeAll(keepingCapacity: Bool = true) {
		opaque.removeAll(keepingCapacity: keepingCapacity)
		blend.removeAll(keepingCapacity: keepingCapacity)
	}
}

/// A `SoftwareModel` turned into GPU vertices, once, in the model's own space (y flipped up); instances are
/// placed with `append`. Static scenery shares one template per model; actors build one per frame.
///
/// Colours are the software renderer's: each triangle's lit HSL16 corners through the palette (gouraud),
/// the flat colour when `triangleColorC == -1`, and for textured faces the lightness as a grey shade over
/// the texture. Hidden triangles (`triangleColorC == -2`) are skipped. Normals are smooth over a vertex's
/// faces, except flat-shaded faces which keep their face normal. Texture coordinates come from the face's
/// P/M/N texture vertices (rt4 `textureFacesP/M/N`) or its own vertices when it has none, exactly the
/// basis the software rasteriser maps with.
public final class GPUModelTemplate {
	public private(set) var opaque: [GPUVertex] = []
	public private(set) var blend: [GPUVertex] = []
	public private(set) var bounds = GPUBounds()
	/// Texture ids the model uses.
	public private(set) var textureIds: Set<Int> = []
	/// The model is kept so its identity (cache key) stays valid.
	let model: SoftwareModel

	public var triangleCount: Int { (opaque.count + blend.count) / 3 }

	public init(_ model: SoftwareModel, palette: GPUPalette, flags: UInt16 = 0) {
		self.model = model
		build(palette: palette, flags: flags)
	}

	private func build(palette: GPUPalette, flags: UInt16) {
		let m = model
		let n = m.vertexCount, tris = m.triangleCount
		guard n > 0, tris > 0, m.vertexX.count >= n, m.vertexY.count >= n, m.vertexZ.count >= n,
		      m.triangleVertexA.count >= tris, m.triangleColorA.count >= tris,
		      m.triangleColorB.count >= tris, m.triangleColorC.count >= tris else { return }

		// Face normals (rt4 axes, outward: (b - a) x (c - a)), accumulated into smooth vertex normals.
		var faceN = [(Float, Float, Float)](repeating: (0, 0, 0), count: tris)
		var smooth = [(Float, Float, Float)](repeating: (0, 0, 0), count: n)
		for t in 0..<tris {
			let a = m.triangleVertexA[t], b = m.triangleVertexB[t], c = m.triangleVertexC[t]
			guard a < n, b < n, c < n, a >= 0, b >= 0, c >= 0 else { continue }
			let bx = Float(m.vertexX[b] - m.vertexX[a]), by = Float(m.vertexY[b] - m.vertexY[a]), bz = Float(m.vertexZ[b] - m.vertexZ[a])
			let cx = Float(m.vertexX[c] - m.vertexX[a]), cy = Float(m.vertexY[c] - m.vertexY[a]), cz = Float(m.vertexZ[c] - m.vertexZ[a])
			var nx = by * cz - cy * bz, ny = bz * cx - cz * bx, nz = bx * cy - cx * by
			let len = (nx * nx + ny * ny + nz * nz).squareRoot()
			if len > 0 { nx /= len; ny /= len; nz /= len }
			faceN[t] = (nx, ny, nz)
			for v in [a, b, c] { smooth[v].0 += nx; smooth[v].1 += ny; smooth[v].2 += nz }
		}
		func unit(_ v: (Float, Float, Float)) -> (Float, Float, Float) {
			let len = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
			return len > 0 ? (v.0 / len, v.1 / len, v.2 / len) : (0, 1, 0)
		}

		opaque.reserveCapacity(tris * 3)
		for t in 0..<tris {
			let colC = m.triangleColorC[t]
			if colC == -2 { continue }
			let a = m.triangleVertexA[t], b = m.triangleVertexB[t], c = m.triangleVertexC[t]
			guard a < n, b < n, c < n, a >= 0, b >= 0, c >= 0 else { continue }
			let alpha = Int(m.triangleAlpha.map { $0[t] } ?? 0) & 0xFF
			let opacity = alpha == 0 ? 255 : max(0, 255 - alpha)
			if opacity == 0 { continue }
			let flat = colC == -1
			let tex = m.triangleTextures.map { $0[t] } ?? -1
			let material = tex >= 0 ? UInt16(truncatingIfNeeded: tex + 1) : 0
			if tex >= 0 { textureIds.insert(tex) }

			// Corner colours.
			var lit = [UInt32](repeating: 0, count: 3), base = lit
			let cols = [m.triangleColorA[t], flat ? m.triangleColorA[t] : m.triangleColorB[t], flat ? m.triangleColorA[t] : colC]
			for k in 0..<3 {
				if tex >= 0 {
					lit[k] = GPUPalette.shade(cols[k], alpha: opacity)
					base[k] = GPUVertex.rgba(255, 255, 255, opacity)
				} else {
					lit[k] = palette.rgba(cols[k], alpha: opacity)
					let original = t < m.triangleColors.count ? Int(m.triangleColors[t]) & 0xFFFF : cols[k]
					base[k] = palette.rgba(original, alpha: opacity)
				}
			}

			// Texture coordinates: solve p - P = u (M - P) + v (N - P) in the plane of the texture triangle.
			var tp = a, tm = b, tn = c
			if tex >= 0, let face = m.triangleTextureFace, face[t] != -1 {
				let f = Int(face[t]) & 0xFF
				if f < m.textureFacesP.count { tp = m.textureFacesP[f]; tm = m.textureFacesM[f]; tn = m.textureFacesN[f] }
			}
			var uvs = [(Float, Float)](repeating: (0, 0), count: 3)
			if tex >= 0, tp < n, tm < n, tn < n, tp >= 0, tm >= 0, tn >= 0 {
				let px = Float(m.vertexX[tp]), py = Float(m.vertexY[tp]), pz = Float(m.vertexZ[tp])
				let e1 = (Float(m.vertexX[tm]) - px, Float(m.vertexY[tm]) - py, Float(m.vertexZ[tm]) - pz)
				let e2 = (Float(m.vertexX[tn]) - px, Float(m.vertexY[tn]) - py, Float(m.vertexZ[tn]) - pz)
				let d11 = e1.0 * e1.0 + e1.1 * e1.1 + e1.2 * e1.2
				let d22 = e2.0 * e2.0 + e2.1 * e2.1 + e2.2 * e2.2
				let d12 = e1.0 * e2.0 + e1.1 * e2.1 + e1.2 * e2.2
				let det = d11 * d22 - d12 * d12
				if abs(det) > 1e-6 {
					for (k, vi) in [a, b, c].enumerated() {
						let q = (Float(m.vertexX[vi]) - px, Float(m.vertexY[vi]) - py, Float(m.vertexZ[vi]) - pz)
						let q1 = q.0 * e1.0 + q.1 * e1.1 + q.2 * e1.2
						let q2 = q.0 * e2.0 + q.1 * e2.1 + q.2 * e2.2
						uvs[k] = ((q1 * d22 - q2 * d12) / det, (q2 * d11 - q1 * d12) / det)
					}
				}
			}

			let verts = [a, b, c]
			for k in 0..<3 {
				let vi = verts[k]
				let nrm = unit(flat ? faceN[t] : smooth[vi])
				let vtx = GPUVertex(x: Float(m.vertexX[vi]), y: Float(-m.vertexY[vi]), z: Float(m.vertexZ[vi]),
				                    nx: nrm.0, ny: -nrm.1, nz: nrm.2, u: uvs[k].0, v: uvs[k].1,
				                    color: lit[k], base: base[k], material: material, flags: flags)
				bounds.add(vtx)
				if opacity == 255 { opaque.append(vtx) } else { blend.append(vtx) }
			}
		}
	}

	/// Appends an instance: rotated by rt4 `yaw` (0...2047, as `SoftwareModel.render`) about Y, then moved to
	/// the rt4 scene position (`x`, `y`, `z`) with `y` negative up. Returns the instance's bounds.
	@discardableResult
	public func append(to stream: inout GPUMeshStream, yaw: Int, x: Int, y: Int, z: Int) -> GPUBounds {
		let s = yaw == 0 ? 0 : Float(MathTables.sin[yaw & 2047]) / 65536
		let c = yaw == 0 ? 1 : Float(MathTables.cos[yaw & 2047]) / 65536
		let ox = Float(x), oy = Float(-y), oz = Float(z)
		var bb = GPUBounds()
		@inline(__always) func place(_ v: GPUVertex) -> GPUVertex {
			var o = v
			if yaw != 0 {
				o.x = v.z * s + v.x * c
				o.z = v.z * c - v.x * s
				o.nx = v.nz * s + v.nx * c
				o.nz = v.nz * c - v.nx * s
			}
			o.x += ox; o.y += oy; o.z += oz
			bb.add(o.x, o.y, o.z)
			return o
		}
		for v in opaque { stream.opaque.append(place(v)) }
		for v in blend { stream.blend.append(place(v)) }
		return bb
	}
}
