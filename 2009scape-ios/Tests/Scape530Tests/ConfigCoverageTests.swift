import Foundation
import XCTest
@testable import Scape530

/// Config types beyond obj/npc/loc (param, struct, inv, varp, light, cursor, msi), the CS2 param
/// opcodes built on them, and the client settings / varp client codes (rt4 `Preferences`, `VarpDomain`).
final class ConfigCoverageTests: XCTestCase {
	static var shared: ConfigStore?

	func store() throws -> ConfigStore {
		if let s = Self.shared { return s }
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		let s = ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
		Self.shared = s
		return s
	}

	/// Decodes every file of one group of the configs archive (terminator must land on the last byte).
	func decodeAll<T: ConfigType>(_ t: T.Type, group: Int) throws -> Int {
		let s = try store()
		var failures: [String] = []
		var unknown: [Int] = []
		let files = try s.files(archive: ConfigStore.Archive.configs, group: group)
		for (f, data) in files {
			do { _ = try T.decode(id: f, data) { unknown.append($0) } } catch { failures.append("\(T.self) \(f): \(error)") }
		}
		XCTAssertEqual(failures, [])
		XCTAssertEqual(unknown, [], "\(T.self) has opcodes rt4 does not know")
		return files.count
	}

	/// Decodes every file of every group of a (non-config) archive.
	func decodeEverything<T: ConfigType>(_ t: T.Type, archive: Int, group: Int) throws -> Int {
		let s = try store()
		var failures: [String] = []
		let files = try s.files(archive: archive, group: group)
		for (f, data) in files {
			do { _ = try T.decode(id: f, data) { _ in XCTFail("\(T.self) \(f) has an unknown opcode") } } catch { failures.append("\(T.self) \(f): \(error)") }
		}
		XCTAssertEqual(failures, [])
		return files.count
	}

	func testQuickChatDecodes() throws {
		let cats = try decodeEverything(QuickChatCatType.self, archive: ConfigStore.Archive.quickChatPrimary, group: 0)
		let phrases = try decodeEverything(QuickChatPhraseType.self, archive: ConfigStore.Archive.quickChatPrimary, group: 1)
		print("quick chat: \(cats) categories, \(phrases) phrases")
		XCTAssertGreaterThan(cats, 10)
		XCTAssertGreaterThan(phrases, 100)
		let root = try XCTUnwrap(try store().quickChatCat(0))
		XCTAssertFalse(root.subcategories.isEmpty)
	}

	/// The cache has no light (group 31) or cursor (group 33) files; check the decoders on rt4-shaped bytes.
	func testLightAndCursorDecodeSyntheticData() throws {
		let light = try LightType.decode(id: 0, [1, 7, 2, 0x01, 0x00, 3, 0x02, 0x00, 4, 0xFF, 0xFE, 0])
		XCTAssertEqual([light.opcode1, light.opcode2, light.opcode3, light.opcode4], [7, 256, 512, -2])
		let defaults = try LightType.decode(id: 1, [0])
		XCTAssertEqual([defaults.opcode1, defaults.opcode2, defaults.opcode3, defaults.opcode4], [0, 2048, 2048, 0])
		let cursor = try CursorType.decode(id: 0, [1, 0x01, 0x02, 2, 5, 9, 0])
		XCTAssertEqual([cursor.spriteId, cursor.hotSpotX, cursor.hotSpotY], [258, 5, 9])
	}

	func testEveryNewConfigDecodes() throws {
		let counts = [
			"param": try decodeAll(ParamType.self, group: ConfigStore.ConfigGroup.param),
			"struct": try decodeAll(StructType.self, group: ConfigStore.ConfigGroup.structs),
			"inv": try decodeAll(InvType.self, group: ConfigStore.ConfigGroup.inv),
			"varp": try decodeAll(VarpType.self, group: ConfigStore.ConfigGroup.varp),
			"light": try decodeAll(LightType.self, group: ConfigStore.ConfigGroup.light),
			"cursor": try decodeAll(CursorType.self, group: ConfigStore.ConfigGroup.cursor),
			"msi": try decodeAll(MsiType.self, group: ConfigStore.ConfigGroup.msi),
		]
		print("decoded new config counts: \(counts.sorted { $0.key < $1.key })")
		// This cache has no light (31) or cursor (33) groups at all.
		for (k, n) in counts where k != "light" && k != "cursor" { XCTAssertGreaterThan(n, 0, k) }
		XCTAssertGreaterThan(counts["param"]!, 100)
		XCTAssertGreaterThan(counts["struct"]!, 100)
	}

