/// Shared helpers for config ("type") decoders. Every decoder follows rt4:
/// read an opcode byte, apply it, stop at opcode 0. A type's `decode(opcode:)`
/// throws `UnknownConfigOpcode` (before reading anything) for opcodes rt4 does
/// not know; the loop then skips that byte like rt4 does and reports it through
/// `onUnknown`, so the cache-wide tests can still catch drift from rt4.
public struct UnknownConfigOpcode: Error, CustomStringConvertible {
	public let type: String
	public let opcode: Int
	public var description: String { "\(type): unknown opcode \(opcode)" }
}

public enum ParamValue: Equatable {
	case int(Int32)
	case string(String)
}

/// Opcode 249 params block (int or string values keyed by a 24-bit param id).
func decodeParams(_ p: inout Packet, into params: inout [Int: ParamValue]) throws {
	let count = try p.g1()
	for _ in 0..<count {
		let isString = try p.g1() == 1
		let key = try p.g3()
		params[key] = isString ? .string(try p.gjstr()) : .int(try p.g4())
	}
}

/// Recolour / retexture pairs (opcodes 40 and 41 on obj/npc/loc).
func decodePairs(_ p: inout Packet) throws -> [(from: Int, to: Int)] {
	let n = try p.g1()
	return try (0..<n).map { _ in (try p.g2(), try p.g2()) }
}

func nullable(_ v: Int) -> Int { v == 65535 ? -1 : v }

/// "Hidden" menu option text in rt4 (`LocalizedText.HIDDEN`).
func menuOption(_ s: String) -> String? { s.lowercased() == "hidden" ? nil : s }

public protocol ConfigType {
	init(id: Int)
	mutating func decode(opcode: Int, _ p: inout Packet) throws
	/// Called once after the terminating 0 (rt4 `postDecode`).
	mutating func postDecode()
}

extension ConfigType {
	public mutating func postDecode() {}

	/// rt4 ignores unknown opcodes without consuming data. The 2009scape cache
	/// has one entry that relies on this: npc 1688 carries `8a ff ff 9f a5 ff`
	/// (opcode 138 from a later revision), which rt4 reads as six no-op opcodes.
	public static func decode(id: Int, _ data: [UInt8], onUnknown: ((Int) -> Void)? = nil) throws -> Self {
		var t = Self(id: id)
		var p = Packet(data)
		while true {
			let op = try p.g1()
			if op == 0 { break }
			do {
				try t.decode(opcode: op, &p)
			} catch let e as UnknownConfigOpcode {
				onUnknown?(e.opcode)
			}
		}
		guard p.remaining == 0 else {
			throw Js5Container.Failure("\(Self.self) \(id): \(p.remaining) trailing bytes after terminator")
		}
		t.postDecode()
		return t
	}
}
