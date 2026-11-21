extension ConfigStore {
	/// An item definition with rt4 `ObjTypeList.get`'s post-processing applied:
	/// noted items (`certtemplate`) take their look from the note template and
	/// their name and cost from the real item (`ObjType.generateCertificate`),
	/// and lent items (`lentTemplate`) take the template's look with the real
	/// item's identity (`ObjType.generateLent`). `ConfigStore.obj` returns the
	/// raw decoded definition; icons and ground models need this one.
	public func objResolved(_ id: Int) throws -> ObjType? {
		let key = "ObjResolved#\(id)"
		if let o = cache[key] as? ObjType { return o }
		guard var o = try obj(id) else { return nil }
		if o.certtemplate != -1, let link = try objResolved(o.certlink), let template = try objResolved(o.certtemplate) {
			o.name = link.name
			o.zoom2d = template.zoom2d
			o.recolours = template.recolours
			o.recolourPalette = template.recolourPalette
			o.recolourSources = template.recolourSources
			o.retextures = template.retextures
			o.xAngle2D = template.xAngle2D
			o.yAngle2D = template.yAngle2D
			o.zAngle2D = template.zAngle2D
			o.xOffset2D = template.xOffset2D
			o.yOffset2D = template.yOffset2D
			o.model = template.model
			o.cost = link.cost
			o.stackable = true
			o.members = link.members
		}
		if o.lentTemplate != -1, let link = try objResolved(o.lentLink), let template = try objResolved(o.lentTemplate) {
			o.recolourPalette = link.recolourPalette
			o.recolourSources = link.recolourSources
			o.recolours = link.recolours
			o.retextures = link.retextures
			o.model = template.model
			o.zoom2d = template.zoom2d
			o.xAngle2D = template.xAngle2D
			o.yAngle2D = template.yAngle2D
			o.zAngle2D = template.zAngle2D
			o.xOffset2D = template.xOffset2D
			o.yOffset2D = template.yOffset2D
			o.cost = 0
			o.team = link.team
			o.name = link.name
			o.members = link.members
			o.ops = link.ops
			o.iops = [link.iops[0], link.iops[1], link.iops[2], link.iops[3], "Discard"]
			o.params = link.params
		}
		cache[key] = o
		return o
	}

	/// rt4 stack-count variants (`ObjType.method1820`, and the same loop in
	/// `Inv.renderObjectSprite` / `ObjType.getModel`): for a count above 1 the
	/// last `countco` threshold the count reaches picks another item whose model
	/// shows a bigger pile (coins, arrows, runes).
	public func objForCount(_ type: ObjType, _ count: Int) throws -> ObjType {
		guard let objs = type.countObj, let counts = type.countCo, count > 1 else { return type }
		var pick = -1
		for i in 0..<10 where count >= counts[i] && counts[i] != 0 { pick = objs[i] }
		guard pick != -1, let variant = try objResolved(pick) else { return type }
		return variant
	}

	/// Builds the lit model rt4 uses for icons and ground items from an item's
	/// own model with its recolours and retextures (`ObjType.getInvModel` /
	/// `getModel`): lit with ambient + 64, contrast + 768 from direction
	/// (-50, -10, -50) and scaled by `resize`.
	func objModel(_ o: ObjType, textureAvailable: (Int) -> Bool) throws -> SoftwareModel? {
		guard let base = try rawModel(o.model) else { return nil }
		let raw = base.copy()
		if o.recolourPalette.isEmpty {
			for (src, dst) in o.recolours.sorted(by: { $0.key < $1.key }) { raw.recolor(src, dst) }
		} else {
			// rt4 `ObjType.getModel`: entry i with a palette byte takes its colour from the client palette (CS2 op 5401).
			for (i, src) in o.recolourSources.enumerated() {
				if i < o.recolourPalette.count {
					raw.recolor(src, recolourPalette(o.recolourPalette[i] & 0xFF))
				} else if let dst = o.recolours[src] {
					raw.recolor(src, dst)
				}
			}
		}
		for (src, dst) in o.retextures.sorted(by: { $0.key < $1.key }) { raw.retexture(src, dst) }
		let m = raw.createModel(ambient: o.ambient + 64, contrast: o.contrast + 768, x: -50, y: -10, z: -50, textureAvailable: textureAvailable)
		if o.resize[0] != 128 || o.resize[1] != 128 || o.resize[2] != 128 {
			m.resize(o.resize[0], o.resize[1], o.resize[2])
		}
		return m
	}

	/// rt4 `client.aShortArray87[index]`: the HSL colour CS2 stored for a palette index (0 until set).
	func recolourPalette(_ index: Int) -> Int { palette[index & 0xFF] }

	/// rt4 `ScriptRunner` op 5401: `client.aShortArray88[index] = rgbToHsl(rgb)`.
	public func setRecolourPalette(index: Int, hsl: Int) {
		palette[index & 0xFF] = hsl
	}
}
