import Foundation
import XCTest
@testable import Scape530

/// The 3D world behind the interfaces: camera maths (no cache needed) and a replay of the
/// recorded resizable session through `GameClient` that renders in-game frames to PNG.
final class WorldViewTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	func testCameraGeometry() {
		var cam = WorldCamera()
		cam.followX = 64 * 128; cam.followZ = 64 * 128
		cam.pitchTarget = 200
		cam.yawTarget = 0
		var eye = cam.eye(groundY: 0)
		// Looking north (yaw 0): the eye is south of the target (smaller z), up (negative y).
		XCTAssertEqual(eye.x, 64 * 128)
		XCTAssertLessThan(eye.z, 64 * 128)
		XCTAssertLessThan(eye.y, -50)
		let distance = cam.zoom + 200 * 3
		let horizontal = Double(64 * 128 - eye.z), vertical = Double(-50 - eye.y)
		XCTAssertEqual((horizontal * horizontal + vertical * vertical).squareRoot(), Double(distance), accuracy: 3)
		// A quarter turn puts the eye to one side instead.
		cam.yawTarget = 512
		eye = cam.eye(groundY: 0)
		XCTAssertNotEqual(eye.x, 64 * 128)
		XCTAssertEqual(eye.z, 64 * 128, accuracy: 3)
	}

	func testCameraLimitsAndFollow() {
		var cam = WorldCamera()
		cam.drag(dx: 0, dy: 100000)
		XCTAssertEqual(cam.pitchTarget, WorldCamera.maxPitch)
		cam.drag(dx: 0, dy: -100000)
		XCTAssertEqual(cam.pitchTarget, WorldCamera.minPitch)
		cam.drag(dx: 5000, dy: 0)
		XCTAssertTrue(cam.yawTarget >= 0 && cam.yawTarget < 2047)
		cam.pinch(scale: 100)
		XCTAssertEqual(cam.zoom, WorldCamera.minZoom)
		cam.pinch(scale: 0.001)
		XCTAssertEqual(cam.zoom, WorldCamera.maxZoom)
		cam.follow(playerXFine: 1000, playerZFine: 1000)
		XCTAssertEqual(cam.followX, 1000)
		cam.follow(playerXFine: 1128, playerZFine: 1000)
		XCTAssertEqual(cam.followX, 1000 + 128 / 16)
	}

	/// Feeds the recorded session (rebuilds, player and npc info) into a `GameClient` as session
	/// events, running 30 client cycles per player-info tick the way a live game would.
	func replay(_ client: GameClient, cyclesPerTick: Int = 30) throws {
		let me = 2047 // the first player-info section is always the local player
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: me, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		var players = PlayerInfoDecoder(selfIndex: me, localX: 52, localZ: 52)
		var npcs = NpcInfoDecoder()
		var zone: (x: Int, z: Int)?
		for pkt in try SessionReplayTests.recordedPackets("resizable-session") {
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

	func testReplayRendersWorldBehindInterface() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		try replay(client)
		XCTAssertEqual(client.screen, .game)
		XCTAssertEqual(client.state.interfaces.top, 746)
		let world = client.world

		var first = true
		for (w, h) in [(1015, 469), (1024, 768), (765, 503)] {
			let t0 = Date()
			var r = try client.frame(width: w, height: h)
			let firstTime = Date().timeIntervalSince(t0)
			if first {
				print("first frame (scene build \(String(format: "%.2f", world.lastBuildSeconds)) s, errors \(world.buildErrors)): \(String(format: "%.2f", firstTime)) s")
				first = false
			}
			// Steady state: a few frames, then time them.
			var total = 0.0
			let n = 3
			for _ in 0..<n {
				let t = Date()
				r = try client.frame(width: w, height: h)
				total += Date().timeIntervalSince(t)
			}
			print("frame \(w)x\(h): \(String(format: "%.0f", total / Double(n) * 1000)) ms avg of \(n); viewport \(String(describing: client.viewport))")
			try save(r, "world-\(w)x\(h)")
			// The same view without interfaces on top.
			var bare = Raster(width: w, height: h)
			XCTAssertTrue(world.draw(into: &bare, rect: (0, 0, w, h)))
			try save(bare, "world-bare-\(w)x\(h)")
			if w == 1015 {
				XCTAssertEqual(world.buildErrors, [])
				XCTAssertNotNil(client.viewport, "interface 746 has a 1337 viewport component")
				XCTAssertGreaterThan(world.ctx.players.count, 0)
				XCTAssertGreaterThan(world.ctx.npcs.count, 0)
				// The world occupies the viewport: lots of non-black, varied pixels where there is no interface.
				let v = try XCTUnwrap(client.viewport)
				var colours = Set<UInt32>()
				var lit = 0
				for y in stride(from: v.y, to: v.y + v.h, by: 4) {
					for x in stride(from: v.x, to: v.x + v.w, by: 4) {
						let p = r.pixels[y * w + x]
						if p & 0xFFFFFF != 0 { lit += 1 }
						colours.insert(p)
					}
				}
				XCTAssertGreaterThan(lit, (v.w / 4) * (v.h / 4) / 2, "world covers the viewport")
				XCTAssertGreaterThan(colours.count, 200)
			}
		}
	}

	/// Drags and pinches change the picture; actors move between ticks.
	func testCameraControlsChangeFrame() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		try replay(client)
		let (w, h) = (852, 393)
		let a = try client.frame(width: w, height: h)
		client.cameraDrag(dx: 120, dy: 40)
		let b = try client.frame(width: w, height: h)
		client.cameraPinch(scale: 1.6)
		let c = try client.frame(width: w, height: h)
		XCTAssertNotEqual(a.pixels, b.pixels)
		XCTAssertNotEqual(b.pixels, c.pixels)
		try save(b, "world-dragged")
		try save(c, "world-zoomed")
		client.cameraReset()
		XCTAssertEqual(client.world.camera.zoom, WorldCamera.defaultZoom)
	}

	/// Logs in to a live server (`SCAPE530_SERVER=host:port`), waits a few seconds and renders the world.
	func testLiveWorldFrame() throws {
		let env = ProcessInfo.processInfo.environment
		guard let server = env["SCAPE530_SERVER"] else { throw XCTSkip("needs SCAPE530_SERVER") }
		let parts = server.split(separator: ":")
		let client = try GameClient(store: try store(), server: .init(host: String(parts[0]), port: Int(parts[1]) ?? 43595))
		let (w, h) = (1015, 469)
		_ = try client.frame(width: w, height: h)
		let d = try XCTUnwrap(client.ui.drawn.last { $0.component.id == client.loginInterface << 16 | 250 })
		client.tap(x: d.x + d.w / 2, y: d.y + d.h / 2)
		client.type("worldview\ntester\n")
		let deadline = Date().addingTimeInterval(20)
		var r = try client.frame(width: w, height: h)
		while Date() < deadline && (client.screen != .game || client.state.ticks < 12) {
			Thread.sleep(forTimeInterval: 0.02)
			r = try client.frame(width: w, height: h)
		}
		XCTAssertEqual(client.screen, .game, "status: \(client.status)")
		// A few more seconds of live ticks, rendering at a normal pace.
		let until = Date().addingTimeInterval(4)
		while Date() < until {
			Thread.sleep(forTimeInterval: 0.02)
			r = try client.frame(width: w, height: h)
		}
		print("live: scene build \(client.world.lastBuildSeconds) s, errors \(client.world.buildErrors), players \(client.world.ctx.players.count), npcs \(client.world.ctx.npcs.count), tile \(String(describing: client.world.selfTile))")
		XCTAssertTrue(client.world.isReady)
		XCTAssertEqual(client.world.buildErrors, [])
		try save(r, "world-live-\(w)x\(h)")
		var bare = Raster(width: w, height: h)
		XCTAssertTrue(client.world.draw(into: &bare, rect: (0, 0, w, h)))
		try save(bare, "world-live-bare")
		client.logout()
	}
}
