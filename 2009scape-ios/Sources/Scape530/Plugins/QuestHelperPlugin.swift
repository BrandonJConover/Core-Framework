import Foundation

/// What the plugin worked out for one quest this tick.
public struct QuestEvaluation: Equatable {
	public var questId: String
	public var name: String
	public var status: QuestStatus
	public var step: QuestStep?
	/// 1-based position of the step in the quest's list, and the list's length (for "step 3 of 8").
	public var stepNumber: Int
	public var stepCount: Int
	public var checklist: [QuestEngine.ChecklistEntry]
}

/// One row of the App's Quests panel.
public struct QuestListEntry: Equatable {
	public var id: String
	public var name: String
	public var status: QuestStatus
	public var points: Int
	public var isActive: Bool
	/// The current step's text for a quest in progress.
	public var stepText: String?
	public var requirements: [String]
}

/// RuneLite-Quest-Helper style guidance for the quests in `QuestCatalog`: a panel with the current step and its item
/// checklist, the step's npc / object / tile highlighted in the scene (an edge arrow with the distance when it is off
/// screen), the needed items outlined in the backpack and the target marked on the minimap.
///
/// The logic is data driven: `QuestEngine` picks the step from the quest's `QuestDef` and a `QuestFacts` snapshot of
/// the varps, inventories, remembered flags and last-seen quest journal.
public final class QuestHelperPlugin: ClientPlugin {
	public let id = "questHelper"
	public let name = "Quest Helper"
	public let summary = "Step-by-step guidance for quests: current step, needed items, target highlights and a minimap marker."
	public var enabled = false
	public let config = PluginConfig([
		.choice("panel", "Step panel", ["Top left", "Top right", "Hidden"], "Top left"),
		.toggle("checklist", "Item checklist in the panel", true),
		.toggle("highlightTarget", "Highlight the target", true),
		.toggle("offscreenArrow", "Arrow when the target is off screen", true),
		.toggle("highlightItems", "Outline needed items in the backpack", true),
		.toggle("minimap", "Mark the target on the minimap", true),
	])
	public var subscriptions: PluginSubscription { [.gameTick, .containers, .overlayScene, .overlayHUD] }

	/// The settings-store key of the plugin's own state (chosen quest, remembered flags).
	static let stateKey = "questHelper.state"

