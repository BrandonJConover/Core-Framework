import Foundation

// Stages and ids below come from the 2009scape server's quest scripts (content/region/misthalin/lumbridge/quest,
// wiztower/quest). Each quest says which source file and varp config it was read from.
extension QuestCatalog {
	static let lumbridge: [QuestDef] = [cooksAssistant, sheepShearer, runeMysteries, restlessGhost, impCatcher]

	// CooksAssistant.kt: `Quest(COOKS_ASSISTANT, 15, 14, 1, 29, 0, 1, 2)` = list varp 29: red 0, yellow 1, green 2.
	// Stage 10 on start, 100 on finish; the hand-ins are server attributes, so the guide goes by what is carried.
	static let cooksAssistant = QuestDef(
		id: "cooks_assistant", name: "Cook's Assistant", serverIndex: 15, points: 1,
		source: QuestStatusSource(varp: 29, complete: [2]),
		summary: "Talk to the Cook in the Lumbridge Castle kitchen.",
		steps: [
			QuestStep("start", "Talk to the Cook in the Lumbridge Castle kitchen and offer to help with the Duke's birthday cake.",
				when: [.status(.notStarted)], targets: [.npc(name: "Cook", ids: [278], at: QuestTile(3209, 3215))]),
			QuestStep("return", "You have everything. Give the milk, flour and egg to the Cook.",
				when: [.has(item: 1927), .has(item: 1933), .has(item: 1944)],
				targets: [.npc(name: "Cook", ids: [278], at: QuestTile(3209, 3215))], items: cooksItems),
			QuestStep("milk", "Fill a bucket with milk from a dairy cow in the field east of Lumbridge (take an empty bucket; there is one at the Groats' farm).",
				when: [.not(.has(item: 1927))],
				targets: [.loc(name: "Dairy cow", id: 8689, at: QuestTile(3254, 3272))], items: cooksItems),
			QuestStep("flour", "Make a pot of flour: pick wheat in the field, take an empty pot, climb to the top of the mill, put the wheat in the hopper, pull the hopper controls, then take the flour from the bin downstairs.",
				when: [.not(.has(item: 1933))],
				targets: [.loc(name: "Hopper controls", id: 2718, at: QuestTile(3166, 3305, 2))], items: cooksItems),
			QuestStep("egg", "Pick up an egg at the Groats' farm north-west of the cow field.",
				targets: [.groundItem(name: "Egg", id: 1944, at: QuestTile(3229, 3299))], items: cooksItems),
		])

	static let cooksItems = [
		QuestItem(1927, "Bucket of milk"), QuestItem(1933, "Pot of flour"), QuestItem(1944, "Egg"),
	]

	// SheepShearer.kt: `Quest(SHEEP_SHEARER, 28, 27, 1, 179, 0, 20, 21)` = varp 179: red 0, yellow 20, green 21.
	// The balls of wool handed in so far are a server attribute, so the checklist counts what you carry.
	static let sheepShearer = QuestDef(
		id: "sheep_shearer", name: "Sheep Shearer", serverIndex: 28, points: 1,
		source: QuestStatusSource(varp: 179, complete: [21]),
		summary: "Talk to Fred the Farmer at his farm north-west of Lumbridge.",
		steps: [
			QuestStep("start", "Talk to Fred the Farmer at his farm north-west of Lumbridge.",
				when: [.status(.notStarted)], targets: [.npc(name: "Fred the Farmer", ids: [758], at: QuestTile(3189, 3273))]),
			QuestStep("deliver", "Bring Fred the 20 balls of wool.",
				when: [.has(item: 1759, count: 20)], targets: [.npc(name: "Fred the Farmer", ids: [758], at: QuestTile(3189, 3273))],
				items: [QuestItem(1759, "Ball of wool", count: 20)]),
			QuestStep("spin", "Spin the wool into balls on the spinning wheel upstairs in Lumbridge Castle.",
				when: [.has(item: 1737)], targets: [.loc(name: "Spinning wheel", id: 36970, at: QuestTile(3209, 3212, 1))],
				items: [QuestItem(1737, "Wool"), QuestItem(1759, "Ball of wool", count: 20)]),
			QuestStep("shear", "Shear sheep in Fred's pen with the shears. Collect wool until you can make 20 balls.",
				when: [.has(item: 1735)], targets: [.npc(name: "Sheep", ids: [43, 1765, 3579, 5156, 5157, 5160, 5161], at: QuestTile(3200, 3267))],
				items: [QuestItem(1735, "Shears"), QuestItem(1759, "Ball of wool", count: 20, needed: false)]),
			QuestStep("shears", "Pick up the shears from the table in Fred's house, then shear his sheep.",
				targets: [.groundItem(name: "Shears", id: 1735, at: QuestTile(3192, 3272))], items: [QuestItem(1735, "Shears")]),
		])

