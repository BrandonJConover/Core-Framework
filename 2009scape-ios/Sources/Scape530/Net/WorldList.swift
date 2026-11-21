import Foundation

/// One country entry of the world list (rt4 `WorldInfo`): a flag sprite index and the region name the list shows.
public struct WorldCountry: Equatable {
	public var flag: Int
	public var name: String
	public init(flag: Int, name: String) { self.flag = flag; self.name = name }
}

/// One world (rt4 `World` / `AbstractWorld`).
public struct WorldEntry: Equatable {
	public var id: Int
	/// Index into `WorldList.countries`.
	public var country: Int
	public var flags: Int32
	public var activity: String
	public var hostname: String
	/// -1 while unknown (the list sends 65535 for an offline world).
	public var players: Int

	public init(id: Int, country: Int, flags: Int32, activity: String, hostname: String, players: Int = -1) {
		self.id = id; self.country = country; self.flags = flags
		self.activity = activity; self.hostname = hostname; self.players = players
	}

	/// rt4 `AbstractWorld.isMembers` / `isQuickChat` / `isPvp` / `isLootShare`.
	public var isMembers: Bool { flags & 0x1 != 0 }
	public var isQuickChat: Bool { flags & 0x2 != 0 }
	public var isPvp: Bool { flags & 0x4 != 0 }
	public var isLootShare: Bool { flags & 0x8 != 0 }
}

/// Port of rt4 `WorldList`: the world list the lobby serves on the game port, plus the CS2 ops that walk and sort it.
///
/// rev 530 asks for it with a raw request on a fresh connection to the game host (rt4 `WorldList.fetch`):
/// `[255][int checksum]` (the checksum of the list already held, 0 for none). The server answers one status byte
/// (0 = go on), a 16-bit length and that many bytes: `[1][updated byte]`, when `updated` is 1 the country table and
/// world table (`decodeWorlds`), then `(smart world id, 16-bit player count)` for every world (`decodePlayers`).
public final class WorldList {
	/// The first byte of the request (2009scape `HSReadEvent` case 255).
	public static let requestOpcode = 255

	/// rt4 `WorldList.step` 1: `[255][checksum]`.
	public static func request(checksum: Int32) -> [UInt8] {
		var p = Packet(capacity: 5)
		p.p1(requestOpcode)
		p.p4(checksum)
		return p.written
	}

	public private(set) var countries: [WorldCountry] = []
	public private(set) var minId = 0
	public private(set) var maxId = 0
	public private(set) var size = 0
	public private(set) var checksum: Int32 = 0
	/// rt4 `WorldList.loaded`.
	public private(set) var loaded = false
	/// rt4 `worlds`, indexed by `id - minId`.
	public private(set) var worlds: [WorldEntry?] = []
	/// rt4 `sorted`: the order the CS2 walk (`getFirstWorld` / `getNextWorld`) sees.
	public private(set) var sorted: [WorldEntry] = []
	private var worldPos = 1

	/// Text ordering for the country and activity sorts: the same approximation of rt4 `JagString.compare`
	/// (case-insensitive, accent-folding) the CS2 string ops use.
	public var compare: (String, String) -> Int = WorldList.compareText

	public static func compareText(_ a: String, _ b: String) -> Int {
		func fold(_ c: UInt32) -> UInt32 {
			switch c {
			case 156, 230: return 101
			case 140, 198: return 69
			case 223: return 115
			default: return c
			}
		}
		let x = a.lowercased().unicodeScalars.map { fold($0.value) }, y = b.lowercased().unicodeScalars.map { fold($0.value) }
		for i in 0..<min(x.count, y.count) where x[i] != y[i] { return x[i] < y[i] ? -1 : 1 }
		return x.count == y.count ? 0 : (x.count < y.count ? -1 : 1)
	}

	public init() {}

	// MARK: decoding

	/// rt4 `WorldList.decode`: false when the reply is malformed (rt4 then reports error 1002).
	@discardableResult
	public func decode(_ bytes: [UInt8]) -> Bool {
		var p = Packet(bytes)
		do {
			guard try p.g1() == 1 else { return false }
			var next = (countries, minId, maxId, size, worlds, checksum, loaded)
			if try p.g1() == 1 { next = try decodeWorlds(&p) }
			// decodePlayers: against the table the list now holds.
			var table = next.4
			for _ in 0..<next.3 {
				let idx = try p.gsmarts()
				var players = try p.g2()
				if players == 65535 { players = -1 }
				if idx >= 0, idx < table.count, table[idx] != nil { table[idx]!.players = players }
			}
			(countries, minId, maxId, size, _, checksum, loaded) = next
			worlds = table
		} catch {
			return false
		}
		rebuildSorted()
		return true
	}

