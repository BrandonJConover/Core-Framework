import Foundation
import XCTest
@testable import Scape530

/// A plugin that records what the manager hands it.
final class RecordingPlugin: ClientPlugin {
	let id: String
	let name = "Recorder"
	var enabled = false
	let config = PluginConfig([.toggle("flag", "Flag", false), .number("n", "N", 5, min: 0, max: 10), .list("l", "L", ["a"])])
	var subscriptions: PluginSubscription
	var events: [String] = []
	var menuCalls = 0

	init(id: String = "rec", subscriptions: PluginSubscription) {
		self.id = id
		self.subscriptions = subscriptions
	}

	func onGameTick(_ ctx: PluginContext) { events.append("tick") }
	func onClientCycle(_ ctx: PluginContext) { events.append("cycle") }
	func onLogin(_ ctx: PluginContext) { events.append("login") }
	func onLogout(_ ctx: PluginContext) { events.append("logout") }
	func startUp(_ ctx: PluginContext) { events.append("start") }
	func shutDown(_ ctx: PluginContext) { events.append("stop") }
	func onStatChanged(_ c: StatChange, _ ctx: PluginContext) { events.append("stat\(c.skill):\(c.xpDelta)") }
	func onContainerChanged(_ c: ContainerChange, _ ctx: PluginContext) { events.append("inv\(c.inventory):\(c.slots.count)") }
	func onChatMessage(_ l: ChatLine, _ ctx: PluginContext) { events.append("chat:\(l.message)") }
	func onActorSpawned(_ a: ActorSnapshot, _ ctx: PluginContext) { events.append("spawn:\(a.name)") }
	func onActorDespawned(_ a: ActorSnapshot, _ ctx: PluginContext) { events.append("despawn:\(a.name)") }
	func onGroundItemSpawned(_ g: GroundItemSnapshot, _ ctx: PluginContext) { events.append("gspawn:\(g.type)x\(g.amount)@\(g.tileX),\(g.tileZ)") }
	func onGroundItemDespawned(_ g: GroundItemSnapshot, _ ctx: PluginContext) { events.append("gdespawn:\(g.type)") }
	func onAnimationChanged(_ c: AnimationChange, _ ctx: PluginContext) { events.append("anim:\(c.oldAnimation)>\(c.actor.animation)") }
	func onHitsplat(_ h: HitsplatEvent, _ ctx: PluginContext) { events.append("hit:\(h.damage)") }
	func modifyMenu(_ menu: inout Menu, source: MenuSource, _ ctx: PluginContext) { menuCalls += 1 }
}

func testActor(_ index: Int, name: String = "Man", npc: Bool = true, anim: Int = -1, hitUntil: [Int] = [0, 0, 0, 0], damage: [Int] = [0, 0, 0, 0]) -> ActorSnapshot {
	ActorSnapshot(key: ActorKey(isNpc: npc, index: index), isSelf: false, name: name, npcId: npc ? 1 : nil, combatLevel: 2, tileX: 10, tileZ: 10, size: 1,
	              animation: anim, hitUntil: hitUntil, hitDamage: damage, hitType: [0, 0, 0, 0], fineX: 1344, fineZ: 1344)
}

final class PluginTests: XCTestCase {
	// MARK: tables and formatting

	func testXpTable() {
		XCTAssertEqual(XpTable.xp(forLevel: 2), 83)
		XCTAssertEqual(XpTable.xp(forLevel: 99), 13_034_431)
		XCTAssertEqual(XpTable.level(forXp: 0), 1)
		XCTAssertEqual(XpTable.level(forXp: 82), 1)
		XCTAssertEqual(XpTable.level(forXp: 83), 2)
		XCTAssertEqual(XpTable.level(forXp: 13_034_430), 98)
		XCTAssertEqual(XpTable.level(forXp: 200_000_000), 99)
		XCTAssertEqual(XpTable.level(forXp: 200_000_000, maxLevel: 120), 120)
	}

	func testFormatting() {
		XCTAssertEqual(PluginFormat.number(1_234_567), "1,234,567")
		XCTAssertEqual(PluginFormat.number(999), "999")
		XCTAssertEqual(PluginFormat.quantity(250_000), "250K")
		XCTAssertEqual(PluginFormat.quantity(12_000_000), "12M")
		XCTAssertEqual(PluginFormat.plainTarget("<col=ffff00>Man<col=40ff00> (level: 2)"), "Man")
		XCTAssertEqual(PluginFormat.plainTarget("<col=ff9040>Lobster"), "Lobster")
		XCTAssertTrue(PluginMatch.name("*bone*", "Big bones"))
		XCTAssertTrue(PluginMatch.name("coins", "Coins"))
		XCTAssertFalse(PluginMatch.name("coin", "Coins"))
		XCTAssertTrue(PluginMatch.name("coin*", "Coins"))
	}

