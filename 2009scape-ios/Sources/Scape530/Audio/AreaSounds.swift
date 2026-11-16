import Foundation

/// One actor's (npc or player) contribution to the ambient sound field: where it is, and which looping
/// sound its current movement plays (rt4 `Npc.getSound` / `Player.getSound`).
public struct ActorSoundInfo: Equatable {
	public var key: Int
	public var isPlayer: Bool
	/// Fine position of the actor (rt4 `xFine/zFine`) and its size in tiles.
	public var xFine: Int, zFine: Int, size: Int
	/// Synth sound id or -1; `radius` in tiles.
	public var sound: Int
	public var radius: Int
	public init(key: Int, isPlayer: Bool, xFine: Int, zFine: Int, size: Int, sound: Int, radius: Int) {
		self.key = key; self.isPlayer = isPlayer; self.xFine = xFine; self.zFine = zFine; self.size = size; self.sound = sound; self.radius = radius
	}
}

/// Port of rt4 `AreaSoundManager` and `AreaSound`: looping ambient sounds that fade with the distance from
/// the local player. Sources are
/// - locs with a `bgsound` (a loop) and/or `bgsounds` (random one-shots every min...max cycles),
/// - npcs whose type has idle/walk/run sounds, and players whose appearance carries sounds.
///
/// Everything here is called from the frame thread; the mixer is touched under `SoundEffectPlayer.lock`.
/// Positions are scene-local fine coordinates (128 per tile), like rt4.
public final class AreaSoundManager {
	/// rt4 `AreaSound`.
	final class Entry {
		var minX = 0, maxX = 0, minZ = 0, maxZ = 0
		var level = 0
		var sound = -1
		var sounds: [Int]?
		/// Audible radius in fine units (tiles * 128); 0 mutes it.
		var radius = 0
		var minInterval = 0, maxInterval = 0
		/// Cycles until the next one-shot of `sounds`.
		var remaining = 0
		/// The loop (`primaryStream`) and the current one-shot (`secondaryStream`).
		var primary: SoundVoice?
		var secondary: SoundVoice?
		// Loc entries.
		var locId = -1
		var loc: LocType?
		/// rt4 `multiLocOrNpc`: re-resolved from its variable.
		var multi = false
	}

	unowned let effects: SoundEffectPlayer
	/// Locs by identity (rt4 `locSounds`), npcs and players by server index.
	private var locs: [Entry] = []
	private var npcs: [Int: Entry] = [:]
	private var players: [Int: Entry] = [:]
	/// Decoded samples by synth id; nil remembers a sound that failed to load.
	private var pcm: [Int: PcmSound?] = [:]
	/// rt4 `LocType.getMultiLoc`: resolves a multi-loc with the current variables.
	public var resolveLoc: (LocType) -> LocType? = { $0 }

	init(effects: SoundEffectPlayer) { self.effects = effects }

	// MARK: content tests (rt4 `LocType.hasAreaSound`)

	/// rt4 `LocType.hasAreaSound`: a loop or a one-shot list on the loc or any of its variants.
	public static func hasAreaSound(_ loc: LocType, store: ConfigStore) -> Bool {
		guard let list = loc.multiLocs else { return loc.bgSound != -1 || loc.bgSounds != nil }
		for id in list where id != -1 {
			if let t = (try? store.loc(id)) ?? nil, t.bgSound != -1 || t.bgSounds != nil { return true }
		}
		return false
	}

	// MARK: locs (rt4 `AreaSoundManager.add` / `remove(x, locType, z, level)`)

