import Foundation

/// rt4 key codes (the values `Keyboard.CODE_MAP` produces) and the Java AWT key codes (`java.awt.event.KeyEvent.VK_*`) that
/// map to them. The public `GameClient.keyDown(code:char:)` takes the Java codes so a shell can use rt4's own table.
public enum KeyCode {
	// rt4 `Keyboard.KEY_*`.
	public static let shift = 81, ctrl = 82, enter = 84, backSpace = 85, alt = 86
	public static let left = 96, right = 97, up = 98, down = 99
	public static let escape = 13, tab = 80, space = 83
	public static let pageUp = 104, pageDown = 105, end = 103, home = 102, insert = 100, delete = 101
	/// F1...F12 are rt4 codes 1...12.
	public static func function(_ n: Int) -> Int { n }

	// Java `KeyEvent.VK_*` values used by the table.
	public enum VK {
		public static let backSpace = 8, tab = 9, enter = 10, clear = 12, shift = 16, control = 17, alt = 18
		public static let escape = 27, space = 32, pageUp = 33, pageDown = 34, end = 35, home = 36
		public static let left = 37, up = 38, right = 39, down = 40
		public static let comma = 44, minus = 45, period = 46, slash = 47
		public static let semicolon = 59, equals = 61
		public static let openBracket = 91, backSlash = 92, closeBracket = 93
		public static let numpad0 = 96, multiply = 106, add = 107, subtract = 109, decimal = 110, divide = 111
		public static let f1 = 112, f12 = 123
		public static let delete = 127, insert = 155
		public static let backQuote = 192, quote = 222
		/// `KeyEvent.VK_NUMBER_SIGN` (520).
		public static let numberSign = 520
	}

	/// rt4 `Keyboard.CODE_MAP`: Java key code to rt4 key code, -1 for none. Includes the punctuation `Keyboard.init` adds
	/// for a non-Microsoft JVM with `setFocusTraversalKeysEnabled` (the branch rt4 takes on macOS, which iOS follows).
	public static let codeMap: [Int] = {
		var m = [Int](repeating: -1, count: 521)
		m[8] = 85; m[9] = 80; m[10] = 84; m[12] = 91
		m[16] = 81; m[17] = 82; m[18] = 86; m[27] = 13; m[32] = 83
		m[33] = 104; m[34] = 105; m[35] = 103; m[36] = 102
		m[37] = 96; m[38] = 98; m[39] = 97; m[40] = 99
		// 0...9
		let digits = [25, 16, 17, 18, 19, 20, 21, 22, 23, 24]
		for d in 0...9 { m[48 + d] = digits[d] }
		// A...Z
		let letters = [48, 68, 66, 50, 34, 51, 52, 53, 39, 54, 55, 56, 70, 69, 40, 41, 32, 35, 49, 36, 38, 67, 33, 65, 37, 64]
		for l in 0..<26 { m[65 + l] = letters[l] }
		// numpad 0...9 (rt4 codes above 0x7F: a press maps to "no key", see `Keyboard.keyPressed`)
		let numpad = [228, 231, 227, 233, 224, 219, 225, 230, 226, 232]
		for d in 0...9 { m[96 + d] = numpad[d] }
		m[106] = 89; m[107] = 87; m[109] = 88; m[110] = 229; m[111] = 90
		for f in 1...12 { m[111 + f] = f }
		m[127] = 101; m[155] = 100
		// `Keyboard.init`, non-Microsoft branch with setFocusTraversalKeysEnabled.
		m[222] = 58; m[192] = 28; m[520] = 59
		m[45] = 26; m[61] = 27; m[91] = 42; m[59] = 57; m[93] = 43; m[44] = 71; m[92] = 74; m[46] = 72; m[47] = 73
		return m
	}()

	/// rt4 `Keyboard.keyPressed` mapping: -1 when unmapped or the code has bit 0x80 set.
	public static func pressCode(javaCode: Int) -> Int {
		guard javaCode >= 0, javaCode < codeMap.count else { return -1 }
		let c = codeMap[javaCode]
		return c & 0x80 != 0 ? -1 : c
	}

	/// rt4 `Keyboard.keyReleased` mapping: the code with bit 0x80 cleared (so a numpad release clears a different slot, as in rt4).
	public static func releaseCode(javaCode: Int) -> Int {
		guard javaCode >= 0, javaCode < codeMap.count else { return -1 }
		let c = codeMap[javaCode]
		return c < 0 ? -1 : c & 0x7F
	}

	/// rt4 `Keyboard.getKeyChar`: the char a typed event queues (the euro sign is 128), -1 when it is not representable.
	public static func typedChar(_ c: Int) -> Int {
		if c == 8364 { return 128 }
		return c <= 0 || c >= 256 ? -1 : c
	}

