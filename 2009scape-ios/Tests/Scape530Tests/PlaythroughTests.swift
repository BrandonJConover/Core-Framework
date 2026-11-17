import Foundation
import XCTest
@testable import Scape530

/// Live "playthrough" tests: log in to a real 2009scape server and play like a person would, using only
/// the client's own input APIs (taps, typed text), then check the instrumentation counters.
/// Needs SCAPE530_CACHE and SCAPE530_SERVER=host:port.
final class PlaythroughTests: XCTestCase {
	/// A logged-in client plus helpers to pump frames and click things.
	final class Live {
		let client: GameClient
		let w = 1015, h = 469
		var last: Raster
		var outDir: URL?
		/// Every client message sent since the last `takeSent()`.
		var sent: [ClientMessage] = []
		func takeSent() -> [ClientMessage] { defer { sent = [] }; return sent }

		init(store: ConfigStore, server: String, user: String) throws {
			let parts = server.split(separator: ":")
			client = try GameClient(store: store, server: .init(host: String(parts[0]), port: Int(parts[1]) ?? 43595))
			last = try client.frame(width: w, height: h)
			if let o = ProcessInfo.processInfo.environment["SCAPE530_OUT"] { outDir = URL(fileURLWithPath: o) }
			client.log = { print("client log: \($0)") }
			let old = client.host.send
			client.host.send = { [unowned self] m in self.sent.append(m); old(m) }
			try login(user)
		}

		func login(_ user: String) throws {
			last = try client.frame(width: w, height: h)
			let d = try XCTUnwrap(client.ui.drawn.last { $0.component.id == client.loginInterface << 16 | 250 })
			client.tap(x: d.x + d.w / 2, y: d.y + d.h / 2)
			client.type("\(user)\ntester\n")
			let deadline = Date().addingTimeInterval(40)
			while Date() < deadline && (client.screen != .game || client.state.ticks < 12) { pump(0.02) }
			XCTAssertEqual(client.screen, .game, "status: \(client.status)")
			pump(2)
		}

		/// Renders frames at roughly the client's pace for `seconds`.
		func pump(_ seconds: Double) {
			let until = Date().addingTimeInterval(seconds)
			repeat {
				if let r = try? client.frame(width: w, height: h) { last = r }
				Thread.sleep(forTimeInterval: 0.02)
			} while Date() < until
		}

		func pump(until cond: () -> Bool, timeout: Double = 6) -> Bool {
			let until = Date().addingTimeInterval(timeout)
			while Date() < until {
				pump(0.05)
				if cond() { return true }
			}
			return cond()
		}

		func shot(_ name: String) {
			guard let o = outDir else { return }
			try? Data(PNG.encode(last)).write(to: o.appendingPathComponent("playthrough-\(name).png"))
		}

		/// Types a line into the chatbox (a `::command` or public chat) the way a player would.
		func say(_ line: String) {
			client.type(line + "\n")
			pump(0.6)
		}

		/// The drawn components whose id is in interface `iface`.
		func drawn(_ iface: Int) -> [(component: Component, x: Int, y: Int, w: Int, h: Int)] {
			client.ui.drawn.filter { $0.component.id >> 16 == iface }
		}

		var openInterfaces: [Int] { Array(client.state.interfaces.open.values).sorted() }

		func tap(_ d: (component: Component, x: Int, y: Int, w: Int, h: Int)) {
			client.tap(x: d.x + d.w / 2, y: d.y + d.h / 2)
			pump(0.4)
		}

		@discardableResult
		func tapComponent(_ id: Int) -> Bool {
			guard let d = client.ui.drawn.last(where: { $0.component.id == id }) else { return false }
			tap(d)
			return true
		}

		/// Taps the first drawn component whose op or text contains `s` (case-insensitive).
		@discardableResult
		func tapText(_ s: String, in iface: Int? = nil) -> Bool {
			let l = s.lowercased()
			let list = iface.map(drawn) ?? client.ui.drawn
			guard let d = list.first(where: { $0.component.text.lowercased().contains(l) || $0.component.ops.contains { $0.lowercased().contains(l) } }) else { return false }
			tap(d)
			return true
		}

		/// Scans the viewport for a point whose default (top) menu entry matches `match`, nearest the player first.
		func scanWorld(step: Int = 10, radius: Int = 130, _ match: (Menu.Entry) -> Bool) -> (x: Int, y: Int, entry: Menu.Entry)? {
			guard let v = client.viewport else { return nil }
			let (cx, cy) = (v.w / 2, v.h / 2)
			for dy in stride(from: max(20, cy - radius), to: min(v.h - 20, cy + radius), by: step) {
				for dx in stride(from: max(20, cx - radius * 2), to: min(v.w - 20, cx + radius * 2), by: step) {
					let px = v.x + dx, py = v.y + dy
					guard client.isOverWorld(x: px, y: py), let (m, _) = client.buildMenu(x: px, y: py) else { continue }
					let e = m.entries[m.top]
					if match(e) { return (px, py, e) }
				}
			}
			return nil
		}

		/// Texts and ops of everything drawn in the chatbox / dialogue interfaces.
		func uiSummary(_ ifaces: [Int]) -> [String] {
			var out: [String] = []
			for i in ifaces { for d in drawn(i) {
				let c = d.component
				if !c.text.isEmpty || !c.ops.filter({ !$0.isEmpty }).isEmpty { out.append("\(i):\(c.id & 0xFFFF) t=\"\(c.text.prefix(50))\" ops=\(c.ops.filter { !$0.isEmpty })") }
			} }
			return out
		}

