/// Runs the blocking login flow over a `BlockingSocket`. The returned socket
/// is positioned right after the first packet header, whose payload (the
/// REBUILD_NORMAL map packet) is returned too.
public enum GameConnection {
	public struct Session {
		public let socket: any ByteTransport
		public let account: Login.Success
		public let firstPacket: [UInt8]
		public var outCipher: IsaacRandom
		public var inCipher: IsaacRandom
	}

	public struct Failure: Error, CustomStringConvertible {
		public let reply: Login.Reply
		public var description: String {
			switch reply {
			case .failure(let c): return Login.message(for: c)
			case .hopDelay(let s): return "World hop delay, try again in \(s) ticks."
			case .disallowed(let r): return "Login disallowed (reason \(r))."
			case .retry: return "Server busy, retry."
			case .success: return "ok"
			}
		}
	}

	/// Opens the game connection. The iOS app replaces this with a Network.framework transport.
	public static var transportFactory: (_ host: String, _ port: Int) throws -> any ByteTransport = { host, port in
		try BlockingSocket(host: host, port: port)
	}

	public static func login(host: String, port: Int, request: Login.Request) throws -> Session {
		let s = try transportFactory(host, port)
		try s.write(Login.handshake(username: request.username))
		let status = Int(try s.readExactly(1)[0])
		guard status == 0 else { throw Failure(reply: .failure(status)) }
		var keyPacket = Packet(try s.readExactly(8))
		let serverKey = try keyPacket.g8()
		let enc = Login.encode(request, serverKey: serverKey)
		try s.write(enc.packet)

		let reply = Int(try s.readExactly(1)[0])
		switch reply {
		case 2:
			let account = try Login.parseSuccess(try s.readExactly(14))
			let first = try s.readExactly(account.firstLength)
			let out = IsaacRandom(seed: enc.seeds)
			let inSeeds = enc.seeds.map { $0 &+ 50 }
			return Session(socket: s, account: account, firstPacket: first, outCipher: out, inCipher: IsaacRandom(seed: inSeeds))
		case 21: throw Failure(reply: .hopDelay((Int(try s.readExactly(1)[0]) + 3) * 60))
		case 29: throw Failure(reply: .disallowed(Int(try s.readExactly(1)[0])))
		case 1: throw Failure(reply: .retry)
		default: throw Failure(reply: .failure(reply))
		}
	}
}
