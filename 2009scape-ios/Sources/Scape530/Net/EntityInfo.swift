/// Bit-level reader for the bit-packed parts of PLAYER_INFO / NPC_INFO
/// (rt4 `Packet.accessBits`, `gBits`, `method2241`, `accessBytes`).
struct BitCursor {
	let data: [UInt8]
	var bitOffset: Int

	init(_ data: [UInt8], byteOffset: Int) {
		self.data = data
		bitOffset = byteOffset * 8
	}

	mutating func bits(_ n: Int) throws -> Int {
		guard bitOffset + n <= data.count * 8 else {
			throw PacketUnderflow(offset: bitOffset / 8, wanted: n, size: data.count)
		}
		var v = 0
		for _ in 0..<n {
			let byte = Int(data[bitOffset >> 3])
			v = v << 1 | (byte >> (7 - (bitOffset & 7))) & 1
			bitOffset += 1
		}
		return v
	}

	/// rt4 `method2241(length)`: bits left in the packet.
	var remaining: Int { data.count * 8 - bitOffset }

	/// rt4 `accessBytes`: round up to the next whole byte.
	var byteOffset: Int { (bitOffset + 7) / 8 }
}

/// Walk direction deltas indexed by the 3-bit direction (rt4 `PathingEntity.move`).
public enum WalkDirection {
	public static let dx = [-1, 0, 1, -1, 1, -1, 0, 1]
	public static let dz = [1, 1, 1, 0, 0, -1, -1, -1]
}

/// rt4 `PathingEntity.ANGLES`, indexed by the 3-bit facing in "add" updates.
public let entityAngles = [768, 1024, 1280, 512, 1536, 256, 0, 1792]

public struct HitSplat: Equatable {
	public var damage: Int
	public var type: Int
}

public struct SpotAnimUpdate: Equatable {
	public var id: Int
	public var height: Int
	public var delay: Int
}

public struct LayeredAnim: Equatable {
	public var seq: Int
	public var delay: Int
	public var slotMask: Int
}

/// Decoded player appearance block (rt4 `Player.decodeAppearance`).
public struct PlayerAppearance: Equatable {
	public var female: Bool
	public var size: Int
	public var skullIcon: Int
	public var prayerIcon: Int
	/// 12 body slots. Raw rt4 encoding: 0 = empty, `0x40000000 | equipSlotIndex`
	/// for worn objects (index into `Equipment.objIds`, resolved later),
	/// `Int32.min | kitId` for identity kits.
	public var slots: [Int]
	/// NPC id when the player is transmogrified (slot 0 = 0xFFFF), else -1.
	public var npcId: Int
	public var colours: [Int]
	public var basId: Int
	public var name37: Int64
	public var combatLevel: Int
	public var combatLevelWithSummoning: Int
	public var skillTotal: Int
	public var combatRange: Int
	public var soundRadius: Int
	/// Ambient sound ids [idle, crawl, walk, run] (rt4 `Player.anInt1648/1658/1654/1670`); -1 when none.
	public var sounds: [Int] = [-1, -1, -1, -1]

	public init(_ bytes: [UInt8]) throws {
		var p = Packet(bytes)
		let flags = try p.g1()
		female = flags & 1 == 1
		let showSkill = flags & 4 != 0
		size = ((flags >> 3) & 7) + 1
		skullIcon = try p.g1b()
		prayerIcon = try p.g1b()
		var s = [Int](repeating: 0, count: 12)
		var npc = -1
		slotLoop: for i in 0..<12 {
			let hi = try p.g1()
			if hi == 0 { continue }
			let v = hi << 8 | (try p.g1())
			if i == 0 && v == 65535 {
				npc = try p.g2()
				_ = try p.g1() // team
				break slotLoop
			}
			s[i] = v >= 32768 ? (0x4000_0000 | (v - 32768)) : (Int(Int32.min) | (v - 256))
		}
		slots = s
		npcId = npc
		colours = try (0..<5).map { _ in try p.g1() }
		basId = try p.g2()
		name37 = try p.g8()
		combatLevel = try p.g1()
		if showSkill {
			skillTotal = try p.g2()
			combatLevelWithSummoning = combatLevel
			combatRange = -1
		} else {
			skillTotal = 0
			combatLevelWithSummoning = try p.g1()
			let r = try p.g1()
			combatRange = r == 255 ? -1 : r
		}
		soundRadius = try p.g1()
		if soundRadius != 0 {
			// rt4 reads them in the order idle, crawl, walk, run.
			sounds = try (0..<4).map { _ in try p.g2() }
		}
	}