		/// Taps the drawn component whose first op equals `op` exactly (case-insensitive).
		@discardableResult
		func tapOp(_ op: String, in iface: Int? = nil) -> Bool {
			let list = iface.map(drawn) ?? client.ui.drawn
			guard let d = list.last(where: { $0.component.ops.contains { $0.lowercased() == op.lowercased() } }) else { return false }
			tap(d)
			return true
		}

		/// Projects a point of the scene to game pixels the way the scene draw does.
		func project(xFine: Int, yFine: Int, zFine: Int) -> (Int, Int)? {
			guard let v = client.viewport, let me = client.world.selfActor, let scene = client.world.scene else { return nil }
			let groundY = scene.tileHeight(level: scene.centralPlane, xFine: me.xFine, zFine: me.zFine)
			let eye = client.world.camera.eye(groundY: groundY)
			let sinP = MathTables.sin[eye.pitch & 2047], cosP = MathTables.cos[eye.pitch & 2047]
			let sinY = MathTables.sin[eye.yaw & 2047], cosY = MathTables.cos[eye.yaw & 2047]
			let dx = xFine - eye.x, dy = yFine - eye.y, dz = zFine - eye.z
			let xr = (dz * sinY + dx * cosY) >> 16
			let zr = (dz * cosY - dx * sinY) >> 16
			let yv = (dy * cosP - zr * sinP) >> 16
			let zv = (dy * sinP + zr * cosP) >> 16
			guard zv > 50 else { return nil }
			return (v.x + v.w / 2 + (xr << 9) / zv, v.y + v.h / 2 + (yv << 9) / zv)
		}

		/// A screen point on an npc whose top menu entry has verb `op` (and name containing `name`), if one is on screen.
		func findNpc(op: String, name: String? = nil) -> (x: Int, y: Int, index: Int)? {
			for (id, a) in client.world.ctx.npcs.sorted(by: { $0.key < $1.key }) {
				guard let t = a.npcType, t.interactive else { continue }
				if let n = name, !t.name.lowercased().contains(n.lowercased()) { continue }
				for off in [60, 90, 120, 30] {
					guard let p = project(xFine: a.xFine, yFine: a.groundY - off, zFine: a.zFine), client.isOverWorld(x: p.0, y: p.1) else { continue }
					guard let (m, _) = client.buildMenu(x: p.0, y: p.1), m.entries[m.top].op.lowercased() == op.lowercased(), m.entries[m.top].key == Int64(id) else { continue }
					return (p.0, p.1, id)
				}
			}
			return nil
		}

		/// The interface currently open in the chatbox dialogue slot (752:12), if any.
		var dialogue: Int? { client.state.interfaces.open[752 << 16 | 12] }

		/// Clickable (continue / option) components of the dialogue: events bit 0 or an op.
		func dialogueButtons() -> [(component: Component, x: Int, y: Int, w: Int, h: Int)] {
			guard let d = dialogue else { return [] }
			return drawn(d).filter { $0.component.events & 1 != 0 && !$0.component.hidden }
		}

		/// Plays a dialogue: prefers an option whose text contains one of `prefer`, otherwise the first
		/// button. Returns the transcript. Stops when the dialogue closes or `rounds` run out.
		@discardableResult
		func driveDialogue(prefer: [String] = [], rounds: Int = 40, shots: String? = nil) -> [String] {
			var transcript: [String] = []
			var idle = 0, stuck = 0
			for r in 0..<rounds {
				pump(0.5)
				guard let d = dialogue else { idle += 1; if idle > 3 { break } else { continue } }
				idle = 0
				let lines = drawn(d).filter { !$0.component.text.isEmpty }.map { $0.component.text }
				transcript.append(lines.joined(separator: " | "))
				if let s = shots, r < 3 { shot("\(s)-\(r)") }
				let buttons = dialogueButtons()
				guard !buttons.isEmpty else { stuck += 1; if stuck > 3 { break } else { continue } }
				stuck = 0
				let pick = buttons.first { b in prefer.contains { b.component.text.lowercased().contains($0.lowercased()) } } ?? buttons.first!
				tap(pick)
				pump(0.8)
			}
			return transcript
		}

		func describe() -> String {
			let open = client.state.interfaces.open.sorted { $0.key < $1.key }.map { "\($0.key >> 16):\($0.key & 0xFFFF)=\($0.value)" }
			let chat = client.state.chatLog.lines.prefix(4).map { "[\($0.type)] \($0.name): \($0.message)" }
			return "top \(client.state.interfaces.top) open \(open) pos \(String(describing: client.state.selfWorld)) chat \(chat)"
		}

		func report() {
			let d = client.diagnostics
			print("DIAG unhandled packets: \(d.unhandledPackets.sorted { $0.key < $1.key })")
			print("DIAG decode failures: \(d.decodeFailures)")
			print("DIAG unported cs2: \(client.unportedScriptOpcodes.sorted { $0.key < $1.key })")
			for (k, v) in client.scriptErrorCounts.sorted(by: { $0.key < $1.key }).prefix(40) { print("DIAG script error x\(v): \(k)") }
		}
	}

