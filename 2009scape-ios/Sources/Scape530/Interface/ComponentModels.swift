import Foundation

/// Playback state of a type-6 component's animation (rt4 `Component.anInt510` / `anInt500` / `anInt496`):
/// the current frame index, the client cycles spent on it, and the next frame index used for tweening.
public struct ModelAnim: Equatable {
	public var frame = 0
	public var cycles = 0
	public var nextFrame = 1
	public init() {}
}

/// Builds and draws the models of type-6 interface components (rt4 `Component.method488` and the type-6
/// branch of `Cs1ScriptRunner.renderComponent`): plain models, npc and player heads (chat heads), items,
/// players by index, and npc bodies. Not thread-safe; use it from the frame thread.
public final class ComponentModels {
	let store: ConfigStore
	public let actors: ActorModels
	private var rasteriser: Rasteriser3D?
	/// Rasteriser gamma for models drawn into interfaces (rt4 `Rasteriser.setBrightness`).
	public var brightness: Float = 0.8 {
		didSet { if brightness != oldValue { rasteriser = nil } }
	}
	private var rasterWidth = 0, rasterHeight = 0
	private weak var icons: ItemIcons?

	private var plain: [Int: SoftwareModel] = [:]
	private var npcHeads: [Int: SoftwareModel] = [:]
	private var playerHeads: [PlayerLook: SoftwareModel] = [:]

	/// The local player's look (rt4 `PlayerList.self.appearance`), for modelType 3 and 5.
	public var selfLook: () -> PlayerLook? = { nil }
	/// Another player's look by player index (modelType 5).
	public var playerLook: (Int) -> PlayerLook? = { _ in nil }
	/// rt4 `NpcType.getMultiNpc`: the variant currently shown for a multi-npc.
	public var resolveNpc: (NpcType) -> NpcType? = { $0 }

	public init(store: ConfigStore, icons: ItemIcons? = nil) {
		self.store = store
		self.icons = icons
		actors = ActorModels(store: store)
	}

	public func clearCache() {
		plain.removeAll(); npcHeads.removeAll(); playerHeads.removeAll(); actors.clearCache()
	}

	// MARK: model building

	/// rt4 `NpcType.getHeadModel` (before animation): the npc's head models merged, recoloured and lit with
	/// ambient 64, contrast 768 and light (-50, -10, -50). Nil when the npc has no head models.
	public func npcHead(_ type: NpcType) throws -> SoftwareModel? {
		guard let t = resolveNpc(type), !t.headModels.isEmpty else { return nil }
		if let m = npcHeads[t.id] { return m }
		var parts: [RawModel?] = []
		for id in t.headModels { parts.append(try store.rawModelCopy(id)) }
		let raw: RawModel
		if parts.count == 1 {
			guard let only = parts[0] else { return nil }
			raw = only
		} else {
			raw = RawModel(merging: parts)
		}
		for (s, d) in t.recolours { raw.recolor(s, d) }
		for (s, d) in t.retextures { raw.retexture(s, d) }
		let m = raw.createModel(ambient: 64, contrast: 768, x: -50, y: -10, z: -50)
		npcHeads[t.id] = m
		return m
	}

	/// rt4 `PlayerAppearance.method1956` (before animation): the worn items' head models and the identity kit
	/// heads merged and recoloured with the appearance colours. A transformed player shows the npc's head.
	public func playerHead(_ look: PlayerLook) throws -> SoftwareModel? {
		if look.npcId != -1 {
			guard let t = try store.npc(look.npcId) else { return nil }
			return try npcHead(t)
		}
		if let m = playerHeads[look] { return m }
		var parts: [RawModel] = []
		for v in look.slots {
			if (v & 0x4000_0000) != 0 {
				if let obj = try store.obj(v & 0x3FFF_FFFF), let h = try objHead(obj, female: look.female) { parts.append(h) }
			} else if (v & Int(Int32.min)) != 0 {
				if let kit = try store.idk(v & 0x3FFF_FFFF), let h = try kitHead(kit) { parts.append(h) }
			}
		}
		let merged = RawModel(merging: parts)
		for i in 0..<5 {
			let c = look.colours[i]
			if BodyColours.destinationBody[i].count > c { merged.recolor(BodyColours.sourceBody[i], BodyColours.destinationBody[i][c]) }
			if BodyColours.destinationSkin[i].count > c { merged.recolor(BodyColours.sourceSkin[i], BodyColours.destinationSkin[i][c]) }
		}
		let m = merged.createModel(ambient: 64, contrast: 768, x: -50, y: -10, z: -50)
		if playerHeads.count > 64 { playerHeads.removeAll() }
		playerHeads[look] = m
		return m
	}

