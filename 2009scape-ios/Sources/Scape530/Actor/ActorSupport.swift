import Foundation

/// Shared helpers for building player and NPC models.
enum ActorSupport {
	@inline(__always) private static func r15(_ v: Int) -> Int { (v + 16384) >> 15 }

	/// rt4 per-slot pose matrix cached by `PlayerAppearance.method1954` and
	/// `NpcType.getBodyModel` (`anIntArrayArray19` / `anIntArrayArray28`),
	/// built from a `BasType.modelRotateTranslate` entry
	/// `[tx, ty, tz, rotX, rotY, rotZ]`. Layout (15 ints): `0...8` a 3x3
	/// rotation (fixed point, 1.0 = 32768), `9...11` the translation and
	/// `12...14` the translation expressed in the rotated frame.
	static func poseMatrix(_ v: [Int]) -> [Int] {
		let tx = v[0], ty = v[1], tz = v[2], ax = v[3], ay = v[4], az = v[5]
		var m = [Int](repeating: 0, count: 15)
		if ax == 0 && ay == 0 && az == 0 {
			m[12] = -tx; m[13] = -ty; m[14] = -tz
			m[0] = 32768; m[4] = 32768; m[8] = 32768
		} else {
			let c3 = MathTables.cos[ax] >> 1, s3 = MathTables.sin[ax] >> 1
			let c4 = MathTables.cos[ay] >> 1, s4 = MathTables.sin[ay] >> 1
			let c5 = MathTables.cos[az] >> 1, s5 = MathTables.sin[az] >> 1
			m[4] = r15(c3 * c5)
			m[5] = -s3
			m[3] = r15(s5 * c3)
			m[2] = r15(c3 * s4)
			m[8] = r15(c4 * c3)
			let t = r15(s5 * s3)
			m[0] = r15(s4 * t + c5 * c4)
			m[14] = r15(m[8] * -tz + -ty * m[5] + m[2] * -tx)
			m[6] = r15(c4 * t + c5 * -s4)
			let u = r15(c5 * s3)
			m[7] = r15(-s5 * -s4 + u * c4)
			m[1] = r15(s4 * u + c4 * -s5)
			m[12] = r15(-ty * m[3] + m[0] * -tx + -tz * m[6])
			m[13] = r15(-ty * m[4] + m[1] * -tx + -tz * m[7])
		}
		m[9] = tx; m[10] = ty; m[11] = tz
		return m
	}

	/// Apply the BAS model rotate/translate to the per-slot raw models and
	/// return the pose matrices (keyed by slot) for later layered animation.
	/// rt4: only slots that have a model get a matrix.
	static func applyBasPose(_ slots: [RawModel?], bas: BasType?) -> [Int: [Int]] {
		guard let bas else { return [:] }
		var matrices: [Int: [Int]] = [:]
		for (slot, v) in bas.modelRotateTranslate.sorted(by: { $0.key < $1.key }) {
			guard v.count >= 6, slot < slots.count, let model = slots[slot] else { continue }
			matrices[slot] = poseMatrix(v)
			if v[3] != 0 || v[4] != 0 || v[5] != 0 { model.rotateAngles(x: v[3], y: v[4], z: v[5]) }
			if v[0] != 0 || v[1] != 0 || v[2] != 0 { model.translate(v[0], v[1], v[2]) }
		}
		return matrices
	}
}

extension ConfigStore {
	/// A private, mutable copy of a cached raw model (rt4 `RawModel.create` returns a fresh one each time).
	func rawModelCopy(_ id: Int) throws -> RawModel? { try rawModel(id)?.copy() }

	/// rt4 `IdkTypeList.count`: capacity of the identity-kit group.
	public func idkCount() throws -> Int {
		try index(Archive.configs).groupCapacities[ConfigGroup.idk]
	}
}
