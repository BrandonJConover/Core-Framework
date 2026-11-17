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

		/// Scans the viewport for a point whose default (top) menu entry matches `match`.
		func scanWorld(step: Int = 10, _ match: (Menu.Entry) -> Bool) -> (x: Int, y: Int, entry: Menu.Entry)? {
			guard let v = client.viewport else { return nil }
			for dy in stride(from: 20, to: v.h - 20, by: step) {
				for dx in stride(from: 20, to: v.w - 20, by: step) {
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
	func finishTutorial(_ l: Live) {
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
		guard l.client.state.interfaces.open.values.contains(372) || l.findNpc(op: "Talk-to", name: "skippy") != nil || l.dialogue != nil else { return }
		if let f = l.findNpc(op: "Talk-to", name: "skippy") {
			l.client.tap(x: f.x, y: f.y)
			l.pump(4)
			l.driveDialogue(prefer: ["Yes, I'd like to skip"], shots: "skippy")
			l.pump(2)
		}
		if let t = l.findNpc(op: "Talk-to", name: "instructor") {
			l.client.tap(x: t.x, y: t.y)
			l.pump(4)
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
}
