import Foundation

/// Everything that decides how a player's body looks: the decoded appearance
/// block plus gender. rt4 keeps these in `PlayerAppearance` (not to be confused
/// with `Net.PlayerAppearance`, the wire block this is built from).
public struct PlayerLook: Hashable {
	public var female: Bool
	/// 12 body slots: 0 empty, `0x40000000 | objId` worn object,
	/// `Int32.min | kitId` identity kit (see `Net.PlayerAppearance.slots`).
	public var slots: [Int]
	public var colours: [Int]
	public var basId: Int
	/// Transmogrified NPC id or -1.
	public var npcId: Int

	public init(female: Bool, slots: [Int], colours: [Int], basId: Int, npcId: Int = -1) {
		self.female = female; self.slots = slots; self.colours = colours; self.basId = basId; self.npcId = npcId
	}

	public init(_ a: PlayerAppearance) {
		self.init(female: a.female, slots: a.slots, colours: a.colours, basId: a.basId, npcId: a.npcId)
	}

	/// rt4 `PlayerAppearance.BASE_PART_MAP`: kit feature index to body slot.
	static let basePartMap = [8, 11, 4, 6, 9, 7, 10, 0]
	static let maleFeatures = [0, 1, 2, 3, 4, 5, 6, 14]
	static let femaleFeatures = [7, 8, 9, 10, 11, 12, 13, 15]

	/// rt4 `PlayerAppearance.set` with a null identikit: the first enabled kit
	/// for each body feature (the character-design default). `basId` -1.
	public static func defaultLook(store: ConfigStore, female: Bool, colours: [Int] = [0, 0, 0, 0, 0], basId: Int = -1) throws -> PlayerLook {
		var slots = [Int](repeating: 0, count: 12)
		let count = try store.idkCount()
		for i in 0..<8 {
			for id in 0..<count {
				guard let kit = try store.idk(id), !kit.disabled else { continue }
				if kit.bodyPart == (female ? femaleFeatures[i] : maleFeatures[i]) {
					slots[basePartMap[i]] = Int(Int32.min) | id
					break
				}
			}
		}
		return PlayerLook(female: female, slots: slots, colours: colours, basId: basId)
	}
}

extension ConfigStore {
	/// rt4 `IdkType.getBodyModel`: the kit's models merged and recoloured; nil when it has none.
	func idkBodyModel(_ kit: IdkType) throws -> RawModel? {
		guard !kit.models.isEmpty else { return nil }
		var parts: [RawModel?] = []
		for id in kit.models { parts.append(try rawModelCopy(id)) }
		let model: RawModel
		if parts.count == 1 {
			guard let only = parts[0] else { return nil }
			model = only
		} else {
			model = RawModel(merging: parts)
		}
		for (s, d) in kit.recolours { model.recolor(s, d) }
		for (s, d) in kit.retextures { model.retexture(s, d) }
		return model
	}

	/// rt4 `ObjType.getBodyModel(female)`: the worn model(s) of an item; nil when it has none.
	func wornModel(_ obj: ObjType, female: Bool) throws -> RawModel? {
		let w1 = female ? obj.womanwear : obj.manwear
		let w2 = female ? obj.womanwear2 : obj.manwear2
		let w3 = female ? obj.womanwear3 : obj.manwear3
		guard w1 != -1 else { return nil }
		var model = try rawModelCopy(w1)
		if w2 != -1 {
			let m2 = try rawModelCopy(w2)
			if w3 == -1 {
				model = RawModel(merging: [model, m2])
			} else {
				model = RawModel(merging: [model, m2, try rawModelCopy(w3)])
			}
		}
		guard let model else { return nil }
		let off = female ? obj.womanWearOffset : obj.manWearOffset
		if off[0] != 0 || off[1] != 0 || off[2] != 0 { model.translate(off[0], off[1], off[2]) }
		for (s, d) in obj.recolours { model.recolor(s, d) }
		for (s, d) in obj.retextures { model.retexture(s, d) }
		return model
	}
}

