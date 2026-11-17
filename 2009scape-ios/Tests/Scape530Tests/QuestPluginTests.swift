import XCTest
@testable import Scape530

/// The quest helper plugin's state handling, panel text and persistence (no client).
final class QuestPluginTests: XCTestCase {
	/// The context only holds its manager weakly.
	var keep: [PluginManager] = []

	func make(store: PluginSettingsStore? = nil, catalog: [QuestDef]? = nil) -> (PluginManager, QuestHelperPlugin, PluginContext) {
		let m = PluginManager(registerBuiltIns: false)
		if let store { m.useSettingsStore(store) }
		let p = catalog.map { QuestHelperPlugin(catalog: $0) } ?? QuestHelperPlugin()
		m.register(p)
		m.setEnabled(true, id: "questHelper")
		keep.append(m)
		return (m, p, PluginContext.detached(manager: m))
	}

	func facts(_ varps: [Int: Int], items: [Int: Int] = [:]) -> QuestFactsSnapshot {
		var f = QuestFactsSnapshot(); f.varps = varps; f.inventory = items
		return f
	}

	func testIsABuiltInPluginOffByDefault() {
		let m = PluginManager()
		let p = m.plugin(ofType: QuestHelperPlugin.self)
		XCTAssertNotNil(p)
		XCTAssertFalse(m.isEnabled("questHelper"))
		XCTAssertEqual(p?.config.string("panel"), "Top left")
		XCTAssertTrue(p!.subscriptions.contains(.overlayScene) && p!.subscriptions.contains(.overlayHUD))
	}

	func testFollowsTheQuestThatChangedLast() {
		let (_, p, ctx) = make()
		p.testFacts = facts([:])
		p.refresh(ctx)
		XCTAssertNil(p.activeQuestId, "nothing in progress")
		XCTAssertNil(p.evaluation)
		// Starting Cook's Assistant moves its list varp from 0 to 1.
		p.testFacts = facts([29: 1])
		p.refresh(ctx)
		XCTAssertEqual(p.activeQuestId, "cooks_assistant")
		XCTAssertEqual(p.evaluation?.step?.id, "milk")
		XCTAssertEqual(p.evaluation?.status, .inProgress)
		XCTAssertEqual(p.evaluation?.stepCount, 5)
		// Sheep Shearer starts later: the helper follows it.
		p.testFacts = facts([29: 1, 179: 20])
		p.refresh(ctx)
		XCTAssertEqual(p.activeQuestId, "sheep_shearer")
		XCTAssertTrue(p.isAutomatic)
		// Finishing it falls back to the other quest in progress.
		p.testFacts = facts([29: 1, 179: 21])
		p.refresh(ctx)
		XCTAssertEqual(p.activeQuestId, "cooks_assistant")
	}

	func testQuestsAlreadyInProgressAtLoginDoNotCountAsChanges() {
		let (_, p, ctx) = make()
		p.onLogin(ctx)
		// Login sends every varp before the first tick: two quests in progress, the first in catalog order is followed.
		p.testFacts = facts([179: 20, 29: 1])
		p.refresh(ctx)
		XCTAssertEqual(p.activeQuestId, "cooks_assistant")
		// A relog resets the baseline.
		p.onLogin(ctx)
		p.testFacts = facts([179: 20])
		p.refresh(ctx)
		XCTAssertEqual(p.activeQuestId, "sheep_shearer")
	}

	func testChoosingAQuestOverridesAutoPick() {
		let (_, p, ctx) = make()
		p.testFacts = facts([29: 1, 179: 20])
		p.refresh(ctx)
		p.setActive("sheep_shearer", ctx)
		XCTAssertFalse(p.isAutomatic)
		XCTAssertEqual(p.activeQuestId, "sheep_shearer")
		p.testFacts = facts([29: 1, 179: 20, 63: 1])   // Rune Mysteries starts
		p.refresh(ctx)
		XCTAssertEqual(p.activeQuestId, "sheep_shearer", "a chosen quest stays")
		// A quest that is not started can be chosen to see where to begin.
		p.setActive("doric" + "s_quest", ctx)
		XCTAssertEqual(p.evaluation?.step?.id, "start")
		XCTAssertEqual(p.evaluation?.status, .notStarted)
		p.setActive("nonsense", ctx)
		XCTAssertTrue(p.isAutomatic, "an unknown id goes back to automatic")
		p.setActive(nil, ctx)
		XCTAssertTrue(p.isAutomatic)
	}

