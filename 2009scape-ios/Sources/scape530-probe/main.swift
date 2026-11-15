import Foundation
import Scape530

// scape530-probe: exercise the Swift rev-530 core against a cache or a server.
//
//   scape530-probe cache <cache-dir> [--deep]
//   scape530-probe js5 <host> <port>
//   scape530-probe login <host> <port> <username> <password> [js5-port]

let args = CommandLine.arguments
func usage() -> Never {
	print("""
	usage:
	  scape530-probe cache <cache-dir> [--deep]       verify reference tables (and every group with --deep)
	  scape530-probe js5 <host> <port>                 JS5 handshake + master index + reference tables
	  scape530-probe login <host> <port> <user> <pass> [js5-port]
	""")
	exit(2)
}

func cacheCommand(_ dir: String, deep: Bool) throws {
	let cache = try DiskCache(directory: URL(fileURLWithPath: dir))
	let archives = cache.groupSlots(archive: 255)
	print("archives in idx255: \(archives)")
	var totalGroups = 0
	var bad = 0
	for a in 0..<archives {
		guard let raw = cache.read(archive: 255, group: a) else {
			print("  [\(a)] missing reference table")
			continue
		}
		let index = try Js5Index(container: Js5Container.stripVersion(raw))
		var line = "  [\(a)] v\(index.version) groups=\(index.size) crc=\(index.checksum)"
		if deep {
			var ok = 0
			for g in index.groupIds {
				guard let packed = cache.read(archive: a, group: g) else { bad += 1; continue }
				let container = Js5Container.stripVersion(packed)
				if Crc32.checksum(container) != index.groupChecksums[g] {
					// Map groups are XTEA-encrypted on disk; CRC still covers ciphertext.
					bad += 1
					continue
				}
				do {
					_ = try Js5Container.decompress(container)
					ok += 1
				} catch {
					if a != 5 { print("    group \(g): \(error)") }
					bad += 1
				}
			}
			line += " ok=\(ok)"
		}
		totalGroups += index.size
		print(line)
	}
	print("total groups: \(totalGroups)" + (deep ? ", failures: \(bad)" : ""))
}

func js5Command(_ host: String, _ port: Int) throws -> [Int32] {
	let client = try Js5Client(host: host, port: port)
	let master = try client.masterIndex()
	print("master index: \(master.count) archives")
	let tables = try client.fetch(master.indices.map { (255, $0) })
	var crcs: [Int32] = []
	for (a, t) in tables.enumerated() {
		let idx = try Js5Index(container: t, expectedChecksum: master[a].crc)
		print("  [\(a)] v\(idx.version) groups=\(idx.size) crc=\(idx.checksum)")
		crcs.append(idx.checksum)
	}
	return crcs
}