	// MARK: events

	func testDifferEmitsEachEventKind() {
		var d = PluginDiffer()
		let all: PluginSubscription = PluginSubscription.diffed
		var a = WorldSnapshot()
		a.stats = [0: .init(level: 10, xp: 1000)]
		a.inventories = [93: [0: ServerMessage.InvItem(id: 379, count: 1)]]
		a.actors = [ActorKey(isNpc: true, index: 1): testActor(1, name: "Goblin")]
		a.ground = [(0 << 16) | (5 << 8) | 6: [GroundObj(type: 526, amount: 1)]]
		a.chatSize = 1
		a.chatLines = [ChatLine(type: 0, name: nil, message: "old", clan: nil, phraseId: -1)]
		// The first snapshot is a silent baseline.
		XCTAssertTrue(d.diff(a, wants: all, xpDivisor: 1).isEmpty)

		var b = a
		b.ticks = 1
		b.stats = [0: .init(level: 10, xp: 1040), 1: .init(level: 5, xp: 300)]
		b.inventories = [93: [0: ServerMessage.InvItem(id: 379, count: 1), 1: ServerMessage.InvItem(id: 995, count: 50)]]
		b.actors = [ActorKey(isNpc: true, index: 2): testActor(2, name: "Cow")]
		b.ground = [(0 << 16) | (5 << 8) | 6: [GroundObj(type: 526, amount: 1), GroundObj(type: 995, amount: 7)]]
		b.chatSize = 3
		b.chatLines = [ChatLine(type: 0, name: nil, message: "two", clan: nil, phraseId: -1), ChatLine(type: 0, name: nil, message: "one", clan: nil, phraseId: -1)] + a.chatLines
		let events = d.diff(b, wants: all, xpDivisor: 1)
		XCTAssertTrue(events.contains(.gameTick))
		XCTAssertTrue(events.contains(.actorSpawned(testActor(2, name: "Cow"))))
		XCTAssertTrue(events.contains(.actorDespawned(testActor(1, name: "Goblin"))))
		XCTAssertTrue(events.contains(.groundItemSpawned(GroundItemSnapshot(type: 995, amount: 7, tileX: 5, tileZ: 6, plane: 0))))
		XCTAssertFalse(events.contains { if case .groundItemDespawned = $0 { return true } else { return false } })
		// A skill seen for the first time is not a gain; an existing one is.
		XCTAssertTrue(events.contains(.statChanged(StatChange(skill: 0, oldLevel: 10, newLevel: 10, oldXp: 1000, newXp: 1040))))
		XCTAssertFalse(events.contains { if case .statChanged(let c) = $0 { return c.skill == 1 } else { return false } })
		XCTAssertTrue(events.contains(.containerChanged(ContainerChange(inventory: 93, slots: [.init(slot: 1, oldId: -1, newId: 995, oldCount: 0, newCount: 50)]))))
		// Chat arrives oldest first.
		let chat = events.compactMap { e -> String? in if case .chatMessage(let l) = e { return l.message } else { return nil } }
		XCTAssertEqual(chat, ["one", "two"])
		XCTAssertEqual(events.last, .gameTick, "the tick comes after the changes it caused")
	}

	func testAnimationHitsplatAndDespawnedGroundItems() {
		var d = PluginDiffer()
		let wants: PluginSubscription = [.animations, .hitsplats, .groundItems]
		var a = WorldSnapshot()
		let k = ActorKey(isNpc: true, index: 4)
		a.actors = [k: testActor(4, anim: -1)]
		a.ground = [(1 << 16) | (9 << 8) | 9: [GroundObj(type: 1, amount: 1)]]
		a.plane = 1
		_ = d.diff(a, wants: wants, xpDivisor: 1)
		var b = a
		b.actors = [k: testActor(4, anim: 422, hitUntil: [0, 140, 0, 0], damage: [0, 9, 0, 0])]
		b.ground = [:]
		let e = d.diff(b, wants: wants, xpDivisor: 1)
		XCTAssertTrue(e.contains { if case .animationChanged(let c) = $0 { return c.oldAnimation == -1 && c.actor.animation == 422 } else { return false } })
		XCTAssertTrue(e.contains { if case .hitsplat(let h) = $0 { return h.damage == 9 } else { return false } })
		XCTAssertTrue(e.contains(.groundItemDespawned(GroundItemSnapshot(type: 1, amount: 1, tileX: 9, tileZ: 9, plane: 1))))
		// A scene rebuild restarts the ground items silently.
		var c = b
		c.buildStamp = 7
		c.ground = [(1 << 16) | (2 << 8) | 2: [GroundObj(type: 5, amount: 1)]]
		XCTAssertFalse(d.diff(c, wants: wants, xpDivisor: 1).contains { if case .groundItemSpawned = $0 { return true } else { return false } })
	}

