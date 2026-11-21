/// Overlay floor (archive 2 group 4). Port of rt4 `FloType.decode`. Colours stay as raw RGB.
public struct FloType: ConfigType, Equatable {
	public let id: Int
	public var rgb = 0
	public var texture = -1
	public var occludeUnderlay = true
	public var secondaryRgb = -1
	public var hideUnderlay = false // opcode 8 (rt4 anInt865 = id)
	public var opcode9 = 1190
	public var opcode10 = true
	public var textureBrightness = 8
	public var blendTexture = false
	public var waterRgb = 0x122b3d
	public var waterOpacity = 16

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1: rgb = try p.g3()
		case 2: texture = try p.g1()
		case 3: texture = nullable(try p.g2())
		case 5: occludeUnderlay = false
		case 7: secondaryRgb = try p.g3()
		case 8: hideUnderlay = true
		case 9: opcode9 = try p.g2()
		case 10: opcode10 = false
		case 11: textureBrightness = try p.g1()
		case 12: blendTexture = true
		case 13: waterRgb = try p.g3()
		case 14: waterOpacity = try p.g1()
		default: throw UnknownConfigOpcode(type: "flo \(id)", opcode: op)
		}
	}
}

/// Underlay floor (archive 2 group 1). Port of rt4 `FluType.decode`.
public struct FluType: ConfigType, Equatable {
	public let id: Int
	public var rgb = 0
	public var texture = -1
	public var opcode3 = 512
	public var blockShadow = true

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1: rgb = try p.g3()
		case 2: texture = nullable(try p.g2())
		case 3: opcode3 = try p.g2()
		case 4: blockShadow = false
		default: throw UnknownConfigOpcode(type: "flu \(id)", opcode: op)
		}
	}
}

/// Identity kit: body part models for player appearance (archive 2 group 3).
public struct IdkType: ConfigType, Equatable {
	public let id: Int
	public var bodyPart = -1
	public var models: [Int] = []
	public var disabled = false
	public var recolours: [Int: Int] = [:]
	public var retextures: [Int: Int] = [:]
	public var headModels = [Int](repeating: -1, count: 5)

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1: bodyPart = try p.g1()
		case 2:
			let n = try p.g1()
			models = try (0..<n).map { _ in try p.g2() }
		case 3: disabled = true
		case 40: for (s, d) in try decodePairs(&p) { recolours[s] = d }
		case 41: for (s, d) in try decodePairs(&p) { retextures[s] = d }
		case 60..<70:
			if op - 60 >= headModels.count { headModels += [Int](repeating: -1, count: op - 60 - headModels.count + 1) }
			headModels[op - 60] = try p.g2()
		default: throw UnknownConfigOpcode(type: "idk \(id)", opcode: op)
		}
	}
}

/// Graphic effect (archive 21, group id >>> 8, file id & 0xFF).
public struct SpotAnimType: ConfigType, Equatable {
	public let id: Int
	public var model = 0
	public var seq = -1
	public var resizeXZ = 128
	public var resizeY = 128
	public var angle = 0
	public var ambient = 0
	public var contrast = 0
	public var opcode9 = false
	public var recolours: [Int: Int] = [:]
	public var retextures: [Int: Int] = [:]

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1: model = try p.g2()
		case 2: seq = try p.g2()
		case 4: resizeXZ = try p.g2()
		case 5: resizeY = try p.g2()
		case 6: angle = try p.g2()
		case 7: ambient = try p.g1()
		case 8: contrast = try p.g1()
		case 9: opcode9 = true
		case 40: for (s, d) in try decodePairs(&p) { recolours[s] = d }
		case 41: for (s, d) in try decodePairs(&p) { retextures[s] = d }
		default: throw UnknownConfigOpcode(type: "spotanim \(id)", opcode: op)
		}
	}

	public static func location(of id: Int) -> (group: Int, file: Int) { (id >> 8, id & 0xFF) }
}

