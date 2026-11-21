import Foundation
import XCTest
@testable import Scape530

/// TRANSMITVAR_VERIFYID, EVENT_APPLET_FOCUS, EVENT_CAMERA_POSITION, WINDOW_STATUS, the reply codes of the login
/// handshake and the CS2 world ops (rt4 `Protocol`, `ClientProt`, `LoginManager`, `ScriptRunner` 6500-6507).
final class HousekeepingTests: XCTestCase {
	private func encode(_ m: ClientMessage) -> [UInt8] {
		var c = IsaacRandom(seed: [0, 0, 0, 0]) // ISAAC off: the key is 0, so the opcode is plain
		return m.encode(&c)
	}

	// MARK: packet encodings

	func testVerifyIdPacket() {
		XCTAssertEqual(encode(.verifyId(0x1234)), [177, 0x12, 0x34])
	}

	func testAppletFocusPacket() {
		XCTAssertEqual(encode(.appletFocus(true)), [22, 1])
		XCTAssertEqual(encode(.appletFocus(false)), [22, 0])
	}

	func testCameraPositionPacket() {
		// rt4: p1isaac(21); p2add(pitch); ip2(yaw).
		XCTAssertEqual(encode(.cameraPosition(pitch: 0x0180, yaw: 0x0123)), [21, 0x01, 0x80 &+ 128, 0x23, 0x01])
	}

	func testWindowStatusPacket() {
		XCTAssertEqual(encode(.windowStatus(mode: 2, width: 1015, height: 469, antiAliasing: 1)), [243, 2, 0x03, 0xF7, 0x01, 0xD5, 1])
	}

	// MARK: verify id bookkeeping

	func testPipelineTracksVerifyId() {
		var p = GameSession.Pipeline(selfId: 1)
		XCTAssertNil(p.takeVerifyId())
		// CAM_RESET carries only the tracknum (g2).
		_ = p.handle(GamePacket(opcode: ServerProt.camReset, payload: [0x01, 0x02]))
		XCTAssertEqual(p.verifyId, 0x0103)
		XCTAssertEqual(p.takeVerifyId(), 0x0103)
		XCTAssertNil(p.takeVerifyId(), "sent once per change")
		// IF_SETHIDE: g1neg, tracknum g2, ig4.
		_ = p.handle(GamePacket(opcode: ServerProt.ifSethide, payload: [0xFF, 0x00, 0x09, 1, 0, 0, 0]))
		XCTAssertEqual(p.takeVerifyId(), 10)
		// IF_SETANGLE reads the tracknum in the middle (g2, g2add, ...): g2add = hi<<8 | (lo - 128).
		_ = p.handle(GamePacket(opcode: ServerProt.ifSetangle, payload: [0, 5, 0x00, 0x85, 0, 0, 0, 0, 0, 0, 0, 0]))
		XCTAssertEqual(p.takeVerifyId(), 6)
		// 16-bit wrap: tracknum 0xFFFF -> 0.
		_ = p.handle(GamePacket(opcode: ServerProt.camReset, payload: [0xFF, 0xFF]))
		XCTAssertEqual(p.takeVerifyId(), 0)
		// A packet without a tracknum leaves it alone.
		_ = p.handle(GamePacket(opcode: ServerProt.logout, payload: []))
		XCTAssertNil(p.takeVerifyId())
	}

	func testPipelineStartsFromTheReconnectVerifyId() {
		let p = GameSession.Pipeline(selfId: 1, verifyId: 42)
		XCTAssertEqual(p.verifyId, 42)
	}

