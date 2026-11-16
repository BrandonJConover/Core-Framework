import Foundation

extension ActorModels {
	/// The lit, un-animated NPC model (rt4 `NpcTypeList.models` entry) and its BAS pose matrices.
	/// `type` must already be resolved from any multi-NPC (varbit) indirection.
	public func npcBody(_ type: NpcType) throws -> (model: SoftwareModel, matrices: [Int: [Int]])? {
		if let b = npcBodies[type.id] { return (b.model, b.matrices) }
		var parts: [RawModel?] = []
		for (i, id) in type.models.enumerated() {
			guard id != -1, let m = try store.rawModelCopy(id) else { parts.append(nil); continue }
			if let o = type.modelOffsets[i] { m.translate(o[0], o[1], o[2]) }
			parts.append(m)
		}
		let bas = type.basId != -1 ? try store.bas(type.basId) : nil
		let matrices = ActorSupport.applyBasPose(parts, bas: bas)
		let raw: RawModel
		if parts.count == 1 {
			guard let only = parts[0] else { return nil }
			raw = only
		} else {
			guard parts.contains(where: { $0 != nil }) else { return nil }
			raw = RawModel(merging: parts)
		}
		// `recolourPalette` (rt4 `recol_p`) indexes a client colour table that
		// is never filled in the software client; the plain pairs are applied.
		for (s, d) in type.recolours { raw.recolor(s, d) }
		for (s, d) in type.retextures { raw.retexture(s, d) }
		let model = raw.createModel(ambient: type.ambient + 64, contrast: type.contrast + 850, x: -30, y: -50, z: -30)
		npcBodies[type.id] = Body(model: model, matrices: matrices)
		return (model, matrices)
	}

	/// A posed, resized NPC model (rt4 `NpcType.getBodyModel`).
	public func npc(_ type: NpcType, layers: [SeqPose?] = [], action: SeqPose? = nil, movement: SeqPose? = nil) throws -> SoftwareModel? {
		guard let body = try npcBody(type) else { return nil }
		let posed = try SoftwareModel.posed(body.model, store: store, layers: layers, layerMatrices: body.matrices, action: action, movement: movement)
		if type.resizeXZ != 128 || type.resizeY != 128 {
			// resize mutates: never on the shared cached body.
			let m = posed === body.model ? posed.copy() : posed
			m.resize(type.resizeXZ, type.resizeY, type.resizeXZ)
			return m
		}
		return posed
	}
}
