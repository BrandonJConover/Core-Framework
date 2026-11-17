import Foundation

// Port Sarim, Draynor and Al Kharid quests, from content/region/asgarnia/portsarim/quest and
// content/region/desert/alkharid/quest.
extension QuestCatalog {
	static let portSarimAlKharid: [QuestDef] = [piratesTreasure, princeAliRescue]

	// PiratesTreasure.java: `Quest(PIRATES_TREASURE, 23, 22, 2, 71, 0, 1, 4)` = varp 71: red 0, yellow 1, green 4.
	// Stage 10: get Karamjan rum 431 into Wydin's back room (crate loc 2071) and give it to Redbeard Frank; 20: Frank's
	// chest key 432 opens the chest (loc 2079) in the Blue Moon Inn's upstairs room, which holds the pirate message 433;
	// then dig in Falador's park (2999,3383), Saradomin statue.
	static let piratesTreasure = QuestDef(
		id: "pirates_treasure", name: "Pirate's Treasure", serverIndex: 23, points: 2,
		source: QuestStatusSource(varp: 71, complete: [4]),
		summary: "Talk to Redbeard Frank at Port Sarim.",
		latches: [
			QuestLatch("gaveRum", when: [.hasAny([432, 433])]),
			QuestLatch("gotNote", when: [.has(item: 433)]),
		],
		steps: [
			QuestStep("start", "Talk to Redbeard Frank on his ship at Port Sarim.",
				when: [.status(.notStarted)], targets: [frank]),
			QuestStep("dig", "Dig with a spade by the Saradomin statue in Falador's park, where the note points.",
				when: [.any([.has(item: 433), .flag("gotNote")])],
				targets: [.tile(name: "Dig spot", at: QuestTile(2999, 3383), radius: 1)], items: [QuestItem(952, "Spade"), QuestItem(433, "Pirate message", note: "read it", needed: false)]),
			QuestStep("chest", "Use the key on the chest in the upstairs room of the Blue Moon Inn in Varrock.",
				when: [.has(item: 432)], targets: [.loc(name: "Chest", id: 2079, at: QuestTile(3219, 3396, 1))], items: [QuestItem(432, "Chest key")]),
			QuestStep("new_key", "You lost the chest key. Ask Redbeard Frank for another.", when: [.flag("gaveRum")], targets: [frank]),
			QuestStep("give_rum", "Give the Karamjan rum to Redbeard Frank.", when: [.has(item: 431)], targets: [frank], items: [QuestItem(431, "Karamjan rum")]),
			QuestStep("rum", "Smuggle Karamjan rum to Port Sarim: buy rum from Zambo, hide it in the banana crate at Luthas's plantation on Karamja, then take it out of the crate in the back room of Wydin's shop.",
				targets: [.npc(name: "Zambo", ids: [568], at: QuestTile(2925, 3143)), .npc(name: "Luthas", ids: [379], at: QuestTile(2939, 3156)), .loc(name: "Wydin's crate", id: 2071, at: QuestTile(3009, 3207))],
				items: [QuestItem(431, "Karamjan rum")]),
		])

	static let frank = QuestTarget.npc(name: "Redbeard Frank", ids: [375], at: QuestTile(3053, 3249))

	// PrinceAliRescue.java: `Quest(PRINCE_ALI_RESCUE, 24, 23, 3, 273, 0, 1, 110)` = varp 273: red 0, yellow 1, green 110.
	// Stages: 10 Osman, 20 gather rope 954, skin paste 2424, pink skirt 1013, yellow wig 2419 and a copy of the cell key
	// (soft clay 1761 -> Lady Keli's key print 2423 -> Osman -> Leela -> bronze key 2418), 40 deal with Joe, 50 tie up Lady Keli
	// and unlock the cell (prison door 2881), 60 return to Hassan, 100 done.
	static let princeAliRescue = QuestDef(
		id: "prince_ali_rescue", name: "Prince Ali Rescue", serverIndex: 24, points: 3,
		source: QuestStatusSource(varp: 273, complete: [110]),
		summary: "Talk to Hassan in Al Kharid Palace.",
		latches: [
			QuestLatch("briefed", when: [.hasAny([954, 2424, 1013, 2419, 1761, 2423, 2418])]),
			QuestLatch("printed", when: [.has(item: 2423)]),
			QuestLatch("hadAll", when: [.has(item: 954), .has(item: 2424), .has(item: 1013), .has(item: 2419), .has(item: 2418)]),
		],
		steps: [
			QuestStep("start", "Talk to Hassan in Al Kharid Palace.", when: [.status(.notStarted)], targets: [hassan]),
			QuestStep("report", "Prince Ali is free. Return to Hassan for your reward.",
				when: [.flag("hadAll"), .not(.has(item: 2424)), .not(.has(item: 1013)), .not(.has(item: 2419))], targets: [hassan]),
			QuestStep("rescue", "Rescue the prince at Lady Keli's jail: get Joe the guard drunk (give him beer) or bribe him, use the rope on Lady Keli, unlock the cell door with the bronze key, then use the wig, paste and skirt on Prince Ali.",
				when: [.has(item: 2418), .has(item: 2424), .has(item: 1013), .has(item: 2419), .any([.has(item: 954), .flag("hadAll")])],
				targets: [.npc(name: "Joe", ids: [916], at: QuestTile(3122, 3245)), .npc(name: "Lady Keli", ids: [919], at: QuestTile(3128, 3245)), .loc(name: "Prison door", id: 2881, at: QuestTile(3123, 3243))],
				items: parItems + [QuestItem(1917, "Beer", count: 3, note: "for Joe, or bribe him", needed: false)]),
			QuestStep("key_osman", "Take the key print to Osman in Al Kharid; he arranges a copy through Leela.",
				when: [.has(item: 2423)], targets: [osman], items: [QuestItem(2423, "Key print")]),
			QuestStep("key_leela", "Collect the duplicate key from Leela, east of Draynor Village.",
				when: [.flag("printed"), .not(.has(item: 2418))], targets: [.npc(name: "Leela", ids: [915], at: QuestTile(3108, 3264))], items: [QuestItem(2418, "Bronze key")]),
			QuestStep("key_print", "Take soft clay to Lady Keli and ask to touch the key to make an imprint. (Soak clay in a bucket of water to soften it.)",
				when: [.flag("briefed"), .not(.has(item: 2418))], targets: [.npc(name: "Lady Keli", ids: [919], at: QuestTile(3128, 3245))],
				items: [QuestItem(1761, "Soft clay")] + parItems),
			QuestStep("gather", "Collect the disguise: a yellow wig (Ned in Draynor spins one from 3 balls of wool, then dye it yellow), skin paste (Aggie in Draynor), a pink skirt and a rope.",
				when: [.flag("briefed")], targets: [.npc(name: "Ned", ids: [743], at: QuestTile(3098, 3257)), .npc(name: "Aggie", ids: [922], at: QuestTile(3086, 3261))], items: parItems),
			QuestStep("osman", "Speak to Osman in Al Kharid for the details of the plan.", targets: [osman]),
		])

	static let hassan = QuestTarget.npc(name: "Hassan", ids: [923], at: QuestTile(3302, 3163))
	static let osman = QuestTarget.npc(name: "Osman", ids: [924], at: QuestTile(3286, 3180))
	static let parItems = [
		QuestItem(954, "Rope"), QuestItem(2424, "Paste"), QuestItem(1013, "Pink skirt"), QuestItem(2419, "Wig"), QuestItem(2418, "Bronze key"),
	]
}
