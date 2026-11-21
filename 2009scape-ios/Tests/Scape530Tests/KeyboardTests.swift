import Foundation
import XCTest
@testable import Scape530

/// Hardware keyboard support: rt4 `Keyboard`, `GameShell.mainInputLoop`, key remaps, CS2 modifier ops, ctrl-run.
final class KeyboardTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	// MARK: Keyboard queues (no cache)

	func testCodeMapMatchesRt4() {
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.up), 98)
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.down), 99)
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.left), 96)
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.right), 97)
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.enter), 84)
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.backSpace), 85)
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.escape), 13)
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.f1), 1)
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.f12), 12)
		XCTAssertEqual(KeyCode.pressCode(javaCode: 65), 48) // A
		XCTAssertEqual(KeyCode.pressCode(javaCode: 90), 64) // Z
		XCTAssertEqual(KeyCode.pressCode(javaCode: 48), 25) // 0
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.shift), 81)
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.control), 82)
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.alt), 86)
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.tab), 80)
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.pageUp), 104)
		// Numpad codes have bit 0x80: a press is ignored, a release clears the low 7 bits (rt4 quirk).
		XCTAssertEqual(KeyCode.pressCode(javaCode: KeyCode.VK.numpad0), -1)
		XCTAssertEqual(KeyCode.releaseCode(javaCode: KeyCode.VK.numpad0), 228 & 0x7F)
		XCTAssertEqual(KeyCode.pressCode(javaCode: 9999), -1)
		XCTAssertEqual(KeyCode.typedChar(8364), 128)
		XCTAssertEqual(KeyCode.typedChar(0x4E2D), -1)
		XCTAssertEqual(KeyCode.typedChar(65), 65)
	}

	func testHIDUsageMapping() {
		XCTAssertEqual(KeyCode.javaCode(hidUsage: 4), 65) // A
		XCTAssertEqual(KeyCode.javaCode(hidUsage: 29), 90) // Z
		XCTAssertEqual(KeyCode.javaCode(hidUsage: 30), 49) // 1
		XCTAssertEqual(KeyCode.javaCode(hidUsage: 39), 48) // 0
		XCTAssertEqual(KeyCode.javaCode(hidUsage: 58), KeyCode.VK.f1)
		XCTAssertEqual(KeyCode.javaCode(hidUsage: 69), KeyCode.VK.f12)
		XCTAssertEqual(KeyCode.javaCode(hidUsage: 82), KeyCode.VK.up)
		XCTAssertEqual(KeyCode.javaCode(hidUsage: 225), KeyCode.VK.shift)
		XCTAssertEqual(KeyCode.javaCode(hidUsage: 228), KeyCode.VK.control)
		XCTAssertEqual(KeyCode.javaCode(hidUsage: 230), KeyCode.VK.alt)
		XCTAssertEqual(KeyCode.javaCode(hidUsage: 227), -1) // command
		// Every mapped HID usage reaches an rt4 code except the numpad (bit 0x80).
		for u in 4...99 where KeyCode.javaCode(hidUsage: u) >= 0 {
			let vk = KeyCode.javaCode(hidUsage: u)
			let numpad = (96...105).contains(vk) || vk == 110
			XCTAssertEqual(KeyCode.pressCode(javaCode: vk) >= 0, !numpad && KeyCode.codeMap[vk] >= 0, "usage \(u) vk \(vk)")
		}
	}

	/// Events apply at `loop()`; typed keys become readable one loop later; focus loss clears every key.
	func testQueueTiming() {
		var k = Keyboard()
		k.keyPressed(javaCode: KeyCode.VK.up)
		k.keyTyped(char: 65)
		XCTAssertFalse(k.isPressed(KeyCode.up))
		XCTAssertNil(k.nextKey())
		k.loop()
		XCTAssertTrue(k.isPressed(KeyCode.up))
		XCTAssertEqual(k.nextKey()?.code, 98)
		let c = k.nextKey()
		XCTAssertEqual(c?.code, -1); XCTAssertEqual(c?.char, 65)
		XCTAssertNil(k.nextKey())
		k.keyReleased(javaCode: KeyCode.VK.up)
		k.loop()
		XCTAssertFalse(k.isPressed(KeyCode.up))
		// unread keys are dropped by the next loop
		k.keyTyped(char: 66)
		k.loop(); k.loop()
		XCTAssertNil(k.nextKey())
		k.keyPressed(javaCode: KeyCode.VK.control); k.loop()
		XCTAssertTrue(k.isPressed(KeyCode.ctrl))
		k.focusLost(); k.loop()
		XCTAssertFalse(k.isPressed(KeyCode.ctrl))
	}

	// MARK: camera

	/// rt4 `mainInputLoop`: pitch += 18^2 * dt, yaw += 24^2 * dt (calcRenderDelta), clamped like `clampCameraAngle`.
	func testArrowCameraMatchesRt4Math() {
		var cam = WorldCamera()
		cam.pitchTarget = 200; cam.yawTarget = 100
		// 50 frames of 20 ms with Up + Right held.
		for _ in 0..<50 { cam.applyArrowKeys(up: true, down: false, left: false, right: true, seconds: 0.02) }
		XCTAssertEqual(cam.pitchTarget, min(200 + 18 * 18 * 0.02 * 50, 383), accuracy: 1e-9)
		XCTAssertEqual(cam.yawTarget, 100 + 24 * 24 * 0.02 * 50, accuracy: 1e-9)
		// Pitch clamps to 383 (rt4 maxPitch); left wins over right; down alone lowers.
		for _ in 0..<200 { cam.applyArrowKeys(up: true, down: true, left: true, right: true, seconds: 0.02) }
		XCTAssertEqual(cam.pitchTarget, 383, accuracy: 1e-9)
		var d = WorldCamera()
		d.pitchTarget = 300; d.yawTarget = 5
		d.applyArrowKeys(up: false, down: true, left: true, right: false, seconds: 0.5)
		XCTAssertEqual(d.pitchTarget, 300 - 324 * 0.5, accuracy: 1e-9)
		// yaw wraps modulo 2047 like rt4 `mod`.
		XCTAssertEqual(d.yawTarget, (5 - 576 * 0.5 + 2047).truncatingRemainder(dividingBy: 2047), accuracy: 1e-9)
		// Nothing held: untouched.
		var e = WorldCamera(); e.pitchTarget = 250
		e.applyArrowKeys(up: false, down: false, left: false, right: false, seconds: 1)
		XCTAssertEqual(e.pitchTarget, 250)
	}

	func testLegacyArrowKeySteps() {
		var cam = WorldCamera()
		cam.pitchTarget = 200; cam.yawTarget = 500
		cam.applyLegacyArrowKey(rt4Code: KeyCode.up); XCTAssertEqual(cam.pitchTarget, 247)
		cam.applyLegacyArrowKey(rt4Code: KeyCode.down); XCTAssertEqual(cam.pitchTarget, 230)
		cam.applyLegacyArrowKey(rt4Code: KeyCode.left); XCTAssertEqual(cam.yawTarget, 435)
		cam.applyLegacyArrowKey(rt4Code: KeyCode.right); XCTAssertEqual(cam.yawTarget, 626)
	}

	// MARK: GameClient (cache needed)

	func newClient() throws -> GameClient {
		try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
	}

	func testModifiersAndCS2Ops() throws {
		let client = try newClient()
		let host = client.host
		func op(_ name: String) -> Int32 {
			let spec = HostOpSpec(opcode: 0, name: name, ints: 0, strings: 0, outInts: 1, outStrings: 0)
			return host.perform(spec, ints: [], strings: []).ints.first ?? -1
		}
		XCTAssertEqual([op("isHoldingAlt"), op("isHoldingCtrl"), op("isHoldingShift")], [0, 0, 0])
		client.keyDown(code: KeyCode.VK.control)
		client.keyDown(code: KeyCode.VK.shift)
		XCTAssertEqual(op("isHoldingCtrl"), 0, "applies at the cycle boundary")
		host.keyboard.loop()
		XCTAssertEqual([op("isHoldingAlt"), op("isHoldingCtrl"), op("isHoldingShift")], [0, 1, 1])
		client.keyUp(code: KeyCode.VK.control)
		host.keyboard.loop()
		XCTAssertEqual(op("isHoldingCtrl"), 0)
		client.setModifiers(shift: false, ctrl: false, alt: true)
		XCTAssertEqual([op("isHoldingAlt"), op("isHoldingCtrl"), op("isHoldingShift")], [1, 0, 0])
		client.setApplicationFocus(false)
		host.keyboard.loop()
		XCTAssertEqual(op("isHoldingAlt"), 0)
	}

	/// The walk packet's ctrl flag follows the held Ctrl key (rt4 ClientProt: `pressedKeys[KEY_CTRL] ? 1 : 0`).
	func testCtrlRunFlag() throws {
		let client = try newClient()
		XCTAssertFalse(client.interaction.isCtrlHeld())
		client.keyDown(code: KeyCode.VK.control); client.host.keyboard.loop()
		XCTAssertTrue(client.interaction.isCtrlHeld())
		let route = PathFinder.Route(waypoints: [(5, 5), (9, 5)], partial: false)
		var a = IsaacRandom(seed: [1, 2, 3, 4]), b = IsaacRandom(seed: [1, 2, 3, 4])
		let held = PathFinder.walkMessage(route: route, originX: 3000, originZ: 3100, running: client.interaction.isCtrlHeld(), minimap: false).encode(&a)
		let plain = PathFinder.walkMessage(route: route, originX: 3000, originZ: 3100, running: false, minimap: false).encode(&b)
		XCTAssertEqual(held.count, plain.count)
		XCTAssertNotEqual(held, plain)
		let diff = zip(held, plain).enumerated().filter { $0.element.0 != $0.element.1 }
		XCTAssertEqual(diff.count, 1)
		// p1add(1) is 129; p1add(0) is 128.
		XCTAssertEqual(diff.first.map { [$0.element.0, $0.element.1] }, [129, 128])
	}

	/// Arrow keys held for N frames rotate the world camera by rt4's amounts.
	func testHeldArrowsRotateClientCamera() throws {
		let client = try newClient()
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: 1, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		client.world.camera.pitchTarget = 200; client.world.camera.yawTarget = 100
		client.keyDown(code: KeyCode.VK.left)
		client.host.keyboard.loop()
		let t0 = Date()
		for i in 0...10 { client.arrowKeyCamera(at: t0.addingTimeInterval(Double(i) * 0.02)) }
		// first call has no previous frame (0 s); 10 frames of 20 ms follow.
		XCTAssertEqual(client.world.camera.yawTarget, (100 - 576 * 0.02 * 10 + 2047).truncatingRemainder(dividingBy: 2047), accuracy: 1e-3)
		XCTAssertEqual(client.world.camera.pitchTarget, 200)
	}

	// MARK: key remaps

	func testKeyRemapDecode() throws {
				// slot 1 (value 0x20 >> 4 - 1 = 1): first g1 = 0x20, then g1 completes 12 bits -> 0x0A5 (repeat 165? -> 0x20<<8|g1)
		var p = Packet([0x20, 0x05, UInt8(KeyCode.up), 0x03, 0])
		var c = Component(parentId: 9000 << 16 | 1, type: 5, index: -1)
		try c.decodeKeyRemaps(&p)
		XCTAssertEqual(c.keyRemapCodes.count, 10)
		XCTAssertEqual(c.keyRemapRepeat[1], (0x20 << 8 | 0x05) & 0xFFF)
		XCTAssertEqual(c.keyRemapCodes[1], KeyCode.up)
		XCTAssertEqual(c.keyRemapMods[1], 3)
		XCTAssertEqual(c.keyRemapRepeat[0], 0)
	}

	func testKeyRemapFiresOptionWithModifiersAndRepeat() throws {
		let client = try newClient()
		let host = client.host
		// An if3 button with one remap: slot 0 -> option 1 on F5 (rt4 code 5), ctrl required, repeat every 3 cycles.
		var c = Component(parentId: 9000 << 16 | 1, type: 5, index: -1)
		c.keyRemapRepeat = [3] + [Int](repeating: 0, count: 9)
		c.keyRemapCodes = [5] + [Int](repeating: 0, count: 9)
		c.keyRemapMods = [1] + [Int](repeating: 0, count: 9)
		func cycle() -> [Int] { host.loop += 1; return host.keyRemapOptions(c) }
		client.keyDown(code: KeyCode.VK.f1 + 4); host.keyboard.loop()
		XCTAssertEqual(cycle(), [], "ctrl not held")
		client.keyDown(code: KeyCode.VK.control); host.keyboard.loop()
		XCTAssertEqual(cycle(), [1])
		XCTAssertEqual(cycle(), []); XCTAssertEqual(cycle(), [])
		XCTAssertEqual(cycle(), [1], "repeats after 3 cycles")
		client.keyUp(code: KeyCode.VK.f1 + 4); host.keyboard.loop()
		XCTAssertEqual(cycle(), [])
		// A repeat of 0 fires once per press.
		c.keyRemapRepeat[0] = 0
		host.keyRemapNext[c.ref] = nil
		client.keyDown(code: KeyCode.VK.f1 + 4); host.keyboard.loop()
		XCTAssertEqual(cycle(), [1]); XCTAssertEqual(cycle(), []); XCTAssertEqual(cycle(), [])
		client.keyUp(code: KeyCode.VK.f1 + 4); host.keyboard.loop()
		XCTAssertEqual(cycle(), [])
		client.keyDown(code: KeyCode.VK.f1 + 4); host.keyboard.loop()
		XCTAssertEqual(cycle(), [1], "fires again on the next press")
	}

	/// F1...F8 are key remaps on the tab-stone buttons of interface 548 (rt4 `Component` key bytes): holding a key for several
	/// cycles clicks option 1 once (repeat 0), and releasing re-arms it. F9...F12 are unbound in the 530 cache.
	func testFKeysSwitchTabs() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		try replayResizable(client, session: "login-session", me: 11)
		client.host.apply(.ifCloseSub(parent: Int32(752 << 16 | 12)))
		for _ in 0..<10 { client.host.cycle() }
		_ = try client.frame(width: 1015, height: 469)
		var sent: [ClientMessage] = []
		client.host.send = { sent.append($0) }
		var tabs = Set<Int>()
		for f in 0..<12 {
			sent.removeAll()
			client.keyDown(code: KeyCode.VK.f1 + f)
			for _ in 0..<4 { client.deliverKeys(); client.host.cycle(); client.host.keyboard.loop() }
			client.keyUp(code: KeyCode.VK.f1 + f)
			for _ in 0..<2 { client.deliverKeys(); client.host.cycle(); client.host.keyboard.loop() }
			let clicks = sent.compactMap { m -> Int? in if case let .ifButton(1, c, _) = m { return c } else { return nil } }
			if f < 8 {
				XCTAssertEqual(clicks.count, 1, "F\(f + 1): \(sent)")
				XCTAssertEqual(clicks.first.map { $0 >> 16 }, 548)
				tabs.formUnion(clicks)
			} else {
				XCTAssertTrue(clicks.isEmpty, "F\(f + 1): \(sent)")
			}
		}
		XCTAssertEqual(tabs.count, 8, "each F-key opens a different tab")
	}

	/// Feeds the recorded resizable session into `client` (see `WorldViewTests.replay`).
	func replayResizable(_ client: GameClient, session: String = "resizable-session", me: Int = 2047, cyclesPerTick: Int = 30) throws {
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: me, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		var players = PlayerInfoDecoder(selfIndex: me, localX: 52, localZ: 52)
		var npcs = NpcInfoDecoder()
		var zone: (x: Int, z: Int)?
		for pkt in try SessionReplayTests.recordedPackets(session) {
			switch pkt.opcode {
			case ServerProt.playerInfo:
				let r = try players.decode(pkt.payload)
				client.handle(.players(r, players))
				for _ in 0..<cyclesPerTick { client.world.cycle(varps: client.state.varps) }
			case ServerProt.npcInfo:
				let p = try XCTUnwrap(players.players[me])
				let r = try npcs.decode(pkt.payload, selfX: p.x, selfZ: p.z)
				client.handle(.npcs(r, npcs))
			default:
				let m = try ServerMessage.decode(pkt)
				if case .rebuildNormal(let r) = m {
					if let z = zone {
						players.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
						npcs.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
					} else {
						players = PlayerInfoDecoder(selfIndex: me, localX: r.localX, localZ: r.localZ)
					}
					zone = (r.zoneX, r.zoneZ)
				}
				client.handle(.message(m))
			}
		}
	}
}