	func testInventorySizesAndVarpCodes() throws {
		let s = try store()
		XCTAssertEqual(try s.inv(93)?.size, 28, "backpack")
		XCTAssertEqual(try s.inv(94)?.size, 14, "worn equipment")
		let codes = Dictionary(grouping: try s.varpIds(), by: { (try? s.varpType($0))??.clientCode ?? 0 })
		print("varp client codes: \(codes.filter { $0.key != 0 }.mapValues { $0.count })")
		XCTAssertNotNil(codes[VarpClientCode.chatEffects])
	}

	/// The host answers inventory size from `InvType`, not from what the server has sent.
	func testInvSizeOpUsesInvType() throws {
		let host = InterfaceScriptHost(store: try store())
		let size = try XCTUnwrap(HostOps.table[3304])
		let free = try XCTUnwrap(HostOps.table[3330])
		XCTAssertEqual(host.perform(size, ints: [93], strings: []).ints, [28])
		XCTAssertEqual(host.perform(free, ints: [93], strings: []).ints, [28])
		host.apply(.invFull(component: -1, inv: 93, items: [.init(id: 995, count: 5)] + [ServerMessage.InvItem](repeating: .init(id: -1, count: 0), count: 2)))
		XCTAssertEqual(host.perform(free, ints: [93], strings: []).ints, [27])
		XCTAssertEqual(host.perform(free, ints: [-1], strings: []).ints, [0])
	}

	// MARK: CS2 params

	/// Assembles `struct_param(structId, paramId)` then `put_varp(varp)`, `return`.
	func structParamScript(id: Int, structId: Int, paramId: Int, varp: Int) throws -> ClientScript {
		var b = Packet(capacity: 64)
		b.p1(0) // no name
		func ins(_ op: Int, _ v: Int) {
			b.p2(op)
			if op >= 100 || op == 21 { b.p1(v) } else { b.p4(v) }
		}
		ins(0, structId)
		ins(0, paramId)
		ins(4500, 0)
		ins(2, varp)
		ins(21, 0)
		b.p4(5) // instructions
		b.p2(0); b.p2(0); b.p2(0); b.p2(0)
		b.p1(0) // switches
		b.p2(1)
		return try ClientScript(id: id, data: b.written)
	}

	func testStructParamOpcodeReadsAndDefaults() throws {
		let s = try store()
		// Find a struct with an int param and one param it lacks.
		var found: (struct: Int, key: Int, value: Int32)?
		for (sid) in try s.files(archive: 2, group: ConfigStore.ConfigGroup.structs).keys.sorted() {
			guard let st = try s.structType(sid) else { continue }
			for (k, v) in st.params {
				if case .int(let i) = v, try s.param(k)?.isString == false { found = (sid, k, i); break }
			}
			if found != nil { break }
		}
		let f = try XCTUnwrap(found)
		let host = RecordingHost()
		let runner = ScriptRunner(store: s, host: host)
		s.cache["cs2#900001"] = try structParamScript(id: 900001, structId: f.struct, paramId: f.key, varp: 1)
		try runner.run(ScriptRequest(args: [.int(900001)]))
		XCTAssertEqual(host.varps[1], f.value)

		// A param the struct lacks falls back to the ParamType default.
		let missing = try XCTUnwrap(try s.files(archive: 2, group: ConfigStore.ConfigGroup.param).keys.sorted().first { k in
			guard let p = try? s.param(k), !p.isString, (try? s.structType(f.struct))??.params[k] == nil else { return false }
			return true
		})
		s.cache["cs2#900002"] = try structParamScript(id: 900002, structId: f.struct, paramId: missing, varp: 2)
		try runner.run(ScriptRequest(args: [.int(900002)]))
		XCTAssertEqual(host.varps[2] ?? 0, try s.param(missing)?.defaultInt)
		// A struct that does not exist has no params at all.
		s.cache["cs2#900003"] = try structParamScript(id: 900003, structId: 0x7FFFFF, paramId: f.key, varp: 3)
		try runner.run(ScriptRequest(args: [.int(900003)]))
		XCTAssertEqual(host.varps[3] ?? 0, try s.param(f.key)?.defaultInt)
	}

