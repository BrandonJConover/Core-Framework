import Foundation

/// Global animation switches (rt4 `SeqType.applyTweening`, defaulting to
/// `GlobalConfig.USE_TWEENING = true`).
public enum AnimSettings {
	public static var applyTweening = true
}

/// Pivot (rt4 statics `anInt5793/5791/5792`) and the pending flag
/// (`aBoolean306`) shared by the transforms of one frame application. rt4 keeps
/// these in statics; here they travel with the call.
struct AnimPivot {
	var x = 0, y = 0, z = 0
	/// A masked origin transform moved the pivot and the next matrix-based
	/// rotate/scale must first map it into the layer's pose space.
	var matrixPending = false
}

/// One animation playing on an entity: the sequence, the current frame index
/// into `seq.frames`, the next frame (-1 for none, used for tweening) and how
/// far through the current frame we are. Mirrors the `(frame, nextFrame,
/// cycle)` triple rt4's `PathingEntity` keeps per animation.
public struct SeqPose {
	public var seq: SeqType
	public var frame: Int
	/// Index of the following frame for tweening, or -1.
	public var nextFrame: Int
	/// rt4's per-frame cycle counter as stored on the entity. The tween
	/// numerator actually used is `step - 1`, as in rt4.
	public var step: Int

	public init(seq: SeqType, frame: Int, nextFrame: Int = -1, step: Int = 0) {
		self.seq = seq; self.frame = frame; self.nextFrame = nextFrame; self.step = step
	}
}

/// A pose with its framesets resolved (rt4's local frame bookkeeping in
/// `PlayerAppearance.method1954` / `NpcType.getBodyModel`).
struct ResolvedPose {
	var set: AnimFrameset?
	var frame: Int
	var tweenSet: AnimFrameset?
	var tweenFrame: Int
	/// Delay of the current frame (tween denominator); 0 when not tweening.
	var delay: Int
	var step: Int
	var flag14: Bool
	var alpha: Bool
	var colour: Bool
}

extension ConfigStore {
	/// Resolve a pose's framesets. `layer` poses follow the rt4 "layered
	/// animation" rules (tween data is zeroed when not tweening).
	func resolve(_ pose: SeqPose) throws -> ResolvedPose? {
		let s = pose.seq
		guard pose.frame >= 0, pose.frame < s.frames.count else { return nil }
		let packed = s.frames[pose.frame]
		let set = try animFrameset(packed >> 16)
		let frame = packed & 0xFFFF
		var r = ResolvedPose(set: set, frame: frame, tweenSet: nil, tweenFrame: -1, delay: 0, step: 0, flag14: s.flag14, alpha: false, colour: false)
		if let set {
			r.alpha = set.isAlphaTransformedSafe(frame)
			r.colour = set.isColorTransformedSafe(frame)
		}
		if (s.tween || AnimSettings.applyTweening), pose.nextFrame != -1, pose.nextFrame < s.frames.count {
			r.delay = s.frameDelays[pose.frame]
			r.step = pose.step
			let np = s.frames[pose.nextFrame]
			r.tweenSet = try animFrameset(np >> 16)
			r.tweenFrame = np & 0xFFFF
			if let t = r.tweenSet {
				r.alpha = r.alpha || t.isAlphaTransformedSafe(r.tweenFrame)
				r.colour = r.colour || t.isColorTransformedSafe(r.tweenFrame)
			}
		}
		return r
	}
}

extension AnimFrameset {
	func isAlphaTransformedSafe(_ f: Int) -> Bool { f >= 0 && f < frames.count && (frames[f]?.transformsAlpha ?? false) }
	func isColorTransformedSafe(_ f: Int) -> Bool { f >= 0 && f < frames.count && (frames[f]?.transformsColor ?? false) }
	func frameSafe(_ f: Int) -> AnimFrame? { f >= 0 && f < frames.count ? frames[f] : nil }
}

// MARK: - skeletal transforms

extension SoftwareModel {
	@inline(__always) private static func r15(_ v: Int) -> Int { (v + 16384) >> 15 }

	/// Full-body ("whole model") mask: rt4 treats `part mask == 65535` as
	/// unfiltered and ignores any pose matrix.
	static let allParts = 65535