	func testListEntriesForTheApp() {
		let (_, p, ctx) = make()
		p.testFacts = facts([29: 2, 179: 20, 107: 4], items: [1735: 1])
		p.refresh(ctx)
		let byId = Dictionary(uniqueKeysWithValues: p.entries.map { ($0.id, $0) })
		XCTAssertEqual(p.entries.count, QuestCatalog.all.count)
		XCTAssertEqual(byId["cooks_assistant"]?.status, .complete)
		XCTAssertNil(byId["cooks_assistant"]?.stepText)
		XCTAssertEqual(byId["sheep_shearer"]?.status, .inProgress)
		XCTAssertTrue(byId["sheep_shearer"]?.stepText?.contains("Shear sheep") == true, byId["sheep_shearer"]?.stepText ?? "")
		XCTAssertEqual(byId["restless_ghost"]?.status, .inProgress)
		XCTAssertEqual(byId["rune_mysteries"]?.status, .notStarted)
		XCTAssertTrue(byId["rune_mysteries"]?.stepText?.contains("Duke Horacio") == true)
		XCTAssertEqual(byId["sheep_shearer"]?.points, 1)
		XCTAssertEqual(byId["prince_ali_rescue"]?.points, 3)
		XCTAssertEqual(p.entries.filter(\.isActive).count, 1)
		XCTAssertEqual(byId["restless_ghost"]?.requirements, ["Be unafraid of a level 13 skeleton."])
	}

	func testLatchFlagsFollowTheInventoryAcrossTicks() {
		let (_, p, ctx) = make()
		p.testFacts = facts([67: 1], items: [1957: 1, 300: 1, 2146: 1, 221: 1])
		p.refresh(ctx)
		XCTAssertEqual(p.evaluation?.step?.id, "give")
		// Hetty takes the items: the helper moves on to the cauldron instead of back to gathering.
		p.testFacts = facts([67: 1])
		p.refresh(ctx)
		XCTAssertEqual(p.evaluation?.step?.id, "drink")
		// Quest complete: no step.
		p.testFacts = facts([67: 3])
		p.refresh(ctx)
		XCTAssertNil(p.evaluation?.step)
	}

	func testSkipAndChoicePersistPerAccount() {
		let store = InMemoryPluginSettingsStore()
		let (m, p, ctx) = make(store: store)
		p.accountKey = "alice"
		p.testFacts = facts([29: 1])
		p.refresh(ctx)
		XCTAssertEqual(p.evaluation?.step?.id, "milk")
		p.skipCurrentStep(ctx)
		XCTAssertEqual(p.evaluation?.step?.id, "flour")
		p.setActive("cooks_assistant", ctx)
		XCTAssertNotNil(store.data(forPlugin: QuestHelperPlugin.stateKey))
		// A new client with the same settings store: the choice comes back, with alice's skip.
		let (m2, p2, ctx2) = make(store: store)
		p2.accountKey = "alice"
		p2.testFacts = facts([29: 1])
		p2.refresh(ctx2)
		XCTAssertEqual(p2.activeQuestId, "cooks_assistant")
		XCTAssertEqual(p2.evaluation?.step?.id, "flour")
		// Another account does not inherit it.
		let (m3, p3, ctx3) = make(store: store)
		p3.accountKey = "bob"
		p3.testFacts = facts([29: 1])
		p3.refresh(ctx3)
		XCTAssertEqual(p3.evaluation?.step?.id, "milk")
		// The skip lasts until the quest's status changes (here: completed).
		p.testFacts = facts([29: 2])
		p.refresh(ctx)
		p.testFacts = facts([29: 0])
		p.setActive("cooks_assistant", ctx)
		p.refresh(ctx)
		XCTAssertEqual(p.evaluation?.step?.id, "start")
		withExtendedLifetime((m, m2, m3)) {}
	}

	func testPanelLinesShowStepAndChecklist() {
		let (_, p, ctx) = make()
		p.testFacts = facts([179: 20], items: [1759: 5])
		p.refresh(ctx)
		// Sheep Shearer with five balls of wool: still no shears, so the first step of the list that matches.
		let e = p.evaluation!
		let lines = p.panelLines(e, width: 180, measure: { $0.count * 6 }, includeChecklist: true)
		XCTAssertEqual(lines.first?.0, "Sheep Shearer  \(e.stepNumber)/\(e.stepCount)")
		XCTAssertTrue(lines.dropFirst().allSatisfy { !$0.0.isEmpty })
		XCTAssertTrue(lines.contains { $0.0 == "[ ] Shears" && $0.1 == 0xFF7070 }, "\(lines)")
		// Every wrapped line fits the width.
		XCTAssertTrue(lines.dropFirst().filter { !$0.0.hasPrefix("[") }.allSatisfy { $0.0.count * 6 <= 180 })
		let noList = p.panelLines(e, width: 180, measure: { $0.count * 6 }, includeChecklist: false)
		XCTAssertFalse(noList.contains { $0.0.hasPrefix("[") })
		// A checklist with counts and a banked item.
		var f = facts([29: 1], items: [1927: 1])
		f.bank = [1933: 1]
		p.testFacts = f
		p.setActive("cooks_assistant", ctx)
		let step = QuestCatalog.cooksAssistant.steps[1]
		let ev = QuestEvaluation(questId: "cooks_assistant", name: "Cook's Assistant", status: .inProgress, step: step, stepNumber: 2, stepCount: 5, checklist: QuestEngine.checklist(step, f))
		let l2 = p.panelLines(ev, width: 200, measure: { $0.count * 6 }, includeChecklist: true).map(\.0)
		XCTAssertTrue(l2.contains("[x] Bucket of milk") && l2.contains("[b] Pot of flour in bank") && l2.contains("[ ] Egg"), "\(l2)")
	}