	func testNewlyWantedEventsStartFromABaseline() {
		var d = PluginDiffer()
		var a = WorldSnapshot()
		_ = d.diff(a, wants: [.stats], xpDivisor: 1)
		a.ground = [5: [GroundObj(type: 1, amount: 1)]]
		// Ground items were not wanted before, so everything already there is not "spawned".
		XCTAssertTrue(d.diff(a, wants: [.stats, .groundItems], xpDivisor: 1).isEmpty)
	}

	func testStatDeltaUsesXpDivisor() {
		var d = PluginDiffer()
		var a = WorldSnapshot()
		a.stats = [0: .init(level: 20, xp: 49_000)]
		_ = d.diff(a, wants: [.stats], xpDivisor: 10)
		a.stats = [0: .init(level: 20, xp: 49_250)]
		XCTAssertEqual(d.diff(a, wants: [.stats], xpDivisor: 10), [.statChanged(StatChange(skill: 0, oldLevel: 20, newLevel: 20, oldXp: 4900, newXp: 4925))])
	}

	func testManagerDispatchHonoursSubscriptionsAndEnabledState() {
		let m = PluginManager(registerBuiltIns: false)
		let all = RecordingPlugin(id: "all", subscriptions: [.gameTick, .stats, .chat, .actors])
		let some = RecordingPlugin(id: "some", subscriptions: [.gameTick])
		let off = RecordingPlugin(id: "off", subscriptions: [.gameTick, .stats])
		[all, some, off].forEach { m.register($0) }
		m.setEnabled(true, id: "all")
		m.setEnabled(true, id: "some")
		m.dispatch([.gameTick, .statChanged(StatChange(skill: 2, oldLevel: 1, newLevel: 1, oldXp: 0, newXp: 30)), .chatMessage(ChatLine(type: 0, name: nil, message: "hi", clan: nil, phraseId: -1)), .actorSpawned(testActor(1))])
		XCTAssertEqual(all.events, ["tick", "stat2:30", "chat:hi", "spawn:Man"])
		XCTAssertEqual(some.events, ["tick"])
		XCTAssertEqual(off.events, [])
		var menu = Menu()
		m.modifyMenu(&menu, source: .world)
		XCTAssertEqual(all.menuCalls, 0, "no menu subscription")
		XCTAssertEqual(m.plugins.count, 3)
	}

	func testStartupShutdownAndPersistedSettings() {
		let store = InMemoryPluginSettingsStore()
		let m = PluginManager(registerBuiltIns: false)
		m.useSettingsStore(store)
		let p = RecordingPlugin(subscriptions: [.gameTick])
		m.register(p)
		XCTAssertFalse(p.enabled)
		m.setEnabled(true, id: "rec")
		p.config.set("flag", .bool(true))
		p.config.set("l", .list(["x", "y"]))
		XCTAssertNotNil(store.data(forPlugin: "rec"))

		// A new manager on the same store sees the saved state.
		let m2 = PluginManager(registerBuiltIns: false)
		m2.useSettingsStore(store)
		let p2 = RecordingPlugin(subscriptions: [.gameTick])
		m2.register(p2)
		XCTAssertTrue(p2.enabled)
		XCTAssertTrue(p2.config.bool("flag"))
		XCTAssertEqual(p2.config.list("l"), ["x", "y"])
		XCTAssertEqual(p2.config.int("n"), 5, "unset values use the field default")

		// Back to defaults removes the stored blob.
		m2.setEnabled(false, id: "rec")
		p2.config.reset()
		XCTAssertNil(store.data(forPlugin: "rec"))
	}

	func testBuiltInsRegisterWithMenuSwapperOnByDefault() {
		let m = PluginManager()
		XCTAssertEqual(m.plugins.map(\.id), ["menuSwapper", "groundItems", "indicators", "xpDrops", "xpTracker", "idleNotifier", "itemPrices", "boosts", "questHelper"])
		XCTAssertEqual(m.plugins.filter(\.enabled).map(\.id), ["menuSwapper"])
		XCTAssertEqual(Set(m.plugins.map(\.id)).count, m.plugins.count)
	}