	/// rt4 `SoftwareModel.method4569` (unfiltered) and `method4577` (filtered by
	/// source mask and optional pose matrix) merged. `mask == nil` selects the
	/// unfiltered variant. `type`: 0 origin, 1 translate, 2 rotate, 3 scale,
	/// 5 alpha, 7 colour.
	func applyBoneTransform(type: Int, bones: [Int], x: Int, y: Int, z: Int, mask: Int?, matrix: [Int]?, pivot: inout AnimPivot) {
		guard let boneVertices else { return }
		let masked = mask != nil
		let m = mask ?? 0
		func vertexOK(_ v: Int) -> Bool {
			guard masked, let src = vertexSources else { return true }
			return (m & Int(src[v])) != 0
		}
		func triangleOK(_ t: Int) -> Bool {
			guard masked, let src = triangleSources else { return true }
			return (m & Int(src[t])) != 0
		}
		let M = masked ? matrix : nil

		switch type {
		case 0:
			var n = 0
			pivot.x = 0; pivot.y = 0; pivot.z = 0
			for b in bones where b < boneVertices.count {
				for v in boneVertices[b] where vertexOK(v) {
					pivot.x += vertexX[v]; pivot.y += vertexY[v]; pivot.z += vertexZ[v]
					n += 1
				}
			}
			if n > 0 {
				pivot.x = pivot.x / n + x
				pivot.y = pivot.y / n + y
				pivot.z = pivot.z / n + z
				if masked { pivot.matrixPending = true }
			} else {
				pivot.x = x; pivot.y = y; pivot.z = z
			}

		case 1:
			var dx = x, dy = y, dz = z
			if let M {
				dx = Self.r15(M[0] * x + M[1] * y + M[2] * z)
				dy = Self.r15(M[3] * x + M[4] * y + M[5] * z)
				dz = Self.r15(M[6] * x + M[7] * y + M[8] * z)
			}
			for b in bones where b < boneVertices.count {
				for v in boneVertices[b] where vertexOK(v) {
					vertexX[v] += dx; vertexY[v] += dy; vertexZ[v] += dz
				}
			}

		case 2:
			guard let M else {
				for b in bones where b < boneVertices.count {
					for v in boneVertices[b] where vertexOK(v) {
						var vx = vertexX[v] - pivot.x, vy = vertexY[v] - pivot.y, vz = vertexZ[v] - pivot.z
						if z != 0 {
							let s = MathTables.sin[z], c = MathTables.cos[z]
							let nx = (vy * s + vx * c + 32767) >> 16
							vy = (vy * c + 32767 - vx * s) >> 16
							vx = nx
						}
						if x != 0 {
							let s = MathTables.sin[x], c = MathTables.cos[x]
							let ny = (vy * c + 32767 - vz * s) >> 16
							vz = (vy * s + vz * c + 32767) >> 16
							vy = ny
						}
						if y != 0 {
							let s = MathTables.sin[y], c = MathTables.cos[y]
							let nx = (vz * s + vx * c + 32767) >> 16
							vz = (vz * c + 32767 - vx * s) >> 16
							vx = nx
						}
						vertexX[v] = vx + pivot.x; vertexY[v] = vy + pivot.y; vertexZ[v] = vz + pivot.z
					}
				}
				return
			}
			let tx = M[9], ty = M[10], tz = M[11], ox = M[12], oy = M[13], oz = M[14]
			if pivot.matrixPending {
				let nx = Self.r15(M[0] * pivot.x + M[3] * pivot.y + M[6] * pivot.z) + ox
				let ny = Self.r15(M[1] * pivot.x + M[4] * pivot.y + M[7] * pivot.z) + oy
				let nz = Self.r15(M[2] * pivot.x + M[5] * pivot.y + M[8] * pivot.z) + oz
				pivot.x = nx; pivot.y = ny; pivot.z = nz
				pivot.matrixPending = false
			}
			let c2 = MathTables.cos[x] >> 1, s2 = MathTables.sin[x] >> 1
			let c3 = MathTables.cos[y] >> 1, s3 = MathTables.sin[y] >> 1
			let c4 = MathTables.cos[z] >> 1, s4 = MathTables.sin[z] >> 1
			let t418 = Self.r15(s2 * c4)
			let t426 = Self.r15(s2 * s4)
			var R = [Int](repeating: 0, count: 9)
			R[0] = Self.r15(c3 * c4 + s3 * t426)
			R[1] = Self.r15(-c3 * s4 + s3 * t418)
			R[2] = Self.r15(s3 * c2)
			R[3] = Self.r15(c2 * s4)
			R[4] = Self.r15(c2 * c4)
			R[5] = -s2
			R[6] = Self.r15(-s3 * c4 + c3 * t426)
			R[7] = Self.r15(s3 * s4 + c3 * t418)
			R[8] = Self.r15(c3 * c2)
			let a = Self.r15(R[0] * -pivot.x + R[1] * -pivot.y + R[2] * -pivot.z)
			let b = Self.r15(R[3] * -pivot.x + R[4] * -pivot.y + R[5] * -pivot.z)
			let c = Self.r15(R[6] * -pivot.x + R[7] * -pivot.y + R[8] * -pivot.z)
			let cx = a + pivot.x, cy = b + pivot.y, cz = c + pivot.z
			var P = [Int](repeating: 0, count: 9)
			for i in 0..<3 {
				for j in 0..<3 {
					var sum = 0
					for k in 0..<3 { sum += R[i * 3 + k] * M[j * 3 + k] }
					P[i * 3 + j] = Self.r15(sum)
				}
			}
			let q0 = Self.r15(R[0] * ox + R[1] * oy + R[2] * oz) + cx
			let q1 = Self.r15(R[3] * ox + R[4] * oy + R[5] * oz) + cy
			let q2 = Self.r15(R[6] * ox + R[7] * oy + R[8] * oz) + cz
			var L = [Int](repeating: 0, count: 9)
			for i in 0..<3 {
				for j in 0..<3 {
					var sum = 0
					for k in 0..<3 { sum += M[i * 3 + k] * P[j + k * 3] }
					L[i * 3 + j] = Self.r15(sum)
				}
			}
			let d0 = Self.r15(M[0] * q0 + M[1] * q1 + M[2] * q2) + tx
			let d1 = Self.r15(M[3] * q0 + M[4] * q1 + M[5] * q2) + ty
			let d2 = Self.r15(M[6] * q0 + M[7] * q1 + M[8] * q2) + tz
			applyLinear(bones, L, d0, d1, d2, vertexOK)

		case 3:
			guard let M else {
				for b in bones where b < boneVertices.count {
					for v in boneVertices[b] where vertexOK(v) {
						vertexX[v] = ((vertexX[v] - pivot.x) * x) / 128 + pivot.x
						vertexY[v] = ((vertexY[v] - pivot.y) * y) / 128 + pivot.y
						vertexZ[v] = ((vertexZ[v] - pivot.z) * z) / 128 + pivot.z
					}
				}
				return
			}
			let tx = M[9], ty = M[10], tz = M[11], ox = M[12], oy = M[13], oz = M[14]
			if pivot.matrixPending {
				let nx = Self.r15(M[0] * pivot.x + M[3] * pivot.y + M[6] * pivot.z) + ox
				let ny = Self.r15(M[1] * pivot.x + M[4] * pivot.y + M[7] * pivot.z) + oy
				let nz = Self.r15(M[2] * pivot.x + M[5] * pivot.y + M[8] * pivot.z) + oz
				pivot.x = nx; pivot.y = ny; pivot.z = nz
				pivot.matrixPending = false
			}
			let sx = (x << 15) >> 7, sy = (y << 15) >> 7, sz = (z << 15) >> 7
			let l392 = Self.r15(sx * -pivot.x), l398 = Self.r15(sy * -pivot.y), l404 = Self.r15(sz * -pivot.z)
			let cx = l392 + pivot.x, cy = l398 + pivot.y, cz = l404 + pivot.z
			let S = [
				Self.r15(sx * M[0]), Self.r15(sx * M[3]), Self.r15(sx * M[6]),
				Self.r15(sy * M[1]), Self.r15(sy * M[4]), Self.r15(sy * M[7]),
				Self.r15(sz * M[2]), Self.r15(sz * M[5]), Self.r15(sz * M[8]),
			]
			let q0 = Self.r15(sx * ox) + cx
			let q1 = Self.r15(sy * oy) + cy
			let q2 = Self.r15(sz * oz) + cz
			var L = [Int](repeating: 0, count: 9)
			for i in 0..<3 {
				for j in 0..<3 {
					var sum = 0
					for k in 0..<3 { sum += M[i * 3 + k] * S[j + k * 3] }
					L[i * 3 + j] = Self.r15(sum)
				}
			}
			let d0 = Self.r15(M[0] * q0 + M[1] * q1 + M[2] * q2) + tx
			let d1 = Self.r15(M[3] * q0 + M[4] * q1 + M[5] * q2) + ty
			let d2 = Self.r15(M[6] * q0 + M[7] * q1 + M[8] * q2) + tz
			applyLinear(bones, L, d0, d1, d2, vertexOK)

		case 5:
			guard let boneTriangles, triangleAlpha != nil else { return }
			for b in bones where b < boneTriangles.count {
				for t in boneTriangles[b] where triangleOK(t) {
					let a = Int(UInt8(bitPattern: triangleAlpha![t])) + x * 8
					triangleAlpha![t] = Int8(truncatingIfNeeded: min(255, max(0, a)))
				}
			}

		case 7:
			guard let boneTriangles else { return }
			for b in bones where b < boneTriangles.count {
				for t in boneTriangles[b] where triangleOK(t) {
					let c = Int(UInt16(bitPattern: triangleColors[t]))
					var h = (c >> 10) & 0x3F, s = (c >> 7) & 0x7, l = c & 0x7F
					h = (h + x) & 0x3F
					s = min(7, max(0, s + y))
					l = min(127, max(0, l + z))
					triangleColors[t] = Int16(truncatingIfNeeded: (h << 10) | (s << 7) | l)
				}
				needsRelight = true
			}

		default: break
		}
	}

