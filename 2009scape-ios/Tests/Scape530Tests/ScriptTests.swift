import Foundation
import XCTest
@testable import Scape530

/// Records every host call so tests can see what a script did.
final class RecordingHost: ScriptHost {
	var calls: [String] = []
	var varps: [Int: Int32] = [:]
	var existing: Set<Int> = []
	var hostOps: [String: Int] = [:]

	func varp(_ id: Int) -> Int32 { varps[id] ?? 0 }
	func setVarp(_ id: Int, _ value: Int32) { varps[id] = value; calls.append("setVarp \(id)=\(value)") }
	func componentExists(_ id: Int) -> Bool { true }
	func createChild(of parent: Int, type: Int, index: Int) throws -> ComponentRef {
		calls.append("createChild \(parent) type \(type) #\(index)")
		return ComponentRef(id: parent, child: index)
	}
	func child(of id: Int, index: Int) -> ComponentRef? { ComponentRef(id: id, child: index) }
	func set(_ ref: ComponentRef, _ setter: ComponentSetter, _ args: [Int32]) { calls.append("set \(ref.id)/\(ref.child) \(setter) \(args)") }
	func setString(_ ref: ComponentRef, _ setter: ComponentStringSetter, _ value: String) { calls.append("setString \(ref.id) \(setter) '\(value)'") }
	func setHook(_ ref: ComponentRef, _ hook: String, args: [ServerMessage.ScriptArg]?, triggers: [Int32]?) { calls.append("hook \(ref.id) \(hook)") }
	func perform(_ op: HostOpSpec, ints: [Int32], strings: [String]) -> HostResult {
		hostOps[op.name, default: 0] += 1
		calls.append("host \(op.name) \(ints) \(strings)")
		return HostResult()
	}
}

final class ScriptTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func testEveryScriptDecodes() throws {
		let s = try store()
		let ids = try s.scriptIds()
		var failures: [String] = []
		var ops = 0
		for id in ids {
			do { ops += try s.script(id)?.opcodes.count ?? 0 } catch { failures.append("script \(id): \(error)") }
		}
		XCTAssertEqual(failures, [])
		print("decoded \(ids.count - failures.count) of \(ids.count) scripts, \(ops) instructions")
	}

	func runHook(_ s: ConfigStore, _ r: ScriptRunner, _ comp: Component, _ hook: String) -> String? {
		guard let args = comp.hooks[hook] else { return nil }
		var req = ScriptRequest(args: args)
		req.source = ComponentRef(id: comp.id)
		do { try r.run(req); return "ok" } catch let ScriptError.unportedOpcode(op, _, _, _) { return "unported \(op)" } catch { return "error \(error)" }
	}

	func testLoginScreenOnLoad() throws {
		let s = try store()
		let ui = InterfaceRenderer(store: s)
		let id = try XCTUnwrap(try ui.interfaceId(named: "loginscreen"))
		XCTAssertEqual(id, 744)
		let comps = try ui.components(id)
		let c0 = try XCTUnwrap(comps[0])
		let args = try XCTUnwrap(c0.hooks["onLoad"])
		print("loginscreen c0 onLoad args: \(args)")
		let host = RecordingHost()
		let r = ScriptRunner(store: s, host: host)
		print("login onLoad: \(runHook(s, r, c0, "onLoad") ?? "none")")
		print("opcodes run: \(r.opcodeCounts.keys.sorted())")
		print("host calls (\(host.calls.count)): \(host.calls.prefix(25))")
	}

	func testOnLoadCoverage() throws {
		let s = try store()
		let ui = InterfaceRenderer(store: s)
		var done = 0, stopped = 0, errors = 0
		var missing: [String: Int] = [:]
		var errorSamples: [String] = []
		for iface in [744, 746, 548, 137, 752] {
			var d = 0, st = 0, er = 0
			for comp in try ui.components(iface).compactMap({ $0 }) where comp.hooks["onLoad"] != nil {
				let host = RecordingHost()
				let r = ScriptRunner(store: s, host: host)
				let res = runHook(s, r, comp, "onLoad") ?? ""
				if res == "ok" { d += 1 } else if res.hasPrefix("unported") { st += 1; missing[res, default: 0] += 1 } else {
					er += 1
					if errorSamples.count < 12 { errorSamples.append("\(iface):\(comp.id & 0xFFFF) \(res)") }
				}
			}
			print("interface \(iface): completed \(d), unported \(st), errors \(er)")
			done += d; stopped += st; errors += er
		}
		print("TOTAL onLoad hooks: completed \(done), stopped on unported opcode \(stopped), other errors \(errors)")
		print("missing opcodes: \(missing.sorted { $0.value > $1.value })")
		print("error samples: \(errorSamples)")
		XCTAssertEqual(stopped, 0)
	}
}