	/// A loc was placed. `x`/`z` is its south-west scene tile, `width`/`length` its footprint after rotation.
	public func addLoc(_ loc: LocType, x: Int, z: Int, level: Int, width: Int, length: Int) {
		let e = Entry()
		e.minX = x * 128
		e.minZ = z * 128
		e.level = level
		e.sounds = loc.bgSounds
		e.radius = loc.bgSoundRange * 128
		e.maxInterval = loc.bgSoundInterval.max
		e.minInterval = loc.bgSoundInterval.min
		e.sound = loc.bgSound
		e.loc = loc
		e.locId = loc.id
		e.maxX = (x + width) * 128
		e.maxZ = (z + length) * 128
		if loc.multiLocs != nil {
			e.multi = true
			update(e)
		}
		if let list = e.sounds, !list.isEmpty {
			e.remaining = e.minInterval + Int(Double.random(in: 0..<1) * Double(e.maxInterval - e.minInterval))
		}
		locs.append(e)
	}

	/// The loc `id` at (`x`, `z`, `level`) was removed.
	public func removeLoc(id: Int, x: Int, z: Int, level: Int) {
		guard let i = locs.firstIndex(where: { $0.level == level && $0.minX == x * 128 && $0.minZ == z * 128 && $0.locId == id }) else { return }
		stop(locs[i])
		locs.remove(at: i)
	}

	/// rt4 `AreaSoundManager.clear(false)`: a new scene replaces the loc sounds.
	public func clearLocs() {
		for e in locs { stop(e) }
		locs.removeAll()
	}

	/// rt4 `AreaSoundManager.clear(true)`.
	public func clearAll() {
		clearLocs()
		for e in npcs.values { stop(e) }
		for e in players.values { stop(e) }
		npcs.removeAll()
		players.removeAll()
	}

	/// The mixer was emptied (logout): forget the voices so they are recreated if sounds still apply.
	func dropVoices() {
		for e in locs + Array(npcs.values) + Array(players.values) { e.primary = nil; e.secondary = nil }
	}

	/// rt4 `AreaSound.update` for multi entries (`AreaSoundManager.updateMulti`, called when varps change).
	func update(_ e: Entry) {
		let before = e.sound
		if let loc = e.loc {
			if let t = resolveLoc(loc) {
				e.maxInterval = t.bgSoundInterval.max
				e.sound = t.bgSound
				e.minInterval = t.bgSoundInterval.min
				e.radius = t.bgSoundRange * 128
				e.sounds = t.bgSounds
			} else {
				e.sound = -1
				e.sounds = nil
				e.maxInterval = 0
				e.radius = 0
				e.minInterval = 0
			}
		}
		if e.sound != before, let v = e.primary {
			remove(v)
			e.primary = nil
		}
	}

	/// rt4 `AreaSoundManager.updateMulti`.
	public func updateMulti() {
		for e in locs where e.multi { update(e) }
	}

	// MARK: actors

	/// Reconciles npc and player entries with the actors now in the scene (rt4 adds and removes them as
	/// NPC_INFO / PLAYER_INFO add and drop actors, and refreshes sounds and bounds every redraw).
	public func syncActors(_ infos: [ActorSoundInfo]) {
		var seenNpc = Set<Int>(), seenPlayer = Set<Int>()
		for a in infos {
			let e: Entry
			if a.isPlayer {
				seenPlayer.insert(a.key)
				e = players[a.key] ?? { let n = Entry(); players[a.key] = n; return n }()
			} else {
				seenNpc.insert(a.key)
				e = npcs[a.key] ?? { let n = Entry(); npcs[a.key] = n; return n }()
			}
			e.minX = a.xFine
			e.maxX = a.xFine + a.size * 64
			e.minZ = a.zFine
			e.maxZ = a.zFine + a.size * 64
			e.radius = a.radius * 128
			if e.sound != a.sound {
				if let v = e.primary { remove(v); e.primary = nil }
				e.sound = a.sound
			}
		}
		for (k, e) in npcs where !seenNpc.contains(k) { stop(e); npcs[k] = nil }
		for (k, e) in players where !seenPlayer.contains(k) { stop(e); players[k] = nil }
	}