	/// `v' = L * v + d` over the selected bones (shared tail of the matrix rotate and scale paths).
	private func applyLinear(_ bones: [Int], _ L: [Int], _ d0: Int, _ d1: Int, _ d2: Int, _ ok: (Int) -> Bool) {
		guard let boneVertices else { return }
		for b in bones where b < boneVertices.count {
			for v in boneVertices[b] where ok(v) {
				let vx = vertexX[v], vy = vertexY[v], vz = vertexZ[v]
				let nx = Self.r15(L[0] * vx + L[1] * vy + L[2] * vz) + d0
				let ny = Self.r15(L[3] * vx + L[4] * vy + L[5] * vz) + d1
				let nz = Self.r15(L[6] * vx + L[7] * vy + L[8] * vz) + d2
				vertexX[v] = nx; vertexY[v] = ny; vertexZ[v] = nz
			}
		}
	}

	/// Effective part mask and dispatch for one base transform (`mask & parts[t]`
	/// then `method4569` when 65535, else `method4577`).
	private func applyTransform(_ base: AnimBase, _ t: Int, type: Int, x: Int, y: Int, z: Int, layerMask: Int, matrix: [Int]?, pivot: inout AnimPivot) {
		let part = layerMask & base.parts[t]
		if part == Self.allParts {
			applyBoneTransform(type: type, bones: base.bones[t], x: x, y: y, z: z, mask: nil, matrix: nil, pivot: &pivot)
		} else {
			applyBoneTransform(type: type, bones: base.bones[t], x: x, y: y, z: z, mask: part, matrix: matrix, pivot: &pivot)
		}
	}

