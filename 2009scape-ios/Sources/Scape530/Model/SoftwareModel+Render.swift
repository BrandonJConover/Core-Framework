import Foundation

/// rt4 `MathUtils.reciprical16`: `65536 / i` (index 0 unused).
private let reciprocal16: [Int] = (0..<2048).map { $0 == 0 ? 0 : 65536 / $0 }

/// Per-render working buffers. rt4 keeps these as `static` arrays on
/// `SoftwareModel` (so rendering is single threaded); one shared instance does
/// the same here. Sizes match rt4's non-"sorted" (`aBoolean307 == false`) path.
final class ModelRenderScratch {
	static let shared = ModelRenderScratch()

	static let maxVertices = 4096
	static let depthBuckets = 1600
	static let bucketSize = 64
	static let overflowRows = 512
	static let overflowSize = 512

	// Per-vertex.
	var vertexScreenX = [Int](repeating: 0, count: maxVertices)
	var vertexScreenY = [Int](repeating: 0, count: maxVertices)
	var vertexDepth = [Int](repeating: 0, count: maxVertices)
	var projectX = [Int](repeating: 0, count: maxVertices)
	var projectY = [Int](repeating: 0, count: maxVertices)
	var projectZ = [Int](repeating: 0, count: maxVertices)
	// Per-triangle.
	var projectTriangle = [Bool](repeating: false, count: maxVertices)
	var testTriangleX = [Bool](repeating: false, count: maxVertices)

	// Depth buckets (rt4 anIntArray558 / anIntArrayArray44 / anIntArray552 / anIntArrayArray43).
	var bucketCount = [Int](repeating: 0, count: depthBuckets)
	var buckets = [Int](repeating: 0, count: depthBuckets * bucketSize)
	var overflowCount = [Int](repeating: 0, count: overflowRows)
	var overflow = [Int](repeating: 0, count: overflowRows * overflowSize)
	var overflowRowsUsed = 0

	// Priority lists (rt4 priorityTriangles etc.): 12 priorities.
	var priorityCounts = [Int](repeating: 0, count: 12)
	var lowPrioritySum = [Int](repeating: 0, count: 12)
	var priorityTriangles = [Int](repeating: 0, count: 12 * maxVertices)
	var normalPriorityDepth = [Int](repeating: 0, count: maxVertices)
	var highPriorityDepth = [Int](repeating: 0, count: maxVertices)

	// Near-plane clipped polygon (rt4 anIntArray542 / 547 / 553).
	var clipX = [Int](repeating: 0, count: 10)
	var clipY = [Int](repeating: 0, count: 10)
	var clipColor = [Int](repeating: 0, count: 10)
}

