/// Script parameter definition (archive 2 group 11). Port of rt4 `ParamType`: the cs2 type character
/// (`s` = string), and the defaults a missing obj/npc/loc/struct param falls back to.
public struct ParamType: ConfigType, Equatable {
	public let id: Int
	/// cs2 type character (rt4 `type`); 115 ('s') makes the param a string.
	public var type = 0
	public var defaultInt: Int32 = 0
	/// rt4 leaves this null unless opcode 5 is present; scripts then push an empty string.
	public var defaultString = ""

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1: type = try p.g1()
		case 2: defaultInt = try p.g4()
		case 5: defaultString = try p.gjstr()
		default: throw UnknownConfigOpcode(type: "param \(id)", opcode: op)
		}
	}

	/// rt4 `ParamType.isString`.
	public var isString: Bool { type == 115 }

	/// What the cs2 param opcodes push for this param given an entity's param table: the entity's own
	/// value when it has one of the right kind, else this type's default (rt4 `getParam(default, id)`).
	public func resolve(_ params: [Int: ParamValue]) -> ParamValue {
		if isString {
			if case .string(let s)? = params[id] { return .string(s) }
			return .string(defaultString)
		}
		if case .int(let v)? = params[id] { return .int(v) }
		return .int(defaultInt)
	}
}

/// Struct: a bag of params (archive 2 group 26). Port of rt4 `StructType`.
public struct StructType: ConfigType, Equatable {
	public let id: Int
	public var params: [Int: ParamValue] = [:]

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		guard op == 249 else { throw UnknownConfigOpcode(type: "struct \(id)", opcode: op) }
		try decodeParams(&p, into: &params)
	}

	/// rt4 `StructType.getParam(id, defaultInt)`.
	public func param(_ key: Int, default d: Int32) -> Int32 {
		if case .int(let v)? = params[key] { return v }
		return d
	}

	/// rt4 `StructType.getParam(defaultString, id)`.
	public func param(_ key: Int, default d: String) -> String {
		if case .string(let v)? = params[key] { return v }
		return d
	}
}

/// Inventory definition (archive 2 group 5). Port of rt4 `InvType`: only the slot count.
public struct InvType: ConfigType, Equatable {
	public let id: Int
	public var size = 0

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		guard op == 2 else { throw UnknownConfigOpcode(type: "inv \(id)", opcode: op) }
		size = try p.g2()
	}
}

/// Player variable definition (archive 2 group 16). Port of rt4 `VarpType`. A non-zero `clientCode`
/// marks a varp the client reacts to (see `VarpClientCode`) and that survives a varp reset.
public struct VarpType: ConfigType, Equatable {
	public let id: Int
	public var clientCode = 0

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		guard op == 5 else { throw UnknownConfigOpcode(type: "varp \(id)", opcode: op) }
		clientCode = try p.g2()
	}
}

/// Scene light definition (archive 2 group 31). Port of rt4 `LightType`; rt4 keeps the fields unnamed
/// (`anInt2865`..`anInt2873`), so they are named here by opcode.
public struct LightType: ConfigType, Equatable {
	public let id: Int
	/// opcode 1 (rt4 `anInt2865`)
	public var opcode1 = 0
	/// opcode 2 (rt4 `anInt2873`)
	public var opcode2 = 2048
	/// opcode 3 (rt4 `anInt2867`)
	public var opcode3 = 2048
	/// opcode 4, signed (rt4 `anInt2872`)
	public var opcode4 = 0

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1: opcode1 = try p.g1()
		case 2: opcode2 = try p.g2()
		case 3: opcode3 = try p.g2()
		case 4: opcode4 = try p.g2b()
		default: throw UnknownConfigOpcode(type: "light \(id)", opcode: op)
		}
	}
}

/// Mouse cursor (archive 2 group 33). Port of rt4 `CursorType`; `spriteId` indexes the sprite archive.
public struct CursorType: ConfigType, Equatable {
	public let id: Int
	public var spriteId = 0
	public var hotSpotX = 0
	public var hotSpotY = 0

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1: spriteId = try p.g2()
		case 2:
			hotSpotX = try p.g1()
			hotSpotY = try p.g1()
		default: throw UnknownConfigOpcode(type: "cursor \(id)", opcode: op)
		}
	}
}

/// Minimap scene icon (archive 2 group 34). Port of rt4 `MsiType` (map scene): `spriteId` is a sprite
/// group in archive 8 (-1 for none), `tint` a 0xRRGGBB multiplied into the palette (rt4 `anInt11`) and
/// `stretch` fills the loc's footprint (rt4 `aBoolean2`).
public struct MsiType: ConfigType, Equatable {
	public let id: Int
	public var spriteId = 0
	/// opcode 2 (rt4 `anInt11`), a 24-bit colour.
	public var tint = 0
	public var stretch = false

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1: spriteId = try p.g2()
		case 2: tint = try p.g3()
		case 3: stretch = true
		case 4: spriteId = -1
		default: throw UnknownConfigOpcode(type: "msi \(id)", opcode: op)
		}
	}
}

