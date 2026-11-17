import Foundation

/// Owns the plugins of one `GameClient`: persistence, enabling, event dispatch, menu and overlay passes.
///
/// The client calls four small hooks (`attach`, `update(cycles:)`, `modifyMenu`, `drawOverlays`) plus
/// `loggedIn` / `loggedOut`. With no plugin enabled each of them returns at its first line.
public final class PluginManager {
	public private(set) var plugins: [ClientPlugin] = []
	/// Receives the notifications plugins ask for. Called on the frame thread; the App hops to the main thread.
	public var onNotification: ((PluginNotification) -> Void)?
	/// Where settings persist. Set through `useSettingsStore` so saved settings load.
	public private(set) var settingsStore: PluginSettingsStore = InMemoryPluginSettingsStore()

	/// Wire experience / this = whole xp. rt4 stores xp as is; some servers send tenths. Detected from the first
	/// stats (a level that only matches one reading), 1 until then.
	public internal(set) var xpDivisor = 1
	private var xpDivisorKnown = false

	weak var client: GameClient?
	private(set) lazy var context = PluginContext(manager: self)
	private let lock = NSLock()
	private var active: [ClientPlugin] = []
	private var activeSubs: PluginSubscription = []
	private var differ = PluginDiffer()
	/// Standing in for the client in tests.
	var testLoop: Int?
	var testTicks: Int?

	public init(registerBuiltIns: Bool = true) {
		if registerBuiltIns { BuiltInPlugins.all().forEach { register($0) } }
	}

	// MARK: registration and settings

	public func register(_ plugin: ClientPlugin) {
		lock.lock()
		guard !plugins.contains(where: { $0.id == plugin.id }) else { lock.unlock(); return }
		plugins.append(plugin)
		lock.unlock()
		plugin.config.onChange = { [weak self, weak plugin] in
			guard let self, let plugin else { return }
			self.persist(plugin)
		}
		load(plugin)
	}

	/// Switches persistence to `store` and reloads every plugin's saved state from it.
	public func useSettingsStore(_ store: PluginSettingsStore) {
		settingsStore = store
		for p in plugins { load(p) }
	}

	private func load(_ plugin: ClientPlugin) {
		var enabled = plugin.defaultEnabled
		plugin.config.load([:])
		if let data = settingsStore.data(forPlugin: plugin.id), let s = try? JSONDecoder().decode(PluginStoredState.self, from: data) {
			enabled = s.enabled ?? enabled
			plugin.config.load(s.values)
		}
		apply(enabled: enabled, to: plugin)
	}

	private func persist(_ plugin: ClientPlugin) {
		rebuildActive() // a setting can change what the plugin subscribes to
		let state = PluginStoredState(enabled: plugin.enabled == plugin.defaultEnabled ? nil : plugin.enabled, values: plugin.config.overrides)
		if state.enabled == nil && state.values.isEmpty {
			settingsStore.setData(nil, forPlugin: plugin.id)
		} else {
			settingsStore.setData(try? JSONEncoder().encode(state), forPlugin: plugin.id)
		}
	}

	public func plugin(id: String) -> ClientPlugin? { plugins.first { $0.id == id } }
	public func plugin<T: ClientPlugin>(ofType: T.Type) -> T? { plugins.lazy.compactMap { $0 as? T }.first }

	public func isEnabled(_ id: String) -> Bool { plugin(id: id)?.enabled ?? false }

	public func setEnabled(_ enabled: Bool, id: String) {
		guard let p = plugin(id: id) else { return }
		apply(enabled: enabled, to: p)
		persist(p)
	}

	private func apply(enabled: Bool, to p: ClientPlugin) {
		let was = p.enabled
		p.enabled = enabled
		rebuildActive()
		guard client != nil, was != enabled else { return }
		if enabled { p.startUp(context) } else { p.shutDown(context) }
	}