extension SoftwareModel {
	/// rt4 `SoftwareModel.render` (the `Model.render` override): projects the
	/// model at scene offset (`x`, `y`, `z`) rotated by `yaw` around Y and
	/// draws it into the rasteriser's buffer.
	///
	/// The camera is given as sin/cos of pitch and yaw (16.16 fixed point, from
	/// `MathTables`); scene coordinates are relative to the camera. `key` is
	/// rt4's picking key: when it is positive and `ScenePicker.shared.allowInput`
	/// is set, a model whose screen box holds the mouse reports its key (see
	/// `ScenePicker`). The particle system and rt4's `arg9` are not ported.
	public func render(_ r: Rasteriser3D, yaw: Int, sinPitch sinCameraPitch: Int, cosPitch cosCameraPitch: Int, sinYaw sinCameraYaw: Int, cosYaw cosCameraYaw: Int, x sceneX: Int, y sceneY: Int, z sceneZ: Int, key: Int64 = 0) {
		ensureBounds()
		let a = (sceneZ * cosCameraYaw - sceneX * sinCameraYaw) >> 16
		let b = (sceneY * sinCameraPitch + a * cosCameraPitch) >> 16
		let c = b + ((lengthXZ * cosCameraPitch + maxY * sinCameraPitch) >> 16)
		let d = b + ((-lengthXZ * cosCameraPitch + minY * sinCameraPitch) >> 16)
		if c <= 50 || d >= 3500 { return } // near and far clip

		let e = (sceneZ * sinCameraYaw + sceneX * cosCameraYaw) >> 16
		let minScreenX = (e + lengthXZ) << 9
		if minScreenX / c <= Int(r.screenLowerX) { return }
		let maxScreenX = (e - lengthXZ) << 9
		if maxScreenX / c >= Int(r.screenUpperX) { return }
		let f = (sceneY * cosCameraPitch - a * sinCameraPitch) >> 16
		let minScreenY = (f + ((lengthXZ * sinCameraPitch + maxY * cosCameraPitch) >> 16)) << 9
		if minScreenY / c <= Int(r.screenLowerY) { return }
		let maxScreenY = (f + ((-lengthXZ * sinCameraPitch + minY * cosCameraPitch) >> 16)) << 9
		if maxScreenY / c >= Int(r.screenUpperY) { return }

		guard vertexCount <= ModelRenderScratch.maxVertices, triangleCount <= ModelRenderScratch.maxVertices else { return }
		let s = ModelRenderScratch.shared
		var anyBehind = false
		let project = d <= 50 || textureFaceCount > 0
		let cx = Int(r.centerX), cy = Int(r.centerY)

		var yawSin = 0, yawCos = 0
		if yaw != 0 {
			yawSin = MathTables.sin[yaw & 2047]
			yawCos = MathTables.cos[yaw & 2047]
		}

		// Mouse picking (rt4 `SoftwareModel.render`): a coarse screen box first, then the projected
		// bounding box; pickable models (actors) report right there, the rest are tested per triangle.
		var testTriangles = false
		let picker = ScenePicker.shared
		if key > 0 && picker.allowInput && d > 0 {
			var left: Int, right: Int, top: Int, bottom: Int
			if e > 0 { left = maxScreenX / c; right = minScreenX / d } else { left = maxScreenX / d; right = minScreenX / c }
			if f > 0 { top = maxScreenY / c; bottom = minScreenY / d } else { top = maxScreenY / d; bottom = minScreenY / c }
			if picker.mouseX >= left && picker.mouseX <= right && picker.mouseY >= top && picker.mouseY <= bottom {
				left = 999999; right = -999999; top = 999999; bottom = -999999
				let bx = [minX, maxX, minX, maxX, minX, maxX, minX, maxX]
				let bz = [minZ, minZ, maxZ, maxZ, minZ, minZ, maxZ, maxZ]
				let by = [minY, minY, minY, minY, maxY, maxY, maxY, maxY]
				for i in 0..<8 {
					var px = bx[i], py = by[i], pz = bz[i]
					if yaw != 0 {
						let t = (pz * yawSin + px * yawCos) >> 16
						pz = (pz * yawCos - px * yawSin) >> 16
						px = t
					}
					px += sceneX
					py += sceneY
					pz += sceneZ
					var t = (pz * sinCameraYaw + px * cosCameraYaw) >> 16
					pz = (pz * cosCameraYaw - px * sinCameraYaw) >> 16
					px = t
					t = (py * cosCameraPitch - pz * sinCameraPitch) >> 16
					pz = (py * sinCameraPitch + pz * cosCameraPitch) >> 16
					if pz > 0 {
						let sx = (px << 9) / pz, sy = (t << 9) / pz
						left = min(left, sx); right = max(right, sx)
						top = min(top, sy); bottom = max(bottom, sy)
					}
				}
				if picker.mouseX >= left && picker.mouseX <= right && picker.mouseY >= top && picker.mouseY <= bottom {
					if pickable { picker.add(key) } else { testTriangles = true }
				}
			}
		}
		for v in 0..<vertexCount {
			var x = vertexX[v], y = vertexY[v], z = vertexZ[v]
			if yaw != 0 {
				let w = (z * yawSin + x * yawCos) >> 16
				z = (z * yawCos - x * yawSin) >> 16
				x = w
			}
			x += sceneX
			y += sceneY
			z += sceneZ
			var w = (z * sinCameraYaw + x * cosCameraYaw) >> 16
			z = (z * cosCameraYaw - x * sinCameraYaw) >> 16
			x = w
			w = (y * cosCameraPitch - z * sinCameraPitch) >> 16
			z = (y * sinCameraPitch + z * cosCameraPitch) >> 16
			s.vertexDepth[v] = z - b
			if z >= 50 {
				s.vertexScreenX[v] = cx + (x << 9) / z
				s.vertexScreenY[v] = cy + (w << 9) / z
			} else {
				s.vertexScreenX[v] = -5000
				anyBehind = true
			}
			if project {
				s.projectX[v] = x
				s.projectY[v] = w
				s.projectZ[v] = z
			}
		}
		drawProjected(r, s, anyBehind, b - d, c - d + 2, pickKey: testTriangles ? key : 0)
	}

