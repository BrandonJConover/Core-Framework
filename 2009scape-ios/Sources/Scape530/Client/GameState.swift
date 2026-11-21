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
	/// Inventory id -> slot count.
	public var inventorySizes: [Int: Int] = [:]
	/// Public / private / trade chat filter settings.
	public var chatFilters: (public: Int, private: Int, trade: Int) = (0, 0, 0)
	/// Seconds until the server reboots (rt4 `Player.rebootTimer`, in ticks / 30).
	public var rebootSeconds = 0
	/// Chat history, newest first (rt4 `Chat`); read by the chatbox scripts.
	public var chatLog = ChatLog()
	/// Friends, ignores and clan chat (rt4 `FriendsList`, `IgnoreList`, `ClanChat`).
	public var social = SocialLists()
	/// rt4 `Player.worldId`: used to sort same-world friends first.
	public var ownWorld = 1
	/// Base-37 names on the ignore list (rt4 `IgnoreList.encodedUsernames`).
	public var ignored: Set<Int64> { Set(social.ignores) }
	/// Our own base-37 name (rt4 `Player.name37`), from the appearance block once it has arrived.
	public var selfName37: Int64 {
		guard let p = players else { return 0 }
		return p.players[p.selfIndex]?.appearance?.name37 ?? 0
	}
	/// Game messages as plain strings, oldest first (kept for callers that only want the text).
	public var chat: [String] { chatLog.lines.reversed().filter { $0.type == 0 }.map(\.message) }
	/// Grand Exchange offer slots (rt4 `StockMarketManager.offers`); a fresh client starts with six empty (not started) slots.
	public var stockOffers = [ServerMessage.StockOffer](repeating: GameState.emptyOffer, count: 6)
	public static let emptyOffer = ServerMessage.StockOffer(status: 0, type: 0, item: 0, price: 0, count: 0, completedCount: 0, completedGold: 0)
	/// rt4 `client.settings`, from SET_SETTINGS_STRING.
	public var settingsString = ""
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
		case .decodeFailed, .disconnected, .loginFailed, .loginQueued: break
		}
	}

	public mutating func apply(_ m: ServerMessage) {
		if interfaces.apply(m) { return }
		switch m {
		case .rebuildNormal(let r), .rebuildRegion(let r): rebuild = r
		case let .grandExchangeOffer(slot, offer): if slot >= 0 && slot < stockOffers.count { stockOffers[slot] = offer ?? Self.emptyOffer }
		case .settingsString(let s): settingsString = s
		case .varp(let id, let v): varps[id] = v
		case .updateStat(let s, let l, let xp): stats[s] = (l, xp)
		case .runEnergy(let e): runEnergy = e
		case .runWeight(let w): weight = w
		case .gameMessage(let s): chatLog.addGameMessage(s, ignored: ignored)
		case .ignoreList(let names): social.setIgnores(names)
		case .friendlistLoaded(let state): social.friendsState = state
		case let .updateFriend(name37, world, rank, worldName):
			if let notice = social.updateFriend(rawName37: name37, world: world, rank: rank, worldName: worldName, ownWorld: ownWorld) {
				chatLog.add(type: 5, name: "", message: notice)
			}
		case .joinClanChat(let j): social.joinClan(j, selfName37: selfName37)
		case let .updateClan(name37, world, rank, worldName, removed):
			social.updateClan(name37: name37, world: world, rank: rank, worldName: worldName, removed: removed, selfName37: selfName37)
		case .invFull(_, let inv, let items):
			var slots: [Int: ServerMessage.InvItem] = [:]
			for (i, it) in items.enumerated() where it.id >= 0 { slots[i] = it }
			inventories[inv] = slots
			inventorySizes[inv] = items.count
		case .invPartial(_, let inv, let changes):
			for c in changes {
				inventories[inv, default: [:]][c.slot] = c.item.id >= 0 ? c.item : nil
				inventorySizes[inv] = max(inventorySizes[inv] ?? 0, c.slot + 1)
			}
		case .chatFilterSettings(let p, let pr, let t): chatFilters = (p, pr, t)
		case .rebootTimer(let secs): rebootSeconds = secs
		case .logout: loggedOut = true
		default: break
		}
	}
}
