import Foundation
import XCTest
@testable import Scape530

/// IF1 scripts (rt4 `Cs1ScriptRunner.run` / `interpolate` / `isTrue`) and interface scrolling.
final class ScrollCs1Tests: XCTestCase {
	/// A `Cs1Source` backed by dictionaries.
	final class Fake: Cs1Source {
		var boosted: [Int: Int] = [:], base: [Int: Int] = [:], xp: [Int: Int] = [:]
		var items: [Int: [Int: Int]] = [:]
		var varps: [Int: Int] = [:], varbits: [Int: Int] = [:]
		var combat = 3, energy = 100, weight = 0, x = 3200, z = 3200
		func cs1BoostedLevel(_ s: Int) -> Int { boosted[s] ?? base[s] ?? 1 }
		func cs1BaseLevel(_ s: Int) -> Int { base[s] ?? 1 }
		func cs1Experience(_ s: Int) -> Int { xp[s] ?? 0 }
		func cs1ItemCount(component: Int, obj: Int) -> Int { items[component]?[obj] ?? 0 }
		func cs1Varp(_ id: Int) -> Int { varps[id] ?? 0 }
		func cs1Varbit(_ id: Int) -> Int { varbits[id] ?? 0 }
		func cs1CombatLevel() -> Int { combat }
		func cs1RunEnergy() -> Int { energy }
		func cs1Weight() -> Int { weight }
		func cs1TileX() -> Int { x }
		func cs1TileZ() -> Int { z }
		func cs1LastLogAddress() -> String { "1.2.3.4" }
	}

	func comp(scripts: [[Int]], comparisons: [(Int, Int)] = []) -> Component {
		var c = Component(parentId: 1, type: 4, index: 0)
		c.if3 = false
		c.cs1Scripts = scripts
		c.cs1Comparisons = comparisons.map { (opcode: $0.0, operand: $0.1) }
		return c
	}

	// MARK: CS1

	func testRunOpcodesAndAccumulator() {
		let f = Fake()
		f.boosted[3] = 42; f.base[3] = 50; f.xp[3] = 1234; f.varps[7] = 93750; f.varps[9] = 0b100
		f.varbits[5] = 6; f.combat = 77; f.energy = 88; f.weight = 12
		f.items[(5 << 16) + 2] = [995: 30]
		func run(_ s: [Int]) -> Int { Cs1.run(0, comp(scripts: [s]), f) }
		XCTAssertEqual(run([1, 3, 0]), 42)            // boosted level
		XCTAssertEqual(run([2, 3, 0]), 50)            // base level
		XCTAssertEqual(run([3, 3, 0]), 1234)          // experience
		XCTAssertEqual(run([4, 5, 2, 995, 0]), 30)    // item count in component 5:2
		XCTAssertEqual(run([4, 5, 2, 995, 20, 5, 0]), 35)
		XCTAssertEqual(run([10, 5, 2, 995, 0]), 999_999_999) // item present
		XCTAssertEqual(run([10, 5, 2, 4151, 0]), 0)
		XCTAssertEqual(run([5, 7, 0]), 93750)         // varp
		XCTAssertEqual(run([7, 7, 0]), 200)           // varp * 100 / 46875
		XCTAssertEqual(run([13, 9, 2, 0]), 1)         // varp bit 2
		XCTAssertEqual(run([13, 9, 1, 0]), 0)
		XCTAssertEqual(run([14, 5, 0]), 6)            // varbit
		XCTAssertEqual(run([8, 0]), 77)
		XCTAssertEqual(run([11, 0]), 88)
		XCTAssertEqual(run([12, 0]), 12)
		XCTAssertEqual(run([18, 0]), 3200)
		XCTAssertEqual(run([9, 0]), 24 * 1 + 49)      // 24 enabled skills at level 1, skill 3 is 50
		// Operators apply to the next value: 20 + 5 - 2 then * 3, then / 3.
		XCTAssertEqual(run([20, 20, 20, 5, 15, 20, 2, 0]), 23)
		XCTAssertEqual(run([20, 20, 17, 20, 3, 0]), 60)
		XCTAssertEqual(run([20, 60, 16, 20, 3, 0]), 20)
		XCTAssertEqual(run([20, 60, 16, 20, 0, 0]), 60) // division by zero leaves it
		XCTAssertEqual(run([6, 3, 0]), InterfaceScriptHost.xpLevelLookup[49]) // xp for level 51
	}