	/// rt4 `SoftwareModel.setCamera` (`method4573` family in the brief): draws
	/// the model as seen by a fixed camera at the origin, used for interface
	/// models (item icons, head models, inventory previews). `yAngle` rotates
	/// about Y, `zAngle` about Z (roll), `xAngle` is the camera tilt; (`x`,
	/// `y`, `z`) translates the model after rotation. Perspective divide uses
	/// the model's own depth. Item icons call it with
	/// `(yAngle2D, zAngle2D, xAngle2D, xOffset2D, sin(xAngle2D) * zoom >> 16
	/// + yOffset2D - minY / 2, yOffset2D + cos(xAngle2D) * zoom >> 16)`.
	public func renderAtOrigin(_ r: Rasteriser3D, yAngle: Int, zAngle: Int, xAngle: Int, x tx: Int, y ty: Int, z tz: Int) {
		ensureBounds()
		guard vertexCount <= ModelRenderScratch.maxVertices, triangleCount <= ModelRenderScratch.maxVertices else { return }
		let s = ModelRenderScratch.shared
		let cx = Int(r.centerX), cy = Int(r.centerY)
		let sinY = MathTables.sin[yAngle & 2047], cosY = MathTables.cos[yAngle & 2047]
		let sinZ = MathTables.sin[zAngle & 2047], cosZ = MathTables.cos[zAngle & 2047]
		let sinP = MathTables.sin[xAngle & 2047], cosP = MathTables.cos[xAngle & 2047]
		let base = (ty * sinP + tz * cosP) >> 16
		for i in 0..<vertexCount {
			var x = vertexX[i], y = vertexY[i], z = vertexZ[i]
			if zAngle != 0 {
				let w = (y * sinZ + x * cosZ) >> 16
				y = (y * cosZ - x * sinZ) >> 16
				x = w
			}
			if yAngle != 0 {
				let w = (z * sinY + x * cosY) >> 16
				z = (z * cosY - x * sinY) >> 16
				x = w
			}
			x += tx
			y += ty
			z += tz
			let w = (y * cosP - z * sinP) >> 16
			z = (y * sinP + z * cosP) >> 16
			s.vertexDepth[i] = z - base
			if z == 0 { return } // rt4: ArithmeticException, swallowed
			s.vertexScreenX[i] = cx + (x << 9) / z
			s.vertexScreenY[i] = cy + (w << 9) / z
			if textureFaceCount > 0 {
				s.projectX[i] = x
				s.projectY[i] = w
				s.projectZ[i] = z
			}
		}
		drawProjected(r, s, false, radius, radius << 1)
	}

	/// rt4 `SoftwareModel.method4591`: like `renderAtOrigin` but with an
	/// orthographic-style fixed divisor `zoom` instead of the vertex depth
	/// (used for flat icons).
	public func renderOrthographic(_ r: Rasteriser3D, yAngle: Int, zAngle: Int, xAngle: Int, x tx: Int, y ty: Int, z tz: Int, zoom: Int) {
		ensureBounds()
		guard zoom != 0, vertexCount <= ModelRenderScratch.maxVertices, triangleCount <= ModelRenderScratch.maxVertices else { return }
		let s = ModelRenderScratch.shared
		let cx = Int(r.centerX), cy = Int(r.centerY)
		let sinY = MathTables.sin[yAngle & 2047], cosY = MathTables.cos[yAngle & 2047]
		let sinZ = MathTables.sin[zAngle & 2047], cosZ = MathTables.cos[zAngle & 2047]
		let sinP = MathTables.sin[xAngle & 2047], cosP = MathTables.cos[xAngle & 2047]
		let base = (ty * sinP + tz * cosP) >> 16
		for i in 0..<vertexCount {
			var x = vertexX[i], y = vertexY[i], z = vertexZ[i]
			if zAngle != 0 {
				let w = (y * sinZ + x * cosZ) >> 16
				y = (y * cosZ - x * sinZ) >> 16
				x = w
			}
			if yAngle != 0 {
				let w = (z * sinY + x * cosY) >> 16
				z = (z * cosY - x * sinY) >> 16
				x = w
			}
			x += tx
			y += ty
			z += tz
			let w = (y * cosP - z * sinP) >> 16
			z = (y * sinP + z * cosP) >> 16
			s.vertexDepth[i] = z - base
			s.vertexScreenX[i] = cx + (x << 9) / zoom
			s.vertexScreenY[i] = cy + (w << 9) / zoom
			if textureFaceCount > 0 {
				s.projectX[i] = x
				s.projectY[i] = w
				s.projectZ[i] = z
			}
		}
		drawProjected(r, s, false, radius, radius << 1)
	}

	// MARK: depth sort and draw

