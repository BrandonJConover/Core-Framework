import Foundation

/// A live game connection on its own thread: logs in, frames and decodes
/// every server packet (entity updates must be decoded in order, so they are
/// decoded here too), sends keepalives and queued client messages. The UI
/// thread drains `poll()` once per frame. Works the same against a remote
/// server or a future on-device one, since both speak the socket protocol.
public final class GameSession {
	public enum Event {
		case loggedIn(Login.Success)
		case message(ServerMessage)
		case players(PlayerInfoDecoder.Result, PlayerInfoDecoder)
		case npcs(PlayerInfoDecoder.Result, NpcInfoDecoder)
		case decodeFailed(opcode: Int, error: String)
		/// The server refused the login (reply code, hop delay, ...).
		case loginFailed(Login.Reply)
		case disconnected(String?)
		/// Login reply 1: the server holds the login (rt4 `LoginManager` step 5) until `skipLoginStage()`.
		case loginQueued
	}

	public let host: String
	public let port: Int
	private let request: Login.Request
	private let lock = NSLock()
	private var inbox: [Event] = []
	private var outbox: [ClientMessage] = []
	private var stopping = false
	private var thread: Thread?
	/// Seconds to wait before connecting (reconnect back-off).
	public var startDelay: TimeInterval = 0
	private var skipRequested = false
	private var verifyIdValue: Int
	/// rt4 `Protocol.verifyId` as of the last packet the network thread decoded; a reconnect login sends it again.
	public var verifyId: Int { lock.lock(); defer { lock.unlock() }; return verifyIdValue }

	public init(host: String, port: Int, request: Login.Request) {
		self.host = host
		self.port = port
		self.request = request
		self.verifyIdValue = request.verifyId
	}

	/// CS2 5601 `skipLoginStage10`: release a login held at reply 1.
	public func skipLoginStage() {
		lock.lock(); skipRequested = true; lock.unlock()
	}

	public func start() {
		let t = Thread { [weak self] in self?.run() }
		t.name = "scape530.session"
		thread = t
		t.start()
	}

	public func send(_ m: ClientMessage) {
		lock.lock(); outbox.append(m); lock.unlock()
	}

	public func close() {
		lock.lock(); stopping = true; lock.unlock()
	}

	/// Events since the last call, oldest first.
	public func poll() -> [Event] {
		lock.lock(); defer { lock.unlock() }
		let e = inbox
		inbox.removeAll()
		return e
	}

	private func post(_ e: Event) {
		lock.lock(); inbox.append(e); lock.unlock()
	}

	private func run() {
		if startDelay > 0 { Thread.sleep(forTimeInterval: startDelay) }
		lock.lock(); let cancelled = stopping; lock.unlock()
		if cancelled { post(.disconnected(nil)); return }
		let session: GameConnection.Session
		do {
			var hooks = GameConnection.Hooks()
			hooks.queued = { [weak self] in self?.post(.loginQueued) }
			hooks.proceed = { [weak self] in
				guard let self else { return true }
				self.lock.lock(); defer { self.lock.unlock() }
				return self.skipRequested
			}
			hooks.cancelled = { [weak self] in
				guard let self else { return true }
				self.lock.lock(); defer { self.lock.unlock() }
				return self.stopping
			}
			session = try GameConnection.login(host: host, port: port, request: request, hooks: hooks)
		} catch let failure as GameConnection.Failure {
			post(.loginFailed(failure.reply))
			return
		} catch {
			post(.disconnected("\(error)"))
			return
		}
		post(.loggedIn(session.account))
		var framer = GamePacketFramer(cipher: session.inCipher)
		var out = session.outCipher
		var pipeline = Pipeline(selfId: session.account.selfId, verifyId: request.verifyId)

		func handle(_ pkt: GamePacket) {
			for e in pipeline.handle(pkt) { post(e) }
		}

		if !session.resumed { handle(GamePacket(opcode: session.account.firstOpcode, payload: session.firstPacket)) }
		session.socket.setReadTimeout(milliseconds: 50)
		var lastSend = Date()
		while true {
			lock.lock()
			let stop = stopping
			let pending = outbox
			outbox.removeAll()
			lock.unlock()
			if stop { break }
			do {
				for m in pending { try session.socket.write(m.encode(&out)); lastSend = Date() }
				// rt4 `Protocol` flush: TRANSMITVAR_VERIFYID follows the other packets when `setVerifyId` ran since.
				if let v = pipeline.takeVerifyId() {
					lock.lock(); verifyIdValue = v; lock.unlock()
					try session.socket.write(ClientMessage.verifyId(v).encode(&out)); lastSend = Date()
				}
				// rt4 sends NO_TIMEOUT when nothing else went out for ~1 s.
				if Date().timeIntervalSince(lastSend) >= 1 {
					try session.socket.write(ClientMessage.keepAlive.encode(&out))
					lastSend = Date()
				}
			} catch {
				post(.disconnected("\(error)"))
				return
			}
			guard let chunk = try? session.socket.readSome() else { continue }
			if chunk.isEmpty {
				post(.disconnected("The server closed the connection."))
				return
			}
			do {
				for pkt in try framer.feed(chunk) { handle(pkt) }
			} catch {
				// A framing error means we lost sync with the stream.
				post(.disconnected("\(error)"))
				return
			}
		}
		session.socket.close()
		post(.disconnected(nil))
	}

