import Foundation

// Goblin Village quests, from content/region/asgarnia/goblinvillage/quest.
extension QuestCatalog {
	static let goblinVillage: [QuestDef] = [goblinDiplomacy]

	// GoblinDiplomacy.java overrides `getConfig`: varp 62 is 0 before the quest, 1 at stage 10, 4 at 20, 5 at 30, 6 done.
	// The generals want orange (286), then blue (287), then plain brown goblin mail (288). Dyes: orange 1769, blue 1767.
	static let goblinDiplomacy = QuestDef(
		id: "goblin_diplomacy", name: "Goblin Diplomacy", serverIndex: 20, points: 5,
		source: QuestStatusSource(varp: 62, complete: [6]),
		summary: "Talk to the goblin generals in Goblin Village.",
		steps: [
			QuestStep("start", "Talk to General Bentnoze or General Wartface in Goblin Village.", when: [.status(.notStarted)], targets: generals),
			QuestStep("orange_show", "Show the orange goblin armour to the generals.", when: [.varp(62, 1...1), .has(item: 286)], targets: generals, items: [QuestItem(286, "Orange goblin mail")]),
			QuestStep("orange_make", "Make orange goblin armour: use an orange dye on goblin mail (kill goblins for the mail; make the dye from red and yellow dye).",
				when: [.varp(62, 1...1)], targets: [goblins], items: [QuestItem(288, "Goblin mail"), QuestItem(1769, "Orange dye")]),
			QuestStep("blue_show", "Show the blue goblin armour to the generals.", when: [.varp(62, 4...4), .has(item: 287)], targets: generals, items: [QuestItem(287, "Blue goblin mail")]),
			QuestStep("blue_make", "Make blue goblin armour: use a blue dye on goblin mail.",
				when: [.varp(62, 4...4)], targets: [goblins], items: [QuestItem(288, "Goblin mail"), QuestItem(1767, "Blue dye")]),
			QuestStep("brown_show", "Show plain brown goblin mail to the generals.", when: [.varp(62, 5...5), .has(item: 288)], targets: generals, items: [QuestItem(288, "Goblin mail")]),
			QuestStep("brown_get", "Get a plain goblin mail from a goblin.", when: [.varp(62, 5...5)], targets: [goblins], items: [QuestItem(288, "Goblin mail")]),
			QuestStep("talk", "Talk to the generals.", targets: generals),
		])

	static let generals = [
		QuestTarget.npc(name: "General Bentnoze", ids: [4493], at: QuestTile(2957, 3513)),
		QuestTarget.npc(name: "General Wartface", ids: [4494], at: QuestTile(2957, 3512)),
	]
	static let goblins = QuestTarget.tile(name: "Goblin Village", at: QuestTile(2957, 3505), radius: 6)
}
