import Foundation

// Draynor area quests, from content/region/misthalin/draynor/quest.
extension QuestCatalog {
	static let draynor: [QuestDef] = [ernestTheChicken, vampireSlayer]

	// ErnestTheChicken.java: `Quest(ERNEST_THE_CHICKEN, 19, 18, 4, 32, 0, 1, 3)` = varp 32: red 0, yellow 1, green 3.
	// Stage 10: find Ernest; 20: Dr Oddenstein wants oil can 277, pressure gauge 271, rubber tube 276; 100 done.
	static let ernestTheChicken = QuestDef(
		id: "ernest_the_chicken", name: "Ernest the Chicken", serverIndex: 19, points: 4,
		source: QuestStatusSource(varp: 32, complete: [3]),
		summary: "Talk to Veronica outside Draynor Manor.",
		latches: [QuestLatch("parts", when: [.hasAny([277, 271, 276])])],
		steps: [
			QuestStep("start", "Talk to Veronica outside Draynor Manor.",
				when: [.status(.notStarted)], targets: [.npc(name: "Veronica", ids: [285], at: QuestTile(3110, 3330))]),
			QuestStep("return", "You have all three parts. Take them to Professor Oddenstein on the top floor of Draynor Manor.",
				when: [.has(item: 277), .has(item: 271), .has(item: 276)], targets: [oddenstein], items: ernestParts),
			QuestStep("gauge", "Get the pressure gauge: poison the fountain's piranhas (use poison on the fish food, then the fish food on the fountain) and search the fountain.",
				when: [partsKnown, .not(.has(item: 271))],
				targets: [.groundItem(name: "Poison", id: 273, at: QuestTile(3097, 3366)), .groundItem(name: "Fish food", id: 272, at: QuestTile(3108, 3356, 1))], items: ernestParts),
			QuestStep("tube", "Pick up the rubber tube in the manor's ground-floor room.",
				when: [partsKnown, .not(.has(item: 276))], targets: [.groundItem(name: "Rubber tube", id: 276, at: QuestTile(3111, 3367))], items: ernestParts),
			QuestStep("oil", "Get the oil can from the manor basement (use the lever puzzle to cross the rooms).",
				when: [partsKnown, .not(.has(item: 277))], targets: [.groundItem(name: "Oil can", id: 277, at: QuestTile(3092, 9755))], items: ernestParts),
			QuestStep("oddenstein", "Go into Draynor Manor and speak to Professor Oddenstein on the top floor.", targets: [oddenstein]),
		])

	static let ernestParts = [
		QuestItem(277, "Oil can"), QuestItem(271, "Pressure gauge"), QuestItem(276, "Rubber tube"),
	]
	static let partsKnown = QuestCondition.any([.flag("parts"), .journalActive("parts for his machine")])
	static let oddenstein = QuestTarget.npc(name: "Professor Oddenstein", ids: [286], at: QuestTile(3111, 3367, 2))

	// VampireSlayer.java: `Quest(VAMPIRE_SLAYER, 30, 29, 3, 178, 0, 1, 3)` = varp 178: red 0, yellow 1, green 3.
	// Stage 10 see Dr Harlow, 20 Harlow gives advice (a beer buys the stake 1549), 30 kill Count Draynor (coffin loc 2614
	// in the manor basement; garlic 1550 from the cupboard 33502 in Morgan's house; VampireSlayerPlugin).
	static let vampireSlayer = QuestDef(
		id: "vampire_slayer", name: "Vampire Slayer", serverIndex: 30, points: 3,
		source: QuestStatusSource(varp: 178, complete: [3]),
		summary: "Talk to Morgan in Draynor Village.",
		requirements: ["Be able to kill a level 34 vampire."],
		steps: [
			QuestStep("start", "Talk to Morgan in his house in Draynor Village.",
				when: [.status(.notStarted)], targets: [.npc(name: "Morgan", ids: [755], at: QuestTile(3100, 3268))]),
			QuestStep("kill", "Take a clove of garlic from the cupboard upstairs in Morgan's house, then go down to the Draynor Manor basement, open the coffin and kill Count Draynor with the stake and hammer.",
				when: [.has(item: 1549)],
				targets: [.loc(name: "Cupboard", id: 33502, at: QuestTile(3096, 3269, 1)), .loc(name: "Count Draynor's coffin", id: 2614, at: QuestTile(3077, 9775))],
				items: [QuestItem(1549, "Stake"), QuestItem(2347, "Hammer"), QuestItem(1550, "Garlic", note: "weakens the vampire", needed: false)]),
			QuestStep("harlow", "Find Dr Harlow in the Blue Moon Inn in Varrock and give him a beer; he hands over a stake.",
				targets: [.npc(name: "Dr Harlow", ids: [756], at: QuestTile(3222, 3398))],
				items: [QuestItem(1917, "Beer", note: "buy at the bar"), QuestItem(2347, "Hammer", note: "for the stake", needed: false)]),
		])
}
