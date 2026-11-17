import Foundation
import XCTest
@testable import Scape530

/// Render-side interpolation between client cycles (`WorldView+Interpolation`): actors and the camera are drawn
/// part-way between their previous and latest cycle state, game state is untouched, and the faithful mode
/// (off) or a full cycle (alpha 1) draws exactly what rt4 draws.
final class InterpolationTests: XCTestCase {
	func client() throws -> GameClient {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		let session = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/resizable-session", withExtension: "bin"))
		return try RenderBench.makeClient(cache: dir, session: session.path)
	}

	func testBlendsMovingActorAndRestoresIt() throws {
		let world = try client().world
		let me = try XCTUnwrap(world.selfActor)
		world.smoothMotion = true
		let (x, z, yaw) = (me.xFine, me.zFine, me.yaw)
		me.snapshotForInterpolation()
		me.xFine += 12; me.zFine -= 8; me.yaw = (yaw + 20) & 0x7FF
		world.renderAlpha = 0.5
		world.beginInterpolation()
		XCTAssertEqual(me.xFine, x + 6)
		XCTAssertEqual(me.zFine, z - 4)
		XCTAssertEqual(me.yaw, (yaw + 10) & 0x7FF)
		world.endInterpolation()
		XCTAssertEqual(me.xFine, x + 12)
		XCTAssertEqual(me.zFine, z - 8)
		XCTAssertEqual(me.yaw, (yaw + 20) & 0x7FF)
	}

	func testTurnsTheShortWayRoundTheCircle() throws {
		let world = try client().world
		let me = try XCTUnwrap(world.selfActor)
		world.smoothMotion = true
		me.yaw = 2040
		me.snapshotForInterpolation()
		me.yaw = 8
		world.renderAlpha = 0.5
		world.beginInterpolation()
		XCTAssertEqual(me.yaw, 0)
		world.endInterpolation()
		XCTAssertEqual(me.yaw, 8)
	}

	func testJumpsAreNotInterpolated() throws {
		let world = try client().world
		let me = try XCTUnwrap(world.selfActor)
		world.smoothMotion = true
		me.snapshotForInterpolation()
		let x = me.xFine
		me.xFine += 128 // teleport / region shift sized
		world.renderAlpha = 0.25
		world.beginInterpolation()
		XCTAssertEqual(me.xFine, x + 128)
		world.endInterpolation()
	}

	func testFaithfulModeDoesNothing() throws {
		let world = try client().world
		let me = try XCTUnwrap(world.selfActor)
		world.smoothMotion = false
		me.snapshotForInterpolation()
		let x = me.xFine
		me.xFine += 12
		world.renderAlpha = 0.5
		world.beginInterpolation()
		XCTAssertEqual(me.xFine, x + 12)
		world.endInterpolation()
		XCTAssertEqual(me.xFine, x + 12)
	}

	func testCycleSnapshotsCameraAndActors() throws {
		let c = try client()
		let world = c.world
		let me = try XCTUnwrap(world.selfActor)
		// Walk the player two tiles east over a few cycles and check the camera trails but follows.
		me.queueSize = 1
		me.queueX[0] = me.queueX[0] + 2
		me.queueZ[0] = me.queueZ[0]
		var lastX = me.xFine, lastCam = world.camera.followX
		for _ in 0..<10 {
			world.cycle(varps: c.state.varps)
			XCTAssertEqual(me.prevXFine, lastX)
			XCTAssertEqual(world.camera.prevFollowX, lastCam)
			lastX = me.xFine
			lastCam = world.camera.followX
		}
	}

	func testDrawLeavesStateAlone() throws {
		let c = try client()
		let world = c.world
		let me = try XCTUnwrap(world.selfActor)
		world.smoothMotion = true
		me.snapshotForInterpolation()
		me.xFine += 10
		world.camera.followX += 3
		world.renderAlpha = 0.5
		let (x, z, cam) = (me.xFine, me.zFine, world.camera.followX)
		var r = Raster(width: 765, height: 503)
		XCTAssertTrue(world.draw(into: &r, rect: (0, 0, 765, 503)))
		XCTAssertEqual(me.xFine, x)
		XCTAssertEqual(me.zFine, z)
		XCTAssertEqual(world.camera.followX, cam)
	}

	func testFullCycleAlphaDrawsTheFaithfulPicture() throws {
		let c = try client()
		let world = c.world
		let me = try XCTUnwrap(world.selfActor)
		me.snapshotForInterpolation()
		me.xFine += 10
		var off = Raster(width: 765, height: 503), on = off
		world.smoothMotion = false
		XCTAssertTrue(world.draw(into: &off, rect: (0, 0, 765, 503)))
		world.smoothMotion = true
		world.renderAlpha = 1
		XCTAssertTrue(world.draw(into: &on, rect: (0, 0, 765, 503)))
		XCTAssertEqual(off.pixels, on.pixels)
		// ...and a part-way frame differs, because the player and camera sit elsewhere.
		var mid = off
		world.renderAlpha = 0.4
		XCTAssertTrue(world.draw(into: &mid, rect: (0, 0, 765, 503)))
		XCTAssertNotEqual(off.pixels, mid.pixels)
	}

	func testFrameAtDrivesAlphaFromTheClock() throws {
		let c = try client()
		c.smoothMotion = true
		let t0 = Date()
		_ = try c.frame(width: 765, height: 503, at: t0)
		XCTAssertEqual(c.world.renderAlpha, 0, accuracy: 0.001, "the first frame runs a cycle and starts the clock")
		_ = try c.frame(width: 765, height: 503, at: t0.addingTimeInterval(0.005))
		XCTAssertEqual(c.world.renderAlpha, 0.25, accuracy: 0.01)
		_ = try c.frame(width: 765, height: 503, at: t0.addingTimeInterval(0.015))
		XCTAssertEqual(c.world.renderAlpha, 0.75, accuracy: 0.01)
		_ = try c.frame(width: 765, height: 503, at: t0.addingTimeInterval(0.025))
		XCTAssertEqual(c.world.renderAlpha, 0.25, accuracy: 0.01, "a cycle ran at +20 ms")
	}
}
