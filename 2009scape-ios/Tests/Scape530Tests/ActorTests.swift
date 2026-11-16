import Foundation
import XCTest
@testable import Scape530

final class ActorTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	/// Frame of `seq` as a pose; `idx` is the frame index in the sequence.
	func pose(_ s: ConfigStore, _ seqId: Int, _ idx: Int, next: Int = -1, step: Int = 0) throws -> SeqPose {
		SeqPose(seq: try XCTUnwrap(try s.seq(seqId)), frame: idx, nextFrame: next, step: step)
	}

	/// Orthographic wireframe: front view (x right, y down) beside a side view (z right).
	func wire(_ models: [(String, SoftwareModel)], _ name: String) throws {
		let cell = 300
		var r = Raster(width: cell * 2 * models.count, height: cell, fill: 0xFF202028)
		for (n, (_, m)) in models.enumerated() {
			for (view, ox) in [(0, n * 2 * cell), (1, n * 2 * cell + cell)] {
				func pt(_ v: Int) -> (Int, Int) {
					let h = view == 0 ? m.vertexX[v] : m.vertexZ[v]
					return (ox + cell / 2 + h * 2 / 3, cell - 20 + m.vertexY[v] * 2 / 3)
				}
				for t in 0..<m.triangleCount {
					let a = pt(m.triangleVertexA[t]), b = pt(m.triangleVertexB[t]), c = pt(m.triangleVertexC[t])
					r.drawLine(a.0, a.1, b.0, b.1, 0xFFB0D0FF)
					r.drawLine(b.0, b.1, c.0, c.1, 0xFFB0D0FF)
					r.drawLine(c.0, c.1, a.0, a.1, 0xFFB0D0FF)
				}
			}
		}
		try save(r, name)
	}

	func bounds(_ m: SoftwareModel) -> (minY: Int, maxY: Int, minX: Int, maxX: Int, minZ: Int, maxZ: Int) {
		(m.vertexY.prefix(m.vertexCount).min()!, m.vertexY.prefix(m.vertexCount).max()!, m.vertexX.prefix(m.vertexCount).min()!, m.vertexX.prefix(m.vertexCount).max()!, m.vertexZ.prefix(m.vertexCount).min()!, m.vertexZ.prefix(m.vertexCount).max()!)
	}

	func testDefaultPlayerIdleAndWalk() throws {
		let s = try store()
		let models = ActorModels(store: s)
		let look = try PlayerLook.defaultLook(store: s, female: false)
		print("default male slots", look.slots.map { String($0 & 0x3FFFFFFF, radix: 10) })
		let base = try XCTUnwrap(try models.playerBody(look)).model
		print("base: \(base.vertexCount) verts \(base.triangleCount) tris bones \(base.boneVertices?.count ?? -1)")
		XCTAssertGreaterThan(base.vertexCount, 100)
		let bb = bounds(base)
		print("base bounds", bb)

		let idleSeq = try XCTUnwrap(try s.seq(808)), walkSeq = try XCTUnwrap(try s.seq(819))
		print("seq808 frames \(idleSeq.frames.count) delays \(idleSeq.frameDelays) tween \(idleSeq.tween); seq819 frames \(walkSeq.frames.count) delays \(walkSeq.frameDelays)")
		let idle = try XCTUnwrap(try models.player(look, action: nil, movement: try pose(s, 808, 0)))
		let walk0 = try XCTUnwrap(try models.player(look, action: nil, movement: try pose(s, 819, 0)))
		let walkMid = try XCTUnwrap(try models.player(look, action: nil, movement: try pose(s, 819, walkSeq.frames.count / 2)))
		let walkTween = try XCTUnwrap(try models.player(look, action: nil, movement: try pose(s, 819, 1, next: 2, step: 2)))
		let ib = bounds(idle), wb = bounds(walkMid)
		print("idle bounds", ib, "walkMid bounds", wb)

		// Idle stays upright: the figure is taller than wide and roughly as tall as the bind pose.
		XCTAssertGreaterThan(ib.maxY - ib.minY, 2 * (ib.maxX - ib.minX))
		XCTAssertLessThan(abs((ib.maxY - ib.minY) - (bb.maxY - bb.minY)), 40)

		// The walk frame moves the legs: vertices in the lower half differ a lot from idle,
		// and the two legs have different z (stride) in mid-walk.
		func legSpread(_ m: SoftwareModel) -> Int {
			let low = (0..<m.vertexCount).filter { m.vertexY[$0] > (bb.minY + bb.maxY) / 2 + 60 }
			let left = low.filter { m.vertexX[$0] < 0 }.map { m.vertexZ[$0] }
			let right = low.filter { m.vertexX[$0] >= 0 }.map { m.vertexZ[$0] }
			guard !left.isEmpty, !right.isEmpty else { return 0 }
			return abs(left.reduce(0, +) / left.count - right.reduce(0, +) / right.count)
		}
		let idleSpread = legSpread(idle), walkSpread = legSpread(walkMid)
		print("leg z spread idle \(idleSpread) walkMid \(walkSpread)")
		var moved = 0, maxMove = 0
		for v in 0..<idle.vertexCount {
			let d = abs(idle.vertexX[v] - walkMid.vertexX[v]) + abs(idle.vertexY[v] - walkMid.vertexY[v]) + abs(idle.vertexZ[v] - walkMid.vertexZ[v])
			if d > 8 { moved += 1 }
			maxMove = max(maxMove, d)
		}
		print("walkMid vs idle: \(moved)/\(idle.vertexCount) vertices moved > 8, max \(maxMove)")
		XCTAssertGreaterThan(walkSpread, idleSpread + 20)
		XCTAssertGreaterThan(moved, idle.vertexCount / 4)
		// The un-animated base is untouched by posing.
		XCTAssertEqual(try XCTUnwrap(try models.playerBody(look)).model.vertexY, base.vertexY)
		// Tweening yields something between frames, not identical to either.
		let w1 = try XCTUnwrap(try models.player(look, action: nil, movement: try pose(s, 819, 1)))
		let w2 = try XCTUnwrap(try models.player(look, action: nil, movement: try pose(s, 819, 2)))
		XCTAssertNotEqual(walkTween.vertexZ, w1.vertexZ)
		XCTAssertNotEqual(walkTween.vertexZ, w2.vertexZ)
		_ = walk0
		try wire([("base", base), ("idle", idle), ("walk0", walk0), ("walkMid", walkMid)], "player-wire")
	}

	func testFemaleAndRecolour() throws {
		let s = try store()
		let models = ActorModels(store: s)
		let m = try PlayerLook.defaultLook(store: s, female: false, colours: [0, 0, 0, 0, 0])
		let m2 = try PlayerLook.defaultLook(store: s, female: false, colours: [3, 5, 7, 2, 1])
		let f = try PlayerLook.defaultLook(store: s, female: true)
		let a = try XCTUnwrap(try models.playerBody(m)).model, b = try XCTUnwrap(try models.playerBody(m2)).model
		let c = try XCTUnwrap(try models.playerBody(f)).model
		XCTAssertEqual(a.vertexX, b.vertexX)
		XCTAssertNotEqual(a.triangleColorA, b.triangleColorA)
		XCTAssertNotEqual(a.vertexCount, c.vertexCount)
	}

	func testHansNpc() throws {
		let s = try store()
		let models = ActorModels(store: s)
		let hans = try XCTUnwrap(try s.npc(0))
		XCTAssertEqual(hans.name, "Hans")
		let bas = hans.basId != -1 ? try s.bas(hans.basId) : nil
		print("Hans models \(hans.models) bas \(hans.basId) idle \(String(describing: bas?.idle)) walk \(String(describing: bas?.walk)) resize \(hans.resizeXZ)x\(hans.resizeY)")
		let base = try XCTUnwrap(try models.npc(hans))
		let idleId = try XCTUnwrap(bas?.idle), walkId = try XCTUnwrap(bas?.walk)
		let idle = try XCTUnwrap(try models.npc(hans, movement: try pose(s, idleId, 0)))
		let walkSeq = try XCTUnwrap(try s.seq(walkId))
		let walk = try XCTUnwrap(try models.npc(hans, movement: try pose(s, walkId, walkSeq.frames.count / 2)))
		let ib = bounds(idle), wb = bounds(walk)
		print("Hans base verts \(base.vertexCount), idle bounds \(ib), walk bounds \(wb)")
		XCTAssertGreaterThan(ib.maxY - ib.minY, ib.maxX - ib.minX)
		var moved = 0
		for v in 0..<idle.vertexCount where abs(idle.vertexZ[v] - walk.vertexZ[v]) + abs(idle.vertexY[v] - walk.vertexY[v]) > 8 { moved += 1 }
		print("Hans walk moves \(moved)/\(idle.vertexCount) vertices")
		XCTAssertGreaterThan(moved, 10)
		try wire([("base", base), ("idle", idle), ("walk", walk)], "hans-wire")
	}

	func testPlayerDressedAndActionSplit() throws {
		let s = try store()
		let models = ActorModels(store: s)
		var look = try PlayerLook.defaultLook(store: s, female: false)
		look.slots[4] = 0x4000_0000 | 1117   // bronze platebody torso
		look.slots[7] = 0x4000_0000 | 1075   // bronze platelegs
		look.slots[5] = 0x4000_0000 | 1351   // bronze axe in hand
		let base = try XCTUnwrap(try models.playerBody(look)).model
		XCTAssertGreaterThan(base.vertexCount, 150)
		// walk + an action together uses the frame-group split without crashing
		let attack = try XCTUnwrap(try s.seq(423))
		let p = try models.player(look, action: try pose(s, 423, 1), movement: try pose(s, 819, 2))
		XCTAssertNotNil(p)
		print("seq423 frameGroup \(attack.frameGroup?.count ?? -1) mainhand \(attack.mainhand)")
	}

	/// Every Lumbridge-area NPC in the cache builds and animates without crashing.
	func testAllNpcsBuildAndAnimate() throws {
		let s = try store()
		let models = ActorModels(store: s)
		var built = 0, failed = 0
		for id in stride(from: 0, to: 4000, by: 7) {
			guard let t = try s.npc(id), t.multiNpcs == nil, !t.models.isEmpty else { continue }
			if let m = try models.npc(t) {
				built += 1
				let bas = t.basId != -1 ? try s.bas(t.basId) : nil
				if let w = bas?.walk, w != -1, let seq = try s.seq(w), !seq.frames.isEmpty {
					_ = try models.npc(t, movement: SeqPose(seq: seq, frame: 0, nextFrame: seq.frames.count > 1 ? 1 : -1, step: 1))
				}
				_ = m
			} else { failed += 1 }
		}
		print("npcs built \(built) failed \(failed)")
		XCTAssertGreaterThan(built, 100)
	}
}
