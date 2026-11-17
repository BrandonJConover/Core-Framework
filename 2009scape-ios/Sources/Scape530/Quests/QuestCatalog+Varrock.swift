import Foundation

// Varrock quests, from content/region/misthalin/varrock/quest.
extension QuestCatalog {
	static let varrock: [QuestDef] = [romeoJuliet, demonSlayer, dragonSlayer]

	// RomeoJuliet.java: `Quest(ROMEO_JULIET, 26, 25, 5, 144, 0, 1, 100)` = varp 144: red 0, yellow 1, green 100.
	// Stages: 10 find Juliet, 20 carry her message to Romeo (letter 755), 30 Father Lawrence, 40 Apothecary,
	// 50 cadava berries 753, 60 cadava potion 756 to Juliet, 70 tell Romeo, 100 done. The journal shows only the
	// current instruction, so `journalActive` picks the stage when no item says so.
	static let romeoJuliet = QuestDef(
		id: "romeo_juliet", name: "Romeo & Juliet", serverIndex: 26, points: 5,
		source: QuestStatusSource(varp: 144, complete: [100]),
		summary: "Talk to Romeo in Varrock's central square.",
		steps: [
			QuestStep("start", "Talk to Romeo in Varrock's central square, by the fountain.",
				when: [.status(.notStarted)], targets: [romeo]),
			QuestStep("potion", "Take the cadava potion to Juliet in the house west of Varrock's square (upstairs).",
				when: [.has(item: 756)], targets: [juliet], items: [QuestItem(756, "Cadava potion")]),
			QuestStep("letter", "Take Juliet's message to Romeo.",
				when: [.has(item: 755)], targets: [romeo], items: [QuestItem(755, "Message")]),
			QuestStep("berries", "Take the cadava berries to the Apothecary in south-west Varrock.",
				when: [.has(item: 753)], targets: [apothecary], items: [QuestItem(753, "Cadava berries")]),
			QuestStep("tell", "Find Romeo and tell him what happened.", when: [.journalActive("tell him")], targets: [romeo]),
			QuestStep("find_berries", "Pick cadava berries from the bushes south of Varrock (near the Champions' Guild road), then take them to the Apothecary.",
				when: [.journalActive("find some")], targets: [.tile(name: "Cadava bushes", at: QuestTile(3267, 3367), radius: 4)], items: [QuestItem(753, "Cadava berries")]),
			QuestStep("apothecary", "Ask the Apothecary to make a cadava potion.", when: [.journalActive("Apothecary")], targets: [apothecary]),
			QuestStep("lawrence", "Find Father Lawrence in the church north-east of Varrock.", when: [.journalActive("Father Lawrence")], targets: [.npc(name: "Father Lawrence", ids: [640], at: QuestTile(3253, 3487))]),
			QuestStep("juliet", "Find Juliet and give her Romeo's message.", targets: [juliet]),
		])

	static let romeo = QuestTarget.npc(name: "Romeo", ids: [639], at: QuestTile(3211, 3425))
	static let juliet = QuestTarget.npc(name: "Juliet", ids: [637], at: QuestTile(3158, 3425, 1))
	static let apothecary = QuestTarget.npc(name: "Apothecary", ids: [638], at: QuestTile(3195, 3404))

	// DemonSlayer.java: `Quest(DEMON_SLAYER, 16, 15, 3, 222, 0, 1, 3)` = varp 222: red 0, yellow 1, green 3.
	// Stages: 10 ask Sir Prysin, 20 collect three keys (journal: 1st key down the palace kitchen drain 2401, 2nd with
	// Captain Rovin 2400, 3rd with Wizard Traiborn, 25 bones, 2399), 30 kill Delrith with Silverlight 2402, 100 done.
	static let demonSlayer = QuestDef(
		id: "demon_slayer", name: "Demon Slayer", serverIndex: 16, points: 3,
		source: QuestStatusSource(varp: 222, complete: [3]),
		summary: "Talk to the Gypsy Aris in Varrock's central square.",
		requirements: ["Be able to defeat a level 27 demon."],
		latches: [QuestLatch("keys", when: [.hasAny([2401, 2400, 2399])])],
		steps: [
			QuestStep("start", "Talk to Gypsy Aris in her tent in Varrock's square.",
				when: [.status(.notStarted)], targets: [.npc(name: "Gypsy Aris", ids: [882], at: QuestTile(3203, 3424))]),
			QuestStep("delrith", "Wield Silverlight and go to the stone circle south of Varrock. Say Aris's incantation to banish Delrith.",
				when: [.has(item: 2402)], targets: [.tile(name: "Stone circle", at: QuestTile(3228, 3369), radius: 4)], items: [QuestItem(2402, "Silverlight", note: "wield it")]),
			QuestStep("prysin", "You have all three keys. Take them to Sir Prysin in Varrock Palace for Silverlight.",
				when: [.has(item: 2401), .has(item: 2400), .has(item: 2399)], targets: [prysin], items: dsKeys),
			QuestStep("key1", "The first key was washed down the palace kitchen drain: pour a bucket of water on the drain outside the kitchen, then take the key from the sewer pipe below.",
				when: [keysKnown, .not(.has(item: 2401))], targets: [.tile(name: "Palace kitchen drain", at: QuestTile(3225, 3495, 0), radius: 1)],
				items: dsKeys + [QuestItem(1929, "Bucket of water", needed: false)]),
			QuestStep("key2", "Captain Rovin on the top floor of Varrock Palace's north-west tower has the second key.",
				when: [keysKnown, .not(.has(item: 2400))], targets: [.npc(name: "Captain Rovin", ids: [884], at: QuestTile(3204, 3495, 2))], items: dsKeys),
			QuestStep("key3", "Wizard Traiborn in the Wizards' Tower has the third key if you bring him 25 bones.",
				when: [keysKnown, .not(.has(item: 2399))], targets: [.npc(name: "Traiborn", ids: [881], at: QuestTile(3112, 3162, 1))],
				items: dsKeys + [QuestItem(526, "Bones", count: 25, note: "given to Traiborn", needed: false)]),
			QuestStep("prysin_ask", "Ask Sir Prysin in Varrock Palace where to find the sword Silverlight.", targets: [prysin]),
		])

