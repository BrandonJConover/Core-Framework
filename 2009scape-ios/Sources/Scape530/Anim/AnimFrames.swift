import Foundation

/// Frame base (skeleton): per-transform type and label groups.
/// Port of rt4 `AnimBase` (archive 1, group = base id, file 0).
public struct AnimBase {
	public let id: Int
	public let transforms: Int
	/// Label (vertex group) ids affected by each transform.
	public let bones: [[Int]]
	/// Transform type: 0 origin, 1 translate, 2 rotate, 3 scale, 5 alpha, 7 colour.
	public let types: [Int]
	public let shadow: [Bool]
	public let parts: [Int]

	public init(id: Int, bytes: [UInt8]) throws {
		self.id = id
		var b = Packet(bytes)
		let n = try b.g1()
		transforms = n
		types = try (0..<n).map { _ in try b.g1() }
		shadow = try (0..<n).map { _ in try b.g1() == 1 }
		parts = try (0..<n).map { _ in try b.g2() }
		let counts = try (0..<n).map { _ in try b.g1() }
		bones = try counts.map { c in try (0..<c).map { _ in try b.g1() } }
	}
}

/// One decoded animation frame: sparse transform deltas against a base.
/// Port of rt4 `AnimFrame`. Entry `i` applies to base transform `indices[i]`
/// with deltas `x[i]`, `y[i]`, `z[i]` (type 3 defaults to 128, others to 0;
/// type 2 rotations are already unpacked as in rt4).
public struct AnimFrame {
	public let base: AnimBase
	/// Number of transforms this frame touches (rt4 `length`).
	public let length: Int
	public let transformsAlpha: Bool
	public let transformsColor: Bool
	public let indices: [Int]
	public let x: [Int]
	public let y: [Int]
	public let z: [Int]
	/// Index of the preceding origin transform to apply first, or -1.
	public let prevOriginIndices: [Int]
	public let flags: [Int]

	public init(bytes: [UInt8], base: AnimBase) throws {
		self.base = base
		var header = Packet(bytes)
		var body = Packet(bytes)
		header.offset = 2
		let headerLen = try header.g1()
		body.offset = header.offset + headerLen
		var len = 0
		var prevOrigin = -1, prevUsedOrigin = -1
		var alpha = false, color = false
		var ind = [Int](), xs = [Int](), ys = [Int](), zs = [Int](), prev = [Int](), fl = [Int]()
		for i in 0..<headerLen {
			guard i < base.types.count else { throw Packet.Malformed("anim frame header exceeds base") }
			let type = base.types[i]
			if type == 0 { prevOrigin = i }
			let attrs = try header.g1()
			if attrs > 0 {
				if type == 0 { prevUsedOrigin = i }
				ind.append(i)
				let def = type == 3 ? 128 : 0
				var vx = (attrs & 1) == 0 ? def : try body.gsmart()
				var vy = (attrs & 2) == 0 ? def : try body.gsmart()
				var vz = (attrs & 4) == 0 ? def : try body.gsmart()
				// rt4 stores into shorts
				vx = Int(Int16(truncatingIfNeeded: vx)); vy = Int(Int16(truncatingIfNeeded: vy)); vz = Int(Int16(truncatingIfNeeded: vz))
				fl.append((attrs >> 3) & 3)
				if type == 2 {
					func rot(_ v: Int) -> Int { Int(Int16(truncatingIfNeeded: ((v & 0xFF) << 3) + ((v >> 8) & 7))) }
					vx = rot(vx); vy = rot(vy); vz = rot(vz)
				}
				xs.append(vx); ys.append(vy); zs.append(vz)
				var p = -1
				if type == 1 || type == 2 || type == 3 {
					if prevOrigin > prevUsedOrigin { p = prevOrigin; prevUsedOrigin = prevOrigin }
				} else if type == 5 { alpha = true } else if type == 7 { color = true }
				prev.append(p)
				len += 1
			}
		}
		guard body.offset == bytes.count else { throw Packet.Malformed("anim frame trailing bytes") }
		length = len
		indices = ind; x = xs; y = ys; z = zs; prevOriginIndices = prev; flags = fl
		transformsAlpha = alpha; transformsColor = color
	}
}

/// All frames of one frameset group; `frames[fileId]` (nil where the file id is absent).
/// Port of rt4 `AnimFrameset`.
public struct AnimFrameset {
	public let id: Int
	public let frames: [AnimFrame?]
	public func isAlphaTransformed(_ frame: Int) -> Bool { frames[frame]?.transformsAlpha ?? false }
	public func isColorTransformed(_ frame: Int) -> Bool { frames[frame]?.transformsColor ?? false }
}

extension Packet {
	public struct Malformed: Error, CustomStringConvertible {
		public let description: String
		public init(_ d: String) { description = d }
	}
}

extension ConfigStore {
	public enum AnimArchive {
		public static let frames = 0
		public static let bases = 1
	}

	/// rt4 `SeqTypeList.getAnimFrameset`: `id` is `frame >> 16` from a `SeqType`.
	public func animFrameset(_ id: Int) throws -> AnimFrameset? {
		let key = "animframeset#\(id)"
		if let s = cache[key] as? AnimFrameset { return s }
		let files = try self.files(archive: AnimArchive.frames, group: id)
		if files.isEmpty { return nil }
		var bases: [Int: AnimBase] = [:]
		var frames = [AnimFrame?](repeating: nil, count: (files.keys.max() ?? -1) + 1)
		for (fid, bytes) in files {
			guard bytes.count >= 2 else { throw Packet.Malformed("frame \(id):\(fid) too short") }
			let baseId = Int(bytes[0]) << 8 | Int(bytes[1])
			let base: AnimBase
			if let b = bases[baseId] { base = b } else {
				guard let bb = try file(archive: AnimArchive.bases, group: baseId, file: 0) else { throw Packet.Malformed("missing base \(baseId)") }
				base = try AnimBase(id: baseId, bytes: bb)
				bases[baseId] = base
			}
			frames[fid] = try AnimFrame(bytes: bytes, base: base)
		}
		let s = AnimFrameset(id: id, frames: frames)
		cache[key] = s
		return s
	}

	/// Frame by packed seq frame id (`(group << 16) | file`).
	public func animFrame(packed: Int) throws -> AnimFrame? {
		let f = packed & 0xFFFF
		guard let s = try animFrameset(packed >> 16), f < s.frames.count else { return nil }
		return s.frames[f]
	}
}
