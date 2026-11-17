import Foundation

/// Lists skills whose current level differs from the level their experience gives (boosts and drains), with the time
/// until the next point wears off or comes back.
public final class BoostsPlugin: ClientPlugin {
	public let id = "boosts"
	public let name = "Boosts & Timers"
	public let summary = "Small overlay of boosted and drained skills with a countdown to the next change."
	public var enabled = false
	public let config = PluginConfig([
		.toggle("timers", "Show countdown", true, help: "Boosts fade one level a minute and drains return the same way."),
	])
	public var subscriptions: PluginSubscription { [.stats, .overlayHUD] }

	/// Client cycle of each skill's last level change.
	private var changedAt: [Int: Int] = [:]

	public init() {}

	public func onLogin(_ ctx: PluginContext) { changedAt = [:] }
	public func onLogout(_ ctx: PluginContext) { changedAt = [:] }

	public func onStatChanged(_ c: StatChange, _ ctx: PluginContext) {
		if c.newLevel != c.oldLevel { changedAt[c.skill] = ctx.loop }
	}

	/// 100 game ticks per point, in client cycles.
	static let cyclesPerPoint = 100 * 30

	/// Seconds until the next point changes, counted from the last change.
	public static func secondsToNext(changedAt: Int, loop: Int) -> Int {
		let into = max(loop - changedAt, 0) % cyclesPerPoint
		return (cyclesPerPoint - into) * 20 / 1000
	}

	public struct Line: Equatable {
		public var skill: Int
		public var current: Int
		public var base: Int
		public var seconds: Int?
		public var delta: Int { current - base }
	}

	public func lines(_ ctx: PluginContext) -> [Line] {
		let timers = config.bool("timers")
		return ctx.state.stats.keys.sorted().compactMap { skill in
			guard let cur = ctx.currentLevel(skill), let base = ctx.baseLevel(skill), cur != base else { return nil }
			let secs = timers ? changedAt[skill].map { Self.secondsToNext(changedAt: $0, loop: ctx.loop) } : nil
			return Line(skill: skill, current: cur, base: base, seconds: secs)
		}
	}

	public func drawOverlay(_ layer: OverlayLayer, _ canvas: OverlayCanvas, into r: inout Raster) {
		guard layer == .hud else { return }
		var y = canvas.viewport.y + 150
		let x = canvas.viewport.x + 6
		for l in lines(canvas.ctx) {
			var text = "\(Skills.name(l.skill).prefix(3)) \(l.current)/\(l.base) (\(l.delta > 0 ? "+" : "")\(l.delta))"
			if let s = l.seconds { text += String(format: " %d:%02d", s / 60, s % 60) }
			canvas.drawText(text, x: x, y: y, color: l.delta > 0 ? 0x40FF40 : 0xFF6060, centered: false, into: &r)
			y += 13
		}
	}
}
