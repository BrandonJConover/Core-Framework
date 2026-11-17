import Foundation

/// The "+N xp" drops that float up the viewport when experience arrives.
public final class XpDropsPlugin: ClientPlugin {
	public let id = "xpDrops"
	public let name = "XP Drops"
	public let summary = "Floating +N xp with the skill icon whenever you gain experience."
	public var enabled = false
	public let config = PluginConfig([
		.toggle("icons", "Skill icons", true, help: "Falls back to the skill name when the cache has no icon sheet."),
		.number("minXp", "Hide drops below (xp)", 0, min: 0, max: 1000),
		.number("seconds", "Seconds on screen", 3, min: 1, max: 8),
	])
	public var subscriptions: PluginSubscription { [.stats, .overlayHUD] }

	public struct Drop: Equatable {
		public var skill: Int
		public var amount: Int
		public var startLoop: Int
	}
	public private(set) var drops: [Drop] = []

	public init() {}

	/// The drop a stat update makes, nil when no experience was gained (a level boost or drain).
	public static func drop(for c: StatChange, minXp: Int = 0) -> (skill: Int, amount: Int)? {
		let gained = c.newXp - c.oldXp
		return gained > 0 && gained >= minXp ? (c.skill, gained) : nil
	}

	public func onLogin(_ ctx: PluginContext) { drops = [] }
	public func onLogout(_ ctx: PluginContext) { drops = [] }
	public func shutDown(_ ctx: PluginContext) { drops = [] }

	public func onStatChanged(_ change: StatChange, _ ctx: PluginContext) {
		guard let d = Self.drop(for: change, minXp: config.int("minXp")) else { return }
		drops.append(Drop(skill: d.skill, amount: d.amount, startLoop: ctx.loop))
		if drops.count > 24 { drops.removeFirst(drops.count - 24) }
	}

	private var iconFrames: [SpriteFrame]?

	/// The skill icon sprites (one frame per stat id), looked up once; empty when the cache has no such sheet.
	private func skillIcons(_ canvas: OverlayCanvas) -> [SpriteFrame] {
		if let f = iconFrames { return f }
		var frames: [SpriteFrame] = []
		for name in ["staticons", "staticons2"] {
			if let sheet = (try? canvas.ctx.store?.sprite(named: name)) ?? nil, sheet.frames.count >= 25 { frames = sheet.frames; break }
		}
		iconFrames = frames
		return frames
	}

	/// Vertical offset (pixels above the start line) of a drop `age` client cycles old that lives `life` cycles: rises ~70 px.
	public static func rise(age: Int, life: Int) -> Int { min(age, life) * 70 / max(life, 1) }

	public func drawOverlay(_ layer: OverlayLayer, _ canvas: OverlayCanvas, into r: inout Raster) {
		guard layer == .hud, !drops.isEmpty else { return }
		let loop = canvas.loop
		let life = config.int("seconds") * 50
		drops.removeAll { loop - $0.startLoop > life || loop < $0.startLoop }
		guard !drops.isEmpty else { return }
		let icons = config.bool("icons") ? skillIcons(canvas) : []
		let v = canvas.viewport
		let cx = v.x + v.w * 5 / 8, base = v.y + v.h / 3 + 40
		var floor = Int.max
		// Newest first so a fresh drop keeps its place and older ones shift up out of its way.
		for d in drops.sorted(by: { $0.startLoop > $1.startLoop }) {
			var y = base - Self.rise(age: loop - d.startLoop, life: life)
			if y > floor - 16 { y = floor - 16 }
			floor = y
			// Without an icon sheet in the cache the skill's name stands in for it.
			let icon = d.skill < icons.count ? icons[d.skill] : nil
			let text = (icon == nil ? Skills.name(d.skill) + " " : "") + "+" + PluginFormat.number(d.amount)
			let tw = canvas.textWidth(text, font: .bold)
			let total = tw + (icon.map { $0.width + 3 } ?? 0)
			var x = cx - total / 2
			if let icon { r.draw(icon, x: x, y: y - icon.height + 3); x += icon.width + 3 }
			canvas.drawText(text, x: x, y: y, color: 0xFFFFFF, font: .bold, centered: false, into: &r)
		}
	}
}