	/// The decoding half of the network thread, separated so tests can feed it packets: it owns the
	/// stateful PLAYER_INFO / NPC_INFO decoders and keeps them aligned with map rebuilds and teleports.
	public struct Pipeline {
		public private(set) var players: PlayerInfoDecoder
		public private(set) var npcs = NpcInfoDecoder()
		private var zone: (x: Int, z: Int)?
		private let selfId: Int
		/// rt4 `Protocol.verifyId`: the last tracknum + 1 (16 bits), re-sent to the server through `takeVerifyId`.
		public private(set) var verifyId: Int
		private var verifyIdChanged = false

		public init(selfId: Int, verifyId: Int = 0) {
			self.selfId = selfId
			self.verifyId = verifyId
			players = PlayerInfoDecoder(selfIndex: selfId, localX: 52, localZ: 52)
		}

		/// rt4 `Protocol.setVerifyId`.
		mutating func setVerifyId(_ tracknum: Int) {
			verifyId = (tracknum + 1) & 0xFFFF
			verifyIdChanged = true
		}

		/// The verify id to transmit when it changed since the last call (rt4 `verifyIdChanged` / `transmitVerifyId`).
		public mutating func takeVerifyId() -> Int? {
			guard verifyIdChanged else { return nil }
			verifyIdChanged = false
			return verifyId
		}

		/// Decodes one packet into the events the UI thread should see.
		public mutating func handle(_ pkt: GamePacket) -> [Event] {
			do {
				switch pkt.opcode {
				case ServerProt.playerInfo:
					let r = try players.decode(pkt.payload)
					return [.players(r, players)]
				case ServerProt.npcInfo:
					guard let me = players.players[players.selfIndex] else { return [] }
					let r = try npcs.decode(pkt.payload, selfX: me.x, selfZ: me.z)
					return [.npcs(r, npcs)]
				default:
					let (m, track) = try ServerMessage.decodeTracked(pkt)
					if let t = track { setVerifyId(t) }
					switch m {
					case .rebuildNormal(let r), .rebuildRegion(let r):
						if let z = zone {
							players.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
							npcs.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
						} else {
							players = PlayerInfoDecoder(selfIndex: selfId, localX: r.localX, localZ: r.localZ)
						}
						zone = (r.zoneX, r.zoneZ)
					case let .teleportLocalPlayer(x, z, plane, jump):
						// rt4 `Protocol` TELEPORT_LOCAL_PLAYER: `Player.plane = flags >> 1; self.teleport(x, jump, z)`.
						// The world view follows the decoder, so republish it right after the message.
						players.teleportSelf(x: x, z: z, plane: plane, jump: jump)
						return [.message(m), .players(PlayerInfoDecoder.Result(), players)]
					default:
						break
					}
					return [.message(m)]
				}
			} catch {
				return [.decodeFailed(opcode: pkt.opcode, error: "\(error)")]
			}
		}
	}
}
