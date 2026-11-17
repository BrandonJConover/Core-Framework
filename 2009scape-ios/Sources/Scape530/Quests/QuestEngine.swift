import Foundation

/// Evaluates quest definitions against a `QuestFacts`. Pure: no client, no drawing.
public enum QuestEngine {
	public static func holds(_ c: QuestCondition, in def: QuestDef, _ f: QuestFacts) -> Bool {
		switch c {
		case .status(let s): return def.source.status(f) == s
		case .varp(let id, let r): return r.contains(f.varp(id))
		case .varbit(let id, let r): return r.contains(f.varbit(id))
		case .has(let item, let count): return f.carried(item) >= count
		case .hasAny(let items): return items.contains { f.carried($0) > 0 }
		case .banked(let item): return f.banked(item) > 0
		case .flag(let name): return f.flag(name)
		case .journal(let text): return journalLines(def, f, crossed: nil, text)
		case .journalDone(let text): return journalLines(def, f, crossed: true, text)
		case .journalActive(let text): return journalLines(def, f, crossed: false, text)
		case .not(let inner): return !holds(inner, in: def, f)
		case .any(let list): return list.contains { holds($0, in: def, f) }
		case .all(let list): return list.allSatisfy { holds($0, in: def, f) }
		}
	}

	private static func journalLines(_ def: QuestDef, _ f: QuestFacts, crossed: Bool?, _ text: String) -> Bool {
		guard let j = f.journal(of: def.name) else { return false }
		let needle = text.lowercased()
		return j.lines.contains { l in (crossed == nil || l.crossedOut == crossed) && l.text.lowercased().contains(needle) }
	}

	public static func status(_ def: QuestDef, _ f: QuestFacts) -> QuestStatus { def.source.status(f) }

	/// The flag that makes `currentStep` pass over a step ("I did this" in the App).
	public static func skipFlag(_ step: QuestStep) -> String { "skip:" + step.id }

	/// The current step: the first one whose conditions all hold and that was not skipped. A finished quest has none.
	public static func currentStep(_ def: QuestDef, _ f: QuestFacts) -> QuestStep? {
		if status(def, f) == .complete { return nil }
		return def.steps.first { step in !f.flag(skipFlag(step)) && step.when.allSatisfy { holds($0, in: def, f) } }
	}

	/// Index of `currentStep` in `def.steps`.
	public static func currentStepIndex(_ def: QuestDef, _ f: QuestFacts) -> Int? {
		currentStep(def, f).flatMap { s in def.steps.firstIndex { $0.id == s.id } }
	}

	/// The flags the latches set now (adding to `flags`), or an empty set once the quest is not in progress.
	public static func updatedFlags(_ def: QuestDef, _ f: QuestFacts, flags: Set<String>) -> Set<String> {
		guard status(def, f) == .inProgress else { return [] }
		var out = flags
		// A latch may depend on a flag another latch just set, so settle in a few passes.
		for _ in 0..<3 {
			let view = FlagOverlay(base: f, extra: out)
			var changed = false
			for l in def.latches where !out.contains(l.flag) && l.when.allSatisfy({ holds($0, in: def, view) }) { out.insert(l.flag); changed = true }
			if !changed { break }
		}
		return out
	}

	public struct ChecklistEntry: Equatable {
		public enum State: Equatable { case have, banked, missing }
		public var item: QuestItem
		public var state: State
		/// Carried count, capped for display at the wanted count.
		public var carried: Int
		public var done: Bool { state == .have }
	}

	public static func checklist(_ step: QuestStep, _ f: QuestFacts) -> [ChecklistEntry] {
		step.items.map { it in
			let have = f.carried(it.id)
			if have >= it.count { return ChecklistEntry(item: it, state: .have, carried: it.count) }
			return ChecklistEntry(item: it, state: f.banked(it.id) > 0 ? .banked : .missing, carried: have)
		}
	}

	/// True when every needed item of the step is carried.
	public static func checklistComplete(_ step: QuestStep, _ f: QuestFacts) -> Bool {
		checklist(step, f).allSatisfy { $0.done || !$0.item.needed }
	}

	public static func def(named name: String) -> QuestDef? {
		QuestCatalog.all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
	}

	/// The quest whose list varp (or varbit) is `id`, for "the most recently changed quest" tracking.
	public static func defs(usingVarp id: Int, varbitVarps: (Int) -> Int?) -> [QuestDef] {
		QuestCatalog.all.filter { d in
			switch d.source.kind {
			case .varp: return d.source.id == id
			case .varbit: return varbitVarps(d.source.id) == id
			}
		}
	}
}

/// Facts plus extra flags (used while latches settle).
struct FlagOverlay: QuestFacts {
	let base: QuestFacts
	let extra: Set<String>
	func varp(_ id: Int) -> Int { base.varp(id) }
	func varbit(_ id: Int) -> Int { base.varbit(id) }
	func carried(_ item: Int) -> Int { base.carried(item) }
	func banked(_ item: Int) -> Int { base.banked(item) }
	func flag(_ name: String) -> Bool { extra.contains(name) || base.flag(name) }
	func journal(of quest: String) -> QuestJournal? { base.journal(of: quest) }
}

public extension QuestJournal {
	/// Builds a journal from the interface text the client keeps (`InterfaceState.text`, key = interface << 16 | child).
	/// Child 2 is the title; the lines are the other non-empty children in order. nil when interface 275 has no title.
	static func parse(texts: [Int: String]) -> QuestJournal? {
		let iface = 275
		var title = ""
		var lines: [Line] = []
		for (key, raw) in texts.sorted(by: { $0.key < $1.key }) where key >> 16 == iface {
			let child = key & 0xFFFF
			let crossed = raw.range(of: "<str>", options: .caseInsensitive) != nil
			let text = strip(raw)
			if child == 2 { title = text; continue }
			if text.isEmpty || child < 3 { continue }
			lines.append(Line(text, crossedOut: crossed))
		}
		return title.isEmpty ? nil : QuestJournal(quest: title, lines: lines)
	}

	/// Removes `<...>` tags and collapses spaces.
	static func strip(_ s: String) -> String {
		var out = ""
		var inTag = false
		for ch in s {
			if ch == "<" { inTag = true } else if ch == ">" && inTag { inTag = false } else if !inTag { out.append(ch) }
		}
		return out.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
	}
}
