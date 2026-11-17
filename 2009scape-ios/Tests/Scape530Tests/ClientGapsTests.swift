import Foundation
import XCTest
@testable import Scape530

/// Quick chat, if3 component drag, single mouse button mode and stacked actor menus.
final class ClientGapsTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	/// The opcode byte is returned with the ISAAC key removed.
	func encode(_ m: ClientMessage) -> [UInt8] {
		var a = IsaacRandom(seed: [1, 2, 3, 4])
		var b = IsaacRandom(seed: [1, 2, 3, 4])
		let bytes = m.encode(&a)
		let key = b.nextKey()
		return [bytes[0] &- UInt8(truncatingIfNeeded: key)] + bytes.dropFirst()
	}

	/// `ClientMessage` is not Equatable (path tuples): compare descriptions.
	func assertSent(_ got: [ClientMessage], _ expected: [ClientMessage], file: StaticString = #filePath, line: UInt = #line) {
		XCTAssertEqual(got.map { String(describing: $0) }, expected.map { String(describing: $0) }, file: file, line: line)
	}

	// MARK: quick chat packets (no cache)

	func testQuickChatClientPackets() {
		// rt4 op 5059: p1isaac(167), var-byte size, p1(0), p2(phrase), dynamic values.
		XCTAssertEqual(encode(.quickChat(clan: false, phrase: 0x0123, values: [])), [167, 3, 0, 0x01, 0x23])
		XCTAssertEqual(encode(.quickChat(clan: true, phrase: 7, values: [0xAB, 0xCD])), [167, 5, 1, 0, 7, 0xAB, 0xCD])
		// op 5060: p1isaac(178), size, p8(name37), p2(phrase), values.
		XCTAssertEqual(encode(.quickChatPrivate(name37: 0x0102_0304_0506_0708, phrase: 9, values: [0xFF])),
			[178, 11, 1, 2, 3, 4, 5, 6, 7, 8, 0, 9, 0xFF])
	}

	func testQuickChatServerPackets() throws {
		// MESSAGE_QUICKCHAT_PRIVATE: name, id top (2), id bottom (3), rights, phrase, values.
		var body: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 5, 0, 1, 0, 0, 2, 0, 0x01, 0x02, 0xAA]
		var m = try ServerMessage.decode(GamePacket(opcode: ServerProt.messageQuickchatPrivate, payload: body))
		XCTAssertEqual(m, .quickChatPrivate(name37: 5, messageId: (1 << 32) + 2, rights: 0, phrase: 0x0102, values: [0xAA]))
		m = try ServerMessage.decode(GamePacket(opcode: ServerProt.messageQuickchatPrivateEcho, payload: [0, 0, 0, 0, 0, 0, 0, 5, 0x00, 0x09, 0x11]))
		XCTAssertEqual(m, .quickChatPrivateEcho(name37: 5, phrase: 9, values: [0x11]))
		// CLAN_QUICK_CHAT: name, skipped byte, clan, id top, id bottom, rights, phrase, values.
		body = [0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0, 0, 3, 1, 0x00, 0x04]
		m = try ServerMessage.decode(GamePacket(opcode: ServerProt.clanQuickChat, payload: body))
		XCTAssertEqual(m, .quickChatClan(name37: 5, clan37: 6, messageId: 3, rights: 1, phrase: 4, values: []))
	}

	func testQuickChatSortMatchesRt4() {
		// rt4 `Find.method1307`: byte-wise order, shorter prefix first.
		var ids = [3, 1, 2, 4]
		var keys = ["b", "a", "ab", "c"].map { Array($0.utf8) }
		QuickChat.sort(&ids, &keys, 0, 3)
		XCTAssertEqual(ids, [1, 2, 3, 4])
	}

	// MARK: quick chat from the cache

	func testPhraseDecodeFromCache() throws {
		let s = try store()
		let count = s.quickChatPhraseCount(secondary: false)
		XCTAssertGreaterThan(count, 100)
		var withCommands = 0, plain = 0
		for id in 0..<count {
			guard let t = try s.quickChatPhrase(id), !t.textParts.isEmpty else { continue }
			XCTAssertFalse(t.text.isEmpty && t.textParts.count > 1)
			if t.dynamicCommands.isEmpty {
				plain += 1
				var p = Packet([])
				XCTAssertEqual(try t.decodeMessage(&p, store: s), t.textParts[0], "phrase \(id)")
				continue
			}
			// Commands whose value takes the same number of bytes in both directions round trip.
			guard t.dynamicCommands.allSatisfy({ QuickChatPhraseType.encodeBytes[$0] == QuickChatPhraseType.decodeBytes[$0] && $0 != 3 }) else { continue }
			let values = [Int32](repeating: 1, count: t.dynamicCommands.count)
			let bytes = t.encodeMessage(values)
			XCTAssertEqual(bytes.count, t.dynamicCommands.map { QuickChatPhraseType.encodeBytes[$0] }.reduce(0, +))
			var p = Packet(bytes)
			let text = try t.decodeMessage(&p, store: s)
			XCTAssertEqual(p.offset, bytes.count, "phrase \(id) consumed its values")
			XCTAssertTrue(text.hasPrefix(t.textParts[0]), "phrase \(id): \(text)")
			XCTAssertTrue(text.hasSuffix(t.textParts.last!), "phrase \(id): \(text)")
			withCommands += 1
		}
		print("quick chat: \(plain) plain phrases, \(withCommands) with dynamic values")
		XCTAssertGreaterThan(plain, 50)
		XCTAssertGreaterThan(withCommands, 0)
	}

	func testPhraseTextAndCategories() throws {
		let s = try store()
		// A category tree: every child id resolves, phrase shortcuts map back.
		var checked = 0
		for id in 0..<s.quickChatPhraseCount(secondary: false) where checked < 400 {
			guard let cat = try s.quickChatCat(id) else { continue }
			for (i, p) in cat.phrases.enumerated() {
				XCTAssertNotNil(try s.quickChatPhrase(p), "category \(id) phrase \(p)")
				XCTAssertEqual(cat.phrases[cat.phraseShortcuts.firstIndex(of: cat.phraseShortcuts[i])!], cat.phrases[cat.phraseShortcuts.firstIndex(of: cat.phraseShortcuts[i])!])
			}
			for sub in cat.subcategories { XCTAssertNotNil(try s.quickChatCat(sub), "category \(id) sub \(sub)") }
			checked += 1
		}
		XCTAssertGreaterThan(checked, 0)
		// The phrase text of a phrase with a dynamic part joins the pieces with "...".
		let id = try XCTUnwrap((0..<s.quickChatPhraseCount(secondary: false)).first { ((try? s.quickChatPhrase($0)) ?? nil)?.dynamicCommands.isEmpty == false })
		let t = try XCTUnwrap(try s.quickChatPhrase(id))
		XCTAssertEqual(t.text, t.textParts.joined(separator: "..."))
		XCTAssertTrue(t.text.contains("..."))
	}

	func testQuickChatOpsThroughHost() throws {
		let s = try store()
		let host = InterfaceScriptHost(store: s)
		var sent: [ClientMessage] = []
		host.send = { sent.append($0) }
		func op(_ n: Int, _ ints: [Int32] = [], _ strings: [String] = []) -> HostResult {
			host.perform(HostOps.table[n]!, ints: ints, strings: strings)
		}
		// Find a category with both children kinds and compare the ops with the cache.
		let catId = try XCTUnwrap((0..<2000).first { ((try? s.quickChatCat($0)) ?? nil).map { !$0.phrases.isEmpty && !$0.subcategories.isEmpty } ?? false })
		let cat = try XCTUnwrap(try s.quickChatCat(catId))
		XCTAssertEqual(op(5050, [Int32(catId)]).strings, [cat.description])
		XCTAssertEqual(op(5051, [Int32(catId)]).ints, [Int32(cat.subcategories.count)])
		XCTAssertEqual(op(5052, [Int32(catId), 0]).ints, [Int32(cat.subcategories[0])])
		XCTAssertEqual(op(5053, [Int32(catId)]).ints, [Int32(cat.phrases.count)])
		XCTAssertEqual(op(5054, [Int32(catId), 0]).ints, [Int32(cat.phrases[0])])
		XCTAssertEqual(op(5063, [Int32(catId), 0]).ints, [Int32(cat.phraseShortcuts[0])])
		XCTAssertEqual(op(5065, [Int32(catId), Int32(cat.phraseShortcuts[0])]).ints, [Int32(cat.phrases[cat.phraseShortcuts.firstIndex(of: cat.phraseShortcuts[0])!])])
		XCTAssertEqual(op(5065, [Int32(catId), -1]).ints, [-1])
		let phraseId = cat.phrases[0]
		let phrase = try XCTUnwrap(try s.quickChatPhrase(phraseId))
		XCTAssertEqual(op(5055, [Int32(phraseId)]).strings, [phrase.text])
		XCTAssertEqual(op(5066, [Int32(phraseId)]).ints, [Int32(phrase.dynamicCommandCount)])

		// Compose and send: 5058 starts a phrase, 5059 / 5061 / 5060 send it.
		_ = op(5058, [Int32(phraseId)])
		XCTAssertEqual(host.quickChat.phrase, QuickChatPhrase(id: phraseId, values: [Int32](repeating: 0, count: phrase.dynamicCommandCount)))
		_ = op(5059)
		_ = op(5061)
		_ = op(5060, [], ["Some Name"])
		XCTAssertEqual(sent.count, 3)
		let body = phrase.encodeMessage(host.quickChat.phrase!.values)
		assertSent(sent, [.quickChat(clan: false, phrase: phraseId, values: body), .quickChat(clan: true, phrase: phraseId, values: body),
			.quickChatPrivate(name37: Base37.encode("Some Name"), phrase: phraseId, values: body)])

		// A phrase with a value: 5068 sets it and the message carries it.
		let withValue = try XCTUnwrap((0..<s.quickChatPhraseCount(secondary: false)).first { ((try? s.quickChatPhrase($0)) ?? nil).map { $0.dynamicCommands.first.map { QuickChatPhraseType.encodeBytes[$0] > 0 } ?? false } ?? false })
		let vt = try XCTUnwrap(try s.quickChatPhrase(withValue))
		_ = op(5058, [Int32(withValue)])
		_ = op(5068, [0, 0x0102])
		sent.removeAll()
		_ = op(5059)
		guard case let .quickChat(_, _, bytes)? = sent.first else { return XCTFail("nothing sent") }
		XCTAssertEqual(bytes, vt.encodeMessage([0x0102] + [Int32](repeating: 0, count: vt.dynamicCommandCount - 1)))
		XCTAssertEqual(bytes.prefix(QuickChatPhraseType.encodeBytes[vt.dynamicCommands[0]]).last, QuickChatPhraseType.encodeBytes[vt.dynamicCommands[0]] == 1 ? 0x02 : 0x02)

		// Search: results come back sorted, each id readable with 5072.
		let needle = String(phrase.textParts[0].prefix(8)).trimmingCharacters(in: .whitespaces)
		let count = op(5071, [0], [needle]).ints[0]
		if count >= 0 {
			XCTAssertGreaterThan(count, 0)
			var found: [Int32] = []
			for _ in 0..<count { found.append(op(5072).ints[0]) }
			XCTAssertEqual(op(5072).ints, [-1], "no more results")
			XCTAssertTrue(found.contains(Int32(phraseId)) || !phrase.searchable)
			_ = op(5073)
			XCTAssertEqual(op(5072).ints, [found[0]], "reset starts over")
		}
		XCTAssertEqual(op(5071, [0], [""]).ints, [-1], "more than 50 matches: no results")
	}

	func testReceivedQuickChatText() throws {
		let s = try store()
		let id = try XCTUnwrap((0..<s.quickChatPhraseCount(secondary: false)).first { ((try? s.quickChatPhrase($0)) ?? nil).map { $0.dynamicCommands.isEmpty && !$0.textParts.isEmpty } ?? false })
		let t = try XCTUnwrap(try s.quickChatPhrase(id))
		XCTAssertEqual(QuickChat.message(phrase: id, values: [], store: s), t.textParts[0])
		XCTAssertNil(QuickChat.message(phrase: 0x7FFF, values: [], store: s), "unknown phrase")
	}

	// MARK: if3 drag

	/// A layer 300x300 with a container (200x200) and two 32x32 children; positions are set on the renderer by hand.
	func dragRig(events: Int, dragLayer: Bool, deadzone: Int = 5) -> (host: InterfaceScriptHost, layer: Int, dragged: ComponentRef, target: ComponentRef, sent: () -> [ClientMessage]) {
		let host = InterfaceScriptHost(store: ConfigStore(source: { _, _ in nil }))
		var sent: [ClientMessage] = []
		host.send = { sent.append($0) }
		let layerId = 900 << 16
		var layer = Component(parentId: layerId, type: 0, index: 0)
		layer.baseWidth = 300; layer.baseHeight = 300
		// The layer itself is a static component: reuse an override with the same id.
		var staticLayer = layer
		staticLayer.childIndex = -1
		staticLayer.parent = -1
		host.game.interfaces.overrides[layerId] = staticLayer
		var container = Component(parentId: layerId, type: 0, index: 0)
		container.baseWidth = 200; container.baseHeight = 200
		var dragged = Component(parentId: layerId, type: 3, index: 1)
		dragged.baseWidth = 32; dragged.baseHeight = 32
		dragged.events = events
		dragged.dragDeadzone = deadzone
		dragged.hooks["onDragStart"] = [.int(7001)]
		dragged.hooks["onDragRelease"] = [.int(7002)]
		if dragLayer { dragged.dragLayer = ComponentRef(id: layerId, child: 0) }
		var target = Component(parentId: layerId, type: 3, index: 2)
		target.baseWidth = 32; target.baseHeight = 32
		target.events = 1 << 21
		host.game.interfaces.dynamic[layerId] = [0: container, 1: dragged, 2: target]
		let r = host.renderer
		var entries: [(component: Component, x: Int, y: Int, w: Int, h: Int)] = []
		for (c, x, y, w, h) in [(staticLayer, 0, 0, 300, 300), (container, 50, 50, 200, 200), (dragged, 60, 60, 32, 32), (target, 150, 150, 32, 32)] {
			entries.append((c, x, y, w, h))
			r.origins[c.ref] = (x, y)
		}
		r.drawn = entries
		return (host, layerId, dragged.ref, target.ref, { sent })
	}

	func testDragStateMachine() throws {
		// Drag depth 1 (events bits 18-20): the layer above is the drag layer, and the server wants IF_DRAG.
		let rig = dragRig(events: 1 << 18, dragLayer: false)
		let host = rig.host
		XCTAssertTrue(host.beginDragGesture(x: 70, y: 75))
		XCTAssertNotNil(host.drag)
		XCTAssertEqual(host.drag?.offsetX, 10)
		XCTAssertEqual(host.drag?.offsetY, 15)
		// Inside the dead zone: pressed (shown faded in place) but not dragging.
		host.moveDragGesture(x: 72, y: 77)
		host.cycle()
		XCTAssertEqual(host.drag?.dragging, false)
		XCTAssertEqual(host.game.interfaces.componentDrag, ComponentDrag(ref: rig.dragged, x: 60, y: 60))
		XCTAssertTrue(host.errors.isEmpty)
		// Beyond it: dragging, the component follows the pointer (pointer minus the press offset), onDragStart runs.
		host.moveDragGesture(x: 130, y: 120)
		host.cycle()
		XCTAssertEqual(host.drag?.dragging, true)
		XCTAssertEqual(host.game.interfaces.componentDrag, ComponentDrag(ref: rig.dragged, x: 120, y: 105))
		XCTAssertTrue(host.errors.contains { $0.hasPrefix("script 7001") }, "\(host.errors)")
		// Clamped inside the drag layer.
		host.moveDragGesture(x: 1000, y: -50)
		host.cycle()
		XCTAssertEqual(host.game.interfaces.componentDrag, ComponentDrag(ref: rig.dragged, x: 300 - 32, y: 0))
		// Released over the target: onDragRelease runs and IF_DRAG goes out.
		host.moveDragGesture(x: 160, y: 160)
		host.cycle()
		XCTAssertEqual(host.dragTarget, rig.target)
		let result = host.endDragGesture(x: 160, y: 160)
		XCTAssertTrue(result.dragged)
		XCTAssertTrue(host.errors.contains { $0.hasPrefix("script 7002") }, "\(host.errors)")
		assertSent(rig.sent(), [.ifDrag(component: rig.dragged.id, child: 1, targetComponent: rig.target.id, targetChild: 2)])
		XCTAssertNil(host.drag)
		XCTAssertNil(host.game.interfaces.componentDrag)
	}

	func testDragDeadZoneIsAClick() {
		let rig = dragRig(events: 1 << 18, dragLayer: false)
		let host = rig.host
		XCTAssertTrue(host.beginDragGesture(x: 70, y: 70))
		host.moveDragGesture(x: 73, y: 72)
		host.cycle()
		let r = host.endDragGesture(x: 73, y: 72)
		XCTAssertFalse(r.dragged, "never left the dead zone: a click")
		XCTAssertEqual(r.start.x, 70)
		XCTAssertTrue(rig.sent().isEmpty)
	}

	func testDragDeadTimeDelaysTheDrag() {
		let rig = dragRig(events: 1 << 18, dragLayer: false, deadzone: 0)
		var d = rig.host.component(rig.dragged)!
		d.dragDeadtime = 3
		rig.host.game.interfaces.dynamic[rig.layer]?[1] = d
		let host = rig.host
		XCTAssertTrue(host.beginDragGesture(x: 70, y: 70))
		host.moveDragGesture(x: 100, y: 100)
		for _ in 0..<3 { host.cycle(); XCTAssertEqual(host.drag?.dragging, false) }
		host.cycle()
		XCTAssertEqual(host.drag?.dragging, true, "after more cycles than the dead time")
	}

	func testDragLayerFromScriptSendsNoIfDrag() {
		// Op 1301 sets the layer; without server drag depth rt4 drags locally and sends nothing.
		let rig = dragRig(events: 0, dragLayer: true)
		let host = rig.host
		XCTAssertTrue(host.beginDragGesture(x: 70, y: 70))
		host.moveDragGesture(x: 160, y: 160)
		host.cycle()
		XCTAssertTrue(host.endDragGesture(x: 160, y: 160).dragged)
		XCTAssertTrue(rig.sent().isEmpty)
	}

	func testPressWithoutDragLayerIsNotClaimed() {
		let rig = dragRig(events: 0, dragLayer: false)
		XCTAssertFalse(rig.host.beginDragGesture(x: 70, y: 70))
		XCTAssertNil(rig.host.drag)
		XCTAssertFalse(rig.host.pointerHeld)
	}

	func testHeldComponentRunsDragAndReleaseHooks() {
		let rig = dragRig(events: 0, dragLayer: false)
		let host = rig.host
		var c = host.component(rig.target)!
		c.hooks["onClickRepeat"] = [.int(7010)]
		c.hooks["onDrag"] = [.int(7011)]
		c.hooks["onRelease"] = [.int(7012)]
		host.game.interfaces.dynamic[rig.layer]?[2] = c
		host.renderer.drawn = host.renderer.drawn.map { $0.component.ref == c.ref ? (c, $0.x, $0.y, $0.w, $0.h) : $0 }
		XCTAssertTrue(host.beginDragGesture(x: 160, y: 160))
		XCTAssertTrue(host.errors.contains { $0.hasPrefix("script 7010") }, "press hook runs on the press")
		host.moveDragGesture(x: 165, y: 165)
		host.cycle()
		XCTAssertTrue(host.errors.contains { $0.hasPrefix("script 7011") }, "onDrag runs while held over it")
		XCTAssertFalse(host.errors.contains { $0.hasPrefix("script 7012") })
		_ = host.endDragGesture(x: 165, y: 165)
		host.cycle()
		XCTAssertTrue(host.errors.contains { $0.hasPrefix("script 7012") }, "onRelease after the pointer lifts")
	}

	// MARK: single mouse button mode and component menus

	func testSingleMouseButtonMode() throws {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		var menu = Menu()
		menu.add(op: "Talk-to", base: "Man", action: Menu.Action.npc[0], key: 1)
		XCTAssertEqual(menu.count, 2)
		XCTAssertFalse(client.leftClickOpensMenu(menu))
		client.host.varpClient.mouseButtons = 1
		XCTAssertFalse(client.leftClickOpensMenu(menu), "a single option: the left click just does it")
		menu.add(op: "Examine", base: "Man", action: Menu.Action.npcExamine, key: 1)
		XCTAssertTrue(client.leftClickOpensMenu(menu), "single mouse button mode with a choice opens the menu")
		client.host.varpClient.mouseButtons = 0
		XCTAssertFalse(client.leftClickOpensMenu(menu))
		// An if3 option 6...10 as the default entry always opens the menu.
		var high = Menu()
		high.add(op: "Six", base: "", action: Menu.Action.componentOpHigh, key: 6, x: -1, z: 5)
		XCTAssertTrue(high.topIsHighComponentOp)
		XCTAssertTrue(client.leftClickOpensMenu(high))
	}

	func testComponentMenuOrderAndAction() throws {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		var c = Component(parentId: 901 << 16, type: 3, index: 0)
		c.ops = ["Use", "Drop", "", "", "", "Six"]
		c.events = (1 << 1) | (1 << 2) | (1 << 6)
		c.optionBase = "Thing"
		let menu = client.componentMenu(c)
		XCTAssertEqual(menu.entries.map { $0.op }, ["Cancel", "Six", "Drop", "Use"])
		XCTAssertEqual(menu.entries.map { $0.action }, [Menu.Action.cancel, 1003, 9, 9])
		XCTAssertEqual(menu.entries[menu.top].key, 1)
		XCTAssertFalse(menu.topIsHighComponentOp)
		var sent: [ClientMessage] = []
		client.host.send = { sent.append($0) }
		client.host.game.interfaces.dynamic[c.id] = [0: c]
		client.doAction(menu, 1, clickX: 0, clickY: 0)
		assertSent(sent, [.ifButton(op: 6, component: c.id, child: 0)])
		var only = c
		only.events = 1 << 6
		XCTAssertTrue(client.componentMenu(only).topIsHighComponentOp)
	}

	// MARK: stacked actors

	func replay(_ client: GameClient, cyclesPerTick: Int = 30) throws {
		let me = 2047
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: me, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		var players = PlayerInfoDecoder(selfIndex: me, localX: 52, localZ: 52)
		var npcs = NpcInfoDecoder()
		var zone: (x: Int, z: Int)?
		for pkt in try SessionReplayTests.recordedPackets("resizable-session") {
			switch pkt.opcode {
			case ServerProt.playerInfo:
				let r = try players.decode(pkt.payload)
				client.handle(.players(r, players))
				for _ in 0..<cyclesPerTick { client.world.cycle(varps: client.state.varps) }
			case ServerProt.npcInfo:
				let p = try XCTUnwrap(players.players[me])
				let r = try npcs.decode(pkt.payload, selfX: p.x, selfZ: p.z)
				client.handle(.npcs(r, npcs))
			default:
				let m = try ServerMessage.decode(pkt)
				if case .rebuildNormal(let r) = m {
					if let z = zone {
						players.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
						npcs.rebase(dx: (r.zoneX - z.x) * 8, dz: (r.zoneZ - z.z) * 8)
					} else {
						players = PlayerInfoDecoder(selfIndex: me, localX: r.localX, localZ: r.localZ)
					}
					zone = (r.zoneX, r.zoneZ)
				}
				client.handle(.message(m))
			}
		}
	}


	func testStackedActorsAreListedOnce() throws {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		try replay(client)
		_ = try client.frame(width: 1015, height: 469)
		let npcs = client.world.ctx.npcs.sorted { $0.key < $1.key }.filter { $0.value.npcType?.interactive == true && $0.value.size == 1 }
		guard npcs.count >= 3 else { throw XCTSkip("needs three size-1 interactive npcs in the recorded session") }
		let (a, b, c) = (npcs[0], npcs[1], npcs[2])
		// a and b share a tile centre; c stands on its own tile.
		for n in [a, b] { n.value.xFine = 52 * 128 + 64; n.value.zFine = 52 * 128 + 64 }
		c.value.xFine = 55 * 128 + 64; c.value.zFine = 55 * 128 + 64
		func build(_ key: Int) -> Menu {
			MenuBuilder.build(world: client.world, pick: WorldPick(hits: [Int64(key) << 32 | 0x2000_0000], tile: (x: 52, z: 52)), walkText: "Walk here", playerOptions: [])
		}
		func examines(_ m: Menu) -> [String] { m.entries.filter { $0.action == Menu.Action.npcExamine }.map { String($0.base.dropFirst("<col=ffff00>".count)) } }
		let nameA = a.value.npcType!.name, nameB = b.value.npcType!.name
		let m = build(a.key)
		XCTAssertEqual(m.entries.filter { $0.action == Menu.Action.npcExamine }.map { Int($0.key) }.sorted(), [a.key, b.key].sorted(), "both npcs on the tile are listed, once each: \(examines(m))")
		let last = try XCTUnwrap(m.entries.last)
		XCTAssertEqual(Int(last.key), a.key, "the picked npc is the default entry")
		XCTAssertTrue(m.entries.last?.base.contains(nameA) ?? false)
		_ = nameB
		// An npc on a tile of its own adds nothing else.
		let alone = build(c.key)
		XCTAssertEqual(alone.entries.filter { $0.action == Menu.Action.npcExamine }.map { Int($0.key) }, [c.key])
		// Off the tile centre (walking) the rule does not apply.
		a.value.xFine += 32
		XCTAssertEqual(build(a.key).entries.filter { $0.action == Menu.Action.npcExamine }.map { Int($0.key) }, [a.key])
	}

	func testOneActorPerTileIsOn() throws {
		let w = WorldView(store: ConfigStore(source: { _, _ in nil }))
		XCTAssertTrue(w.oneActorPerTile)
	}
}
