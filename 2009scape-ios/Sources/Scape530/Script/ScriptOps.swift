import Foundation

/// The opcodes above 51: component ops, math, strings, config lookups and the
/// host-routed game queries.
extension ScriptRunner {
	func scalars(_ s: String) -> [UInt32] { s.unicodeScalars.map { $0.value } }
	func string(_ u: [UInt32]) -> String {
		var v = String.UnicodeScalarView()
		for c in u { if let s = Unicode.Scalar(c) { v.append(s) } }
		return String(v)
	}

	func clamp(_ v: Int32, _ lo: Int32, _ hi: Int32) -> Int32 { min(max(v, lo), hi) }

	func execExtended(_ op: Int, operand: Int32, script: ClientScript) throws {
		let first = operand == 1
		switch op {
		case 100:
			let a = try popInts(3)
			guard a[1] != 0 else { throw StackFault(message: "cc_create type 0") }
			let ref = try host.createChild(of: Int(a[0]), type: Int(a[1]), index: Int(a[2]))
			if first { active1 = ref } else { active2 = ref }
		case 101:
			let c = try active(first)
			guard c.child != -1 else { throw StackFault(message: "Tried to cc_delete static active-component!") }
			try host.deleteChild(c)
		case 102:
			host.deleteChildren(of: Int(try popI()))
		case 200:
			let (id, idx) = try pop2()
			if idx != -1, let r = host.child(of: Int(id), index: Int(idx)) {
				try pushI(1)
				if first { active1 = r } else { active2 = r }
			} else {
				try pushI(0)
			}
		case 201:
			let id = Int(try popI())
			if host.componentExists(id) {
				try pushI(1)
				let r = ComponentRef(id: id)
				if first { active1 = r } else { active2 = r }
			} else {
				try pushI(0)
			}
		case 1000..<1500, 2000..<2500:
			try execComponentSetter(op, first: first)
		case 1500..<1900, 2500..<2900:
			try execComponentGetter(op, first: first)
		case 3309: try pushI((try popI() >> 14) & 0x3FFF)
		case 3310: try pushI(try popI() >> 28)
		case 3311: try pushI(try popI() & 0x3FFF)
		case 3336:
			let a = try popInts(4)
			try pushI(a[0] &+ (a[1] &<< 14) &+ (a[2] &<< 28) &+ a[3])
		case 3313, 3314, 3315:
			var a = try popInts(2)
			a[0] = a[0] &+ 32768
			try callHost(HostOps.table[op - 12]!, ints: a, strings: [])
		case 3400:
			let (e, k) = try pop2()
			let en = try enumType(Int(e))
			if case .string(let s)? = en.values[k] { try pushS(s) } else { try pushS(en.defaultString) }
		case 3408:
			let a = try popInts(4)
			let en = try enumType(Int(a[2]))
			guard en.keyType == Int(a[0]), en.valueType == Int(a[1]) else { throw StackFault(message: "C3408-1") }
			if a[1] == 115 {
				if case .string(let s)? = en.values[a[3]] { try pushS(s) } else { try pushS(en.defaultString) }
			} else {
				if case .int(let v)? = en.values[a[3]] { try pushI(v) } else { try pushI(en.defaultInt) }
			}
		case 3409:
			let a = try popInts(3)
			guard a[1] != -1 else { throw StackFault(message: "C3409-2") }
			let en = try enumType(Int(a[1]))
			guard en.valueType == Int(a[0]) else { throw StackFault(message: "C3409-1") }
			try pushB(en.values.values.contains(.int(a[2])))
		case 3410:
			let s = try popS()
			let id = try popI()
			guard id != -1 else { throw StackFault(message: "C3410-2") }
			let en = try enumType(Int(id))
			guard en.valueType == 115 else { throw StackFault(message: "C3410-1") }
			try pushB(en.values.values.contains(.string(s)))
		case 3411:
			try pushI(try enumType(Int(try popI())).values.count)
		case 4000: let (a, b) = try pop2(); try pushI(a &+ b)
		case 4001: let (a, b) = try pop2(); try pushI(a &- b)
		case 4002: let (a, b) = try pop2(); try pushI(a &* b)
		case 4003:
			let (a, b) = try pop2()
			guard b != 0 else { throw StackFault(message: "divide by zero") }
			try pushI(a.dividedReportingOverflow(by: b).partialValue)
		case 4004: try pushI(Self.d2i(Double(try popI()) * Double.random(in: 0..<1)))
		case 4005: try pushI(Self.d2i(Double.random(in: 0..<1) * Double(try popI() &+ 1)))
		case 4006:
			let a = try popInts(5)
			let d = a[3] &- a[2]
			guard d != 0 else { throw StackFault(message: "divide by zero") }
			try pushI(((a[1] &- a[0]) &* (a[4] &- a[2])).dividedReportingOverflow(by: d).partialValue &+ a[0])
		case 4007:
			let (a, b) = try pop2()
			try pushI(Int32(truncatingIfNeeded: Int64(a) * Int64(b) / 100 + Int64(a)))
		case 4008: let (a, b) = try pop2(); try pushI(a | (1 &<< b))
		case 4009: let (a, b) = try pop2(); try pushI((0 &- (1 &<< b) &- 1) & a)
		case 4010: let (a, b) = try pop2(); try pushB((a & (1 &<< b)) != 0)
		case 4011:
			let (a, b) = try pop2()
			guard b != 0 else { throw StackFault(message: "modulo by zero") }
			try pushI(a.remainderReportingOverflow(dividingBy: b).partialValue)
		case 4012:
			let (a, b) = try pop2()
			try pushI(a == 0 ? 0 : Self.d2i(pow(Double(a), Double(b))))
		case 4013:
			let (a, b) = try pop2()
			if a == 0 { try pushI(0) } else if b == 0 { try pushI(Int32.max) } else { try pushI(Self.d2i(pow(Double(a), 1.0 / Double(b)))) }
		case 4014: let (a, b) = try pop2(); try pushI(a & b)
		case 4015: let (a, b) = try pop2(); try pushI(a | b)
		case 4016: let (a, b) = try pop2(); try pushI(min(a, b))
		case 4017: let (a, b) = try pop2(); try pushI(max(a, b))
		case 4018:
			let a = try popInts(3)
			guard a[1] != 0 else { throw StackFault(message: "divide by zero") }
			try pushI(Int32(truncatingIfNeeded: Int64(a[0]) * Int64(a[2]) / Int64(a[1])))
		case 4100:
			let s = try popS(); let n = try popI()
			try pushS(s + String(n))
		case 4101:
			let b = try popS(); let a = try popS()
			try pushS(a + b)
		case 4102:
			let s = try popS(); let n = try popI()
			try pushS(s + (n < 0 ? "" : "+") + String(n))
		case 4103: try pushS(try popS().lowercased())
		case 4104:
			let days = Int64(try popI())
			let date = Date(timeIntervalSince1970: Double(days * 86_400_000 + 1_014_768_000_000) / 1000)
			var cal = Calendar(identifier: .gregorian)
			cal.timeZone = TimeZone(identifier: "UTC") ?? .current
			let c = cal.dateComponents([.day, .month, .year], from: date)
			let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
			try pushS("\(c.day ?? 0)-\(months[((c.month ?? 1) - 1) % 12])-\(c.year ?? 0)")
		case 4105:
			let b = try popS(); let a = try popS()
			let female = host.perform(HostOps.table[3327]!, ints: [], strings: []).ints.first ?? 0
			try pushS(female != 0 ? b : a)
		case 4106: try pushS(String(try popI()))
		case 4107:
			let b = try popS(); let a = try popS()
			try pushI(compareJag(a, b))
		case 4108:
			let s = try popS(); let (w, f) = try pop2()
			try pushI(host.paragraphLineCount(font: Int(f), text: s, width: Int(w)))
		case 4109:
			let s = try popS(); let (w, f) = try pop2()
			try pushI(host.maxLineWidth(font: Int(f), text: s, width: Int(w)))
		case 4110:
			let b = try popS(); let a = try popS()
			try pushS(try popI() == 1 ? a : b)
		case 4111:
			try pushS(try popS().replacingOccurrences(of: "<", with: "<lt>").replacingOccurrences(of: ">", with: "<gt>"))
		case 4112:
			let s = try popS(); let c = try popI()
			if c == -1 { throw StackFault(message: "null char") }
			guard c > 0 && c <= 255 else { throw StackFault(message: "invalid char") }
			try pushS(s + String(Character(Unicode.Scalar(UInt8(c)))))
		case 4113:
			let c = try popI()
			try pushB((c >= 32 && c <= 126) || (c >= 160 && c <= 255) || c == 128 || c == 140 || c == 151 || c == 156 || c == 159)
		case 4114:
			let c = try popI()
			try pushB((c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57))
		case 4115:
			let c = try popI()
			try pushB((c >= 97 && c <= 122) || (c >= 65 && c <= 90))
		case 4116:
			let c = try popI()
			try pushB(c >= 48 && c <= 57)
		case 4117: try pushI(try popS().unicodeScalars.count)
		case 4118:
			let s = scalars(try popS()); let (a, b) = try pop2()
			guard a >= 0, a <= b, Int(b) <= s.count else { throw StackFault(message: "substring \(a)..<\(b) of \(s.count)") }
			try pushS(string(Array(s[Int(a)..<Int(b)])))
		case 4119:
			var out = ""
			var inTag = false
			for ch in try popS() {
				if ch == "<" { inTag = true } else if ch == ">" { inTag = false } else if !inTag { out.append(ch) }
			}
			try pushS(out)
		case 4120:
			let s = scalars(try popS()); let (c, start) = try pop2()
			var r: Int32 = -1
			var i = max(Int(start), 0)
			while i < s.count { if s[i] == UInt32(truncatingIfNeeded: c) & 0xFF { r = Int32(i); break }; i += 1 }
			try pushI(r)
		case 4121:
			let needle = scalars(try popS()); let hay = scalars(try popS()); let start = Int(try popI())
			try pushI(indexOf(hay, needle, max(start, 0)))
		case 4122:
			let c = try popI()
			try pushI((c >= 65 && c <= 90) || (c >= 192 && c <= 222 && c != 215) ? c + 32 : c == 159 ? 255 : c == 140 ? 156 : c)
		case 4123:
			let c = try popI()
			try pushI((c >= 97 && c <= 122) || (c >= 224 && c <= 254 && c != 247) ? c - 32 : c == 255 ? 159 : c == 156 ? 140 : c)
		case 4124:
			let grouped = try popI() != 0
			let v = Int64(try popI())
			try pushS(formatNumber(v, grouped: grouped))
		case 4200...4208:
			try execObj(op)
		case 4300:
			let (n, p) = try pop2()
			guard let t = try store.npc(Int(n)) else { throw StackFault(message: "missing npc \(n)") }
			try pushParam(t.params, param: Int(p))
		case 4400:
			let (n, p) = try pop2()
			guard let t = try store.loc(Int(n)) else { throw StackFault(message: "missing loc \(n)") }
			try pushParam(t.params, param: Int(p))
		case 4500:
			let (n, p) = try pop2()
			try pushParam(try structParams(Int(n)), param: Int(p))
		case 6304:
			let y = try popI()
			let leap: Bool
			if y < 0 { leap = (y + 1) % 4 == 0 } else if y < 1582 { leap = y % 4 == 0 } else if y % 4 != 0 { leap = false } else if y % 100 != 0 { leap = true } else { leap = y % 400 == 0 }
			try pushB(leap)
		default:
			guard let spec = HostOps.table[op] else { throw Unported(opcode: op) }
			let ints = try popInts(spec.ints)
			let strs = try popStrings(spec.strings)
			try callHost(spec, ints: ints, strings: strs)
		}
	}