	func live(_ name: String) throws -> Live {
		let env = ProcessInfo.processInfo.environment
		guard let dir = env["SCAPE530_CACHE"], let server = env["SCAPE530_SERVER"] else { throw XCTSkip("needs SCAPE530_CACHE and SCAPE530_SERVER") }
		let store = ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
		return try Live(store: store, server: server, user: "\(name)\(Int.random(in: 100...999))")
	}

	/// Fresh account: character design, then skip Tutorial Island through Skippy and Terrova.
	func finishTutorial(_ l: Live, afterDesign: () -> Void = {}) {
		if l.client.state.interfaces.open.values.contains(771) {
			l.shot("design-00")
			XCTAssertTrue(l.tapOp("Select 2-button mouse"))
			for step in 0..<8 where l.client.state.interfaces.open.values.contains(771) {
				if step == 1 { l.shot("design-01") }
				if !(l.tapOp("Select next") || l.tapOp("Confirm changes")) { break }
				l.pump(1.2)
			}
			XCTAssertFalse(l.client.state.interfaces.open.values.contains(771), "design screens closed")
			l.pump(2)
		}
		afterDesign()
		guard l.client.state.interfaces.open.values.contains(372) || l.findNpc(op: "Talk-to", name: "skippy") != nil || l.dialogue != nil else { return }
		if let f = l.findNpc(op: "Talk-to", name: "skippy") {
			l.client.tap(x: f.x, y: f.y)
			l.pump(1)
			if l.client.interaction.popup != nil { _ = chooseMenu(l, "Talk-to") }
			l.pump(3)
			l.driveDialogue(prefer: ["Yes, I'd like to skip"], shots: "skippy")
			l.pump(2)
		}
		if let t = l.findNpc(op: "Talk-to", name: "instructor") {
			l.client.tap(x: t.x, y: t.y)
			l.pump(1)
			if l.client.interaction.popup != nil { _ = chooseMenu(l, "Talk-to") }
			l.pump(3)
			l.driveDialogue(prefer: ["Yes, I'm ready", "I'm ready now"], shots: "terrova")
			l.pump(4)
		}
	}

	func testTutorialDialogue() throws {
		let l = try live("tut")
		XCTAssertTrue(l.client.state.interfaces.open.values.contains(771), "a new account starts in the character designer")
		finishTutorial(l)
		print("AFTER tutorial: \(l.describe())")
		l.shot("after-tutorial")
		XCTAssertNotNil(l.client.state.stats[0], "stats arrived")
		if let p = l.client.state.selfWorld { XCTAssertTrue((3200...3260).contains(p.x) && (3200...3260).contains(p.z), "arrived in Lumbridge: \(p)") }
		l.report()
		l.client.logout()
	}

	// MARK: gameplay

	/// Inventory slot (0-based) of the first item with `id` in inventory `inv` (93 backpack, 94 worn, 95 bank).
	func slotOf(_ l: Live, item id: Int, inv: Int = 93) -> Int? {
		l.client.state.inventories[inv]?.first { $0.value.id == id }?.key
	}

	func count(_ l: Live, item id: Int, inv: Int = 93) -> Int {
		Int(l.client.state.inventories[inv]?.values.filter { $0.id == id }.reduce(0) { $0 + Int($1.count) } ?? 0)
	}

	/// Screen centre of slot `slot` of the item grid `c` (drawn last frame).
	func slotPoint(_ l: Live, _ c: Component, _ slot: Int) -> (Int, Int)? {
		guard let o = l.client.ui.origins[c.ref] else { return nil }
		let col = slot % max(c.baseWidth, 1), row = slot / max(c.baseWidth, 1)
		return (o.x + col * (c.invMarginX + 32) + 16, o.y + row * (c.invMarginY + 32) + 16)
	}

	/// Taps an item slot in whichever drawn item grid shows `item` in `inv`: finds the grid by its content.
	@discardableResult
	func tapItem(_ l: Live, _ id: Int, inv: Int = 93, long: Bool = false, iface: Int? = nil) -> Bool {
		// if3 grids built by CS2 (bank, shops) are created item sprites rather than type-2 components.
		if let iface, let d = l.client.ui.drawn.last(where: { $0.component.id >> 16 == iface && $0.component.objId == id && $0.component.childIndex != -1 && $0.w > 0 }) {
			let p = (d.x + d.w / 2, d.y + d.h / 2)
			let c = d.component
			var sent: [ClientMessage] = []
			let old = l.client.host.send
			l.client.host.send = { sent.append($0); old($0) }
			defer { l.client.host.send = old }
			print("TAPITEM \(id) at \(p) comp \(c.id >> 16):\(c.id & 0xFFFF)/\(c.childIndex) ops=\(c.ops) events=\(String(c.events, radix: 16)) hooks=\(c.hooks.keys.sorted()) hit=\(String(describing: l.client.ui.hitTest(x: p.0, y: p.1)?.id))")
			defer { print("TAPITEM sent \(sent)") }
			if long { l.client.longPress(x: p.0, y: p.1) } else { l.client.tap(x: p.0, y: p.1) }
			l.pump(0.8)
			return true
		}
		guard let slot = slotOf(l, item: id, inv: inv) else { return false }
		for d in l.client.ui.drawn.reversed() where d.component.type == 2 {
			guard let items = l.client.state.interfaces.invSlots[d.component.id], items[slot]?.id == id, let p = slotPoint(l, d.component, slot) else { continue }
			if long { l.client.longPress(x: p.0, y: p.1) } else { l.client.tap(x: p.0, y: p.1) }
			l.pump(0.8)
			return true
		}
		return false
	}