	func testXpDivisorDetection() {
		let m = PluginManager(registerBuiltIns: false)
		// Levels 10, 20 and 30 with xp sent in tenths.
		m.detectXpDivisor([0: (10, Int32(XpTable.xp(forLevel: 10) * 10)), 1: (20, Int32(XpTable.xp(forLevel: 20) * 10)), 2: (30, Int32(XpTable.xp(forLevel: 30) * 10))])
		XCTAssertEqual(m.xpDivisor, 10)
		let n = PluginManager(registerBuiltIns: false)
		n.detectXpDivisor([0: (10, Int32(XpTable.xp(forLevel: 10))), 1: (20, Int32(XpTable.xp(forLevel: 20))), 2: (30, Int32(XpTable.xp(forLevel: 30)))])
		XCTAssertEqual(n.xpDivisor, 1)
	}

	// MARK: menu swapper

	func bankerMenu() -> Menu {
		var m = Menu()
		m.add(op: "Walk here", base: "", action: Menu.Action.walkHere, x: 3, z: 3)
		m.add(op: "Talk-to", base: "<col=ffff00>Banker", action: 17, key: 5)
		m.add(op: "Bank", base: "<col=ffff00>Banker", action: 4, key: 5)
		m.add(op: "Collect", base: "<col=ffff00>Banker", action: 19, key: 5)
		m.add(op: "Examine", base: "<col=ffff00>Banker", action: Menu.Action.npcExamine, key: 5)
		m.sort()
		return m
	}

	func testMenuSwapperPromotesNamedOption() {
		var m = bankerMenu()
		let before = m.entries.map(\.op)
		XCTAssertEqual(m.entries[m.top].op, "Collect")
		XCTAssertTrue(MenuEntrySwapperPlugin.apply(MenuEntrySwapperPlugin.parse(["banker = bank"]), to: &m))
		XCTAssertEqual(m.entries[m.top].op, "Bank")
		XCTAssertEqual(Set(m.entries.map(\.op)), Set(before), "nothing lost")
		XCTAssertEqual(m.entries[0].action, Menu.Action.cancel)
		XCTAssertEqual(m.count, before.count)
	}

	func testMenuSwapperIgnoresOtherTargetsAndMissingOptions() {
		var m = bankerMenu()
		let original = m.entries
		XCTAssertFalse(MenuEntrySwapperPlugin.apply(MenuEntrySwapperPlugin.parse(["Man=Pickpocket", "Banker=Pickpocket", "garbage line"]), to: &m))
		XCTAssertEqual(m.entries, original)
	}

	func testMenuSwapperFirstMatchingRuleAndLevelSuffix() {
		var m = Menu()
		m.add(op: "Walk here", base: "", action: Menu.Action.walkHere)
		m.add(op: "Talk-to", base: "<col=ffff00>Man<col=40ff00> (level: 2)", action: 17, key: 1)
		m.add(op: "Pickpocket", base: "<col=ffff00>Man<col=40ff00> (level: 2)", action: 4, key: 1)
		m.add(op: "Attack", base: "<col=ffff00>Man<col=40ff00> (level: 2)", action: 2, key: 1)
		let rules = MenuEntrySwapperPlugin.parse(["Man=Attack", "Man=Pickpocket"])
		MenuEntrySwapperPlugin.apply(rules, to: &m)
		XCTAssertEqual(m.entries[m.top].op, "Attack")
		// Already the default: no change, still reported.
		XCTAssertTrue(MenuEntrySwapperPlugin.apply(rules, to: &m))
		XCTAssertEqual(m.entries[m.top].op, "Attack")
	}

	func testMenuSwapperDefaultsParse() {
		let rules = MenuEntrySwapperPlugin.parse(MenuEntrySwapperPlugin.defaultRules)
		XCTAssertEqual(rules.count, MenuEntrySwapperPlugin.defaultRules.count)
		XCTAssertEqual(rules.first, MenuEntrySwapperPlugin.Rule("Banker=Bank"))
		XCTAssertNil(MenuEntrySwapperPlugin.Rule("=x"))
		XCTAssertNil(MenuEntrySwapperPlugin.Rule("x="))
	}

	func testManagerAppliesSwapperThroughHook() {
		let m = PluginManager()
		var menu = bankerMenu()
		m.modifyMenu(&menu, source: .world)
		XCTAssertEqual(menu.entries[menu.top].op, "Bank", "the shipped Banker rule")
		m.setEnabled(false, id: "menuSwapper")
		var other = bankerMenu()
		m.modifyMenu(&other, source: .world)
		XCTAssertEqual(other.entries[other.top].op, "Collect")
	}

