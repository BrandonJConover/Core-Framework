import XCTest
@testable import Scape530

/// The quest guides checked against the real cache and the server's own data files, so a wrong id or tile cannot
/// slip in. Needs `SCAPE530_CACHE`; the loc and spawn checks also need `SCAPE530_S09` (the server's `data/configs`).
final class QuestDataTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func serverFile(_ name: String) throws -> Data {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_S09"] else { throw XCTSkip("SCAPE530_S09 not set") }
		return try Data(contentsOf: URL(fileURLWithPath: dir + "/" + name))
	}

	func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "\u{2019}", with: "'") }

	/// A declared name may carry a qualifier in brackets ("Map part (Wormbrain)") that tells apart items sharing a name.
	func base(_ s: String) -> String { norm(String(s.split(separator: "(").first ?? "")).trimmingCharacters(in: .whitespaces) }

	func testItemIdsAndNamesMatchTheCache() throws {
		let s = try store()
		var checked = 0
		for d in QuestCatalog.all {
			for step in d.steps {
				for it in step.items {
					let t = try XCTUnwrap(try s.objResolved(it.id), "\(d.name)/\(step.id): item \(it.id) \(it.name) exists in the cache")
					XCTAssertEqual(norm(t.name), base(it.name), "\(d.name)/\(step.id): item \(it.id)")
					checked += 1
				}
				for case .groundItem(let name, let id, _) in step.targets {
					let t = try XCTUnwrap(try s.objResolved(id), "\(d.name)/\(step.id): ground item \(id)")
					XCTAssertEqual(norm(t.name), norm(name), "\(d.name)/\(step.id): ground item \(id)")
				}
			}
		}
		XCTAssertGreaterThan(checked, 50)
	}

	func testNpcIdsAndNamesMatchTheCache() throws {
		let s = try store()
		var checked = 0
		for d in QuestCatalog.all {
			for step in d.steps {
				for case .npc(let name, let ids, _) in step.targets {
					XCTAssertFalse(ids.isEmpty)
					for id in ids {
						let t = try XCTUnwrap(try s.npc(id), "\(d.name)/\(step.id): npc \(id)")
						XCTAssertEqual(norm(t.name), norm(name), "\(d.name)/\(step.id): npc \(id)")
						checked += 1
					}
				}
			}
		}
		XCTAssertGreaterThan(checked, 30)
	}

	/// Every npc target's known tile lies within a few tiles of one of the server's spawns for that npc.
	func testNpcTilesMatchServerSpawns() throws {
		struct Spawn: Decodable { var npc_id: String; var loc_data: String }
		let spawns = try JSONDecoder().decode([Spawn].self, from: try serverFile("npc_spawns.json"))
		var byId: [Int: [(Int, Int, Int)]] = [:]
		for sp in spawns {
			guard let id = Int(sp.npc_id) else { continue }
			for part in sp.loc_data.split(separator: "-") {
				let nums = part.trimmingCharacters(in: CharacterSet(charactersIn: "{}")).split(separator: ",").compactMap { Int($0) }
				if nums.count >= 3 { byId[id, default: []].append((nums[0], nums[1], nums[2])) }
			}
		}
		for d in QuestCatalog.all {
			for step in d.steps {
				for case .npc(let name, let ids, let at) in step.targets {
					var near = false
					for id in ids { for p in byId[id] ?? [] where abs(p.0 - at.x) <= 3 && abs(p.1 - at.z) <= 3 && p.2 == at.plane { near = true } }
					XCTAssertTrue(near, "\(d.name)/\(step.id): \(name) at \(at) is not a server spawn")
				}
			}
		}
	}

	func testLocTargetsExistInTheMapAtTheirTile() throws {
		let s = try store()
		struct X: Decodable { struct K: Decodable { var regionId: String; var keys: String }; var xteas: [K] }
		let x = try JSONDecoder().decode(X.self, from: try serverFile("xteas.json"))
		var keys: [Int: [Int32]] = [:]
		for k in x.xteas { keys[Int(k.regionId)!] = k.keys.split(separator: ",").compactMap { Int32($0) } }
		var checked = 0
		for d in QuestCatalog.all {
			for step in d.steps {
				for case .loc(let name, let id, let at) in step.targets {
					let rx = at.x >> 6, rz = at.z >> 6
					let locs = try XCTUnwrap(try s.mapLocs(x: rx, z: rz, key: keys[rx << 8 | rz] ?? [0, 0, 0, 0]), "map region of \(name)")
					let hit = locs.contains { $0.id == id && rx * 64 + $0.x == at.x && rz * 64 + $0.z == at.z && $0.level == at.plane }
					XCTAssertTrue(hit, "\(d.name)/\(step.id): \(name) loc \(id) at \(at)")
					checked += 1
				}
			}
		}
		XCTAssertGreaterThan(checked, 10)
	}

	func testGroundItemTargetsAreServerGroundSpawns() throws {
		struct G: Decodable { var item_id: String; var loc_data: String }
		let spawns = try JSONDecoder().decode([G].self, from: try serverFile("ground_spawns.json"))
		var byId: [Int: [(Int, Int, Int)]] = [:]
		for sp in spawns {
			guard let id = Int(sp.item_id) else { continue }
			for part in sp.loc_data.split(separator: "-") {
				let n = part.trimmingCharacters(in: CharacterSet(charactersIn: "{}")).split(separator: ",").compactMap { Int($0) }
				if n.count >= 4 { byId[id, default: []].append((n[1], n[2], n[3])) }   // {1,x,z,plane,delay}
			}
		}
		for d in QuestCatalog.all {
			for step in d.steps {
				for case .groundItem(let name, let id, let at) in step.targets {
					XCTAssertTrue((byId[id] ?? []).contains { $0.0 == at.x && $0.1 == at.z && $0.2 == at.plane }, "\(d.name)/\(step.id): \(name) \(id) at \(at)")
				}
			}
		}
	}
}