	func testEveryTrackedPacketKindDecodesATracknum() throws {
		// One sample per rt4 branch that calls `setVerifyId`; the payloads are zero padded to the decoder's length.
		let tracked: [Int] = [ServerProt.runCs2, ServerProt.ifSettext1, ServerProt.ifSettext2, ServerProt.ifSettext3, ServerProt.ifSethide,
		                     ServerProt.ifOpentop, ServerProt.ifOpensub, ServerProt.ifClosesub, ServerProt.ifSetanim, ServerProt.ifSetmodel,
		                     ServerProt.ifSetnpchead, ServerProt.ifSetplayerhead, ServerProt.ifSetobject, ServerProt.ifSetcolour,
		                     ServerProt.ifSetposition, ServerProt.ifSetangle, ServerProt.ifSetscrollpos, ServerProt.setInterfaceSettings,
		                     ServerProt.clientSetvarcSmall, ServerProt.clientSetvarcLarge, ServerProt.camShake, ServerProt.camReset,
		                     ServerProt.camLookat, ServerProt.camForceangle, ServerProt.cameraDetach, ServerProt.switchWidget,
		                     ServerProt.widgetstructSetting, ServerProt.interfaceAnimateRotate, ServerProt.generateChatHeadFromBody]
		var misses: [Int] = []
		for op in tracked {
			// Strings are read first for runCs2 / settext: an empty one (a single 0) keeps lengths simple.
			var found = false
			for len in 0..<40 {
				let payload = [UInt8](repeating: 0, count: len)
				if let r = try? ServerMessage.decodeTracked(GamePacket(opcode: op, payload: payload)), r.track != nil { found = true; break }
			}
			if !found { misses.append(op) }
		}
		XCTAssertEqual(misses, [])
	}

	// MARK: login replies

	func testEveryLoginReplyHasTheCacheScriptsText() {
		let expected: [Int: String] = [
			-2: "Enter your username and password.",
			-5: "Connection timed out. Please try using a different world.",
			-4: "Error connecting to server.",
			-1: "No response from server. Please try using a different world.",
			3: "Invalid username or password. If you have forgotten your password, click here.",
			4: "Your account has been disabled. Please click here to check your Message Centre for details.",
			5: "Your account has not logged out from its last session. Try again in a few minutes.",
			6: "RuneScape has been updated! Please reload this page.",
			7: "This world is full. Please use a different world.",
			8: "Unable to connect: login server offline.",
			9: "Login limit exceeded: too many connections from your address.",
			10: "Unable to connect: bad session ID.",
			13: "Could not complete login. Please try using a different world.",
			14: "The server is being updated. Please wait a few minutes and try again.",
			16: "Too many incorrect logins from your address. Please wait 5 minutes before trying again.",
			17: "You are standing in a members-only area. To play on this world, move to a free area first.",
			20: "Invalid loginserver requested. Please try using a different world.",
			22: "Malformed login packet. Please try again.",
			23: "No reply from login server. Please wait a minute and try again.",
			24: "Error loading your profile. Please contact Customer Support.",
			25: "Unexpected loginserver response. Please try using a different world.",
			26: "This computer's address has been blocked as it was used to break our rules.",
			27: "Service unavailable.",
			15: "Unexpected server response. Please try using a different world.",
			99: "Unexpected server response. Please try using a different world.",
		]
		for (code, text) in expected { XCTAssertEqual(Login.message(for: code), text, "code \(code)") }
		XCTAssertTrue(Login.message(for: 12).hasPrefix("You need a members' account"))
		XCTAssertTrue(Login.message(for: 11).hasPrefix("Your password is an extremely common choice"))
		XCTAssertTrue(Login.message(for: 18).hasPrefix("Your account has been locked as we suspect it has been stolen."))
		XCTAssertTrue(Login.message(for: 19).hasPrefix("Fullscreen is currently a members-only feature"))
		XCTAssertTrue(Login.message(for: 30).hasPrefix("This is not a member's account"))
	}

	func testHopDelayAndDisallowTexts() {
		XCTAssertEqual(Login.message(forHopDelay: 3 * 60), "You have only just left another world. Your profile will be transferred in 3 seconds.")
		XCTAssertEqual(Login.message(forDisallow: 0), "You must have a Combat Level of at least 20 (without Summoning) to enter a PvP world.")
		XCTAssertEqual(Login.message(forDisallow: 1), "You are currently carrying lent items and cannot enter a PvP world.")
		XCTAssertEqual(Login.message(forDisallow: 7), "Unexpected server response. Please try using a different world.")
		XCTAssertEqual(Login.message(for: .hopDelay(300)), Login.message(forHopDelay: 300))
		XCTAssertEqual(Login.message(for: .disallowed(1)), Login.message(forDisallow: 1))
	}