/// Session experience per skill, with experience per hour.
public final class XpTrackerPlugin: ClientPlugin {
	public let id = "xpTracker"
	public let name = "XP Tracker"
	public let summary = "Tracks experience gained and xp per hour this session (open it from the Plugins sheet)."
	public var enabled = false
	public let config = PluginConfig([
		.toggle("hud", "Show on screen", false, help: "A small panel in the top left of the viewport."),
	])
	public var subscriptions: PluginSubscription { config.bool("hud") ? [.stats, .overlayHUD] : [.stats] }

	public struct Row: Equatable {
		public var skill: Int
		public var name: String
		public var gained: Int
		public var levelsGained: Int
		public var level: Int
		public var xpPerHour: Int
		public var secondsToNextLevel: Int?
	}

	private struct Track {
		var startXp: Int
		var startLevel: Int
		var currentXp: Int
		var firstGain: Date?
		var lastGain: Date?
	}
	private var tracks: [Int: Track] = [:]
	private let lock = NSLock()
	/// Clock for tests.
	var now: () -> Date = Date.init

	public init() {}

	public func onLogin(_ ctx: PluginContext) { reset() }
	public func onLogout(_ ctx: PluginContext) {}

	public func reset() {
		lock.lock(); tracks = [:]; lock.unlock()
	}

	public func onStatChanged(_ c: StatChange, _ ctx: PluginContext) { record(c) }

	func record(_ c: StatChange) {
		guard c.newXp > c.oldXp else { return }
		lock.lock(); defer { lock.unlock() }
		var t = tracks[c.skill] ?? Track(startXp: c.oldXp, startLevel: XpTable.level(forXp: c.oldXp), currentXp: c.oldXp, firstGain: nil, lastGain: nil)
		let n = now()
		if t.firstGain == nil { t.firstGain = n }
		t.lastGain = n
		t.currentXp = c.newXp
		tracks[c.skill] = t
	}

	/// Rows for the App panel, most experience first. Safe to call from the main thread.
	public func snapshot() -> [Row] {
		lock.lock(); defer { lock.unlock() }
		let n = now()
		return tracks.map { skill, t in
			let gained = t.currentXp - t.startXp
			let level = XpTable.level(forXp: t.currentXp, maxLevel: skill == 18 || skill == 24 ? 120 : 99)
			// Rate over the time since the first gain, but at least a minute so one drop does not read as millions per hour.
			let elapsed = max(n.timeIntervalSince(t.firstGain ?? n), 60)
			let rate = Int(Double(gained) / elapsed * 3600)
			let next = level < 99 ? XpTable.xp(forLevel: level + 1) - t.currentXp : nil
			let eta = next.flatMap { rate > 0 ? Int(Double($0) / Double(rate) * 3600) : nil }
			return Row(skill: skill, name: Skills.name(skill), gained: gained, levelsGained: level - t.startLevel, level: level, xpPerHour: rate, secondsToNextLevel: eta)
		}.sorted { $0.gained > $1.gained }
	}

	public var totalGained: Int { snapshot().reduce(0) { $0 + $1.gained } }

	public func drawOverlay(_ layer: OverlayLayer, _ canvas: OverlayCanvas, into r: inout Raster) {
		guard layer == .hud, config.bool("hud") else { return }
		let rows = snapshot().prefix(5)
		guard !rows.isEmpty else { return }
		var y = canvas.viewport.y + 74
		let x = canvas.viewport.x + 6
		for row in rows {
			canvas.drawText("\(row.name): \(PluginFormat.number(row.gained)) xp (\(PluginFormat.quantity(row.xpPerHour))/hr)", x: x, y: y, color: 0xFFFF00, centered: false, into: &r)
			y += 13
		}
	}
}