/// Builds, caches and animates actor (player and NPC) models. Port of the
/// model side of rt4 `PlayerAppearance.method1954` and `NpcType.getBodyModel`.
public final class ActorModels {
	public let store: ConfigStore

	struct BodyKey: Hashable { var slots: [Int]; var colours: [Int]; var female: Bool; var basId: Int }
	struct Body { var model: SoftwareModel; var matrices: [Int: [Int]] }

	var bodies: [BodyKey: Body] = [:]
	var npcBodies: [Int: Body] = [:]
	/// rt4 `bodyModels` is an LRU of 260 entries; this drops everything at the limit.
	public var bodyCacheLimit = 260

	public init(store: ConfigStore) { self.store = store }

	public func clearCache() { bodies.removeAll(); npcBodies.removeAll() }

	/// rt4 applies a weapon animation's `mainhand` / `offhand` item swap to the
	/// kit slots 5 / 3 before building (65535 clears the slot).
	static func overrideHands(_ slots: [Int], action: SeqType?) -> [Int] {
		guard let s = action, s.mainhand >= 0 || s.offhand >= 0 else { return slots }
		var out = slots
		if s.mainhand >= 0 { out[5] = s.mainhand == 65535 ? 0 : (s.mainhand | 0x4000_0000) }
		if s.offhand >= 0 { out[3] = s.offhand == 65535 ? 0 : (s.offhand | 0x4000_0000) }
		return out
	}

	/// The lit, un-animated body (rt4's `bodyModels` entry) and the pose
	/// matrices from the BAS. Nil when the look has no models at all.
	public func playerBody(_ look: PlayerLook, action: SeqType? = nil) throws -> (model: SoftwareModel, matrices: [Int: [Int]])? {
		let slots = Self.overrideHands(look.slots, action: action)
		let key = BodyKey(slots: slots, colours: look.colours, female: look.female, basId: look.basId)
		if let b = bodies[key] { return (b.model, b.matrices) }

		var parts = [RawModel?](repeating: nil, count: 12)
		for i in 0..<12 {
			let v = slots[i]
			if (v & 0x4000_0000) != 0 {
				if let obj = try store.obj(v & 0x3FFF_FFFF) { parts[i] = try store.wornModel(obj, female: look.female) }
			} else if (v & Int(Int32.min)) != 0 {
				if let kit = try store.idk(v & 0x3FFF_FFFF) { parts[i] = try store.idkBodyModel(kit) }
			}
		}
		let bas = look.basId != -1 ? try store.bas(look.basId) : nil
		let matrices = ActorSupport.applyBasPose(parts, bas: bas)
		guard parts.contains(where: { $0 != nil }) else { return nil }
		let merged = RawModel(merging: parts)
		for i in 0..<5 {
			let c = look.colours[i]
			if BodyColours.destinationBody[i].count > c { merged.recolor(BodyColours.sourceBody[i], BodyColours.destinationBody[i][c]) }
			if BodyColours.destinationSkin[i].count > c { merged.recolor(BodyColours.sourceSkin[i], BodyColours.destinationSkin[i][c]) }
		}
		let model = merged.createModel(ambient: 64, contrast: 850, x: -30, y: -50, z: -30)
		if bodies.count >= bodyCacheLimit { bodies.removeAll() }
		bodies[key] = Body(model: model, matrices: matrices)
		return (model, matrices)
	}

	/// A posed player model. `action` is the current animation (rt4 `seqId`),
	/// `movement` the walk/run/idle animation, `layers` the layered animations.
	/// A transmogrified player (`npcId != -1`) is built as that NPC.
	public func player(_ look: PlayerLook, layers: [SeqPose?] = [], action: SeqPose?, movement: SeqPose?) throws -> SoftwareModel? {
		if look.npcId != -1 {
			guard let t = try store.npc(look.npcId) else { return nil }
			return try npc(t, layers: layers, action: action, movement: movement)
		}
		guard let body = try playerBody(look, action: action?.seq) else { return nil }
		return try SoftwareModel.posed(body.model, store: store, layers: layers, layerMatrices: body.matrices, action: action, movement: movement)
	}
}
