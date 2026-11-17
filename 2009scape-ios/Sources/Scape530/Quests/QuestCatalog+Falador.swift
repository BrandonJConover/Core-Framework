import Foundation

// Falador, Rimmington and Port Sarim area quests, from content/region/asgarnia.
extension QuestCatalog {
	static let falador: [QuestDef] = [doricsQuest, witchsPotion, knightsSword, blackKnightsFortress]

	// DoricsQuest.kt: `Quest(DORICS_QUEST, 17, 16, 1, 31, 0, 1, 100)` = varp 31: red 0, yellow 1, green 100.
	// Doric wants 6 clay 434, 4 copper ore 436 and 2 iron ore 440.
	static let doricsQuest = QuestDef(
		id: "dorics_quest", name: "Doric's Quest", serverIndex: 17, points: 1,
		source: QuestStatusSource(varp: 31, complete: [100]),
		summary: "Talk to Doric, north of Falador.",
		requirements: ["Level 15 Mining helps."],
		steps: [
			QuestStep("start", "Talk to Doric in his smithy north of Falador.",
				when: [.status(.notStarted)], targets: [doric]),
			QuestStep("return", "Give Doric the clay, copper ore and iron ore.",
				when: doricItems.map { .has(item: $0.id, count: $0.count) }, targets: [doric], items: doricItems),
			QuestStep("mine", "Mine the clay, copper ore and iron ore at the Rimmington mine (south of Falador, west of Port Sarim). You need a pickaxe.",
				targets: [.tile(name: "Rimmington mine", at: QuestTile(2984, 3237), radius: 6)],
				items: doricItems + [QuestItem(1265, "Bronze pickaxe", note: "or any better pickaxe", needed: false)]),
		])

	static let doric = QuestTarget.npc(name: "Doric", ids: [284], at: QuestTile(2953, 3450))
	static let doricItems = [QuestItem(434, "Clay", count: 6), QuestItem(436, "Copper ore", count: 4), QuestItem(440, "Iron ore", count: 2)]

	// WitchsPotion.kt: `Quest(WITCHS_POTION, 31, 30, 1, 67, 0, 1, 3)` = varp 67: red 0, yellow 1, green 3.
	// Stage 1..39: bring onion 1957, rat's tail 300, burnt meat 2146, eye of newt 221; 40..99: drink from the cauldron.
	// Hetty takes the items, so the "gave" latch remembers that the four were once carried together.
	static let witchsPotion = QuestDef(
		id: "witchs_potion", name: "Witch's Potion", serverIndex: 31, points: 1,
		source: QuestStatusSource(varp: 67, complete: [3]),
		summary: "Talk to Hetty in her house in Rimmington.",
		latches: [QuestLatch("gave", when: witchItems.map { .has(item: $0.id) })],
		steps: [
			QuestStep("start", "Talk to Hetty in her house in Rimmington, west of Port Sarim.",
				when: [.status(.notStarted)], targets: [hetty]),
			QuestStep("give", "Give Hetty the onion, rat's tail, burnt meat and eye of newt.",
				when: witchItems.map { .has(item: $0.id) }, targets: [hetty], items: witchItems),
			QuestStep("drink", "Drink from the cauldron in Hetty's house.",
				when: [.any([.flag("gave"), .journalActive("cauldron")])], targets: [.loc(name: "Cauldron", id: 2024, at: QuestTile(2967, 3205))]),
			QuestStep("gather", "Gather the four ingredients: an onion from the patch north of Hetty's house, a rat's tail from a rat, a piece of burnt meat (cook raw meat until it burns) and an eye of newt from Betty's shop in Port Sarim.",
				targets: [.loc(name: "Onion", id: 3366, at: QuestTile(2950, 3251)), .npc(name: "Betty", ids: [583], at: QuestTile(3011, 3257)), .npc(name: "Rat", ids: [47], at: QuestTile(3089, 3266))],
				items: witchItems),
		])

	static let hetty = QuestTarget.npc(name: "Hetty", ids: [307], at: QuestTile(2968, 3206))
	static let witchItems = [QuestItem(1957, "Onion"), QuestItem(300, "Rat's tail"), QuestItem(2146, "Burnt meat"), QuestItem(221, "Eye of newt")]