do {
	guard args.count >= 2 else { usage() }
	switch args[1] {
	case "cache":
		guard args.count >= 3 else { usage() }
		try cacheCommand(args[2], deep: args.contains("--deep"))
	case "js5":
		guard args.count >= 4, let port = Int(args[3]) else { usage() }
		_ = try js5Command(args[2], port)
	case "login":
		guard args.count >= 6, let port = Int(args[3]) else { usage() }
		var req = Login.Request(username: args[4], password: args[5])
		if let m = ProcessInfo.processInfo.environment["PROBE_WINDOW_MODE"].flatMap({ Int($0) }) { req.windowMode = m; req.canvasWidth = 1015; req.canvasHeight = 469 }
		if args.count >= 7, let js5Port = Int(args[6]) {
			req.archiveChecksums = Array(try js5Command(args[2], js5Port).prefix(28))
		}
		let session = try GameConnection.login(host: args[2], port: port, request: req)
		print("logged in: \(session.account)")
		print("first packet: opcode \(session.account.firstOpcode), \(session.firstPacket.count) bytes")
		if session.account.firstOpcode == ServerProt.rebuildNormal {
			let rebuild = try RebuildNormal(payload: session.firstPacket)
			print("rebuild: world (\(rebuild.worldX), \(rebuild.worldZ)) plane \(rebuild.plane), regions \(rebuild.regions.map(\.locGroupName))")
			// With a local cache, prove the server's XTEA keys open the location groups.
			if let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] {
				let cache = try DiskCache(directory: URL(fileURLWithPath: dir))
				let maps = try Js5Index(container: Js5Container.stripVersion(cache.read(archive: 255, group: 5)!))
				for (region, key) in zip(rebuild.regions, rebuild.xteaKeys) {
					guard let g = maps.group(named: region.locGroupName), var c = cache.read(archive: 5, group: g).map(Js5Container.stripVersion) else {
						print("  \(region.locGroupName): not in cache")
						continue
					}
					if key != [0, 0, 0, 0] { Xtea.decryptContainer(&c, key: key) }
					let result = (try? Js5Container.decompress(c)).map { "\($0.count) bytes" } ?? "FAILED"
					print("  \(region.locGroupName) (group \(g)): \(result)")
				}
			}
		}
		// Read a few seconds of game packets to prove framing stays aligned.
		var framer = GamePacketFramer(cipher: session.inCipher)
		var start = (x: 52, z: 52)
		if session.account.firstOpcode == ServerProt.rebuildNormal, let r = try? RebuildNormal(payload: session.firstPacket) {
			start = (r.localX, r.localZ)
		}
		var players = PlayerInfoDecoder(selfIndex: session.account.selfId, localX: start.x, localZ: start.z)
		var npcs = NpcInfoDecoder()
		var recording = [UInt8]()
		let recordPath = ProcessInfo.processInfo.environment["PROBE_RECORD"]
		func record(_ op: Int, _ payload: [UInt8]) {
			guard recordPath != nil else { return }
			var h = Packet(capacity: 5)
			h.p1(op); h.p4(payload.count)
			recording += h.written + payload
		}
		record(session.account.firstOpcode, session.firstPacket)
		var typed = 0
		var unhandled: [Int: Int] = [:]
		var failures: [String] = []
		let seconds = Double(ProcessInfo.processInfo.environment["PROBE_SECONDS"] ?? "5") ?? 5
		let verbose = ProcessInfo.processInfo.environment["PROBE_VERBOSE"] != nil
		// PROBE_SCRIPT="2:cmd tele 3222 3218|4:walk 3225 3218" runs client actions at second offsets.
		var script: [(at: Double, action: String)] = (ProcessInfo.processInfo.environment["PROBE_SCRIPT"] ?? "")
			.split(separator: "|").compactMap { item in
				let parts = item.split(separator: ":", maxSplits: 1)
				guard parts.count == 2, let t = Double(parts[0]) else { return nil }
				return (t, String(parts[1]))
			}
		var outCipher = session.outCipher
		let began = Date()
		var lastKeepAlive = began
		var zone = (x: 0, z: 0)
		if let r = try? RebuildNormal(payload: session.firstPacket) { zone = (r.zoneX, r.zoneZ) }
		session.socket.setReadTimeout(milliseconds: 200)
		let deadline = Date().addingTimeInterval(seconds)
		while Date() < deadline {
			let now = Date()
			while let next = script.first, now.timeIntervalSince(began) >= next.at {
				script.removeFirst()
				let words = next.action.split(separator: " ")
				var msg: ClientMessage?
				if words.first == "cmd" {
					msg = .command(words.dropFirst().joined(separator: " "))
				} else if words.first == "walk", words.count == 3, let x = Int(words[1]), let z = Int(words[2]) {
					msg = .walk(destX: x, destZ: z)
				}
				if let m = msg {
					try session.socket.write(m.encode(&outCipher))
					print("-> \(next.action)")
				}
			}
			if now.timeIntervalSince(lastKeepAlive) >= 1 {
				try session.socket.write(ClientMessage.keepAlive.encode(&outCipher))
				lastKeepAlive = now
			}
			guard let chunk = try? session.socket.readSome() else { continue }
			if chunk.isEmpty { print("server closed the connection"); break }
			for pkt in try framer.feed(chunk) {
				record(pkt.opcode, pkt.payload)
				do {
					if pkt.opcode == ServerProt.playerInfo {
						let r = try players.decode(pkt.payload)
						typed += 1
						if verbose && (!r.added.isEmpty || !r.updated.isEmpty) {
							print("  PLAYER_INFO added \(r.added) removed \(r.removed) updated \(r.updated.keys.sorted()) local \(players.localIds)")
							for (id, m) in r.updated { if let a = m.appearance { print("    #\(id) \(a.name ?? "?") cb \(a.combatLevel) female \(a.female) bas \(a.basId)") } }
						}
						continue
					}
					if pkt.opcode == ServerProt.npcInfo {
						let me = players.players[players.selfIndex]!
						let r = try npcs.decode(pkt.payload, selfX: me.x, selfZ: me.z)
						typed += 1
						if verbose && !r.added.isEmpty {
							print("  NPC_INFO added \(r.added.map { "#\($0) type \(npcs.npcs[$0]!.type) at \(npcs.npcs[$0]!.x),\(npcs.npcs[$0]!.z)" })")
						}
						continue
					}
					let msg = try ServerMessage.decode(pkt)
					if case .rebuildNormal(let r) = msg {
						let dx = (r.zoneX - zone.x) * 8, dz = (r.zoneZ - zone.z) * 8
						players.rebase(dx: dx, dz: dz)
						npcs.rebase(dx: dx, dz: dz)
						zone = (r.zoneX, r.zoneZ)
						print("  rebuild -> world (\(r.worldX), \(r.worldZ))")
					}
					if case .unhandled(let op, _) = msg {
						unhandled[op, default: 0] += 1
					} else {
						typed += 1
						if verbose { print("  \(msg)") }
					}
				} catch {
					failures.append("\(error) payload=\(pkt.payload.map { String($0) }.joined(separator: ","))")
				}
			}
		}
		print("decoded \(typed) typed messages in \(Int(seconds))s")
		print("not yet decoded (opcode: count): \(unhandled.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", "))")
		print("decode failures: \(failures.count)")
		if let path = recordPath {
			try Data(recording).write(to: URL(fileURLWithPath: path))
			print("recorded \(recording.count) bytes to \(path)")
		}
		let me = players.players[players.selfIndex]!
		print("self at scene \(me.x),\(me.z); players tracked \(players.players.count), npcs tracked \(npcs.npcs.count)")
		for f in Set(failures).sorted() { print("  \(f)") }
	default:
		usage()
	}
} catch {
	print("error: \(error)")
	exit(1)
}