	public var name: String? { Base37.decode(name37) }
}

/// Per-entity update masks shared by players and NPCs.
public struct EntityMasks: Equatable {
	public var hits: [HitSplat] = []
	public var healthBar: Int?
	public var anim: (seq: Int, delay: Int)?
	public var layeredAnims: [LayeredAnim]?
	public var faceEntity: Int?
	public var faceTile: (x: Int, z: Int)?
	public var forceChat: String?
	public var spotAnim: SpotAnimUpdate?
	/// Players only.
	public var appearance: PlayerAppearance?
	public var publicChat: (effects: Int, rights: Int, encoded: [UInt8])?
	public var forceMove: [Int]?
	/// NPCs only: type change.
	public var transform: Int?

	public static func == (a: EntityMasks, b: EntityMasks) -> Bool {
		String(describing: a) == String(describing: b)
	}
}

/// Scene-local tile position plus the last movement this tick.
public struct TrackedEntity: Equatable {
	public var index: Int
	public var x: Int
	public var z: Int
	/// NPC type id (NPCs only).
	public var type: Int = -1
	public var lastStep: [Int] = []
	/// Speed of each entry of `lastStep` (rt4 `move(speed, direction)`): 0 crawl (a lone step of
	/// "type 2"), 1 walk, 2 run (two steps).
	public var lastSpeed: [Int] = []
	/// Speed of the latest step; true when it was a run step.
	public var running = false
	public var appearance: PlayerAppearance?
	/// Counts position events (an add record, or the local player's teleport block). A consumer that
	/// remembers the serial it applied knows when `x/z` were set rather than walked to.
	public var posSerial = 0
	/// The jump flag of the latest position event (rt4 `teleport(x, jump, z)` / `method2683`):
	/// set means snap there, clear means walk there when it is within 8 tiles.
	public var jump = false
	/// Facing of an add record, as an angle (rt4 `PathingEntity.ANGLES[bits]`), applied to new actors only.
	public var facing = 0
}

/// Stateful PLAYER_INFO decoder: keeps rt4's local player list so later
/// packets' movement bits line up. Port of rt4 `Protocol.readPlayerInfoPacket`.
public struct PlayerInfoDecoder {
	public private(set) var selfIndex: Int
	public private(set) var players: [Int: TrackedEntity] = [:]
	/// Order matters: the "existing players" section walks this list.
	public private(set) var localIds: [Int] = []
	public private(set) var plane = 0
	var appearanceCache: [Int: PlayerAppearance] = [:]

	public init(selfIndex: Int, localX: Int, localZ: Int) {
		self.selfIndex = selfIndex
		players[selfIndex] = TrackedEntity(index: selfIndex, x: localX, z: localZ)
	}

	public struct Result: Equatable {
		public var updated: [Int: EntityMasks] = [:]
		public var added: [Int] = []
		public var removed: [Int] = []
	}

	public struct Desync: Error, CustomStringConvertible {
		public let description: String
	}

	/// Re-centre after a REBUILD_NORMAL (positions are scene-local).
	public mutating func rebase(dx: Int, dz: Int) {
		for k in players.keys {
			players[k]!.x -= dx
			players[k]!.z -= dz
		}
	}