	// TheKnightsSword.java: `Quest(THE_KNIGHTS_SWORD, 22, 21, 1, 122, 0, 1, 7)` = varp 122: red 0, yellow 1, green 7.
	// Stages: 10 Reldo, 20 Thurgo (redberry pie 2325), 30 Thurgo again, 40 ask the Squire for a picture, 50 portrait 666
	// from Sir Vyvin's cupboard, 60 two iron bars 2351 + blurite ore 668 to Thurgo, then blurite sword 667 to the Squire.
	static let knightsSword = QuestDef(
		id: "knights_sword", name: "The Knight's Sword", serverIndex: 22, points: 1,
		source: QuestStatusSource(varp: 122, complete: [7]),
		summary: "Talk to the Squire in the White Knights' Castle courtyard in Falador.",
		requirements: ["Level 10 Mining.", "Be unafraid of level 57 ice warriors."],
		steps: [
			QuestStep("start", "Talk to the Squire in the courtyard of the White Knights' Castle in southern Falador.",
				when: [.status(.notStarted)], targets: [squire]),
			QuestStep("return", "Give the blurite sword to the Squire.", when: [.has(item: 667)], targets: [squire], items: [QuestItem(667, "Blurite sword")]),
			QuestStep("thurgo_ready", "You have the bars and the ore. Take them to Thurgo.",
				when: [.has(item: 2351, count: 2), .has(item: 668)], targets: [thurgo], items: ksMetal),
			QuestStep("portrait_back", "Take the portrait to Thurgo.", when: [.has(item: 666)], targets: [thurgo], items: [QuestItem(666, "Portrait")]),
			QuestStep("blurite", "Mine blurite ore in the caves below Thurgo's house (10 Mining) and smelt two iron bars, then take both to Thurgo.",
				when: [.journalActive("Blurite")], targets: [.loc(name: "Blurite rocks", id: 33220, at: QuestTile(3049, 9566))], items: ksMetal),
			QuestStep("portrait", "Search the cupboard in Sir Vyvin's room (upstairs in the castle) for the portrait of the sword.",
				when: [.journalActive("portrait")], targets: [.loc(name: "Sir Vyvin's cupboard", id: 2271, at: QuestTile(2984, 3336, 2))], items: [QuestItem(666, "Portrait")]),
			QuestStep("squire_picture", "Ask the Squire about a picture of the sword.", when: [.journalActive("picture of the sword")], targets: [squire]),
			QuestStep("thurgo_pie", "Take a redberry pie to Thurgo, the Imcando dwarf south-west of Port Sarim.",
				when: [.journalActive("pie")], targets: [thurgo], items: [QuestItem(2325, "Redberry pie")]),
			QuestStep("reldo", "Ask Reldo in the Varrock Palace library about the Imcando dwarves.",
				targets: [.npc(name: "Reldo", ids: [2660], at: QuestTile(3208, 3496))]),
		])

	static let squire = QuestTarget.npc(name: "Squire", ids: [606], at: QuestTile(2974, 3343))
	static let thurgo = QuestTarget.npc(name: "Thurgo", ids: [604], at: QuestTile(3001, 3144))
	static let ksMetal = [QuestItem(2351, "Iron bar", count: 2), QuestItem(668, "Blurite ore")]

	// BlackKnightsFortress.java: `Quest(BLACK_KNIGHTS_FORTRESS, 14, 13, 3, 130, 0, 1, 4)` = varp 130: red 0, yellow 1, green 4.
	// Stages: 10 get in (worn bronze med helm 1139 + iron chainbody 1101 at the sturdy door 2337), 20 sabotage with a cabbage 1965
	// (grill 2342, hole 2336), 30 report to Sir Amik Varze, 100 done. Needs 12 quest points.
	static let blackKnightsFortress = QuestDef(
		id: "black_knights_fortress", name: "Black Knights' Fortress", serverIndex: 14, points: 3,
		source: QuestStatusSource(varp: 130, complete: [4]),
		summary: "Talk to Sir Amik Varze in Falador Castle.",
		requirements: ["12 quest points.", "Level 33 knights; Smithing 26 helps."],
		steps: [
			QuestStep("start", "Talk to Sir Amik Varze on the top floor of Falador Castle.",
				when: [.status(.notStarted)], targets: [amik]),
			QuestStep("report", "The witch's potion is ruined. Return to Sir Amik Varze for your reward.", when: [.journalActive("reward")], targets: [amik]),
			QuestStep("cabbage", "Climb to the hole on the fortress's upper floor and drop the cabbage in (use it on the hole).",
				when: [.has(item: 1965), .not(.journalActive("investigate"))], targets: [.loc(name: "Hole", id: 2336, at: QuestTile(3031, 3507, 1))], items: [QuestItem(1965, "Cabbage", note: "not a cabbage from the Draynor patch")]),
			QuestStep("get_cabbage", "Pick a cabbage from the field north of Falador, then sneak back into the fortress and use it on the hole.",
				when: [.journalActive("cabbage")], targets: [.tile(name: "Cabbage field", at: QuestTile(3045, 3291), radius: 4)], items: [QuestItem(1965, "Cabbage")]),
			QuestStep("listen", "Listen at the grill in the fortress's dining hall.",
				when: [.has(item: 1139), .has(item: 1101)], targets: [.loc(name: "Grill", id: 2342, at: QuestTile(3026, 3507))], items: bkDisguise),
			QuestStep("disguise", "Wear a bronze med helm and an iron chainbody, then enter the Black Knights' Fortress on Ice Mountain through the sturdy door.",
				targets: [.loc(name: "Sturdy door", id: 2337, at: QuestTile(3016, 3514))], items: bkDisguise),
		])

	static let amik = QuestTarget.npc(name: "Sir Amik Varze", ids: [608], at: QuestTile(2962, 3337, 2))
	static let bkDisguise = [QuestItem(1139, "Bronze med helm", note: "wear it"), QuestItem(1101, "Iron chainbody", note: "wear it")]
}
