/// rt4 `JagString.encode37` / `Base37.decode37`: usernames as base-37 longs.
public enum Base37 {
	public static func encode(_ name: String) -> Int64 {
		var v: Int64 = 0
		for (i, u) in name.unicodeScalars.enumerated() where i < 12 {
			let c = u.value
			v &*= 37
			switch c {
			case 65...90: v &+= Int64(c) + 1 - 65
			case 97...122: v &+= Int64(c) + 1 - 97
			case 48...57: v &+= Int64(c) + 27 - 48
			default: break
			}
		}
		while v % 37 == 0 && v != 0 {
			v /= 37
		}
		return v
	}

	static let alphabet: [Character] = Array("_abcdefghijklmnopqrstuvwxyz0123456789")

	/// Decodes to the lowercase underscore form (display formatting is a UI concern).
	public static func decode(_ value: Int64) -> String? {
		guard value > 0, value < 6_582_952_005_840_035_281 else { return nil }
		guard value % 37 != 0 else { return nil }
		var v = value
		var out: [Character] = []
		while v != 0 {
			out.append(alphabet[Int(v % 37)])
			v /= 37
		}
		return String(out.reversed())
	}
}
