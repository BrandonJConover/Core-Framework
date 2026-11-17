import XCTest
@testable import Scape530

/// The quest data model, engine and catalog (no client, no cache).
final class QuestTests: XCTestCase {
	/// (varp, not started, in progress, complete) of every authored quest, copied from the server's `Quest(...)`
	/// constructors (see the file comments in `QuestCatalog+*.swift`; `testCatalogMatchesServerSource` rechecks them
	/// against the server source when `SCAPE530_SERVER_SRC` is set).
	static let serverConfigs: [String: (varp: Int, red: Int, yellow: Int, green: Int)] = [
		"Cook's Assistant": (29, 0, 1, 2), "Sheep Shearer": (179, 0, 20, 21), "Rune Mysteries": (63, 0, 1, 6),
		"The Restless Ghost": (107, 0, 4, 5), "Imp Catcher": (160, 0, 1, 2), "Ernest the Chicken": (32, 0, 1, 3),
		"Vampire Slayer": (178, 0, 1, 3), "Romeo & Juliet": (144, 0, 1, 100), "Demon Slayer": (222, 0, 1, 3),
		"Dragon Slayer": (176, 0, 1, 10), "Doric's Quest": (31, 0, 1, 100), "Witch's Potion": (67, 0, 1, 3),
		"The Knight's Sword": (122, 0, 1, 7), "Black Knights' Fortress": (130, 0, 1, 4), "Pirate's Treasure": (71, 0, 1, 4),
		"Prince Ali Rescue": (273, 0, 1, 110), "Goblin Diplomacy": (62, 0, 1, 6),
	]

	func facts(varp: Int? = nil, value: Int = 0, items: [Int: Int] = [:], worn: [Int: Int] = [:], bank: [Int: Int] = [:], flags: Set<String> = [], journal: QuestJournal? = nil, quest: String? = nil) -> QuestFactsSnapshot {
		var f = QuestFactsSnapshot()
		if let varp { f.varps[varp] = value }
		f.inventory = items; f.worn = worn; f.bank = bank; f.flags = flags
		if let journal { f.journals[journal.quest] = journal }
		return f
	}

	func def(_ name: String) -> QuestDef { QuestEngine.def(named: name)! }

	/// The id of the current step with the quest in progress.
	/// Like the plugin each tick: the latches settle on the facts first, then the step is picked.
	func step(_ name: String, _ f: QuestFactsSnapshot) -> String? {
		var f = f
		f.flags = QuestEngine.updatedFlags(def(name), f, flags: f.flags)
		return QuestEngine.currentStep(def(name), f)?.id
	}

	func inProgress(_ name: String, items: [Int: Int] = [:], worn: [Int: Int] = [:], flags: Set<String> = [], journal: [String] = [], crossed: [String] = [], varp62: Int? = nil) -> QuestFactsSnapshot {
		let d = def(name)
		var f = facts(varp: d.source.id, value: varp62 ?? yellow(d), items: items, worn: worn, flags: flags)
		if !journal.isEmpty || !crossed.isEmpty {
			f.journals[name] = QuestJournal(quest: name, lines: journal.map { .init($0, crossedOut: false) } + crossed.map { .init($0, crossedOut: true) })
		}
		return f
	}

	/// The in-progress ("yellow") value the server uses (the second config number).
	func yellow(_ d: QuestDef) -> Int { Self.serverConfigs[d.name]!.yellow }

	// MARK: catalog integrity

	func testCatalogHasTheFreeToPlayGuides() {
		let names = Set(QuestCatalog.all.map(\.name))
		for n in ["Cook's Assistant", "Sheep Shearer", "Rune Mysteries", "Romeo & Juliet", "The Restless Ghost", "Ernest the Chicken", "Imp Catcher", "Witch's Potion", "Doric's Quest", "Goblin Diplomacy", "Prince Ali Rescue", "Vampire Slayer", "Pirate's Treasure", "Demon Slayer", "The Knight's Sword", "Black Knights' Fortress", "Dragon Slayer"] {
			XCTAssertTrue(names.contains(n), n)
		}
		XCTAssertEqual(QuestCatalog.all.count, Self.serverConfigs.count)
	}

