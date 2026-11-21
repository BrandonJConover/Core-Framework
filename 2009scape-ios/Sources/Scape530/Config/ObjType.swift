/// Item definition (archive 19, group id >>> 8, file id & 0xFF). Port of rt4 `ObjType.decode`.
public struct ObjType: ConfigType, Equatable {
	public let id: Int
	public var model = 0
	public var name = "null"
	public var zoom2d = 2000
	public var xAngle2D = 0
	public var yAngle2D = 0
	public var zAngle2D = 0
	public var xOffset2D = 0
	public var yOffset2D = 0
	public var stackable = false
	public var cost: Int32 = 1
	public var members = false
	public var manwear = -1, manwear2 = -1, manwear3 = -1
	public var womanwear = -1, womanwear2 = -1, womanwear3 = -1
	public var manhead = -1, manhead2 = -1, womanhead = -1, womanhead2 = -1
	public var manWearOffset = [0, 0, 0]
	public var womanWearOffset = [0, 0, 0]
	public var ops: [String?] = [nil, nil, "Take", nil, nil]
	public var iops: [String?] = [nil, nil, nil, nil, "Drop"]
	public var recolours: [Int: Int] = [:]
	public var retextures: [Int: Int] = [:]
	public var recolourPalette: [Int] = []
	/// rt4 `recol_s` in cache order, which `recolourPalette` (`recol_p`) indexes.
	public var recolourSources: [Int] = []
	public var stockMarket = false
	public var dummyItem = 0
	public var certlink = -1, certtemplate = -1
	public var lentLink = -1, lentTemplate = -1
	public var countObj: [Int]?
	public var countCo: [Int]?
	public var resize = [128, 128, 128]
	public var ambient = 0
	public var contrast = 0
	public var team = 0
	public var cursors: [(op: Int, cursor: Int)] = []
	public var params: [Int: ParamValue] = [:]

	public init(id: Int) { self.id = id }

	public static func == (a: ObjType, b: ObjType) -> Bool { a.id == b.id && a.name == b.name && a.model == b.model }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1: model = try p.g2()
		case 2: name = try p.gjstr()
		case 4: zoom2d = try p.g2()
		case 5: xAngle2D = try p.g2()
		case 6: yAngle2D = try p.g2()
		case 7: xOffset2D = try p.g2b()
		case 8: yOffset2D = try p.g2b()
		case 11: stackable = true
		case 12: cost = try p.g4()
		case 16: members = true
		case 23: manwear = try p.g2()
		case 24: manwear2 = try p.g2()
		case 25: womanwear = try p.g2()
		case 26: womanwear2 = try p.g2()
		case 30...34: ops[op - 30] = menuOption(try p.gjstr())
		case 35...39: iops[op - 35] = try p.gjstr()
		case 40:
			let pairs = try decodePairs(&p)
			recolourSources = pairs.map { $0.from }
			for (s, d) in pairs { recolours[s] = d }
		case 41: for (s, d) in try decodePairs(&p) { retextures[s] = d }
		case 42:
			let n = try p.g1()
			recolourPalette = try (0..<n).map { _ in try p.g1b() }
		case 65: stockMarket = true
		case 78: manwear3 = try p.g2()
		case 79: womanwear3 = try p.g2()
		case 90: manhead = try p.g2()
		case 91: womanhead = try p.g2()
		case 92: manhead2 = try p.g2()
		case 93: womanhead2 = try p.g2()
		case 95: zAngle2D = try p.g2()
		case 96: dummyItem = try p.g1()
		case 97: certlink = try p.g2()
		case 98: certtemplate = try p.g2()
		case 100...109:
			if countObj == nil {
				countObj = [Int](repeating: 0, count: 10)
				countCo = [Int](repeating: 0, count: 10)
			}
			countObj![op - 100] = try p.g2()
			countCo![op - 100] = try p.g2()
		case 110: resize[0] = try p.g2()
		case 111: resize[1] = try p.g2()
		case 112: resize[2] = try p.g2()
		case 113: ambient = try p.g1b()
		case 114: contrast = try p.g1b() * 5
		case 115: team = try p.g1()
		case 121: lentLink = try p.g2()
		case 122: lentTemplate = try p.g2()
		case 125: manWearOffset = [try p.g1b(), try p.g1b(), try p.g1b()]
		case 126: womanWearOffset = [try p.g1b(), try p.g1b(), try p.g1b()]
		case 127, 128: cursors.append((try p.g1(), try p.g2()))
		case 129, 130: _ = try p.g1(); _ = try p.g2()
		case 249: try decodeParams(&p, into: &params)
		default: throw UnknownConfigOpcode(type: "obj \(id)", opcode: op)
		}
	}

	public static func location(of id: Int) -> (group: Int, file: Int) { (id >> 8, id & 0xFF) }
}
