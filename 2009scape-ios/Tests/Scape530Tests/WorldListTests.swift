import Foundation
import XCTest
@testable import Scape530

/// A scripted byte stream standing in for a game socket.
final class ScriptedTransport: ByteTransport {
	var incoming: [UInt8]
	var sent: [UInt8] = []
	var closed = false
	init(_ incoming: [UInt8]) { self.incoming = incoming }
	func write(_ bytes: [UInt8]) throws { sent += bytes }
	func readSome(max: Int) throws -> [UInt8] {
		let n = min(max, incoming.count)
		defer { incoming.removeFirst(n) }
		return Array(incoming.prefix(n))
	}
	func readExactly(_ count: Int) throws -> [UInt8] {
		guard incoming.count >= count else { throw ConnectFailure(host: "t", port: 0, reason: "short read") }
		defer { incoming.removeFirst(count) }
		return Array(incoming.prefix(count))
	}
	func setReadTimeout(milliseconds: Int) {}
	func close() { closed = true }
}

/// Builds the bytes 2009scape's `WorldList.sendUpdate` writes (see `core/net/lobby/WorldList.java`).
enum WorldListFixture {
	struct W { var id: Int, country: Int, flags: Int, activity: String, host: String, players: Int }

	static func smart(_ v: Int) -> [UInt8] { v > 127 ? [UInt8((v + 32768) >> 8), UInt8((v + 32768) & 0xFF)] : [UInt8(v)] }
	static func jstr(_ s: String) -> [UInt8] { [0] + Array(s.utf8) + [0] }
	static func int(_ v: Int) -> [UInt8] { (0..<4).map { UInt8((v >> (24 - 8 * $0)) & 0xFF) } }

	/// The reply body after the length: `[1][updated]` then the tables and the player counts.
	static func body(worlds: [W], countries: [(flag: Int, name: String)], minId: Int = 0, maxId: Int? = nil, update: Bool = true, checksum: Int = 77) -> [UInt8] {
		var b: [UInt8] = [1, update ? 1 : 0]
		if update {
			b += smart(countries.count)
			for c in countries { b += smart(c.flag) + jstr(c.name) }
			b += smart(minId) + smart(maxId ?? worlds.count) + smart(worlds.count)
			for w in worlds { b += smart(w.id - minId) + [UInt8(w.country)] + int(w.flags) + jstr(w.activity) + jstr(w.host) }
			b += int(checksum)
		}
		for w in worlds { let p = w.players < 0 ? 65535 : w.players; b += smart(w.id - minId) + [UInt8(p >> 8), UInt8(p & 0xFF)] }
		return b
	}

	/// The whole wire reply: status byte, 16-bit length, body.
	static func reply(_ body: [UInt8]) -> [UInt8] { [0, UInt8(body.count >> 8), UInt8(body.count & 0xFF)] + body }

	static let single = [W(id: 1, country: 0, flags: 1 | 8, activity: "2009Scape Classic", host: "127.0.0.1", players: 3)]
	static let several = [
		W(id: 1, country: 0, flags: 1 | 8, activity: "-", host: "w1.example", players: 120),
		W(id: 2, country: 1, flags: 2, activity: "Skill total 1000", host: "w2.example", players: 40),
		W(id: 3, country: 1, flags: 4, activity: "Bounty hunter", host: "w3.example", players: -1),
		W(id: 4, country: 0, flags: 0, activity: "-", host: "w4.example", players: 75),
	]
	static let countries = [(flag: 225, name: "USA"), (flag: 77, name: "Germany")]
}

final class WorldListTests: XCTestCase {
	func testRequestBytes() {
		XCTAssertEqual(WorldList.request(checksum: 0), [255, 0, 0, 0, 0])
		XCTAssertEqual(WorldList.request(checksum: 0x01020304), [255, 1, 2, 3, 4])
	}

	func testDecodeSingleWorldLikeTheServer() {
		let list = WorldList()
		let body = WorldListFixture.body(worlds: WorldListFixture.single, countries: [(225, "Anywhere, USA")])
		XCTAssertTrue(list.decode(body))
		XCTAssertTrue(list.loaded)
		XCTAssertEqual(list.size, 1)
		XCTAssertEqual(list.checksum, 77)
		let w = list.world(1)
		XCTAssertEqual(w, WorldEntry(id: 1, country: 0, flags: 9, activity: "2009Scape Classic", hostname: "127.0.0.1", players: 3))
		XCTAssertTrue(w!.isMembers && w!.isLootShare && !w!.isPvp && !w!.isQuickChat)
		XCTAssertEqual(list.country(of: w!), WorldCountry(flag: 225, name: "Anywhere, USA"))
		XCTAssertNil(list.world(2))
		XCTAssertEqual(list.firstWorld()?.id, 1)
		XCTAssertNil(list.nextWorld())
	}