	private func decodeWorlds(_ p: inout Packet) throws -> ([WorldCountry], Int, Int, Int, [WorldEntry?], Int32, Bool) {
		let countryCount = try p.gsmarts()
		var countries: [WorldCountry] = []
		for _ in 0..<countryCount {
			let flag = try p.gsmarts()
			countries.append(WorldCountry(flag: flag, name: try p.gjstr2()))
		}
		let minId = try p.gsmarts(), maxId = try p.gsmarts(), size = try p.gsmarts()
		guard maxId + 1 - minId >= 0 else { throw PacketUnderflow(offset: p.offset, wanted: 0, size: p.data.count) }
		var worlds = [WorldEntry?](repeating: nil, count: maxId + 1 - minId)
		for _ in 0..<size {
			let offset = try p.gsmarts()
			guard offset >= 0, offset < worlds.count else { throw PacketUnderflow(offset: p.offset, wanted: 0, size: p.data.count) }
			let country = try p.g1()
			let flags = try p.g4()
			let activity = try p.gjstr2()
			let host = try p.gjstr2()
			worlds[offset] = WorldEntry(id: offset + minId, country: country, flags: Int32(truncatingIfNeeded: flags), activity: activity, hostname: host)
		}
		let sum = try p.g4()
		return (countries, minId, maxId, size, worlds, Int32(truncatingIfNeeded: sum), true)
	}

	/// rt4 `WorldList.fetch` end: `sorted` is every present world by id.
	private func rebuildSorted() {
		sorted = []
		sorted.reserveCapacity(size)
		if maxId >= minId { for id in minId...maxId { if let w = world(id) { sorted.append(w) } } }
	}

	/// A list holding just one world, used when the server does not serve a list.
	public func loadFallback(id: Int, hostname: String, name: String = "2009scape") {
		countries = [WorldCountry(flag: 0, name: name)]
		minId = id; maxId = id; size = 1
		worlds = [WorldEntry(id: id, country: 0, flags: 0, activity: "-", hostname: hostname)]
		loaded = true
		rebuildSorted()
	}

	// MARK: queries (CS2 6501 / 6502 / 6506)

	/// rt4 `ScriptRunner.getWorld`.
	public func world(_ id: Int) -> WorldEntry? {
		loaded && id >= minId && id <= maxId && id - minId < worlds.count ? worlds[id - minId] : nil
	}

	public func country(of w: WorldEntry) -> WorldCountry {
		w.country >= 0 && w.country < countries.count ? countries[w.country] : WorldCountry(flag: 0, name: "")
	}

	/// rt4 `getFirstWorld`.
	public func firstWorld() -> WorldEntry? {
		worldPos = 0
		return nextWorld()
	}

	/// rt4 `getNextWorld`.
	public func nextWorld() -> WorldEntry? {
		guard sorted.count > worldPos else { return nil }
		defer { worldPos += 1 }
		return sorted[worldPos]
	}

	// MARK: sorting (CS2 6507)

	/// rt4 `WorldList.sortWorldList(secondaryKey, primaryReverse, primaryKey, secondaryReverse)`: a quicksort on
	/// `sorted` by `primaryKey` (then `secondaryKey` unless -1). Keys: 0 id (default), 1 players, 2 country,
	/// 3 activity, 4 lootshare, 5 quickchat, 6 pvp, 7 members.
	public func sort(primaryKey: Int, primaryReverse: Bool, secondaryKey: Int, secondaryReverse: Bool) {
		quicksort(secondaryKey, primaryKey, sorted.count - 1, secondaryReverse, 0, primaryReverse)
	}

	/// rt4 `WorldList.method1697`; the same partition scheme, so equal worlds end up in rt4's order.
	private func quicksort(_ secKey: Int, _ priKey: Int, _ hi: Int, _ secRev: Bool, _ lo: Int, _ priRev: Bool) {
		if hi <= lo { return }
		let mid = (hi + lo) / 2
		var store = lo
		let pivot = sorted[mid]
		sorted[mid] = sorted[hi]
		sorted[hi] = pivot
		for i in lo..<hi where rank(pivot, sorted[i], secKey, priKey, secRev, priRev) <= 0 {
			let t = sorted[i]
			sorted[i] = sorted[store]
			sorted[store] = t
			store += 1
		}
		sorted[hi] = sorted[store]
		sorted[store] = pivot
		quicksort(secKey, priKey, store - 1, secRev, lo, priRev)
		quicksort(secKey, priKey, hi, secRev, store + 1, priRev)
	}

	/// rt4 `WorldList.method3115`.
	func rank(_ a: WorldEntry, _ b: WorldEntry, _ secKey: Int, _ priKey: Int, _ secRev: Bool, _ priRev: Bool) -> Int {
		let primary = compareKey(b, priKey, a, priRev)
		if primary != 0 { return priRev ? -primary : primary }
		if secKey == -1 { return 0 }
		let secondary = compareKey(b, secKey, a, secRev)
		return secRev ? -secondary : secondary
	}