	// MARK: handshake replies

	@discardableResult
	private func withTransports(_ list: [ScriptedTransport], _ body: () -> Void) -> Int {
		let saved = GameConnection.transportFactory
		defer { GameConnection.transportFactory = saved }
		var opened = 0
		GameConnection.transportFactory = { _, _ in defer { opened += 1 }; return list[min(opened, list.count - 1)] }
		body()
		return opened
	}

	private func loginFailure(host: String, port: Int, request: Login.Request, hooks: GameConnection.Hooks = GameConnection.Hooks()) -> GameConnection.Failure? {
		do { _ = try GameConnection.login(host: host, port: port, request: request, hooks: hooks) } catch { return error as? GameConnection.Failure }
		return nil
	}

	private let key = [UInt8](repeating: 7, count: 8)

	private func request(reconnecting: Bool = false) -> Login.Request {
		var r = Login.Request(username: "tester", password: "pw")
		r.reconnecting = reconnecting
		return r
	}

	func testReply21And29CarryTheirByte() throws {
		let hop = ScriptedTransport([0] + key + [21, 2])
		_ = withTransports([hop]) {
			let failure = loginFailure(host: "h", port: 1, request: request())
				XCTAssertEqual(failure?.reply, .hopDelay(300))
		}
		XCTAssertTrue(hop.closed)
		let dis = ScriptedTransport([0] + key + [29, 1])
		_ = withTransports([dis]) {
			let failure = loginFailure(host: "h", port: 1, request: request())
				XCTAssertEqual(failure?.reply, .disallowed(1))
				XCTAssertEqual(failure?.description, Login.message(forDisallow: 1))
		}
	}

	func testOtherCodesAreFailures() {
		for code in [3, 4, 5, 7, 11, 14, 16, 25] {
			let t = ScriptedTransport([0] + key + [UInt8(code)])
			_ = withTransports([t]) {
				let failure = loginFailure(host: "h", port: 1, request: request())
					XCTAssertEqual(failure?.reply, .failure(code))
			}
		}
		// A non-zero handshake status stops before the key.
		let t = ScriptedTransport([9])
		_ = withTransports([t]) {
			let failure = loginFailure(host: "h", port: 1, request: request())
				XCTAssertEqual(failure?.reply, .failure(9))
		}
	}

	func testReply23IsRetriedOnceOnANewConnection() {
		let a = ScriptedTransport([0] + key + [23])
		let b = ScriptedTransport([0] + key + [3])
		let opened = withTransports([a, b]) {
			let failure = loginFailure(host: "h", port: 1, request: request())
				XCTAssertEqual(failure?.reply, .failure(3))
		}
		XCTAssertEqual(opened, 2)
		// Twice in a row is final.
		let c = ScriptedTransport([0] + key + [23]), d = ScriptedTransport([0] + key + [23])
		_ = withTransports([c, d]) {
			let failure = loginFailure(host: "h", port: 1, request: request())
				XCTAssertEqual(failure?.reply, .failure(23))
		}
	}

	func testReply1WaitsForTheScriptThenAnswers17() {
		let t = ScriptedTransport([0] + key + [1, 29, 0])
		var queued = 0, polls = 0
		var hooks = GameConnection.Hooks()
		hooks.queued = { queued += 1 }
		hooks.proceed = { polls += 1; return polls > 3 }
		_ = withTransports([t]) {
			let failure = loginFailure(host: "h", port: 1, request: request(), hooks: hooks)
				XCTAssertEqual(failure?.reply, .disallowed(0))
		}
		XCTAssertEqual(queued, 1)
		XCTAssertEqual(polls, 4)
		XCTAssertEqual(t.sent.last, 17, "rt4 step 6: p1isaac(17) once the login is released")
	}

