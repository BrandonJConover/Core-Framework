import Foundation

extension SoftwareModel {
	/// rt4 `SoftwareModel.method4552`: turn 180 degrees about the vertical axis.
	func rotate180() {
		for v in 0..<vertexCount { vertexX[v] = -vertexX[v]; vertexZ[v] = -vertexZ[v] }
		boundsValid = false
	}

	/// rt4 `SoftwareModel.method4578`: quarter turn the other way from `rotateCounterClockwise`.
	func rotateClockwise() {
		for v in 0..<vertexCount { let z = vertexZ[v]; vertexZ[v] = vertexX[v]; vertexX[v] = -z }
		boundsValid = false
	}
}

extension ConfigStore {
	/// The lit, un-animated model of a spot animation (rt4 `SpotAnimTypeList.models` entry): the raw
	/// model recoloured and lit with `ambient + 64`, `contrast + 850`.
	func spotAnimBody(_ t: SpotAnimType) throws -> SoftwareModel? {
		let key = "spotanim-body#\(t.id)"
		if let m = cache[key] as? SoftwareModel { return m }
		guard let raw = try rawModelCopy(t.model) else { return nil }
		for (s, d) in t.recolours { raw.recolor(s, d) }
		for (s, d) in t.retextures { raw.retexture(s, d) }
		let model = raw.createModel(ambient: t.ambient + 64, contrast: t.contrast + 850, x: -30, y: -50, z: -30)
		cache[key] = model
		return model
	}

	/// rt4 `SpotAnimType.constructModel(nextFrame, step, frame)`: the body posed at `frame` of the
	/// graphic's sequence (tweening towards `nextFrame`), resized and turned. A private copy: callers
	/// may translate it.
	func spotAnimModel(_ t: SpotAnimType, frame: Int, nextFrame: Int, step: Int) throws -> SoftwareModel? {
		guard let body = try spotAnimBody(t) else { return nil }
		var model = body
		if t.seq != -1, frame != -1, let seq = try self.seq(t.seq), !seq.frames.isEmpty {
			model = try SoftwareModel.posed(body, store: self, action: SeqPose(seq: seq, frame: frame, nextFrame: nextFrame, step: step), movement: nil)
		}
		if model === body { model = body.copy() }
		if t.resizeXZ != 128 || t.resizeY != 128 { model.resize(t.resizeXZ, t.resizeY, t.resizeXZ) }
		switch t.angle {
		case 90: model.rotateCounterClockwise()
		case 180: model.rotate180()
		case 270: model.rotateClockwise()
		default: break
		}
		return model
	}
}