	func testItemPricesAppendsValueToExamine() throws {
		let m = PluginManager(registerBuiltIns: false)
		let p = ItemPricesPlugin()
		m.register(p)
		m.setEnabled(true, id: p.id)
		m.context.testSetItem(ItemInfo(id: 379, name: "Lobster", cost: 150, stackable: false, members: false))
		var menu = Menu()
		menu.add(op: "Eat", base: "<col=ff9040>Lobster", action: 25, key: 379)
		menu.add(op: "Examine", base: "<col=ff9040>Lobster", action: Menu.Action.itemExamine, key: 379)
		m.modifyMenu(&menu, source: .inventory)
		XCTAssertEqual(menu.text(2), "Examine <col=ff9040>Lobster <col=ffffff>(150 gp)")
		XCTAssertEqual(menu.text(1), "Eat <col=ff9040>Lobster", "only Examine changes")
		m.modifyMenu(&menu, source: .inventory)
		XCTAssertEqual(menu.text(2), "Examine <col=ff9040>Lobster <col=ffffff>(150 gp)", "not appended twice")
	}

	// MARK: xp

	func testXpDropFromStatUpdates() {
		let gain = StatChange(skill: 3, oldLevel: 40, newLevel: 40, oldXp: 1000, newXp: 1064)
		XCTAssertEqual(XpDropsPlugin.drop(for: gain)?.amount, 64)
		XCTAssertEqual(XpDropsPlugin.drop(for: gain)?.skill, 3)
		XCTAssertNil(XpDropsPlugin.drop(for: gain, minXp: 100))
		XCTAssertNil(XpDropsPlugin.drop(for: StatChange(skill: 2, oldLevel: 50, newLevel: 59, oldXp: 5, newXp: 5)), "a potion is not a drop")
		XCTAssertEqual(XpDropsPlugin.rise(age: 0, life: 150), 0)
		XCTAssertEqual(XpDropsPlugin.rise(age: 75, life: 150), 35)
		XCTAssertEqual(XpDropsPlugin.rise(age: 999, life: 150), 70)
	}

	func testXpDropsPluginCollectsFromEvents() {
		let m = PluginManager(registerBuiltIns: false)
		let p = XpDropsPlugin()
		m.register(p)
		m.setEnabled(true, id: p.id)
		m.testLoop = 500
		m.dispatch([.statChanged(StatChange(skill: 10, oldLevel: 5, newLevel: 5, oldXp: 100, newXp: 140)), .statChanged(StatChange(skill: 10, oldLevel: 5, newLevel: 5, oldXp: 140, newXp: 140))])
		XCTAssertEqual(p.drops, [XpDropsPlugin.Drop(skill: 10, amount: 40, startLoop: 500)])
	}

	func testXpTrackerRates() {
		let m = PluginManager(registerBuiltIns: false)
		let t = XpTrackerPlugin()
		m.register(t)
		m.setEnabled(true, id: t.id)
		var clock = Date(timeIntervalSince1970: 1_000_000)
		t.now = { clock }
		m.dispatch([.statChanged(StatChange(skill: 10, oldLevel: 1, newLevel: 1, oldXp: 0, newXp: 50))])
		clock.addTimeInterval(1800)
		m.dispatch([.statChanged(StatChange(skill: 10, oldLevel: 1, newLevel: 4, oldXp: 50, newXp: 1000)), .statChanged(StatChange(skill: 3, oldLevel: 10, newLevel: 10, oldXp: 1154, newXp: 1200))])
		let rows = t.snapshot()
		XCTAssertEqual(rows.map(\.skill), [10, 3], "most xp first")
		XCTAssertEqual(rows[0].gained, 1000)
		XCTAssertEqual(rows[0].xpPerHour, 2000)
		XCTAssertEqual(rows[0].levelsGained, XpTable.level(forXp: 1000) - 1)
		XCTAssertEqual(rows[1].name, "Hitpoints")
		XCTAssertEqual(t.totalGained, 1046)
		t.reset()
		XCTAssertTrue(t.snapshot().isEmpty)
	}

	// MARK: idle

	func testIdleDetectorFiresOnceAfterWorking() {
		var d = IdleDetector(idleTicks: 3)
		XCTAssertFalse(d.tick(animating: false, moving: false), "never active yet")
		XCTAssertFalse(d.tick(animating: true, moving: false))
		XCTAssertFalse(d.tick(animating: false, moving: false))
		XCTAssertFalse(d.tick(animating: false, moving: false))
		XCTAssertTrue(d.tick(animating: false, moving: false), "third quiet tick")
		for _ in 0..<10 { XCTAssertFalse(d.tick(animating: false, moving: false), "only once") }
		XCTAssertFalse(d.tick(animating: true, moving: false))
		XCTAssertFalse(d.tick(animating: false, moving: false))
		XCTAssertFalse(d.tick(animating: true, moving: false), "animating again resets the count")
		XCTAssertFalse(d.tick(animating: false, moving: false))
		XCTAssertFalse(d.tick(animating: false, moving: false))
		XCTAssertTrue(d.tick(animating: false, moving: false))
	}