	/// The quests the helper knows. Tests and bots may swap in their own.
	public var catalog: [QuestDef] { didSet { catalogById = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) } }
	private var catalogById: [String: QuestDef]

	public init(catalog: [QuestDef] = QuestCatalog.all) {
		self.catalog = catalog
		catalogById = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
	}

	// MARK: state

	private let lock = NSLock()
	private var loaded = false
	private var activeId: String?            // chosen by the player; nil = follow the quest that changed last
	private var autoId: String?
	private var lastChangedId: String?
	private var baselineVarps: [String: Int] = [:]
	private var baselineSet = false
	private var flags: [String: Set<String>] = [:]   // quest id -> flags of the current account
	private var allFlags: [String: [String: [String]]] = [:] // account -> quest id -> flags (persisted)
	private var journals: [String: QuestJournal] = [:]
	private var entriesCache: [QuestListEntry] = []
	private var evalCache: QuestEvaluation?
	private var factsCache = QuestFactsSnapshot()
	/// Names the player's saved flags (skips, remembered progress); the App sets it to the account name at login.
	public var accountKey = "default" {
		didSet { if accountKey != oldValue { lock.lock(); flags = (allFlags[accountKey] ?? [:]).mapValues { Set($0) }; lock.unlock() } }
	}
	/// Set by the tests (and a bot) to run without a client behind the context.
	var testFacts: QuestFactsSnapshot?

	// MARK: App API

	/// The quest the helper follows, nil when none is chosen and none is in progress.
	public var activeQuestId: String? { lock.lock(); defer { lock.unlock() }; return activeId ?? autoId }
	/// True while the helper follows the most recently changed quest on its own.
	public var isAutomatic: Bool { lock.lock(); defer { lock.unlock() }; return activeId == nil }
	public var evaluation: QuestEvaluation? { lock.lock(); defer { lock.unlock() }; return evalCache }
	public var entries: [QuestListEntry] { lock.lock(); defer { lock.unlock() }; return entriesCache }

	/// Picks the quest to follow; nil goes back to following the last quest that changed.
	public func setActive(_ id: String?, _ ctx: PluginContext? = nil) {
		lock.lock()
		activeId = id.flatMap { catalogById[$0] != nil ? $0 : nil }
		lock.unlock()
		persist(ctx?.manager)
		if let ctx { refresh(ctx) }
	}

	/// "I did this": passes over the current step of the followed quest until the quest's status changes.
	public func skipCurrentStep(_ ctx: PluginContext? = nil) {
		lock.lock()
		if let e = evalCache, let step = e.step { flags[e.questId, default: []].insert(QuestEngine.skipFlag(step)) }
		lock.unlock()
		persist(ctx?.manager)
		if let ctx { refresh(ctx) }
	}

	// MARK: events

	public func startUp(_ ctx: PluginContext) { ensureLoaded(ctx.manager) }

	public func onLogin(_ ctx: PluginContext) {
		lock.lock(); baselineSet = false; baselineVarps = [:]; lastChangedId = nil; autoId = nil; journals = [:]; lock.unlock()
	}

	public func onLogout(_ ctx: PluginContext) {
		ctx.setMinimapMarkers([])
		lock.lock(); evalCache = nil; entriesCache = []; lock.unlock()
	}

	public func shutDown(_ ctx: PluginContext) { ctx.setMinimapMarkers([]) }

	public func onGameTick(_ ctx: PluginContext) { refresh(ctx) }
	public func onContainerChanged(_ change: ContainerChange, _ ctx: PluginContext) { refresh(ctx) }

	// MARK: evaluation

	private func makeFacts(_ ctx: PluginContext) -> QuestFactsSnapshot {
		if let t = testFacts { return t }
		var f = QuestFactsSnapshot.from(varps: ctx.state.varps, inventories: ctx.state.inventories)
		// Varbits the catalog reads (decoded through the cache's varbit definitions).
		if let store = ctx.store {
			for d in catalog where d.source.kind == .varbit {
				if let vb = (try? store.varbit(d.source.id)) ?? nil { f.varbits[d.source.id] = Int(vb.value(in: ctx.state.varps[vb.varp] ?? 0)) }
			}
			for id in QuestCatalog.varbits(in: catalog) { if let vb = (try? store.varbit(id)) ?? nil { f.varbits[id] = Int(vb.value(in: ctx.state.varps[vb.varp] ?? 0)) } }
		}
		return f
	}

	func refresh(_ ctx: PluginContext) {
		ensureLoaded(ctx.manager)
		var facts = makeFacts(ctx)
		if testFacts == nil, let j = QuestJournal.parse(texts: ctx.state.interfaces.text) {
			lock.lock(); journals[j.quest] = j; lock.unlock()
		}
		lock.lock()
		facts.journals = journals
		var statuses: [String: QuestStatus] = [:]
		var changedNow: String?
		var flagsChanged = false
		for def in catalog {
			let s = def.source.status(facts)
			statuses[def.id] = s
			let raw = def.source.kind == .varp ? facts.varp(def.source.id) : facts.varbit(def.source.id)
			if baselineSet, let old = baselineVarps[def.id], old != raw { changedNow = def.id }
			baselineVarps[def.id] = raw
			// Flags: latches and skips live while the quest is in progress.
			let old = flags[def.id] ?? []
			let view = FlagOverlay(base: facts, extra: old)
			let new = QuestEngine.updatedFlags(def, view, flags: old)
			if new != old { flags[def.id] = new.isEmpty ? nil : new; flagsChanged = true }
		}
		baselineSet = true
		if let c = changedNow { lastChangedId = c }
		// Auto pick: the last changed quest while it is in progress, else keep the old one, else the first in progress.
		if let l = lastChangedId, statuses[l] == .inProgress { autoId = l }
		else if let a = autoId, statuses[a] == .inProgress { /* keep */ }
		else { autoId = catalog.first { statuses[$0.id] == .inProgress }?.id }
		let effective = activeId ?? autoId
		var entries: [QuestListEntry] = []
		var evalNow: QuestEvaluation?
		for def in catalog {
			let view = FlagOverlay(base: facts, extra: flags[def.id] ?? [])
			let status = statuses[def.id] ?? .notStarted
			var stepText: String?
			if status == .inProgress { stepText = QuestEngine.currentStep(def, view)?.text }
			if status == .notStarted { stepText = def.steps.first { $0.when.contains(.status(.notStarted)) }?.text ?? def.summary }
			entries.append(QuestListEntry(id: def.id, name: def.name, status: status, points: def.points, isActive: def.id == effective, stepText: stepText, requirements: def.requirements))
			if def.id == effective {
				let step = QuestEngine.currentStep(def, view)
				let idx = QuestEngine.currentStepIndex(def, view)
				evalNow = QuestEvaluation(questId: def.id, name: def.name, status: status, step: step, stepNumber: (idx ?? -1) + 1, stepCount: def.steps.count,
				                          checklist: step.map { QuestEngine.checklist($0, view) } ?? [])
			}
		}
		entriesCache = entries
		evalCache = evalNow
		factsCache = facts
		lock.unlock()
		if flagsChanged { persist(ctx.manager) }
		updateMinimap(ctx, evalNow)
	}

	// MARK: persistence

	private struct SavedState: Codable {
		var active: String?
		var flags: [String: [String: [String]]]
	}

	private func ensureLoaded(_ manager: PluginManager?) {
		lock.lock(); defer { lock.unlock() }
		guard !loaded else { return }
		loaded = true
		guard let data = manager?.settingsStore.data(forPlugin: Self.stateKey), let s = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
		activeId = s.active.flatMap { catalogById[$0] != nil ? $0 : nil }
		allFlags = s.flags
		flags = (allFlags[accountKey] ?? [:]).mapValues { Set($0) }
	}

	private func persist(_ manager: PluginManager?) {
		lock.lock()
		allFlags[accountKey] = flags.mapValues { $0.sorted() }
		let state = SavedState(active: activeId, flags: allFlags)
		lock.unlock()
		let empty = state.active == nil && state.flags.values.allSatisfy { $0.isEmpty }
		manager?.settingsStore.setData(empty ? nil : try? JSONEncoder().encode(state), forPlugin: Self.stateKey)
	}

	// MARK: targets

	/// A target in world tiles, with the live npc when it is in the scene.
	struct ResolvedTarget: Equatable {
		var target: QuestTarget
		var world: QuestTile
		var npc: ActorSnapshot?
	}

	/// The targets of a step with live npc positions swapped in.
	func resolve(_ step: QuestStep, npcs: [ActorSnapshot], origin: (x: Int, z: Int)) -> [ResolvedTarget] {
		step.targets.map { t in
			if case .npc(_, let ids, let at) = t {
				let live = npcs.filter { $0.npcId.map(ids.contains) ?? false }
				// The one closest to the known spawn.
				if let n = live.min(by: { dist($0, at, origin) < dist($1, at, origin) }) {
					return ResolvedTarget(target: t, world: QuestTile(origin.x + n.tileX, origin.z + n.tileZ, at.plane), npc: n)
				}
			}
			return ResolvedTarget(target: t, world: t.tile, npc: nil)
		}
	}

	private func dist(_ n: ActorSnapshot, _ t: QuestTile, _ o: (x: Int, z: Int)) -> Int { abs(o.x + n.tileX - t.x) + abs(o.z + n.tileZ - t.z) }

	private func updateMinimap(_ ctx: PluginContext, _ e: QuestEvaluation?) {
		guard config.bool("minimap"), let step = e?.step else { ctx.setMinimapMarkers([]); return }
		let plane = ctx.plane
		ctx.setMinimapMarkers(step.targets.map(\.tile).filter { $0.plane == plane }.map { ($0.x, $0.z) })
	}

	// MARK: overlays

	static let targetColour: UInt32 = 0x00E5FF
	static let panelBack: UInt32 = 0x000000

	public func drawOverlay(_ layer: OverlayLayer, _ canvas: OverlayCanvas, into r: inout Raster) {
		guard let e = evaluation, e.status == .inProgress || e.status == .notStarted else { return }
		switch layer {
		case .scene: drawTargets(e, canvas, &r)
		case .hud:
			drawPanel(e, canvas, &r)
			if config.bool("highlightItems") { drawItemOutlines(e, canvas, &r) }
		}
	}

	private func drawTargets(_ e: QuestEvaluation, _ canvas: OverlayCanvas, _ r: inout Raster) {
		guard canvas.canProject, let step = e.step, config.bool("highlightTarget") || config.bool("offscreenArrow"), let me = canvas.ctx.selfActor else { return }
		let ctx = canvas.ctx
		let origin = ctx.origin
		let targets = resolve(step, npcs: canvas.npcs(), origin: origin)
		let blink = canvas.loop % 40 < 28
		var nearest: (ResolvedTarget, Int)?
		var anyOnScreen = false
		let meWorld = QuestTile(origin.x + me.tileX, origin.z + me.tileZ, ctx.plane)
		for t in targets {
			let d = max(abs(t.world.x - meWorld.x), abs(t.world.z - meWorld.z))
			if nearest == nil || d < nearest!.1 { nearest = (t, d) }
			let sx = t.world.x - origin.x, sz = t.world.z - origin.z
			guard t.world.plane == ctx.plane, sx >= 0, sx < 104, sz >= 0, sz < 104 else { continue }
			var anchor: ScreenPoint?
			if let n = t.npc {
				anchor = canvas.project(xFine: n.fineX, zFine: n.fineZ, height: 220)
				if config.bool("highlightTarget"), let c = canvas.footprintCorners(xFine: n.fineX, zFine: n.fineZ, size: n.size) {
					r.fillPolygon(c, Self.targetColour, opacity: 70)
					r.strokePolygon(c, Self.targetColour)
				}
			} else {
				anchor = canvas.project(xFine: sx * 128 + 64, zFine: sz * 128 + 64, height: 120)
				if config.bool("highlightTarget") {
					if case .loc = t.target { canvas.fillTile(x: sx, z: sz, color: Self.targetColour, opacity: 70, into: &r); canvas.outlineTile(x: sx, z: sz, color: Self.targetColour, into: &r) }
					else if case .tile(_, _, let radius) = t.target, radius > 0 {
						canvas.outlineTile(x: max(sx - radius, 0), z: max(sz - radius, 0), size: min(radius * 2 + 1, 103), color: Self.targetColour, into: &r)
						canvas.fillTile(x: sx, z: sz, color: Self.targetColour, opacity: 60, into: &r)
					} else { canvas.fillTile(x: sx, z: sz, color: Self.targetColour, opacity: 70, into: &r); canvas.outlineTile(x: sx, z: sz, color: Self.targetColour, into: &r) }
				}
			}
			if QuestMarkerMath.onScreen(anchor, viewport: canvas.viewport) { anyOnScreen = true }
			if config.bool("highlightTarget"), blink, let a = anchor {
				// A bobbing arrow above the target, like rt4's tile hint arrows.
				let bob = (canvas.loop % 40) < 20 ? 0 : 3
				r.fillPolygon([ScreenPoint(x: a.x, y: a.y - 6 + bob), ScreenPoint(x: a.x - 7, y: a.y - 20 + bob), ScreenPoint(x: a.x + 7, y: a.y - 20 + bob)], Self.targetColour)
				canvas.drawText(t.target.name, x: a.x, y: a.y - 24 + bob, color: Self.targetColour, into: &r)
			}
		}
		// Off screen: the arrow on the viewport edge.
		guard config.bool("offscreenArrow"), !anyOnScreen, let (t, _) = nearest else { return }
		let dx = t.world.x - meWorld.x, dz = t.world.z - meWorld.z
		guard let m = QuestMarkerMath.edgeMarker(dx: dx, dz: dz, yaw: canvas.cameraYaw, viewport: canvas.viewport) else { return }
		let head = QuestMarkerMath.arrowHead(x: m.x, y: m.y, angle: m.angle)
		r.fillPolygon(head, Self.targetColour)
		r.strokePolygon(head, 0x000000)
		var label = "\(t.target.name) \(m.distance)"
		if t.world.plane != ctx.plane { label += t.world.plane > ctx.plane ? " (up)" : " (down)" }
		let w = canvas.textWidth(label)
		let tx = min(max(m.x, canvas.viewport.x + w / 2 + 2), canvas.viewport.x + canvas.viewport.w - w / 2 - 2)
		canvas.drawText(label, x: tx, y: m.y + (m.y < canvas.viewport.y + canvas.viewport.h / 2 ? 24 : -14), color: Self.targetColour, into: &r)
	}

	/// Lines of the panel: (text, colour, bold).
	func panelLines(_ e: QuestEvaluation, width: Int, measure: (String) -> Int, includeChecklist: Bool) -> [(String, UInt32, Bool)] {
		var out: [(String, UInt32, Bool)] = []
		var title = e.name
		if e.status == .inProgress, e.stepNumber > 0 { title += "  \(e.stepNumber)/\(e.stepCount)" }
		out.append((title, 0xFFD060, true))
		let text = e.step?.text ?? (e.status == .notStarted ? "Not started." : "No step matches your progress; open the quest journal to refresh.")
		for l in QuestMarkerMath.wrap(text, width: width, measure: measure) { out.append((l, 0xFFFFFF, false)) }
		if includeChecklist {
			for c in e.checklist {
				let mark = c.done ? "[x] " : (c.state == .banked ? "[b] " : "[ ] ")
				var line = mark + c.item.name
				if c.item.count > 1 { line += " (\(c.carried)/\(c.item.count))" }
				if c.state == .banked { line += " in bank" }
				out.append((line, c.done ? 0x60FF60 : (c.item.needed ? 0xFF7070 : 0xB0B0B0), false))
			}
		}
		return out
	}

	private func drawPanel(_ e: QuestEvaluation, _ canvas: OverlayCanvas, _ r: inout Raster) {
		let mode = config.string("panel")
		guard mode != "Hidden" else { return }
		let width = 190
		let lines = panelLines(e, width: width - 8, measure: { canvas.textWidth($0) }, includeChecklist: config.bool("checklist"))
		let lineH = 13
		let h = lines.count * lineH + 8
		let v = canvas.viewport
		let x = mode == "Top right" ? v.x + v.w - width - 6 : v.x + 6
		let y = v.y + 6
		r.fillRect(x, y, width, h, Self.panelBack, opacity: 150)
		r.fillRect(x, y, width, 1, 0xFFD060, opacity: 180)
		var ty = y + 12
		for (text, colour, bold) in lines {
			canvas.drawText(text, x: x + 4, y: ty, color: colour, font: bold ? .bold : .small, centered: false, into: &r)
			ty += lineH
		}
	}

	private func drawItemOutlines(_ e: QuestEvaluation, _ canvas: OverlayCanvas, _ r: inout Raster) {
		guard let step = e.step else { return }
		let wanted = Set(step.items.map(\.id))
		guard !wanted.isEmpty else { return }
		let pulse = canvas.loop % 40 < 28
		for s in canvas.ctx.backpackSlots() where wanted.contains(s.itemId) {
			let col: UInt32 = pulse ? 0xFFE040 : 0xFFB000
			r.fillRect(s.x, s.y, 32, 1, col); r.fillRect(s.x, s.y + 31, 32, 1, col)
			r.fillRect(s.x, s.y, 1, 32, col); r.fillRect(s.x + 31, s.y, 1, 32, col)
			r.fillRect(s.x + 1, s.y + 1, 30, 30, col, opacity: 36)
		}
	}
}