	func testParamTypeResolve() {
		var p = ParamType(id: 7)
		p.defaultInt = 42
		p.defaultString = "dflt"
		XCTAssertEqual(p.resolve([:]), .int(42))
		XCTAssertEqual(p.resolve([7: .int(3)]), .int(3))
		XCTAssertEqual(p.resolve([7: .string("x")]), .int(42), "wrong kind is ignored like rt4's cast-free lookup would not")
		p.type = 115
		XCTAssertTrue(p.isString)
		XCTAssertEqual(p.resolve([:]), .string("dflt"))
		XCTAssertEqual(p.resolve([7: .string("hi")]), .string("hi"))
	}

	// MARK: client settings and varp client codes

	func emptyHost() -> InterfaceScriptHost {
		InterfaceScriptHost(store: ConfigStore(source: { _, _ in nil }))
	}

	func testPreferenceOpsClampAndNotify() throws {
		let host = emptyHost()
		var changes: [ClientPreferences.Change] = []
		host.onPreferenceChange = { changes.append($0) }
		func set(_ op: Int, _ v: Int32) { _ = host.perform(HostOps.table[op]!, ints: [v], strings: []) }
		func get(_ op: Int) -> Int32 { host.perform(HostOps.table[op]!, ints: [], strings: []).ints.first ?? -99 }
		XCTAssertEqual(get(6101), 3)
		set(6001, 9)
		XCTAssertEqual(get(6101), 4)
		set(6019, 300)
		XCTAssertEqual(get(6119), 255)
		set(6019, 100)
		set(6018, -4)
		set(6020, 500)
		XCTAssertEqual([get(6119), get(6118), get(6120)], [100, 0, 127])
		XCTAssertEqual(changes, [.brightness(gamma: 0.6), .musicVolume(old: 255, new: 100), .soundEffectVolume(0), .ambientVolume(127)])
		set(6011, 7)
		XCTAssertEqual(get(6111), 0)
	}

	func testVarpClientCodeSideEffects() throws {
		let s = try store()
		let codes = Dictionary(grouping: try s.varpIds(), by: { (try? s.varpType($0))??.clientCode ?? 0 })
		let host = InterfaceScriptHost(store: s)
		var seen: [(Int, Int)] = []
		host.onVarpClientCode = { seen.append(($0, $1)) }
		if let id = codes[VarpClientCode.chatEffects]?.first {
			host.setVarp(id, 1)
			XCTAssertEqual(host.varpClient.chatEffectsDisabled, 1)
			XCTAssertEqual(seen.last?.0, VarpClientCode.chatEffects)
			// rt4 `VarpDomain.reset` keeps varps that have a client code.
			host.apply(.resetClientVarcache)
			XCTAssertEqual(host.varp(id), 1)
		}
		if let id = codes[VarpClientCode.mouseButtons]?.first {
			host.setVarp(id, 1)
			XCTAssertEqual(host.varpClient.mouseButtons, 1)
		}
		if let id = codes[VarpClientCode.insertMode]?.first {
			host.setVarp(id, 1)
			XCTAssertEqual(host.varpClient.inserting, 1)
		}
		if let plain = codes[0]?.first {
			host.setVarp(plain, 5)
			host.apply(.resetClientVarcache)
			XCTAssertEqual(host.varp(plain), 0)
		}
	}

	/// The Options tab ops reach the audio players and rasterisers through `GameClient`.
	func testOptionsReachAudioAndRasteriser() throws {
		let s = try store()
		let client = try GameClient(store: s, server: .init(host: "127.0.0.1", port: 1))
		func set(_ op: Int, _ v: Int32) { _ = client.host.perform(HostOps.table[op]!, ints: [v], strings: []) }
		set(6019, 100)
		XCTAssertEqual(client.audio.music.volume, 100)
		set(6018, 33)
		XCTAssertEqual(client.audio.effects.effectVolume, 33)
		set(6020, 44)
		XCTAssertEqual(client.audio.effects.ambientVolume, 44)
		set(6001, 1)
		XCTAssertEqual(client.world.brightness, 0.9)
		XCTAssertEqual(client.ui.models.brightness, 0.9)
		XCTAssertEqual(client.ui.icons.brightness, 0.9)
		set(6019, 0)
		XCTAssertEqual(client.audio.music.volume, 0)
	}
}