	/// rt4 `ObjType.getHeadModel(female)`.
	func objHead(_ o: ObjType, female: Bool) throws -> RawModel? {
		let h1 = female ? o.womanhead : o.manhead
		let h2 = female ? o.womanhead2 : o.manhead2
		guard h1 != -1, var model = try store.rawModelCopy(h1) else { return nil }
		if h2 != -1, let m2 = try store.rawModelCopy(h2) { model = RawModel(merging: [model, m2]) }
		for (s, d) in o.recolours { model.recolor(s, d) }
		for (s, d) in o.retextures { model.retexture(s, d) }
		return model
	}

	/// rt4 `IdkType.getHeadModel`.
	func kitHead(_ k: IdkType) throws -> RawModel? {
		var parts: [RawModel] = []
		for id in k.headModels where id != -1 { if let m = try store.rawModelCopy(id) { parts.append(m) } }
		guard !parts.isEmpty else { return nil }
		let model = parts.count == 1 ? parts[0] : RawModel(merging: parts)
		for (s, d) in k.recolours { model.recolor(s, d) }
		for (s, d) in k.retextures { model.retexture(s, d) }
		return model
	}

	/// modelType 1: a cache model lit like rt4 `RawModel.createModel(64, 768, -50, -10, -50)`.
	func plainModel(_ id: Int) throws -> SoftwareModel? {
		if let m = plain[id] { return m }
		guard let raw = try store.rawModelCopy(id) else { return nil }
		let m = raw.createModel(ambient: 64, contrast: 768, x: -50, y: -10, z: -50)
		if plain.count > 128 { plain.removeAll() }
		plain[id] = m
		return m
	}

	/// The model a component shows right now (rt4 `Component.method488`), animated by its sequence.
	/// `anim` is the component's `ModelAnim`. Nil when there is nothing to draw (or it cannot be built).
	public func model(for c: Component, anim: ModelAnim, seqOverride: Int? = nil) throws -> SoftwareModel? {
		let seqId = seqOverride ?? c.modelSeqId
		let seq = seqId == -1 ? nil : try store.seq(seqId)
		let pose = seq.map { SeqPose(seq: $0, frame: anim.frame, nextFrame: anim.nextFrame, step: anim.cycles) }
		func animate(_ m: SoftwareModel?) throws -> SoftwareModel? {
			guard let m else { return nil }
			guard let pose, !pose.seq.frames.isEmpty else { return m }
			return try SoftwareModel.posed(m, store: store, action: pose, movement: nil)
		}

		if c.objId != -1 {
			guard let base = try store.objResolved(c.objId) else { return nil }
			let o = try store.objForCount(base, c.objCount)
			let icons = self.icons
			return try animate(try store.objModel(o, textureAvailable: { icons?.textureAvailable($0) ?? true }))
		}
		switch c.modelType {
		case 1:
			guard c.modelId != -1 else { return nil }
			return try animate(try plainModel(c.modelId))
		case 2:
			guard c.modelId != -1, let t = try store.npc(c.modelId) else { return nil }
			return try animate(try npcHead(t))
		case 3:
			guard let look = selfLook() else { return nil }
			return try animate(try playerHead(look))
		case 4:
			guard c.modelId != -1, let o = try store.objResolved(c.modelId) else { return nil }
			let icons = self.icons
			return try animate(try store.objModel(o, textureAvailable: { icons?.textureAvailable($0) ?? true }))
		case 5:
			// rt4 checks the name hash too; the index (low 11 bits, 2047 for self) is all this port keeps.
			var look: PlayerLook?
			if c.modelId == -1 {
				look = try PlayerLook.defaultLook(store: store, female: false)
			} else {
				let index = c.modelId & 0x7FF
				look = index == 2047 ? selfLook() : playerLook(index)
			}
			guard let look else { return nil }
			let action = pose
			return try actors.player(look, action: action, movement: nil)
		case 6:
			guard c.modelId != -1, let t = try store.npc(c.modelId), let r = resolveNpc(t) else { return nil }
			return try actors.npc(r, action: pose)
		case 7:
			// rt4 `PlayerAppearance.method1946`: three identity-kit heads in the local player's colours.
			guard let me = selfLook() else { return nil }
			let kits = [(c.modelId >> 16) & 0xFFFF, c.modelId & 0xFFFF, c.modelExtra]
			let look = PlayerLook(female: me.female, slots: kits.map { Int(Int32.min) | $0 }, colours: me.colours, basId: -1)
			return try animate(try playerHead(look))
		default:
			return nil
		}
	}