	func testRunFailureCodes() {
		let f = Fake()
		XCTAssertEqual(Cs1.run(3, comp(scripts: [[20, 1, 0]]), f), -2)  // no such script
		XCTAssertEqual(Cs1.run(0, comp(scripts: [[20, 1]]), f), -1)     // runs off the end
		XCTAssertEqual(Cs1.run(0, comp(scripts: [[1, 99, 0]]), f), -1)  // skill out of range
	}

	func testInterpolate() {
		let f = Fake()
		f.base[0] = 10
		let c = comp(scripts: [[2, 0, 0], [20, 7, 0], [20, 9, 0]])
		XCTAssertEqual(Cs1.interpolate(c, "Attack: %1/%2 and %1", f), "Attack: 10/7 and 10")
		XCTAssertEqual(Cs1.interpolate(c, "plain", f), "plain")
		XCTAssertEqual(Cs1.interpolate(c, "ip %dns", f), "ip 1.2.3.4")
		// A script that does not exist yields -2, like rt4's `run`.
		XCTAssertEqual(Cs1.interpolate(c, "%4", f), "-2")
		XCTAssertEqual(Cs1.interpolate(c, "100%", f), "100%")
	}

	func testIsTrue() {
		let f = Fake()
		f.base[0] = 10
		let scripts = [[2, 0, 0]]
		func check(_ op: Int, _ operand: Int) -> Bool { Cs1.isTrue(comp(scripts: scripts, comparisons: [(op, operand)]), f) }
		XCTAssertTrue(check(1, 10)); XCTAssertFalse(check(1, 11))
		XCTAssertTrue(check(2, 11)); XCTAssertFalse(check(2, 10))   // value < operand
		XCTAssertTrue(check(3, 9)); XCTAssertFalse(check(3, 10))    // value > operand
		XCTAssertTrue(check(4, 9)); XCTAssertFalse(check(4, 10))    // value != operand
		XCTAssertFalse(Cs1.isTrue(comp(scripts: []), f))            // no comparisons: never active
		// All comparisons must hold.
		let two = comp(scripts: [[2, 0, 0], [20, 1, 0]], comparisons: [(1, 10), (1, 2)])
		XCTAssertFalse(Cs1.isTrue(two, f))
	}

	func testRendererShowsActiveText() throws {
		let host = InterfaceScriptHost(store: ConfigStore(source: { _, _ in nil }))
		let c = comp(scripts: [[5, 1, 0]], comparisons: [(1, 1)])
		XCTAssertFalse(host.renderer.isActive(c))
		host.game.varps[1] = 1
		XCTAssertTrue(host.renderer.isActive(c))
		XCTAssertEqual(host.cs1Varp(1), 1)
	}

	// MARK: scrolling

	/// An IF1 layer (100x80, 400 of content) at (20, 30) with a scrollbar column, plus an if3 layer (100x80, 300 of
	/// content) at (200, 30) with an `onScroll` hook.
	func scrollRig() -> (host: InterfaceScriptHost, if1: ComponentRef, if3: ComponentRef) {
		let host = InterfaceScriptHost(store: ConfigStore(source: { _, _ in nil }))
		let id1 = (900 << 16) | 1, id3 = (900 << 16) | 2
		var a = Component(parentId: id1, type: 0, index: 0)
		a.if3 = false; a.childIndex = -1; a.parent = -1
		a.baseWidth = 100; a.baseHeight = 80; a.scrollHeight = 400
		var b = Component(parentId: id3, type: 0, index: 0)
		b.childIndex = -1; b.parent = -1
		b.baseWidth = 100; b.baseHeight = 80; b.scrollHeight = 300
		b.hooks["onScroll"] = [.int(7003)]
		host.game.interfaces.overrides[id1] = a
		host.game.interfaces.overrides[id3] = b
		host.renderer.drawn = [(a, 20, 30, 100, 80), (b, 200, 30, 100, 80)]
		host.renderer.origins[a.ref] = (20, 30)
		host.renderer.origins[b.ref] = (200, 30)
		return (host, a.ref, b.ref)
	}