	/// rt4 `SoftwareModel.draw` (bucket path): back-face culls, files each
	/// visible triangle into a depth bucket (`depthOffset` shifts depths to
	/// non-negative, `bucketLimit` is the number of buckets in use), then
	/// draws far to near, interleaving the priority lists as rt4 does.
	private func drawProjected(_ r: Rasteriser3D, _ s: ModelRenderScratch, _ anyBehind: Bool, _ depthOffset: Int, _ bucketLimit: Int, pickKey: Int64 = 0) {
		var pickKey = pickKey
		if bucketLimit >= ModelRenderScratch.depthBuckets { return }
		for i in 0..<ModelRenderScratch.depthBuckets { s.bucketCount[i] = 0 }
		for i in 0..<ModelRenderScratch.overflowRows { s.overflowCount[i] = 0 }
		s.overflowRowsUsed = 0
		let width = Int(r.width)

		/// Files triangle `i` into the bucket for `depth`.
		func file(_ i: Int, _ depth: Int) {
			guard depth >= 0 && depth < ModelRenderScratch.depthBuckets else { return } // rt4: AIOOBE, model aborted
			let n = s.bucketCount[depth]
			if n < ModelRenderScratch.bucketSize {
				s.buckets[depth * ModelRenderScratch.bucketSize + n] = i
				s.bucketCount[depth] = n + 1
			} else {
				var row = n
				if row == ModelRenderScratch.bucketSize {
					if s.overflowRowsUsed == ModelRenderScratch.overflowRows { return }
					row = s.overflowRowsUsed + 65
					s.overflowRowsUsed += 1
					s.bucketCount[depth] = row
				}
				row -= 65
				let m = s.overflowCount[row]
				if m < ModelRenderScratch.overflowSize {
					s.overflow[row * ModelRenderScratch.overflowSize + m] = i
					s.overflowCount[row] = m + 1
				}
			}
		}

		for i in 0..<triangleCount where triangleColorC[i] != -2 {
			let a = triangleVertexA[i], b = triangleVertexB[i], c = triangleVertexC[i]
			let xa = s.vertexScreenX[a], xb = s.vertexScreenX[b], xc = s.vertexScreenX[c]
			if anyBehind && (xa == -5000 || xb == -5000 || xc == -5000) {
				// At least one vertex is behind the near plane: cull in view space.
				let bx = s.projectX[b], by = s.projectY[b], bz = s.projectZ[b]
				let e0x = Int32(truncatingIfNeeded: s.projectX[a] - bx)
				let e0y = Int32(truncatingIfNeeded: s.projectY[a] - by)
				let e0z = Int32(truncatingIfNeeded: s.projectZ[a] - bz)
				let e1x = Int32(truncatingIfNeeded: s.projectX[c] - bx)
				let e1y = Int32(truncatingIfNeeded: s.projectY[c] - by)
				let e1z = Int32(truncatingIfNeeded: s.projectZ[c] - bz)
				let nx = (e0y &* e1z) &- (e0z &* e1y)
				let ny = (e0z &* e1x) &- (e0x &* e1z)
				let nz = (e0x &* e1y) &- (e0y &* e1x)
				let dot = (Int32(truncatingIfNeeded: bx) &* nx) &+ (Int32(truncatingIfNeeded: by) &* ny) &+ (Int32(truncatingIfNeeded: bz) &* nz)
				if dot > 0 {
					s.projectTriangle[i] = true
					file(i, (s.vertexDepth[a] + s.vertexDepth[b] + s.vertexDepth[c]) / 3 + depthOffset)
				}
			} else {
				// rt4 `draw`: the mouse test runs before the back-face test, once per model.
				if pickKey != 0 {
					let picker = ScenePicker.shared
					let ya = s.vertexScreenY[a], yb = s.vertexScreenY[b], yc = s.vertexScreenY[c]
					let mx = picker.mouseX + Int(r.centerX), my = picker.mouseY + Int(r.centerY)
					if !(my < ya && my < yb && my < yc) && !(my > ya && my > yb && my > yc) && !(mx < xa && mx < xb && mx < xc) && (mx <= xa || mx <= xb || mx <= xc) {
						picker.add(pickKey)
						pickKey = 0
					}
				}
				let cross = Int32(truncatingIfNeeded: xa - xb) &* Int32(truncatingIfNeeded: s.vertexScreenY[c] - s.vertexScreenY[b])
					&- Int32(truncatingIfNeeded: s.vertexScreenY[a] - s.vertexScreenY[b]) &* Int32(truncatingIfNeeded: xc - xb)
				if cross > 0 {
					s.projectTriangle[i] = false
					s.testTriangleX[i] = xa < 0 || xb < 0 || xc < 0 || xa > width || xb > width || xc > width
					file(i, (s.vertexDepth[a] + s.vertexDepth[b] + s.vertexDepth[c]) / 3 + depthOffset)
				}
			}
		}

		guard let priorities = trianglePriorities else {
			var i = bucketLimit - 1
			while i >= 0 {
				let n = s.bucketCount[i]
				if n > 0 {
					let m = min(n, 64)
					for k in 0..<m { drawTriangle(r, s, s.buckets[i * 64 + k]) }
				}
				if n > 64 {
					let row = n - 64 - 1
					for k in 0..<s.overflowCount[row] { drawTriangle(r, s, s.overflow[row * ModelRenderScratch.overflowSize + k]) }
				}
				i -= 1
			}
			return
		}

		for i in 0..<12 { s.priorityCounts[i] = 0; s.lowPrioritySum[i] = 0 }
		func addPriority(_ tri: Int, _ depth: Int) {
			let p = Int(priorities[tri])
			guard p >= 0 && p < 12 else { return }
			let n = s.priorityCounts[p]
			s.priorityCounts[p] = n + 1
			s.priorityTriangles[p * ModelRenderScratch.maxVertices + n] = tri
			if p < 10 {
				s.lowPrioritySum[p] += depth
			} else if p == 10 {
				s.normalPriorityDepth[n] = depth
			} else {
				s.highPriorityDepth[n] = depth
			}
		}
		var i = bucketLimit - 1
		while i >= 0 {
			let n = s.bucketCount[i]
			if n > 0 {
				for k in 0..<min(n, 64) { addPriority(s.buckets[i * 64 + k], i) }
			}
			if n > 64 {
				let row = n - 64 - 1
				for k in 0..<s.overflowCount[row] { addPriority(s.overflow[row * ModelRenderScratch.overflowSize + k], i) }
			}
			i -= 1
		}

		// Priorities 1/2, 3/4 and 6/8 are averaged so that priority-10/11
		// triangles are interleaved at the matching depth.
		let pc = s.priorityCounts, lp = s.lowPrioritySum
		var minPriority = 0
		if pc[1] > 0 || pc[2] > 0 { minPriority = (lp[1] + lp[2]) / (pc[1] + pc[2]) }
		var halfPriority = 0
		if pc[3] > 0 || pc[4] > 0 { halfPriority = (lp[3] + lp[4]) / (pc[3] + pc[4]) }
		var maxPriority = 0
		if pc[6] > 0 || pc[8] > 0 { maxPriority = (lp[6] + lp[8]) / (pc[6] + pc[8]) }

		// Current list: priority 10 first, then 11 (rt4 swaps arrays by identity).
		var t = 0
		var listIndex = 10
		var listCount = pc[10]
		var onHigh = false
		if listCount == 0 {
			listIndex = 11; listCount = pc[11]; onHigh = true
		}
		func listDepth(_ idx: Int) -> Int { onHigh ? s.highPriorityDepth[idx] : s.normalPriorityDepth[idx] }
		var pri = listCount > 0 ? listDepth(0) : -1000

		func drawNextInterleaved() {
			drawTriangle(r, s, s.priorityTriangles[listIndex * ModelRenderScratch.maxVertices + t])
			t += 1
			if t == listCount && !onHigh {
				t = 0; listIndex = 11; listCount = pc[11]; onHigh = true
			}
			pri = t < listCount ? listDepth(t) : -1000
		}

		for p in 0..<10 {
			if p == 0 { while pri > minPriority { drawNextInterleaved() } }
			if p == 3 { while pri > halfPriority { drawNextInterleaved() } }
			if p == 5 { while pri > maxPriority { drawNextInterleaved() } }
			for m in 0..<pc[p] { drawTriangle(r, s, s.priorityTriangles[p * ModelRenderScratch.maxVertices + m]) }
		}
		while pri != -1000 { drawNextInterleaved() }
	}