	func testReply1GivesUpWhenCancelled() {
		let t = ScriptedTransport([0] + key + [1])
		var hooks = GameConnection.Hooks()
		hooks.proceed = { false }
		hooks.cancelled = { true }
		_ = withTransports([t]) {
			let failure = loginFailure(host: "h", port: 1, request: request(), hooks: hooks)
				XCTAssertEqual(failure?.reply, .retry)
		}
		XCTAssertTrue(t.closed)
	}

	func testReply15ResumesAReconnect() throws {
		var account = Login.Success(staffModLevel: 2, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false,
		                            mapQuickChat: false, mouseRecorder: false, selfId: 5, member: true, mapMembers: true, firstOpcode: 0, firstLength: 0)
		account.selfId = 5
		var req = request(reconnecting: true)
		req.resumeAccount = account
		let t = ScriptedTransport([0] + key + [15])
		var session: GameConnection.Session?
		withTransports([t]) { session = try? GameConnection.login(host: "h", port: 1, request: req) }
		XCTAssertEqual(session?.resumed, true)
		XCTAssertEqual(session?.account.selfId, 5)
		XCTAssertEqual(session?.firstPacket, [])
		// The reconnect login (opcode 18) is what went out.
		XCTAssertEqual(t.sent[2 ... 2].first, 18)
		// Without an account to resume (or on a normal login) 15 is just an unknown reply.
		let u = ScriptedTransport([0] + key + [15])
		_ = withTransports([u]) {
			let failure = loginFailure(host: "h", port: 1, request: request())
				XCTAssertEqual(failure?.reply, .failure(15))
		}
	}

	// MARK: CS2 world ops

	private func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("needs SCAPE530_CACHE") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	private func hostWithWorlds() throws -> InterfaceScriptHost {
		let host = InterfaceScriptHost(store: try store())
		XCTAssertTrue(host.worldList.decode(WorldListFixture.body(worlds: WorldListFixture.several, countries: WorldListFixture.countries)))
		return host
	}

	func testWorldOpsWalkAndSortTheList() throws {
		let host = try hostWithWorlds()
		func call(_ opcode: Int, _ ints: [Int32] = []) -> HostResult { host.perform(HostOps.table[opcode]!, ints: ints, strings: []) }
		let first = call(6501)
		XCTAssertEqual(first.ints, [1, 9, 225, 120])
		XCTAssertEqual(first.strings, ["-", "USA"])
		XCTAssertEqual(call(6502).ints, [2, 2, 77, 40])
		// 6507: primary key 1 (players), not reversed, secondary 0, not reversed -> offline world last.
		_ = call(6507, [1, 0, 0, 0])
		XCTAssertEqual(call(6501).ints.first, 2)
		var ids: [Int32] = []
		var row = call(6501)
		while row.ints[0] != -1 { ids.append(row.ints[0]); row = call(6502) }
		XCTAssertEqual(ids, [2, 4, 1, 3])
		// 6506 world info: flags, country flag, players and the strings; unknown worlds read -1.
		let info = call(6506, [3])
		XCTAssertEqual(info.ints, [4, 77, -1])
		XCTAssertEqual(info.strings, ["Bounty hunter", "Germany"])
		XCTAssertEqual(call(6506, [99]).ints, [-1, 0, 0])
	}

	func testWorldHopOpAndPreferences() throws {
		let host = try hostWithWorlds()
		func call(_ opcode: Int, _ ints: [Int32] = []) -> HostResult { host.perform(HostOps.table[opcode]!, ints: ints, strings: []) }
		var hopped: [Int] = []
		host.onWorldHop = { hopped.append($0.id); return true }
		XCTAssertEqual(call(6503, [2]).ints, [1])
		XCTAssertEqual(call(6503, [99]).ints, [0], "no such world")
		XCTAssertEqual(hopped, [2])
		host.loginReply = -3
		XCTAssertEqual(call(6503, [3]).ints, [0], "not while a login is running")
		host.loginReply = -2
		call(6504, [2])
		XCTAssertEqual(call(6505).ints, [2])
		call(5309, [1])
		XCTAssertEqual(call(5308).ints, [1])
		call(5309, [7])
		XCTAssertEqual(call(5308).ints, [0], "out of range resets to 0, as rt4")
		call(6600, [1])
		XCTAssertEqual(call(6601).ints, [1])
	}

