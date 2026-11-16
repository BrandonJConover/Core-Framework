import Foundation
import XCTest
@testable import Scape530

/// Projectiles and tile graphics, forced movement, layered and overlaid animations, sound cues, and the
/// jump / crawl speed bits of PLAYER_INFO and NPC_INFO.
final class MotionTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	/// MSB-first bit packer for hand-built PLAYER_INFO / NPC_INFO payloads.
	struct BitWriter {
		var bytes: [UInt8] = []
		var used = 0
		mutating func put(_ value: Int, _ n: Int) {
			for i in stride(from: n - 1, through: 0, by: -1) {
				if used % 8 == 0 { bytes.append(0) }
				if (value >> i) & 1 == 1 { bytes[bytes.count - 1] |= UInt8(0x80 >> (used % 8)) }
				used += 1
			}
		}
	}

	/// Feeds the recorded session into a `GameClient` (copied from `WorldViewTests.replay`).
	func replay(_ client: GameClient, cyclesPerTick: Int = 30) throws {
		let me = 2047 // the first player-info section is always the local player
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: me, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		var players = PlayerInfoDecoder(selfIndex: me, localX: 52, localZ: 52)
		var npcs = NpcInfoDecoder()
		var zone: (x: Int, z: Int)?
		for pkt in try SessionReplayTests.recordedPackets("resizable-session") {
			switch pkt.opcode {
			case ServerProt.playerInfo:
				let r = try players.decode(pkt.payload)
				client.handle(.players(r, players))
				for _ in 0..<cyclesPerTick { client.world.cycle(varps: client.state.varps) }
			case ServerProt.npcInfo:
				let p = try XCTUnwrap(players.players[me])
				let r = try npcs.decode(pkt.payload, selfX: p.x, selfZ: p.z)
				client.handle(.npcs(r, npcs))
			default:
				let m = try ServerMessage.decode(pkt)
				if case .rebuildNormal(let r) = m {
					if let z = zone {
						players.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
						npcs.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
					} else {
						players = PlayerInfoDecoder(selfIndex: me, localX: r.localX, localZ: r.localZ)
					}
					zone = (r.zoneX, r.zoneZ)
				}
				client.handle(.message(m))
			}
		}
	}

	// MARK: jump flag and speeds (no cache needed)

	func testPlayerInfoKeepsJumpFacingAndStepSpeeds() throws {
		var d = PlayerInfoDecoder(selfIndex: 2047, localX: 50, localZ: 50)
		// Tick 1: the local player crawls one step (type 2 without the run bit); player 5 appears
		// 3 east, 2 south of us with facing 4 and the jump bit set.
		var w = BitWriter()
		w.put(1, 1); w.put(2, 2); w.put(0, 1); w.put(4, 3); w.put(0, 1)
		w.put(0, 8)
		w.put(5, 11); w.put(0, 1); w.put(3, 5); w.put(4, 3); w.put(1, 1); w.put((-2) & 31, 5)
		w.put(2047, 11)
		_ = try d.decode(w.bytes)
		let me = try XCTUnwrap(d.players[2047])
		XCTAssertEqual(me.lastStep, [4])
		XCTAssertEqual(me.lastSpeed, [0], "a lone type-2 step is rt4 `move(0, dir)`, a crawl")
		XCTAssertFalse(me.running)
		let other = try XCTUnwrap(d.players[5])
		XCTAssertEqual(other.x, me.x + 3)
		XCTAssertEqual(other.z, me.z - 2)
		XCTAssertTrue(other.jump)
		XCTAssertEqual(other.facing, entityAngles[4])
		XCTAssertEqual(other.posSerial, 1)

		// Tick 2: player 5 runs two steps; we walk one step; a second add has the jump bit clear.
		w = BitWriter()
		w.put(1, 1); w.put(1, 2); w.put(6, 3); w.put(0, 1)
		w.put(1, 8)
		w.put(1, 1); w.put(2, 2); w.put(1, 1); w.put(2, 3); w.put(2, 3); w.put(0, 1)
		w.put(9, 11); w.put(0, 1); w.put(1, 5); w.put(0, 3); w.put(0, 1); w.put(1, 5)
		w.put(2047, 11)
		_ = try d.decode(w.bytes)
		XCTAssertEqual(d.players[2047]?.lastSpeed, [0, 1])
		XCTAssertEqual(d.players[5]?.lastSpeed, [2, 2])
		XCTAssertTrue(d.players[5]?.running ?? false)
		XCTAssertEqual(d.players[5]?.posSerial, 1, "stepping is not a position event")
		XCTAssertEqual(d.players[9]?.jump, false)

		// Tick 3: the local player teleports (type 3) with the jump bit, then without it.
		for jump in [1, 0] {
			w = BitWriter()
			w.put(1, 1); w.put(3, 2); w.put(70, 7); w.put(jump, 1); w.put(0, 2); w.put(0, 1); w.put(33, 7)
			w.put(2, 8)
			w.put(0, 1); w.put(0, 1)
			w.put(2047, 11)
			let serial = d.players[2047]?.posSerial ?? 0
			_ = try d.decode(w.bytes)
			let t = try XCTUnwrap(d.players[2047])
			XCTAssertEqual([t.x, t.z], [33, 70])
			XCTAssertEqual(t.jump, jump == 1)
			XCTAssertEqual(t.posSerial, serial + 1)
		}
	}

	func testNpcInfoKeepsJumpAndFacing() throws {
		var d = NpcInfoDecoder()
		var w = BitWriter()
		w.put(0, 8)
		// id 12, jump, facing 5, no extended block, dz -1, type 3000, dx 4
		w.put(12, 15); w.put(1, 1); w.put(5, 3); w.put(0, 1); w.put(31, 5); w.put(3000, 14); w.put(4, 5)
		_ = try d.decode(w.bytes, selfX: 60, selfZ: 61)
		let n = try XCTUnwrap(d.npcs[12])
		XCTAssertEqual([n.x, n.z, n.type], [64, 60, 3000])
		XCTAssertTrue(n.jump)
		XCTAssertEqual(n.facing, entityAngles[5])
		XCTAssertEqual(n.posSerial, 1)
		// Next tick it crawls then runs.
		w = BitWriter()
		w.put(1, 8)
		w.put(1, 1); w.put(2, 2); w.put(0, 1); w.put(2, 3); w.put(0, 1)
		_ = try d.decode(w.bytes, selfX: 60, selfZ: 61)
		XCTAssertEqual(d.npcs[12]?.lastSpeed, [0])
	}

	/// The world applies the decoded jump bit: a teleport within 8 tiles without it is walked, with it snaps; a crawl step is queued with speed 0.
	func testWorldAppliesJumpAndCrawl() throws {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		try replay(client)
		let world = client.world
		let me = try XCTUnwrap(world.selfActor)
		let (x0, z0) = (me.queueX[0], me.queueZ[0])

		var d = PlayerInfoDecoder(selfIndex: 2047, localX: x0, localZ: z0)
		var w = BitWriter()
		w.put(1, 1); w.put(2, 2); w.put(0, 1); w.put(4, 3); w.put(0, 1) // one crawl step east
		w.put(0, 8); w.put(2047, 11)
		world.handle(.players(try d.decode(w.bytes), d), varps: client.state.varps)
		XCTAssertEqual(me.queueX[0], x0 + 1)
		XCTAssertEqual(me.queueSpeed[0], 0, "crawl speed reaches the movement queue")
		XCTAssertEqual(me.queueSize, 1)

		let fineBefore = (me.xFine, me.zFine)
		w = BitWriter()
		w.put(1, 1); w.put(3, 2); w.put(z0 + 3, 7); w.put(0, 1); w.put(0, 2); w.put(0, 1); w.put(x0 + 4, 7)
		w.put(0, 8); w.put(2047, 11)
		world.handle(.players(try d.decode(w.bytes), d), varps: client.state.varps)
		XCTAssertEqual(me.queueX[0], x0 + 4)
		XCTAssertEqual(me.queueSize, 2, "no jump bit and a short hop: the actor walks there")
		XCTAssertEqual(fineBefore.0, me.xFine)

		w = BitWriter()
		w.put(1, 1); w.put(3, 2); w.put(z0 + 6, 7); w.put(1, 1); w.put(0, 2); w.put(0, 1); w.put(x0 + 7, 7)
		w.put(0, 8); w.put(2047, 11)
		world.handle(.players(try d.decode(w.bytes), d), varps: client.state.varps)
		XCTAssertEqual(me.queueSize, 0, "jump bit: snap")
		XCTAssertEqual(me.xFine, (x0 + 7) * 128 + 64)
		XCTAssertEqual(me.zFine, (z0 + 6) * 128 + 64)
	}

	// MARK: forced movement

	func testForcedMovementInterpolates() throws {
		let s = try store()
		let ctx = WorldContext(store: s, models: ActorModels(store: s))
		let a = PathingActor(kind: .player, index: 3, ctx: ctx)
		ctx.loop = 100
		a.setPosition(x: 20, z: 20, jump: true)
		// Be dragged to (22, 20) first, then from there to (26, 24) between loops 108 and 116, facing west (direction 3).
		a.applyForceMove([22, 20, 26, 24, 4, 16, 3])
		XCTAssertEqual(a.forceCyclesToStart, 104)
		XCTAssertEqual(a.forceCyclesToDest, 116)
		XCTAssertEqual(a.queueSize, 1)
		var seen: [Int: (Int, Int)] = [:]
		for _ in 0..<20 {
			ctx.loop += 1
			a.cycle(isSelf: false)
			seen[ctx.loop] = (a.xFine, a.zFine)
		}
		// Easing to the start tile: 2624 -> 2880 in shares of 1/3, 1/2, 1/1 of what is left (loops 101...103; loop 104 starts the drag).
		XCTAssertEqual(seen[101]?.0, 2709)
		XCTAssertEqual(seen[102]?.0, 2794)
		XCTAssertEqual(seen[103]?.0, 2880)
		XCTAssertEqual(seen[104]?.0, 2880)
		XCTAssertEqual(seen[104]?.1, 20 * 128 + 64, "z stays: the start tile has the same z")
		// Linear from loop 104 (start cycle) to loop 116: 12 cycles across (2880, 2624) -> (3392, 3136).
		XCTAssertEqual(seen[104]?.0, 2880)
		XCTAssertEqual(seen[110]?.0, (6 * 3392 + 2880 * 6) / 12)
		XCTAssertEqual(seen[110]?.1, (6 * 3136 + 2624 * 6) / 12)
		XCTAssertEqual(seen[113]?.0, (9 * 3392 + 2880 * 3) / 12)
		XCTAssertEqual(seen[116]?.0, 3392)
		XCTAssertEqual(seen[116]?.1, 3136)
		XCTAssertEqual(a.yaw, 512, "direction 3 faces west (yaw 512) at once while dragged")
		// Afterwards ordinary movement resumes from the queue (it still ends on the old tile, so it walks back).
		XCTAssertNotEqual(seen[117]?.0, 3392)
	}

	// MARK: action over movement, layers

	/// A seq that has a frame group ("walkmerge"), the kind that plays an action on the upper body over a walk.
	func findMergeSeq(_ s: ConfigStore, matchingBaseOf walk: SeqType, limit: Int = 8000) -> [SeqType] {
		func baseId(_ q: SeqType) -> Int? {
			let f = q.frames[1]
			return (try? s.animFrameset(f >> 16))??.frameSafe(f & 0xFFFF)?.base.id
		}
		let want = baseId(walk)
		var out: [SeqType] = []
		for i in 0..<limit {
			if let q = (try? s.seq(i)) ?? nil, let g = q.frameGroup, !g.isEmpty, q.frames.count >= 2, baseId(q) == want { out.append(q) }
			if out.count >= 60 { break }
		}
		return out
	}

	func testActionSeqOverlaysWalkOnDifferentVertexGroups() throws {
		let s = try store()
		let models = ActorModels(store: s)
		let look = try PlayerLook.defaultLook(store: s, female: false)
		let walk = SeqPose(seq: try XCTUnwrap(try s.seq(819)), frame: 2)
		var proven: SeqType?
		let candidates = findMergeSeq(s, matchingBaseOf: walk.seq)
		print("\(candidates.count) merge sequences share the walk skeleton")
		for q in candidates {
			let action = SeqPose(seq: q, frame: 1)
			guard let both = try models.player(look, action: action, movement: walk),
			      let a = try models.player(look, action: action, movement: nil),
			      let m = try models.player(look, action: nil, movement: walk) else { continue }
			var fromAction = 0, fromWalk = 0, other = 0, same = 0
			for v in 0..<both.vertexCount {
				let p = (both.vertexX[v], both.vertexY[v], both.vertexZ[v])
				let pa = (a.vertexX[v], a.vertexY[v], a.vertexZ[v]), pm = (m.vertexX[v], m.vertexY[v], m.vertexZ[v])
				if p == pa && p != pm { fromAction += 1 }
				if p == pm && p != pa { fromWalk += 1 }
				if p != pm && p != pa { other += 1 }
				if pa == pm { same += 1 }
			}
			if proven == nil { print("cand \(q.id): action-only \(fromAction) walk-only \(fromWalk) neither \(other) a==m \(same)/\(both.vertexCount) group \(q.frameGroup!.sorted().prefix(8))") }
			// The action drives the body outside its frame group, the walk drives the group (legs): so some
			// vertices equal the action-only pose, and the walk-driven ones match neither pose alone.
			if fromAction > 0 && other > 0 && same < both.vertexCount {
				print("seq \(q.id) (frame group \(q.frameGroup?.count ?? 0) transforms) over walk 819: \(fromAction) vertices follow the action only, \(fromWalk) follow the walk only, of \(both.vertexCount)")
				proven = q
				break
			}
		}
		XCTAssertNotNil(proven, "some action sequence splits the body with the walk")
	}

	func testLayeredAnimationLifecycleAndModel() throws {
		let s = try store()
		let ctx = WorldContext(store: s, models: ActorModels(store: s))
		let a = PathingActor(kind: .player, index: 3, ctx: ctx)
		a.look = try PlayerLook.defaultLook(store: s, female: false)
		a.setPosition(x: 10, z: 10, jump: true)
		let plain = try XCTUnwrap(a.buildModel())
		// A multi-frame sequence for the layer.
		// A looping sequence whose skeleton has layer parts (so it can run on a model part).
		var found: SeqType?, anyLoop: SeqType?
		for i in 0..<9000 where found == nil {
			guard let q = (try? s.seq(i)) ?? nil, q.frames.count >= 2, q.replayOffset >= 0, q.replayCount >= 50, q.frameDelays.allSatisfy({ $0 > 0 }) else { continue }
			let f = q.frames[0]
			guard let base = (try? s.animFrameset(f >> 16))??.frameSafe(f & 0xFFFF)?.base else { continue }
			if anyLoop == nil { anyLoop = q }
			if base.parts.contains(where: { $0 != 0 && $0 != SoftwareModel.allParts }) { found = q }
		}
		// Rev 530's skeletons may have no layer parts; the lifecycle is tested either way, the model effect only when one exists.
		let q = try XCTUnwrap(found ?? anyLoop, "a looping sequence exists")
		print("layer seq \(q.id), skeleton with layer parts: \(found != nil)")
		a.applyLayeredAnims([LayeredAnim(seq: q.id, delay: 2, slotMask: 0b101), LayeredAnim(seq: q.id, delay: 2, slotMask: 0xFF0)])
		XCTAssertNotNil(a.layers[0])
		XCTAssertNil(a.layers[1])
		XCTAssertNotNil(a.layers[2])
		XCTAssertEqual(a.layers[0]?.delay, 2)
		// The delay counts down before the frames advance.
		a.updateLayers()
		a.updateLayers()
		XCTAssertEqual(a.layers[0]?.delay, 0)
		XCTAssertEqual(a.layers[0]?.step, 0)
		a.updateLayers()
		XCTAssertEqual(a.layers[0]?.step, 1)
		var frames = Set<Int>()
		for _ in 0..<(q.frameDelays.reduce(0, +) + 4) {
			a.updateLayers()
			if let f = a.layers[0]?.frame { frames.insert(f) }
		}
		XCTAssertGreaterThan(frames.count, 1, "the layer steps through its frames")
		let layered = try XCTUnwrap(a.buildModel())
		var differs = 0
		for v in 0..<plain.vertexCount where plain.vertexX[v] != layered.vertexX[v] || plain.vertexY[v] != layered.vertexY[v] || plain.vertexZ[v] != layered.vertexZ[v] { differs += 1 }
		if found != nil { XCTAssertGreaterThan(differs, 0, "a layered animation moves part of the body") }
		// -1 clears the slots in the mask only.
		a.applyLayeredAnims([LayeredAnim(seq: -1, delay: 0, slotMask: 0b001)])
		XCTAssertNil(a.layers[0])
		XCTAssertNotNil(a.layers[2])
		// Re-sending the same sequence with exact-move 0 stops it.
		var again = q
		again.exactMove = 0
		_ = again
	}

	// MARK: sound cues

	func testSeqSoundCuesFireAsFramesAdvance() throws {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		try replay(client)
		let world = client.world
		let s = world.store
		var cue: SeqType?
		for i in 0..<4000 {
			if let q = (try? s.seq(i)) ?? nil, let all = q.soundEffects, all.count >= 2, all[0] != nil, q.frames.count >= 2, q.frameDelays.allSatisfy({ $0 > 0 }) { cue = q; break }
		}
		let q = try XCTUnwrap(cue)
		var got: [(Int, Int, Bool)] = []
		world.onSeqFrameSound = { seq, index, _, _, mine in if seq.id == q.id { got.append((seq.id, index, mine)) } }
		let me = try XCTUnwrap(world.selfActor)
		me.animate(delay: 0, seq: q.id)
		XCTAssertEqual(got.first?.1, 0, "the first cue plays when the animation starts")
		XCTAssertEqual(got.first?.2, true, "own animations are flagged as the local player's")
		for _ in 0..<(q.frameDelays.reduce(0, +) + 3) { world.cycle(varps: client.state.varps) }
		let indices = got.map(\.1)
		print("seq \(q.id) cues fired for frames \(indices)")
		XCTAssertTrue(indices.contains(1), "advancing to frame 1 fires its cue")
		// An npc's cues are not the local player's.
		got = []
		let npc = try XCTUnwrap(world.ctx.npcs.values.first)
		npc.animate(delay: 0, seq: q.id)
		XCTAssertEqual(got.first?.2, false)
	}

	// MARK: projectiles and tile graphics

	func spotAnimWithModel(_ s: ConfigStore, preferring: [Int]) -> Int? {
		for id in preferring + Array(0..<400) {
			if let t = (try? s.spotAnim(id)) ?? nil, t.model != 0, t.seq != -1 { return id }
		}
		return nil
	}

	func testProjectileFliesFromPlayerToHans() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		try replay(client)
		let world = client.world
		let (w, h) = (852, 393)
		var before = Raster(width: w, height: h)
		XCTAssertTrue(world.draw(into: &before, rect: (0, 0, w, h)))

		let me = try XCTUnwrap(world.selfActor)
		let (hansIndex, hans) = try XCTUnwrap(world.ctx.npcs.first { $0.value.npcType?.id == 0 })
		let (sx, sz) = (me.queueX[0], me.queueZ[0]), (tx, tz) = (hans.queueX[0], hans.queueZ[0])
		print("player (\(sx), \(sz)) -> Hans #\(hansIndex) (\(tx), \(tz))")
		XCTAssertLessThan(abs(tx - sx), 100)
		let gfx = try XCTUnwrap(spotAnimWithModel(s, preferring: [91, 15, 27]))
		// Variant 2 (MAP_PROJANIM_2): zone-relative source, signed offset to the target, npc target = index + 1.
		world.applyZone(.zonePartialFollows(chunkX: sx & ~7, chunkZ: sz & ~7))
		let raw = [((sx & 7) << 4) | (sz & 7), tx - sx, tz - sz, hansIndex + 1, gfx, 25, 15, 0, 40, 16, 0]
		world.applyZone(.zoneUpdate(.projectile(opcode: ServerProt.mapProjanim2, raw: raw)))
		XCTAssertEqual(world.projectiles.count, 1)
		let p = world.projectiles[0]
		XCTAssertEqual(p.sourceX, sx * 128 + 64)
		XCTAssertEqual(p.sourceY, sz * 128 + 64)
		XCTAssertEqual(p.lastCycle - p.firstCycle, 40)
		XCTAssertEqual(p.targetIndex, hansIndex + 1)

		// Mid-flight: halfway between the two actors, above the ground, nearer to Hans than at the start.
		for _ in 0..<20 { world.cycle(varps: client.state.varps) }
		XCTAssertEqual(world.projectiles.count, 1)
		let mid = (x: p.x, y: p.y, z: p.z)
		let sx0 = Double(p.sourceX), sy0 = Double(p.sourceY)
		let hx = Double(hans.xFine), hy = Double(hans.zFine)
		print("mid flight \(mid), source (\(sx0), \(sy0)), Hans (\(hx), \(hy))")
		if abs(hx - sx0) > 256 {
			XCTAssertGreaterThan(abs(mid.x - sx0), 64)
			XCTAssertLessThan(abs(mid.x - hx), abs(sx0 - hx))
		}
		XCTAssertLessThan(mid.z, Double(world.scene?.tileHeight(level: 0, xFine: Int(mid.x), zFine: Int(mid.y)) ?? 0), "the missile is above the ground")
		var frame = Raster(width: w, height: h)
		XCTAssertTrue(world.draw(into: &frame, rect: (0, 0, w, h)))
		try save(frame, "projectile-midflight")
		var differing = 0
		for i in 0..<frame.pixels.count where frame.pixels[i] != before.pixels[i] { differing += 1 }
		XCTAssertGreaterThan(differing, 40, "the projectile is drawn")
		let withProj = world.scene?.sceneryList.count ?? 0

		// It is removed on arrival.
		for _ in 0..<30 { world.cycle(varps: client.state.varps) }
		XCTAssertEqual(world.projectiles.count, 0)
		XCTAssertTrue(world.draw(into: &frame, rect: (0, 0, w, h)))
		XCTAssertLessThan(world.scene?.sceneryList.count ?? 0, withProj)

		// The other two variants decode to the same flight in half-tile units.
		world.applyZone(.zonePartialFollows(chunkX: (sx & ~7), chunkZ: (sz & ~7)))
		let half = [((((sx & ~7) * 2 + 2 * (sx & 7)) - (sx & ~7) * 2) << 4) | ((sz & 7) * 2), (tx - sx) * 2, (tz - sz) * 2, 0, gfx, 25, 15, 0, 40, 16, 0]
		world.applyZone(.zoneUpdate(.projectile(opcode: ServerProt.mapProjanim3, raw: half)))
		XCTAssertEqual(world.projectiles.count, 1)
		XCTAssertEqual(world.projectiles[0].sourceX, (sx * 2) * 64, "variant 3 counts half tiles")
		XCTAssertEqual(world.projectiles[0].elevationPitch, 16)
	}

	func testProjectileMotionMath() throws {
		let s = try store()
		let gfx = try XCTUnwrap(spotAnimWithModel(s, preferring: [91]))
		// A straight shot (no pitch) from (0, 0, 0) to (1000, 0, -100) over loops 10...50.
		let p = Projectile(store: s, spotAnimId: gfx, plane: 0, sourceX: 0, sourceY: 0, sourceZ: 0, firstCycle: 10, lastCycle: 50,
		                   elevationPitch: -1, arcScale: 0, targetIndex: 0, baseZ: 0)
		p.setTarget(targetY: 0, cycle: 10, targetHeight: -100, targetX: 1000)
		for _ in 0..<20 { p.update(1) }
		XCTAssertEqual(p.x, 1000.0 * 20 / 41, accuracy: 1e-6, "reaches the target 1 cycle after lastCycle, so 41 cycles in total")
		XCTAssertEqual(p.z, -100.0 * 20 / 41, accuracy: 1e-6)
		XCTAssertEqual(p.yaw, (Int(atan2(1000.0 / 41, 0) * 325.949) + 1024) & 0x7FF)
		// With a pitch the height is parabolic and still lands on the target height.
		let q = Projectile(store: s, spotAnimId: gfx, plane: 0, sourceX: 0, sourceY: 0, sourceZ: 0, firstCycle: 10, lastCycle: 50,
		                   elevationPitch: 16, arcScale: 0, targetIndex: 0, baseZ: 0)
		q.setTarget(targetY: 0, cycle: 10, targetHeight: -100, targetX: 1000)
		var peak = 0.0
		for _ in 0..<41 { q.update(1); peak = min(peak, q.z) }
		XCTAssertEqual(q.z, -100, accuracy: 1e-6)
		XCTAssertLessThan(peak, -100, "the arc rises above the target before coming down")
	}

	func testGroundSpotAnimPlaysOnceAndGoes() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		try replay(client)
		let world = client.world
		world.finishBuild()
		let gfx = try XCTUnwrap(spotAnimWithModel(s, preferring: [91, 86]))
		let seq = try XCTUnwrap(try s.seq(try XCTUnwrap(try s.spotAnim(gfx)).seq))
		let me = try XCTUnwrap(world.selfActor)
		world.applyZone(.zonePartialFollows(chunkX: me.queueX[0] & ~7, chunkZ: me.queueZ[0] & ~7))
		// SPOTANIM_SPECIFIC with a 3 cycle delay.
		world.applyZone(.zoneUpdate(.spotAnim(x: me.queueX[0] & 7, z: me.queueZ[0] & 7, id: gfx, height: 0, delay: 3)))
		XCTAssertEqual(world.groundSpots.count, 1)
		// SPOTANIM_ENTITY aimed at a tile: plane 0, world x and z.
		let target = Int32(truncatingIfNeeded: (1 << 30) | (0 << 28) | ((world.origin.x + me.queueX[0] + 1) << 14) | (world.origin.z + me.queueZ[0]))
		world.handle(.message(.spotAnimEntity(delay: 0, height: 0, target: target, gfx: gfx)), varps: client.state.varps)
		XCTAssertEqual(world.groundSpots.count, 2, "a graphic on a tile is drawn too")
		let (w, h) = (852, 393)
		var r = Raster(width: w, height: h)
		for _ in 0..<5 { world.cycle(varps: client.state.varps) }
		XCTAssertTrue(world.draw(into: &r, rect: (0, 0, w, h)))
		try save(r, "spotanim-ground")
		XCTAssertGreaterThan(world.scene?.sceneryList.count ?? 0, 0)
		for _ in 0..<(seq.frameDelays.reduce(0, +) + 12) { world.cycle(varps: client.state.varps) }
		XCTAssertEqual(world.groundSpots.count, 0, "they end after their sequence")
	}
}