	func testScrollbarThumbGeometry() {
		// rt4 method1624: thumb = h * (h - 32) / max, at least 8; position scales over the free travel.
		let t = InterfaceRenderer.scrollbarThumb(height: 80, scrollY: 160, scrollMax: 400)
		XCTAssertEqual(t.size, 80 * 48 / 400)
		XCTAssertEqual(t.top, 160 * (80 - t.size - 32) / 320)
		XCTAssertEqual(InterfaceRenderer.scrollbarThumb(height: 80, scrollY: 0, scrollMax: 4000).size, 8)
	}

	func testWheelScrollsIf1AndClamps() {
		let rig = scrollRig()
		let host = rig.host
		XCTAssertTrue(host.isOverScrollable(x: 50, y: 50))
		XCTAssertTrue(host.isOverScrollable(x: 125, y: 50), "the scrollbar column belongs to the layer")
		XCTAssertFalse(host.isOverScrollable(x: 500, y: 50))
		XCTAssertTrue(host.scrollWheel(x: 50, y: 50, delta: 1))
		XCTAssertEqual(host.component(rig.if1)?.scrollY, 45)
		host.scrollWheel(x: 125, y: 50, delta: 2)
		XCTAssertEqual(host.component(rig.if1)?.scrollY, 135)
		host.scrollWheel(x: 50, y: 50, delta: 100)
		XCTAssertEqual(host.component(rig.if1)?.scrollY, 320, "clamped to extent - height")
		host.scrollWheel(x: 50, y: 50, delta: -100)
		XCTAssertEqual(host.component(rig.if1)?.scrollY, 0)
	}

	func testWheelFiresOnScrollWithDelta() {
		let rig = scrollRig()
		XCTAssertTrue(rig.host.scrollWheel(x: 250, y: 50, delta: -3))
		// The hook ran (script 7003 does not exist in the empty store, which is reported).
		XCTAssertTrue(rig.host.errors.contains { $0.hasPrefix("script 7003") }, "\(rig.host.errors)")
		XCTAssertEqual(rig.host.component(rig.if3)?.scrollY, 0, "if3 layers are moved by their script, not by the client")
	}

	func testDragScrollFollowsFinger() {
		let rig = scrollRig()
		let host = rig.host
		// Finger moves up 30 px: content moves up with it.
		XCTAssertTrue(host.scrollDrag(x: 250, y: 50, dy: -30))
		XCTAssertEqual(host.component(rig.if3)?.scrollY, 30)
		XCTAssertTrue(host.scrollDrag(x: 250, y: 50, dy: -7))
		XCTAssertEqual(host.component(rig.if3)?.scrollY, 37)
		XCTAssertTrue(host.scrollDrag(x: 250, y: 50, dy: 10))
		XCTAssertEqual(host.component(rig.if3)?.scrollY, 27)
		host.scrollDrag(x: 250, y: 50, dy: -5000)
		XCTAssertEqual(host.component(rig.if3)?.scrollY, 220, "clamped to extent - height")
		host.scrollDrag(x: 250, y: 50, dy: 5000)
		XCTAssertEqual(host.component(rig.if3)?.scrollY, 0)
		XCTAssertFalse(host.scrollDrag(x: 600, y: 400, dy: 5))
		// IF1 content follows the finger too; the thumb drag maps onto the whole extent.
		host.scrollDrag(x: 50, y: 50, dy: -40)
		XCTAssertEqual(host.component(rig.if1)?.scrollY, 40)
		host.scrollDrag(x: 125, y: 60, dy: 10)
		let thumb = InterfaceRenderer.scrollbarThumb(height: 80, scrollY: 40, scrollMax: 400).size
		XCTAssertEqual(host.component(rig.if1)?.scrollY, 40 + 10 * 320 / (80 - thumb - 32))
	}

