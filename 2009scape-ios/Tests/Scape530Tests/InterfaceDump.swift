import Foundation
import XCTest
@testable import Scape530

final class InterfaceDump: XCTestCase {
	func testDump() throws {
		guard let ids = ProcessInfo.processInfo.environment["DUMP_IF"], let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { return }
		let ui = InterfaceRenderer(store: ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir))))
		for id in ids.split(separator: ",").compactMap({ Int($0) }) {
			for case let c? in try ui.components(id) {
				print("IF \(id):\(c.id & 0xFFFF) t\(c.type) if3=\(c.if3) parent=\(c.parent == -1 ? "-" : "\(c.parent & 0xFFFF)") \(c.baseX),\(c.baseY) \(c.baseWidth)x\(c.baseHeight) dyn\(c.dynamicWidth)/\(c.dynamicHeight) mode\(c.horizontalMode)/\(c.verticalMode) hidden=\(c.hidden) sprite=\(c.spriteId) tile=\(c.spriteTiling) text='\(c.text)' font=\(c.font) col=\(String(c.color, radix: 16)) cc=\(c.clientCode) a=\(c.alpha) hooks=\(c.hooks.keys.sorted())")
			}
		}
	}
}

extension InterfaceDump {
	func testDumpSprites() throws {
		guard let ids = ProcessInfo.processInfo.environment["DUMP_SPRITE"], let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { return }
		let s = ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
		for id in ids.split(separator: ",").compactMap({ Int($0) }) {
			guard let sh = try s.sprite(id) else { print("SPR \(id) missing"); continue }
			for f in sh.frames {
				let opaque = f.indices.filter { $0 != 0 }.count
				print("SPR \(id) \(f.width)x\(f.height) inner \(f.innerWidth)x\(f.innerHeight)@\(f.xOffset),\(f.yOffset) opaque=\(opaque) alpha=\(f.alpha != nil) pal=\(f.palette.count)")
			}
		}
	}
}

extension InterfaceDump {
	/// DUMP_SCRIPT=108,109 prints each script's opcodes and operands.
	func testDumpScripts() throws {
		guard let ids = ProcessInfo.processInfo.environment["DUMP_SCRIPT"], let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { return }
		let s = ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
		for id in ids.split(separator: ",").compactMap({ Int($0) }) {
			guard let sc = try s.script(id) else { print("SCRIPT \(id) missing"); continue }
			print("SCRIPT \(id) name=\(sc.name ?? "-") ints=\(sc.intArgs) strs=\(sc.stringArgs) locals=\(sc.intLocals)/\(sc.stringLocals)")
			for i in 0..<sc.opcodes.count { print("  \(i): \(sc.opcodes[i]) \(sc.stringOperands[i].map { "\"\($0)\"" } ?? "\(sc.intOperands[i])")") }
		}
	}
}

extension InterfaceDump {
	/// DUMP_FIND=3104,3105 lists the scripts that use those opcodes.
	func testFindOpcodes() throws {
		guard let ops = ProcessInfo.processInfo.environment["DUMP_FIND"], let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { return }
		let s = ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
		let want = Set(ops.split(separator: ",").compactMap { Int($0) })
		for id in 0..<20000 {
			guard let sc = try? s.script(id) else { continue }
			for (i, op) in sc.opcodes.enumerated() where want.contains(op) { print("FIND script \(id) pc \(i) op \(op)") }
		}
	}
}