	/// rt4 `Model.method4553`: apply `frame` (blended towards `next` by
	/// `step/delay` when given) to this model.
	///
	/// - groupFilter / groupMatch: rt4's `boolean[] framegroup` and the value a
	///   transform's membership must have to be applied (type 0 always applies).
	func applyFrame(base: AnimBase, frame: AnimFrame, next: AnimFrame?, step: Int, delay: Int, group: Set<Int>?, groupMatch: Bool, layerMask: Int, matrix: [Int]?, pivot: inout AnimPivot) {
		func allowed(_ t: Int) -> Bool {
			guard let group else { return true }
			return group.contains(t) == groupMatch || base.types[t] == 0
		}
		if next == nil || step == 0 || delay == 0 {
			for i in 0..<frame.length {
				let t = frame.indices[i]
				guard allowed(t) else { continue }
				let po = frame.prevOriginIndices[i]
				if po != -1 {
					applyTransform(base, po, type: 0, x: 0, y: 0, z: 0, layerMask: layerMask, matrix: matrix, pivot: &pivot)
				}
				applyTransform(base, t, type: base.types[t], x: frame.x[i], y: frame.y[i], z: frame.z[i], layerMask: layerMask, matrix: matrix, pivot: &pivot)
			}
			return
		}
		let next = next!
		var i1 = 0, i2 = 0
		for t in 0..<base.transforms {
			let has1 = i1 < frame.length && frame.indices[i1] == t
			let has2 = i2 < next.length && next.indices[i2] == t
			guard has1 || has2 else { continue }
			guard allowed(t) else {
				if has1 { i1 += 1 }
				if has2 { i2 += 1 }
				continue
			}
			let type = base.types[t]
			let def = type == 3 ? 128 : 0
			var ax = def, ay = def, az = def, ap = -1, af = 0
			if has1 {
				ax = frame.x[i1]; ay = frame.y[i1]; az = frame.z[i1]
				ap = frame.prevOriginIndices[i1]; af = frame.flags[i1]
				i1 += 1
			}
			var bx = def, by = def, bz = def, bp = -1, bf = 0
			if has2 {
				bx = next.x[i2]; by = next.y[i2]; bz = next.z[i2]
				bp = next.prevOriginIndices[i2]; bf = next.flags[i2]
				i2 += 1
			}
			var rx: Int, ry: Int, rz: Int
			if (af & 2) != 0 || (bf & 1) != 0 {
				rx = ax; ry = ay; rz = az
			} else if type == 2 {
				var dx = (bx - ax) & 0x7FF, dy = (by - ay) & 0x7FF, dz = (bz - az) & 0x7FF
				if dx >= 1024 { dx -= 2048 }
				if dy >= 1024 { dy -= 2048 }
				if dz >= 1024 { dz -= 2048 }
				rx = (ax + (dx * step) / delay) & 0x7FF
				ry = (ay + (dy * step) / delay) & 0x7FF
				rz = (az + (dz * step) / delay) & 0x7FF
			} else if type == 7 {
				var dx = (bx - ax) & 0x3F
				if dx >= 32 { dx -= 64 }
				rx = (ax + (dx * step) / delay) & 0x3F
				ry = ay + ((by - ay) * step) / delay
				rz = az + ((bz - az) * step) / delay
			} else {
				rx = ax + ((bx - ax) * step) / delay
				ry = ay + ((by - ay) * step) / delay
				rz = az + ((bz - az) * step) / delay
			}
			if ap != -1 {
				applyTransform(base, ap, type: 0, x: 0, y: 0, z: 0, layerMask: layerMask, matrix: matrix, pivot: &pivot)
			} else if bp != -1 {
				applyTransform(base, bp, type: 0, x: 0, y: 0, z: 0, layerMask: layerMask, matrix: matrix, pivot: &pivot)
			}
			applyTransform(base, t, type: type, x: rx, y: ry, z: rz, layerMask: layerMask, matrix: matrix, pivot: &pivot)
		}
	}

