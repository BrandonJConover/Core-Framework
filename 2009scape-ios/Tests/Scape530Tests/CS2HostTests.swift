import Foundation
import XCTest
@testable import Scape530

/// The CS2 host drives real interfaces: the login screen (744) and the
/// resizable game frame (746) are built by their onLoad/onTimer scripts, not
/// by hand-set state.
final class CS2HostTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	func render(_ host: InterfaceScriptHost, _ w: Int, _ h: Int) throws -> Raster {
		var r = Raster(width: w, height: h)
		try host.renderer.render(host.game.interfaces.top, state: host.game.interfaces, into: &r)
		return r
	}

	func center(_ host: InterfaceScriptHost, _ interface: Int, _ index: Int) throws -> (Int, Int) {
		let d = try XCTUnwrap(host.renderer.drawn.last { $0.component.id == interface << 16 | index })
		return (d.x + d.w / 2, d.y + d.h / 2)
	}

	// MARK: login screen

	/// 744 opens, its onLoad builds the main menu, taps and keys move through
	/// the form and `directlogin` fires with what was typed.
	func testLoginScreenDrivenByScripts() throws {
		let host = InterfaceScriptHost(store: try store())
		var attempts: [(String, String)] = []
		host.onDirectLogin = { attempts.append(($0, $1)) }
		for (w, h) in [(765, 503), (852, 393)] {
			host.resize(width: w, height: h)
			host.apply(.ifOpenTop(id: 744, reset: 0))
			for _ in 0..<5 { host.cycle() }
			XCTAssertEqual(host.takeErrors(), [])
			try save(try render(host, w, h), "cs2-login-menu-\(w)x\(h)")
		}
		XCTAssertEqual(host.varc(174), 0, "main menu")
		let (lx, ly) = try center(host, 744, 250)
		host.tap(x: lx, y: ly)
		host.cycle()
		XCTAssertEqual(host.varc(174), 1, "username field focused")
		func press(_ code: Int, _ ch: Int) { host.key(code: code, char: ch); host.cycle() }
		for c in "phone".unicodeScalars { press(-1, Int(c.value)) }
		XCTAssertEqual(host.varcstr(32), "phone")
		press(84, -1)
		XCTAssertEqual(host.varc(174), 2, "Enter moves to the password field")
		for c in "tester!".unicodeScalars { press(-1, Int(c.value)) }
		press(85, -1)
		XCTAssertEqual(host.varcstr(33), "tester")
		try save(try render(host, 852, 393), "cs2-login-form-852x393")
		press(84, -1)
		XCTAssertEqual(attempts.count, 1)
		XCTAssertEqual(attempts.first?.0, "phone")
		XCTAssertEqual(attempts.first?.1, "tester")
		// A rejected login shows rt4's own message.
		host.loginReply = 3
		host.cycle(); host.cycle()
		try save(try render(host, 852, 393), "cs2-login-error-852x393")
		XCTAssertEqual(host.takeErrors(), [])
	}

	/// The whole `GameClient` flow against a server that is not there: the
	/// scripts show "connecting", then the failure.
	func testGameClientLoginAgainstClosedPort() throws {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		_ = try client.frame(width: 852, height: 393)
		XCTAssertEqual(client.screen, .title)
		let id = client.loginInterface << 16
		func tapComponent(_ i: Int) throws {
			let d = try XCTUnwrap(client.ui.drawn.last { $0.component.id == id | i })
			client.tap(x: d.x + d.w / 2, y: d.y + d.h / 2)
		}
		try tapComponent(250)
		XCTAssertEqual(client.screen, .loginForm)
		XCTAssertTrue(client.wantsKeyboard)
		client.username = "prefill"
		client.type("x")
		client.enter()
		XCTAssertEqual(client.username, "prefillx")
		client.type("secret\n")
		XCTAssertEqual(client.password, "secret")
		XCTAssertEqual(client.screen, .connecting)
		try save(try client.frame(width: 852, height: 393), "cs2-client-connecting")
		let deadline = Date().addingTimeInterval(5)
		while client.screen == .connecting && Date() < deadline { Thread.sleep(forTimeInterval: 0.02); _ = try client.frame(width: 852, height: 393) }
		XCTAssertEqual(client.screen, .loginForm)
		try save(try client.frame(width: 852, height: 393), "cs2-client-refused")
		XCTAssertEqual(client.host.takeErrors(), [])
	}

	// MARK: game frame

	func replayResizable(_ host: InterfaceScriptHost) throws {
		for pkt in try SessionReplayTests.recordedPackets("resizable-session") where pkt.opcode != ServerProt.playerInfo && pkt.opcode != ServerProt.npcInfo {
			host.apply(try ServerMessage.decode(pkt))
		}
	}

	/// Replays a recorded resizable-mode session through the host, so 746's
	/// onLoad / onVarpTransmit / onInvTransmit / onStatTransmit scripts run.
	func testResizableFrameWithScripts() throws {
		let host = InterfaceScriptHost(store: try store())
		host.resize(width: 1015, height: 469)
		try replayResizable(host)
		XCTAssertEqual(host.game.interfaces.top, 746)
		for _ in 0..<10 { host.cycle() }
		let errors = host.takeErrors()
		print("script errors replaying the session: \(errors.count) \(errors.prefix(5))")
		XCTAssertEqual(errors, [])
		for (w, h) in [(1015, 469), (1024, 768), (765, 503)] {
			host.resize(width: w, height: h)
			host.cycle()
			try save(try render(host, w, h), "cs2-resizable-\(w)x\(h)")
		}
		XCTAssertEqual(host.takeErrors(), [])
		print("hooks fired, opcodes seen: \(host.runner.opcodeCounts.count)")
	}

	/// Var, inventory and stat changes mark components due; hooks with trigger
	/// lists only fire for the ids they name (rt4 `InterfaceList.method946`).
	func testTransmitTriggers() throws {
		var log = InterfaceScriptHost.TransmitLog()
		var reader = 0
		XCTAssertFalse(log.due(reader: &reader, triggers: [5]))
		log.note(3)
		XCTAssertFalse(log.due(reader: &reader, triggers: [5]), "no trigger matches")
		XCTAssertEqual(reader, 1)
		log.note(5)
		XCTAssertTrue(log.due(reader: &reader, triggers: [5]))
		log.note(9)
		XCTAssertTrue(log.due(reader: &reader, triggers: nil), "no trigger list: any change")
		for i in 0..<40 { log.note(i + 100) }
		XCTAssertTrue(log.due(reader: &reader, triggers: [1]), "more than 32 behind: always fires")
	}

	// MARK: client packets

	func testIfButtonPackets() {
		var cipher = IsaacRandom(seed: [0, 0, 0, 0])
		var plain = IsaacRandom(seed: [0, 0, 0, 0])
		func enc(_ m: ClientMessage) -> [UInt8] { m.encode(&cipher) }
		// IF_BUTTON1: opcode 155, component (4 bytes big endian), child (2 bytes).
		let k1 = plain.nextKey()
		XCTAssertEqual(enc(.ifButton(op: 1, component: 746 << 16 | 12, child: -1)), [UInt8(truncatingIfNeeded: 155 + k1), 0x02, 0xEA, 0x00, 0x0C, 0xFF, 0xFF])
		let k2 = plain.nextKey()
		XCTAssertEqual(enc(.ifButton(op: 10, component: 1 << 16, child: 3)), [UInt8(truncatingIfNeeded: 9 + k2), 0, 1, 0, 0, 0, 3])
		let k3 = plain.nextKey()
		XCTAssertEqual(enc(.ifButtonLegacy(component: 0x01020304)), [UInt8(truncatingIfNeeded: 10 + k3), 1, 2, 3, 4])
		let k4 = plain.nextKey()
		XCTAssertEqual(enc(.ifContinue(component: 0x01020304, child: 0x0506)), [UInt8(truncatingIfNeeded: 132 + k4), 0x03, 0x04, 0x01, 0x02, 0x06, 0x05])
		let k5 = plain.nextKey()
		XCTAssertEqual(enc(.closeModal), [UInt8(truncatingIfNeeded: 184 + k5)])
	}

	/// A tap on an if3 component with a server-enabled option sends IF_BUTTON.
	func testTapSendsIfButton() throws {
		let host = InterfaceScriptHost(store: try store())
		host.resize(width: 1015, height: 469)
		try replayResizable(host)
		for _ in 0..<5 { host.cycle() }
		_ = try render(host, 1015, 469)
		var sent: [ClientMessage] = []
		host.send = { sent.append($0) }
		// Find any drawn component with an enabled option, tap it, expect its IF_BUTTON.
		var found = false
		for d in host.renderer.drawn.reversed() {
			let c = d.component
			guard c.if3, (0..<min(c.ops.count, 10)).contains(where: { host.optionText(c, $0) != nil && (c.events >> ($0 + 1)) & 1 != 0 }) else { continue }
			sent.removeAll()
			host.tap(x: d.x + d.w / 2, y: d.y + d.h / 2)
			guard case let .ifButton(op, comp, _)? = sent.first else { continue }
			print("tap on \(c.id >> 16):\(c.id & 0xFFFF) sent IF_BUTTON\(op) for \(comp >> 16):\(comp & 0xFFFF)")
			XCTAssertGreaterThanOrEqual(op, 1)
			found = true
			break
		}
		XCTAssertTrue(found, "no tappable option in the recorded game frame")
	}
}
