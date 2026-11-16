import Foundation

/// CS2 interpreter. Port of rt4 `ScriptRunner.run(maxCycles, HookRequest)`.
/// Game and component access goes through `ScriptHost`; config lookups
/// (enums, params, objs, varbits) use the `ConfigStore`.
public final class ScriptRunner {
	public let store: ConfigStore
	public unowned let host: ScriptHost

	/// Opcodes executed in the last/all runs (for coverage reporting).
	public var opcodeCounts: [Int: Int] = [:]
	public var trace = false

	static let stackSize = 1000
	static let maxFrames = 50

	var intStack = [Int32](repeating: 0, count: ScriptRunner.stackSize)
	var strStack = [String](repeating: "", count: ScriptRunner.stackSize)
	var isp = 0, ssp = 0
	/// rt4 `anIntArray140` / `anIntArrayArray33`: five script int arrays, persistent across runs.
	var arrayLengths = [Int](repeating: 0, count: 5)
	var arrays = [[Int32]](repeating: [Int32](repeating: 0, count: 5000), count: 5)
	var active1: ComponentRef?
	var active2: ComponentRef?

	struct Frame {
		var script: ClientScript
		var pc: Int
		var intLocals: [Int32]
		var strLocals: [String]
	}

	public init(store: ConfigStore, host: ScriptHost) {
		self.store = store
		self.host = host
	}

	/// rt4 `ScriptRunner.run(HookRequest)`: 200000 cycle budget.
	public func run(_ request: ScriptRequest, maxCycles: Int = 200_000) throws {
		guard case let .int(sid)? = request.args.first else { return }
		guard var script = try store.script(Int(sid)) else { return }
		isp = 0
		ssp = 0
		var frames: [Frame] = []
		var pc = -1
		var intLocals = [Int32](repeating: 0, count: script.intLocals)
		var strLocals = [String](repeating: "", count: script.stringLocals)
		var curOp = -1

		func fail(_ m: String) -> ScriptError {
			.failure(m, script: script.id, name: script.name, pc: pc, opcode: curOp)
		}

		// Hook argument placeholders (0x80000001...).
		var ni = 0, ns = 0
		for a in request.args.dropFirst() {
			switch a {
			case .int(let v):
				var id = v
				let r: Int32? = {
					switch UInt32(bitPattern: v) {
					case 0x8000_0001: return Int32(truncatingIfNeeded: request.mouseX)
					case 0x8000_0002: return Int32(truncatingIfNeeded: request.mouseY)
					case 0x8000_0003: return Int32(truncatingIfNeeded: request.source?.id ?? -1)
					case 0x8000_0004: return Int32(truncatingIfNeeded: request.op)
					case 0x8000_0005: return Int32(truncatingIfNeeded: request.source?.child ?? -1)
					case 0x8000_0006: return Int32(truncatingIfNeeded: request.target?.id ?? -1)
					case 0x8000_0007: return Int32(truncatingIfNeeded: request.target?.child ?? -1)
					case 0x8000_0008: return Int32(truncatingIfNeeded: request.keyCode)
					case 0x8000_0009: return Int32(truncatingIfNeeded: request.keyChar)
					default: return nil
					}
				}()
				if let r { id = r }
				guard ni < intLocals.count else { throw fail("too many int args") }
				intLocals[ni] = id
				ni += 1
			case .string(let s):
				guard ns < strLocals.count else { throw fail("too many string args") }
				strLocals[ns] = s == "event_opbase" ? request.opBase : s
				ns += 1
			}
		}

		var cycles = 0
		while true {
			cycles += 1
			if cycles > maxCycles { throw fail("slow") }
			pc += 1
			guard pc >= 0, pc < script.opcodes.count else { throw fail("pc out of range") }
			let op = script.opcodes[pc]
			curOp = op
			let operand = script.intOperands[pc]
			opcodeCounts[op, default: 0] += 1

			do {
				switch op {
				case 0: try pushI(operand)
				case 1: try pushI(host.varp(Int(operand)))
				case 2: host.setVarp(Int(operand), try popI())
				case 3: try pushS(script.stringOperands[pc] ?? "")
				case 6: pc += Int(operand)
				case 7: let (a, b) = try pop2(); if a != b { pc += Int(operand) }
				case 8: let (a, b) = try pop2(); if a == b { pc += Int(operand) }
				case 9: let (a, b) = try pop2(); if a < b { pc += Int(operand) }
				case 10: let (a, b) = try pop2(); if a > b { pc += Int(operand) }
				case 31: let (a, b) = try pop2(); if a <= b { pc += Int(operand) }
				case 32: let (a, b) = try pop2(); if a >= b { pc += Int(operand) }
				case 21:
					guard let f = frames.popLast() else { return }
					script = f.script
					intLocals = f.intLocals
					strLocals = f.strLocals
					pc = f.pc
				case 25: try pushI(try varbit(Int(operand)))
				case 27: try setVarbit(Int(operand), try popI())
				case 33:
					guard Int(operand) < intLocals.count else { throw fail("int local out of range") }
					try pushI(intLocals[Int(operand)])
				case 34:
					let v = try popI()
					guard Int(operand) < intLocals.count else { throw fail("int local out of range") }
					intLocals[Int(operand)] = v
				case 35:
					guard Int(operand) < strLocals.count else { throw fail("string local out of range") }
					try pushS(strLocals[Int(operand)])
				case 36:
					let v = try popS()
					guard Int(operand) < strLocals.count else { throw fail("string local out of range") }
					strLocals[Int(operand)] = v
				case 37:
					let n = Int(operand)
					guard n >= 0, ssp >= n else { throw fail("stack underflow") }
					ssp -= n
					let joined = strStack[ssp..<ssp + n].joined()
					try pushS(joined)
				case 38: _ = try popI()
				case 39: _ = try popS()
				case 40:
					guard let callee = try store.script(Int(operand)) else { throw fail("non-existant gosub script \(operand)") }
					var newInts = [Int32](repeating: 0, count: callee.intLocals)
					var newStrs = [String](repeating: "", count: callee.stringLocals)
					guard isp >= callee.intArgs, ssp >= callee.stringArgs, callee.intArgs <= newInts.count, callee.stringArgs <= newStrs.count else {
						throw fail("bad gosub args")
					}
					for i in 0..<callee.intArgs { newInts[i] = intStack[isp - callee.intArgs + i] }
					for i in 0..<callee.stringArgs { newStrs[i] = strStack[ssp - callee.stringArgs + i] }
					isp -= callee.intArgs
					ssp -= callee.stringArgs
					guard frames.count < ScriptRunner.maxFrames else { throw fail("call stack overflow") }
					frames.append(Frame(script: script, pc: pc, intLocals: intLocals, strLocals: strLocals))
					script = callee
					pc = -1
					intLocals = newInts
					strLocals = newStrs
				case 42: try pushI(host.varc(Int(operand)))
				case 43: host.setVarc(Int(operand), try popI())
				case 44:
					let id = Int(operand) >> 16
					let n = Int(try popI())
					guard id < 5, n >= 0, n <= 5000 else { throw fail("bad array") }
					arrayLengths[id] = n
					let fill: Int32 = (Int(operand) & 0xFFFF) == 105 ? 0 : -1
					for i in 0..<n { arrays[id][i] = fill }
				case 45:
					let i = Int(try popI())
					let id = Int(operand)
					guard id < 5, i >= 0, i < arrayLengths[id] else { throw fail("array index") }
					try pushI(arrays[id][i])
				case 46:
					let (i32, v) = try pop2()
					let i = Int(i32)
					let id = Int(operand)
					guard id < 5, i >= 0, i < arrayLengths[id] else { throw fail("array index") }
					arrays[id][i] = v
				case 47: try pushS(host.varcstr(Int(operand)))
				case 48: host.setVarcstr(Int(operand), try popS())
				case 51:
					let v = try popI()
					guard Int(operand) < script.switchTables.count else { throw fail("switch table") }
					if let off = script.switchTables[Int(operand)][v] { pc += Int(off) }
				default:
					try execExtended(op, operand: operand, script: script)
				}
			} catch let e as ScriptError {
				throw e
			} catch let e as StackFault {
				throw fail(e.message)
			} catch let e as Unported {
				throw ScriptError.unportedOpcode(opcode: e.opcode, script: script.id, name: script.name, pc: pc)
			} catch {
				throw fail("\(error)")
			}
		}
	}