	/// rt4 `PlayerList.self.teleport(x, jump, z)` plus `Player.plane`: puts the local player at a
	/// scene-local tile. Used by PLAYER_INFO's teleport block and by TELEPORT_LOCAL_PLAYER.
	public mutating func teleportSelf(x: Int, z: Int, plane: Int, jump: Bool) {
		self.plane = plane
		guard var me = players[selfIndex] else { return }
		me.x = x
		me.z = z
		me.lastStep = []
		me.lastSpeed = []
		me.jump = jump
		me.posSerial += 1
		players[selfIndex] = me
	}

	public mutating func decode(_ payload: [UInt8]) throws -> Result {
		var r = Result()
		var extended: [Int] = []
		var bc = BitCursor(payload, byteOffset: 0)

		// Self
		if try bc.bits(1) == 1 {
			switch try bc.bits(2) {
			case 0:
				extended.append(selfIndex)
			case 1:
				step(selfIndex, try bc.bits(3), speed: 1)
				if try bc.bits(1) == 1 { extended.append(selfIndex) }
			case 2:
				if try bc.bits(1) == 1 {
					step(selfIndex, try bc.bits(3), speed: 2)
					step(selfIndex, try bc.bits(3), speed: 2)
				} else {
					step(selfIndex, try bc.bits(3), speed: 0)
				}
				if try bc.bits(1) == 1 { extended.append(selfIndex) }
			default:
				// rt4 `readSelfPlayerInfo` type 3: `teleport(x, jump, z)`.
				let z = try bc.bits(7)
				let jump = try bc.bits(1) == 1
				plane = try bc.bits(2)
				if try bc.bits(1) == 1 { extended.append(selfIndex) }
				let x = try bc.bits(7)
				teleportSelf(x: x, z: z, plane: plane, jump: jump)
			}
		}

		// Existing local players
		let count = try bc.bits(8)
		guard count <= localIds.count else { throw Desync(description: "player list grew from \(localIds.count) to \(count) (gppov1)") }
		for id in localIds[count...] { r.removed.append(id) }
		var kept: [Int] = []
		for id in localIds[0..<count] {
			if try bc.bits(1) == 0 {
				kept.append(id)
				continue
			}
			switch try bc.bits(2) {
			case 0:
				kept.append(id)
				extended.append(id)
			case 1:
				kept.append(id)
				step(id, try bc.bits(3), speed: 1)
				if try bc.bits(1) == 1 { extended.append(id) }
			case 2:
				kept.append(id)
				if try bc.bits(1) == 1 {
					step(id, try bc.bits(3), speed: 2)
					step(id, try bc.bits(3), speed: 2)
				} else {
					step(id, try bc.bits(3), speed: 0)
				}
				if try bc.bits(1) == 1 { extended.append(id) }
			default:
				r.removed.append(id)
			}
		}

		// New players
		let me = players[selfIndex]!
		while bc.remaining >= 11 {
			let id = try bc.bits(11)
			if id == 2047 { break }
			if try bc.bits(1) == 1 { extended.append(id) }
			var dx = try bc.bits(5)
			let facing = entityAngles[try bc.bits(3)]
			if dx > 15 { dx -= 32 }
			let jump = try bc.bits(1) == 1
			var dz = try bc.bits(5)
			if dz > 15 { dz -= 32 }
			var e = players[id] ?? TrackedEntity(index: id, x: 0, z: 0)
			e.x = me.x + dx
			e.z = me.z + dz
			e.lastStep = []
			e.lastSpeed = []
			e.jump = jump
			e.facing = facing
			e.posSerial += 1
			if e.appearance == nil { e.appearance = appearanceCache[id] }
			players[id] = e
			kept.append(id)
			r.added.append(id)
		}

		// Masks
		var p = Packet(payload, offset: bc.byteOffset)
		for id in extended {
			var flags = try p.g1()
			if flags & 0x10 != 0 { flags += try p.g1() << 8 }
			let masks = try Self.readMasks(flags, &p)
			if let a = masks.appearance {
				appearanceCache[id] = a
				players[id]?.appearance = a
			}
			r.updated[id] = masks
		}
		guard p.offset == payload.count else {
			throw Desync(description: "PLAYER_INFO consumed \(p.offset) of \(payload.count) (gpp1)")
		}
		for id in r.removed where !kept.contains(id) {
			players[id] = nil
		}
		localIds = kept
		return r
	}