	func testWrap() {
		let lines = QuestMarkerMath.wrap("Talk to the Cook in the Lumbridge Castle kitchen", width: 60, measure: { $0.count * 6 })
				XCTAssertTrue(lines.allSatisfy { $0.count * 6 <= 60 })
		XCTAssertEqual(lines.joined(separator: " "), "Talk to the Cook in the Lumbridge Castle kitchen")
		// A single long word is kept whole.
		XCTAssertEqual(QuestMarkerMath.wrap("Supercalifragilistic word", width: 30, measure: { $0.count * 6 }), ["Supercalifragilistic", "word"])
	}

	// MARK: off-screen marker math

	let vp = (x: 4, y: 4, w: 512, h: 334)

	func testEdgeMarkerPointsTowardsTheTarget() throws {
		// Yaw 0: north is straight ahead, so a target to the north is on the top edge, centred.
		let n = try XCTUnwrap(QuestMarkerMath.edgeMarker(dx: 0, dz: 30, yaw: 0, viewport: vp))
		XCTAssertEqual(n.x, vp.x + vp.w / 2)
		XCTAssertEqual(n.y, vp.y + 16)
		XCTAssertEqual(n.distance, 30)
		XCTAssertEqual(n.angle, 0, accuracy: 1e-9)
		// East of the player is to the right: right edge, vertically centred, arrow pointing right (90 degrees).
		let e = try XCTUnwrap(QuestMarkerMath.edgeMarker(dx: 20, dz: 0, yaw: 0, viewport: vp))
		XCTAssertEqual(e.x, vp.x + vp.w - 16)
		XCTAssertEqual(e.y, vp.y + vp.h / 2)
		XCTAssertEqual(e.angle, Double.pi / 2, accuracy: 1e-9)
		// South is behind: bottom edge, arrow pointing down.
		let s = try XCTUnwrap(QuestMarkerMath.edgeMarker(dx: 0, dz: -12, yaw: 0, viewport: vp))
		XCTAssertEqual(s.y, vp.y + vp.h - 16)
		XCTAssertEqual(abs(s.angle), Double.pi, accuracy: 1e-9)
		// West: left edge.
		XCTAssertEqual(QuestMarkerMath.edgeMarker(dx: -9, dz: 0, yaw: 0, viewport: vp)?.x, vp.x + 16)
		// Turning the camera a quarter turn (yaw 512) makes north appear on the right (the projection's own rotation).
		let q = try XCTUnwrap(QuestMarkerMath.edgeMarker(dx: 0, dz: 30, yaw: 512, viewport: vp))
		XCTAssertEqual(q.x, vp.x + vp.w - 16)
		XCTAssertEqual(q.y, vp.y + vp.h / 2)
		XCTAssertNil(QuestMarkerMath.edgeMarker(dx: 0, dz: 0, yaw: 0, viewport: vp))
		// A diagonal lands on the edge the ray meets first, inside the inset rectangle.
		let d = try XCTUnwrap(QuestMarkerMath.edgeMarker(dx: 10, dz: 10, yaw: 0, viewport: vp))
		XCTAssertTrue(d.x > vp.x + vp.w / 2 && d.y < vp.y + vp.h / 2)
		XCTAssertTrue(d.x <= vp.x + vp.w - 16 && d.y >= vp.y + 16)
		XCTAssertEqual(d.distance, 14)
		XCTAssertEqual(d.angle, Double.pi / 4, accuracy: 1e-9)
	}

	func testEdgeMarkerStaysInsideForAnyDirection() {
		for yaw in stride(from: 0, to: 2048, by: 97) {
			for (dx, dz) in [(40, 3), (-25, 60), (7, -80), (-90, -2), (1, 1), (0, -1)] {
				guard let m = QuestMarkerMath.edgeMarker(dx: dx, dz: dz, yaw: yaw, viewport: vp) else { return XCTFail() }
				XCTAssertTrue(m.x >= vp.x + 15 && m.x <= vp.x + vp.w - 15 && m.y >= vp.y + 15 && m.y <= vp.y + vp.h - 15, "yaw \(yaw) (\(dx),\(dz)) -> \(m)")
			}
		}
	}

	func testOnScreenAndArrowHead() {
		XCTAssertTrue(QuestMarkerMath.onScreen(ScreenPoint(x: 200, y: 150), viewport: vp))
		XCTAssertFalse(QuestMarkerMath.onScreen(ScreenPoint(x: 2, y: 150), viewport: vp))
		XCTAssertFalse(QuestMarkerMath.onScreen(ScreenPoint(x: 200, y: 500), viewport: vp))
		XCTAssertFalse(QuestMarkerMath.onScreen(nil, viewport: vp))
		let up = QuestMarkerMath.arrowHead(x: 100, y: 100, angle: 0)
		XCTAssertEqual(up.count, 4)
		XCTAssertLessThan(up[0].y, 100, "the tip is above the centre when pointing up")
		let right = QuestMarkerMath.arrowHead(x: 100, y: 100, angle: Double.pi / 2)
		XCTAssertGreaterThan(right[0].x, 100)
	}
}