	// MARK: stack helpers

	struct StackFault: Error { let message: String }
	struct Unported: Error { let opcode: Int }

	@inline(__always) func pushI(_ v: Int32) throws {
		guard isp < ScriptRunner.stackSize else { throw StackFault(message: "int stack overflow") }
		intStack[isp] = v
		isp += 1
	}
	@inline(__always) func pushI(_ v: Int) throws { try pushI(Int32(truncatingIfNeeded: v)) }
	@inline(__always) func pushB(_ b: Bool) throws { try pushI(b ? 1 : 0) }
	@inline(__always) func pushS(_ v: String) throws {
		guard ssp < ScriptRunner.stackSize else { throw StackFault(message: "string stack overflow") }
		strStack[ssp] = v
		ssp += 1
	}
	@inline(__always) func popI() throws -> Int32 {
		guard isp > 0 else { throw StackFault(message: "int stack underflow") }
		isp -= 1
		return intStack[isp]
	}
	@inline(__always) func popS() throws -> String {
		guard ssp > 0 else { throw StackFault(message: "string stack underflow") }
		ssp -= 1
		return strStack[ssp]
	}
	/// Pops two ints, returned in push order.
	@inline(__always) func pop2() throws -> (Int32, Int32) {
		guard isp >= 2 else { throw StackFault(message: "int stack underflow") }
		isp -= 2
		return (intStack[isp], intStack[isp + 1])
	}
	/// Pops `n` ints, returned in push order.
	func popInts(_ n: Int) throws -> [Int32] {
		guard isp >= n else { throw StackFault(message: "int stack underflow") }
		isp -= n
		return Array(intStack[isp..<isp + n])
	}
	func popStrings(_ n: Int) throws -> [String] {
		guard ssp >= n else { throw StackFault(message: "string stack underflow") }
		ssp -= n
		return Array(strStack[ssp..<ssp + n])
	}

