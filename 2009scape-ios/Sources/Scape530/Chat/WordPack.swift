import Foundation

/// Chat text on the wire (rt4 `WordPack`, `Protocol.formatChatMessage`,
/// `JagString.encodeMessage`, `Font.escape`).
public enum WordPack {
	/// The huffman table's location in the cache: archive 10, one group, file named "huffman"
	/// (rt4 `client.HUFFMAN_GROUP`, `js5Archive10.fetchFile("", "huffman")`).
	public static func loadCodec(_ store: ConfigStore) throws -> HuffmanCodec? {
		if let c = store.cache["huffman"] as? HuffmanCodec { return c }
		let index = try store.index(10)
		for group in index.groupIds {
			let files = try store.files(archive: 10, group: group)
			let named = index.file(named: "huffman", inGroup: group).flatMap { files[$0] }
			if let data = named ?? (index.groupIds.count == 1 ? files[0] : nil) {
				let codec = HuffmanCodec(bits: data)
				store.cache["huffman"] = codec
				return codec
			}
		}
		return nil
	}

	/// rt4 `WordPack.encode`: `psmarts(length)` followed by the huffman bytes.
	public static func encode(_ text: String, codec: HuffmanCodec) throws -> [UInt8] {
		let raw = Cp1252.encode(text)
		let n = min(raw.count, 0x7FFF)
		var p = Packet(capacity: raw.count + 4)
		if n < 128 { p.p1(n) } else { p.p2(n + 0x8000) }
		p.pdata(try codec.encode(raw, length: n))
		return p.written
	}

	/// rt4 `Protocol.method4350` (`formatChatMessage`): `gsmarts` length then huffman bytes.
	/// A failure yields "Cabbage", as rt4's catch does.
	public static func decode(_ data: [UInt8], codec: HuffmanCodec) -> String {
		var p = Packet(data)
		do {
			var n = try p.gsmarts()
			if n > 32767 { n = 32767 }
			let (bytes, _) = try codec.decode(data, at: p.offset, length: n)
			// rt4 `JagString.decodeString` drops NUL bytes.
			return Cp1252.decode(bytes.filter { $0 != 0 })
		} catch {
			return "Cabbage"
		}
	}

	/// rt4 `JagString.encodeMessage`: sentence-case normalisation (first letter of a sentence upper,
	/// other letters lower). Operates on cp1252 bytes like rt4.
	public static func sentenceCase(_ text: String) -> String {
		var state = 2
		var out = Cp1252.encode(text)
		for i in 0..<out.count {
			var c = out[i]
			let lower = (c >= 97 && c <= 122) || (c >= 0xE0 && c <= 0xFE && c != 0xF7)
			let upper = (c >= 65 && c <= 90) || (c >= 0xC0 && c <= 0xDE && c != 0xD7)
			if lower {
				if state == 2 { c = c &- 32 }
				state = 0
			} else if upper {
				if state == 0 { c = c &+ 32 }
				state = 0
			} else if c == 46 || c == 33 || c == 63 {
				state = 2
			} else if c != 32 {
				state = 1
			} else if state != 2 {
				state = 1
			}
			out[i] = c
		}
		return Cp1252.decode(out)
	}

	/// rt4 `Font.escape`: `<` and `>` become the `<lt>` / `<gt>` entities so chat cannot inject tags.
	public static func escape(_ text: String) -> String {
		var out = ""
		for ch in text {
			switch ch {
			case "<": out += "<lt>"
			case ">": out += "<gt>"
			default: out.append(ch)
			}
		}
		return out
	}

	/// What rt4 does to a decoded chat line: sentence case, then escape.
	public static func display(_ decoded: String) -> String { escape(sentenceCase(decoded)) }

	/// rt4 `Base37.decode37(..).toTitleCase()`: underscores become spaces, each word capitalised.
	public static func displayName(_ name37: Int64) -> String {
		guard let n = Base37.decode(name37) else { return "" }
		var out = "", capNext = true
		for ch in n {
			if ch == "_" { out.append(" "); capNext = true; continue }
			out.append(capNext ? Character(ch.uppercased()) : ch)
			capNext = false
		}
		return out
	}

	/// rt4 `Protocol.getChatIcon`: the `<img=n>` crown for staff.
	public static func chatIcon(rights: Int) -> String {
		switch rights {
		case 1, 2, 3, 5, 6, 7: return "<img=\(rights == 3 ? 2 : rights - 1)>"
		default: return ""
		}
	}
}