	func testIdleDetectorMovementRules() {
		var d = IdleDetector(idleTicks: 2, requireAnimation: true)
		XCTAssertFalse(d.tick(animating: false, moving: true))
		XCTAssertFalse(d.tick(animating: false, moving: false))
		XCTAssertFalse(d.tick(animating: false, moving: false), "walking alone never arms")
		XCTAssertFalse(d.tick(animating: true, moving: false))
		XCTAssertFalse(d.tick(animating: false, moving: false))
		XCTAssertFalse(d.tick(animating: false, moving: true), "moving holds the countdown")
		XCTAssertFalse(d.tick(animating: false, moving: false))
		XCTAssertTrue(d.tick(animating: false, moving: false))

		var w = IdleDetector(idleTicks: 2, requireAnimation: false)
		XCTAssertFalse(w.tick(animating: false, moving: true), "a walk arms it")
		XCTAssertFalse(w.tick(animating: false, moving: false))
		XCTAssertTrue(w.tick(animating: false, moving: false))
		XCTAssertEqual(IdleNotifierPlugin.ticks(forSeconds: 6), 10)
	}

	func testLowHitpointsLatch() {
		var l = LowHitpointsDetector()
		XCTAssertFalse(l.update(current: 50, base: 50, percent: 25))
		XCTAssertFalse(l.update(current: 20, base: 50, percent: 25))
		XCTAssertTrue(l.update(current: 12, base: 50, percent: 25))
		XCTAssertFalse(l.update(current: 8, base: 50, percent: 25), "already low")
		XCTAssertFalse(l.update(current: 40, base: 50, percent: 25))
		XCTAssertTrue(l.update(current: 10, base: 50, percent: 25), "re-armed after recovering")
		XCTAssertFalse(l.update(current: 1, base: 50, percent: 0), "0 % turns it off")
	}

	func testBoostCountdown() {
		XCTAssertEqual(BoostsPlugin.secondsToNext(changedAt: 0, loop: 0), 60)
		XCTAssertEqual(BoostsPlugin.secondsToNext(changedAt: 0, loop: 1500), 30)
		XCTAssertEqual(BoostsPlugin.secondsToNext(changedAt: 100, loop: 3100), 60, "wraps every 100 ticks")
	}

	func testGroundItemClassification() {
		typealias G = GroundItemsPlugin
		XCTAssertEqual(G.classify(name: "Coins", value: 50, hidden: [], highlighted: [], highlightValue: 10_000, hideBelow: 0), .normal)
		XCTAssertEqual(G.classify(name: "Rune bar", value: 12_000, hidden: [], highlighted: [], highlightValue: 10_000, hideBelow: 0), .valuable)
		XCTAssertNil(G.classify(name: "Bones", value: 1, hidden: ["bones"], highlighted: [], highlightValue: 0, hideBelow: 0))
		XCTAssertEqual(G.classify(name: "Bones", value: 1, hidden: ["bones"], highlighted: ["Bones"], highlightValue: 0, hideBelow: 0), .highlighted, "highlight beats hide")
		XCTAssertNil(G.classify(name: "Feather", value: 2, hidden: [], highlighted: [], highlightValue: 0, hideBelow: 5))
	}

	// MARK: polygons

	func testFillPolygonCoversShapeWithAlpha() {
		var r = Raster(width: 40, height: 40, fill: 0x000000)
		r.fillPolygon([ScreenPoint(x: 5, y: 5), ScreenPoint(x: 25, y: 5), ScreenPoint(x: 25, y: 25), ScreenPoint(x: 5, y: 25)], 0xFFFFFF, opacity: 128)
		let inside = r.pixels[15 * 40 + 15] & 0xFF, outside = r.pixels[30 * 40 + 30] & 0xFF
		XCTAssertTrue((120...136).contains(Int(inside)), "half opaque white over black, got \(inside)")
		XCTAssertEqual(outside, 0)
		let covered = r.pixels.filter { $0 & 0xFF != 0 }.count
		XCTAssertTrue((380...420).contains(covered), "about 20 x 20 pixels, got \(covered)")
		// A diamond only covers about half its bounding box.
		var d = Raster(width: 40, height: 40, fill: 0)
		d.fillPolygon([ScreenPoint(x: 20, y: 0), ScreenPoint(x: 39, y: 20), ScreenPoint(x: 20, y: 39), ScreenPoint(x: 0, y: 20)], 0xFF0000)
		let n = d.pixels.filter { $0 & 0xFF0000 != 0 }.count
		XCTAssertTrue((650...850).contains(n), "diamond area ~ 760, got \(n)")
	}
}