	// MARK: varbits (rt4 VarpDomain.getVarbit / setVarbitClient)

	func varbitMask(_ v: VarbitType) -> UInt32 {
		let width = v.endBit - v.startBit
		return width >= 31 ? 0xFFFF_FFFF : (1 << UInt32(width + 1)) - 1
	}

	func varbit(_ id: Int) throws -> Int32 {
		guard let v = try store.varbit(id) else { throw StackFault(message: "missing varbit \(id)") }
		return v.value(in: host.varp(v.varp))
	}

	func setVarbit(_ id: Int, _ value: Int32) throws {
		guard let v = try store.varbit(id) else { throw StackFault(message: "missing varbit \(id)") }
		let mask = varbitMask(v)
		let cur = UInt32(bitPattern: host.varp(v.varp))
		let new = (cur & ~(mask << UInt32(v.startBit))) | ((UInt32(bitPattern: value) & mask) << UInt32(v.startBit))
		host.setVarp(v.varp, Int32(bitPattern: new))
	}

	// MARK: params (rt4 ParamType / StructType)

	struct ParamInfo {
		var isString = false
		var defaultInt: Int32 = 0
		var defaultString = ""
	}

	func paramInfo(_ id: Int) throws -> ParamInfo {
		var info = ParamInfo()
		guard let data = try store.file(archive: ConfigStore.Archive.configs, group: ConfigStore.ScriptArchive.paramGroup, file: id) else { return info }
		var p = Packet(data)
		while true {
			let op = try p.g1()
			if op == 0 { break }
			switch op {
			case 1: info.isString = try p.g1() == 115
			case 2: info.defaultInt = try p.g4()
			case 5: info.defaultString = try p.gjstr()
			default: break
			}
		}
		return info
	}

	func structParams(_ id: Int) throws -> [Int: ParamValue] {
		var out: [Int: ParamValue] = [:]
		guard let data = try store.file(archive: ConfigStore.Archive.configs, group: ConfigStore.ScriptArchive.structGroup, file: id) else { return out }
		var p = Packet(data)
		while true {
			let op = try p.g1()
			if op == 0 { break }
			if op == 249 { try decodeParams(&p, into: &out) }
		}
		return out
	}

	func pushParam(_ params: [Int: ParamValue], param: Int) throws {
		let info = try paramInfo(param)
		if info.isString {
			if case .string(let s)? = params[param] { try pushS(s) } else { try pushS(info.defaultString) }
		} else {
			if case .int(let v)? = params[param] { try pushI(v) } else { try pushI(info.defaultInt) }
		}
	}

	// MARK: component addressing

	func active(_ useFirst: Bool) throws -> ComponentRef {
		guard let c = useFirst ? active1 : active2 else { throw StackFault(message: "no active component") }
		return c
	}

	// MARK: Java number helpers

	static func d2i(_ d: Double) -> Int32 {
		if d.isNaN { return 0 }
		if d >= 2147483647 { return Int32.max }
		if d <= -2147483648 { return Int32.min }
		return Int32(d)
	}

	static func hookName(_ op: Int) -> (String, Bool)? {
		switch op {
		case 1400: return ("onClickRepeat", false)
		case 1401: return ("onHold", false)
		case 1402: return ("onRelease", false)
		case 1403: return ("onMouseOver", false)
		case 1404: return ("onMouseLeave", false)
		case 1405: return ("onDragStart", false)
		case 1406: return ("onUseWith", false)
		case 1407: return ("onVarpTransmit", true)
		case 1408: return ("onTimer", false)
		case 1409: return ("onOptionClick", false)
		case 1410: return ("onDragRelease", false)
		case 1411: return ("onDrag", false)
		case 1412: return ("onMouseRepeat", false)
		case 1414: return ("onInvTransmit", true)
		case 1415: return ("onStatTransmit", true)
		case 1416: return ("onUse", false)
		case 1417: return ("onScroll", false)
		case 1418: return ("onMsg", false)
		case 1419: return ("onKey", false)
		case 1420: return ("onFriendTransmit", false)
		case 1421: return ("onClanTransmit", false)
		case 1422: return ("onMiscTransmit", false)
		case 1423: return ("onDialogAbort", false)
		case 1424: return ("onWidgetsOpenClose", false)
		case 1425: return ("onStockTransmit", false)
		case 1426: return ("onMinimapUnlock", false)
		case 1427: return ("onResize", false)
		case 1428: return ("onVarcTransmit", true)
		case 1429: return ("onVarcstrTransmit", true)
		default: return nil
		}
	}
}
