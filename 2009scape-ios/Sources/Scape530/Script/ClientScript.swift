/// A decoded CS2 script (archive 12, group = script id, file 0). Port of rt4
/// `ClientScriptList.get` / `ClientScript`.
public struct ClientScript {
	public let id: Int
	/// rt4 `fastgjstr` name: nil when the first byte is 0.
	public var name: String?
	public var intLocals = 0, stringLocals = 0, intArgs = 0, stringArgs = 0
	public var opcodes: [Int] = []
	/// Int operand (g4 or g1), or 0 for string-operand instructions.
	public var intOperands: [Int32] = []
	public var stringOperands: [String?] = []
	/// Switch tables: case value -> relative jump offset.
	public var switchTables: [[Int32: Int32]] = []

	public struct DecodeError: Error, CustomStringConvertible {
		public let message: String
		public var description: String { message }
	}

	public init(id: Int, data: [UInt8]) throws {
		self.id = id
		guard data.count >= 14 else { throw DecodeError(message: "script \(id): too short (\(data.count))") }
		var p = Packet(data, offset: data.count - 2)
		let trailerLen = try p.g2()
		let trailerPos = data.count - trailerLen - 12 - 2
		guard trailerPos >= 0 else { throw DecodeError(message: "script \(id): bad trailer length \(trailerLen)") }
		p.offset = trailerPos
		let instructions = Int(try p.g4())
		guard instructions >= 0, instructions <= data.count else { throw DecodeError(message: "script \(id): bad instruction count") }
		intLocals = try p.g2()
		stringLocals = try p.g2()
		intArgs = try p.g2()
		stringArgs = try p.g2()
		let switches = try p.g1()
		for _ in 0..<switches {
			var cases = try p.g2()
			var table: [Int32: Int32] = [:]
			while cases > 0 {
				cases -= 1
				let value = try p.g4()
				table[value] = try p.g4()
			}
			switchTables.append(table)
		}
		p.offset = 0
		// fastgjstr
		if data[0] == 0 {
			p.offset = 1
		} else {
			name = try p.gjstr()
		}
		opcodes = [Int](repeating: 0, count: instructions)
		intOperands = [Int32](repeating: 0, count: instructions)
		stringOperands = [String?](repeating: nil, count: instructions)
		var i = 0
		while trailerPos > p.offset {
			guard i < instructions else { throw DecodeError(message: "script \(id): more instructions than declared (\(instructions))") }
			let op = try p.g2()
			if op == 3 {
				stringOperands[i] = try p.gjstr()
			} else if op >= 100 || op == 21 || op == 38 || op == 39 {
				intOperands[i] = Int32(try p.g1())
			} else {
				intOperands[i] = try p.g4()
			}
			opcodes[i] = op
			i += 1
		}
		guard i == instructions else { throw DecodeError(message: "script \(id): decoded \(i) of \(instructions) instructions") }
	}
}

extension ConfigStore {
	public enum ScriptArchive {
		public static let scripts = 12
		public static let paramGroup = 11
		public static let structGroup = 26
	}

	/// rt4 `ClientScriptList.get`: script `id` from archive 12, memoised.
	public func script(_ id: Int) throws -> ClientScript? {
		let key = "cs2#\(id)"
		if let s = cache[key] as? ClientScript { return s }
		guard try index(ScriptArchive.scripts).isValid(group: id),
			let data = try file(archive: ScriptArchive.scripts, group: id, file: 0) else { return nil }
		let s = try ClientScript(id: id, data: data)
		cache[key] = s
		return s
	}

	/// All script ids present in archive 12.
	public func scriptIds() throws -> [Int] {
		Array(try index(ScriptArchive.scripts).groupIds)
	}
}