	/// Number of tracked sources (locs, npcs, players), for tests.
	public var counts: (locs: Int, npcs: Int, players: Int) { (locs.count, npcs.count, players.count) }

	/// Voices currently attached (loops, one-shots), for tests.
	public var voiceCounts: (loops: Int, oneShots: Int) {
		let all = locs + Array(npcs.values) + Array(players.values)
		return (all.filter { $0.primary != nil }.count, all.filter { $0.secondary != nil }.count)
	}

	// MARK: per-cycle update (rt4 `AreaSoundManager.redraw`)

	/// Call once per frame with the cycles since the last call, the listener's fine position and level.
	/// rt4 `redraw(sceneDelta, xFine, zFine, plane)`.
	public func redraw(cycles: Int, xFine x: Int, zFine z: Int, level: Int) {
		if locs.contains(where: \.multi) { updateMulti() }
		for e in locs { redraw(e, cycles: cycles, x: x, z: z, level: level) }
		for e in npcs.values { redraw(e, cycles: cycles, x: x, z: z, level: level) }
		for e in players.values { redraw(e, cycles: cycles, x: x, z: z, level: level) }
	}

	/// rt4 `AreaSoundManager.redraw(x, areaSound, level, loops, z)`.
	func redraw(_ e: Entry, cycles: Int, x: Int, z: Int, level: Int) {
		if e.sound == -1 && e.sounds == nil { return }
		var distance = 0
		if e.maxX < x { distance = x - e.maxX } else if e.minX > x { distance = e.minX - x }
		if e.maxZ < z { distance += z - e.maxZ } else if z < e.minZ { distance += e.minZ - z }
		let ambient = effects.ambientVolume
		if e.radius == 0 || e.radius < distance - 64 || ambient == 0 || level != e.level {
			stop(e)
			return
		}
		distance -= 64
		if distance < 0 { distance = 0 }
		let volume = (e.radius - distance) * ambient / e.radius
		if let v = e.primary {
			setVolume(v, volume)
		} else if e.sound >= 0, let pcm = sample(e.sound), let v = SoundVoice.effect(pcm, volume: volume) {
			v.setLoops(-1)
			add(v)
			e.primary = v
		}
		if let v = e.secondary {
			setVolume(v, volume)
			if finished(v) { e.secondary = nil }
		} else if let list = e.sounds, !list.isEmpty {
			e.remaining -= cycles
			if e.remaining <= 0 {
				let id = list[Int(Double(list.count) * Double.random(in: 0..<1))]
				if let pcm = sample(id), let v = SoundVoice.effect(pcm, volume: volume) {
					v.setLoops(0)
					add(v)
					e.remaining = Int(Double(e.maxInterval - e.minInterval) * Double.random(in: 0..<1)) + e.minInterval
					e.secondary = v
				}
			}
		}
	}

	// MARK: mixer access (all under the player's lock)

	private func sample(_ id: Int) -> PcmSound? {
		if let hit = pcm[id] { return hit }
		let loaded = SynthSound.create(archive: effects.archive, group: id)?.toPcmSound()
		pcm[id] = .some(loaded)
		return loaded
	}

	private func add(_ v: SoundVoice) { effects.lock.lock(); effects.mixer.add(v); effects.lock.unlock() }
	private func remove(_ v: SoundVoice) { effects.lock.lock(); effects.mixer.remove(v); effects.lock.unlock() }
	private func setVolume(_ v: SoundVoice, _ volume: Int) {
		effects.lock.lock(); v.setVolume(volume << 6, pan: v.currentPan); effects.lock.unlock()
	}
	private func finished(_ v: SoundVoice) -> Bool { effects.lock.lock(); defer { effects.lock.unlock() }; return v.finished }

	/// Detaches both voices (rt4 `removeSubStream` on the primary and secondary stream).
	private func stop(_ e: Entry) {
		if let v = e.primary { remove(v); e.primary = nil }
		if let v = e.secondary { remove(v); e.secondary = nil }
	}
}