	/// Calls the host and pushes exactly `outInts` / `outStrings` results.
	func callHost(_ spec: HostOpSpec, ints: [Int32], strings: [String]) throws {
		let r = host.perform(spec, ints: ints, strings: strings)
		for i in 0..<spec.outInts { try pushI(i < r.ints.count ? r.ints[i] : 0) }
		for i in 0..<spec.outStrings { try pushS(i < r.strings.count ? r.strings[i] : "") }
	}

	func enumType(_ id: Int) throws -> EnumType {
		guard let e = try store.enumType(id) else { throw StackFault(message: "missing enum \(id)") }
		return e
	}

	func execObj(_ op: Int) throws {
		if op == 4208 {
			let (o, p) = try pop2()
			guard let t = try store.obj(Int(o)) else { throw StackFault(message: "missing obj \(o)") }
			try pushParam(t.params, param: Int(p))
			return
		}
		let obj: Int32
		var idx: Int32 = 0
		if op == 4201 || op == 4202 { (obj, idx) = try pop2() } else { obj = try popI() }
		guard let t = try store.obj(Int(obj)) else { throw StackFault(message: "missing obj \(obj)") }
		switch op {
		case 4200: try pushS(t.name)
		case 4201: try pushS(idx >= 1 && idx <= 5 ? (t.ops[Int(idx) - 1] ?? "") : "")
		case 4202: try pushS(idx >= 1 && idx <= 5 ? (t.iops[Int(idx) - 1] ?? "") : "")
		case 4203: try pushI(t.cost)
		case 4204: try pushB(t.stackable)
		case 4205: try pushI(t.certtemplate == -1 && t.certlink >= 0 ? t.certlink : Int(obj))
		case 4206: try pushI(t.certtemplate >= 0 && t.certlink >= 0 ? t.certlink : Int(obj))
		case 4207: try pushB(t.members)
		default: throw Unported(opcode: op)
		}
	}