	/// USB HID keyboard usage (UIKit `UIKeyboardHIDUsage.rawValue`) to Java key code; -1 for keys rt4 has no code for.
	public static func javaCode(hidUsage u: Int) -> Int {
		switch u {
		case 4...29: return 65 + (u - 4)
		case 30...38: return 49 + (u - 30)
		case 39: return 48
		case 40: return VK.enter
		case 41: return VK.escape
		case 42: return VK.backSpace
		case 43: return VK.tab
		case 44: return VK.space
		case 45: return VK.minus
		case 46: return VK.equals
		case 47: return VK.openBracket
		case 48: return VK.closeBracket
		case 49: return VK.backSlash
		case 50: return VK.numberSign
		case 51: return VK.semicolon
		case 52: return VK.quote
		case 53: return VK.backQuote
		case 54: return VK.comma
		case 55: return VK.period
		case 56: return VK.slash
		case 58...69: return VK.f1 + (u - 58)
		case 73: return VK.insert
		case 74: return VK.home
		case 75: return VK.pageUp
		case 76: return VK.delete
		case 77: return VK.end
		case 78: return VK.pageDown
		case 79: return VK.right
		case 80: return VK.left
		case 81: return VK.down
		case 82: return VK.up
		case 84: return VK.divide
		case 85: return VK.multiply
		case 86: return VK.subtract
		case 87: return VK.add
		case 88: return VK.enter
		case 89...97: return VK.numpad0 + 1 + (u - 89)
		case 98: return VK.numpad0
		case 99: return VK.decimal
		case 224, 228: return VK.control
		case 225, 229: return VK.shift
		case 226, 230: return VK.alt
		default: return -1
		}
	}
}

/// Port of rt4 `Keyboard`: the held-key table and the two event queues, fed by `keyPressed` / `keyTyped` / `keyReleased` and
/// advanced once per client cycle by `loop()`.
public struct Keyboard {
	/// rt4 `Keyboard.pressedKeys` (112 entries, indexed by rt4 key code).
	public private(set) var pressedKeys = [Bool](repeating: false, count: 112)
	/// rt4 `eventQueue`: a code to press, or `~code` to release (the 128-slot ring holds 127).
	private var events: [Int] = []
	private var eventOverflow = false
	/// rt4 `typedCodeQueue` / `typedCharQueue` entries since the last `loop()`, and those `nextKey` may now return.
	private var pending: [(code: Int, char: Int)] = []
	private var ready: [(code: Int, char: Int)] = []
	/// rt4 `Keyboard.idleLoops`: cycles since the last key event.
	public private(set) var idleLoops = 0

	public init() {}

	public func isPressed(_ code: Int) -> Bool { code >= 0 && code < pressedKeys.count && pressedKeys[code] }

	/// rt4 `Keyboard.keyPressed` for a Java key code.
	public mutating func keyPressed(javaCode: Int) {
		idleLoops = 0
		let code = KeyCode.pressCode(javaCode: javaCode)
		if code >= 0 {
			pushEvent(code)
			if pending.count < 127 { pending.append((code, -1)) }
		}
	}

	/// rt4 `Keyboard.keyTyped` for a character (queued as code -1).
	public mutating func keyTyped(char: Int) {
		let c = KeyCode.typedChar(char)
		if c >= 0, pending.count < 127 { pending.append((-1, c)) }
	}

	/// rt4 `Keyboard.keyReleased` for a Java key code.
	public mutating func keyReleased(javaCode: Int) {
		idleLoops = 0
		let code = KeyCode.releaseCode(javaCode: javaCode)
		if code >= 0 { pushEvent(~code) }
	}

	/// rt4 `Keyboard.focusLost`: every key counts as released at the next `loop()`.
	public mutating func focusLost() { eventOverflow = true }

	private mutating func pushEvent(_ e: Int) {
		guard !eventOverflow else { return }
		events.append(e)
		if events.count >= 127 { eventOverflow = true }
	}

	/// rt4 `Keyboard.loop`: applies the queued press / release events, then makes the keys typed since the previous call
	/// readable (anything the previous cycle left unread is dropped).
	public mutating func loop() {
		idleLoops += 1
		if eventOverflow {
			for i in pressedKeys.indices { pressedKeys[i] = false }
			events.removeAll()
			eventOverflow = false
		} else {
			for e in events {
				if e >= 0 { if e < pressedKeys.count { pressedKeys[e] = true } }
				else if ~e < pressedKeys.count { pressedKeys[~e] = false }
			}
			events.removeAll()
		}
		ready = pending
		pending.removeAll()
	}

	/// rt4 `Keyboard.nextKey`: the next (code, char) readable this cycle.
	public mutating func nextKey() -> (code: Int, char: Int)? {
		ready.isEmpty ? nil : ready.removeFirst()
	}

	/// Sets a held key directly (a shell's modifier state sync), bypassing the queue.
	mutating func setPressed(_ code: Int, _ down: Bool) {
		if code >= 0, code < pressedKeys.count { pressedKeys[code] = down }
	}

	/// Releases every key at once (focus loss, `pressesCancelled`).
	mutating func releaseAll() {
		for i in pressedKeys.indices { pressedKeys[i] = false }
		events.removeAll()
		eventOverflow = false
	}
}
