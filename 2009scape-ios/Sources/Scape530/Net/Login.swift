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
		/// rt4 `Protocol.verifyId`: the last verify id (`setVerifyId`), re-sent on a reconnect so the server keeps counting.
		public var verifyId = 0
		/// The account block of the session being resumed, used when a reconnect is answered with code 15.
		public var resumeAccount: Success?
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
		/// Code 15 on a reconnect login (opcode 18): the server resumed the old session, no account block follows.
		case reconnected
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

	/// The text the cache's login screen script (clientscript 711, which rev 530 uses in place of any
	/// `LocalizedText` entry) shows for a `LoginManager.reply` code, with its link markup reduced to the
	/// plain words. Negative codes are the client's own states: -2 idle, -3 connecting is not an error,
	/// -4 / -5 / -1 are the connect failures `LoginManager.loop` raises. Code 21 is `message(forHopDelay:)`
	/// and code 29 is `message(forDisallow:)`; unknown codes read as the script's default branch.
	public static func message(for code: Int) -> String {
		switch code {
		case -2: return "Enter your username and password."
		case -5: return "Connection timed out. Please try using a different world."
		case -4: return "Error connecting to server."
		case -1: return "No response from server. Please try using a different world."
		case 3: return "Invalid username or password. If you have forgotten your password, click here."
		case 4: return "Your account has been disabled. Please click here to check your Message Centre for details."
		case 5: return "Your account has not logged out from its last session. Try again in a few minutes."
		case 6: return "RuneScape has been updated! Please reload this page."
		case 7: return "This world is full. Please use a different world."
		case 8: return "Unable to connect: login server offline."
		case 9: return "Login limit exceeded: too many connections from your address."
		case 10: return "Unable to connect: bad session ID."
		case 11: return "Your password is an extremely common choice, and is very weak. You must change it before you can login. Click here"
		case 12: return "You need a members' account to log in to this world. Please subscribe or use a different world. "
		case 13: return "Could not complete login. Please try using a different world."
		case 14: return "The server is being updated. Please wait a few minutes and try again."
		case 16: return "Too many incorrect logins from your address. Please wait 5 minutes before trying again."
		case 17: return "You are standing in a members-only area. To play on this world, move to a free area first."
		case 18: return "Your account has been locked as we suspect it has been stolen. Click here to recover your account."
		case 19: return "Fullscreen is currently a members-only feature. To log in, either return to the main menu and exit fullscreen or use a members' account."
		case 20: return "Invalid loginserver requested. Please try using a different world."
		case 22: return "Malformed login packet. Please try again."
		case 23: return "No reply from login server. Please wait a minute and try again."
		case 24: return "Error loading your profile. Please contact Customer Support."
		case 25: return "Unexpected loginserver response. Please try using a different world."
		case 26: return "This computer's address has been blocked as it was used to break our rules."
		case 27: return "Service unavailable."
		case 30: return "This is not a member's account; please choose the 'Free Users' option from the website to play on this account."
		default: return "Unexpected server response. Please try using a different world."
		}
	}

	/// Reply 21 (`LoginManager.hopTime` = `(byte + 3) * 60` ticks of 20 ms): the script divides by 50 for seconds.
	public static func message(forHopDelay ticks: Int) -> String {
		"You have only just left another world. Your profile will be transferred in \(ticks / 50) seconds."
	}

	/// Reply 29 with its detail byte (`LoginManager.disallowResult`, clientscript 1894).
	public static func message(forDisallow reason: Int) -> String {
		switch reason {
		case 0: return "You must have a Combat Level of at least 20 (without Summoning) to enter a PvP world."
		case 1: return "You are currently carrying lent items and cannot enter a PvP world."
		default: return "Unexpected server response. Please try using a different world."
		}
	}

	/// The line for a whole reply as `GameConnection` reports it.
	public static func message(for reply: Reply) -> String {
		switch reply {
		case .success, .reconnected: return ""
		case .hopDelay(let t): return message(forHopDelay: t)
		case .disallowed(let r): return message(forDisallow: r)
		case .retry: return "Please wait while your login is processed."
		case .failure(let c): return message(for: c)
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