	/// Picks the popup-menu row whose text starts with `prefix` after a long press.
	@discardableResult
	func chooseMenu(_ l: Live, _ prefix: String) -> Bool {
		guard let popup = l.client.interaction.popup else { return false }
		guard let i = popup.menu.entries.indices.first(where: { popup.menu.text($0).lowercased().hasPrefix(prefix.lowercased()) }) else {
			print("MENU has no \(prefix): \((0..<popup.menu.count).map { popup.menu.text($0) })")
			return false
		}
		let rowY = (popup.menu.count - i - 1) * 15 + popup.y + 31 - 5
		l.client.tap(x: popup.x + 10, y: rowY)
		l.pump(0.8)
		return true
	}

	func testGameplay() throws {
		let l = try live("ptplay")
		finishTutorial(l)
		l.pump(2)
		print("GAMEPLAY start: \(l.describe())")
		// Dev items through the chatbox, the way a player types commands.
		l.say("::empty")
		for line in ["::item 995 100000", "::item 1205", "::item 1139", "::item 2309 3", "::item 361 5", "::item 590", "::item 1511 2", "::item 556 500", "::item 558 500", "::item 1351", "::item 303"] {
			l.say(line)
		}
		l.pump(1.5)
		print("INV: \(l.client.state.inventories[93]?.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value.id)x\($0.value.count)" } ?? [])")
		XCTAssertEqual(count(l, item: 995), 100000, "::item gave coins")
		XCTAssertEqual(count(l, item: 2309), 3)

		// Sidebar tabs: every one opens and draws.
		for tab in ["Combat Styles", "Stats", "Quest List", "Inventory", "Worn Equipment", "Prayer List", "Magic Spellbook", "Friends List", "Ignore List", "Clan Chat", "Options", "Emotes", "Music Player"] {
			let ok = l.tapOp(tab)
			l.pump(0.8)
			print("TAB \(tab): tapped=\(ok) \(l.describe().prefix(120))")
			XCTAssertTrue(ok, "tab \(tab) exists")
			l.shot("tab-" + tab.lowercased().replacingOccurrences(of: " ", with: "-"))
		}
		l.tapOp("Inventory")
		l.pump(1)

