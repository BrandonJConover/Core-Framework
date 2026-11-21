import Foundation

/// Release-mode render benchmark: replays a recorded login session into a `GameClient` (a real region with
/// players and npcs) and times full frames and the pieces of a frame. Driven by `scape530-bench`.
public enum RenderBench {
	public struct Row {
		public var label: String
		public var msPerFrame: Double
	}

	public struct SizeResult {
		public var width: Int, height: Int
		public var rows: [Row]
		/// Checksum of the final frame, to see at a glance that an optimisation did not change output.
		public var checksum: UInt64
	}

	static func packets(_ url: URL) throws -> [GamePacket] {
		var p = Packet([UInt8](try Data(contentsOf: url)))
		var out: [GamePacket] = []
		while p.remaining > 0 {
			let op = try p.g1()
			let len = Int(try p.g4())
			out.append(GamePacket(opcode: op, payload: try p.gdata(len)))
		}
		return out
	}

	/// The test suite's `replay`: rebuild, player and npc info, 30 client cycles per player-info tick.
	public static func makeClient(cache: String, session: String) throws -> GameClient {
		if ProcessInfo.processInfo.environment["SCAPE530_NO_MODEL_CACHE"] != nil { PathingActor.cacheModels = false }
		let store = ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: cache)))
		let client = try GameClient(store: store, server: .init(host: "127.0.0.1", port: 1))
		if ProcessInfo.processInfo.environment["SCAPE530_NO_SHADOWS"] != nil { client.host.prefs.characterShadows = false }
		let me = 2047
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: me, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		var players = PlayerInfoDecoder(selfIndex: me, localX: 52, localZ: 52)
		var npcs = NpcInfoDecoder()
		var zone: (x: Int, z: Int)?
		for pkt in try packets(URL(fileURLWithPath: session)) {
			switch pkt.opcode {
			case ServerProt.playerInfo:
				let r = try players.decode(pkt.payload)
				client.handle(.players(r, players))
				for _ in 0..<30 { client.world.cycle(varps: client.state.varps) }
			case ServerProt.npcInfo:
				guard let p = players.players[me] else { continue }
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
		client.world.finishBuild()
		return client
	}

	static func checksum(_ r: Raster) -> UInt64 {
		var h: UInt64 = 0xcbf29ce484222325
		for p in r.pixels { h = (h ^ UInt64(p)) &* 0x100000001b3 }
		return h
	}

	public static func run(client: GameClient, width: Int, height: Int, frames: Int, log: (String) -> Void = { _ in }) throws -> SizeResult {
		// The first frame of a fresh client runs exactly one cycle whatever the clock says, so its picture is
		// reproducible: its checksum shows whether an optimisation changed any pixel.
		let sum = checksum(try client.frame(width: width, height: height))
		// Warm up: a few more frames settle texture / model caches.
		for _ in 0..<8 { _ = try client.frame(width: width, height: height) }
		let world = client.world
		let ms = { (s: Double) in s / Double(frames) * 1000 }
		var rows: [Row] = []

		// Whole frames (includes whatever client cycles the wall clock asks for).
		let t = DispatchTime.now().uptimeNanoseconds
		for _ in 0..<frames { _ = try client.frame(width: width, height: height) }
		rows.append(Row(label: "full frame (GameClient.frame)", msPerFrame: Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6 / Double(frames)))

		// Pieces.
		let v = client.viewport.flatMap { $0.x + $0.w <= width && $0.y + $0.h <= height ? $0 : nil } ?? (x: 0, y: 0, w: width, h: height)
		var r = Raster(width: width, height: height)
		PerfStats.reset()
		PerfStats.enabled = true
		let w0 = PerfStats.now()
		// A 60 fps shell runs 50/60 of a client cycle per frame, so most frames re-pose their actors.
		drawLoop(client, world, &r, v, frames)
		PerfStats.nanos[PerfStats.Section.frame.rawValue] = DispatchTime.now().uptimeNanoseconds - w0
		let top = client.host.game.interfaces.top
		if top != -1 {
			let t0 = PerfStats.now()
			for _ in 0..<frames { try client.ui.render(top, state: client.host.game.interfaces, into: &r) }
			PerfStats.add(.ui, since: t0)
			let t1 = PerfStats.now()
			for _ in 0..<frames { _ = world.drawMinimap(drawn: client.ui.drawn, into: &r) }
			PerfStats.add(.minimap, since: t1)
		}
		let t2 = PerfStats.now()
		for _ in 0..<frames { world.cycle(varps: client.state.varps) }
		PerfStats.add(.cycle, since: t2)
		PerfStats.enabled = false
		for s in PerfStats.Section.allCases where s != .frame {
			rows.append(Row(label: s.label, msPerFrame: ms(PerfStats.seconds(s))))
		}
		rows.insert(Row(label: "world.draw (3D + overlays)", msPerFrame: ms(PerfStats.seconds(.frame))), at: 1)
		return SizeResult(width: width, height: height, rows: rows, checksum: sum)
	}

	/// The 3D part of the benchmark on its own (the function callgrind profiles in steady state).
	@inline(never) static func drawLoop(_ client: GameClient, _ world: WorldView, _ r: inout Raster, _ v: (x: Int, y: Int, w: Int, h: Int), _ frames: Int) {
		var cycleDebt = 0.0
		for _ in 0..<frames {
			cycleDebt += 50.0 / 60.0
			while cycleDebt >= 1 { cycleDebt -= 1; world.cycle(varps: client.state.varps) }
			world.draw(into: &r, rect: v)
		}
	}

	public static func describe(_ client: GameClient) -> String {
		let w = client.world
		return "players \(w.ctx.players.count), npcs \(w.ctx.npcs.count), plane \(w.plane), scene \(w.scene != nil ? "built" : "missing")"
	}
}
