/// Scenery/object definition (archive 16, group id >>> 8, file id & 0xFF).
/// Port of rt4 `LocType.decode` and `postDecode`.
public struct LocType: ConfigType, Equatable {
	public static let centrepieceStraight = 10

	public let id: Int
	public var models: [Int]?
	/// Shape per model (opcode 1); nil when the models apply to any shape (opcode 5).
	public var shapes: [Int]?
	public var name = "null"
	public var width = 1
	public var length = 1
	public var blockWalk = 2
	public var blockRange = true
	public var interactable = -1
	public var hillskewType = 0
	public var hillskewAmount = -1
	public var shareLight = false
	public var occlude = false
	public var anim = -1
	public var wallOffset = 16
	public var ambient = 0
	public var contrast = 0
	public var ops: [String?] = [nil, nil, nil, nil, nil]
	public var recolours: [Int: Int] = [:]
	public var retextures: [Int: Int] = [:]
	public var recolourPalette: [Int] = []
	public var mapFunction = -1
	public var mirror = false
	public var active = true
	public var resize = [128, 128, 128]
	public var blockSides = 0
	public var offset = [0, 0, 0]
	public var forceDecor = false
	public var breakRouteFinding = false
	public var supportItems = -1
	public var multiVarbit = -1
	public var multiVarp = -1
	public var multiLocs: [Int]?
	public var bgSound = -1
	public var bgSoundRange = 0
	public var bgSoundInterval = (min: 0, max: 0)
	public var bgSounds: [Int]?
	public var render = false
	public var castShadow = true
	public var allowRandomizedAnimation = true
	public var members = false
	public var hasAnimation = false
	public var mapSceneRotated = false
	public var cursors: [(op: Int, cursor: Int)] = []
	public var mapSceneAngleOffset = 0
	public var mapScene = -1
	public var flags90and98 = (false, false)
	public var params: [Int: ParamValue] = [:]

	public init(id: Int) { self.id = id }

	public static func == (a: LocType, b: LocType) -> Bool { a.id == b.id && a.name == b.name && a.models == b.models }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1:
			let n = try p.g1()
			if n > 0 {
				if models == nil {
					var m: [Int] = [], s: [Int] = []
					for _ in 0..<n {
						m.append(try p.g2())
						s.append(try p.g1())
					}
					models = m
					shapes = s
				} else {
					p.offset += n * 3
				}
			}
		case 2: name = try p.gjstr()
		case 5:
			let n = try p.g1()
			if n > 0 {
				if models == nil {
					models = try (0..<n).map { _ in try p.g2() }
					shapes = nil
				} else {
					p.offset += n * 2
				}
			}
		case 14: width = try p.g1()
		case 15: length = try p.g1()
		case 17: blockWalk = 0; blockRange = false
		case 18: blockRange = false
		case 19: interactable = try p.g1()
		case 21: hillskewType = 1
		case 22: shareLight = true
		case 23: occlude = true
		case 24: anim = nullable(try p.g2())
		case 27: blockWalk = 1
		case 28: wallOffset = try p.g1()
		case 29: ambient = try p.g1b()
		case 39: contrast = try p.g1b() * 5
		case 30...34: ops[op - 30] = menuOption(try p.gjstr())
		case 40: for (s, d) in try decodePairs(&p) { recolours[s] = d }
		case 41: for (s, d) in try decodePairs(&p) { retextures[s] = d }
		case 42:
			let n = try p.g1()
			recolourPalette = try (0..<n).map { _ in try p.g1b() }
		case 60: mapFunction = try p.g2()
		case 62: mirror = true
		case 64: active = false
		case 65: resize[0] = try p.g2()
		case 66: resize[1] = try p.g2()
		case 67: resize[2] = try p.g2()
		case 69: blockSides = try p.g1()
		case 70: offset[0] = try p.g2b()
		case 71: offset[1] = try p.g2b()
		case 72: offset[2] = try p.g2b()
		case 73: forceDecor = true
		case 74: breakRouteFinding = true
		case 75: supportItems = try p.g1()
		case 77, 92:
			multiVarbit = nullable(try p.g2())
			multiVarp = nullable(try p.g2())
			var fallback = -1
			if op == 92 { fallback = nullable(try p.g2()) }
			let n = try p.g1()
			var list = try (0...n).map { _ in nullable(try p.g2()) }
			list.append(fallback)
			multiLocs = list
		case 78:
			bgSound = try p.g2()
			bgSoundRange = try p.g1()
		case 79:
			bgSoundInterval = (try p.g2(), try p.g2())
			bgSoundRange = try p.g1()
			let n = try p.g1()
			bgSounds = try (0..<n).map { _ in try p.g2() }
		case 81:
			hillskewType = 2
			hillskewAmount = try p.g1() * 256
		case 82: render = true
		case 88: castShadow = false
		case 89: allowRandomizedAnimation = false
		case 90: flags90and98.0 = true
		case 91: members = true
		case 93:
			hillskewType = 3
			hillskewAmount = try p.g2()
		case 94: hillskewType = 4
		case 95: hillskewType = 5
		case 96: hasAnimation = true
		case 97: mapSceneRotated = true
		case 98: flags90and98.1 = true
		case 99, 100: cursors.append((try p.g1(), try p.g2()))
		case 101: mapSceneAngleOffset = try p.g1()
		case 102: mapScene = try p.g2()
		case 249: try decodeParams(&p, into: &params)
		default: throw UnknownConfigOpcode(type: "loc \(id)", opcode: op)
		}
	}

	public mutating func postDecode() {
		if interactable == -1 {
			interactable = 0
			if models != nil && (shapes == nil || shapes![0] == LocType.centrepieceStraight) {
				interactable = 1
			}
			if ops.contains(where: { $0 != nil }) { interactable = 1 }
		}
		if supportItems == -1 {
			supportItems = blockWalk == 0 ? 0 : 1
		}
	}

	public static func location(of id: Int) -> (group: Int, file: Int) { (id >> 8, id & 0xFF) }
}
