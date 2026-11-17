import Foundation

/// A toggleable client feature. Plugins only react: events arrive through the `on...` methods, menus pass
/// through `modifyMenu`, and overlays draw into the frame. Everything has a default no-op, so a plugin
/// implements only what it needs and lists those hooks in `subscriptions` (the manager skips the work
/// behind the rest).
///
/// All methods run on the thread that renders frames. Settings are edited from the main thread through
/// `config` (thread-safe).
public protocol ClientPlugin: AnyObject {
	/// Stable key for persistence ("groundItems").
	var id: String { get }
	var name: String { get }
	var summary: String { get }
	var defaultEnabled: Bool { get }
	/// Set by the manager.
	var enabled: Bool { get set }
	var config: PluginConfig { get }
	var subscriptions: PluginSubscription { get }

	func startUp(_ ctx: PluginContext)
	func shutDown(_ ctx: PluginContext)

	func onLogin(_ ctx: PluginContext)
	func onLogout(_ ctx: PluginContext)
	/// Once per server game tick (the player-info packet).
	func onGameTick(_ ctx: PluginContext)
	/// Once per 20 ms client cycle (rt4 `client.loop`).
	func onClientCycle(_ ctx: PluginContext)

	func onStatChanged(_ change: StatChange, _ ctx: PluginContext)
	func onContainerChanged(_ change: ContainerChange, _ ctx: PluginContext)
	func onChatMessage(_ line: ChatLine, _ ctx: PluginContext)
	func onActorSpawned(_ actor: ActorSnapshot, _ ctx: PluginContext)
	func onActorDespawned(_ actor: ActorSnapshot, _ ctx: PluginContext)
	func onGroundItemSpawned(_ item: GroundItemSnapshot, _ ctx: PluginContext)
	func onGroundItemDespawned(_ item: GroundItemSnapshot, _ ctx: PluginContext)
	func onAnimationChanged(_ change: AnimationChange, _ ctx: PluginContext)
	func onHitsplat(_ hit: HitsplatEvent, _ ctx: PluginContext)

	/// Reorders, removes, swaps or adds entries after the menu was built. The last entry is the default (tap) action;
	/// entry 0 (Cancel) must stay.
	func modifyMenu(_ menu: inout Menu, source: MenuSource, _ ctx: PluginContext)

	/// Draws into the game raster. `canvas` knows the 3D viewport and projects world positions to the screen.
	func drawOverlay(_ layer: OverlayLayer, _ canvas: OverlayCanvas, into r: inout Raster)
}

public extension ClientPlugin {
	var summary: String { "" }
	var defaultEnabled: Bool { false }
	var subscriptions: PluginSubscription { [] }

	func startUp(_ ctx: PluginContext) {}
	func shutDown(_ ctx: PluginContext) {}
	func onLogin(_ ctx: PluginContext) {}
	func onLogout(_ ctx: PluginContext) {}
	func onGameTick(_ ctx: PluginContext) {}
	func onClientCycle(_ ctx: PluginContext) {}
	func onStatChanged(_ change: StatChange, _ ctx: PluginContext) {}
	func onContainerChanged(_ change: ContainerChange, _ ctx: PluginContext) {}
	func onChatMessage(_ line: ChatLine, _ ctx: PluginContext) {}
	func onActorSpawned(_ actor: ActorSnapshot, _ ctx: PluginContext) {}
	func onActorDespawned(_ actor: ActorSnapshot, _ ctx: PluginContext) {}
	func onGroundItemSpawned(_ item: GroundItemSnapshot, _ ctx: PluginContext) {}
	func onGroundItemDespawned(_ item: GroundItemSnapshot, _ ctx: PluginContext) {}
	func onAnimationChanged(_ change: AnimationChange, _ ctx: PluginContext) {}
	func onHitsplat(_ hit: HitsplatEvent, _ ctx: PluginContext) {}
	func modifyMenu(_ menu: inout Menu, source: MenuSource, _ ctx: PluginContext) {}
	func drawOverlay(_ layer: OverlayLayer, _ canvas: OverlayCanvas, into r: inout Raster) {}
}

/// Item facts a plugin usually needs, cached per item id.
public struct ItemInfo: Equatable {
	public var id: Int
	public var name: String
	/// Shop value (rt4 `ObjType.cost`), the only price the cache has.
	public var cost: Int
	public var stackable: Bool
	public var members: Bool
}

/// What a plugin may read of the running client, plus the few things it may ask for (a notification).
public final class PluginContext {
	weak var client: GameClient?
	weak var manager: PluginManager?
	private var items: [Int: ItemInfo?] = [:]

	init(manager: PluginManager) { self.manager = manager }

	/// A context with no client behind it (unit tests of plugin logic).
	public static func detached(manager: PluginManager) -> PluginContext { PluginContext(manager: manager) }

	/// rt4 `client.loop`: client cycles since login (20 ms each).
	public var loop: Int { client?.world.ctx.loop ?? manager?.testLoop ?? 0 }
	/// Server ticks seen since login.
	public var ticks: Int { client?.state.ticks ?? manager?.testTicks ?? 0 }
	public var state: GameState { client?.state ?? GameState() }
	public var store: ConfigStore? { client?.store }

	/// Wire experience divided by this is whole xp (see `PluginManager.xpDivisor`).
	public var xpDivisor: Int { manager?.xpDivisor ?? 1 }

	/// Current (boosted or drained) level of a skill, nil before the server sent it.
	public func currentLevel(_ skill: Int) -> Int? { state.stats[skill]?.level }

	/// Level the skill's experience corresponds to.
	public func baseLevel(_ skill: Int) -> Int? {
		guard let s = state.stats[skill] else { return nil }
		return XpTable.level(forXp: Int(s.xp) / xpDivisor, maxLevel: skill == 18 || skill == 24 ? 120 : 99)
	}

	public func item(_ id: Int) -> ItemInfo? {
		if let cached = items[id] { return cached }
		var info: ItemInfo?
		if let t = (try? client?.store.objResolved(id)) ?? nil {
			info = ItemInfo(id: id, name: t.name, cost: Int(t.cost), stackable: t.stackable, members: t.members)
		}
		items[id] = info
		return info
	}

	/// Registers an item for tests without a cache.
	func testSetItem(_ i: ItemInfo) { items[i.id] = i }

	/// The local player, if it is in the scene.
	public var selfActor: ActorSnapshot? { client.flatMap { manager?.selfSnapshot($0) } }
	/// The scene's origin in world tiles (add to a scene tile for the world tile).
	public var origin: (x: Int, z: Int) { client?.world.origin ?? (0, 0) }
	public var plane: Int { client?.world.plane ?? 0 }
	/// Ground items of the current plane.
	public var groundStacks: [Int: [GroundObj]] { client?.world.objStacks ?? [:] }
	public var viewport: (x: Int, y: Int, w: Int, h: Int)? { client?.viewport }
	/// The tile of the minimap flag (where the player is walking to), if any.
	public var destinationTile: (x: Int, z: Int)? { client?.world.destinationFlag }

	public func notify(_ n: PluginNotification) { manager?.deliver(n) }
}