	func testDecodeMinIdOffsetAndOfflinePlayers() {
		let list = WorldList()
		var ws = WorldListFixture.several
		for i in ws.indices { ws[i].id += 300 }
		XCTAssertTrue(list.decode(WorldListFixture.body(worlds: ws, countries: WorldListFixture.countries, minId: 301, maxId: 304)))
		XCTAssertEqual(list.minId, 301)
		XCTAssertEqual(list.world(302)?.hostname, "w2.example")
		XCTAssertEqual(list.world(303)?.players, -1)
		XCTAssertNil(list.world(300))
		XCTAssertEqual(list.sorted.map(\.id), [301, 302, 303, 304])
	}

	func testPlayerOnlyUpdateKeepsTheTable() {
		let list = WorldList()
		XCTAssertTrue(list.decode(WorldListFixture.body(worlds: WorldListFixture.several, countries: WorldListFixture.countries)))
		var ws = WorldListFixture.several
		ws[0].players = 5; ws[2].players = 9
		XCTAssertTrue(list.decode(WorldListFixture.body(worlds: ws, countries: [], update: false)))
		XCTAssertEqual(list.world(1)?.players, 5)
		XCTAssertEqual(list.world(3)?.players, 9)
		XCTAssertEqual(list.world(2)?.activity, "Skill total 1000")
		XCTAssertEqual(list.checksum, 77)
	}