	func indexOf(_ hay: [UInt32], _ needle: [UInt32], _ start: Int) -> Int32 {
		if needle.isEmpty { return start <= hay.count ? Int32(start) : -1 }
		if hay.count < needle.count { return -1 }
		var i = start
		while i + needle.count <= hay.count {
			if Array(hay[i..<i + needle.count]) == needle { return Int32(i) }
			i += 1
		}
		return -1
	}

	/// Approximation of rt4 `JagString.compare` (case-insensitive, accent-folding order): -1, 0 or 1.
	func compareJag(_ a: String, _ b: String) -> Int32 {
		func fold(_ c: UInt32) -> UInt32 {
			switch c {
			case 156, 230: return 101
			case 140, 198: return 69
			case 223: return 115
			default: return c
			}
		}
		let x = scalars(a.lowercased()).map(fold), y = scalars(b.lowercased()).map(fold)
		for i in 0..<min(x.count, y.count) where x[i] != y[i] { return x[i] < y[i] ? -1 : 1 }
		return x.count == y.count ? 0 : (x.count < y.count ? -1 : 1)
	}

	func formatNumber(_ v: Int64, grouped: Bool) -> String {
		var digits = String(v.magnitude)
		if grouped {
			var out = ""
			for (i, ch) in digits.reversed().enumerated() {
				if i != 0 && i % 3 == 0 { out.append(",") }
				out.append(ch)
			}
			digits = String(out.reversed())
		}
		return (v < 0 ? "-" : "") + digits
	}

