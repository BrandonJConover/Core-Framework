import XCTest
@testable import Scape530

/// The character designer previews identikit and colour changes on the local player (CS2 403 / 404 / 410).
extension PlaythroughTests {
	func testDesignerPreviewChanges() throws {
		let l = try live("ptdesign")
		XCTAssertTrue(l.client.state.interfaces.open.values.contains(771), "designer open")
		var edits: [AppearanceEdit] = []
		let old = l.client.host.onAppearanceEdit
		l.client.host.onAppearanceEdit = { edits.append($0); old($0) }
		let before = l.client.world.selfLook
		print("DESIGN before: \(String(describing: before))")
		let ops = Set(l.drawn(771).flatMap { $0.component.ops }.filter { !$0.isEmpty })
		print("DESIGN ops: \(ops.sorted())")
		_ = l.takeSent()
		XCTAssertTrue(l.tapOp("Select body options"))
		l.pump(1.5)
		let skip: Set<Int> = [14, 16, 18, 20, 37, 40, 46]
		let swatches = l.drawn(771).filter { d in !skip.contains(d.component.id & 0xFFFF) && d.w < 80 && d.h < 80 && (d.component.hooks["onOptionClick"] != nil || d.component.hooks["onClick"] != nil || d.component.ops.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) }
		print("DESIGN body comps: \(swatches.map { "\($0.component.id & 0xFFFF):\($0.component.ops.filter { !$0.isEmpty }):\($0.component.hooks.keys.sorted())" }.prefix(30))")
		for d in swatches.prefix(4) {
			l.tap(d)
			l.pump(0.6)
		}
		print("DESIGN edits: \(edits) sent: \(l.takeSent().prefix(8))")
		print("DESIGN after: \(String(describing: l.client.world.selfLook))")
		l.shot("designer-preview")
		l.report()
		XCTAssertFalse(edits.isEmpty, "the designer's scripts edited the look")
		XCTAssertNotEqual(l.client.world.selfLook, before, "the preview look changed")
	}
}

