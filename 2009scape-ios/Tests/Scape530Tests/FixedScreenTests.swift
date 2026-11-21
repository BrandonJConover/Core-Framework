import Foundation
import XCTest
@testable import Scape530

/// Fixed 765x503 mode (top-level interface 548, rt4 `DisplayMode` mode 0) next to resizable (746).
final class FixedScreenTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func fixedClient(width: Int, height: Int) throws -> GameClient {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		client.windowMode = .fixed
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: 2047, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		client.handle(.message(.ifOpenTop(id: 548, reset: 0)))
		for _ in 0..<3 { _ = try client.frame(width: width, height: height) }
		return client
	}

	func testLayoutAndViewport() throws {
		let client = try fixedClient(width: 1100, height: 700)
		XCTAssertEqual(client.state.interfaces.top, 548)
		// The game is laid out on a 765x503 canvas whatever the shell's size (rt4 `GameShell.canvasWidth`).
		XCTAssertEqual(client.host.canvas.w, 765)
		XCTAssertEqual(client.host.canvas.h, 503)
		let v = try XCTUnwrap(client.viewport)
		XCTAssertEqual([v.x, v.y, v.w, v.h], [4, 4, 512, 334], "rt4 fixed viewport (548:1 at 4,4 holding the 512x334 clientCode 1337)")
		// Minimap (cc 1338) sits in the top-right panel 548:12 at 516,0.
		let map = try XCTUnwrap(client.ui.drawn.first { $0.component.clientCode == 1338 })
		XCTAssertEqual(map.x, 516 + 35)
		XCTAssertEqual(map.y, 9)
		// Both tab rows and the chatbox container are laid out at their fixed positions.
		XCTAssertNotNil(client.ui.drawn.first { $0.component.id == 548 << 16 | 18 }, "bottom tab row")
		XCTAssertNotNil(client.ui.drawn.first { $0.component.id == 548 << 16 | 36 }, "top tab row")
		let chat = try XCTUnwrap(client.ui.drawn.first { $0.component.id == 548 << 16 | 75 })
		XCTAssertEqual([chat.x, chat.y, chat.w, chat.h], [0, 338, 519, 142])
	}

	func testFrameIsCentredAndScaled() throws {
		let client = try fixedClient(width: 1100, height: 700)
		let l = try XCTUnwrap(client.fixedLayout)
		XCTAssertEqual(l.scale, 700.0 / 503.0, accuracy: 1e-9)
		XCTAssertEqual(l.h, 700)
		XCTAssertEqual(l.x, (1100 - l.w) / 2)
		let r = try client.frame(width: 1100, height: 700)
		XCTAssertEqual(r.width, 1100)
		XCTAssertEqual(r.height, 700)
		// Letterbox bars are black, the frame is not.
		XCTAssertEqual(r.pixels[350 * 1100 + 2], 0xFF00_0000)
		var colours = Set<UInt32>()
		for y in stride(from: 0, to: 700, by: 7) { for x in stride(from: l.x, to: l.x + l.w, by: 7) { colours.insert(r.pixels[y * 1100 + x]) } }
		XCTAssertGreaterThan(colours.count, 20)
		// An exactly 765x503 canvas is the frame itself.
		let exact = try fixedClient(width: 765, height: 503)
		let el = try XCTUnwrap(exact.fixedLayout)
		XCTAssertEqual([el.x, el.y, el.w, el.h], [0, 0, 765, 503])
		XCTAssertEqual(el.scale, 1)
		XCTAssertEqual(try exact.frame(width: 765, height: 503).width, 765)
	}

	func testTouchCoordinatesMapToGamePixels() throws {
		let client = try fixedClient(width: 1100, height: 700)
		let v = try XCTUnwrap(client.viewport)
		// Round trip.
		for (x, y) in [(10, 10), (300, 200), (760, 500)] {
			let c = client.toCanvas(x: x, y: y)
			let g = client.toGame(x: c.x, y: c.y)
			XCTAssertEqual(g.x, x, accuracy: 1)
			XCTAssertEqual(g.y, y, accuracy: 1)
		}
		// The viewport centre in canvas pixels is over the world; the letterbox is not; neither is a button.
		let c = client.toCanvas(x: v.x + v.w / 2, y: v.y + v.h / 2)
		XCTAssertTrue(client.isOverWorld(x: c.x, y: c.y))
		XCTAssertFalse(client.isOverWorld(x: 3, y: 350))
		let tab = try XCTUnwrap(client.ui.drawn.last { $0.component.id == 548 << 16 | 69 })
		let t = client.toCanvas(x: tab.x + tab.w / 2, y: tab.y + tab.h / 2)
		XCTAssertFalse(client.isOverWorld(x: t.x, y: t.y))
		// Resizable mode is the identity again.
		client.windowMode = .resizable
		_ = try client.frame(width: 1100, height: 700)
		XCTAssertEqual(client.toGame(x: 123, y: 45).x, 123)
		XCTAssertNil(client.fixedLayout)
	}

	func testTapOnButtonInFixedMode() throws {
		let client = try fixedClient(width: 1100, height: 700)
		var sent: [ClientMessage] = []
		let old = client.host.send
		client.host.send = { sent.append($0); old($0) }
		let tab = try XCTUnwrap(client.ui.drawn.last { $0.component.id == 548 << 16 | 69 })
		let t = client.toCanvas(x: tab.x + tab.w / 2, y: tab.y + tab.h / 2)
		client.tap(x: t.x, y: t.y)
		XCTAssertFalse(sent.isEmpty, "the minimap button (548:69) reacts to a tap at its scaled position")
	}

	func testWindowModeOpsFollowRt4() throws {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		XCTAssertEqual(client.windowMode, .resizable)
		XCTAssertEqual(client.host.windowModeValue(), 2)
		client.host.onSetWindowMode(1) // rt4 5307 with 0/1 -> fixed
		XCTAssertEqual(client.windowMode, .fixed)
		XCTAssertEqual(client.host.windowModeValue(), 0)
		client.host.onSetWindowMode(2)
		XCTAssertEqual(client.windowMode, .resizable)
		XCTAssertEqual(WindowMode.fixed.rawValue, 0)
		XCTAssertEqual(WindowMode.resizable.rawValue, 2)
	}
}