extension ConfigStore {
	public func param(_ id: Int) throws -> ParamType? { try load(ParamType.self, id, archive: Archive.configs, group: ConfigGroup.param, file: id) }
	public func structType(_ id: Int) throws -> StructType? { try load(StructType.self, id, archive: Archive.configs, group: ConfigGroup.structs, file: id) }
	public func inv(_ id: Int) throws -> InvType? { try load(InvType.self, id, archive: Archive.configs, group: ConfigGroup.inv, file: id) }
	public func varpType(_ id: Int) throws -> VarpType? { try load(VarpType.self, id, archive: Archive.configs, group: ConfigGroup.varp, file: id) }
	public func light(_ id: Int) throws -> LightType? { try load(LightType.self, id, archive: Archive.configs, group: ConfigGroup.light, file: id) }
	public func cursor(_ id: Int) throws -> CursorType? { try load(CursorType.self, id, archive: Archive.configs, group: ConfigGroup.cursor, file: id) }
	public func msi(_ id: Int) throws -> MsiType? { try load(MsiType.self, id, archive: Archive.configs, group: ConfigGroup.msi, file: id) }

	/// Every varp id the cache defines (rt4 `VarpTypeList.anInt4043` is the group's capacity).
	public func varpIds() throws -> [Int] { try files(archive: Archive.configs, group: ConfigGroup.varp).keys.sorted() }
}

/// Quick chat category (archive 24 group 0 for ids below 0x8000, archive 25 for the rest with id & 0x7FFF).
/// Port of rt4 `QuickChatCatType`; ids from archive 25 get their child ids tagged with 0x8000
/// (rt4 `method465`), done here by `QuickChatCatType.tagged()`.
public struct QuickChatCatType: ConfigType, Equatable {
	public let id: Int
	public var description = ""
	public var subcategories: [Int] = []
	public var subcategoryShortcuts: [Int] = []
	public var phrases: [Int] = []
	public var phraseShortcuts: [Int] = []

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1: description = try p.gjstr()
		case 2:
			let n = try p.g1()
			subcategories = []; subcategoryShortcuts = []
			for _ in 0..<n {
				subcategories.append(try p.g2())
				subcategoryShortcuts.append(try p.g1() & 0xFF)
			}
		case 3:
			let n = try p.g1()
			phrases = []; phraseShortcuts = []
			for _ in 0..<n {
				phrases.append(try p.g2())
				phraseShortcuts.append(try p.g1() & 0xFF)
			}
		case 4: break
		default: throw UnknownConfigOpcode(type: "quickchatcat \(id)", opcode: op)
		}
	}

	/// rt4 `QuickChatCatType.method465`: marks child ids as belonging to the secondary archive.
	public func tagged() -> QuickChatCatType {
		var c = self
		c.phrases = phrases.map { $0 | 0x8000 }
		c.subcategories = subcategories.map { $0 | 0x8000 }
		return c
	}
}

/// Quick chat phrase (archive 24 group 1, or archive 25 for ids from 0x8000). Port of rt4 `QuickChatPhraseType`.
public struct QuickChatPhraseType: ConfigType, Equatable {
	public let id: Int
	/// The text pieces around the dynamic slots (rt4 splits the string on `<`, char 60).
	public var textParts: [String] = []
	public var automaticResponses: [Int] = []
	/// Dynamic commands (rt4 `anIntArray71`) and their params (`anIntArrayArray5`).
	public var dynamicCommands: [Int] = []
	public var dynamicParams: [[Int]] = []
	/// rt4 `aBoolean60`: cleared by opcode 4.
	public var searchable = true

	/// rt4 `anIntArray412`: params per dynamic command.
	static let paramCounts = [1, 0, 0, 0, 1, 0, 2, 1, 1, 1, 0, 2, 0, 0, 1, 0]

	public init(id: Int) { self.id = id }

	public mutating func decode(opcode op: Int, _ p: inout Packet) throws {
		switch op {
		case 1: textParts = try p.gjstr().split(separator: "<", omittingEmptySubsequences: false).map(String.init)
		case 2:
			let n = try p.g1()
			automaticResponses = try (0..<n).map { _ in try p.g2() }
		case 3:
			let n = try p.g1()
			dynamicCommands = []; dynamicParams = []
			for _ in 0..<n {
				let cmd = try p.g2()
				guard cmd >= 0, cmd < Self.paramCounts.count else { throw Js5Container.Failure("quickchat phrase \(id): bad dynamic command \(cmd)") }
				dynamicCommands.append(cmd)
				dynamicParams.append(try (0..<Self.paramCounts[cmd]).map { _ in try p.g2() })
			}
		case 4: searchable = false
		default: throw UnknownConfigOpcode(type: "quickchatphrase \(id)", opcode: op)
		}
	}

	/// rt4 `method763`: marks response ids as belonging to the secondary archive.
	public func tagged() -> QuickChatPhraseType {
		var c = self
		c.automaticResponses = automaticResponses.map { $0 | 0x8000 }
		return c
	}
}

extension ConfigStore {
	/// rt4 `QuickChatCatTypeList.get`.
	public func quickChatCat(_ id: Int) throws -> QuickChatCatType? {
		try quickChat(QuickChatCatType.self, id, group: 0) { $0.tagged() }
	}

	/// rt4 `QuickChatPhraseTypeList.get`.
	public func quickChatPhrase(_ id: Int) throws -> QuickChatPhraseType? {
		try quickChat(QuickChatPhraseType.self, id, group: 1) { $0.tagged() }
	}

	private func quickChat<T: ConfigType>(_ t: T.Type, _ id: Int, group: Int, tag: (T) -> T) throws -> T? {
		let key = "\(T.self)#\(id)"
		if let v = cache[key] as? T { return v }
		let secondary = id >= 0x8000
		guard let data = try file(archive: secondary ? Archive.quickChatSecondary : Archive.quickChatPrimary, group: group, file: id & 0x7FFF) else { return nil }
		var v = try T.decode(id: id, data)
		if secondary { v = tag(v) }
		cache[key] = v
		return v
	}
}