	/// rt4 `Model.method4551` + `method4557` wrapper: run `body` with a fresh
	/// pivot, then re-light if a colour transform ran and invalidate bounds.
	private func withAnimation(_ body: (inout AnimPivot) -> Void) {
		guard boneVertices != nil else { return }
		var pivot = AnimPivot()
		body(&pivot)
		if needsRelight { relightAfterColourChange(); needsRelight = false }
		boundsValid = false
	}

	private func resolveTween(_ set: AnimFrameset?, _ index: Int, base: AnimBase) -> AnimFrame? {
		guard let set, let f = set.frameSafe(index), f.base.id == base.id else { return nil }
		return f
	}

	/// rt4 `Model.method4558`: apply one animation frame, optionally blended
	/// towards a second frame. `step` is the already-decremented tween numerator.
	public func animate(_ set: AnimFrameset, frame: Int, tweenSet: AnimFrameset?, tweenFrame: Int, step: Int, delay: Int) {
		guard frame != -1, let f = set.frameSafe(frame) else { return }
		let next = resolveTween(tweenSet, tweenFrame, base: f.base)
		withAnimation { p in
			applyFrame(base: f.base, frame: f, next: next, step: step, delay: delay, group: nil, groupMatch: false, layerMask: Self.allParts, matrix: nil, pivot: &p)
		}
	}

