/// Synchronous JS5 client: handshake, then request groups and wait for them.
/// Enough for the probe and for an initial "download the cache" step.
public final class Js5Client {
	public let socket: BlockingSocket
	private var parser = Js5Protocol.ResponseParser()
	private var ready: [Int: Js5Protocol.Response] = [:]

	public struct Rejected: Error, CustomStringConvertible {
		public let status: Int
		public var description: String { "JS5 handshake rejected with status \(status)" + (status == 6 ? " (client out of date)" : "") }
	}

	public init(host: String, port: Int, revision: Int = Js5Protocol.revision, loggedIn: Bool = false) throws {
		socket = try BlockingSocket(host: host, port: port)
		try socket.write(Js5Protocol.handshake(revision: revision))
		let status = Int(try socket.readExactly(1)[0])
		guard status == 0 else { throw Rejected(status: status) }
		try socket.write(Js5Protocol.sessionStart(loggedIn: loggedIn))
	}

	/// Requests several groups at once (rt4 keeps up to 20 in flight) and
	/// returns their containers in request order.
	public func fetch(_ wanted: [(archive: Int, group: Int)]) throws -> [[UInt8]] {
		var results: [[UInt8]] = []
		var i = 0
		while i < wanted.count {
			let batch = wanted[i..<min(i + 20, wanted.count)]
			var req: [UInt8] = []
			for w in batch { req += Js5Protocol.request(archive: w.archive, group: w.group) }
			try socket.write(req)
			for w in batch {
				let key = w.archive << 16 | w.group
				while ready[key] == nil {
					let chunk = try socket.readSome()
					guard !chunk.isEmpty else { throw BlockingSocket.Failure(description: "JS5 connection closed") }
					for r in try parser.feed(chunk) { ready[r.archive << 16 | r.group] = r }
				}
				results.append(ready.removeValue(forKey: key)!.container)
			}
			i += batch.count
		}
		return results
	}

	public func fetch(archive: Int, group: Int) throws -> [UInt8] {
		try fetch([(archive, group)])[0]
	}

	/// Archive 255 group 255: [crc:4][version:4] per archive, inside an uncompressed container.
	public func masterIndex() throws -> [(crc: Int32, version: Int32)] {
		try Js5MasterIndex.parse(fetch(archive: 255, group: 255))
	}
}

public enum Js5MasterIndex {
	public static func parse(_ container: [UInt8]) throws -> [(crc: Int32, version: Int32)] {
		var p = Packet(try Js5Container.decompress(container))
		var out: [(Int32, Int32)] = []
		while p.remaining >= 8 {
			out.append((try p.g4(), try p.g4()))
		}
		return out
	}
}
