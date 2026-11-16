import Foundation

/// A ground item (rt4 `ObjStack`).
public struct GroundObj: Equatable {
	public var type: Int
	public var amount: Int
}

/// What is under a touch point: entity keys in draw order (far to near) and the ground tile.
public struct WorldPick {
	/// rt4 `Model.aLongArray11`: keys of the players, npcs, locs and ground items under the point.
	public var hits: [Int64]
	/// The scene tile under the point (rt4 `MiniMenu.anInt1742/2954`), nil over empty space.
	public var tile: (x: Int, z: Int)?
}

extension WorldView {
	// MARK: picking

	/// Draws the scene once more with the mouse at (`x`, `y`) in game pixels and collects what lies under
	/// it (rt4 does this as part of every frame; here it runs on demand for a tap or long-press).
	/// Returns nil when the world is not ready or the point is outside `rect`.
	public func pick(x: Int, y: Int, rect: (x: Int, y: Int, w: Int, h: Int)) -> WorldPick? {
		guard x >= rect.x, y >= rect.y, x < rect.x + rect.w, y < rect.y + rect.h else { return nil }
		guard renderScene(rect: rect, pick: (x, y)) != nil else { return nil }
		let picker = ScenePicker.shared
		var hits = picker.hits
		let tile = picker.tileX >= 0 ? (x: picker.tileX, z: picker.tileZ) : nil
		picker.allowInput = false
		picker.tileRequested = false
		// Ground items have no model here: a stack on the picked tile counts as the farthest hit.
		if let t = tile, !groundObjects(x: t.x, z: t.z).isEmpty, !hits.contains(Int64((t.z << 7) + t.x + 0x6000_0000)) {
			hits.insert(Int64(t.x) | Int64(t.z) << 7 | 0x6000_0000, at: 0)
		}
		return WorldPick(hits: hits, tile: tile)
	}

	/// The local player's combat level (rt4 `PlayerList.self.combatLevel`).
	var ownCombatLevel: Int { selfActor?.appearance?.combatLevel ?? 0 }

	/// The stack on a scene tile of the current plane, oldest first.
	public func groundObjects(x: Int, z: Int) -> [GroundObj] { objStacks[stackKey(plane, x, z)] ?? [] }

	func stackKey(_ level: Int, _ x: Int, _ z: Int) -> Int { level << 16 | x << 8 | z }

	// MARK: actors

	/// The local player's scene tile (rt4 `PlayerList.self.movementQueueX/Z[0]`) and size.
	var selfSceneTile: (x: Int, z: Int, size: Int)? {
		guard let a = selfActor else { return nil }
		return (a.queueX[0], a.queueZ[0], a.size)
	}

	/// The scene tile an npc or player stands on (rt4 `movementQueueX/Z[0]`).
	func npcTile(_ index: Int) -> (x: Int, z: Int)? { ctx.npcs[index].map { ($0.queueX[0], $0.queueZ[0]) } }
	func playerTile(_ index: Int) -> (x: Int, z: Int)? { ctx.players[index].map { ($0.queueX[0], $0.queueZ[0]) } }

	/// World tile of scene tile (0, 0) (rt4 `Camera.originX/Z`).
	public var origin: (x: Int, z: Int) { (ctx.originX, ctx.originZ) }

	/// The npc type id the server must be told about when examining (rt4 resolves multi-npcs first).
	func npcTypeId(_ index: Int) -> Int? { ctx.npcs[index]?.npcType?.id }

	// MARK: zone updates (rt4 Protocol.readZonePacket)

	/// Applies the zone bus messages that change the world after the scene is built: loc add/delete
	/// (scene and collision) and ground items.
	func applyZone(_ m: ServerMessage) {
		switch m {
		case let .zonePartialFollows(x, z):
			chunk = (x, z)
		case let .zoneFullFollows(x, z):
			chunk = (x, z)
			for tx in x..<(x + 8) { for tz in z..<(z + 8) { objStacks[stackKey(plane, tx, tz)] = nil; refreshObjStack(x: tx, z: tz) } }
		case let .zonePartialEnclosed(x, z, updates):
			chunk = (x, z)
			for u in updates { applyZoneUpdate(u) }
		case let .zoneUpdate(u):
			applyZoneUpdate(u)
		case .clearMinimapFlag:
			destinationFlag = nil
		default:
			break
		}
	}

