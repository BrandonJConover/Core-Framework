import Foundation

/// What a plugin wants to hear about. The manager only does the work behind an event (taking snapshots,
/// diffing them) while at least one enabled plugin subscribes to it, so a plugin-free client pays nothing.
public struct PluginSubscription: OptionSet {
	public let rawValue: Int
	public init(rawValue: Int) { self.rawValue = rawValue }

	public static let gameTick = PluginSubscription(rawValue: 1 << 0)
	public static let clientCycle = PluginSubscription(rawValue: 1 << 1)
	public static let stats = PluginSubscription(rawValue: 1 << 2)
	public static let containers = PluginSubscription(rawValue: 1 << 3)
	public static let chat = PluginSubscription(rawValue: 1 << 4)
	public static let actors = PluginSubscription(rawValue: 1 << 5)
	public static let groundItems = PluginSubscription(rawValue: 1 << 6)
	public static let animations = PluginSubscription(rawValue: 1 << 7)
	public static let hitsplats = PluginSubscription(rawValue: 1 << 8)
	public static let menu = PluginSubscription(rawValue: 1 << 9)
	/// Overlay drawn over the 3D scene, under the interfaces (ground item labels, tile highlights).
	public static let overlayScene = PluginSubscription(rawValue: 1 << 10)
	/// Overlay drawn over the interfaces, clipped to the 3D viewport (floating text, small panels).
	public static let overlayHUD = PluginSubscription(rawValue: 1 << 11)

	/// Subscriptions that need a snapshot of the world diffed every frame.
	static let diffed: PluginSubscription = [.gameTick, .stats, .containers, .chat, .actors, .groundItems, .animations, .hitsplats]
}

public enum OverlayLayer {
	case scene, hud
}

public struct ActorKey: Hashable {
	public let isNpc: Bool
	public let index: Int
	public init(isNpc: Bool, index: Int) { self.isNpc = isNpc; self.index = index }
}

/// A player or npc as a plugin sees it. Tiles are scene tiles (0...103); `worldTile` adds the scene origin.
public struct ActorSnapshot: Equatable {
	public var key: ActorKey
	public var isSelf: Bool
	public var name: String
	/// Npc type id (nil for players).
	public var npcId: Int?
	public var combatLevel: Int
	public var tileX: Int, tileZ: Int
	public var size: Int
	/// Current action animation (rt4 `seqId`), -1 for none.
	public var animation: Int
	/// rt4 `hitVisibleUntil` per splat slot, and the splat data of each slot (only filled while a plugin listens to hitsplats).
	public var hitUntil: [Int]
	public var hitDamage: [Int]
	public var hitType: [Int]
	public var fineX: Int, fineZ: Int
}

public struct StatChange: Equatable {
	public var skill: Int
	public var oldLevel: Int, newLevel: Int
	/// Experience in whole xp (the wire value divided by the manager's `xpDivisor`).
	public var oldXp: Int, newXp: Int
	public var xpDelta: Int { newXp - oldXp }
}

public struct ContainerChange: Equatable {
	public var inventory: Int
	/// (slot, old item id or -1, new item id or -1, old count, new count)
	public var slots: [SlotChange]

	public struct SlotChange: Equatable {
		public var slot: Int
		public var oldId: Int, newId: Int
		public var oldCount: Int, newCount: Int
	}
}

public struct GroundItemSnapshot: Equatable {
	public var type: Int
	public var amount: Int
	public var tileX: Int, tileZ: Int, plane: Int
}

public struct AnimationChange: Equatable {
	public var actor: ActorSnapshot
	public var oldAnimation: Int
}

public struct HitsplatEvent: Equatable {
	public var actor: ActorSnapshot
	public var damage: Int
	public var type: Int
}

/// Everything the diff engine reports.
public enum PluginEvent: Equatable {
	case gameTick
	case statChanged(StatChange)
	case containerChanged(ContainerChange)
	case chatMessage(ChatLine)
	case actorSpawned(ActorSnapshot)
	case actorDespawned(ActorSnapshot)
	case groundItemSpawned(GroundItemSnapshot)
	case groundItemDespawned(GroundItemSnapshot)
	case animationChanged(AnimationChange)
	case hitsplat(HitsplatEvent)
}

/// A request for the App to tell the player something (a UNUserNotification while backgrounded, a haptic otherwise).
public struct PluginNotification: Equatable {
	public enum Kind: String { case idle, lowHitpoints, info }
	public var pluginId: String
	public var kind: Kind
	public var title: String
	public var body: String
}

/// Where a menu being modified came from.
public enum MenuSource { case world, inventory }

/// rt4 skill order (stat ids of UPDATE_STAT).
public enum Skills {
	public static let names = ["Attack", "Defence", "Strength", "Hitpoints", "Ranged", "Prayer", "Magic", "Cooking", "Woodcutting", "Fletching", "Fishing", "Firemaking", "Crafting", "Smithing", "Mining", "Herblore", "Agility", "Thieving", "Slayer", "Farming", "Runecrafting", "Hunter", "Construction", "Summoning", "Dungeoneering"]
	public static let hitpoints = 3
	public static func name(_ skill: Int) -> String { skill >= 0 && skill < names.count ? names[skill] : "Skill \(skill)" }
}

/// The experience table: xp needed for each level (RuneScape formula, level 2 = 83 xp, level 99 = 13,034,431).
public enum XpTable {
	/// `thresholds[l]` is the xp at which level `l + 1` starts, up to level 126.
	static let thresholds: [Int] = {
		var out: [Int] = []
		var points = 0.0
		for l in 1...126 {
			out.append(Int((points / 4).rounded(.down)))
			points += (Double(l) + 300.0 * pow(2.0, Double(l) / 7.0)).rounded(.down)
		}
		return out
	}()

	/// The level a skill with `xp` is at, capped at `maxLevel`.
	public static func level(forXp xp: Int, maxLevel: Int = 99) -> Int {
		var level = 1
		while level < min(maxLevel, thresholds.count), xp >= thresholds[level] { level += 1 }
		return level
	}

	public static func xp(forLevel level: Int) -> Int { thresholds[max(0, min(level - 1, thresholds.count - 1))] }
}

public enum PluginFormat {
	/// 1,234,567 style number.
	public static func number(_ n: Int) -> String {
		var s = String(abs(n))
		var out = ""
		while s.count > 3 { out = "," + s.suffix(3) + out; s = String(s.dropLast(3)) }
		return (n < 0 ? "-" : "") + s + out
	}

	/// RuneScape style stack size: plain below 100k, "100K" up to 10M, then "10M".
	public static func quantity(_ n: Int) -> String {
		if n >= 10_000_000 { return "\(n / 1_000_000)M" }
		if n >= 100_000 { return "\(n / 1000)K" }
		return number(n)
	}

	/// "<col=..>" and other tags removed, a trailing " (level: N)" / " (skill: N)" removed: the plain target name of a menu entry.
	public static func plainTarget(_ base: String) -> String {
		var out = ""
		var inTag = false
		for ch in base {
			if ch == "<" { inTag = true } else if ch == ">" && inTag { inTag = false } else if !inTag { out.append(ch) }
		}
		if let r = out.range(of: " (level:") ?? out.range(of: " (skill:") { out = String(out[..<r.lowerBound]) }
		else if let r = out.range(of: "(level:") ?? out.range(of: "(skill:") { out = String(out[..<r.lowerBound]) }
		return out.trimmingCharacters(in: .whitespaces)
	}
}