	private func rebuildActive() {
		lock.lock()
		active = plugins.filter(\.enabled)
		activeSubs = active.reduce([]) { $0.union($1.subscriptions) }
		lock.unlock()
	}

	private func snapshotActive() -> (plugins: [ClientPlugin], subs: PluginSubscription) {
		lock.lock(); defer { lock.unlock() }
		return (active, activeSubs)
	}

	// MARK: client hooks

	func attach(_ client: GameClient) {
		self.client = client
		context.client = client
		for p in snapshotActive().plugins { p.startUp(context) }
	}

	func loggedIn() {
		differ.reset()
		for p in snapshotActive().plugins { p.onLogin(context) }
	}

	func loggedOut() {
		for p in snapshotActive().plugins { p.onLogout(context) }
		differ.reset()
	}

	/// Once per frame while in game, after the client cycles ran.
	func update(cycles: Int) {
		let (list, subs) = snapshotActive()
		guard !list.isEmpty, let client else { return }
		if subs.contains(.clientCycle) {
			for _ in 0..<max(cycles, 0) { for p in list where p.subscriptions.contains(.clientCycle) { p.onClientCycle(context) } }
		}
		let wants = subs.intersection(.diffed)
		guard !wants.isEmpty else { return }
		if !xpDivisorKnown { detectXpDivisor(client.state.stats) }
		let events = differ.diff(snapshot(of: client, wants: wants), wants: wants, xpDivisor: xpDivisor)
		dispatch(events, to: list)
	}

	/// Runs the events through the plugins that subscribed to each kind.
	func dispatch(_ events: [PluginEvent], to list: [ClientPlugin]? = nil) {
		let list = list ?? snapshotActive().plugins
		let ctx = context
		for e in events {
			switch e {
			case .gameTick: for p in list where p.subscriptions.contains(.gameTick) { p.onGameTick(ctx) }
			case .statChanged(let c): for p in list where p.subscriptions.contains(.stats) { p.onStatChanged(c, ctx) }
			case .containerChanged(let c): for p in list where p.subscriptions.contains(.containers) { p.onContainerChanged(c, ctx) }
			case .chatMessage(let l): for p in list where p.subscriptions.contains(.chat) { p.onChatMessage(l, ctx) }
			case .actorSpawned(let a): for p in list where p.subscriptions.contains(.actors) { p.onActorSpawned(a, ctx) }
			case .actorDespawned(let a): for p in list where p.subscriptions.contains(.actors) { p.onActorDespawned(a, ctx) }
			case .groundItemSpawned(let g): for p in list where p.subscriptions.contains(.groundItems) { p.onGroundItemSpawned(g, ctx) }
			case .groundItemDespawned(let g): for p in list where p.subscriptions.contains(.groundItems) { p.onGroundItemDespawned(g, ctx) }
			case .animationChanged(let c): for p in list where p.subscriptions.contains(.animations) { p.onAnimationChanged(c, ctx) }
			case .hitsplat(let h): for p in list where p.subscriptions.contains(.hitsplats) { p.onHitsplat(h, ctx) }
			}
		}
	}

	/// After the menu builder: lets plugins reorder, swap, remove or add entries.
	func modifyMenu(_ menu: inout Menu, source: MenuSource) {
		let (list, subs) = snapshotActive()
		guard subs.contains(.menu) else { return }
		for p in list where p.subscriptions.contains(.menu) { p.modifyMenu(&menu, source: source, context) }
	}

	/// Draws the overlays of one layer. `rect` is the 3D viewport the overlays are clipped to.
	func drawOverlays(_ layer: OverlayLayer, into r: inout Raster) {
		let (list, subs) = snapshotActive()
		let wanted: PluginSubscription = layer == .scene ? .overlayScene : .overlayHUD
		guard subs.contains(wanted), let client else { return }
		let rect = client.overlayRect
		let canvas = OverlayCanvas(world: client.world, viewport: rect, ctx: context)
		let saved = (r.clipLeft, r.clipTop, r.clipRight, r.clipBottom)
		r.setClip(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h)
		for p in list where p.subscriptions.contains(wanted) { p.drawOverlay(layer, canvas, into: &r) }
		r.setClip(saved.0, saved.1, saved.2, saved.3)
	}