	// MARK: triangle dispatch

	/// rt4 `SoftwareModel.drawTriangle`: hands one triangle to the rasteriser
	/// (flat, Gouraud or textured; alpha via `Rasteriser.alpha`).
	private func drawTriangle(_ r: Rasteriser3D, _ s: ModelRenderScratch, _ index: Int) {
		if s.projectTriangle[index] {
			drawClippedTriangle(r, s, index)
			return
		}
		let a = triangleVertexA[index], b = triangleVertexB[index], c = triangleVertexC[index]
		r.testX = s.testTriangleX[index]
		r.alpha = Int32(triangleAlpha.map { Int($0[index]) & 0xFF } ?? 0)
		let colorA = triangleColorA[index], colorB = triangleColorB[index], colorC = triangleColorC[index]
		if let tex = triangleTextures, tex[index] != -1 {
			var tA = a, tB = b, tC = c
			if let face = triangleTextureFace, face[index] != -1 {
				let f = Int(face[index]) & 0xFF
				tA = textureFacesP[f]; tB = textureFacesM[f]; tC = textureFacesN[f]
			}
			if colorC == -1 {
				r.fillTexturedAlphaTriangle(s.vertexScreenY[a], s.vertexScreenY[b], s.vertexScreenY[c], s.vertexScreenX[a], s.vertexScreenX[b], s.vertexScreenX[c], colorA, colorA, colorA, s.projectX[tA], s.projectX[tB], s.projectX[tC], s.projectY[tA], s.projectY[tB], s.projectY[tC], s.projectZ[tA], s.projectZ[tB], s.projectZ[tC], tex[index])
			} else {
				r.fillTexturedAlphaTriangle(s.vertexScreenY[a], s.vertexScreenY[b], s.vertexScreenY[c], s.vertexScreenX[a], s.vertexScreenX[b], s.vertexScreenX[c], colorA, colorB, colorC, s.projectX[tA], s.projectX[tB], s.projectX[tC], s.projectY[tA], s.projectY[tB], s.projectY[tC], s.projectZ[tA], s.projectZ[tB], s.projectZ[tC], tex[index])
			}
		} else if colorC == -1 {
			r.fillTriangle(s.vertexScreenY[a], s.vertexScreenY[b], s.vertexScreenY[c], s.vertexScreenX[a], s.vertexScreenX[b], s.vertexScreenX[c], Int(r.palette[colorA & 0xFFFF]))
		} else {
			r.fillGouraudTriangle(s.vertexScreenY[a], s.vertexScreenY[b], s.vertexScreenY[c], s.vertexScreenX[a], s.vertexScreenX[b], s.vertexScreenX[c], colorA & 0xFFFF, colorB & 0xFFFF, colorC & 0xFFFF)
		}
	}