extension PluginContext {
	/// Backpack slots that hold an item, with their top-left raster position (interface 149, the 2009 backpack).
	func backpackSlots() -> [(slot: Int, itemId: Int, x: Int, y: Int)] {
		guard let client else { return [] }
		var out: [(slot: Int, itemId: Int, x: Int, y: Int)] = []
		for d in client.ui.drawn.reversed() where d.component.type == 2 && d.component.id == 149 << 16 {
			let c = d.component
			guard let o = client.ui.origins[c.ref], let items = client.host.game.interfaces.invSlots[c.id] else { continue }
			var slot = 0
			for row in 0..<c.baseHeight {
				for col in 0..<c.baseWidth {
					var sx = o.x + col * (c.invMarginX + 32), sy = o.y + row * (c.invMarginY + 32)
					if slot < 20, slot < c.invSprites.count, let e = c.invSprites[slot] { sx += e.x; sy += e.y }
					if let it = items[slot], it.id >= 0 { out.append((slot, it.id, sx, sy)) }
					slot += 1
				}
			}
			break
		}
		return out
	}

	/// Tells the minimap which world tiles to mark (plugins; the quest helper's target).
	func setMinimapMarkers(_ tiles: [(x: Int, z: Int)]) { client?.world.minimapMarkers = tiles }
}