	private func applyZoneUpdate(_ u: ZoneUpdate) {
		func tile(_ x: Int, _ z: Int) -> (x: Int, z: Int)? {
			let tx = chunk.x + x, tz = chunk.z + z
			return tx >= 0 && tz >= 0 && tx < 104 && tz < 104 ? (tx, tz) : nil
		}
		switch u {
		case let .soundArea(x, z, id, radius, loops, delay):
			if let t = tile(x, z) { onSoundArea?(id, t.x, t.z, radius, loops, delay) }
		case let .locDel(x, z, shape, _):
			if let t = tile(x, z) { removeLoc(level: plane, x: t.x, z: t.z, layer: Self.locLayer(shape)) }
		case let .locAdd(x, z, id, shape, rotation):
			if let t = tile(x, z) { changeLoc(level: plane, x: t.x, z: t.z, id: id, shape: shape, rotation: rotation) }
		case let .objAdd(x, z, id, count, hiddenFrom):
			if hiddenFrom != selfIndex, let t = tile(x, z) {
				objStacks[stackKey(plane, t.x, t.z), default: []].append(GroundObj(type: id, amount: count))
				refreshObjStack(x: t.x, z: t.z)
			}
		case let .objReveal(x, z, id, count):
			if let t = tile(x, z) {
				objStacks[stackKey(plane, t.x, t.z), default: []].append(GroundObj(type: id, amount: count))
				refreshObjStack(x: t.x, z: t.z)
			}
		case let .objDel(x, z, id):
			guard let t = tile(x, z) else { return }
			let k = stackKey(plane, t.x, t.z)
			if var list = objStacks[k], let i = list.firstIndex(where: { $0.type == id }) {
				list.remove(at: i)
				objStacks[k] = list.isEmpty ? nil : list
				refreshObjStack(x: t.x, z: t.z)
			}
		case let .objCount(x, z, id, oldCount, newCount):
			guard let t = tile(x, z) else { return }
			let k = stackKey(plane, t.x, t.z)
			if var list = objStacks[k], let i = list.firstIndex(where: { $0.type == id && $0.amount == oldCount }) {
				list[i].amount = newCount
				objStacks[k] = list
				refreshObjStack(x: t.x, z: t.z)
			}
		default:
			break
		}
	}

	/// rt4 `Loc.LAYERS`: walls 0-3 are layer 0, wall decorations 4-8 layer 1, scenery 9-21 layer 2, ground decor 22 layer 3.
	static func locLayer(_ shape: Int) -> Int { shape < 4 ? 0 : shape < 9 ? 1 : shape < 22 ? 2 : 3 }

	/// The collision map a loc on `level` belongs to (rt4 drops it one level under a bridge).
	private func collisionLevel(_ level: Int, _ x: Int, _ z: Int) -> Int {
		guard let s = scene, (s.renderFlags[1][x][z] & 0x2) == 0x2 else { return level }
		return level - 1
	}

	/// Removes the loc of `layer` on a tile from the scene and its collision (rt4 `SceneGraph.removeLoc`).
	func removeLoc(level: Int, x: Int, z: Int, layer: Int) {
		guard let s = scene else { return }
		let key: Int64
		switch layer {
		case 0: key = s.wallKey(level: level, x: x, z: z)
		case 1: key = s.wallDecorKey(level: level, x: x, z: z)
		case 2: key = s.sceneryKey(level: level, x: x, z: z)
		default: key = s.groundDecorKey(level: level, x: x, z: z)
		}
		guard key != 0 else { return }
		let id = Int((key >> 32) & Int64(Int32.max)), shape = Int((key >> 14) & 0x1F), rotation = Int((key >> 20) & 3)
		if let type = (try? store.loc(id)) ?? nil {
			let ml = collisionLevel(level, x, z)
			if ml >= 0, ml < collision.count {
				let map = collision[ml]
				switch layer {
				case 0: if type.blockWalk != 0 { map.unflagWall(angle: rotation, shape: shape, blocksProjectiles: type.blockRange, x: x, z: z) }
				case 2: if type.blockWalk != 0 { map.unflagScenery(x: x, z: z, width: type.width, length: type.length, angle: rotation, blocksProjectiles: type.blockRange) }
				case 3: if type.blockWalk == 1 { map.unflagGroundDecor(x: x, z: z) }
				default: break
				}
			}
		}
		switch layer {
		case 0: s.removeWall(level: level, x: x, z: z)
		case 1: s.removeWallDecor(level: level, x: x, z: z)
		case 2: s.removeScenery(level: level, x: x, z: z)
		default: s.removeGroundDecor(level: level, x: x, z: z)
		}
	}

	/// LOC_ADD: replaces whatever occupies the loc's layer on the tile with the new loc (scene and collision).
	func changeLoc(level: Int, x: Int, z: Int, id: Int, shape: Int, rotation: Int) {
		guard x > 0, z > 0, x < 103, z < 103, let placer = placer else { return }
		removeLoc(level: level, x: x, z: z, layer: Self.locLayer(shape))
		try? placer.addLoc(plane: level, locIndex: id, shape: shape, x: x, z: z, orientation: rotation)
		if let type = (try? store.loc(id)) ?? nil {
			let ml = collisionLevel(level, x, z)
			if ml >= 0, ml < collision.count { CollisionBuilder.flagLoc(collision[ml], type: type, shape: shape, rotation: rotation, x: x, z: z) }
		}
	}
}
