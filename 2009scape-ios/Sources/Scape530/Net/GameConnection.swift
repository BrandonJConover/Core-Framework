import Foundation

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
		/// True when a reconnect was answered with code 15: the old stream carries on, so there is no first packet.
		public var resumed = false
	}

	public struct Failure: Error, CustomStringConvertible {
		public let reply: Login.Reply
		public var description: String { Login.message(for: reply) }
	}

	/// Opens the game connection. The iOS app replaces this with a Network.framework transport.
	public static var transportFactory: (_ host: String, _ port: Int) throws -> any ByteTransport = { host, port in
		try BlockingSocket(host: host, port: port)
	}

	/// Login hooks: `queued` fires on reply 1 (rt4 `LoginManager` step 5, the video-advert wait), then the login
	/// holds until `proceed` returns true (CS2 op 5601 `skipLoginStage10`) and answers with opcode 17.
	public struct Hooks {
		public var queued: () -> Void = {}
		public var proceed: () -> Bool = { true }
		/// Seconds to hold in the queued state before giving up.
		public var queuedTimeout: TimeInterval = 60
		public var cancelled: () -> Bool = { false }
		public init() {}
	}

	public static func login(host: String, port: Int, request: Login.Request, hooks: Hooks = Hooks()) throws -> Session {
		// rt4 `LoginManager.loop` step 4: reply 23 ("no reply from login server") is retried once on a fresh connection.
		do {
			return try attempt(host: host, port: port, request: request, hooks: hooks)
		} catch let f as Failure {
			if case .failure(23) = f.reply { return try attempt(host: host, port: port, request: request, hooks: hooks) }
			throw f
		}
	}

	static func attempt(host: String, port: Int, request: Login.Request, hooks: Hooks) throws -> Session {
		let s = try transportFactory(host, port)
		try s.write(Login.handshake(username: request.username))
		let status = Int(try s.readExactly(1)[0])
		guard status == 0 else { s.close(); throw Failure(reply: .failure(status)) }
		var keyPacket = Packet(try s.readExactly(8))
		let serverKey = try keyPacket.g8()
		let enc = Login.encode(request, serverKey: serverKey)
		try s.write(enc.packet)

		var out = IsaacRandom(seed: enc.seeds)
		var reply = Int(try s.readExactly(1)[0])
		if reply == 1 {
			// Step 5 / 6: wait for the script to release the login, answer p1isaac(17), read the next reply.
			hooks.queued()
			let deadline = Date().addingTimeInterval(hooks.queuedTimeout)
			while !hooks.proceed() {
				if hooks.cancelled() || Date() > deadline { s.close(); throw Failure(reply: .retry) }
				Thread.sleep(forTimeInterval: 0.02)
			}
			try s.write([UInt8(truncatingIfNeeded: 17 + out.nextKey())])
			reply = Int(try s.readExactly(1)[0])
		}
		switch reply {
		case 2:
			let account = try Login.parseSuccess(try s.readExactly(14))
			let first = try s.readExactly(account.firstLength)
			let inSeeds = enc.seeds.map { $0 &+ 50 }
			return Session(socket: s, account: account, firstPacket: first, outCipher: out, inCipher: IsaacRandom(seed: inSeeds))
		case 15 where request.reconnecting && request.resumeAccount != nil:
			let inSeeds = enc.seeds.map { $0 &+ 50 }
			return Session(socket: s, account: request.resumeAccount!, firstPacket: [], outCipher: out, inCipher: IsaacRandom(seed: inSeeds), resumed: true)
		case 21: s.close(); throw Failure(reply: .hopDelay((Int(try s.readExactly(1)[0]) + 3) * 60))
		case 29: let r = Int(try s.readExactly(1)[0]); s.close(); throw Failure(reply: .disallowed(r))
		case 1: s.close(); throw Failure(reply: .retry)
		default: s.close(); throw Failure(reply: .failure(reply))
		}
	}
}
