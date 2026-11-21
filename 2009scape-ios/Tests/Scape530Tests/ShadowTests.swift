import Foundation
import XCTest
@testable import Scape530

/// Character shadows (rt4 `ShadowModelList`), the terrain tilt of large creatures (`method2685`) and BAS
/// roll / pitch (`method2687`).
final class ShadowTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	/// Feeds the recorded session into a `GameClient` (copied from `WorldViewTests.replay`).
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

	// MARK: BAS decoding

	func testBasFootprintRollPitchDecode() throws {
		var b = BasType(id: 1)
		var p = Packet([10, 12])
		try b.decode(opcode: 26, &p)
		XCTAssertEqual(b.opcode26.0, 40)
		XCTAssertEqual(b.opcode26.1, 48)
		for (op, bytes) in [(31, [3]), (32, [0, 9]), (33, [0xFF, 0xF0]), (34, [4]), (35, [0, 7]), (36, [0, 20])] as [(Int, [UInt8])] {
			var q = Packet(bytes)
			try b.decode(opcode: op, &q)
		}
		XCTAssertEqual(b.roll.acceleration, 3)
		XCTAssertEqual(b.roll.maxSpeed, 9)
		XCTAssertEqual(b.roll.target, -16)
		XCTAssertEqual(b.pitch.acceleration, 4)
		XCTAssertEqual(b.pitch.maxSpeed, 7)
		XCTAssertEqual(b.pitch.target, 20)
	}

	// MARK: footprint tilt (rt4 method2685)

	func testTiltOnFlatGroundIsNoRotation() {
		let t = FootprintTilt.compute(width: 128, length: 192, orientation: 700, xFine: 5000, zFine: 7000, groundY: -40) { _, _ in -40 }
		XCTAssertEqual(t.rotateX, 0)
		XCTAssertEqual(t.rotateZ, 0)
		XCTAssertEqual(t.translateY, 0)
		XCTAssertTrue(t.isIdentity)
		// Level ground at another height than the actor's own only lifts it.
		let lifted = FootprintTilt.compute(width: 128, length: 192, orientation: 0, xFine: 5000, zFine: 7000, groundY: 0) { _, _ in -40 }
		XCTAssertEqual(lifted, FootprintTilt(rotateX: 0, rotateZ: 0, translateY: -40))
	}

	func testTiltWithoutFootprintIsIdentity() {
		let t = FootprintTilt.compute(width: 0, length: 128, orientation: 0, xFine: 0, zFine: 0, groundY: 0) { x, z in x + z }
		XCTAssertTrue(t.isIdentity)
	}

	func testTiltOnASlopeUsesAtan2() {
		// Facing north (orientation 0) over ground that rises 1:1 towards +z. The front corners are `length`
		// higher than the back ones: pitch of atan2(-length, length), a negative eighth turn (rt4 angle unit 2048/turn).
		let (w, l) = (128, 192)
		let t = FootprintTilt.compute(width: w, length: l, orientation: 0, xFine: 4000, zFine: 6000, groundY: 6000) { _, z in z }
		XCTAssertEqual(t.rotateX, Int(atan2(Double(-l), Double(l)) * 325.95) & 0x7FF)
		XCTAssertEqual(Double(t.rotateX), 2048 - 256, accuracy: 2)
		XCTAssertEqual(t.rotateZ, 0, "no slope across x")
		XCTAssertEqual(t.translateY, 0, "the average corner height is the ground height under the centre")
		// The same hill seen with the creature turned a quarter (orientation 512) tips it sideways instead.
		let q = FootprintTilt.compute(width: w, length: l, orientation: 512, xFine: 4000, zFine: 6000, groundY: 6000) { _, z in z }
		XCTAssertEqual(q.rotateX, 0)
		XCTAssertNotEqual(q.rotateZ, 0)
	}

	func testTiltAppliesRotationThenShift() throws {
		let m = SoftwareModel()
		m.vertexCount = 1; m.vertexX = [0]; m.vertexY = [-100]; m.vertexZ = [0]
		FootprintTilt(rotateX: 0, rotateZ: 0, translateY: 30).apply(to: m)
		XCTAssertEqual(m.vertexY, [-70])
		FootprintTilt(rotateX: 512, rotateZ: 0, translateY: 0).apply(to: m)
		XCTAssertEqual(m.vertexZ[0], -70, "a quarter turn about x moves height into z")
	}

	// MARK: roll / pitch (rt4 method2687)

	func testRollPitchSpringProgression() {
		var s = AxisSpring()
		var speeds = [Int]()
		for _ in 0..<200 {
			s.step(target: 400, acceleration: 2, maxSpeed: 10)
			speeds.append(s.velocity)
		}
		XCTAssertEqual(speeds.first, 2, "starts at one acceleration step")
		XCTAssertEqual(speeds.max(), 10, "speed is capped at maxSpeed")
		XCTAssertTrue(zip(speeds, speeds.dropFirst()).allSatisfy { abs($0 - $1) <= 2 })
		XCTAssertEqual(s.position, 400, "settles on the target")
		XCTAssertEqual(s.velocity, 0)
		// Turning back: runs the other way down to zero.
		for _ in 0..<200 { s.step(target: 0, acceleration: 2, maxSpeed: 10) }
		XCTAssertEqual(s.position, 0)
		XCTAssertEqual(s.velocity, 0)
		// A negative target mirrors it.
		var n = AxisSpring()
		for _ in 0..<200 { n.step(target: -400, acceleration: 2, maxSpeed: 10) }
		XCTAssertEqual(n.position, -400)
	}

	func testSpringWithoutAccelerationStaysPut() {
		var s = AxisSpring()
		s.step(target: 50, acceleration: 0, maxSpeed: 10)
		XCTAssertEqual(s, AxisSpring())
	}

	func testRollPitchLeanAboutMiddleHeight() {
		let m = SoftwareModel()
		m.vertexCount = 2
		m.vertexX = [0, 0]; m.vertexY = [-200, 0]; m.vertexZ = [0, 0]
		PathingActor.applyRollPitch(m, roll: 512 << 5, pitch: 0)
		// A quarter turn about z at mid height: the head (100 above the pivot) ends up 100 to the side, the feet opposite.
		XCTAssertEqual(Double(m.vertexY[0]), -100, accuracy: 2)
		XCTAssertEqual(Double(abs(m.vertexX[0])), 100, accuracy: 2)
	}

	// MARK: shadow model (rt4 ShadowModelList.method1043)

	func testShadowDiscShapeAndTerrain() throws {
		let s = try store()
		let list = ShadowModelList()
		let body = SoftwareModel()
		body.vertexCount = 2
		body.vertexX = [-30, 30]; body.vertexY = [-100, 0]; body.vertexZ = [-20, 20]
		let flat = list.shadow(store: s, modifier1: 160, stretches: false, seq: nil, xFine: 3000, colour2: 0, zFine: 3000, colour1: 0,
		                       size: 1, body: body, orientation: 0, frame: 0, groundY: 0, modifier2: 240) { _, _ in 0 }
		XCTAssertEqual(flat.vertexCount, 9 * 3 + 1)
		XCTAssertEqual(flat.triangleCount, 9 * 5)
		XCTAssertTrue(flat.vertexY.allSatisfy { $0 == 0 })
		flat.ensureBounds()
		XCTAssertEqual(flat.minX, -30, accuracy: 2, "cut to the body's footprint")
		XCTAssertEqual(flat.maxZ, 20, accuracy: 2)
		let hill = list.shadow(store: s, modifier1: 160, stretches: false, seq: nil, xFine: 3000, colour2: 0, zFine: 3000, colour1: 0,
		                       size: 1, body: body, orientation: 0, frame: 0, groundY: 0, modifier2: 240) { x, _ in x / 100 }
		XCTAssertFalse(hill.vertexY.allSatisfy { $0 == 0 }, "laid on a sloping ground")
		XCTAssertTrue(flat !== hill)
		XCTAssertEqual(list.shadow(store: s, modifier1: 160, stretches: false, seq: nil, xFine: 3000, colour2: 0, zFine: 3000, colour1: 0,
		                           size: 3, body: body, orientation: 0, frame: 0, groundY: 0, modifier2: 240) { _, _ in 0 }.vertexCount, 15 * 3 + 1)
	}

	/// The replayed scene drawn with and without character shadows: the shadows darken the ground around the actors.
	func testShadowsAreDrawnUnderActors() throws {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		try replay(client)
		let world = client.world
		let (w, h) = (852, 393)
		world.ctx.characterShadows = false
		var off = Raster(width: w, height: h)
		XCTAssertTrue(world.draw(into: &off, rect: (0, 0, w, h)))
		world.ctx.characterShadows = true
		var on = Raster(width: w, height: h)
		XCTAssertTrue(world.draw(into: &on, rect: (0, 0, w, h)))
		var darker = 0, brighter = 0
		func lum(_ p: UInt32) -> Int { Int((p >> 16) & 0xFF) + Int((p >> 8) & 0xFF) + Int(p & 0xFF) }
		for (a, b) in zip(off.pixels, on.pixels) where a != b { if lum(b) < lum(a) { darker += 1 } else { brighter += 1 } }
		print("shadow pixels: darker \(darker), brighter \(brighter)")
		XCTAssertGreaterThan(darker, 100, "characters cast a shadow")
		XCTAssertGreaterThan(darker, brighter * 3)
		// The shadow is part of the render, not of the cached pose: the cached model is untouched.
		let me = try XCTUnwrap(world.selfActor)
		XCTAssertTrue(try XCTUnwrap(me.buildModel()) === me.buildModel())
		try save(off, "shadows-off")
		try save(on, "shadows-on")
		let out = "/mnt/project-files/2009scape-ios/screens/shadows"
		if ProcessInfo.processInfo.environment["SCAPE530_OUT"] == nil, FileManager.default.fileExists(atPath: "/mnt/project-files") {
			try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
			try? Data(PNG.encode(on)).write(to: URL(fileURLWithPath: out + "/shadows-on.png"))
			try? Data(PNG.encode(off)).write(to: URL(fileURLWithPath: out + "/shadows-off.png"))
		}
	}
}
