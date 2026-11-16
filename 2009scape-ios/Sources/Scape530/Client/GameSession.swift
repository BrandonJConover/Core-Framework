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
	}

	public let host: String
	public let port: Int
	private let request: Login.Request
	private let lock = NSLock()
	private var inbox: [Event] = []
	private var outbox: [ClientMessage] = []
	private var stopping = false
	private var thread: Thread?

	public init(host: String, port: Int, request: Login.Request) {
		self.host = host
		self.port = port
		self.request = request
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
		let session: GameConnection.Session
		do {
			session = try GameConnection.login(host: host, port: port, request: request)
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
		var players = PlayerInfoDecoder(selfIndex: session.account.selfId, localX: 52, localZ: 52)
		var npcs = NpcInfoDecoder()
		var zone: (x: Int, z: Int)?

		func handle(_ pkt: GamePacket) {
			do {
				switch pkt.opcode {
				case ServerProt.playerInfo:
					let r = try players.decode(pkt.payload)
					post(.players(r, players))
				case ServerProt.npcInfo:
					guard let me = players.players[players.selfIndex] else { return }
					let r = try npcs.decode(pkt.payload, selfX: me.x, selfZ: me.z)
					post(.npcs(r, npcs))
				default:
					let m = try ServerMessage.decode(pkt)
					if case .rebuildNormal(let r) = m {
						if let z = zone {
							players.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
							npcs.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
						} else {
							players = PlayerInfoDecoder(selfIndex: session.account.selfId, localX: r.localX, localZ: r.localZ)
						}
						zone = (r.zoneX, r.zoneZ)
					}
					post(.message(m))
				}
			} catch {
				post(.decodeFailed(opcode: pkt.opcode, error: "\(error)"))
			}
		}

		handle(GamePacket(opcode: session.account.firstOpcode, payload: session.firstPacket))
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
}
