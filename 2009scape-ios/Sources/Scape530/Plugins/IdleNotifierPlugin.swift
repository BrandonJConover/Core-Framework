import Foundation

/// Idle detection as a tick-driven state machine, kept apart from the plugin so it can be tested exactly.
///
/// The player becomes *armed* by being active (animating, and with `requireAnimation` false also walking). Once armed,
/// `idleTicks` consecutive ticks with nothing going on make `tick` return true, once; the detector then waits to be
/// armed again. Walking while armed (with `requireAnimation`) resets the countdown without disarming.
public struct IdleDetector: Equatable {
	public var idleTicks: Int
	public var requireAnimation: Bool
	private(set) public var armed = false
	private(set) public var quiet = 0

	public init(idleTicks: Int, requireAnimation: Bool = true) {
		self.idleTicks = idleTicks
		self.requireAnimation = requireAnimation
	}

	public mutating func reset() { armed = false; quiet = 0 }

	/// One game tick. Returns true on the tick the player counts as idle.
	public mutating func tick(animating: Bool, moving: Bool) -> Bool {
		let working = animating || (!requireAnimation && moving)
		if working { armed = true; quiet = 0; return false }
		if moving { quiet = 0; return false }
		guard armed else { return false }
		quiet += 1
		if quiet >= idleTicks {
			armed = false
			quiet = 0
			return true
		}
		return false
	}
}

/// Low hitpoints as a latch: fires once when the hitpoints fall to the threshold, and again only after recovering above it.
public struct LowHitpointsDetector: Equatable {
	private(set) public var below = false
	public init() {}
	public mutating func reset() { below = false }

	public mutating func update(current: Int, base: Int, percent: Int) -> Bool {
		guard percent > 0, base > 0 else { below = false; return false }
		let low = current * 100 <= base * percent
		defer { below = low }
		return low && !below
	}
}

/// Tells the App when the local player stops working or is about to die. The App turns the callback into a
/// notification while the app is in the background and a haptic while it is on screen.
public final class IdleNotifierPlugin: ClientPlugin {
	public let id = "idleNotifier"
	public let name = "Idle Notifier"
	public let summary = "Notifies you when your character stops what it was doing, or hitpoints run low."
	public var enabled = false
	public let config = PluginConfig([
		.number("idleSeconds", "Idle after (seconds)", 4, min: 2, max: 60, help: "Seconds without an animation or movement after working."),
		.toggle("requireAnimation", "Only after skilling or fighting", true, help: "When off, stopping after a walk counts too."),
		.number("lowHpPercent", "Low hitpoints at (%)", 25, min: 0, max: 90, help: "0 turns the low hitpoints alert off."),
		.toggle("idle", "Idle alert", true),
	])
	public var subscriptions: PluginSubscription { [.gameTick, .stats] }

	private var idle = IdleDetector(idleTicks: 7)
	private var hp = LowHitpointsDetector()
	private var lastTile: (x: Int, z: Int, plane: Int)?
	public private(set) var lastIdleAt: Date?

	public init() {}

	public func onLogin(_ ctx: PluginContext) { resetState() }
	public func onLogout(_ ctx: PluginContext) { resetState() }
	public func startUp(_ ctx: PluginContext) { resetState() }

	private func resetState() { idle.reset(); hp.reset(); lastTile = nil }

	/// Game ticks are 0.6 s.
	static func ticks(forSeconds s: Int) -> Int { max(Int((Double(s) / 0.6).rounded(.up)), 1) }

	public func onGameTick(_ ctx: PluginContext) {
		guard config.bool("idle"), let me = ctx.selfActor else { return }
		idle.idleTicks = Self.ticks(forSeconds: config.int("idleSeconds"))
		idle.requireAnimation = config.bool("requireAnimation")
		let tile = (x: me.tileX, z: me.tileZ, plane: ctx.plane)
		let moving = lastTile.map { $0 != tile } ?? false
		lastTile = tile
		if idle.tick(animating: me.animation != -1, moving: moving) {
			lastIdleAt = Date()
			ctx.notify(PluginNotification(pluginId: id, kind: .idle, title: "Idle", body: "Your character stopped."))
		}
	}

	public func onStatChanged(_ change: StatChange, _ ctx: PluginContext) {
		guard change.skill == Skills.hitpoints, let base = ctx.baseLevel(Skills.hitpoints) else { return }
		if hp.update(current: change.newLevel, base: base, percent: config.int("lowHpPercent")) {
			ctx.notify(PluginNotification(pluginId: id, kind: .lowHitpoints, title: "Low hitpoints", body: "Hitpoints are at \(change.newLevel) of \(base)."))
		}
	}
}