	/// rt4 `SoftwareModel.drawProjectedTriangle`: clips a triangle that
	/// crosses the near plane (z = 50) into a polygon of 3 or 4 vertices in
	/// view space, interpolating colour, and draws it.
	private func drawClippedTriangle(_ r: Rasteriser3D, _ s: ModelRenderScratch, _ index: Int) {
		let cx = Int(r.centerX), cy = Int(r.centerY)
		var n = 0
		let va = triangleVertexA[index], vb = triangleVertexB[index], vc = triangleVertexC[index]
		let za = s.projectZ[va], zb = s.projectZ[vb], zc = s.projectZ[vc]
		r.alpha = Int32(triangleAlpha.map { Int($0[index]) & 0xFF } ?? 0)
		let colA = triangleColorA[index] & 0xFFFF
		let colB = triangleColorB[index] & 0xFFFF
		let colC = triangleColorC[index] & 0xFFFF

		/// Crossing point on the edge from `from` (behind) to `to` (in front).
		func intersect(_ from: Int, _ to: Int, _ zFrom: Int, _ zTo: Int, _ colFrom: Int, _ colTo: Int) {
			let diff = zTo - zFrom
			let t = (50 - zFrom) * (diff < 2048 ? reciprocal16[diff] : 65536 / diff)
			let fx = s.projectX[from], fy = s.projectY[from]
			s.clipX[n] = cx + ((fx + (((s.projectX[to] - fx) * t) >> 16)) << 9) / 50
			s.clipY[n] = cy + ((fy + (((s.projectY[to] - fy) * t) >> 16)) << 9) / 50
			s.clipColor[n] = colFrom + (((colTo - colFrom) * t) >> 16)
			n += 1
		}
		func keep(_ v: Int, _ col: Int) {
			s.clipX[n] = s.vertexScreenX[v]
			s.clipY[n] = s.vertexScreenY[v]
			s.clipColor[n] = col
			n += 1
		}

		if za >= 50 {
			keep(va, colA)
		} else {
			if zc >= 50 { intersect(va, vc, za, zc, colA, colC) }
			if zb >= 50 { intersect(va, vb, za, zb, colA, colB) }
		}
		if zb >= 50 {
			keep(vb, colB)
		} else {
			if za >= 50 { intersect(vb, va, zb, za, colB, colA) }
			if zc >= 50 { intersect(vb, vc, zb, zc, colB, colC) }
		}
		if zc >= 50 {
			keep(vc, colC)
		} else {
			if zb >= 50 { intersect(vc, vb, zc, zb, colC, colB) }
			if za >= 50 { intersect(vc, va, zc, za, colC, colA) }
		}

		let x0 = s.clipX[0], x1 = s.clipX[1], x2 = s.clipX[2]
		let y0 = s.clipY[0], y1 = s.clipY[1], y2 = s.clipY[2]
		r.testX = false
		let w = Int(r.width)
		let colorC = triangleColorC[index]
		var textured = -1
		var tA = va, tB = vb, tC = vc
		if let tex = triangleTextures, tex[index] != -1 {
			textured = tex[index]
			if let face = triangleTextureFace, face[index] != -1 {
				let f = Int(face[index]) & 0xFF
				tA = textureFacesP[f]; tB = textureFacesM[f]; tC = textureFacesN[f]
			}
		}
		let flatColor = triangleColorA[index]

		if n == 3 {
			if x0 < 0 || x1 < 0 || x2 < 0 || x0 > w || x1 > w || x2 > w { r.testX = true }
			if textured != -1 {
				if colorC == -1 {
					r.fillTexturedAlphaTriangle(y0, y1, y2, x0, x1, x2, flatColor, flatColor, flatColor, s.projectX[tA], s.projectX[tB], s.projectX[tC], s.projectY[tA], s.projectY[tB], s.projectY[tC], s.projectZ[tA], s.projectZ[tB], s.projectZ[tC], textured)
				} else {
					r.fillTexturedAlphaTriangle(y0, y1, y2, x0, x1, x2, s.clipColor[0], s.clipColor[1], s.clipColor[2], s.projectX[tA], s.projectX[tB], s.projectX[tC], s.projectY[tA], s.projectY[tB], s.projectY[tC], s.projectZ[tA], s.projectZ[tB], s.projectZ[tC], textured)
				}
			} else if colorC == -1 {
				r.fillTriangle(y0, y1, y2, x0, x1, x2, Int(r.palette[flatColor & 0xFFFF]))
			} else {
				r.fillGouraudTriangle(y0, y1, y2, x0, x1, x2, s.clipColor[0], s.clipColor[1], s.clipColor[2])
			}
		}
		if n != 4 { return }
		let x3 = s.clipX[3], y3 = s.clipY[3]
		if x0 < 0 || x1 < 0 || x2 < 0 || x0 > w || x1 > w || x2 > w || x3 < 0 || x3 > w { r.testX = true }
		if textured != -1 {
			if colorC == -1 {
				r.fillTexturedAlphaTriangle(y0, y1, y2, x0, x1, x2, flatColor, flatColor, flatColor, s.projectX[tA], s.projectX[tB], s.projectX[tC], s.projectY[tA], s.projectY[tB], s.projectY[tC], s.projectZ[tA], s.projectZ[tB], s.projectZ[tC], textured)
				r.fillTexturedAlphaTriangle(y0, y2, y3, x0, x2, x3, flatColor, flatColor, flatColor, s.projectX[tA], s.projectX[tB], s.projectX[tC], s.projectY[tA], s.projectY[tB], s.projectY[tC], s.projectZ[tA], s.projectZ[tB], s.projectZ[tC], textured)
			} else {
				r.fillTexturedAlphaTriangle(y0, y1, y2, x0, x1, x2, s.clipColor[0], s.clipColor[1], s.clipColor[2], s.projectX[tA], s.projectX[tB], s.projectX[tC], s.projectY[tA], s.projectY[tB], s.projectY[tC], s.projectZ[tA], s.projectZ[tB], s.projectZ[tC], textured)
				r.fillTexturedAlphaTriangle(y0, y2, y3, x0, x2, x3, s.clipColor[0], s.clipColor[2], s.clipColor[3], s.projectX[tA], s.projectX[tB], s.projectX[tC], s.projectY[tA], s.projectY[tB], s.projectY[tC], s.projectZ[tA], s.projectZ[tB], s.projectZ[tC], textured)
			}
		} else if colorC == -1 {
			let color = Int(r.palette[flatColor & 0xFFFF])
			r.fillTriangle(y0, y1, y2, x0, x1, x2, color)
			r.fillTriangle(y0, y2, y3, x0, x2, x3, color)
		} else {
			r.fillGouraudTriangle(y0, y1, y2, x0, x1, x2, s.clipColor[0], s.clipColor[1], s.clipColor[2])
			r.fillGouraudTriangle(y0, y2, y3, x0, x2, x3, s.clipColor[0], s.clipColor[2], s.clipColor[3])
		}
	}

