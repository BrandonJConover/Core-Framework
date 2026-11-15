/// NPC definition (archive 18, group id >>> 7, file id & 0x7F). Port of rt4 `NpcType.decode`.
public struct NpcType: ConfigType, Equatable {
	public let id: Int
	public var models: [Int] = []
	public var headModels: [Int] = []
	public var name = "null"
	public var size = 1
	public var ops: [String?] = [nil, nil, nil, nil, nil]
	public var recolours: [Int: Int] = [:]
	public var retextures: [Int: Int] = [:]
	public var recolourPalette: [Int] = []
	public var minimapVisible = true
	public var combatLevel = -1
	public var resizeXZ = 128
	public var resizeY = 128
	public var topRenderPriority = false
	public var ambient = 0
	public var contrast = 0
	public var headIcon = -1
	public var rotationSpeed = 32
	public var multiVarbit = -1
	public var multiVarp = -1
	/// Variant NPC ids by varbit/varp value; the last entry is the default.
	public var multiNpcs: [Int]?
	public var interactive = true
	public var rotationFlag = true
	public var hasShadow = true
	public var shadowColours = [0, 0]
	public var shadowModifiers = [-96, -16]
	public var loginScreenProperties = 0
	public var modelOffsets: [Int: [Int]] = [:]
	public var hitBarId = -1
	public var iconHeight = -1
	public var spawnDirection = 4
	public var minimapMarker = -1
	public var basId = -1
	public var sounds = (idle: -1, crawl: -1, walk: -1, run: -1, radius: 0)
	public var cursors: [(op: Int, cursor: Int)] = []
	public var attackCursor = -1
	public var params: [Int: ParamValue] = [:]

	public init(id: Int) { self.id = id }

	public static func == (a: NpcType, b: NpcType) -> Bool { a.id == b.id && a.name == b.name && a.models == b.models }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1:
			let n = try p.g1()
			models = try (0..<n).map { _ in nullable(try p.g2()) }
		case 2: name = try p.gjstr()
		case 12: size = try p.g1()
		case 30...34: ops[op - 30] = menuOption(try p.gjstr())
		case 40: for (s, d) in try decodePairs(&p) { recolours[s] = d }
		case 41: for (s, d) in try decodePairs(&p) { retextures[s] = d }
		case 42:
			let n = try p.g1()
			recolourPalette = try (0..<n).map { _ in try p.g1b() }
		case 60:
			let n = try p.g1()
			headModels = try (0..<n).map { _ in try p.g2() }
		case 93: minimapVisible = false
		case 95: combatLevel = try p.g2()
		case 97: resizeXZ = try p.g2()
		case 98: resizeY = try p.g2()
		case 99: topRenderPriority = true
		case 100: ambient = try p.g1b()
		case 101: contrast = try p.g1b() * 5
		case 102: headIcon = try p.g2()
		case 103: rotationSpeed = try p.g2()
		case 106, 118:
			multiVarbit = nullable(try p.g2())
			multiVarp = nullable(try p.g2())
			var fallback = -1
			if op == 118 { fallback = nullable(try p.g2()) }
			let n = try p.g1()
			var list = try (0...n).map { _ in nullable(try p.g2()) }
			list.append(fallback)
			multiNpcs = list
		case 107: interactive = false
		case 109: rotationFlag = false
		case 111: hasShadow = false
		case 113: shadowColours = [try p.g2(), try p.g2()]
		case 114: shadowModifiers = [try p.g1b(), try p.g1b()]
		case 115: _ = try p.g1(); _ = try p.g1()
		case 119: loginScreenProperties = try p.g1b()
		case 121:
			let n = try p.g1()
			for _ in 0..<n {
				let slot = try p.g1()
				modelOffsets[slot] = [try p.g1b(), try p.g1b(), try p.g1b()]
			}
		case 122: hitBarId = try p.g2()
		case 123: iconHeight = try p.g2()
		case 125: spawnDirection = try p.g1b()
		case 126: minimapMarker = try p.g2()
		case 127: basId = try p.g2()
		case 128: _ = try p.g1()
		case 134:
			let idle = nullable(try p.g2()), crawl = nullable(try p.g2())
			let walk = nullable(try p.g2()), run = nullable(try p.g2())
			sounds = (idle, crawl, walk, run, try p.g1())
		case 135, 136: cursors.append((try p.g1(), try p.g2()))
		case 137: attackCursor = try p.g2()
		case 249: try decodeParams(&p, into: &params)
		default: throw UnknownConfigOpcode(type: "npc \(id)", opcode: op)
		}
	}

	public static func location(of id: Int) -> (group: Int, file: Int) { (id >> 7, id & 0x7F) }
}