	func testCatalogIsWellFormed() {
		var ids = Set<String>(), indexes = Set<Int>()
		for d in QuestCatalog.all {
			XCTAssertTrue(ids.insert(d.id).inserted, "duplicate id \(d.id)")
			XCTAssertTrue(indexes.insert(d.serverIndex).inserted, "duplicate server index \(d.name)")
			XCTAssertFalse(d.steps.isEmpty, d.name)
			XCTAssertEqual(Set(d.steps.map(\.id)).count, d.steps.count, "step ids of \(d.name)")
			// The first step is the "go and start it" step, shown while the quest is not started.
			XCTAssertTrue(d.steps[0].when.contains(.status(.notStarted)), d.name)
			XCTAssertFalse(d.steps[0].targets.isEmpty, "\(d.name) start step has a target")
			// An in-progress quest always has a step: the last step has no condition that can fail.
			XCTAssertTrue(d.steps.last!.when.isEmpty, "\(d.name) needs a fallback step")
			for s in d.steps {
				XCTAssertFalse(s.text.isEmpty, "\(d.name)/\(s.id)")
				for it in s.items { XCTAssertGreaterThan(it.count, 0); XCTAssertFalse(it.name.isEmpty) }
				for t in s.targets { XCTAssertTrue((0...3).contains(t.tile.plane) && t.tile.x > 2000 && t.tile.z > 2000, "\(d.name)/\(s.id) tile \(t.tile)") }
			}
			// Latch flags used by steps are declared.
			let declared = Set(d.latches.map(\.flag))
			func flags(_ c: QuestCondition) -> [String] {
				switch c {
				case .flag(let f): return [f]
				case .not(let i): return flags(i)
				case .any(let l), .all(let l): return l.flatMap(flags)
				default: return []
				}
			}
			for f in d.steps.flatMap({ $0.when.flatMap(flags) }) { XCTAssertTrue(declared.contains(f), "\(d.name) uses undeclared flag \(f)") }
		}
	}

	// MARK: stage resolution from varps

	func testStatusFromVarpsForEveryQuest() {
		for d in QuestCatalog.all {
			let c = Self.serverConfigs[d.name]!
			XCTAssertEqual(d.source.kind, .varp, d.name)
			XCTAssertEqual(d.source.id, c.varp, d.name)
			XCTAssertEqual(d.source.status(facts(varp: c.varp, value: c.red)), .notStarted, d.name)
			XCTAssertEqual(d.source.status(facts(varp: c.varp, value: c.yellow)), .inProgress, d.name)
			XCTAssertEqual(d.source.status(facts(varp: c.varp, value: c.green)), .complete, d.name)
			XCTAssertEqual(d.source.status(QuestFactsSnapshot()), .notStarted, "\(d.name): no varp sent yet means not started")
			XCTAssertNil(QuestEngine.currentStep(d, facts(varp: c.varp, value: c.green)), "\(d.name) complete has no step")
			XCTAssertEqual(QuestEngine.currentStep(d, facts(varp: c.varp, value: c.red))?.id, "start", d.name)
		}
	}

	func testGoblinDiplomacyShowsItsStageInTheVarp() {
		let d = def("Goblin Diplomacy")
		for (v, want) in [(1, QuestStatus.inProgress), (4, .inProgress), (5, .inProgress), (6, .complete), (0, .notStarted)] {
			XCTAssertEqual(d.source.status(facts(varp: 62, value: v)), want, "varp 62 = \(v)")
		}
		XCTAssertEqual(step("Goblin Diplomacy", facts(varp: 62, value: 1)), "orange_make")
		XCTAssertEqual(step("Goblin Diplomacy", facts(varp: 62, value: 1, items: [286: 1])), "orange_show")
		XCTAssertEqual(step("Goblin Diplomacy", facts(varp: 62, value: 4)), "blue_make")
		XCTAssertEqual(step("Goblin Diplomacy", facts(varp: 62, value: 4, items: [287: 1])), "blue_show")
		XCTAssertEqual(step("Goblin Diplomacy", facts(varp: 62, value: 5)), "brown_get")
		XCTAssertEqual(step("Goblin Diplomacy", facts(varp: 62, value: 5, items: [288: 1])), "brown_show")
		// Holding the wrong colour for the stage does not skip ahead.
		XCTAssertEqual(step("Goblin Diplomacy", facts(varp: 62, value: 4, items: [286: 1])), "blue_make")
	}