	/// rt4 `Model.method4555`: apply one frame to a shadow model, using only the transforms whose
	/// `AnimBase.shadow` flag is set (the bones that move the feet), never tweened.
	public func animateShadow(_ set: AnimFrameset, frame: Int) {
		guard frame != -1, let f = set.frameSafe(frame) else { return }
		withAnimation { p in
			for i in 0..<f.length {
				let t = f.indices[i]
				guard f.base.shadow[t] else { continue }
				if f.prevOriginIndices[i] != -1 {
					applyTransform(f.base, f.prevOriginIndices[i], type: 0, x: 0, y: 0, z: 0, layerMask: Self.allParts, matrix: nil, pivot: &p)
				}
				applyTransform(f.base, t, type: f.base.types[t], x: f.x[i], y: f.y[i], z: f.z[i], layerMask: Self.allParts, matrix: nil, pivot: &p)
			}
		}
	}

	/// rt4 `Model.method4565`: apply one frame of a layered animation, limited to
	/// the model parts selected by `layerMask` (bit `1 << layer`), using the
	/// optional bone pose matrix.
	public func animateLayer(_ set: AnimFrameset, frame: Int, tweenSet: AnimFrameset?, tweenFrame: Int, step: Int, delay: Int, layerMask: Int, matrix: [Int]?) {
		guard frame != -1, let f = set.frameSafe(frame) else { return }
		let next = resolveTween(tweenSet, tweenFrame, base: f.base)
		withAnimation { p in
			applyFrame(base: f.base, frame: f, next: next, step: step, delay: delay, group: nil, groupMatch: false, layerMask: layerMask, matrix: matrix, pivot: &p)
		}
	}

	/// rt4 `Model.method4570`: two animations at once. `first` is applied to
	/// transforms outside `group`, `second` to those inside it (origin
	/// transforms apply to both). With no `group` or no second frame this is a
	/// plain `animate` of `first`.
	public func animateSplit(first: (set: AnimFrameset, frame: Int, tweenSet: AnimFrameset?, tweenFrame: Int, step: Int, delay: Int), second: (set: AnimFrameset, frame: Int, tweenSet: AnimFrameset?, tweenFrame: Int, step: Int, delay: Int)?, group: Set<Int>?) {
		guard first.frame != -1 else { return }
		guard let group, let second, second.frame != -1 else {
			animate(first.set, frame: first.frame, tweenSet: first.tweenSet, tweenFrame: first.tweenFrame, step: first.step, delay: first.delay)
			return
		}
		guard let f1 = first.set.frameSafe(first.frame), let f2 = second.set.frameSafe(second.frame) else { return }
		let n1 = resolveTween(first.tweenSet, first.tweenFrame, base: f1.base)
		let n2 = resolveTween(second.tweenSet, second.tweenFrame, base: f1.base)
		withAnimation { p in
			applyFrame(base: f1.base, frame: f1, next: n1, step: first.step, delay: first.delay, group: group, groupMatch: false, layerMask: Self.allParts, matrix: nil, pivot: &p)
			// rt4 interposes `method4569(0, new int[0], 0, 0, 0)`: resets the pivot.
			applyBoneTransform(type: 0, bones: [], x: 0, y: 0, z: 0, mask: nil, matrix: nil, pivot: &p)
			applyFrame(base: f1.base, frame: f2, next: n2, step: second.step, delay: second.delay, group: group, groupMatch: true, layerMask: Self.allParts, matrix: nil, pivot: &p)
		}
	}