	func testDragScrollOverridesStaleStateScroll() {
		let rig = scrollRig()
		rig.host.game.interfaces.scroll[rig.if1.id] = 100 // set by `InterfaceState.apply` alone
		rig.host.scrollDrag(x: 50, y: 50, dy: -10)
		XCTAssertEqual(rig.host.component(rig.if1)?.scrollY, 110)
		XCTAssertNil(rig.host.game.interfaces.scroll[rig.if1.id])
	}

	func testScrollbarPress() {
		let rig = scrollRig()
		let host = rig.host
		XCTAssertTrue(host.pressScrollbar(x: 125, y: 100)) // down arrow
		XCTAssertEqual(host.component(rig.if1)?.scrollY, 4)
		XCTAssertTrue(host.pressScrollbar(x: 125, y: 35)) // up arrow
		XCTAssertEqual(host.component(rig.if1)?.scrollY, 0)
		XCTAssertTrue(host.pressScrollbar(x: 125, y: 70)) // track
		XCTAssertGreaterThan(host.component(rig.if1)?.scrollY ?? 0, 0)
		XCTAssertFalse(host.pressScrollbar(x: 50, y: 50))
	}

	func testClientApiNeedsGame() throws {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		XCTAssertFalse(client.isOverScrollable(x: 10, y: 10))
		XCTAssertFalse(client.scrollInterface(x: 10, y: 10, delta: 1))
		XCTAssertFalse(client.dragScroll(x: 10, y: 10, dy: 5))
	}

	// MARK: cache

	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func testRealInterfacesScroll() throws {
		let s = try store()
		var found: [String] = []
		var scrolledIf1 = false
		for iface in [274, 762, 275, 12, 763, 11] {
			let host = InterfaceScriptHost(store: s)
			host.game.interfaces.top = iface
			host.runOnLoad(interface: iface)
			var r = Raster(width: 765, height: 503)
			try host.renderer.render(iface, state: host.game.interfaces, into: &r)
			let layers = host.renderer.drawn.filter { $0.component.type == 0 && $0.component.scrollMaxV > $0.h }
			found.append("\(iface): \(host.renderer.drawn.count) drawn, \(layers.count) scrollable, if1=\(layers.filter { !$0.component.if3 }.count)")
			guard let l = layers.first else { continue }
			let (x, y) = (l.x + l.w / 2, l.y + min(l.h / 2, 20))
			XCTAssertTrue(host.isOverScrollable(x: x, y: y), "\(iface)")
			let before = host.scrollY(of: host.component(l.component.ref)!)
			XCTAssertTrue(host.scrollDrag(x: x, y: y, dy: -25), "\(iface)")
			let after = host.scrollY(of: host.component(l.component.ref)!)
			XCTAssertEqual(after, min(before + 25, l.component.scrollMaxV - l.h), "\(iface)")
			host.scrollDrag(x: x, y: y, dy: -1_000_000)
			XCTAssertEqual(host.scrollY(of: host.component(l.component.ref)!), l.component.scrollMaxV - l.h, "\(iface) clamps at the end")
			host.scrollDrag(x: x, y: y, dy: 1_000_000)
			XCTAssertEqual(host.scrollY(of: host.component(l.component.ref)!), 0, "\(iface) clamps at the start")
			// The scrolled layer renders without error.
			try host.renderer.render(iface, state: host.game.interfaces, into: &r)
			if !l.component.if3 { scrolledIf1 = true }
		}
		print("SCROLL-SURVEY", found)
		XCTAssertFalse(found.allSatisfy { $0.contains(" 0 scrollable") }, "\(found)")
		_ = scrolledIf1
	}
}