	/// rt4 `WorldList.method4595`.
	func compareKey(_ w0: WorldEntry, _ key: Int, _ w1: WorldEntry, _ reverse: Bool) -> Int {
		func flag(_ f: (WorldEntry) -> Bool) -> Int { f(w0) ? (f(w1) ? 0 : 1) : (f(w1) ? -1 : 0) }
		switch key {
		case 1:
			var p0 = w0.players, p1 = w1.players
			if !reverse {
				if p1 == -1 { p1 = 2001 }
				if p0 == -1 { p0 = 2001 }
			}
			return p0 - p1
		case 2: return compare(country(of: w0).name, country(of: w1).name)
		case 3:
			if w0.activity == "-" {
				if w1.activity == "-" { return 0 }
				return reverse ? -1 : 1
			} else if w1.activity == "-" {
				return reverse ? 1 : -1
			}
			return compare(w0.activity, w1.activity)
		case 4: return flag { $0.isLootShare }
		case 5: return flag { $0.isQuickChat }
		case 6: return flag { $0.isPvp }
		case 7: return flag { $0.isMembers }
		default: return w0.id - w1.id
		}
	}

	// MARK: fetching (rt4 `WorldList.fetch`)

	/// Where to ask: set by the client to its current game server.
	public var endpoint: () -> (host: String, port: Int) = { ("127.0.0.1", 43595) }
	/// Opens the connection; the iOS shell swaps the transport through `GameConnection.transportFactory`.
	public var connect: (_ host: String, _ port: Int) throws -> any ByteTransport = { try GameConnection.transportFactory($0, $1) }
	/// Seconds before a fetch is abandoned (rt4: 30 s, error 1000).
	public var timeout: TimeInterval = 30
	/// Minimum gap between two fetches (rt4: 5 s since the last one closed).
	public var refetchGap: TimeInterval = 5
	/// The last error code `fetch` returned (0 = none), for the shell and tests.
	public private(set) var lastError = 0

	private let lock = NSLock()
	private var inFlight = false
	private var finished: [UInt8]?
	private var failure: Int?
	private var closeTime: Date?
	private var errors = 0

	/// rt4 `WorldList.fetch` as the CS2 op 6500 calls it, once per script run: -1 while a request is running,
	/// 0 when the list is current (or was fetched less than `refetchGap` ago), otherwise an error code
	/// (1000 timeout, 1001 cannot connect, 1002 bad reply, 1003 i/o error, or the server's non-zero status byte).
	/// Failed fetches are retried up to four more times before the code is returned; when nothing was ever
	/// loaded a one-world list of the current server stands in so the login screen still has a world.
	public func fetch(now: Date = Date()) -> Int {
		lock.lock()
		if inFlight { lock.unlock(); return -1 }
		if let bytes = finished {
			finished = nil
			lock.unlock()
			if decode(bytes) {
				errors = 0
				closeTime = now
				lastError = 0
				return 0
			}
			return close(1002, now: now)
		}
		if let f = failure {
			failure = nil
			lock.unlock()
			return close(f, now: now)
		}
		if let c = closeTime, now.timeIntervalSince(c) < refetchGap { lock.unlock(); return 0 }
		inFlight = true
		lock.unlock()
		let ep = endpoint()
		let sum = loaded ? checksum : 0
		let thread = Thread { [weak self] in self?.run(host: ep.host, port: ep.port, checksum: sum) }
		thread.name = "scape530.worldlist"
		thread.start()
		return -1
	}

	/// rt4 `WorldList.close`: count the error; below five of them go round again (-1), else report the code.
	private func close(_ code: Int, now: Date) -> Int {
		errors += 1
		if errors > 4 {
			errors = 0
			closeTime = now
			lastError = code
			if !loaded { loadFallback(id: fallbackWorldId, hostname: endpoint().host) }
			return code
		}
		closeTime = nil
		return fetch(now: now)
	}

	/// World id the single-world fallback list uses.
	public var fallbackWorldId = 1

	private func run(host: String, port: Int, checksum: Int32) {
		var result: [UInt8]?
		var code = 0
		var socket: (any ByteTransport)?
		do {
			do { socket = try connect(host, port) } catch { throw FetchError(1001) }
			let s = socket!
			s.setReadTimeout(milliseconds: Int(timeout * 1000))
			do {
				try s.write(WorldList.request(checksum: checksum))
				let status = Int(try s.readExactly(1)[0])
				if status != 0 { throw FetchError(status) }
				let len = try s.readExactly(2)
				let body = try s.readExactly(Int(len[0]) << 8 | Int(len[1]))
				result = body
			} catch let e as FetchError {
				throw e
			} catch let e as BlockingSocket.Failure where e.timedOut {
				throw FetchError(1000)
			} catch {
				throw FetchError(1003)
			}
		} catch let e as FetchError {
			code = e.code
		} catch {
			code = 1003
		}
		socket?.close()
		lock.lock()
		inFlight = false
		if let r = result { finished = r } else { failure = code }
		lock.unlock()
	}

	private struct FetchError: Error {
		let code: Int
		init(_ c: Int) { code = c }
	}
}