	static let prysin = QuestTarget.npc(name: "Sir Prysin", ids: [883], at: QuestTile(3204, 3470))
	static let keysKnown = QuestCondition.any([.flag("keys"), .journalActive("3 keys"), .journalActive("1st Key"), .journalActive("2nd Key"), .journalActive("3rd Key")])
	static let dsKeys = [
		QuestItem(2401, "Silverlight key (1st)"), QuestItem(2400, "Silverlight key (2nd)"), QuestItem(2399, "Silverlight key (3rd)"),
	]

	// DragonSlayer.kt: `Quest(DRAGON_SLAYER, 18, 17, 2, 176, 0, 1, 10)` = varp 176: red 0, yellow 1, green 10.
	// Stages: 10 Oziach, 15 Guildmaster again, 20 gather map pieces 1535 / 1537 / 1536, anti-dragon shield 1540, a ship and
	// Captain Ned, 30 sail, 40 kill Elvarg (head 11279), 100 done. Needs 32 quest points for the Champions' Guild.
	static let dragonSlayer = QuestDef(
		id: "dragon_slayer", name: "Dragon Slayer", serverIndex: 18, points: 2,
		source: QuestStatusSource(varp: 176, complete: [10]),
		summary: "Talk to the Guildmaster in the Champions' Guild.",
		requirements: ["32 quest points to enter the Champions' Guild.", "Be able to defeat a level 83 dragon."],
		steps: [
			QuestStep("start", "Talk to the Guildmaster in the Champions' Guild south-west of Varrock.",
				when: [.status(.notStarted)], targets: [guildmaster]),
			QuestStep("oziach", "Speak to Oziach on the cliffs west of Edgeville.", when: [.journalActive("speak to Oziach")], targets: [oziach]),
			QuestStep("guildmaster2", "Return to the Guildmaster for detailed instructions.", when: [.journalActive("return to the Champions' Guild Guildmaster")], targets: [guildmaster]),
			QuestStep("report", "You have slain Elvarg. Tell Oziach.", when: [.has(item: 11279)], targets: [oziach], items: [QuestItem(11279, "Elvarg's head")]),
			QuestStep("kill", "Kill the dragon Elvarg on Crandor.", when: [.journalActive("kill the dragon")], items: [QuestItem(1540, "Anti-dragon shield")]),
			QuestStep("sail", "Go to your ship in Port Sarim and set sail for Crandor with Captain Ned.", when: [.journalActive("set sail for")], targets: [.tile(name: "Port Sarim docks", at: QuestTile(3047, 3204), radius: 4)]),
			QuestStep("shield", "Ask Duke Horacio in Lumbridge Castle for an anti-dragon shield.",
				when: [.journalActive("anti-"), .not(.has(item: 1540))], targets: [.npc(name: "Duke Horacio", ids: [741], at: QuestTile(3212, 3220, 1))], items: dsMaps),
			QuestStep("maze", "Get the map piece from Melzar's Maze near Rimmington (the guildmaster gave you the maze key).",
				when: [.not(.has(item: 1535)), .not(.has(item: 1538))], targets: [.npc(name: "Melzar the Mad", ids: [753], at: QuestTile(2929, 9649))], items: dsMaps),
			QuestStep("oracle", "Ask the Oracle on Ice Mountain about the hidden map piece.",
				when: [.not(.has(item: 1537)), .not(.has(item: 1538))], targets: [.npc(name: "Oracle", ids: [746], at: QuestTile(3010, 3502))], items: dsMaps),
			QuestStep("wormbrain", "Take the map piece from the goblin Wormbrain in Port Sarim's jail.",
				when: [.not(.has(item: 1536)), .not(.has(item: 1538))], targets: [.npc(name: "Wormbrain", ids: [745], at: QuestTile(3013, 3189))], items: dsMaps),
			QuestStep("ship", "Buy a ship from Klarense in Port Sarim, repair its hole (planks, nails, hammer) and hire Captain Ned in Draynor Village.",
				targets: [.npc(name: "Klarense", ids: [744], at: QuestTile(3047, 3204))],
				items: [QuestItem(960, "Plank", count: 3, needed: false), QuestItem(1539, "Steel nails", count: 30, needed: false), QuestItem(2347, "Hammer", needed: false)]),
		])

	static let guildmaster = QuestTarget.npc(name: "Guildmaster", ids: [198], at: QuestTile(3190, 3358))
	static let oziach = QuestTarget.npc(name: "Oziach", ids: [747], at: QuestTile(3069, 3516))
	static let dsMaps = [
		QuestItem(1535, "Map part (Melzar's Maze)"), QuestItem(1537, "Map part (Ice Mountain)"), QuestItem(1536, "Map part (Wormbrain)"), QuestItem(1540, "Anti-dragon shield"),
	]
}