	func testCatalogMatchesServerSource() throws {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_SERVER_SRC"] else { throw XCTSkip("SCAPE530_SERVER_SRC not set") }
		// Every `Quest(Quests.X, index, button, points, varp, red, yellow, green)` constructor of the quest folders.
		let rx = try NSRegularExpression(pattern: #"Quests\.([A-Z_]+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+))?\s*\)"#)
		var found: [String: [Int]] = [:]
		let en = FileManager.default.enumerator(atPath: dir)
		while let p = en?.nextObject() as? String {
			guard p.hasSuffix(".java") || p.hasSuffix(".kt"), let text = try? String(contentsOfFile: dir + "/" + p, encoding: .utf8), text.contains("extends Quest") || text.contains(": Quest(") else { continue }
			for line in text.split(separator: "\n") where line.contains("Quests.") && (line.contains("super(") || line.contains(": Quest(")) {
				let s = String(line)
				guard let m = rx.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { continue }
				func g(_ i: Int) -> Int? { Range(m.range(at: i), in: s).flatMap { Int(s[$0]) } }
				found[String(s[Range(m.range(at: 1), in: s)!])] = [g(2), g(3), g(4), g(5), g(6), g(7), g(8)].map { $0 ?? -1 }
			}
		}
		let slugs: [String: String] = ["Cook's Assistant": "COOKS_ASSISTANT", "Sheep Shearer": "SHEEP_SHEARER", "Rune Mysteries": "RUNE_MYSTERIES", "The Restless Ghost": "THE_RESTLESS_GHOST", "Imp Catcher": "IMP_CATCHER", "Ernest the Chicken": "ERNEST_THE_CHICKEN", "Vampire Slayer": "VAMPIRE_SLAYER", "Romeo & Juliet": "ROMEO_JULIET", "Demon Slayer": "DEMON_SLAYER", "Dragon Slayer": "DRAGON_SLAYER", "Doric's Quest": "DORICS_QUEST", "Witch's Potion": "WITCHS_POTION", "The Knight's Sword": "THE_KNIGHTS_SWORD", "Black Knights' Fortress": "BLACK_KNIGHTS_FORTRESS", "Pirate's Treasure": "PIRATES_TREASURE", "Prince Ali Rescue": "PRINCE_ALI_RESCUE", "Goblin Diplomacy": "GOBLIN_DIPLOMACY"]
		for d in QuestCatalog.all {
			let v = try XCTUnwrap(found[slugs[d.name]!], "server constructor for \(d.name)")
			XCTAssertEqual(v[0], d.serverIndex, "\(d.name) index"); XCTAssertEqual(v[2], d.points, "\(d.name) points")
			if d.name == "Goblin Diplomacy" { XCTAssertEqual(v[3], -1, "overrides getConfig"); continue }
			let c = Self.serverConfigs[d.name]!
			XCTAssertEqual(Array(v[3...6]), [c.varp, c.red, c.yellow, c.green], d.name)
		}
	}

	// MARK: step selection

	func testCooksAssistantSteps() {
		let n = "Cook's Assistant"
		XCTAssertEqual(step(n, facts(varp: 29, value: 0)), "start")
		XCTAssertEqual(step(n, inProgress(n)), "milk")
		XCTAssertEqual(step(n, inProgress(n, items: [1927: 1])), "flour")
		XCTAssertEqual(step(n, inProgress(n, items: [1927: 1, 1933: 1])), "egg")
		XCTAssertEqual(step(n, inProgress(n, items: [1944: 1, 1933: 1])), "milk")
		XCTAssertEqual(step(n, inProgress(n, items: [1927: 1, 1933: 1, 1944: 1])), "return")
		XCTAssertNil(step(n, facts(varp: 29, value: 2)))
	}

	func testSheepShearerSteps() {
		let n = "Sheep Shearer"
		XCTAssertEqual(step(n, inProgress(n)), "shears")
		XCTAssertEqual(step(n, inProgress(n, items: [1735: 1])), "shear")
		XCTAssertEqual(step(n, inProgress(n, items: [1735: 1, 1737: 5])), "spin")
		XCTAssertEqual(step(n, inProgress(n, items: [1759: 19])), "shears")
		XCTAssertEqual(step(n, inProgress(n, items: [1759: 19, 1737: 1])), "spin")
		XCTAssertEqual(step(n, inProgress(n, items: [1759: 20])), "deliver")
	}

	func testRuneMysteriesFollowsTheItems() {
		let n = "Rune Mysteries"
		XCTAssertEqual(step(n, inProgress(n, items: [1438: 1])), "talisman")
		XCTAssertEqual(step(n, inProgress(n)), "sedridor")
		XCTAssertEqual(step(n, inProgress(n, items: [290: 1])), "package")
		// The package is handed in: the latch remembers it and the next step is Aubury again.
		var f = inProgress(n, items: [290: 1])
		let flags = QuestEngine.updatedFlags(def(n), f, flags: [])
		XCTAssertEqual(flags, ["hadPackage"])
		f = inProgress(n, flags: flags)
		XCTAssertEqual(step(n, f), "aubury2")
		XCTAssertEqual(step(n, inProgress(n, items: [291: 1], flags: flags)), "notes")
		// Leaving the quest (complete) clears the latches.
		XCTAssertEqual(QuestEngine.updatedFlags(def(n), facts(varp: 63, value: 6), flags: flags), [])
	}

	func testRestlessGhostSteps() {
		let n = "The Restless Ghost"
		XCTAssertEqual(step(n, inProgress(n)), "urhney")
		XCTAssertEqual(step(n, inProgress(n, worn: [552: 1])), "ghost")
		XCTAssertEqual(step(n, inProgress(n, items: [964: 1], worn: [552: 1])), "return_skull")
		XCTAssertEqual(step(n, inProgress(n, worn: [552: 1], journal: ["I should go and search the Wizard's Tower South West of Lumbridge for the Ghost's Skull."])), "skull")
		XCTAssertEqual(step(n, inProgress(n, worn: [552: 1], journal: ["I should take the Skull back to the Ghost so it can rest."])), "skull")
	}

	func testImpCatcherChecksAllFourBeads() {
		let n = "Imp Catcher"
		XCTAssertEqual(step(n, inProgress(n, items: [1474: 1, 1470: 1, 1476: 1])), "beads")
		XCTAssertEqual(step(n, inProgress(n, items: [1474: 1, 1470: 1, 1476: 1, 1472: 1])), "return")
		let c = QuestEngine.checklist(def(n).steps[2], inProgress(n, items: [1474: 1, 1470: 1]))
		XCTAssertEqual(c.map(\.state), [.have, .have, .missing, .missing])
	}

	func testErnestParts() {
		let n = "Ernest the Chicken"
		XCTAssertEqual(step(n, inProgress(n)), "oddenstein")
		XCTAssertEqual(step(n, inProgress(n, journal: ["I need to bring Dr Oddenstein parts for his machine"])), "gauge")
		XCTAssertEqual(step(n, inProgress(n, items: [271: 1, 277: 1])), "tube")
		XCTAssertEqual(step(n, inProgress(n, items: [271: 1, 276: 1])), "oil")
		XCTAssertEqual(step(n, inProgress(n, items: [271: 1, 276: 1, 277: 1])), "return")
		// A part in the backpack is enough to know the quest is past its first stage (the latch), even after it is used.
		let flags = QuestEngine.updatedFlags(def(n), inProgress(n, items: [276: 1]), flags: [])
		XCTAssertEqual(step(n, inProgress(n, flags: flags)), "gauge")
	}

	func testVampireSlayerSteps() {
		let n = "Vampire Slayer"
		XCTAssertEqual(step(n, inProgress(n)), "harlow")
		XCTAssertEqual(step(n, inProgress(n, items: [1917: 1])), "harlow")
		XCTAssertEqual(step(n, inProgress(n, items: [1549: 1, 2347: 1])), "kill")
		let c = QuestEngine.checklist(def(n).steps[1], inProgress(n, items: [1549: 1]))
		XCTAssertEqual(c.map(\.state), [.have, .missing, .missing])
		XCTAssertFalse(QuestEngine.checklistComplete(def(n).steps[1], inProgress(n, items: [1549: 1])))
		XCTAssertTrue(QuestEngine.checklistComplete(def(n).steps[1], inProgress(n, items: [1549: 1, 2347: 1])), "garlic is optional")
	}

	func testRomeoAndJulietUsesItemsThenTheJournal() {
		let n = "Romeo & Juliet"
		XCTAssertEqual(step(n, inProgress(n)), "juliet")
		XCTAssertEqual(step(n, inProgress(n, items: [755: 1])), "letter")
		XCTAssertEqual(step(n, inProgress(n, items: [753: 1])), "berries")
		XCTAssertEqual(step(n, inProgress(n, items: [756: 1])), "potion")
		XCTAssertEqual(step(n, inProgress(n, journal: ["I should find Father Lawrence and see how we can help."])), "lawrence")
		XCTAssertEqual(step(n, inProgress(n, journal: ["I need to find the Apothecary to make a cadava potion."])), "apothecary")
		XCTAssertEqual(step(n, inProgress(n, journal: ["I will have to find some Cadava berries somewhere!"])), "find_berries")
		XCTAssertEqual(step(n, inProgress(n, journal: ["I have to find Romeo and tell him what's happened."])), "tell")
		// A crossed-out line is history, not the current instruction.
		XCTAssertEqual(step(n, inProgress(n, crossed: ["I should find Father Lawrence and see how we can help."])), "juliet")
	}

	func testDemonSlayerKeysAndSilverlight() {
		let n = "Demon Slayer"
		XCTAssertEqual(step(n, inProgress(n)), "prysin_ask")
		XCTAssertEqual(step(n, inProgress(n, items: [2400: 1])), "key1", "a key in hand means stage 20, so the first missing key is next")
		XCTAssertEqual(step(n, inProgress(n, items: [2401: 1])), "key2")
		XCTAssertEqual(step(n, inProgress(n, items: [2401: 1, 2400: 1])), "key3")
		XCTAssertEqual(step(n, inProgress(n, items: [2401: 1, 2400: 1, 2399: 1])), "prysin")
		XCTAssertEqual(step(n, inProgress(n, journal: ["Sir Prysin needs 3 keys before he can give me Silverlight."])), "key1")
		XCTAssertEqual(step(n, inProgress(n, worn: [2402: 1])), "delrith", "Silverlight wielded still counts as carried")
	}

	func testDoricsQuestCounts() {
		let n = "Doric's Quest"
		XCTAssertEqual(step(n, inProgress(n, items: [434: 6, 436: 4, 440: 1])), "mine")
		XCTAssertEqual(step(n, inProgress(n, items: [434: 6, 436: 4, 440: 2])), "return")
		XCTAssertEqual(step(n, inProgress(n, items: [434: 7, 436: 5, 440: 3])), "return")
	}

	func testWitchsPotionRemembersTheHandIn() {
		let n = "Witch's Potion"
		let four: [Int: Int] = [1957: 1, 300: 1, 2146: 1, 221: 1]
		XCTAssertEqual(step(n, inProgress(n, items: [1957: 1, 300: 1])), "gather")
		XCTAssertEqual(step(n, inProgress(n, items: four)), "give")
		let flags = QuestEngine.updatedFlags(def(n), inProgress(n, items: four), flags: [])
		XCTAssertEqual(step(n, inProgress(n, flags: flags)), "drink", "ingredients gone and handed in: drink from the cauldron")
		XCTAssertEqual(step(n, inProgress(n, journal: ["I should drink from the cauldron and improve my magic!"])), "drink")
	}

	func testKnightsSwordStages() {
		let n = "The Knight's Sword"
		XCTAssertEqual(step(n, inProgress(n)), "reldo")
		XCTAssertEqual(step(n, inProgress(n, journal: ["He will help me now I have gained his trust through pie"])), "thurgo_pie")
		XCTAssertEqual(step(n, inProgress(n, journal: ["Thurgo needs a picture of the sword before he can help."])), "squire_picture")
		XCTAssertEqual(step(n, inProgress(n, journal: ["The Squire told me about a portrait which has a picture of the sword in Sir Vyvin's room"])), "portrait")
		XCTAssertEqual(step(n, inProgress(n, items: [666: 1])), "portrait_back")
		XCTAssertEqual(step(n, inProgress(n, journal: ["according to Thurgo to make a replica sword he will need two Iron Bars and some Blurite Ore."])), "blurite")
		XCTAssertEqual(step(n, inProgress(n, items: [2351: 2, 668: 1])), "thurgo_ready")
		XCTAssertEqual(step(n, inProgress(n, items: [667: 1])), "return")
	}

	func testBlackKnightsFortressSteps() {
		let n = "Black Knights' Fortress"
		XCTAssertEqual(step(n, inProgress(n)), "disguise")
		XCTAssertEqual(step(n, inProgress(n, worn: [1139: 1, 1101: 1])), "listen")
		XCTAssertEqual(step(n, inProgress(n, items: [1965: 1], journal: ["I eavesdropped on a Witch and the Black Knight Captain and discovered that their invincibility potion can be destroyed with a normal cabbage."])), "cabbage")
		XCTAssertEqual(step(n, inProgress(n, items: [1965: 1], journal: ["Sir Amik Varze has asked me to investigate the Black Knights' Fortress"])), "disguise")
		XCTAssertEqual(step(n, inProgress(n, journal: ["destroyed with a normal cabbage."])), "get_cabbage")
		XCTAssertEqual(step(n, inProgress(n, journal: ["my reward from Sir Amik Varze in Falador Castle."])), "report")
	}

	func testPiratesTreasureRemembersTheKey() {
		let n = "Pirate's Treasure"
		XCTAssertEqual(step(n, inProgress(n)), "rum")
		XCTAssertEqual(step(n, inProgress(n, items: [431: 1])), "give_rum")
		let withKey = inProgress(n, items: [432: 1])
		XCTAssertEqual(step(n, withKey), "chest")
		let flags = QuestEngine.updatedFlags(def(n), withKey, flags: [])
		XCTAssertTrue(flags.contains("gaveRum"))
		XCTAssertEqual(step(n, inProgress(n, flags: flags)), "new_key")
		XCTAssertEqual(step(n, inProgress(n, items: [433: 1])), "dig")
		let f2 = QuestEngine.updatedFlags(def(n), inProgress(n, items: [433: 1]), flags: flags)
		XCTAssertEqual(step(n, inProgress(n, flags: f2)), "dig", "the note is gone but the latch remembers it")
	}

	func testPrinceAliRescueFlow() {
		let n = "Prince Ali Rescue"
		XCTAssertEqual(step(n, inProgress(n)), "osman")
		XCTAssertEqual(step(n, inProgress(n, items: [954: 1])), "key_print")
		XCTAssertEqual(step(n, inProgress(n, items: [2423: 1])), "key_osman")
		var flags = QuestEngine.updatedFlags(def(n), inProgress(n, items: [2423: 1]), flags: [])
		XCTAssertEqual(flags, ["briefed", "printed"])
		XCTAssertEqual(step(n, inProgress(n, flags: flags)), "key_leela")
		XCTAssertEqual(step(n, inProgress(n, items: [2418: 1], flags: flags)), "gather")
		let all: [Int: Int] = [954: 1, 2424: 1, 1013: 1, 2419: 1, 2418: 1]
		XCTAssertEqual(step(n, inProgress(n, items: all, flags: flags)), "rescue")
		flags = QuestEngine.updatedFlags(def(n), inProgress(n, items: all, flags: flags), flags: flags)
		XCTAssertTrue(flags.contains("hadAll"))
		// Rope used on Lady Keli: the rest is still in hand.
		var noRope = all; noRope[954] = nil
		XCTAssertEqual(step(n, inProgress(n, items: noRope, flags: flags)), "rescue")
		// Everything used: back to Hassan.
		XCTAssertEqual(step(n, inProgress(n, items: [:], flags: flags)), "report")
	}

	func testDragonSlayerJournalSteps() {
		let n = "Dragon Slayer"
		XCTAssertEqual(step(n, inProgress(n, journal: ["I should speak to Oziach, who lives by the cliffs to the west of Edgeville."])), "oziach")
		XCTAssertEqual(step(n, inProgress(n, journal: ["I should return to the Champions' Guild Guildmaster for more detailed instructions."])), "guildmaster2")
		XCTAssertEqual(step(n, inProgress(n, items: [1535: 1, 1537: 1, 1536: 1, 1540: 1])), "ship")
		XCTAssertEqual(step(n, inProgress(n, items: [1535: 1, 1537: 1, 1540: 1])), "wormbrain")
		XCTAssertEqual(step(n, inProgress(n, items: [11279: 1])), "report")
	}

	// MARK: skipping and checklist

	func testSkippingAStepMovesToTheNextMatchingOne() {
		let n = "Cook's Assistant"
		var f = inProgress(n)
		XCTAssertEqual(step(n, f), "milk")
		f.flags.insert(QuestEngine.skipFlag(def(n).steps.first { $0.id == "milk" }!))
		XCTAssertEqual(step(n, f), "flour")
	}

	func testChecklistTracksInventoryWornAndBank() {
		var inv: [Int: [Int: ServerMessage.InvItem]] = [:]
		inv[QuestContainers.backpack] = [0: .init(id: 1927, count: 1), 3: .init(id: 1944, count: 2)]
		inv[QuestContainers.equipment] = [3: .init(id: 552, count: 1)]
		inv[QuestContainers.bank] = [10: .init(id: 1933, count: 1)]
		let f = QuestFactsSnapshot.from(varps: [29: 1], inventories: inv)
		XCTAssertEqual(f.carried(1944), 2)
		XCTAssertEqual(f.carried(552), 1, "worn items count as carried")
		XCTAssertEqual(f.banked(1933), 1)
		XCTAssertEqual(f.varp(29), 1)
		let c = QuestEngine.checklist(def("Cook's Assistant").steps[1], f)
		XCTAssertEqual(c.map(\.state), [.have, .banked, .have])
		XCTAssertEqual(c.map(\.done), [true, false, true])
		XCTAssertFalse(QuestEngine.checklistComplete(def("Cook's Assistant").steps[1], f))
		// Counts: 20 balls of wool needed, 5 carried.
		var f2 = QuestFactsSnapshot(); f2.give(1759, 5)
		let w = QuestEngine.checklist(def("Sheep Shearer").steps[1], f2)
		XCTAssertEqual(w[0].state, .missing); XCTAssertEqual(w[0].carried, 5)
		f2.give(1759, 15)
		XCTAssertEqual(QuestEngine.checklist(def("Sheep Shearer").steps[1], f2)[0].state, .have)
	}

	func testJournalParsing() throws {
		let key = { (c: Int) in 275 << 16 | c }
		let texts: [Int: String] = [
			key(2): "<col=8A0808>Cook's Assistant</col>",
			key(12): "<col=08088A>It's the <col=8A0808>Duke of Lumbridge's</col> birthday",
			key(13): "<str><col=000000>I have given the cook a bucket of milk.</col></str>",
			key(14): "",
			(100 << 16 | 2): "not the journal",
		]
		let j = try XCTUnwrap(QuestJournal.parse(texts: texts))
		XCTAssertEqual(j.quest, "Cook's Assistant")
		XCTAssertEqual(j.lines, [.init("It's the Duke of Lumbridge's birthday", crossedOut: false), .init("I have given the cook a bucket of milk.", crossedOut: true)])
		XCTAssertNil(QuestJournal.parse(texts: [100 << 16 | 2: "x"]))
		var f = QuestFactsSnapshot(); f.journals[j.quest] = j
		XCTAssertTrue(QuestEngine.holds(.journalDone("bucket of milk"), in: def("Cook's Assistant"), f))
		XCTAssertFalse(QuestEngine.holds(.journalActive("bucket of milk"), in: def("Cook's Assistant"), f))
		XCTAssertTrue(QuestEngine.holds(.journalActive("duke of lumbridge"), in: def("Cook's Assistant"), f))
		// The journal of another quest is ignored.
		XCTAssertFalse(QuestEngine.holds(.journal("birthday"), in: def("Sheep Shearer"), f))
	}

	func testVarbitStatusSource() {
		let s = QuestStatusSource(varbit: 451, notStarted: [0], complete: [2])
		var f = QuestFactsSnapshot()
		XCTAssertEqual(s.status(f), .notStarted)
		f.varbits[451] = 1
		XCTAssertEqual(s.status(f), .inProgress)
		f.varbits[451] = 2
		XCTAssertEqual(s.status(f), .complete)
		let d = QuestDef(id: "x", name: "X", serverIndex: 1, points: 1, source: s, steps: [QuestStep("a", "a", when: [.varbit(9, 3...4)])])
		XCTAssertEqual(QuestCatalog.varbits(in: [d]), [9])
	}
}