/// Plugins against a scene rendered from the cache (needs `SCAPE530_CACHE`).
final class PluginSceneTests: XCTestCase {
	func store() throws -> ConfigStore {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("SCAPE530_CACHE not set") }
		return ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
	}

	/// The recorded resizable session fed into a client, as `InteractTests.startedClient`.
	func startedClient(width: Int = 1015, height: Int = 469) throws -> GameClient {
		let client = try GameClient(store: try store(), server: .init(host: "127.0.0.1", port: 1))
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
				for _ in 0..<30 { client.world.cycle(varps: client.state.varps) }
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
		_ = try client.frame(width: width, height: height)
		_ = try client.frame(width: width, height: height)
		return client
	}

	func differing(_ a: Raster, _ b: Raster, in rect: (x: Int, y: Int, w: Int, h: Int)) -> Int {
		var n = 0
		for y in max(rect.y, 0)..<min(rect.y + rect.h, a.height) {
			for x in max(rect.x, 0)..<min(rect.x + rect.w, a.width) where a.pixels[y * a.width + x] != b.pixels[y * a.width + x] { n += 1 }
		}
		return n
	}

	func testProjectionPutsPlayerNearViewportCentre() throws {
		let client = try startedClient()
		let canvas = OverlayCanvas(world: client.world, viewport: client.overlayRect, ctx: client.plugins.context)
		XCTAssertTrue(canvas.canProject)
		let me = try XCTUnwrap(client.plugins.context.selfActor)
		let p = try XCTUnwrap(canvas.projectTileCenter(x: me.tileX, z: me.tileZ))
		let v = canvas.viewport
		XCTAssertLessThan(abs(p.x - (v.x + v.w / 2)), 60, "the camera follows the player: \(p) in \(v)")
		XCTAssertTrue(p.y > v.y && p.y < v.y + v.h)
		// One tile east is a few pixels to one side (depends on yaw) and the footprint is a convex quad around the centre.
		let q = try XCTUnwrap(canvas.tileCorners(x: me.tileX, z: me.tileZ))
		XCTAssertEqual(q.count, 4)
		XCTAssertTrue(q.map(\.x).min()! < p.x && q.map(\.x).max()! > p.x)
		XCTAssertTrue(q.map(\.y).min()! < p.y && q.map(\.y).max()! > p.y)
		// Same maths as the scene's own pick projection: a point far behind the camera is nil.
		XCTAssertNil(canvas.project(xFine: 0, zFine: 0))
	}

	func testGroundItemOverlayDrawsIntoTheScene() throws {
		let client = try startedClient()
		var base = try client.frame(width: 1015, height: 469)
		let me = try XCTUnwrap(client.plugins.context.selfActor)
		// A stack of coins two tiles from the player (zone updates address tiles relative to the chunk).
		client.world.handle(.message(.zonePartialFollows(chunkX: me.tileX + 2, chunkZ: me.tileZ)), varps: [:])
		client.world.handle(.message(.zoneUpdate(.objAdd(x: 0, z: 0, id: 995, count: 25_000, hiddenFrom: -1))), varps: [:])
		XCTAssertEqual(client.world.groundObjects(x: me.tileX + 2, z: me.tileZ).count, 1)
		base = try client.frame(width: 1015, height: 469)

		// Off: the overlay pass leaves the raster alone.
		var off = base
		client.plugins.drawOverlays(.scene, into: &off)
		XCTAssertEqual(off.pixels, base.pixels)

		client.plugins.setEnabled(true, id: "groundItems")
		var on = base
		client.plugins.drawOverlays(.scene, into: &on)
		let canvas = OverlayCanvas(world: client.world, viewport: client.overlayRect, ctx: client.plugins.context)
		let p = try XCTUnwrap(canvas.projectTileCenter(x: me.tileX + 2, z: me.tileZ))
		let changed = differing(base, on, in: (p.x - 60, p.y - 30, 120, 40))
		XCTAssertGreaterThan(changed, 25, "the label \"Coins (25,000)\" is drawn near \(p)")
		// Nothing outside the label's neighbourhood changed.
		XCTAssertEqual(differing(base, on, in: (0, 0, base.width, max(p.y - 60, 0))), 0)
		// Label text is white or the "valuable" colour with a black shadow.
		XCTAssertTrue(on.pixels.contains { $0 == 0xFF40E0FF || $0 == 0xFF40FF40 || $0 == 0xFFFFFFFF })

		// Hiding the item by name removes the label again.
		client.plugins.plugin(id: "groundItems")?.config.set("hidden", .list(["coins"]))
		var hidden = base
		client.plugins.drawOverlays(.scene, into: &hidden)
		XCTAssertEqual(hidden.pixels, base.pixels)
		try save(on, "plugin-ground-items")
	}

	func testTileIndicatorsFillPlayerTile() throws {
		let client = try startedClient()
		let base = try client.frame(width: 1015, height: 469)
		client.plugins.setEnabled(true, id: "indicators")
		var on = base
		client.plugins.drawOverlays(.scene, into: &on)
		let me = try XCTUnwrap(client.plugins.context.selfActor)
		let canvas = OverlayCanvas(world: client.world, viewport: client.overlayRect, ctx: client.plugins.context)
		let p = try XCTUnwrap(canvas.projectTileCenter(x: me.tileX, z: me.tileZ))
		XCTAssertGreaterThan(differing(base, on, in: (p.x - 40, p.y - 30, 80, 60)), 200)
		try save(on, "plugin-tiles")
	}

	func testXpDropsFlowFromStatUpdatesToPixels() throws {
		let client = try startedClient()
		// The frame itself runs the overlays, so take the reference before the plugin is on.
		let base = try client.frame(width: 1015, height: 469)
		client.plugins.setEnabled(true, id: "xpDrops")
		client.plugins.update(cycles: 1) // baseline
		let before = client.state.stats[10]
		let xp = before?.xp ?? 0
		client.handle(.message(.updateStat(skill: 10, level: before?.level ?? 1, xp: xp)))
		client.plugins.update(cycles: 1)
		client.handle(.message(.updateStat(skill: 10, level: before?.level ?? 1, xp: xp + Int32(250 * client.plugins.xpDivisor))))
		client.plugins.update(cycles: 1)
		let drops = try XCTUnwrap(client.plugins.plugin(ofType: XpDropsPlugin.self)).drops
		XCTAssertEqual(drops.count, 1, "\(drops)")
		XCTAssertEqual(drops.first?.amount, 250)
		var on = base
		client.plugins.drawOverlays(.hud, into: &on)
		XCTAssertGreaterThan(differing(base, on, in: (0, 0, base.width, base.height)), 30)
		try save(on, "plugin-xp-drop")
	}

	func testSwapperChangesDefaultEntryOfABuiltWorldMenu() throws {
		let client = try startedClient()
		let world = client.world
		func project(_ a: PathingActor) -> (Int, Int)? {
			guard let v = client.viewport, let me = world.selfActor, let scene = world.scene else { return nil }
			let eye = world.camera.eye(groundY: scene.tileHeight(level: scene.centralPlane, xFine: me.xFine, zFine: me.zFine))
			let sinP = MathTables.sin[eye.pitch & 2047], cosP = MathTables.cos[eye.pitch & 2047]
			let sinY = MathTables.sin[eye.yaw & 2047], cosY = MathTables.cos[eye.yaw & 2047]
			let dx = a.xFine - eye.x, dy = a.groundY - 60 - eye.y, dz = a.zFine - eye.z
			let xr = (dz * sinY + dx * cosY) >> 16, zr = (dz * cosY - dx * sinY) >> 16
			let yv = (dy * cosP - zr * sinP) >> 16, zv = (dy * sinP + zr * cosP) >> 16
			guard zv > 50 else { return nil }
			return (v.x + v.w / 2 + (xr << 9) / zv, v.y + v.h / 2 + (yv << 9) / zv)
		}
		let swapper = try XCTUnwrap(client.plugins.plugin(id: "menuSwapper"))
		for (id, a) in world.ctx.npcs.sorted(by: { $0.key < $1.key }) {
			guard let t = a.npcType, t.interactive, t.ops.contains(where: { $0 != nil }) else { continue }
			guard let p = project(a), client.isOverWorld(x: p.0, y: p.1) else { continue }
			swapper.config.set("rules", .list([]))
			guard let (plain, pick) = client.buildMenu(x: p.0, y: p.1), pick.hits.contains(Int64(id) << 32 | 0x2000_0000), plain.entries[plain.top].op != "Examine" else { continue }
			swapper.config.set("rules", .list(["\(t.name)=Examine"]))
			let (swapped, _) = try XCTUnwrap(client.buildMenu(x: p.0, y: p.1))
			XCTAssertEqual(swapped.entries[swapped.top].op, "Examine")
			XCTAssertEqual(swapped.count, plain.count)
			// The preview line a tap shows follows the swap.
			client.previewTap(x: p.0, y: p.1)
			XCTAssertTrue(client.interaction.preview?.hasPrefix("Examine") ?? false, "\(client.interaction.preview ?? "nil")")
			return
		}
		XCTFail("no pickable npc with options on screen")
	}

	func save(_ r: Raster, _ name: String) throws {
		guard let out = ProcessInfo.processInfo.environment["SCAPE530_OUT"] else { return }
		try Data(PNG.encode(r)).write(to: URL(fileURLWithPath: out).appendingPathComponent(name + ".png"))
	}
}