/// Base animation set: idle/walk/run/turn animations per body (archive 2 group 32).
public struct BasType: ConfigType, Equatable {
	public let id: Int
	public var idle = -1, walk = -1
	public var slowWalk = -1, slowWalkFullTurn = -1, slowWalkCCW = -1, slowWalkCW = -1
	public var run = -1, runFullTurn = -1, runCCW = -1, runCW = -1
	public var walkFullTurn = -1, walkCCW = -1, walkCW = -1
	public var standingCCW = -1, standingCW = -1
	public var opcode26 = (0, 0)
	/// Per body slot: rotate x/y/z, translate x/y/z.
	public var modelRotateTranslate: [Int: [Int]] = [:]
	public var yaw = (acceleration: 0, maxSpeed: 0)
	public var roll = (acceleration: 0, maxSpeed: 0, target: 0)
	public var pitch = (acceleration: 0, maxSpeed: 0, target: 0)
	/// rt4 default -1 (no acceleration: the plain 4/8/16-per-cycle steps). 0 would pin the speed at 1 fine unit a cycle.
	public var movementAcceleration = -1

	public init(id: Int) { self.id = id }

	public static func == (a: BasType, b: BasType) -> Bool { a.id == b.id && a.idle == b.idle && a.walk == b.walk }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1:
			idle = nullable(try p.g2())
			walk = nullable(try p.g2())
		case 2: slowWalk = try p.g2()
		case 3: slowWalkFullTurn = try p.g2()
		case 4: slowWalkCCW = try p.g2()
		case 5: slowWalkCW = try p.g2()
		case 6: run = try p.g2()
		case 7: runFullTurn = try p.g2()
		case 8: runCCW = try p.g2()
		case 9: runCW = try p.g2()
		case 26: opcode26 = (try p.g1() * 4, try p.g1() * 4)
		case 27:
			let slot = try p.g1()
			modelRotateTranslate[slot] = try (0..<6).map { _ in try p.g2b() }
		case 29: yaw.acceleration = try p.g1()
		case 30: yaw.maxSpeed = try p.g2()
		case 31: roll.acceleration = try p.g1()
		case 32: roll.maxSpeed = try p.g2()
		case 33: roll.target = try p.g2b()
		case 34: pitch.acceleration = try p.g1()
		case 35: pitch.maxSpeed = try p.g2()
		case 36: pitch.target = try p.g2b()
		case 37: movementAcceleration = try p.g1()
		case 38: standingCCW = try p.g2()
		case 39: standingCW = try p.g2()
		case 40: walkFullTurn = try p.g2()
		case 41: walkCCW = try p.g2()
		case 42: walkCW = try p.g2()
		case 43, 44, 45: _ = try p.g2()
		default: throw UnknownConfigOpcode(type: "bas \(id)", opcode: op)
		}
	}
}

/// Bit range inside a varp (archive 22, group id >>> 10, file id & 0x3FF).
public struct VarbitType: ConfigType, Equatable {
	public let id: Int
	public var varp = 0
	public var startBit = 0
	public var endBit = 0

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		guard op == 1 else { throw UnknownConfigOpcode(type: "varbit \(id)", opcode: op) }
		varp = try p.g2()
		startBit = try p.g1()
		endBit = try p.g1()
	}

	public func value(in varpValue: Int32) -> Int32 {
		let width = endBit - startBit
		let mask: UInt32 = width >= 31 ? 0xFFFF_FFFF : (1 << UInt32(width + 1)) - 1
		return Int32(bitPattern: (UInt32(bitPattern: varpValue) >> UInt32(startBit)) & mask)
	}

	public static func location(of id: Int) -> (group: Int, file: Int) { (id >> 10, id & 0x3FF) }
}

/// Key/value table used by client scripts (archive 17, group id >>> 8, file id & 0xFF).
public struct EnumType: ConfigType, Equatable {
	public let id: Int
	/// cs2 type chars as bytes ('i', 's', 'o', ...).
	public var keyType = 0
	public var valueType = 0
	public var defaultString = "null"
	public var defaultInt: Int32 = 0
	public var values: [Int32: ParamValue] = [:]

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1: keyType = try p.g1()
		case 2: valueType = try p.g1()
		case 3: defaultString = try p.gjstr()
		case 4: defaultInt = try p.g4()
		case 5, 6:
			let n = try p.g2()
			for _ in 0..<n {
				let k = try p.g4()
				values[k] = op == 5 ? .string(try p.gjstr()) : .int(try p.g4())
			}
		default: throw UnknownConfigOpcode(type: "enum \(id)", opcode: op)
		}
	}

	public static func location(of id: Int) -> (group: Int, file: Int) { (id >> 8, id & 0xFF) }
}
