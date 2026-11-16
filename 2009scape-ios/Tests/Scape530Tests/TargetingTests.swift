import Foundation
import XCTest
@testable import Scape530

/// Chat heads and model components, "Use" / spell target modes, and inventory drags.
final class TargetingTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}

	func encode(_ m: ClientMessage) -> [UInt8] {
		var a = IsaacRandom(seed: [1, 2, 3, 4])
		var b = IsaacRandom(seed: [1, 2, 3, 4])
		let bytes = m.encode(&a)
		let key = b.nextKey()
		return [bytes[0] &- UInt8(truncatingIfNeeded: key)] + bytes.dropFirst()
	}

	// MARK: packets (no cache)

	func testUseAndSpellPacketBytes() {
		// Opcode byte is returned with the ISAAC key removed. Bodies are written from rt4 `MiniMenu.doAction`.
		let c = 0x0102_0304
		XCTAssertEqual(encode(.useItemOnNpc(component: c, slot: 5, itemId: 1511, npc: 0x0102)),
			[115, 0x02, 0x01, 0x04, 0x03, 5, 0, 0x02, 0x01, UInt8(truncatingIfNeeded: 0xE7 + 128), 0x05])
		XCTAssertEqual(encode(.useItemOnPlayer(component: c, slot: 5, itemId: 1511, player: 7)),
			[248, 135, 0, 0x05, 0xE7, 0, 5, 0x02, 0x01, 0x04, 0x03])
		XCTAssertEqual(encode(.useItemOnLoc(component: c, slot: 5, itemId: 1511, locId: 0x1234, x: 3222, z: 3218)),
			[134, UInt8(truncatingIfNeeded: 3222 >> 8), UInt8(truncatingIfNeeded: (3222 & 0xFF) + 128), 0x05, 0xE7, UInt8(truncatingIfNeeded: 3218 & 0xFF), UInt8(truncatingIfNeeded: 3218 >> 8), 0, 5,
			 0x02, 0x01, 0x04, 0x03, 0x12, UInt8(truncatingIfNeeded: 0x34 + 128)])
		XCTAssertEqual(encode(.useItemOnObj(component: c, slot: 5, itemId: 1511, objId: 995, x: 100, z: 200)),
			[101, UInt8(truncatingIfNeeded: 100 + 128), 0, 5, 0, 0xE7, 0x05, UInt8(truncatingIfNeeded: 995 & 0xFF), UInt8(truncatingIfNeeded: 995 >> 8), UInt8(truncatingIfNeeded: 200 + 128), 0, 0x02, 0x01, 0x04, 0x03])
		XCTAssertEqual(encode(.useItemOnItem(component: c, slot: 5, itemId: 1511, targetComponent: 0x0A0B_0C0D, targetSlot: 9, targetItem: 590)),
			[27, 0, 5, 0x0D, 0x0C, 0x0B, 0x0A, 9, 0, 0x04, 0x03, 0x02, 0x01, UInt8(truncatingIfNeeded: 0xE7 + 128), 0x05, UInt8(truncatingIfNeeded: (590 & 0xFF) + 128), UInt8(truncatingIfNeeded: 590 >> 8)])
		let spell = (192 << 16) | 16
		XCTAssertEqual(encode(.spellOnNpc(component: spell, child: 3, npc: 7)),
			[239, 16, 0, 192, 0, 0, UInt8(truncatingIfNeeded: 3 + 128), UInt8(truncatingIfNeeded: 7 + 128), 0])
		XCTAssertEqual(encode(.spellOnPlayer(component: spell, child: 3, player: 7)),
			[195, 0, UInt8(truncatingIfNeeded: 3 + 128), 16, 0, 192, 0, UInt8(truncatingIfNeeded: 7 + 128), 0])
		XCTAssertEqual(encode(.spellOnItem(component: spell, child: 3, targetComponent: 0x0095_0000, targetSlot: 4, targetItem: 590)),
			[253, 16, 0, 192, 0, UInt8(truncatingIfNeeded: 4 + 128), 0, 0, 0, 0x95, 0, 0x02, UInt8(truncatingIfNeeded: (590 & 0xFF) + 128), 3, 0])
		XCTAssertEqual(encode(.spellOnTile(component: spell, child: 3, x: 3200, z: 3210)),
			[131, 192, 0, 16, 0, UInt8(truncatingIfNeeded: 3200 >> 8), UInt8(truncatingIfNeeded: (3200 & 0xFF) + 128), UInt8(truncatingIfNeeded: 3 + 128), 0, UInt8(truncatingIfNeeded: 3210 >> 8), UInt8(truncatingIfNeeded: (3210 & 0xFF) + 128)])
		XCTAssertEqual(encode(.invItemOp(action: 25, component: 0x0095_0000, slot: 4, itemId: 590)),
			[81, 0, UInt8(truncatingIfNeeded: 4 + 128), 0x02, 0x4E, 0, 0, 0, 0x95])
	}

	func testMoveItemPacket() {
		// opcode 231: p2(to), ip4(component), p2add(from), p1sub(inserting)
		XCTAssertEqual(encode(.moveItem(component: 0x0095_0000, from: 4, to: 9, insert: false)),
			[231, 0, 9, 0, 0, 0x95, 0, 0, UInt8(truncatingIfNeeded: 4 + 128), 128])
		XCTAssertEqual(encode(.moveItem(component: 0x0095_0000, from: 4, to: 9, insert: true)).last, 127)
	}

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

	func startedClient(width: Int = 1015, height: Int = 469) throws -> GameClient {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		try replay(client)
		_ = try client.frame(width: width, height: height)
		_ = try client.frame(width: width, height: height)
		return client
	}

	// MARK: chat heads

	/// A fresh client showing interface 149 (the inventory) as the top level with the given items.
	func inventoryClient(items: [(Int, Int32)]) throws -> (GameClient, Int) {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
		client.handle(.loggedIn(Login.Success(staffModLevel: 0, blackmarks: 0, underage: false, parentalChatConsent: false, parentalAdvertConsent: false, mapQuickChat: false, mouseRecorder: false, selfId: 2047, member: false, mapMembers: false, firstOpcode: 0, firstLength: 0)))
		client.handle(.message(.ifOpenTop(id: 149, reset: 0)))
		let comp = 149 << 16
		client.handle(.message(.invFull(component: Int32(comp), inv: 93, items: items.map { ServerMessage.InvItem(id: $0.0, count: $0.1) })))
		_ = try client.frame(width: 765, height: 503)
		return (client, comp)
	}

	/// An npc dialogue (interface 242) with the npc's chat head, injected into the recorded session's chatbox.
	func testNpcChatHeadRenders() throws {
		let client = try startedClient()
		let s = client.store
		// The first npc with head models, say hello with its head and the "happy" chat animation.
		var npcId = -1
		for id in 0..<4000 { if let t = try s.npc(id), !t.headModels.isEmpty, t.name != "null" { npcId = id; break } }
		XCTAssertNotEqual(npcId, -1)
		let container = Int32(752 << 16 | 12)
		client.handle(.message(.ifOpenSub(parent: container, component: 242, type: 1)))
		client.handle(.message(.ifSetNpcHead(component: Int32(242 << 16 | 2), npc: npcId)))
		client.handle(.message(.ifSetText(component: Int32(242 << 16 | 3), text: "Gielinor Guide")))
		client.handle(.message(.ifSetText(component: Int32(242 << 16 | 4), text: "Greetings! I see you are a new arrival to this land.")))
		client.handle(.message(.ifSetAnim(component: Int32(242 << 16 | 2), seq: 588)))
		for _ in 0..<3 { _ = try client.frame(width: 1015, height: 469) }
		let r = try client.frame(width: 1015, height: 469)
		try save(r, "targeting-chat-head")
		let head = try XCTUnwrap(client.ui.drawn.first { $0.component.id == 242 << 16 | 2 })
		XCTAssertEqual(head.component.modelType, 2)
		var colours = Set<UInt32>()
		for y in head.y..<(head.y + head.h) { for x in head.x..<(head.x + head.w) { colours.insert(r.pixels[y * r.width + x]) } }
		print("chat head \(head.w)x\(head.h) at \(head.x),\(head.y): \(colours.count) colours, npc \(npcId)")
		XCTAssertGreaterThan(colours.count, 30, "the head model is drawn")
		// The animation advances with client cycles.
		let before = client.host.game.interfaces.modelAnim[head.component.ref]
		for _ in 0..<40 { client.host.cycle() }
		_ = try client.frame(width: 1015, height: 469)
		let after = client.host.game.interfaces.modelAnim[head.component.ref]
		XCTAssertNotNil(after)
		XCTAssertNotEqual(before, after)
	}

	func testPlayerHeadAndGenericModelComponent() throws {
		let client = try startedClient()
		let container = Int32(752 << 16 | 12)
		client.handle(.message(.ifOpenSub(parent: container, component: 242, type: 1)))
		client.handle(.message(.ifSetPlayerHead(component: Int32(242 << 16 | 2))))
		_ = try client.frame(width: 1015, height: 469)
		let r = try client.frame(width: 1015, height: 469)
		try save(r, "targeting-player-head")
		let head = try XCTUnwrap(client.ui.drawn.first { $0.component.id == 242 << 16 | 2 })
		XCTAssertEqual(head.component.modelType, 3)
		var colours = Set<UInt32>()
		for y in head.y..<(head.y + head.h) { for x in head.x..<(head.x + head.w) { colours.insert(r.pixels[y * r.width + x]) } }
		XCTAssertGreaterThan(colours.count, 30, "own player head is drawn")
		// IF_SETMODEL: a plain cache model (an item model) in the same component.
		client.handle(.message(.ifSetModel(component: Int32(242 << 16 | 2), model: 2635)))
		XCTAssertEqual(client.ui.drawn.first { $0.component.id == 242 << 16 | 2 }?.component.modelType ?? 3, 3)
		_ = try client.frame(width: 1015, height: 469)
		XCTAssertEqual(client.host.component(ComponentRef(id: 242 << 16 | 2))?.modelType, 1)
	}

	// MARK: target modes

	func pickableNpc(_ client: GameClient) throws -> (id: Int, pick: WorldPick) {
		for (id, a) in client.world.ctx.npcs.sorted(by: { $0.key < $1.key }) {
			guard let t = a.npcType, t.interactive else { continue }
			return (id, WorldPick(hits: [Int64(id) << 32 | 0x2000_0000], tile: (x: 50, z: 50)))
		}
		throw XCTSkip("no npc in the recorded session")
	}

	func testUseModeMenuAndPacket() throws {
		let client = try startedClient()
		let npc = try pickableNpc(client)
		let type = try XCTUnwrap(client.world.ctx.npcs[npc.id]?.npcType)
		let label = "<col=ff9040>Bronze axe<col=ffffff>"
		client.interaction.target = .use(component: 149 << 16, slot: 3, itemId: 1351, label: label)
		let menu = MenuBuilder.build(world: client.world, pick: npc.pick, walkText: "Walk here", playerOptions: [], target: client.interaction.target)
		let lines = (0..<menu.count).map { menu.text($0) }
		print("use-mode menu: \(lines)")
		XCTAssertEqual(menu.entries[0].op, "Cancel")
		XCTAssertFalse(menu.entries.contains { $0.action == Menu.Action.walkHere }, "no walk entry while an item is selected")
		let e = try XCTUnwrap(menu.entries.first { $0.action == Menu.Action.useOnNpc })
		XCTAssertEqual(e.op, "Use")
		XCTAssertTrue(e.base.hasPrefix(label + " -> <col=ffff00>" + type.name), e.base)
		XCTAssertEqual(menu.entries[menu.top].action, Menu.Action.useOnNpc)
		XCTAssertEqual(menu.hoverText.hasPrefix("Use "), true)

		var sent: [ClientMessage] = []
		client.interaction.onSend = { sent.append($0) }
		client.doAction(menu, menu.top, clickX: 10, clickY: 10)
		XCTAssertNil(client.interaction.target, "an action leaves target mode")
		guard case let .useItemOnNpc(c, slot, item, n)? = sent.last else { return XCTFail("sent \(sent)") }
		XCTAssertEqual([c, slot, item, n], [149 << 16, 3, 1351, npc.id])
	}

	func testSpellModeMenuAndPacket() throws {
		let client = try startedClient()
		let npc = try pickableNpc(client)
		let spell = 192 << 16 | 25
		// Mask 2 (npc): walk stays, the npc gets "Cast".
		client.interaction.target = .spell(component: spell, child: -1, mask: 2, param: -1, verb: "Cast", label: "<col=00ff00>Wind Strike<col=ffffff>")
		var menu = MenuBuilder.build(world: client.world, pick: npc.pick, walkText: "Walk here", playerOptions: [], target: client.interaction.target)
		XCTAssertTrue(menu.entries.contains { $0.action == Menu.Action.walkHere })
		let e = try XCTUnwrap(menu.entries.first { $0.action == Menu.Action.spellOnNpc })
		XCTAssertEqual(e.op, "Cast")
		XCTAssertTrue(e.base.hasPrefix("<col=00ff00>Wind Strike<col=ffffff> -> <col=ffff00>"), e.base)
		var sent: [ClientMessage] = []
		client.interaction.onSend = { sent.append($0) }
		client.doAction(menu, try XCTUnwrap(menu.entries.firstIndex { $0.action == Menu.Action.spellOnNpc }), clickX: 10, clickY: 10)
		guard case let .spellOnNpc(c, child, n)? = sent.last else { return XCTFail("sent \(sent)") }
		XCTAssertEqual([c, child, n], [spell, -1, npc.id])
		XCTAssertNil(client.interaction.target)

		// A mask without npcs offers nothing on them; tapping "Cancel" just leaves the mode.
		client.interaction.target = .spell(component: spell, child: -1, mask: 8, param: -1, verb: "Cast", label: "x")
		menu = MenuBuilder.build(world: client.world, pick: npc.pick, walkText: "Walk here", playerOptions: [], target: client.interaction.target)
		XCTAssertFalse(menu.entries.contains { $0.action == Menu.Action.spellOnNpc })
		sent.removeAll()
		client.doAction(menu, 0, clickX: 0, clickY: 0)
		XCTAssertTrue(sent.isEmpty)
		XCTAssertNil(client.interaction.target)
	}

	// MARK: inventory

	func testInventoryMenuUseAndItemOnItem() throws {
		let (client, comp) = try inventoryClient(items: [(1351, 1), (590, 1), (995, 500)])
		let c = try XCTUnwrap(client.ui.drawn.first { $0.component.id == comp }?.component)
		print("inventory events \(String(c.events, radix: 16)), options \(c.invOptions)")
		let hit = try XCTUnwrap(client.inventorySlot(atX: client.ui.origins[c.ref]!.x + 5, y: client.ui.origins[c.ref]!.y + 5))
		XCTAssertEqual(hit.slot, 0)
		let item = try XCTUnwrap(client.inventoryItem(c, 0))
		let menu = client.inventorySlotMenu(c, slot: 0, item: item)
		let lines = (0..<menu.count).map { menu.text($0) }
		print("slot menu: \(lines)")
		XCTAssertEqual(menu.entries[0].op, "Cancel")
		XCTAssertTrue(lines.contains { $0.hasPrefix("Use <col=ff9040>") })
		XCTAssertTrue(lines.contains { $0.hasPrefix("Examine <col=ff9040>") })
		XCTAssertTrue(lines.contains { $0.hasPrefix("Drop <col=ff9040>") })

		// "Use" selects the item: target mode, the slot outlined in white.
		var sent: [ClientMessage] = []
		client.interaction.onSend = { sent.append($0) }
		client.doAction(menu, try XCTUnwrap(menu.entries.firstIndex { $0.action == Menu.Action.selectUse }), clickX: 0, clickY: 0)
		guard case let .use(tc, ts, ti, tl)? = client.interaction.target else { return XCTFail("not in use mode") }
		XCTAssertEqual([tc, ts, ti], [comp, 0, 1351])
		XCTAssertTrue(tl.hasPrefix("<col=ff9040>"))
		XCTAssertTrue(sent.isEmpty)
		let r = try client.frame(width: 765, height: 503)
		try save(r, "targeting-use-selected")

		// Tapping another slot uses the item on it, and leaves target mode.
		let o = try XCTUnwrap(client.ui.origins[c.ref])
		client.tap(x: o.x + (32 + c.invMarginX) * 1 + 5, y: o.y + 5)
		guard case let .useItemOnItem(uc, us, ui, utc, uts, uti)? = sent.last else { return XCTFail("sent \(sent)") }
		XCTAssertEqual([uc, us, ui, utc, uts, uti], [comp, 0, 1351, comp, 1, 590])
		XCTAssertNil(client.interaction.target)
	}

	func testInventoryTapUsesDefaultOpAndLongPressOpensMenu() throws {
		let (client, comp) = try inventoryClient(items: [(1351, 1), (590, 1)])
		let c = try XCTUnwrap(client.ui.drawn.first { $0.component.id == comp }?.component)
		let o = try XCTUnwrap(client.ui.origins[c.ref])
		var sent: [ClientMessage] = []
		client.interaction.onSend = { sent.append($0) }
		client.tap(x: o.x + 5, y: o.y + 5)
		guard case let .invItemOp(action, ic, slot, item)? = sent.last else { return XCTFail("sent \(sent)") }
		print("default op action \(action)")
		XCTAssertEqual([ic, slot, item], [comp, 0, 1351])
		XCTAssertTrue(Menu.Action.itemOps.contains(action) || Menu.Action.invOptions.contains(action))
		XCTAssertEqual(client.state.interfaces.inventoryUI.pressed?.slot, 0, "pressed highlight")
		for _ in 0..<15 { client.cycleInventoryUI() }
		XCTAssertNil(client.state.interfaces.inventoryUI.pressed)

		XCTAssertTrue(client.longPress(x: o.x + 5, y: o.y + 5))
		let popup = try XCTUnwrap(client.interaction.popup)
		XCTAssertGreaterThan(popup.menu.count, 2)
	}

	func testInventoryDragSendsMoveItem() throws {
		let (client, comp) = try inventoryClient(items: [(1351, 1), (590, 1), (995, 500)])
		let c = try XCTUnwrap(client.ui.drawn.first { $0.component.id == comp }?.component)
		let o = try XCTUnwrap(client.ui.origins[c.ref])
		let slotX = { (s: Int) in o.x + (32 + c.invMarginX) * s + 5 }
		var sent: [ClientMessage] = []
		client.interaction.onSend = { sent.append($0) }
		XCTAssertTrue((c.events >> 28) & 1 != 0 || (c.events >> 29) & 1 != 0, "inventory 149 allows swaps")
		XCTAssertTrue(client.longPress(x: slotX(0), y: o.y + 5))
		XCTAssertNotNil(client.interaction.popup, "menu while the finger is still")
		client.dragMove(x: slotX(0) + 3, y: o.y + 5)
		XCTAssertFalse(client.isDraggingItem, "inside the dead zone")
		client.dragMove(x: slotX(1) - 8, y: o.y + 9)
		XCTAssertTrue(client.isDraggingItem)
		XCTAssertNil(client.interaction.popup)
		let r = try client.frame(width: 765, height: 503)
		try save(r, "targeting-drag")
		client.dragEnd(x: slotX(2), y: o.y + 5)
		guard case let .moveItem(mc, from, to, insert)? = sent.last else { return XCTFail("sent \(sent)") }
		XCTAssertEqual([mc, from, to], [comp, 0, 2])
		XCTAssertFalse(insert)
		XCTAssertFalse(client.isDraggingItem)
		// The move is applied locally at once (swap).
		XCTAssertEqual(client.state.interfaces.invSlots[comp]?[2]?.id, 1351)
		XCTAssertEqual(client.state.interfaces.invSlots[comp]?[0]?.id, 995)
		var bytes = encode(.moveItem(component: comp, from: 0, to: 2, insert: false))
		XCTAssertEqual(bytes[0], 231)
		bytes.removeFirst()
		XCTAssertEqual(bytes, [0, 2, 0, 0, 0x95, 0, 0, 128, 128])
	}
}