	func deliver(_ n: PluginNotification) { onNotification?(n) }

	// MARK: snapshots

	func selfSnapshot(_ client: GameClient) -> ActorSnapshot? {
		let w = client.world
		return w.ctx.players[w.selfIndex].map { $0.pluginSnapshot(isSelf: true, hits: false) }
	}

	private func snapshot(of client: GameClient, wants: PluginSubscription) -> WorldSnapshot {
		var s = WorldSnapshot()
		let state = client.state
		let world = client.world
		s.ticks = state.ticks
		s.plane = world.plane
		s.buildStamp = world.buildCount
		if wants.contains(.stats) { for (k, v) in state.stats { s.stats[k] = .init(level: v.level, xp: Int(v.xp)) } }
		if wants.contains(.containers) { s.inventories = state.inventories }
		if wants.contains(.chat) { s.chatSize = state.chatLog.size; s.chatLines = state.chatLog.lines }
		if wants.contains(.groundItems) { s.ground = world.objStacks }
		if !wants.intersection([.actors, .animations, .hitsplats]).isEmpty {
			let hits = wants.contains(.hitsplats)
			for (i, a) in world.ctx.players { s.actors[ActorKey(isNpc: false, index: i)] = a.pluginSnapshot(isSelf: i == world.selfIndex, hits: hits) }
			for (i, a) in world.ctx.npcs { s.actors[ActorKey(isNpc: true, index: i)] = a.pluginSnapshot(isSelf: false, hits: hits) }
		}
		return s
	}

	/// Votes with every skill whose level matches exactly one reading of its xp (wire value or a tenth of it).
	func detectXpDivisor(_ stats: [Int: (level: Int, xp: Int32)]) {
		var ones = 0, tens = 0
		for (skill, s) in stats where s.xp > 0 {
			let cap = skill == 18 || skill == 24 ? 120 : 99
			let a = XpTable.level(forXp: Int(s.xp), maxLevel: cap), b = XpTable.level(forXp: Int(s.xp) / 10, maxLevel: cap)
			if a == b { continue }
			if s.level == a { ones += 1 } else if s.level == b { tens += 1 }
		}
		guard ones + tens >= 3 else { return }
		xpDivisor = tens > ones ? 10 : 1
		xpDivisorKnown = true
	}
}

extension GameClient {
	/// The rectangle plugin overlays draw in: the 3D viewport, or the whole raster before the interface reported one.
	var overlayRect: (x: Int, y: Int, w: Int, h: Int) {
		viewport.flatMap { $0.x + $0.w <= lastSize.w && $0.y + $0.h <= lastSize.h ? $0 : nil } ?? (x: 0, y: 0, w: lastSize.w, h: lastSize.h)
	}
}

extension PathingActor {
	/// What plugins see of an actor. Hit splat data only when `hits` (it is copied per actor per frame).
	func pluginSnapshot(isSelf: Bool, hits: Bool) -> ActorSnapshot {
		let isNpc = kind == .npc
		let name = isNpc ? (npcType?.name ?? "") : (appearance.map { MenuBuilder.displayName($0) } ?? "")
		return ActorSnapshot(
			key: ActorKey(isNpc: isNpc, index: index), isSelf: isSelf, name: name, npcId: isNpc ? npcType?.id : nil,
			combatLevel: isNpc ? (npcType?.combatLevel ?? 0) : (appearance?.combatLevel ?? 0),
			tileX: queueX[0], tileZ: queueZ[0], size: size, animation: seqId,
			hitUntil: hits ? hitVisibleUntil : [], hitDamage: hits ? hitDamages : [], hitType: hits ? hitTypes : [],
			fineX: xFine, fineZ: zFine)
	}
}
