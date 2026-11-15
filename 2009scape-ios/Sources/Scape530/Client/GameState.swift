/// Everything the UI shows, folded from server messages on the UI thread.
public struct GameState {
	public var account: Login.Success?
	public var interfaces = InterfaceState()
	public var varps: [Int: Int32] = [:]
	public var stats: [Int: (level: Int, xp: Int32)] = [:]
	public var runEnergy = 0
	public var weight = 0
	/// Inventory id -> slot -> item.
	public var inventories: [Int: [Int: ServerMessage.InvItem]] = [:]
	public var chat: [String] = []
	public var rebuild: RebuildNormal?
	public var players: PlayerInfoDecoder?
	public var npcs: NpcInfoDecoder?
	public var ticks = 0
	public var loggedOut = false

	public init() {}

	/// Self position in world tiles, if known.
	public var selfWorld: (x: Int, z: Int, plane: Int)? {
		guard let r = rebuild, let p = players, let me = p.players[p.selfIndex] else { return nil }
		return ((r.zoneX - 6) * 8 + me.x, (r.zoneZ - 6) * 8 + me.z, p.plane)
	}

	public mutating func apply(_ e: GameSession.Event) {
		switch e {
		case .loggedIn(let a): account = a
		case .players(_, let p): players = p; ticks += 1
		case .npcs(_, let n): npcs = n
		case .message(let m): apply(m)
		case .decodeFailed, .disconnected: break
		}
	}

	public mutating func apply(_ m: ServerMessage) {
		if interfaces.apply(m) { return }
		switch m {
		case .rebuildNormal(let r): rebuild = r
		case .varp(let id, let v): varps[id] = v
		case .updateStat(let s, let l, let xp): stats[s] = (l, xp)
		case .runEnergy(let e): runEnergy = e
		case .runWeight(let w): weight = w
		case .gameMessage(let s):
			chat.append(s)
			if chat.count > 100 { chat.removeFirst(chat.count - 100) }
		case .invFull(_, let inv, let items):
			var slots: [Int: ServerMessage.InvItem] = [:]
			for (i, it) in items.enumerated() where it.id >= 0 { slots[i] = it }
			inventories[inv] = slots
		case .invPartial(_, let inv, let changes):
			for c in changes { inventories[inv, default: [:]][c.slot] = c.item }
		case .logout: loggedOut = true
		default: break
		}
	}
}
