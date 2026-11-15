import Foundation
import XCTest
@testable import Scape530

/// Decodes sprites and fonts from the real cache and renders them, writing
/// PNGs to `SCAPE530_OUT` (if set) so they can be compared by eye with the
/// original client.
final class GraphicsTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	func testEverySpriteDecodes() throws {
		let s = try store()
		let idx = try s.index(ConfigStore.GraphicsArchive.sprites)
		var failures: [String] = []
		var frames = 0
		for g in idx.groupIds {
			do { frames += try s.sprite(g)?.frames.count ?? 0 } catch { failures.append("sprite \(g): \(error)") }
		}
		XCTAssertEqual(failures, [])
		print("decoded \(idx.groupIds.count) sprite groups, \(frames) frames")
	}

	func testTitleScreen() throws {
		let s = try store()
		let bg = try XCTUnwrap(try s.sprite(named: "titlebg")).frames[0]
		let logo = try XCTUnwrap(try s.sprite(named: "logo")).frames[0]
		let p12 = try XCTUnwrap(try s.font(named: "p12_full"))
		let b12 = try XCTUnwrap(try s.font(named: "b12_full"))
		XCTAssertGreaterThan(p12.lineHeight, 8)
		XCTAssertEqual(p12.stringWidth("<col=ff0000>a</col>"), p12.stringWidth("a"))

		// rt4 TitleScreen.load at the classic 765x503 canvas.
		var r = Raster(width: 765, height: 503)
		let w = r.height * 956 / 503
		r.drawScaled(bg, x: (r.width - w) / 2, y: 0, w: w, h: r.height)
		r.draw(logo, x: r.width / 2 - logo.width / 2, y: 18)
		b12.drawCenter("Welcome to RuneScape", x: 382, y: 260, color: 0xFFFF00, shadow: 0, into: &r)
		p12.drawCenter("Native Swift client: <col=ff9040>rev 530</col>", x: 382, y: 280, color: 0xFFFFFF, shadow: 0, into: &r)
		try save(r, "title-765x503")
	}
}

extension GraphicsTests {
	func testEveryInterfaceDecodes() throws {
		let s = try store()
		let ui = InterfaceRenderer(store: s)
		let idx = try s.index(ConfigStore.GraphicsArchive.interfaces)
		var failures: [String] = []
		var count = 0
		for g in idx.groupIds {
			do { count += try ui.components(g).compactMap { $0 }.count } catch { failures.append("interface \(g): \(error)") }
		}
		XCTAssertEqual(failures, [])
		print("decoded \(idx.groupIds.count) interfaces, \(count) components")
	}

	/// Replays the recorded live session's interface packets and draws the
	/// resulting game frame, like the client would after login (minus the 3D view).
	func testRecordedGameFrame() throws {
		let s = try store()
		let ui = InterfaceRenderer(store: s)
		var state = InterfaceState()
		for pkt in try SessionReplayTests.recordedPackets() where pkt.opcode != ServerProt.playerInfo && pkt.opcode != ServerProt.npcInfo {
			state.apply(try ServerMessage.decode(pkt))
		}
		print("hidden \(state.hidden.map { "\($0.key >> 16):\($0.key & 0xFFFF)=\($0.value)" })")
		print("top \(state.top), open \(state.open.sorted { $0.key < $1.key }.map { "\($0.key >> 16):\($0.key & 0xFFFF)->\($0.value)" })")
		XCTAssertNotEqual(state.top, -1)
		var r = Raster(width: 765, height: 503)
		try ui.render(state.top, state: state, into: &r)
		try save(r, "gameframe-\(state.top)")
		var chat = Raster(width: 519, height: 142)
		try ui.render(752, state: state, into: &chat)
		try save(chat, "chat-752")
	}
}

extension GraphicsTests {
	/// Resizable mode (window mode 2) is how the client fits any screen: the
	/// server opens interface 746 and its components stretch with the canvas.
	/// Rendered at phone and tablet landscape sizes (in game pixels).
	func testResizableFrameAtPhoneSizes() throws {
		let s = try store()
		let ui = InterfaceRenderer(store: s)
		var state = InterfaceState()
		for pkt in try SessionReplayTests.recordedPackets("resizable-session") where pkt.opcode != ServerProt.playerInfo && pkt.opcode != ServerProt.npcInfo {
			state.apply(try ServerMessage.decode(pkt))
		}
		XCTAssertEqual(state.top, 746)
		for (w, h) in [(1015, 469), (1024, 768), (765, 503)] {
			var r = Raster(width: w, height: h)
			try ui.render(state.top, state: state, into: &r)
			try save(r, "resizable-\(w)x\(h)")
		}
	}
}

extension GraphicsTests {
	func testLoginScreenInterface() throws {
		let s = try store()
		let ui = InterfaceRenderer(store: s)
		let id = try XCTUnwrap(try ui.interfaceId(named: "loginscreen"))
		print("loginscreen interface \(id)")
		var state = InterfaceState()
		state.hidden[id << 16 | 226] = false
		state.hidden[id << 16 | 131] = false
		for (w, h) in [(765, 503), (852, 393)] {
			var r = Raster(width: w, height: h)
			try ui.render(id, state: state, into: &r)
			try save(r, "loginscreen-\(w)x\(h)")
		}
	}
}
