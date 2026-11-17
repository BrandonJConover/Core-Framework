import Foundation

/// A frame's worth of the parts of the game state plugins can observe. `PluginDiffer` compares two of them.
struct WorldSnapshot {
	struct Stat: Equatable { var level: Int; var xp: Int }
	var ticks = 0
	var stats: [Int: Stat] = [:]
	var inventories: [Int: [Int: ServerMessage.InvItem]] = [:]
	var chatSize = 0
	var chatLines: [ChatLine] = []
	var actors: [ActorKey: ActorSnapshot] = [:]
	var ground: [Int: [GroundObj]] = [:]
	var plane = 0
	/// Changes whenever the scene is rebuilt (ground items and tiles restart then).
	var buildStamp = 0
}

/// Turns consecutive snapshots into events. Polling a snapshot instead of hooking the packet handlers keeps the
/// plugin layer out of the networking code and costs nothing for event kinds nobody listens to.
struct PluginDiffer {
	private var previous: WorldSnapshot?
	/// The event kinds the previous snapshot has data for; kinds newly wanted are baselined silently.
	private var baseline: PluginSubscription = []

	mutating func reset() { previous = nil; baseline = [] }

	mutating func diff(_ next: WorldSnapshot, wants: PluginSubscription, xpDivisor: Int) -> [PluginEvent] {
		defer { previous = next; baseline = wants }
		guard let prev = previous else { return [] }
		var out: [PluginEvent] = []
		let live = wants.intersection(baseline)
		let scale = max(xpDivisor, 1)

		if live.contains(.actors) || live.contains(.animations) || live.contains(.hitsplats) {
			for (key, a) in next.actors.sorted(by: { ($0.key.isNpc ? 1 : 0, $0.key.index) < ($1.key.isNpc ? 1 : 0, $1.key.index) }) {
				guard let old = prev.actors[key] else {
					if live.contains(.actors) { out.append(.actorSpawned(a)) }
					continue
				}
				if live.contains(.animations), old.animation != a.animation {
					out.append(.animationChanged(AnimationChange(actor: a, oldAnimation: old.animation)))
				}
				if live.contains(.hitsplats) {
					for i in 0..<min(a.hitUntil.count, old.hitUntil.count) where a.hitUntil[i] > old.hitUntil[i] {
						out.append(.hitsplat(HitsplatEvent(actor: a, damage: i < a.hitDamage.count ? a.hitDamage[i] : 0, type: i < a.hitType.count ? a.hitType[i] : 0)))
					}
				}
			}
			if live.contains(.actors) {
				for (key, a) in prev.actors where next.actors[key] == nil { out.append(.actorDespawned(a)) }
			}
		}

		if live.contains(.groundItems), prev.buildStamp == next.buildStamp, prev.plane == next.plane, prev.ground != next.ground {
			for key in Set(prev.ground.keys).union(next.ground.keys).sorted() {
				let old = prev.ground[key] ?? [], new = next.ground[key] ?? []
				if old == new { continue }
				let tile = (x: (key >> 8) & 0xFF, z: key & 0xFF, plane: key >> 16)
				// Multiset difference: an item removed and another added counts as both.
				var remaining = old
				var added: [GroundObj] = []
				for g in new {
					if let i = remaining.firstIndex(of: g) { remaining.remove(at: i) } else { added.append(g) }
				}
				for g in remaining { out.append(.groundItemDespawned(GroundItemSnapshot(type: g.type, amount: g.amount, tileX: tile.x, tileZ: tile.z, plane: tile.plane))) }
				for g in added { out.append(.groundItemSpawned(GroundItemSnapshot(type: g.type, amount: g.amount, tileX: tile.x, tileZ: tile.z, plane: tile.plane))) }
			}
		}

		if live.contains(.stats) {
			for (skill, s) in next.stats.sorted(by: { $0.key < $1.key }) {
				guard let old = prev.stats[skill], old != s else { continue }
				out.append(.statChanged(StatChange(skill: skill, oldLevel: old.level, newLevel: s.level, oldXp: old.xp / scale, newXp: s.xp / scale)))
			}
		}

		if live.contains(.containers) {
			for (inv, slots) in next.inventories.sorted(by: { $0.key < $1.key }) {
				guard let old = prev.inventories[inv], old != slots else { continue }
				var changes: [ContainerChange.SlotChange] = []
				for slot in Set(old.keys).union(slots.keys).sorted() {
					let a = old[slot], b = slots[slot]
					if a == b { continue }
					changes.append(.init(slot: slot, oldId: a?.id ?? -1, newId: b?.id ?? -1, oldCount: Int(a?.count ?? 0), newCount: Int(b?.count ?? 0)))
				}
				if !changes.isEmpty { out.append(.containerChanged(ContainerChange(inventory: inv, slots: changes))) }
			}
		}

		if live.contains(.chat), next.chatSize > prev.chatSize {
			let n = min(next.chatSize - prev.chatSize, next.chatLines.count)
			for line in next.chatLines.prefix(n).reversed() { out.append(.chatMessage(line)) }
		}

		if live.contains(.gameTick), next.ticks != prev.ticks { out.append(.gameTick) }
		return out
	}
}