	// MARK: terrain fitting

	/// rt4 `SoftwareModel.method4586` (hillskew): fits the lit model to the
	/// terrain at tile-space offset (`x`, `z`). `type` is `LocType.hillskewType`
	/// (1 drape, 2 drape below a fraction, 3 tilt, 4/5 use the `upper` grid).
	/// Returns `self` when nothing needs to change; otherwise a copy that
	/// shares triangle data, so cached models stay intact.
	public func fitToTerrain(type: Int, amount: Int, heights: [[Int]], upper: [[Int]]?, x: Int, baseY: Int, z: Int) -> SoftwareModel {
		ensureBounds()
		var lo = x + minX, hi = x + maxX, zlo = z + minZ, zhi = z + maxZ
		if [1, 2, 3, 5].contains(type) && (lo < 0 || ((hi + 128) >> 7) >= heights.count || zlo < 0 || ((zhi + 128) >> 7) >= heights[0].count) { return self }
		if type == 4 || type == 5 {
			guard let up = upper else { return self }
			if lo < 0 || ((hi + 128) >> 7) >= up.count || zlo < 0 || ((zhi + 128) >> 7) >= up[0].count { return self }
		} else {
			lo >>= 7; hi = (hi + 127) >> 7; zlo >>= 7; zhi = (zhi + 127) >> 7
			if heights[lo][zlo] == baseY && heights[hi][zlo] == baseY && heights[lo][zhi] == baseY && heights[hi][zhi] == baseY { return self }
		}
		let m = copy()
		if type != 3 { m.vertexY = [Int](repeating: 0, count: vertexCount) }

		func sample(_ g: [[Int]], _ wx: Int, _ wz: Int) -> Int {
			let fx = wx & 0x7F, fz = wz & 0x7F, tx = wx >> 7, tz = wz >> 7
			let p = (g[tx][tz] * (128 - fx) + g[tx + 1][tz] * fx) >> 7
			let q = (g[tx][tz + 1] * (128 - fx) + g[tx + 1][tz + 1] * fx) >> 7
			return (p * (128 - fz) + q * fz) >> 7
		}
		switch type {
		case 1:
			for i in 0..<vertexCount {
				m.vertexY[i] = vertexY[i] + sample(heights, vertexX[i] + x, vertexZ[i] + z) - baseY
			}
		case 2:
			for i in 0..<vertexCount {
				let frac = minY == 0 ? amount : (vertexY[i] << 16) / minY
				if frac < amount {
					let h = sample(heights, vertexX[i] + x, vertexZ[i] + z)
					m.vertexY[i] = vertexY[i] + (h - baseY) * (amount - frac) / amount
				} else {
					m.vertexY[i] = vertexY[i]
				}
			}
		case 3:
			m.tiltToTerrain(heights, x, baseY, z, (amount & 0xFF) * 4, ((amount >> 8) & 0xFF) * 4)
		case 4:
			guard let up = upper else { return self }
			let height = maxY - minY
			for i in 0..<vertexCount {
				m.vertexY[i] = vertexY[i] + sample(up, vertexX[i] + x, vertexZ[i] + z) + height - baseY
			}
		case 5:
			guard let up = upper else { return self }
			let height = maxY - minY
			if height == 0 { return self }
			for i in 0..<vertexCount {
				let lower = sample(heights, vertexX[i] + x, vertexZ[i] + z)
				let top = sample(up, vertexX[i] + x, vertexZ[i] + z)
				let diff = lower - top
				m.vertexY[i] = ((((vertexY[i] << 8) / height) * diff) >> 8) - (baseY - lower)
			}
		default: break
		}
		m.boundsValid = false
		return m
	}

