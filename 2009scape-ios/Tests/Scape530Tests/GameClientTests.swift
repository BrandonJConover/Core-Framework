import Foundation
import XCTest
@testable import Scape530

/// Drives the whole client like a player would: tap "Log In", type, submit,
/// and wait for the game frame. Needs a cache and a server
/// (`SCAPE530_SERVER=host:port`).
final class GameClientTests: XCTestCase {
	func center(_ client: GameClient, _ component: Int) throws -> (Int, Int) {
		let d = try XCTUnwrap(client.ui.drawn.last { $0.component.id == client.loginInterface << 16 | component })
		return (d.x + d.w / 2, d.y + d.h / 2)
	}

	func testLoginFlowToGameFrame() throws {
		let env = ProcessInfo.processInfo.environment
		guard let dir = env["SCAPE530_CACHE"], let server = env["SCAPE530_SERVER"] else { throw XCTSkip("needs SCAPE530_CACHE and SCAPE530_SERVER") }
		let parts = server.split(separator: ":")
		let store = ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
		let client = try GameClient(store: store, server: .init(host: String(parts[0]), port: Int(parts[1]) ?? 43595))
		let (w, h) = (852, 393) // iPhone 15 landscape, 1 game pixel per point
		var out = URL(fileURLWithPath: env["SCAPE530_OUT"] ?? NSTemporaryDirectory())

		_ = try client.frame(width: w, height: h)
		let (lx, ly) = try center(client, 250)
		client.tap(x: lx, y: ly)
		XCTAssertEqual(client.screen, .loginForm)
		XCTAssertTrue(client.wantsKeyboard)
		client.type("phone\ntester\n") // return moves to password, then submits
		XCTAssertEqual(client.username, "phone")
		XCTAssertEqual(client.screen, .connecting)

		let deadline = Date().addingTimeInterval(15)
		var r = try client.frame(width: w, height: h)
		while Date() < deadline && (client.screen != .game || client.state.ticks < 10) {
			Thread.sleep(forTimeInterval: 0.05)
			r = try client.frame(width: w, height: h)
		}
		XCTAssertEqual(client.screen, .game, "status: \(client.status)")
		XCTAssertEqual(client.state.interfaces.top, 746)
		XCTAssertNotNil(client.state.selfWorld)
		out.appendPathComponent("client-game-\(w)x\(h).png")
		try Data(PNG.encode(r)).write(to: out)
		client.logout()
	}
}

final class CacheUpdaterTests: XCTestCase {
	/// Downloads the sprite, font and interface archives from a live server
	/// into an empty folder, checks they read back, then reruns and expects
	/// nothing more to fetch.
	func testDownloadIntoEmptyCache() throws {
		let env = ProcessInfo.processInfo.environment
		guard let server = env["SCAPE530_SERVER"] else { throw XCTSkip("needs SCAPE530_SERVER") }
		let parts = server.split(separator: ":")
		let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("js5-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: dir) }
		let updater = CacheUpdater(directory: dir, host: String(parts[0]), port: Int(parts[1]) ?? 43595)
		let wanted = [3, 8, 13]
		let first = try updater.run(archives: wanted)
		XCTAssertGreaterThan(first, 1000)
		let store = ConfigStore(disk: try DiskCache(directory: dir))
		XCTAssertNotNil(try store.sprite(named: "titlebg"))
		XCTAssertNotNil(try store.font(named: "p12_full"))
		XCTAssertNotNil(try InterfaceRenderer(store: store).components(744).first ?? nil)
		XCTAssertEqual(try updater.run(archives: wanted), 0)
	}
}