	// MARK: components

	/// Pops the component for a script op: the active one (< 2000) or one id from the stack.
	func componentOperand(_ remote: Bool, first: Bool) throws -> ComponentRef {
		remote ? ComponentRef(id: Int(try popI())) : try active(first)
	}

	func execComponentSetter(_ rawOp: Int, first: Bool) throws {
		let remote = rawOp >= 2000
		let op = remote ? rawOp - 1000 : rawOp
		let c = try componentOperand(remote, first: first)

		func ints(_ n: Int, _ s: ComponentSetter) throws { host.set(c, s, try popInts(n)) }

		switch op {
		case 1000:
			let a = try popInts(4)
			host.set(c, .position, [a[0], a[1], clamp(a[3], 0, 5), clamp(a[2], 0, 5)])
		case 1001:
			let a = try popInts(4)
			host.set(c, .size, [a[0], a[1], clamp(a[2], 0, 4), clamp(a[3], 0, 4)])
		case 1003: try ints(1, .hidden)
		case 1004: try ints(2, .aspect)
		case 1005: try ints(1, .noClickThrough)
		case 1100: try ints(2, .scrollPos)
		case 1101: try ints(1, .rgb)
		case 1102: try ints(1, .filled)
		case 1103: try ints(1, .trans)
		case 1104: try ints(1, .lineWidth)
		case 1105: try ints(1, .sprite)
		case 1106: try ints(1, .angle2d)
		case 1107: try ints(1, .spriteTiling)
		case 1108: try ints(1, .model)
		case 1109: try ints(6, .modelRotation)
		case 1110: try ints(1, .animation)
		case 1111: try ints(1, .modelOrtho)
		case 1112: host.setString(c, .text, try popS())
		case 1113: try ints(1, .font)
		case 1114: try ints(3, .textAlignment)
		case 1115: try ints(1, .shadowed)
		case 1116: try ints(1, .outlineThickness)
		case 1117: try ints(1, .shadowColor)
		case 1118: try ints(1, .vFlip)
		case 1119: try ints(1, .hFlip)
		case 1120: try ints(2, .scrollMax)
		case 1121: try ints(2, .opcode1121)
		case 1122: try ints(1, .hasAlpha)
		case 1123: try ints(1, .modelZoom)
		case 1200, 1205:
			let a = try popInts(2)
			host.set(c, .item, [a[0], a[1], op == 1205 ? 0 : 1])
		case 1201: try ints(1, .npcHead)
		case 1202: host.set(c, .selfHead, [])
		case 1203: try ints(1, .otherPlayerHead)
		case 1204: try ints(1, .playerFull)
		case 1300:
			let idx = Int(try popI()) - 1
			let s = try popS()
			if idx >= 0 && idx <= 9 { host.setOption(c, slot: idx, s) }
		case 1301: try ints(2, .draggable)
		case 1302: try ints(1, .dragRenderBehaviour)
		case 1303: try ints(1, .dragDeadZone)
		case 1304: try ints(1, .dragDeadTime)
		case 1305: host.setString(c, .optionBase, try popS())
		case 1306: host.setString(c, .optionCircumfix, try popS())
		case 1307: host.clearOptions(c)
		case 1308:
			let a = try popInts(2)
			host.set(c, .opcode1308, [a[1], a[0]])
		case 1309:
			let (slot, value) = try pop2()
			if slot >= 1 && slot <= 10 { host.set(c, .opEnabled, [slot - 1, value]) }
		case 1400..<1500:
			guard let (hook, _) = Self.hookName(op) else { throw Unported(opcode: rawOp) }
			var desc = scalars(try popS())
			var triggers: [Int32]?
			if let last = desc.last, last == 89 {
				var n = Int(try popI())
				var t = [Int32](repeating: 0, count: max(n, 0))
				while n > 0 { n -= 1; t[n] = try popI() }
				triggers = t.isEmpty ? nil : t
				desc.removeLast()
			}
			var args = [ServerMessage.ScriptArg](repeating: .int(0), count: desc.count + 1)
			var i = desc.count
			while i >= 1 {
				args[i] = desc[i - 1] == 115 ? .string(try popS()) : .int(try popI())
				i -= 1
			}
			let sid = try popI()
			if sid == -1 {
				host.setHook(c, hook, args: nil, triggers: triggers)
			} else {
				args[0] = .int(sid)
				host.setHook(c, hook, args: args, triggers: triggers)
			}
		default:
			throw Unported(opcode: rawOp)
		}
	}