	/// rt4 `Model.method4573`: tilts the model to lie on a terrain patch of
	/// `w` x `d` units centred on the model (hillskew type 3).
	private func tiltToTerrain(_ h: [[Int]], _ x: Int, _ baseY: Int, _ z: Int, _ w: Int, _ d: Int) {
		let h00 = RawModel.heightAt(h, x - w / 2, z - d / 2)
		let h10 = RawModel.heightAt(h, x + w / 2, z - d / 2)
		let h01 = RawModel.heightAt(h, x - w / 2, z + d / 2)
		let h11 = RawModel.heightAt(h, x + w / 2, z + d / 2)
		let minA = min(h00, h10), minB = min(h01, h11)
		let minC = min(h10, h11), minD = min(h00, h01)
		if d != 0 {
			let a = Int(atan2(Double(minA - minB), Double(d)) * 325.95) & 0x7FF
			if a != 0 { rotateX(a) }
		}
		if w != 0 {
			let a = Int(atan2(Double(minD - minC), Double(w)) * 325.95) & 0x7FF
			if a != 0 { rotateZ(a) }
		}
		var mid = h00 + h11
		if h10 + h01 < mid { mid = h10 + h01 }
		mid = (mid >> 1) - baseY
		if mid != 0 { translate(0, mid, 0) }
	}
}