	mutating func step(_ id: Int, _ dir: Int, speed: Int) {
		guard var e = players[id] else { return }
		e.x += WalkDirection.dx[dir]
		e.z += WalkDirection.dz[dir]
		e.lastStep.append(dir)
		e.lastSpeed.append(speed)
		e.running = speed == 2
		players[id] = e
	}

	static func readMasks(_ flags: Int, _ p: inout Packet) throws -> EntityMasks {
		var m = EntityMasks()
		if flags & 0x80 != 0 {
			let effects = try p.ig2()
			let rights = try p.g1()
			let len = try p.g1()
			// rt4 reads the Huffman-encoded text in reverse (igdata).
			m.publicChat = (effects, rights, Array(try p.gdata(len).reversed()))
		}
		if flags & 0x1 != 0 {
			let dmg = try p.gsmarts()
			let type = try p.g1add()
			m.hits.append(HitSplat(damage: dmg, type: type))
			m.healthBar = try p.g1sub()
		}
		if flags & 0x8 != 0 {
			let seq = ServerMessage.nullable(try p.g2())
			m.anim = (seq, try p.g1())
		}
		if flags & 0x4 != 0 {
			let len = try p.g1add()
			m.appearance = try PlayerAppearance(try p.gdata(len))
		}
		if flags & 0x2 != 0 {
			m.faceEntity = ServerMessage.nullable(try p.g2add())
		}
		if flags & 0x400 != 0 {
			m.forceMove = [try p.g1neg(), try p.g1(), try p.g1add(), try p.g1(), try p.ig2(), try p.ig2(), try p.g1neg()]
		}
		if flags & 0x20 != 0 {
			m.forceChat = try p.gjstr()
		}
		if flags & 0x200 != 0 {
			let dmg = try p.gsmarts()
			m.hits.append(HitSplat(damage: dmg, type: try p.g1sub()))
		}
		if flags & 0x800 != 0 {
			let n = try p.g1neg()
			var list: [LayeredAnim] = []
			for _ in 0..<n {
				let seq = ServerMessage.nullable(try p.ig2())
				list.append(LayeredAnim(seq: seq, delay: try p.g1add(), slotMask: try p.g2()))
			}
			m.layeredAnims = list
		}
		if flags & 0x100 != 0 {
			let id = ServerMessage.nullable(try p.ig2())
			let packed = try p.mg4()
			m.spotAnim = SpotAnimUpdate(id: id, height: Int(packed >> 16), delay: Int(packed & 0xFFFF))
		}
		if flags & 0x40 != 0 {
			m.faceTile = (try p.g2(), try p.ig2add())
		}
		return m
	}
}

/// Stateful NPC_INFO decoder (rt4 `Protocol.readNpcPacket`). Needs the local
/// player's scene position, so feed it after the same tick's PLAYER_INFO.
public struct NpcInfoDecoder {
	public private(set) var npcs: [Int: TrackedEntity] = [:]
	public private(set) var localIds: [Int] = []

	public init() {}

	public mutating func rebase(dx: Int, dz: Int) {
		for k in npcs.keys {
			npcs[k]!.x -= dx
			npcs[k]!.z -= dz
		}
	}