	/// rt4 `SoftwareModel.method4581`: recompute lit colours of untextured
	/// Gouraud/flat triangles after a colour transform, keeping the stored
	/// lightness (bits 17+) and swapping in the new HSL16 hue/saturation.
	func relightAfterColourChange() {
		func mul(_ a: Int, _ b: Int) -> Int {
			let l = min(126, max(2, (b * (a & 0x7F)) >> 7))
			return (a & 0xFF80) + l
		}
		for i in 0..<triangleCount {
			if let tex = triangleTextures, tex[i] != -1 { continue }
			let c = Int(UInt16(bitPattern: triangleColors[i]))
			func relit(_ v: Int) -> Int {
				let hi = Int(Int32(truncatingIfNeeded: v)) & Int(Int32(bitPattern: 0xFFFE_0000))
				return hi | mul(c, hi >> 17)
			}
			if triangleColorC[i] == -1 {
				triangleColorA[i] = relit(triangleColorA[i])
			} else if triangleColorC[i] != -2 {
				triangleColorA[i] = relit(triangleColorA[i])
				triangleColorB[i] = relit(triangleColorB[i])
				triangleColorC[i] = relit(triangleColorC[i])
			}
		}
	}

	/// A copy prepared for animation (rt4 `method4572(shareAlpha, shareColors, ...)`).
	/// Swift arrays copy on write, so sharing is automatic; only a missing
	/// alpha array has to be created when an alpha transform will run.
	func animatableCopy(alpha: Bool) -> SoftwareModel {
		let m = copy()
		if alpha && m.triangleAlpha == nil { m.triangleAlpha = [Int8](repeating: 0, count: m.triangleCount) }
		return m
	}

	// MARK: pose driver

	/// The animation driver shared by `PlayerAppearance.method1954` and
	/// `NpcType.getBodyModel`: copy `base` and apply, in rt4's order, every
	/// layered animation (`layers[i]` limited to part bit `1 << i`, with its
	/// optional pose matrix), then the action and movement poses. When both
	/// play, the action drives transforms outside its frame group (rt4
	/// `framegroup`, "walkmerge") and the movement drives those inside it.
	///
	/// Returns `base` itself when nothing animates.
	public static func posed(_ base: SoftwareModel, store: ConfigStore, layers: [SeqPose?] = [], layerMatrices: [Int: [Int]] = [:], action: SeqPose?, movement: SeqPose?) throws -> SoftwareModel {
		var layerPoses: [(index: Int, pose: ResolvedPose)] = []
		var anyAlpha = false, anyColour = false
		var any = false
		for (i, l) in layers.enumerated() {
			guard let l, !l.seq.frames.isEmpty, let r = try store.resolve(l), r.set != nil else { continue }
			any = true
			layerPoses.append((i, r))
			anyAlpha = anyAlpha || r.alpha; anyColour = anyColour || r.colour
		}
		func take(_ p: SeqPose?) throws -> ResolvedPose? {
			guard let p, !p.seq.frames.isEmpty, let r = try store.resolve(p) else { return nil }
			anyAlpha = anyAlpha || r.alpha; anyColour = anyColour || r.colour
			return r
		}
		let a = try take(action), mv = try take(movement)
		if !any && action == nil && movement == nil { return base }
		_ = anyColour
		let m = base.animatableCopy(alpha: anyAlpha)

		for (i, r) in layerPoses {
			guard let set = r.set else { continue }
			m.animateLayer(set, frame: r.frame, tweenSet: r.tweenSet, tweenFrame: r.tweenFrame, step: r.step - 1, delay: r.delay, layerMask: 1 << i, matrix: layerMatrices[i])
		}
		let aa = a?.set != nil ? a : nil
		let mm = mv?.set != nil ? mv : nil
		func tup(_ r: ResolvedPose) -> (set: AnimFrameset, frame: Int, tweenSet: AnimFrameset?, tweenFrame: Int, step: Int, delay: Int) {
			(r.set!, r.frame, r.tweenSet, r.tweenFrame, r.step - 1, r.delay)
		}
		if let aa, let mm {
			m.animateSplit(first: tup(aa), second: tup(mm), group: action?.seq.frameGroup)
		} else if let aa {
			m.animateSplit(first: tup(aa), second: nil, group: nil)
		} else if let mm {
			m.animateSplit(first: tup(mm), second: nil, group: nil)
		}
		return m
	}
}
