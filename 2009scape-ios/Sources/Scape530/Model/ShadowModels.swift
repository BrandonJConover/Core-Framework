import Foundation

/// Port of rt4 `ShadowModelList` (client!di `SHADOWS`, `method1043`): the soft dark disc drawn under
/// characters when `Preferences.characterShadowsOn` is set. rt4 draws it in the software renderer
/// too (`Npc.render` / `Player.render`), so this is the SD path, not a GL-only effect.
final class ShadowModelList {
	/// rt4 `SoftLruHashTable(32)`; here simply emptied when full.
	private var cache: [Int: SoftwareModel] = [:]

	func clear() { cache.removeAll() }

	/// The disc model for a size and colour pair: three rings of `9 + 3 * (size - 1)` (21 above 4) points
	/// with the colour and alpha blended from the inner to the outer ring.
	private func disc(modifier1: Int, colour2: Int, colour1: Int, size: Int, modifier2: Int, x: Int, z: Int) -> SoftwareModel {
		// rt4 keys on `(long) arg4 << 48 + (int) (size + (modifier1 << 16) + (modifier2 << 24)) + (long) arg6 << 32`.
		let low = Int(Int32(truncatingIfNeeded: size &+ (modifier1 << 16) &+ (modifier2 << 24)))
		let key = (colour2 << 48) &+ low &+ (colour1 << 32)
		if let m = cache[key] { return m }
		let n: Int
		switch size {
		case 1: n = 9
		case 2: n = 12
		case 3: n = 15
		case 4: n = 18
		default: n = 21
		}
		let radii = [64, 96, 128]
		let raw = RawModel(vertexCapacity: n * 3 + 1, triangleCapacity: n * 3 * 2 - n)
		let centre = raw.addGroundVertex(0, 0)
		var ring = [[Int]](repeating: [Int](repeating: 0, count: n), count: 3)
		for r in 0..<3 {
			let radius = radii[r]
			for j in 0..<n {
				let angle = (j << 11) / n
				// rt4 adds the position before the shift, `(z + cos * r) >> 16`.
				let vz = (z + MathTables.cos[angle] * radius) >> 16
				let vx = (x + MathTables.sin[angle] * radius) >> 16
				ring[r][j] = raw.addGroundVertex(vx, vz)
			}
		}
		for r in 0..<3 {
			let outer = (r * 256 + 128) / 3
			let inner = 256 - outer
			let alpha = (modifier2 * outer + modifier1 * inner) >> 8
			let colour = ((((colour1 & 0x7F) * inner + (colour2 & 0x7F) * outer) & 0x7F00)
				+ ((inner * (colour1 & 0x380) + outer * (colour2 & 0x380)) & 0x38000)
				+ ((outer * (colour2 & 0xFC00) + (colour1 & 0xFC00) * inner) & 0xFC0000)) >> 8
			for j in 0..<n {
				let next = (j + 1) % n
				if r == 0 {
					raw.addTriangle(centre, ring[0][next], ring[0][j], color: colour, alpha: alpha)
				} else {
					raw.addTriangle(ring[r - 1][j], ring[r - 1][next], ring[r][next], color: colour, alpha: alpha)
					raw.addTriangle(ring[r - 1][j], ring[r][next], ring[r][j], color: colour, alpha: alpha)
				}
			}
		}
		let m = raw.createModel(ambient: 64, contrast: 768, x: -50, y: -10, z: -50)
		if cache.count >= 32 { cache.removeAll() }
		cache[key] = m
		return m
	}

	/// rt4 `ShadowModelList.method1043`: the shadow of `body` (a character `size` tiles wide, facing
	/// `orientation`, at fine position `xFine`/`zFine` on ground height `groundY`), cut to the body's
	/// footprint, posed with the shadow bones of the current animation frame and laid on the terrain.
	/// `stretches` is the animation's `aBoolean171` (the footprint grows 128 towards the facing).
	func shadow(store: ConfigStore, modifier1: Int, stretches: Bool, seq: SeqType?, xFine: Int, colour2: Int, zFine: Int,
	            colour1: Int, size: Int, body: SoftwareModel, orientation: Int, frame: Int, groundY: Int, modifier2: Int,
	            height: (Int, Int) -> Int) -> SoftwareModel {
		let base = disc(modifier1: modifier1, colour2: colour2, colour1: colour1, size: size, modifier2: modifier2, x: xFine, z: zFine)
		let half = size * 64 - 1
		var minLimitX = -half, minLimitZ = -half, maxLimitX = half, maxLimitZ = half
		body.ensureBounds()
		var minX = body.minX, maxX = body.maxX, minZ = body.minZ, maxZ = body.maxZ
		var set: AnimFrameset?
		var frame = frame
		if let seq, frame >= 0, frame < seq.frames.count {
			let packed = seq.frames[frame]
			set = (try? store.animFrameset(packed >> 16)) ?? nil
			frame = packed & 0xFFFF
		}
		if stretches {
			if orientation > 1664 || orientation < 384 { minLimitZ -= 128 }
			if orientation > 1152 && orientation < 1920 { maxLimitX = half + 128 }
			if orientation > 640 && orientation < 1408 { maxLimitZ = half + 128 }
			if orientation > 128 && orientation < 896 { minLimitX -= 128 }
		}
		if maxLimitZ < maxZ { maxZ = maxLimitZ }
		if minLimitX > minX { minX = minLimitX }
		if minZ < minLimitZ { minZ = minLimitZ }
		if maxLimitX < maxX { maxX = maxLimitX }

		let m: SoftwareModel
		if let set {
			m = base.animatableCopy(alpha: set.isAlphaTransformedSafe(frame))
			m.resize((maxX - minX) / 2, 128, (maxZ - minZ) / 2)
			m.translate((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
			m.animateShadow(set, frame: frame)
		} else {
			m = base.copy()
			m.resize((maxX - minX) / 2, 128, (maxZ - minZ) / 2)
			m.translate((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
		}
		if orientation != 0 { m.rotateY(orientation) }
		// Software branch: lay the disc on the terrain when the ground under its corners is not level.
		if height(xFine + minX, zFine + minZ) != groundY || height(xFine + maxX, zFine + maxZ) != groundY {
			for v in 0..<m.vertexCount {
				m.vertexY[v] += height(xFine + m.vertexX[v], zFine + m.vertexZ[v]) - groundY
			}
			m.boundsValid = false
		}
		return m
	}
}