	public mutating func decode(_ payload: [UInt8], selfX: Int, selfZ: Int) throws -> PlayerInfoDecoder.Result {
		var r = PlayerInfoDecoder.Result()
		var extended: [Int] = []
		var bc = BitCursor(payload, byteOffset: 0)

		let count = try bc.bits(8)
		guard count <= localIds.count else {
			throw PlayerInfoDecoder.Desync(description: "NPC list grew from \(localIds.count) to \(count) (gnpov1)")
		}
		for id in localIds[count...] { r.removed.append(id) }
		var kept: [Int] = []
		for id in localIds[0..<count] {
			if try bc.bits(1) == 0 {
				kept.append(id)
				continue
			}
			switch try bc.bits(2) {
			case 0:
				kept.append(id)
				extended.append(id)
			case 1:
				kept.append(id)
				step(id, try bc.bits(3), speed: 1)
				if try bc.bits(1) == 1 { extended.append(id) }
			case 2:
				kept.append(id)
				if try bc.bits(1) == 1 {
					step(id, try bc.bits(3), speed: 2)
					step(id, try bc.bits(3), speed: 2)
				} else {
					step(id, try bc.bits(3), speed: 0)
				}
				if try bc.bits(1) == 1 { extended.append(id) }
			default:
				r.removed.append(id)
			}
		}

		while bc.remaining >= 27 {
			let id = try bc.bits(15)
			if id == 32767 { break }
			let jump = try bc.bits(1) == 1
			let facing = entityAngles[try bc.bits(3)]
			if try bc.bits(1) == 1 { extended.append(id) }
			var dz = try bc.bits(5)
			let type = try bc.bits(14)
			if dz > 15 { dz -= 32 }
			var dx = try bc.bits(5)
			if dx > 15 { dx -= 32 }
			var e = TrackedEntity(index: id, x: selfX + dx, z: selfZ + dz, type: type)
			e.jump = jump
			e.facing = facing
			e.posSerial = (npcs[id]?.posSerial ?? 0) + 1
			npcs[id] = e
			kept.append(id)
			r.added.append(id)
		}

		var p = Packet(payload, offset: bc.byteOffset)
		for id in extended {
			var flags = try p.g1()
			if flags & 0x8 != 0 { flags += try p.g1() << 8 }
			let m = try Self.readMasks(flags, &p)
			if let t = m.transform { npcs[id]?.type = t }
			r.updated[id] = m
		}
		guard p.offset == payload.count else {
			throw PlayerInfoDecoder.Desync(description: "NPC_INFO consumed \(p.offset) of \(payload.count) (gnp1)")
		}
		for id in r.removed where !kept.contains(id) {
			npcs[id] = nil
		}
		localIds = kept
		return r
	}

	mutating func step(_ id: Int, _ dir: Int, speed: Int) {
		guard var e = npcs[id] else { return }
		e.x += WalkDirection.dx[dir]
		e.z += WalkDirection.dz[dir]
		e.lastStep.append(dir)
		e.lastSpeed.append(speed)
		e.running = speed == 2
		npcs[id] = e
	}

	static func readMasks(_ flags: Int, _ p: inout Packet) throws -> EntityMasks {
		var m = EntityMasks()
		if flags & 0x40 != 0 {
			let dmg = try p.g1()
			let type = try p.g1neg()
			m.hits.append(HitSplat(damage: dmg, type: type))
			m.healthBar = try p.g1sub()
		}
		if flags & 0x2 != 0 {
			let dmg = try p.g1neg()
			m.hits.append(HitSplat(damage: dmg, type: try p.g1sub()))
		}
		if flags & 0x10 != 0 {
			let seq = ServerMessage.nullable(try p.g2())
			m.anim = (seq, try p.g1())
		}
		if flags & 0x4 != 0 {
			m.faceEntity = ServerMessage.nullable(try p.g2add())
		}
		if flags & 0x80 != 0 {
			let id = ServerMessage.nullable(try p.g2add())
			let packed = try p.ig4()
			m.spotAnim = SpotAnimUpdate(id: id, height: Int(packed >> 16), delay: Int(packed & 0xFFFF))
		}
		if flags & 0x1 != 0 {
			m.transform = try p.ig2()
		}
		if flags & 0x20 != 0 {
			m.forceChat = try p.gjstr()
		}
		if flags & 0x100 != 0 {
			let n = try p.g1neg()
			var list: [LayeredAnim] = []
			for _ in 0..<n {
				let seq = ServerMessage.nullable(try p.ig2())
				list.append(LayeredAnim(seq: seq, delay: try p.g1sub(), slotMask: try p.g2()))
			}
			m.layeredAnims = list
		}
		if flags & 0x200 != 0 {
			m.faceTile = (try p.g2add(), try p.g2())
		}
		return m
	}
}
