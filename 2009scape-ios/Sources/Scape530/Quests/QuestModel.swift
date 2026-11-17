import Foundation

// The declarative quest-step format.
//
// This folder is deliberately independent of the plugin system (no `ClientPlugin`, no overlay code), so a server side
// or on-device quest-companion bot can consume the same data: a `QuestDef` says how to read a quest's progress out of
// the varps the 2009scape server sends, and which `QuestStep` is current given a `QuestFacts` view of the player
// (varps, carried items, remembered flags, the open quest journal).
//
// How the server reports quests (Quest.java `getConfig` / QuestRepository `syncronizeTab`): each quest has one list
// varp (or varbit) that the server sets to one of three values: red (stage 0), yellow (stage 1...99) or green
// (stage 100). The finer stage (10, 20, 30 ...) lives only on the server, so the guide narrows the step down with
// carried items, remembered "latch" flags and the quest journal text. A few quests (Goblin Diplomacy) override
// `getConfig` and show their stage in the varp directly; those use `.varp` conditions on top of the status.

/// World tile (the coordinates the server scripts use), plane 0...3.
public struct QuestTile: Equatable, Hashable {
	public var x: Int, z: Int, plane: Int
	public init(_ x: Int, _ z: Int, _ plane: Int = 0) { self.x = x; self.z = z; self.plane = plane }
}

public enum QuestStatus: String, Equatable, Sendable {
	case notStarted, inProgress, complete
}

/// Where the quest list varp / varbit is and which of its values mean red (not started) and green (complete). Any
/// other value is in progress (yellow).
public struct QuestStatusSource: Equatable {
	public enum Kind: Equatable { case varp, varbit }
	public var kind: Kind
	public var id: Int
	public var notStarted: [Int]
	public var complete: [Int]

	public init(varp id: Int, notStarted: [Int] = [0], complete: [Int]) { self.kind = .varp; self.id = id; self.notStarted = notStarted; self.complete = complete }
	public init(varbit id: Int, notStarted: [Int] = [0], complete: [Int]) { self.kind = .varbit; self.id = id; self.notStarted = notStarted; self.complete = complete }

	public func status(_ facts: QuestFacts) -> QuestStatus {
		let v = kind == .varp ? facts.varp(id) : facts.varbit(id)
		if complete.contains(v) { return .complete }
		if notStarted.contains(v) { return .notStarted }
		return .inProgress
	}
}

/// A test on the player. `QuestStep.when` lists conditions that must all hold for the step to be current.
public indirect enum QuestCondition: Equatable {
	case status(QuestStatus)
	/// The varp's value is in the range.
	case varp(Int, ClosedRange<Int>)
	case varbit(Int, ClosedRange<Int>)
	/// At least `count` of the item are carried (backpack or worn).
	case has(item: Int, count: Int = 1)
	/// At least one of the items is carried.
	case hasAny([Int])
	/// The item is in the bank (only known after the bank was opened this session).
	case banked(item: Int)
	/// A flag set by one of the quest's `latches`, or by the player ("I did this") through the App.
	case flag(String)
	/// A line of the last-seen quest journal of this quest contains the text (tags stripped, case-insensitive).
	case journal(String)
	/// ... and that line is crossed out (done, `<str>`).
	case journalDone(String)
	/// ... and that line is not crossed out (the current instruction).
	case journalActive(String)
	case not(QuestCondition)
	case any([QuestCondition])
	case all([QuestCondition])
}

/// A flag that sticks once its conditions held while the quest was in progress, to remember what the player did when
/// the evidence (an item handed in) is gone. Cleared when the quest is not started or complete.
public struct QuestLatch: Equatable {
	public var flag: String
	public var when: [QuestCondition]
	public init(_ flag: String, when: [QuestCondition]) { self.flag = flag; self.when = when }
}

/// An item the step wants. `needed` false lists a tool or a helpful item (shown dimmer, never blocks the checklist).
public struct QuestItem: Equatable {
	public var id: Int
	public var count: Int
	public var name: String
	public var note: String
	public var needed: Bool
	public init(_ id: Int, _ name: String, count: Int = 1, note: String = "", needed: Bool = true) {
		self.id = id; self.name = name; self.count = count; self.note = note; self.needed = needed
	}
}

/// Where a step happens, in the kinds the overlay can draw.
public enum QuestTarget: Equatable {
	/// An npc by type id (ids of the variants of one npc all listed) with a known spawn tile for the off-screen marker.
	case npc(name: String, ids: [Int], at: QuestTile)
	/// A scenery object by id at a world tile.
	case loc(name: String, id: Int, at: QuestTile)
	/// A place to walk to (radius in tiles around it counts as arrived).
	case tile(name: String, at: QuestTile, radius: Int)
	/// An item to find lying around (ground spawn) or to pick up at a tile.
	case groundItem(name: String, id: Int, at: QuestTile)

	public var name: String {
		switch self {
		case .npc(let n, _, _), .loc(let n, _, _), .tile(let n, _, _), .groundItem(let n, _, _): return n
		}
	}

	/// The tile used for the distance and the off-screen marker.
	public var tile: QuestTile {
		switch self {
		case .npc(_, _, let t), .loc(_, _, let t), .tile(_, let t, _), .groundItem(_, _, let t): return t
		}
	}
}

public struct QuestStep: Equatable {
	public var id: String
	/// What to do, a sentence or two.
	public var text: String
	public var when: [QuestCondition]
	public var targets: [QuestTarget]
	public var items: [QuestItem]
	public init(_ id: String, _ text: String, when: [QuestCondition] = [], targets: [QuestTarget] = [], items: [QuestItem] = []) {
		self.id = id; self.text = text; self.when = when; self.targets = targets; self.items = items
	}
}

public struct QuestDef: Equatable {
	/// Stable slug ("cooks_assistant").
	public var id: String
	public var name: String
	/// The server's `Quest` index (QuestRepository key).
	public var serverIndex: Int
	public var points: Int
	public var source: QuestStatusSource
	/// Requirements and recommendations to show before the quest is started.
	public var requirements: [String]
	public var latches: [QuestLatch]
	/// Tried in order; the first whose conditions hold is current.
	public var steps: [QuestStep]
	/// Where to start (also the "not started" step's target).
	public var summary: String

	public init(id: String, name: String, serverIndex: Int, points: Int, source: QuestStatusSource, summary: String = "", requirements: [String] = [], latches: [QuestLatch] = [], steps: [QuestStep]) {
		self.id = id; self.name = name; self.serverIndex = serverIndex; self.points = points; self.source = source
		self.summary = summary; self.requirements = requirements; self.latches = latches; self.steps = steps
	}
}

/// What the engine may ask about the player. The plugin builds one from the client; a bot builds its own.
public protocol QuestFacts {
	func varp(_ id: Int) -> Int
	func varbit(_ id: Int) -> Int
	/// Carried count of the item (backpack plus worn).
	func carried(_ item: Int) -> Int
	func banked(_ item: Int) -> Int
	func flag(_ name: String) -> Bool
	/// The last quest journal seen for the quest named `quest`, nil when none was seen (or it was another quest's).
	func journal(of quest: String) -> QuestJournal?
}

/// The text lines of an opened quest journal (interface 275), tags removed.
public struct QuestJournal: Equatable {
	public struct Line: Equatable {
		public var text: String
		public var crossedOut: Bool
		public init(_ text: String, crossedOut: Bool) { self.text = text; self.crossedOut = crossedOut }
	}
	public var quest: String
	public var lines: [Line]
	public init(quest: String, lines: [Line]) { self.quest = quest; self.lines = lines }
}
