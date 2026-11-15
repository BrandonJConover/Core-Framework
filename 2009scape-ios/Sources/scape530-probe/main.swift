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
		if args.count >= 7, let js5Port = Int(args[6]) {
			req.archiveChecksums = Array(try js5Command(args[2], js5Port).prefix(28))
		}
		let session = try GameConnection.login(host: args[2], port: port, request: req)
		print("logged in: \(session.account)")
		print("first packet: opcode \(session.account.firstOpcode), \(session.firstPacket.count) bytes")
		if session.account.firstOpcode == ServerProt.rebuildNormal {
			let rebuild = try RebuildNormal(payload: session.firstPacket)
			print("rebuild: world (\(rebuild.worldX), \(rebuild.worldZ)) plane \(rebuild.plane), regions \(rebuild.regions.map(\.locGroupName))")
		}
		// Read a few seconds of game packets to prove framing stays aligned.
		var framer = GamePacketFramer(cipher: session.inCipher)
		var counts: [Int: Int] = [:]
		let deadline = Date().addingTimeInterval(5)
		while Date() < deadline {
			guard let chunk = try? session.socket.readSome(), !chunk.isEmpty else { break }
			for pkt in try framer.feed(chunk) { counts[pkt.opcode, default: 0] += 1 }
		}
		print("packets in 5s by opcode: \(counts.sorted { $0.key < $1.key })")
	default:
		usage()
	}
} catch {
	print("error: \(error)")
	exit(1)
}