		// Equip the dagger and helm, eat bread.
		XCTAssertTrue(tapItem(l, 1205), "dagger visible in inventory")
		XCTAssertTrue(tapItem(l, 1139))
		l.pump(1)
		XCTAssertEqual(count(l, item: 1205, inv: 94), 1, "dagger wielded")
		XCTAssertEqual(count(l, item: 1139, inv: 94), 1, "helm worn")
		let bread = count(l, item: 2309)
		XCTAssertTrue(tapItem(l, 2309))
		l.pump(1.5)
		XCTAssertEqual(count(l, item: 2309), bread - 1, "bread eaten")
		l.shot("inventory-equipped")
		// Long press menu on an item, drop it.
		XCTAssertTrue(tapItem(l, 361, long: true))
		l.shot("item-menu")
		XCTAssertTrue(chooseMenu(l, "Drop"), "Drop option")
		l.pump(1.5)
		XCTAssertEqual(count(l, item: 361), 4, "tuna dropped")
		l.report()
		l.client.logout()
	}

	/// The packets added for full protocol coverage, triggered the way a server operator would: the Tutorial Island hint
	/// arrow on a fresh account, then the camera and animation admin commands.
	func testProtocolCoverageLive() throws {
		let l = try live("ptcov")
		// A fresh account stands on Tutorial Island; once the designer closes the guide wears a hint arrow.
		var arrows: [ServerMessage.HintArrow] = []
		var guestName: String?
		finishTutorial(l) {
			// Stage 1 asks for the options tab (the flashing spanner); stage 2 puts the arrow on the guide.
			l.pump(3)
			print("COV options tab tapped: \(l.tapOp("Options"))")
			_ = l.pump(until: { !l.client.world.hintArrows.compactMap { $0 }.isEmpty }, timeout: 8)
			arrows = l.client.world.hintArrows.compactMap { $0 }
			guestName = arrows.first.flatMap { l.client.world.ctx.npcs[$0.target]?.npcType?.name }
			print("COV arrow target: \(String(describing: guestName)) hint icons drawn: \(l.client.world.hintArrows.compactMap { $0 }.count)")
			l.shot("hint-arrow")
		}
		print("COV hint arrows: \(arrows))")
		if let a = arrows.first {
			XCTAssertEqual(a.type, 1, "the guide is an npc")
			XCTAssertEqual(guestName, "RuneScape guide", "the arrow's npc was in the scene")
		} else {
			XCTFail("no hint arrow over the tutorial guide")
		}
		l.pump(2)
		// The skip may leave the tap menu open; it would swallow the typed command.
		_ = chooseMenu(l, "Cancel")
		l.pump(1)
		l.say("::anim 861")
		// Camera: panning to a tile takes the camera off the player, resetting hands it back.
		l.say("::poscam 34 26 300")
		l.say("::rotcam 33 30 0 100")
		l.pump(1)
		XCTAssertNotNil(l.client.world.camera.scripted, "::poscam scripted the camera")
		l.shot("camera-scripted")
		l.say("::movcam 36 36 300 50")
		l.pump(1)
		l.say("::shakecam 3 5 10 100 2")
		l.pump(1)
		XCTAssertTrue(l.client.world.camera.shakes[3].active, "::shakecam shook the yaw axis")
		l.say("::resetcam")
		l.pump(1)
		XCTAssertNil(l.client.world.camera.scripted, "::resetcam gave the camera back")
		XCTAssertFalse(l.client.world.camera.shakes[3].active)
		let d = l.client.diagnostics
		print("COV unhandled \(d.unhandledPackets) failures \(d.decodeFailures) unported cs2 \(l.client.unportedScriptOpcodes)")
		XCTAssertTrue(d.decodeFailures.isEmpty, "no packet failed to decode: \(d.decodeFailures)")
		XCTAssertTrue(d.unhandledPackets.isEmpty, "no packet went unhandled: \(d.unhandledPackets)")
		l.client.logout()
	}

	/// Bank, the "enter amount" prompt, run toggle, friends "enter name" prompt, logout and log back in.
	func testBankPromptsRunLogout() throws {
		let l = try live("ptbank")
		finishTutorial(l)
		l.pump(2)
		l.say("::empty")
		l.say("::item 2309 5")
		l.say("::item 995 5000")
		l.pump(1)
		XCTAssertEqual(count(l, item: 2309), 5)
		// Bank booth interface, deposit and withdraw-X.
		l.say("::bank")
		XCTAssertTrue(l.pump(until: { l.client.state.interfaces.open.values.contains(762) }, timeout: 6), "bank opens: \(l.describe())")
		l.pump(1)
		l.shot("bank-open")
		l.report()
		print("BANK open ifaces: \(l.openInterfaces)")
		print("BANK invSlots keys: \(l.client.state.interfaces.invSlots.keys.sorted().map { "\($0 >> 16):\($0 & 0xFFFF)" }) drawn type2: \(l.client.ui.drawn.filter { $0.component.type == 2 }.map { "\($0.component.id >> 16):\($0.component.id & 0xFFFF) \($0.x),\($0.y) \($0.w)x\($0.h)" })")
		XCTAssertTrue(tapItem(l, 2309, iface: 763), "tap bread in bank backpack")
		l.pump(1.5)
		print("BANK after deposit: backpack bread \(count(l, item: 2309)), bank bread \(count(l, item: 2309, inv: 95))")
		XCTAssertLessThan(count(l, item: 2309), 5, "deposit sent")
		XCTAssertGreaterThan(count(l, item: 2309, inv: 95), 0, "bank holds bread")
		XCTAssertTrue(tapItem(l, 2309, long: true, iface: 763), "long press backpack slot")
		XCTAssertTrue(chooseMenu(l, "Deposit-All"), "Deposit-All option")
		l.pump(1.5)
		XCTAssertEqual(count(l, item: 2309), 0, "all bread deposited")
		XCTAssertEqual(count(l, item: 2309, inv: 95), 5)
		XCTAssertTrue(tapItem(l, 2309, inv: 95, long: true, iface: 762), "long press bank slot")
		l.shot("bank-menu")
		print("BANK menu: \(l.client.interaction.popup.map { m in (0..<m.menu.count).map { m.menu.text($0) } } ?? [])")
		XCTAssertTrue(chooseMenu(l, "Withdraw-X"), "Withdraw-X option")
		l.pump(1.5)
		l.shot("bank-enter-amount")
		print("PROMPT: \(l.describe().prefix(200)) keyboard=\(l.client.wantsKeyboard)")
		let before = count(l, item: 2309)
		_ = l.takeSent()
		l.client.type("3\n")
		l.pump(2)
		print("PROMPT sent: \(l.takeSent()) bread \(before)->\(count(l, item: 2309)) varc5=\(l.client.host.varc(5)) chat \(l.client.state.chatLog.lines.prefix(3).map(\.message))")
		XCTAssertEqual(count(l, item: 2309), before + 3, "withdrew the typed amount")
		XCTAssertEqual(count(l, item: 2309, inv: 95), 2)
		// Close the bank.
		l.tapOp("Close")
		l.pump(1)
		l.shot("bank-closed")
		XCTAssertFalse(l.client.state.interfaces.open.values.contains(762), "bank closed")

		// Run toggle.
		l.tapOp("Inventory")
		let runBefore = l.client.host.varp(173)
		XCTAssertTrue(l.tapOp("Turn run mode on") || l.tapOp("Turn run mode off"), "run orb")
		l.pump(1.5)
		print("RUN varp 173: \(runBefore) -> \(l.client.host.varp(173))")
		XCTAssertNotEqual(runBefore, l.client.host.varp(173), "run mode toggled")

		// Friends list: Add Friend opens the name prompt.
		l.tapOp("Friends List")
		l.pump(0.5)
		XCTAssertTrue(l.tapText("Add Friend"), "Add Friend button")
		l.pump(1)
		l.shot("enter-name")
		l.client.type("zezima\n")
		l.pump(1.5)
		print("FRIENDS: \(l.client.state.social.friends.map(\.displayName))")
		XCTAssertTrue(l.client.state.social.friends.contains { $0.displayName.lowercased() == "zezima" }, "friend added")

		// Logout and back in.
		l.tapOp("Log Out")
		l.pump(0.8)
		l.shot("logout-tab")
		XCTAssertTrue(l.tapText("Click here to logout") || l.tapOp("Logout"), "logout button")
		XCTAssertTrue(l.pump(until: { l.client.screen != .game }, timeout: 10), "logged out")
		l.shot("logged-out")
		l.report()
	}

	/// True while some actor shows a hitsplat or health bar.
	func combatVisible(_ l: Live) -> (hits: Int, bars: Int) {
		let w = l.client.world
		var hits = 0, bars = 0
		for a in Array(w.ctx.npcs.values) + Array(w.ctx.players.values) {
			for i in 0..<4 where a.hitVisibleUntil[i] > w.ctx.loop { hits += 1 }
			if a.hitpointsBarVisibleUntil > w.ctx.loop { bars += 1 }
		}
		return (hits, bars)
	}

	/// Teleports to the chicken coop, attacks a chicken and waits for hitsplats, health bar and experience.
	func testCombat() throws {
		let l = try live("ptfight")
		finishTutorial(l)
		l.pump(2)
		l.say("::empty")
		l.say("::item 1205")
		l.pump(1)
		XCTAssertTrue(tapItem(l, 1205), "wield dagger")
		l.say("::tele 3235 3296 0")
		XCTAssertTrue(l.pump(until: { (l.client.state.selfWorld?.z ?? 0) > 3290 }, timeout: 10), "teleported: \(String(describing: l.client.state.selfWorld))")
		l.pump(4)
		l.client.cameraReset()
		l.pump(1)
		for (id, a) in l.client.world.ctx.npcs { print("NPC \(id) \(a.npcType?.name ?? "?") ops \(a.npcType?.ops.compactMap { $0 } ?? [])") }
		l.shot("combat-before")
		func combatXp() -> Int { (0...6).reduce(0) { $0 + Int(l.client.state.stats[$1]?.xp ?? 0) } }
		let xp0 = combatXp()
		var target = l.findNpc(op: "Attack", name: "chicken")
		if target == nil { // turn the camera around once if nothing is on screen
			l.client.cameraDrag(dx: 400, dy: 0)
			l.pump(1)
			target = l.findNpc(op: "Attack", name: "chicken")
		}
		let t = try XCTUnwrap(target, "a chicken to attack")
		_ = l.takeSent()
		l.client.tap(x: t.x, y: t.y)
		print("COMBAT sent: \(l.takeSent())")
		var sawHit = false, sawBar = false
		var shots = 0
		let until = Date().addingTimeInterval(25)
		while Date() < until {
			l.pump(0.3)
			let c = combatVisible(l)
			if c.hits > 0 && !sawHit { sawHit = true; l.shot("combat-hitsplat") }
			if c.bars > 0 && !sawBar { sawBar = true; l.shot("combat-healthbar") }
			if c.hits > 0 && shots < 1 { shots += 1 }
			if combatXp() > xp0 && sawHit && sawBar { break }
		}
		print("COMBAT result: hit=\(sawHit) bar=\(sawBar) combat xp \(xp0)->\(combatXp())")
		XCTAssertTrue(sawHit, "a hitsplat was shown")
		XCTAssertTrue(sawBar, "a health bar was shown")
		XCTAssertGreaterThan(combatXp(), xp0, "combat experience granted")
		l.pump(1)
		l.shot("combat-after")
		l.report()
		l.client.logout()
	}

	/// Opens the inventory tab unless it is showing (tapping the open tab folds the side panel away in resizable mode).
	func showInventory(_ l: Live) {
		if !l.client.ui.drawn.contains(where: { $0.component.type == 2 && $0.component.id >> 16 == 149 }) { l.tapOp("Inventory"); l.pump(0.5) }
	}

	func teleport(_ l: Live, _ x: Int, _ z: Int) {
		l.say("::tele \(x) \(z) 0")
		let ok = l.pump(until: { if let p = l.client.state.selfWorld { return abs(p.x - x) <= 2 && abs(p.z - z) <= 2 }; return false }, timeout: 10)
		XCTAssertTrue(ok, "teleported to \(x),\(z): \(String(describing: l.client.state.selfWorld))")
		l.pump(4)
		l.client.cameraReset()
		l.pump(1)
	}

	/// Talks to Hans (dialogue with options), uses a shop, lights a fire (item on item) and cooks (item on object).
	func testWorldInteractions() throws {
		let l = try live("ptworld")
		finishTutorial(l)
		l.pump(2)
		l.say("::empty")

		// Hans in Lumbridge castle: dialogue with options.
		teleport(l, 3222, 3219)
		var hans = l.findNpc(op: "Talk-to", name: "hans")
		if hans == nil { l.client.cameraDrag(dx: 500, dy: 0); l.pump(1); hans = l.findNpc(op: "Talk-to", name: "hans") }
		if let h = hans {
			l.client.tap(x: h.x, y: h.y)
			l.pump(4)
			let t = l.driveDialogue(prefer: ["Who are you", "I'm looking for whoever is in charge", "Can you tell me"], rounds: 14, shots: "hans")
			for line in t { print("HANS: \(line)") }
			XCTAssertGreaterThan(t.count, 2, "a conversation took place")
			l.pump(2)
		} else {
			print("HANS not found; npcs: \(l.client.world.ctx.npcs.values.compactMap { $0.npcType?.name })")
			XCTFail("Hans on screen")
		}
		XCTAssertNil(l.dialogue, "dialogue ended: \(l.describe().prefix(300))")

		// Fire: tinderbox on logs, then raw shrimp on the fire.
		l.say("::item 590")
		l.say("::item 1511")
		l.say("::item 317 3")
		l.pump(1)
		l.shot("after-hans")
		print("INV after items: \(l.client.state.inventories[93]?.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value.id)" } ?? []) \(l.describe().prefix(400))")
		showInventory(l)
		_ = l.takeSent()
		XCTAssertTrue(tapItem(l, 590), "select tinderbox")
		print("USE target after tinderbox: \(String(describing: l.client.interaction.target))")
		l.shot("use-tinderbox")
		XCTAssertTrue(tapItem(l, 1511), "tap logs")
		print("USE sent: \(l.takeSent())")
		l.pump(8)
		print("FIRE chat: \(l.client.state.chatLog.lines.prefix(3).map(\.message))")
		XCTAssertEqual(count(l, item: 1511), 0, "logs burned")
		l.shot("fire")
		// Cook shrimp on the fire.
		l.client.cameraReset()
		l.pump(1)
		XCTAssertTrue(tapItem(l, 317), "select raw shrimp")
		let fire = l.scanWorld(step: 12) { $0.op == "Use" && $0.base.lowercased().contains("fire") }
		print("FIRE scan: \(String(describing: fire?.entry.base))")
		if let f = fire {
			l.client.tap(x: f.x, y: f.y)
			l.pump(3)
			print("COOK interfaces: \(l.describe().prefix(300))")
			l.shot("cook-prompt")
			print("COOK ui: \(l.uiSummary(Array(l.client.state.interfaces.open.values.filter { $0 > 200 && $0 < 800 && ![746, 747, 748, 749, 750, 751, 752, 754, 261, 274, 320, 387, 464, 550, 551, 589, 182, 187, 192, 271, 92, 149, 137].contains($0) })).prefix(14))")
			for d in l.drawn(307) { print("COOK comp 307:\(d.component.id & 0xFFFF) type \(d.component.type) btn \(d.component.buttonType) option \(String(describing: d.component.option)) at \(d.x),\(d.y) \(d.w)x\(d.h)") }
			if let d = l.drawn(307).first(where: { $0.component.type == 6 }) {
				l.client.longPress(x: d.x + d.w / 2, y: d.y + d.h / 2)
				print("COOK menu: \(l.client.interaction.popup.map { m in (0..<m.menu.count).map { m.menu.text($0) } } ?? [])")
				l.shot("cook-menu")
				l.client.dismissMenu()
				l.tap(d)
			}
			l.pump(10)
			print("COOK chat: \(l.client.state.chatLog.lines.prefix(3).map(\.message)) shrimp \(count(l, item: 317)) cooked \(count(l, item: 315))")
		} else {
			l.client.cameraDrag(dx: 400, dy: 0)
			l.pump(1)
			l.shot("fire-notfound")
			XCTFail("fire visible")
		}
		l.report()
		l.client.logout()
	}

	/// Lumbridge general store (shop interface, buy) and Wind Strike on a chicken (spell target mode).
	func testShopAndMagic() throws {
		let l = try live("ptshop")
		finishTutorial(l)
		l.pump(2)
		l.say("::empty")
		l.say("::item 995 1000")
		l.pump(1)
		teleport(l, 3212, 3248)
		var keeper = l.findNpc(op: "Talk-to", name: "shopkeeper")
		if keeper == nil { l.client.cameraDrag(dx: 500, dy: 0); l.pump(1); keeper = l.findNpc(op: "Talk-to", name: "shopkeeper") }
		if let k = keeper {
			l.client.longPress(x: k.x, y: k.y)
			XCTAssertTrue(chooseMenu(l, "Trade"), "Trade option")
			XCTAssertTrue(l.pump(until: { l.client.state.interfaces.open.values.contains(620) }, timeout: 8), "shop opens: \(l.describe().prefix(300))")
			l.pump(1.5)
			l.shot("shop")
			print("SHOP ifaces: \(l.openInterfaces) type2 \(l.client.ui.drawn.filter { $0.component.type == 2 }.map { $0.component.id >> 16 })")
			print("SHOP items drawn: \(l.client.ui.drawn.filter { $0.component.objId != -1 && $0.component.id >> 16 == 620 }.count)")
			let item = l.client.ui.drawn.first { $0.component.objId != -1 && $0.component.id >> 16 == 620 && $0.w > 0 }
			if let it = item {
				l.client.longPress(x: it.x + it.w / 2, y: it.y + it.h / 2)
				print("SHOP menu: \(l.client.interaction.popup.map { m in (0..<m.menu.count).map { m.menu.text($0) } } ?? [])")
				l.shot("shop-menu")
				let before = count(l, item: 995)
				if chooseMenu(l, "Buy 1") {
					l.pump(1.5)
					print("SHOP bought: coins \(before) -> \(count(l, item: 995)) inv \(l.client.state.inventories[93]?.values.map(\.id) ?? [])")
					XCTAssertLessThan(count(l, item: 995), before, "coins spent")
				} else { l.client.dismissMenu(); XCTFail("Buy 1 option") }
			} else { XCTFail("shop stock drawn") }
			l.tapOp("Close")
			l.pump(1)
			XCTAssertFalse(l.client.state.interfaces.open.values.contains(620), "shop closed")
		} else {
			XCTFail("shopkeeper on screen: \(l.client.world.ctx.npcs.values.compactMap { $0.npcType?.name })")
		}

		// Wind Strike on a chicken.
		l.say("::item 556 50")
		l.say("::item 558 50")
		teleport(l, 3235, 3296)
		l.tapOp("Magic Spellbook")
		l.pump(1)
		l.shot("spellbook")
		let spell = l.client.ui.drawn.first { $0.component.optionBase.contains("Wind Strike") || $0.component.option == "Cast" && $0.component.optionBase.contains("Wind") }
		print("SPELL comp: \(String(describing: spell.map { ($0.component.id >> 16, $0.component.id & 0xFFFF, $0.component.optionBase, $0.component.ops.first ?? "") }))")
		let sp = try XCTUnwrap(spell, "Wind Strike in the spellbook")
		l.tap(sp)
		print("SPELL target: \(String(describing: l.client.interaction.target))")
		XCTAssertNotNil(l.client.interaction.target, "spell target mode")
		var chicken = l.findNpc(op: "Cast", name: "chicken")
		if chicken == nil { l.client.cameraDrag(dx: 400, dy: 0); l.pump(1); chicken = l.findNpc(op: "Cast", name: "chicken") }
		let c = try XCTUnwrap(chicken, "chicken as spell target")
		l.client.tap(x: c.x, y: c.y)
		var hit = false
		let until = Date().addingTimeInterval(15)
		while Date() < until && !hit { l.pump(0.3); hit = combatVisible(l).hits > 0 }
		l.shot("spell-hit")
		XCTAssertTrue(hit, "the spell hit")
		XCTAssertGreaterThan(l.client.state.stats[6]?.xp ?? 0, 0, "magic xp")
		l.report()
		l.client.logout()
	}

	/// Opens a wide set of server interfaces with `::iface` and reports script failures and unported CS2 ops.
	func testInterfaceSweep() throws {
		let l = try live("ptsweep")
		finishTutorial(l)
		l.pump(2)
		l.say("::item 995 1000")
		let ids = [105, 107, 109, 12, 13, 14, 17, 18, 19, 23, 25, 26, 27, 28, 38, 47, 52, 60, 64, 67, 70, 76, 84, 90, 102, 103, 104, 106, 108, 111, 112, 114, 115, 116, 117, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 138, 139, 141, 143, 144, 145, 146, 147, 148, 150, 154, 155, 156, 157, 158, 159, 160,
			200, 201, 205, 206, 207, 208, 209, 210, 211, 213, 214, 215, 216, 217, 218, 220, 221, 222, 223, 225, 226, 227, 228, 229, 230, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 254, 255, 259, 260, 262, 266, 267, 268, 269, 270, 272, 273, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290,
			300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370,
			400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480,
			500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 546, 547, 548, 549, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 567, 568, 569, 570,
			600, 601, 602, 603, 604, 605, 606, 607, 608, 609, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 622, 623, 624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638, 639, 640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 650, 651, 652, 653, 654, 655, 656, 657, 658, 659, 660, 661, 662, 663, 664, 665, 666, 667, 668, 669, 670,
			700, 701, 702, 703, 704, 705, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719, 720, 721, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 732, 733, 734, 735, 736, 737, 738, 739, 740, 741, 742, 743, 745, 755, 756, 757, 758, 759, 760, 761, 764, 765, 766, 767, 768, 769, 770, 772, 773, 774, 775, 776, 777, 778, 779, 780]
		// Full sweep (483 interfaces, ~11 min) only with SWEEP_ALL=1; otherwise a 1-in-12 sample plus known-problem ids.
		let all = ProcessInfo.processInfo.environment["SWEEP_ALL"] != nil
		let sweepIds = all ? ids : ids.enumerated().filter { $0.offset % 12 == 0 || [102, 105, 307, 762, 620].contains($0.element) }.map { $0.element }
		var before = l.client.scriptErrorCounts.count
		var report: [(Int, [String])] = []
		var rendered = 0
		for id in sweepIds {
			l.client.send(.command("iface \(id)"))
			l.pump(0.5)
			var failed = true
			do { _ = try l.client.frame(width: l.w, height: l.h); failed = false } catch { report.append((id, ["render threw: \(error)"])) }
			rendered += failed ? 0 : 1
			let errs = Array(l.client.scriptErrorCounts.keys.sorted())
			if errs.count > before { report.append((id, Array(errs.suffix(errs.count - before)))); before = errs.count }
			l.client.send(.closeModal)
			l.pump(0.2)
		}
		for (id, e) in report { print("SWEEP \(id): \(e.prefix(3))") }
		print("SWEEP rendered \(rendered) of \(ids.count) interfaces without throwing; unported cs2: \(l.client.unportedScriptOpcodes.sorted { $0.key < $1.key })")
		l.report()
		l.client.logout()
	}
}
