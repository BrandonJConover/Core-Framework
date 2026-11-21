import Foundation
import XCTest
@testable import Scape530

/// CS2 client actions ported from rt4 `ScriptRunner`: appearance edits, audio, item search, chat filter and
/// report packets, inventory param totals, the viewport limits.
final class CS2ClientOpsTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	/// The opcode byte is returned with the ISAAC key removed.
	func encode(_ m: ClientMessage) -> [UInt8] {
		var a = IsaacRandom(seed: [1, 2, 3, 4])
		var b = IsaacRandom(seed: [1, 2, 3, 4])
		let bytes = m.encode(&a)
		let key = b.nextKey()
		return [bytes[0] &- UInt8(truncatingIfNeeded: key)] + bytes.dropFirst()
	}

	func run(_ host: InterfaceScriptHost, _ op: Int, _ ints: [Int32] = [], _ strings: [String] = []) -> HostResult {
		host.perform(HostOps.table[op]!, ints: ints, strings: strings)
	}

	// MARK: packets (no cache)

	func testChatFilterBugReportAndTwoStringPackets() {
		// rt4 5001: p1isaac(157), p1 x3.
		XCTAssertEqual(encode(.chatFilterSettings(public: 1, private: 2, trade: 3)), [157, 1, 2, 3])
		// rt4 5002: p1isaac(99), p8(name37), p1(category - 1), p1(flag).
		XCTAssertEqual(encode(.bugReport(name37: 0x0102_0304_0506_0708, category: 3, flag: 1)), [99, 1, 2, 3, 4, 5, 6, 7, 8, 2, 1])
		// rt4 5400: p1isaac(117), size = (len + 1) * 2 + 1, jstr, jstr, p1.
		XCTAssertEqual(encode(.twoStrings("ab", "c", 9)), [117, 6, 0x61, 0x62, 0, 0x63, 0, 9])
	}

	// MARK: appearance (no cache)

	func testIdentikitColourAndGenderEdits() {
		var slots = [Int](repeating: 0, count: 12)
		slots[8] = Int(Int32.min) | 5 // hair (feature 0)
		var look = PlayerLook(female: false, slots: slots, colours: [0, 0, 0, 0, 0], basId: -1)
		look.setIdentikit(feature: 0, kit: 9) { _ in true }
		XCTAssertEqual(look.slots[8], Int(Int32.min) | 9)
		// A kit that does not exist, and a body part that is not worn, change nothing.
		look.setIdentikit(feature: 0, kit: 99) { $0 != 99 }
		XCTAssertEqual(look.slots[8], Int(Int32.min) | 9)
		look.setIdentikit(feature: 1, kit: 4) { _ in true }
		XCTAssertEqual(look.slots[11], 0)
		// Female feature ids map onto the same slots as the male ones (7 is the female hair).
		look.setIdentikit(feature: 7, kit: 12) { _ in true }
		XCTAssertEqual(look.slots[8], Int(Int32.min) | 12)
		// An unknown feature does nothing.
		look.setIdentikit(feature: 40, kit: 1) { _ in true }
		look.setColour(slot: 2, colour: 7)
		look.setColour(slot: 9, colour: 7)
		XCTAssertEqual(look.colours, [0, 0, 7, 0, 0])
		look.setGender(female: true)
		XCTAssertTrue(look.female)
	}

	func testViewportLimitsClampLikeRt4() {
		var v = ViewportLimits()
		v.set6200(0, -3)
		XCTAssertEqual([v.heightZoomLow, v.heightZoomHigh], [256, 205])
		v.set6201(100, 0)
		XCTAssertEqual([v.cameraZoomLow, v.cameraZoomHigh], [100, 320])
		v.set6202(50, 10, 40, 5)
		XCTAssertEqual([v.minZoom, v.maxZoom, v.minAspect, v.maxAspect], [50, 50, 40, 40])
		v.set6202(0, 0, 0, 0)
		XCTAssertEqual([v.minZoom, v.maxZoom, v.minAspect, v.maxAspect], [1, 32767, 1, 32767])
	}

	// MARK: host ops

	func testHostOpsRouteAppearanceAudioAndActions() throws {
		let host = InterfaceScriptHost(store: try store())
		var edits: [AppearanceEdit] = [], sounds: [[Int]] = [], songs: [Int] = [], jingles: [[Int]] = []
		var anims: [[Int]] = [], clicks: [String] = [], sent: [ClientMessage] = []
		host.onAppearanceEdit = { edits.append($0) }
		host.selfFemale = { true }
		host.onPlaySoundEffect = { sounds.append([$0, $1, $2]) }
		host.onPlaySong = { songs.append($0) }
		host.onPlayJingle = { jingles.append([$0, $1]) }
		host.onAnimateSelf = { anims.append([$0, $1]) }
		host.onClickPlayerOption = { clicks.append("\($0):\($1)") }
		host.send = { sent.append($0) }
		_ = run(host, 403, [0, 9]); _ = run(host, 404, [2, 5]); _ = run(host, 410, [1])
		XCTAssertEqual(edits, [.identikit(feature: 0, kit: 9), .colour(slot: 2, colour: 5), .gender(female: true)])
		XCTAssertEqual(run(host, 3327).ints, [1])
		_ = run(host, 3200, [4000, 2, 10]); _ = run(host, 3201, [35]); _ = run(host, 3202, [77, 200])
		XCTAssertEqual(sounds, [[4000, 2, 10]])
		XCTAssertEqual(songs, [35])
		XCTAssertEqual(jingles, [[77, 200]])
		_ = run(host, 3101, [808, 3]); _ = run(host, 3107, [4], ["Bob"])
		XCTAssertEqual(anims, [[808, 3]])
		XCTAssertEqual(clicks, ["4:Bob"])
		_ = run(host, 5001, [1, 2, 3])
		XCTAssertEqual(host.game.chatFilters.public, 1)
		XCTAssertEqual(host.game.chatFilters.trade, 3)
		_ = run(host, 5002, [2, 0], ["a"]); _ = run(host, 5400, [7], ["x", "y"])
		XCTAssertEqual(sent.map { String(describing: $0) }, [
			String(describing: ClientMessage.chatFilterSettings(public: 1, private: 2, trade: 3)),
			String(describing: ClientMessage.bugReport(name37: Base37.encode("a"), category: 2, flag: 0)),
			String(describing: ClientMessage.twoStrings("x", "y", 7)),
		])
		_ = run(host, 5427, [14, 15])
		XCTAssertEqual(host.menuCursors.use, 14)
		XCTAssertEqual(host.menuCursors.examine, 15)
		_ = run(host, 6202, [10, 20, 5, 6])
		XCTAssertEqual(host.viewportLimits.maxZoom, 20)
		XCTAssertEqual(run(host, 3629).ints, [0])
	}

	func testDaysSinceLaunchOfAMonthStart() throws {
		let host = InterfaceScriptHost(store: try store())
		// Arguments are day, month (0-based), year.
		let jan2002 = run(host, 6302, [1, 0, 2002]).ints[0]
		let jan2003 = run(host, 6302, [1, 0, 2003]).ints[0]
		XCTAssertEqual(jan2003 - jan2002, 365)
		XCTAssertEqual(jan2002, 11688 - 11745, "rt4: epoch days of 1 Jan 2002 less 11745")
	}

	func testObjSearchFiltersAndSorts() throws {
		let host = InterfaceScriptHost(store: try store())
		let count = Int(run(host, 4210, [0], ["dragon scimitar"]).ints[0])
		XCTAssertGreaterThan(count, 0)
		var ids: [Int] = []
		while true {
			let id = Int(run(host, 4211).ints[0])
			if id == -1 { break }
			ids.append(id)
		}
		XCTAssertEqual(ids.count, count)
		for id in ids {
			let t = try XCTUnwrap(try host.store.objResolved(id))
			XCTAssertTrue(t.name.lowercased().contains("dragon scimitar"), t.name)
			XCTAssertEqual(t.certtemplate, -1)
			XCTAssertEqual(t.lentTemplate, -1)
		}
		let names = try ids.map { try XCTUnwrap(try host.store.objResolved($0)).name }
		XCTAssertEqual(names, names.sorted { Cp1252.encode($0).lexicographicallyPrecedes(Cp1252.encode($1)) })
		// Reset rewinds the cursor.
		_ = run(host, 4212)
		XCTAssertEqual(Int(run(host, 4211).ints[0]), ids[0])
		// Grand Exchange mode only lists tradeable items.
		let ge = Int(run(host, 4210, [1], ["dragon scimitar"]).ints[0])
		XCTAssertLessThanOrEqual(ge, count)
		while Int(run(host, 4211).ints[0]) != -1 {}
		// A broad search overflows rt4's 250 result limit: -1 and no results.
		XCTAssertEqual(run(host, 4210, [0], ["a"]).ints, [-1])
		XCTAssertEqual(run(host, 4211).ints, [-1])
	}

	func testInvParamTotalSumsParamsWithAndWithoutStacks() throws {
		let host = InterfaceScriptHost(store: try store())
		// Find two distinct objects sharing an int param.
		var byParam: [Int: [(id: Int, value: Int32)]] = [:]
		for id in 0..<host.objCapacity {
			guard let t = try host.store.objResolved(id) else { continue }
			for (k, v) in t.params { if case let .int(n) = v, n != 0 { byParam[k, default: []].append((id, n)) } }
			if byParam.values.contains(where: { $0.count >= 2 }) { break }
		}
		let (param, items) = try XCTUnwrap(byParam.first { $0.value.count >= 2 })
		let a = items[0], b = items[1]
		host.game.inventories[777] = [
			0: ServerMessage.InvItem(id: a.id, count: 3),
			1: ServerMessage.InvItem(id: b.id, count: 2),
			2: ServerMessage.InvItem(id: 1, count: 1_000), // some item without the param adds nothing unless it has it
		]
		let extra = try XCTUnwrap(try host.store.objResolved(1)).params[param]
		var plain = a.value + b.value, stacked = a.value * 3 + b.value * 2
		if case let .int(n)? = extra { plain += n; stacked += n * 1_000 }
		XCTAssertEqual(run(host, 3331, [777, Int32(param)]).ints, [plain])
		XCTAssertEqual(run(host, 3332, [777, Int32(param)]).ints, [stacked])
		XCTAssertEqual(run(host, 3332, [12345, Int32(param)]).ints, [0], "an unknown container totals 0")
	}

	func testObjRecolourPaletteFeedsRecolourPaletteItems() throws {
		let host = InterfaceScriptHost(store: try store())
		var flushed = 0
		host.onObjRecolour = { flushed += 1 }
		_ = run(host, 5401, [5, 0x00FF00])
		XCTAssertEqual(flushed, 1)
		XCTAssertEqual(host.store.recolourPalette(5), SceneColor.rgbToHsl(0x00FF00))
		XCTAssertEqual(host.store.recolourPalette(6), 0)
	}
}