	func testMalformedRepliesAreRejected() {
		let list = WorldList()
		XCTAssertFalse(list.decode([]))
		XCTAssertFalse(list.decode([2, 1]))
		var body = WorldListFixture.body(worlds: WorldListFixture.several, countries: WorldListFixture.countries)
		body.removeLast(7)
		XCTAssertFalse(list.decode(body))
		XCTAssertFalse(list.loaded)
		// A world offset past the table is refused rather than trapping.
		XCTAssertFalse(WorldList().decode([1, 1, 0, 0, 0, 1, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	}

	// MARK: sorting (rt4 `sortWorldList`)

	private func loaded() -> WorldList {
		let list = WorldList()
		XCTAssertTrue(list.decode(WorldListFixture.body(worlds: WorldListFixture.several, countries: WorldListFixture.countries)))
		return list
	}

	func testSortByPlayers() {
		let l = loaded()
		// Primary key players, ascending; an offline world (-1) sorts as 2001, so last.
		l.sort(primaryKey: 1, primaryReverse: false, secondaryKey: -1, secondaryReverse: false)
		XCTAssertEqual(l.sorted.map(\.id), [2, 4, 1, 3])
		l.sort(primaryKey: 1, primaryReverse: true, secondaryKey: -1, secondaryReverse: false)
		// Reversed: offline worlds count as -1, so they come last again after the largest.
		XCTAssertEqual(l.sorted.map(\.id), [1, 4, 2, 3])
	}

	func testSortByCountryThenId() {
		let l = loaded()
		l.sort(primaryKey: 2, primaryReverse: false, secondaryKey: 0, secondaryReverse: true)
		// Germany (2, 3) before USA (1, 4); ids descending inside each country.
		XCTAssertEqual(l.sorted.map(\.id), [3, 2, 4, 1])
	}

	func testSortByActivityPutsDashLast() {
		let l = loaded()
		l.sort(primaryKey: 3, primaryReverse: false, secondaryKey: 0, secondaryReverse: false)
		XCTAssertEqual(l.sorted.map(\.id), [3, 2, 1, 4])
		l.sort(primaryKey: 3, primaryReverse: true, secondaryKey: 0, secondaryReverse: false)
		XCTAssertEqual(l.sorted.map(\.id), [2, 3, 1, 4]) // rt4 keeps "-" last in both directions
	}

	func testSortByFlags() {
		let l = loaded()
		l.sort(primaryKey: 7, primaryReverse: false, secondaryKey: 0, secondaryReverse: false)
		XCTAssertEqual(l.sorted.map(\.id), [2, 3, 4, 1]) // non-members first, then members
		l.sort(primaryKey: 6, primaryReverse: true, secondaryKey: 0, secondaryReverse: false)
		XCTAssertEqual(l.sorted.map(\.id), [3, 1, 2, 4]) // pvp first
		l.sort(primaryKey: 5, primaryReverse: true, secondaryKey: 0, secondaryReverse: false)
		XCTAssertEqual(l.sorted.map(\.id), [2, 1, 3, 4]) // quick chat first
		l.sort(primaryKey: 4, primaryReverse: true, secondaryKey: 0, secondaryReverse: false)
		XCTAssertEqual(l.sorted.map(\.id), [1, 2, 3, 4]) // lootshare first
		l.sort(primaryKey: 9, primaryReverse: false, secondaryKey: -1, secondaryReverse: false)
		XCTAssertEqual(l.sorted.map(\.id), [1, 2, 3, 4]) // unknown key: by id
	}

	func testWalkAfterSort() {
		let l = loaded()
		l.sort(primaryKey: 0, primaryReverse: true, secondaryKey: -1, secondaryReverse: false)
		var seen: [Int] = []
		var w = l.firstWorld()
		while let x = w { seen.append(x.id); w = l.nextWorld() }
		XCTAssertEqual(seen, [4, 3, 2, 1])
	}

	func testFallbackListIsOneWorld() {
		let l = WorldList()
		l.loadFallback(id: 1, hostname: "h")
		XCTAssertEqual(l.sorted.map(\.id), [1])
		XCTAssertEqual(l.world(1)?.hostname, "h")
	}

	// MARK: fetching

	private func waitFetch(_ l: WorldList) -> Int {
		for _ in 0..<400 {
			let r = l.fetch()
			if r != -1 { return r }
			Thread.sleep(forTimeInterval: 0.01)
		}
		return -99
	}

	func testFetchAsksWithTheChecksumAndDecodes() {
		let body = WorldListFixture.body(worlds: WorldListFixture.several, countries: WorldListFixture.countries)
		let t = ScriptedTransport(WorldListFixture.reply(body))
		let l = WorldList()
		l.connect = { _, _ in t }
		XCTAssertEqual(l.fetch(), -1) // starts the request and does not block
		var r = -1
		for _ in 0..<400 where r == -1 { Thread.sleep(forTimeInterval: 0.01); r = l.fetch() }
		XCTAssertEqual(r, 0)
		XCTAssertEqual(t.sent, [255, 0, 0, 0, 0])
		XCTAssertTrue(t.closed)
		XCTAssertEqual(l.sorted.count, 4)
		// Within the refetch gap the list is current without another request.
		XCTAssertEqual(l.fetch(), 0)
		XCTAssertEqual(t.sent.count, 5)
	}

	func testSecondFetchSendsTheLoadedChecksum() {
		let l = WorldList()
		let first = ScriptedTransport(WorldListFixture.reply(WorldListFixture.body(worlds: WorldListFixture.several, countries: WorldListFixture.countries)))
		l.connect = { _, _ in first }
		l.refetchGap = 0
		XCTAssertEqual(waitFetch(l), 0)
		let second = ScriptedTransport(WorldListFixture.reply(WorldListFixture.body(worlds: WorldListFixture.several, countries: [], update: false)))
		l.connect = { _, _ in second }
		XCTAssertEqual(waitFetch(l), 0)
		XCTAssertEqual(second.sent, [255, 0, 0, 0, 77])
	}

	func testServerStatusByteIsTheErrorCode() {
		let l = WorldList()
		l.connect = { _, _ in ScriptedTransport([7]) }
		XCTAssertEqual(waitFetch(l), 7)
		// Nothing loaded: a one-world list of the server in use stands in.
		XCTAssertEqual(l.sorted.map(\.id), [1])
		XCTAssertEqual(l.lastError, 7)
	}

	func testUnreachableServerIsCode1001AfterRetries() {
		let l = WorldList()
		var attempts = 0
		l.connect = { _, _ in attempts += 1; throw ConnectFailure(host: "h", port: 1, reason: "down") }
		XCTAssertEqual(waitFetch(l), 1001)
		XCTAssertEqual(attempts, 5) // rt4 `close`: four retries before the code is reported
	}

	func testGarbageBodyIsCode1002() {
		let l = WorldList()
		l.connect = { _, _ in ScriptedTransport(WorldListFixture.reply([9, 9, 9])) }
		XCTAssertEqual(waitFetch(l), 1002)
	}

	// MARK: live

	func testLiveServerServesTheWorldList() throws {
		guard let server = ProcessInfo.processInfo.environment["SCAPE530_SERVER"] else { throw XCTSkip("needs SCAPE530_SERVER") }
		let parts = server.split(separator: ":")
		let l = WorldList()
		l.endpoint = { (String(parts[0]), Int(parts[1]) ?? 43595) }
		XCTAssertEqual(waitFetch(l), 0)
		XCTAssertTrue(l.loaded)
		XCTAssertNotNil(l.world(1), "world 1 should be listed: \(l.sorted)")
		print("live world list:", l.sorted, l.countries)
	}
}
