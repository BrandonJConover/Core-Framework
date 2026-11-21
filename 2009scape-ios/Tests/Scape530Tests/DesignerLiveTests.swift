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
		// A colour swatch or style arrow: anything but the mouse-button and confirm buttons.
		let candidates = l.drawn(771).filter { d in d.component.ops.contains { o in !o.isEmpty && !o.lowercased().contains("mouse") && !o.lowercased().contains("confirm") } }
		for d in l.drawn(771) where d.component.hooks["onOp"] != nil || d.component.hooks["onClick"] != nil {
			print("DESIGN hookcomp \(d.component.id & 0xFFFF) type \(d.component.type) ops \(d.component.ops.filter { !$0.isEmpty }) at \(d.x),\(d.y) \(d.w)x\(d.h) hidden? hooks \(d.component.hooks.keys.sorted())")
		}
		for d in candidates.prefix(6) {
			print("DESIGN tap \(d.component.id & 0xFFFF) ops \(d.component.ops.filter { !$0.isEmpty })")
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

