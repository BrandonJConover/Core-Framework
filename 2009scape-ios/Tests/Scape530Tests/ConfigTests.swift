import XCTest
@testable import Scape530

/// Decodes every config entry in the real cache (needs SCAPE530_CACHE).
/// Each decoder must hit its 0 terminator exactly at the end of the file,
/// so a wrong field width anywhere shows up as a failure here.
final class ConfigTests: XCTestCase {
	static var store: ConfigStore?

	func store() throws -> ConfigStore {
		if let s = Self.store { return s }
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else {
			throw XCTSkip("SCAPE530_CACHE not set")
		}
		let s = ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
		Self.store = s
		return s
	}

	/// Decodes all files of `archive` (optionally one group) and returns how many decoded.
	func decodeAll<T: ConfigType>(_ t: T.Type, archive: Int, group: Int? = nil, idOf: (Int, Int) -> Int) throws -> Int {
		let s = try store()
		let idx = try s.index(archive)
		var ok = 0
		var failures: [String] = []
		var unknown: [String] = []
		for g in (group.map { [$0] } ?? idx.groupIds) {
			for (f, data) in try s.files(archive: archive, group: g) {
				do {
					let id = idOf(g, f)
					_ = try T.decode(id: id, data) { op in
						unknown.append("\(T.self) \(id) op \(op)")
					}
					ok += 1
				} catch {
					failures.append("\(error)")
				}
			}
		}
		XCTAssertEqual(failures.count, 0, "\(T.self): \(failures.prefix(5))")
		// Only npc 1688 has opcodes rt4 does not know (see ConfigType.decode).
		let expected = T.self == NpcType.self ? [138, 255, 255, 159, 165, 255].map { "NpcType 1688 op \($0)" } : []
		XCTAssertEqual(unknown, expected)
		return ok
	}

	func testEveryConfigDecodes() throws {
		let counts = [
			"obj": try decodeAll(ObjType.self, archive: ConfigStore.Archive.objs) { $0 << 8 | $1 },
			"npc": try decodeAll(NpcType.self, archive: ConfigStore.Archive.npcs) { $0 << 7 | $1 },
			"loc": try decodeAll(LocType.self, archive: ConfigStore.Archive.locs) { $0 << 8 | $1 },
			"seq": try decodeAll(SeqType.self, archive: ConfigStore.Archive.seqs) { $0 << 7 | $1 },
			"spotanim": try decodeAll(SpotAnimType.self, archive: ConfigStore.Archive.spotAnims) { $0 << 8 | $1 },
			"varbit": try decodeAll(VarbitType.self, archive: ConfigStore.Archive.varbits) { $0 << 10 | $1 },
			"enum": try decodeAll(EnumType.self, archive: ConfigStore.Archive.enums) { $0 << 8 | $1 },
			"flo": try decodeAll(FloType.self, archive: 2, group: ConfigStore.ConfigGroup.flo) { $1 },
			"flu": try decodeAll(FluType.self, archive: 2, group: ConfigStore.ConfigGroup.flu) { $1 },
			"idk": try decodeAll(IdkType.self, archive: 2, group: ConfigStore.ConfigGroup.idk) { $1 },
			"bas": try decodeAll(BasType.self, archive: 2, group: ConfigStore.ConfigGroup.bas) { $1 },
		]
		print("decoded config counts: \(counts.sorted { $0.key < $1.key })")
		XCTAssertGreaterThan(counts["obj"]!, 10_000)
		XCTAssertGreaterThan(counts["npc"]!, 5_000)
		XCTAssertGreaterThan(counts["loc"]!, 20_000)
	}

	/// Spot checks against things the live server showed us.
	func testKnownDefinitions() throws {
		let s = try store()
		XCTAssertEqual(try s.obj(995)?.name, "Coins")
		XCTAssertEqual(try s.obj(995)?.stackable, true)
		XCTAssertEqual(try s.obj(1351)?.name, "Bronze axe")
		XCTAssertEqual(try s.npc(0)?.name, "Hans")
		XCTAssertEqual(try s.npc(945)?.name, "RuneScape guide")
		XCTAssertEqual(try s.npc(47)?.name, "Rat")
		XCTAssertEqual(try s.idk(0)?.bodyPart, 0)
		// The player's BAS from PLAYER_INFO appearance (1426) has idle + walk anims.
		let bas = try XCTUnwrap(try s.bas(1426))
		XCTAssertNotEqual(bas.idle, -1)
		XCTAssertNotNil(try s.seq(bas.walk))
	}
}