	// RuneMysteries.java: `Quest(RUNE_MYSTERIES, 27, 26, 1, 63, 0, 1, 6)` = varp 63: red 0, yellow 1, green 6.
	// Stages: 10 talisman from the Duke, 20 given to Sedridor (he asks again), 30 research package, 40 delivered to
	// Aubury, 50 Aubury's notes, 100 done. Items (WizardTowerPlugin.SedridorDialogue): talisman 1438, package 290, notes 291.
	static let runeMysteries = QuestDef(
		id: "rune_mysteries", name: "Rune Mysteries", serverIndex: 27, points: 1,
		source: QuestStatusSource(varp: 63, complete: [6]),
		summary: "Talk to Duke Horacio upstairs in Lumbridge Castle.",
		latches: [QuestLatch("hadPackage", when: [.has(item: 290)])],
		steps: [
			QuestStep("start", "Talk to Duke Horacio on the first floor of Lumbridge Castle.",
				when: [.status(.notStarted)], targets: [.npc(name: "Duke Horacio", ids: [741], at: QuestTile(3212, 3220, 1))]),
			QuestStep("notes", "Take Aubury's research notes to Sedridor in the Wizards' Tower basement.",
				when: [.has(item: 291)], targets: [sedridor], items: [QuestItem(291, "Notes", note: "Aubury's research notes")]),
			QuestStep("package", "Take the research package to Aubury in the rune shop in south-east Varrock.",
				when: [.has(item: 290)], targets: [.npc(name: "Aubury", ids: [553], at: QuestTile(3253, 3403))], items: [QuestItem(290, "Research package")]),
			QuestStep("talisman", "Take the talisman to Sedridor in the Wizards' Tower basement (ladder south-west of Lumbridge).",
				when: [.has(item: 1438)], targets: [.loc(name: "Wizards' Tower ladder", id: 2147, at: QuestTile(3104, 3162)), sedridor], items: [QuestItem(1438, "Air talisman")]),
			QuestStep("aubury2", "Speak to Aubury again; he has finished with the research package.",
				when: [.flag("hadPackage")], targets: [.npc(name: "Aubury", ids: [553], at: QuestTile(3253, 3403))]),
			QuestStep("sedridor", "Speak to Sedridor in the Wizards' Tower basement to agree to help with his research.",
				targets: [.loc(name: "Wizards' Tower ladder", id: 2147, at: QuestTile(3104, 3162)), sedridor]),
		])

	static let sedridor = QuestTarget.npc(name: "Sedridor", ids: [300], at: QuestTile(3105, 9569))

	// RestlessGhost.java: `Quest(THE_RESTLESS_GHOST, 25, 24, 1, 107, 0, 4, 5)` = varp 107: red 0, yellow 4, green 5.
	// Stages: 10 talk to Father Urhney, 20 talk to the ghost, 30 fetch the skull, 40 return it.
	// Items: ghostspeak amulet 552, skull 964. Coffin loc ids 2145 (shut) / 15061 (open); skull altar loc 2146 (RestlessGhostPlugin).
	static let restlessGhost = QuestDef(
		id: "restless_ghost", name: "The Restless Ghost", serverIndex: 25, points: 1,
		source: QuestStatusSource(varp: 107, complete: [5]),
		summary: "Talk to Father Aereck in the church next to Lumbridge Castle.",
		requirements: ["Be unafraid of a level 13 skeleton."],
		steps: [
			QuestStep("start", "Talk to Father Aereck in the church next to Lumbridge Castle.",
				when: [.status(.notStarted)], targets: [.npc(name: "Father Aereck", ids: [456], at: QuestTile(3244, 3205))]),
			QuestStep("return_skull", "Put the skull in the ghost's coffin: open the coffin in the graveyard and use the skull on it.",
				when: [.has(item: 964)], targets: [.loc(name: "Coffin", id: 2145, at: QuestTile(3249, 3192))], items: [QuestItem(964, "Skull")]),
			QuestStep("skull", "Search the altar in the Wizards' Tower basement for the ghost's skull. A skeleton guards it.",
				when: [.any([.journalActive("Ghost's Skull"), .journalActive("Skull back")])],
				targets: [.loc(name: "Skull altar", id: 2146, at: QuestTile(3120, 9566))], items: [QuestItem(552, "Ghostspeak amulet", note: "worn", needed: false)]),
			QuestStep("ghost", "Wear the Amulet of Ghostspeak and talk to the ghost: open the coffin in the graveyard.",
				when: [.hasAny([552])], targets: [.loc(name: "Coffin", id: 2145, at: QuestTile(3249, 3192))], items: [QuestItem(552, "Ghostspeak amulet", note: "wear it")]),
			QuestStep("urhney", "Find Father Urhney in his shack in Lumbridge Swamp; he gives you the amulet.",
				targets: [.npc(name: "Father Urhney", ids: [458], at: QuestTile(3148, 3175))]),
		])

	// ImpCatcher.java: `Quest(IMP_CATCHER, 21, 20, 1, 160, 0, 1, 2)` = varp 160: red 0, yellow 1, green 2.
	// Beads: black 1474, red 1470, white 1476, yellow 1472.
	static let impCatcher = QuestDef(
		id: "imp_catcher", name: "Imp Catcher", serverIndex: 21, points: 1,
		source: QuestStatusSource(varp: 160, complete: [2]),
		summary: "Talk to Wizard Mizgog at the top of the Wizards' Tower.",
		steps: [
			QuestStep("start", "Talk to Wizard Mizgog on the second floor of the Wizards' Tower.",
				when: [.status(.notStarted)], targets: [mizgog]),
			QuestStep("return", "You have all four beads. Give them to Wizard Mizgog.",
				when: impBeads.map { .has(item: $0.id) }, targets: [mizgog], items: impBeads),
			QuestStep("beads", "Kill imps until they drop the four missing beads.",
				targets: [.npc(name: "Imp", ids: [708, 709, 1531], at: QuestTile(3068, 3251))], items: impBeads),
		])

	static let mizgog = QuestTarget.npc(name: "Wizard Mizgog", ids: [706], at: QuestTile(3103, 3163, 2))
	static let impBeads = [
		QuestItem(1474, "Black bead"), QuestItem(1470, "Red bead"), QuestItem(1476, "White bead"), QuestItem(1472, "Yellow bead"),
	]
}
