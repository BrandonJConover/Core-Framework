import Foundation

/// Quick chat phrase runtime: encoding and decoding of dynamic phrase values, ported from
/// rt4 `QuickChatPhraseType` / `QuickChatPhraseTypeList` / `Js5QuickChatCommandDecoder`.
extension QuickChatPhraseType {
	/// rt4 `DYNAMIC_COMMAND_ENCODE_BYTES`: bytes a dynamic command's value takes in an outgoing message.
	static let encodeBytes = [2, 2, 4, 0, 1, 8, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0]
	/// rt4 `anIntArray51`: bytes a dynamic command's value takes in an incoming message.
	static let decodeBytes = [2, 2, 4, 2, 1, 8, 4, 1, 4, 4, 2, 1, 1, 1, 4, 1]

	/// rt4 `getDynamicCommandCount`.
	public var dynamicCommandCount: Int { dynamicCommands.count }

	/// rt4 `getDynamicCommand`: -1 when out of range.
	public func dynamicCommand(_ i: Int) -> Int { i >= 0 && i < dynamicCommands.count ? dynamicCommands[i] : -1 }

	/// rt4 `getDynamicCommandParam(param, command)`: -1 when out of range.
	public func dynamicCommandParam(_ param: Int, _ command: Int) -> Int {
		guard command >= 0, command < dynamicParams.count, param >= 0, param < dynamicParams[command].count else { return -1 }
		return dynamicParams[command][param]
	}

	/// rt4 `getText`: the text pieces joined with "..." (rt4 `aClass100_231`, the obfuscated literal `)3)3)3`).
	public var text: String { textParts.joined(separator: "...") }

	/// rt4 `encodeMessage`: the dynamic values of an outgoing phrase, each as many big-endian bytes as its command takes.
	public func encodeMessage(_ values: [Int32]) -> [UInt8] {
		guard !dynamicCommands.isEmpty else { return [] }
		var out: [UInt8] = []
		var i = 0
		while i < dynamicCommands.count && i < values.count {
			let n = Self.encodeBytes[dynamicCommands[i]]
			if n > 0 {
				let v = Int64(values[i])
				for shift in stride(from: (n - 1) * 8, through: 0, by: -8) { out.append(UInt8(truncatingIfNeeded: v >> Int64(shift))) }
			}
			i += 1
		}
		return out
	}

	/// rt4 `decodeMessage`: builds the phrase text from the dynamic values that follow the phrase id.
	public func decodeMessage(_ p: inout Packet, store: ConfigStore) throws -> String {
		var out = ""
		for (i, cmd) in dynamicCommands.enumerated() {
			guard i < textParts.count else { throw Js5Container.Failure("quickchat phrase \(id): missing text part \(i)") }
			out += textParts[i]
			var value: Int64 = 0
			for _ in 0..<Self.decodeBytes[cmd] { value = (value << 8) | Int64(try p.g1()) }
			out += QuickChat.dynamicText(command: cmd, params: dynamicParams[i], value: value, store: store)
		}
		out += textParts.last ?? ""
		return out
	}
}

/// rt4 `QuickChatPhrase`: the phrase being composed by the chat scripts (ops 5058, 5068, 5069).
public struct QuickChatPhrase: Equatable {
	public var id: Int
	public var values: [Int32]
}

public enum QuickChat {
	/// rt4 `Js5QuickChatCommandDecoder.decode` with the numeric fallback (`JagString.method2929`).
	static func dynamicText(command: Int, params: [Int], value: Int64, store: ConfigStore) -> String {
		func enumString() -> String? {
			guard let first = params.first, let e = try? store.enumType(first) else { return nil }
			if case .string(let s)? = e.values[Int32(truncatingIfNeeded: value)] { return s }
			return e.defaultString
		}
		switch command {
		case 0, 6, 7, 11:
			if let s = enumString() { return s }
		case 1, 10:
			if let o = try? store.obj(Int(Int32(truncatingIfNeeded: value))) { return o.name }
		default: break
		}
		return String(value)
	}

	/// The text of a received phrase: `values` are the bytes after the phrase id. nil for an unknown phrase.
	public static func message(phrase: Int, values: [UInt8], store: ConfigStore) -> String? {
		guard let type = (try? store.quickChatPhrase(phrase)) ?? nil else { return nil }
		var p = Packet(values)
		return try? type.decodeMessage(&p, store: store)
	}

	/// The packet for ops 5059 / 5061 (public, clan): `[kind, phrase id, values...]` goes in the var-byte body.
	static func phraseBody(_ phrase: QuickChatPhrase, store: ConfigStore) -> [UInt8] {
		guard let type = try? store.quickChatPhrase(phrase.id) else { return [] }
		return type.encodeMessage(phrase.values)
	}

	/// rt4 `Find.findQuickChatPhrases`: searchable phrases whose text contains `needle`, sorted as rt4 sorts them.
	/// nil when more than 50 match (rt4 sets index -1 and clears the results).
	static func search(secondary: Bool, needle: String, store: ConfigStore) -> [Int]? {
		let lowered = needle.lowercased()
		let start = secondary ? 0x8000 : 0
		let count = store.quickChatPhraseCount(secondary: secondary)
		var ids: [Int] = [], texts: [String] = []
		var id = start
		while id < start + count {
			if let t = try? store.quickChatPhrase(id), t.searchable, lowered.isEmpty || t.text.lowercased().contains(lowered) {
				if ids.count >= 50 { return nil }
				ids.append(id)
				texts.append(t.text)
			}
			id += 1
		}
		var bytes = texts.map { Cp1252.encode($0) }
		sort(&ids, &bytes, 0, ids.count - 1)
		return ids
	}

	/// rt4 `Find.method1307`: quicksort of ids by their text; the tie-break `compare < (i & 1)` is rt4's.
	static func sort(_ ids: inout [Int], _ keys: inout [[UInt8]], _ lo: Int, _ hi: Int) {
		if hi <= lo { return }
		var mid = lo
		let pivotIndex = (lo + hi) / 2
		let pivot = keys[pivotIndex], pivotId = ids[pivotIndex]
		keys.swapAt(pivotIndex, hi); ids.swapAt(pivotIndex, hi)
		for i in lo..<hi where compare(keys[i], pivot) < (i & 1) {
			keys.swapAt(i, mid); ids.swapAt(i, mid)
			mid += 1
		}
		keys[hi] = keys[mid]; ids[hi] = ids[mid]
		keys[mid] = pivot; ids[mid] = pivotId
		sort(&ids, &keys, lo, mid - 1)
		sort(&ids, &keys, mid + 1, hi)
	}

	/// rt4 `JagString.method3139(other)` seen from `a`: byte-wise, shorter first.
	static func compare(_ a: [UInt8], _ b: [UInt8]) -> Int {
		for i in 0..<min(a.count, b.count) {
			if a[i] < b[i] { return -1 }
			if b[i] < a[i] { return 1 }
		}
		return b.count > a.count ? -1 : (b.count >= a.count ? 0 : 1)
	}
}
