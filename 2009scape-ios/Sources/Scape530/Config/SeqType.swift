/// Animation sequence (archive 20, group id >>> 7, file id & 0x7F). Port of rt4 `SeqType.decode`.
public struct SeqType: ConfigType, Equatable {
	public let id: Int
	public var frameDelays: [Int] = []
	/// Packed frame ids: (frameset group << 16) | frame file.
	public var frames: [Int] = []
	public var replayOffset = -1
	public var frameGroup: Set<Int>?
	public var stretches = false
	public var priority = 5
	public var mainhand = -1
	public var offhand = -1
	public var replayCount = 99
	public var loopType = -1
	public var moveType = -1
	public var exactMove = 2
	/// Second skeletal frameset (opcode 12), packed like `frames`.
	public var frameset: [Int]?
	public var soundEffects: [[Int]?]?
	public var flag14 = false
	public var tween = false
	public var flag16 = false

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1:
			let n = try p.g2()
			frameDelays = try (0..<n).map { _ in try p.g2() }
			var f = try (0..<n).map { _ in try p.g2() }
			for i in 0..<n { f[i] += try p.g2() << 16 }
			frames = f
		case 2: replayOffset = try p.g2()
		case 3:
			let n = try p.g1()
			frameGroup = Set(try (0..<n).map { _ in try p.g1() })
		case 4: stretches = true
		case 5: priority = try p.g1()
		case 6: mainhand = try p.g2()
		case 7: offhand = try p.g2()
		case 8: replayCount = try p.g1()
		case 9: loopType = try p.g1()
		case 10: moveType = try p.g1()
		case 11: exactMove = try p.g1()
		case 12:
			let n = try p.g1()
			var f = try (0..<n).map { _ in try p.g2() }
			for i in 0..<n { f[i] += try p.g2() << 16 }
			frameset = f
		case 13:
			let n = try p.g2()
			var list: [[Int]?] = []
			for _ in 0..<n {
				let c = try p.g1()
				if c > 0 {
					var s = [try p.g3()]
					for _ in 1..<c { s.append(try p.g2()) }
					list.append(s)
				} else {
					list.append(nil)
				}
			}
			soundEffects = list
		case 14: flag14 = true
		case 15: tween = true
		case 16: flag16 = true
		default: throw UnknownConfigOpcode(type: "seq \(id)", opcode: op)
		}
	}

	public static func location(of id: Int) -> (group: Int, file: Int) { (id >> 7, id & 0x7F) }
}
