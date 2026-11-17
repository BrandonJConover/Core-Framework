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

		init(store: ConfigStore, server: String, user: String) throws {
			let parts = server.split(separator: ":")
			client = try GameClient(store: store, server: .init(host: String(parts[0]), port: Int(parts[1]) ?? 43595))
			last = try client.frame(width: w, height: h)
			if let o = ProcessInfo.processInfo.environment["SCAPE530_OUT"] { outDir = URL(fileURLWithPath: o) }
			client.log = { print("client log: \($0)") }
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

	/// Fresh account: finish character design, talk to the Gielinor Guide through the dialogue.
	func testTutorialDialogue() throws {
		let l = try live("tut")
		// Character design screens (interface 771): mouse style, then each tab.
		l.shot("design-00")
		XCTAssertTrue(l.tapOp("Select 2-button mouse"))
		for step in 0..<8 where !l.openInterfaces.isEmpty && l.client.state.interfaces.open.values.contains(771) {
			let ops = l.client.ui.drawn.compactMap { $0.component.ops.first }.filter { !$0.isEmpty }
			print("DESIGN step \(step): \(ops.prefix(14))")
			if step == 1 { l.shot("design-01") }
			if !(l.tapOp("Select next") || l.tapOp("Confirm changes")) { break }
			l.pump(1.2)
		}
		print("DESIGN done: \(l.describe())")
		l.pump(2)
		l.shot("tutorial-start")
		// Talk to the guide.
		for (id, a) in l.client.world.ctx.npcs {
			let p = l.project(xFine: a.xFine, yFine: a.groundY - 60, zFine: a.zFine)
			var top = "-"
			if let p, let (m, _) = l.client.buildMenu(x: p.0, y: p.1) { top = m.text(m.top) }
			print("NPC \(id) \(a.npcType?.name ?? "?") type \(a.npcType?.id ?? -1) interactive \(a.npcType?.interactive ?? false) ops \(a.npcType?.ops ?? []) at \(String(describing: p)) top=\(top)")
		}
		let found = l.findNpc(op: "Talk-to", name: "skippy") ?? l.findNpc(op: "Talk-to")
		print("TALK candidate: \(String(describing: found)) npcs \(l.client.world.ctx.npcs.count)")
		if let f = found {
			l.client.tap(x: f.x, y: f.y)
			l.pump(4)
			l.pump(2)
			print("DLG drawn241=\(l.drawn(241).count) 137=\(l.drawn(137).count) all ifaces=\(Set(l.client.ui.drawn.map { $0.component.id >> 16 }).sorted())")
			let t = l.driveDialogue(prefer: ["Yes, I'd like to skip"], shots: "dialogue")
			for line in t.prefix(8) { print("DIALOGUE: \(line)") }
		}
		l.pump(2)
		print("AFTER skip: \(l.describe())")
		l.shot("after-skip")
		if let t = l.findNpc(op: "Talk-to", name: "instructor") ?? l.findNpc(op: "Talk-to") {
			l.client.tap(x: t.x, y: t.y)
			l.pump(4)
			let tr = l.driveDialogue(prefer: ["Yes, I'm ready", "I'm ready now"], shots: "terrova")
			for line in tr { print("TERROVA: \(line)") }
		}
		l.pump(4)
		print("AFTER tutorial: \(l.describe())")
		l.shot("after-tutorial")
		l.report()
		l.client.logout()
	}
}