	func execComponentGetter(_ rawOp: Int, first: Bool) throws {
		// 2700-2705 have their own shapes.
		switch rawOp {
		case 2702: try pushB(host.isInterfaceOpen(parent: Int(try popI()), interface: nil)); return
		case 2703: try pushI(host.childCount(of: Int(try popI()))); return
		case 2704, 2705:
			let (p, i) = try pop2()
			try pushB(host.isInterfaceOpen(parent: Int(p), interface: Int(i)))
			return
		default: break
		}
		let remote = rawOp >= 2500
		let op = remote ? rawOp - 1000 : rawOp
		let c = try componentOperand(remote, first: first)
		func g(_ x: ComponentGetter) throws { try pushI(host.get(c, x)) }
		switch op {
		case 1500: try g(.x)
		case 1501: try g(.y)
		case 1502: try g(.width)
		case 1503: try g(.height)
		case 1504: try g(.hidden)
		case 1505: try g(.layer)
		case 1600: try g(.scrollX)
		case 1601: try g(.scrollY)
		case 1602: try pushS(host.text(of: c))
		case 1603: try g(.scrollMaxH)
		case 1604: try g(.scrollMaxV)
		case 1605: try g(.modelZoom)
		case 1606: try g(.modelXAngle)
		case 1607: try g(.modelYOffset)
		case 1608: try g(.modelYAngle)
		case 1609: try g(.alpha)
		case 1610: try g(.modelXOffset)
		case 1611: try g(.modelZOffset)
		case 1612: try g(.spriteId)
		case 1700: try g(.objId)
		case 1701: try pushI(host.get(c, .objId) == -1 ? 0 : host.get(c, .objCount))
		case 1702 where !remote: try g(.childIndex)
		case 1800: try g(.targetMask)
		case 1801: try pushS(host.option(of: c, slot: Int(try popI()) - 1))
		case 1802: try pushS(host.optionBase(of: c))
		default: throw Unported(opcode: rawOp)
		}
	}
}