	func testWorldSwitchTimerAndSkipOps() throws {
		let host = try hostWithWorlds()
		host.worldSwitchTimer = 180
		XCTAssertEqual(host.perform(HostOps.table[5608]!, ints: [], strings: []).ints, [180])
		var skipped = 0
		host.onSkipLoginStage = { skipped += 1 }
		_ = host.perform(HostOps.table[5601]!, ints: [], strings: [])
		XCTAssertEqual(skipped, 1)
		// 5602 does not clear a login held at reply 1.
		host.loginReply = 1
		_ = host.perform(HostOps.table[5602]!, ints: [], strings: [])
		XCTAssertEqual(host.loginReply, 1)
		host.loginReply = 3
		_ = host.perform(HostOps.table[5602]!, ints: [], strings: [])
		XCTAssertEqual(host.loginReply, -2)
	}

	func testWorldFetchOpFallsBackToOneWorld() throws {
		let host = InterfaceScriptHost(store: try store())
		host.worldList.connect = { _, _ in throw ConnectFailure(host: "h", port: 1, reason: "down") }
		var done = 0
		for _ in 0..<600 where done == 0 {
			done = Int(host.perform(HostOps.table[6500]!, ints: [], strings: []).ints[0])
			if done == 0 { Thread.sleep(forTimeInterval: 0.01) }
		}
		XCTAssertEqual(done, 1)
		XCTAssertEqual(host.perform(HostOps.table[6501]!, ints: [], strings: []).ints.first, 1)
	}

	// MARK: live

	/// Logs in to a live server (`SCAPE530_SERVER=host:port`), then toggles focus, turns the camera and resizes:
	/// the server must keep the session (it would drop the connection on a packet it cannot parse).
	func testLiveHousekeepingPacketsKeepTheSession() throws {
		guard let server = ProcessInfo.processInfo.environment["SCAPE530_SERVER"] else { throw XCTSkip("needs SCAPE530_SERVER") }
		let parts = server.split(separator: ":")
		let client = try GameClient(store: try store(), server: .init(host: String(parts[0]), port: Int(parts[1]) ?? 43595))
		var (w, h) = (1015, 469)
		_ = try client.frame(width: w, height: h)
		let d = try XCTUnwrap(client.ui.drawn.last { $0.component.id == client.loginInterface << 16 | 250 })
		client.tap(x: d.x + d.w / 2, y: d.y + d.h / 2)
		client.type("house\(Int.random(in: 1000...9999))\ntester\n")
		func run(_ seconds: Double, until: (() -> Bool)? = nil) throws {
			let end = Date().addingTimeInterval(seconds)
			while Date() < end && !(until?() ?? false) { Thread.sleep(forTimeInterval: 0.02); _ = try client.frame(width: w, height: h) }
		}
		try run(20) { client.screen == .game && client.state.ticks >= 6 }
		XCTAssertEqual(client.screen, .game, "status: \(client.status)")
		let ticks = client.state.ticks
		client.setApplicationFocus(false)
		try run(0.5)
		client.cameraDrag(dx: 40, dy: 10)
		try run(1)
		client.setApplicationFocus(true)
		w = 900; h = 500
		try run(2)
		client.cameraDrag(dx: -30, dy: -10)
		try run(2)
		XCTAssertEqual(client.screen, .game, "session dropped: \(client.connectError ?? "-")")
		XCTAssertGreaterThan(client.state.ticks, ticks, "the world kept ticking")
		// The list the lobby serves, over the same port, through the CS2 op.
		var done = 0
		for _ in 0..<300 where done == 0 { done = Int(client.host.perform(HostOps.table[6500]!, ints: [], strings: []).ints[0]); Thread.sleep(forTimeInterval: 0.01) }
		XCTAssertNotNil(client.worldList.world(1))
		client.logout()
	}
}
