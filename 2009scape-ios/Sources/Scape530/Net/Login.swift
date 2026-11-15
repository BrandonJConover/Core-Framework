/// Rev-530 game login, ported from rt4 `LoginManager.loop` (steps 2-9) with
/// 2009scape's `GlobalConfig` switches: LOGIN_EXTRA_INFO = true,
/// LOGIN_FAKE_IDX28 = true, USE_ISAAC = false.
public enum Login {
	/// Step 2: [14][(name37 >> 16) & 31]. Server replies a status byte (0 = go
	/// on) and then the 8-byte server session key.
	public static func handshake(username: String) -> [UInt8] {
		let hash = Int((Base37.encode(username) >> 16) & 0x1F)
		return [14, UInt8(hash)]
	}

	public struct Request {
		public var username: String
		public var password: String
		public var reconnecting = false
		public var revision = 530
		/// `LoginManager.anInt39`, -1 until the world list sets it.
		public var worldSelector = -1
		public var advertSuppressed = true
		/// rt4 `DisplayMode.getWindowMode()`: 1 fixed, 2 resizable, 3 fullscreen.
		public var windowMode = 1
		public var canvasWidth = 765
		public var canvasHeight = 503
		public var antiAliasingMode = 0
		public var uid = [UInt8](repeating: 0, count: 24)
		public var settings = ""
		public var affiliate: Int32 = 0
		public var preferences: Int32 = 0
		public var verifyId = 0
		/// CRCs of archives 0...27 from the master index (rt4 sends 28, plus a fake 0 for idx28).
		public var archiveChecksums = [Int32](repeating: 0, count: 28)
		public var rsa = RsaKey.scape2009

		public init(username: String, password: String) {
			self.username = username
			self.password = password
		}
	}

	public struct Encoded {
		public let packet: [UInt8]
		/// The four ISAAC seed ints; outbound cipher = seeds, inbound = seeds + 50.
		public let seeds: [Int32]
	}

	/// Step 3, given the server key read after the handshake.
	public static func encode(_ r: Request, serverKey: Int64,
	                          clientSeeds: (Int32, Int32) = (Int32.random(in: 0..<99_999_999), Int32.random(in: 0..<99_999_999))) -> Encoded {
		let seeds: [Int32] = [clientSeeds.0, clientSeeds.1, Int32(truncatingIfNeeded: serverKey >> 32), Int32(truncatingIfNeeded: serverKey)]

		var secure = Packet(capacity: 128)
		secure.p1(10)
		for s in seeds { secure.p4(s) }
		secure.p8(Base37.encode(r.username))
		secure.pjstr(r.password)
		secure.pjstr("")
		secure.pjstr("")
		secure.pjstr("")
		let rsaBlock = r.rsa.encryptBlock(secure.written)

		var p = Packet(capacity: 400)
		p.p1(r.reconnecting ? 18 : 16)
		p.p2(rsaBlock.count + Cp1252.encode(r.settings).count + 1 + 159 + 4)
		p.p4(r.revision)
		p.p1(r.worldSelector)
		p.p1(r.advertSuppressed ? 1 : 0)
		p.p1(1)
		p.p1(r.windowMode)
		p.p2(r.canvasWidth)
		p.p2(r.canvasHeight)
		p.p1(r.antiAliasingMode)
		p.pdata(r.uid.prefix(24))
		p.pjstr(r.settings)
		p.p4(r.affiliate)
		p.p4(r.preferences)
		p.p2(r.verifyId)
		for i in 0..<28 { p.p4(i < r.archiveChecksums.count ? r.archiveChecksums[i] : 0) }
		p.p4(0) // LOGIN_FAKE_IDX28
		p.pdata(rsaBlock)
		return Encoded(packet: p.written, seeds: seeds)
	}

	public enum Reply: Equatable {
		/// Code 2 followed by the 14-byte account block.
		case success(Success)
		/// Code 21: world hop delay, `(byte + 3) * 60` ticks in rt4.
		case hopDelay(Int)
		/// Code 29: disallowed with a reason byte.
		case disallowed(Int)
		/// Code 1: retry (server loading); rt4 sends opcode 17 and waits again.
		case retry
		case failure(Int)
	}

	public struct Success: Equatable {
		public var staffModLevel: Int
		public var blackmarks: Int
		public var underage: Bool
		public var parentalChatConsent: Bool
		public var parentalAdvertConsent: Bool
		public var mapQuickChat: Bool
		public var mouseRecorder: Bool
		public var selfId: Int
		public var member: Bool
		public var mapMembers: Bool
		/// First game packet header (the REBUILD_NORMAL that follows).
		public var firstOpcode: Int
		public var firstLength: Int
	}

	/// Human readable text for a reply code (rt4 login screen strings, abridged).
	public static func message(for code: Int) -> String {
		switch code {
		case 3: return "Invalid username or password."
		case 4: return "Your account has been disabled."
		case 5: return "Your account is already logged in."
		case 6: return "The game has been updated. Please reload."
		case 7: return "This world is full."
		case 8: return "Unable to connect: login server offline."
		case 9: return "Login limit exceeded: too many connections from your address."
		case 10: return "Unable to connect: bad session id."
		case 12: return "You need a members account to log in to this world."
		case 13: return "Could not complete login. Please try again."
		case 14: return "The server is being updated. Please wait."
		case 16: return "Too many login attempts. Please wait a few minutes."
		case 17: return "You are standing in a members-only area."
		case 18: return "Account locked as we suspect it has been stolen."
		case 20: return "Invalid loginserver requested."
		case 22: return "Malformed login packet."
		case 23: return "No reply from loginserver."
		case 24: return "Error loading your profile."
		case 26: return "This computer's address has been blocked."
		default: return "Unexpected server response (\(code))."
		}
	}

	public static func parseSuccess(_ b: [UInt8]) throws -> Success {
		var p = Packet(b)
		return Success(
			staffModLevel: try p.g1(),
			blackmarks: try p.g1(),
			underage: try p.g1() == 1,
			parentalChatConsent: try p.g1() == 1,
			parentalAdvertConsent: try p.g1() == 1,
			mapQuickChat: try p.g1() == 1,
			mouseRecorder: try p.g1() == 1,
			selfId: try p.g2(),
			member: try p.g1() == 1,
			mapMembers: try p.g1() == 1,
			firstOpcode: try p.g1(),
			firstLength: try p.g2()
		)
	}
}
