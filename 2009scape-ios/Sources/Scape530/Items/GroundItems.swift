import Foundation

/// Models of items lying on the ground, cached per (item type, count variant) like rt4's `ObjTypeList.models`.
final class GroundItemModels {
	private let store: ConfigStore
	private var cache: [Int: SoftwareModel] = [:]
	private var missing: Set<Int> = []

	init(store: ConfigStore) { self.store = store }

	/// rt4 `ObjType.getModel(.., count, ..)`: the count variant's model, lit as for icons and resized,
	/// marked pickable so ground items can be tapped.
	func model(type: Int, count: Int, textureAvailable: (Int) -> Bool) -> SoftwareModel? {
		guard let base = (try? store.objResolved(type)) ?? nil, let o = try? store.objForCount(base, count) else { return nil }
		if let m = cache[o.id] { return m }
		if missing.contains(o.id) { return nil }
		guard let m = (try? store.objModel(o, textureAvailable: textureAvailable)) ?? nil else {
			missing.insert(o.id)
			return nil
		}
		m.pickable = true
		cache[o.id] = m
		return m
	}
}

extension WorldView {
	/// rt4 `Protocol.spawnGroundObject`: rebuilds the pile on scene tile (x, z) of the current plane
	/// from `objStacks`: the most valuable item (cost, times amount + 1 for stackables) is drawn on
	/// top, and the first two other item types show beneath it.
	func refreshObjStack(x: Int, z: Int) {
		guard let scene = scene, x >= 0, z >= 0, x < 104, z < 104 else { return }
		let level = plane
		guard let list = objStacks[stackKey(plane, x, z)], !list.isEmpty else {
			_ = scene.removeObjStack(level: level, x: x, z: z)
			return
		}
		var best = -99_999_999
		var primary: GroundObj?
		for g in list {
			guard let t = (try? store.objResolved(g.type)) ?? nil else { continue }
			var value = Int(t.cost)
			if t.stackable { value *= g.amount + 1 }
			if best < value { best = value; primary = g }
		}
		guard let top = primary else {
			_ = scene.removeObjStack(level: level, x: x, z: z)
			return
		}
		var second: GroundObj?, third: GroundObj?
		for g in list where g.type != top.type {
			if second == nil { second = g }
			if g.type != second?.type && third == nil { third = g }
		}
		if groundModels == nil { groundModels = GroundItemModels(store: store) }
		let ts = textures
		let avail: (Int) -> Bool = { id in
			guard let t = ts else { return false }
			return t.meta.indices.contains(id) && t.meta[id].defined
		}
		func entity(_ g: GroundObj?) -> SceneEntity? {
			guard let g = g else { return nil }
			return groundModels?.model(type: g.type, count: g.amount, textureAvailable: avail)
		}
		let y = scene.tileHeight(level: level, xFine: x * 128 + 64, zFine: z * 128 + 64)
		scene.setObjStack(level: level, x: x, z: z, y: y, primary: entity(top), key: Int64((z << 7) + x + 1_610_612_736), secondary: entity(second), tertiary: entity(third))
	}

	/// Places every tracked pile into a freshly built scene.
	func placeAllObjStacks() {
		for key in objStacks.keys where key >> 16 == plane { refreshObjStack(x: (key >> 8) & 0xFF, z: key & 0xFF) }
	}
}