	// MARK: drawing

	private func raster(width: Int, height: Int) -> Rasteriser3D {
		if let r = rasteriser, rasterWidth >= width, rasterHeight >= height { return r }
		let w = max(rasterWidth, width), h = max(rasterHeight, height)
		let r = Rasteriser3D(width: w, height: h)
		r.unpackTextures(icons?.textureStore())
		r.setBrightness(brightness, jitter: false)
		rasteriser = r
		rasterWidth = w
		rasterHeight = h
		return r
	}

	/// The type-6 branch of rt4 `Cs1ScriptRunner.renderComponent`: sets the projection centre at the component's
	/// centre shifted by its aspect-scaled offsets, places the model with the component's rotation and zoom
	/// (orthographically for `modelOrtho` in if3), and blits what was drawn onto `raster`.
	public func draw(_ c: Component, anim: ModelAnim, x: Int, y: Int, w: Int, h: Int, into target: inout Raster) {
		guard w > 0, h > 0, w <= 2048, h <= 2048 else { return }
		guard let model = try? model(for: c, anim: anim) else { return }
		let xScale = c.aspectWidth > 0 ? (w << 8) / c.aspectWidth : 256
		let yScale = c.aspectHeight > 0 ? (h << 8) / c.aspectHeight : 256
		let r = raster(width: w, height: h)
		r.setClip(0, 0, w, h)
		r.prepare()
		// rt4 `Rasteriser.setBounds(centerX, centerY)` in component-local pixels.
		r.centerX = Int32(w / 2 + ((xScale * c.screenShiftX) >> 8))
		r.centerY = Int32(h / 2 + ((yScale * c.screenShiftY) >> 8))
		r.screenLowerX = -r.centerX
		r.screenUpperX = Int32(w) - r.centerX
		r.screenLowerY = -r.centerY
		r.screenUpperY = Int32(h) - r.centerY
		for row in 0..<h { (r.px + row * Int(r.stride)).update(repeating: 0, count: w) }

		model.ensureBounds()
		let memory = c.objId != -1 ? -model.minY / 2 : 0
		let sin = (MathTables.sin[c.modelXAngle & 2047] * c.modelZoom) >> 16
		let cos = (MathTables.cos[c.modelXAngle & 2047] * c.modelZoom) >> 16
		if !c.if3 {
			model.renderAtOrigin(r, yAngle: c.modelYAngle, zAngle: 0, xAngle: c.modelXAngle, x: 0, y: sin, z: cos)
		} else if c.modelOrtho {
			model.renderOrthographic(r, yAngle: c.modelYAngle, zAngle: c.modelYOffset, xAngle: c.modelXAngle, x: c.modelXOffset, y: c.modelZOffset + memory + sin, z: cos + c.modelZOffset, zoom: c.modelZoom)
		} else {
			model.renderAtOrigin(r, yAngle: c.modelYAngle, zAngle: c.modelYOffset, xAngle: c.modelXAngle, x: c.modelXOffset, y: c.modelZOffset + sin + memory, z: cos + c.modelZOffset)
		}

		let stride = Int(r.stride)
		let y0 = max(y, target.clipTop), y1 = min(y + h, target.clipBottom)
		let x0 = max(x, target.clipLeft), x1 = min(x + w, target.clipRight)
		guard x0 < x1, y0 < y1 else { return }
		for dy in y0..<y1 {
			let src = r.px + (dy - y) * stride - x
			let row = dy * target.width
			for dx in x0..<x1 {
				let p = src[dx]
				if p != 0 { target.pixels[row + dx] = 0xFF00_0000 | UInt32(bitPattern: p) }
			}
		}
	}
}
