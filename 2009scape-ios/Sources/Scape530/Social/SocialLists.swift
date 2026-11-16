import Foundation

/// One clan chat member (rt4 `ClanMember`). `rank` is signed (-1 = guest).
public struct ClanMember: Equatable {
	public var name37: Int64
	public var world: Int
	public var rank: Int
	public var worldName: String
	public init(name37: Int64, world: Int, rank: Int, worldName: String) {
		self.name37 = name37; self.world = world; self.rank = rank; self.worldName = worldName
	}
	/// rt4 `ClanMember.username`: the decoded (lowercase) base-37 name.
	public var username: String { Base37.decode(name37) ?? "" }
	/// rt4 `.toTitleCase()` of the name, as the clan list scripts display it.
	public var displayName: String { WordPack.displayName(name37) }
}

/// The payload of JOIN_CLAN_CHAT. `members == nil` is rt4's size 255: only the header changes.
public struct ClanChannelJoin: Equatable {
	public var owner37: Int64
	public var name37: Int64
	public var minKick: Int
	public var members: [ClanMember]?
}

/// One friend list row (rt4 `FriendsList` parallel arrays at one index).
public struct Friend: Equatable {
	public var name37: Int64
	public var world: Int
	public var worldName: String
	public var rank: Int
	public var sameGame: Bool
	public var displayName: String { WordPack.displayName(name37) }
}

/// Result of a client-side list change: the packet to send and/or the chat notice rt4 shows.
public struct SocialAction: Equatable {
	public var message: ClientMessage?
	public var notice: String?
	public static func == (a: SocialAction, b: SocialAction) -> Bool {
		a.notice == b.notice && String(describing: a.message) == String(describing: b.message)
	}
}

/// Friends, ignores and clan chat state, ported from rt4 `FriendsList`, `IgnoreList`, `ClanChat` and
/// the Protocol branches that fill them. Names are kept as base-37 longs; every comparison rt4 does
/// with `equalsIgnoreCase` on decoded names is the same comparison on the longs.
public struct SocialLists: Equatable {
	// MARK: friends (rt4 `FriendsList`)

	/// rt4 `FriendsList.state`: 0 not loaded, 1 loading, 2 loaded (the scripts read -2 / -1 counts until then).
	public var friendsState = 0
	public private(set) var friends: [Friend] = []
	// MARK: ignores (rt4 `IgnoreList`)
	public private(set) var ignores: [Int64] = []

	// MARK: clan chat (rt4 `ClanChat`)
	public var clanName: String?
	public var clanOwner: String?
	public var clanMinKick = 0
	/// rt4 `ClanChat.rank`: our own rank in the channel.
	public var clanRank = 0
	public private(set) var clanMembers: [ClanMember] = []
	public var inClan: Bool { clanName != nil }

	public init() {}

	public static let friendLimit = 200, freeFriendLimit = 100, ignoreLimit = 100

	/// rt4 strips a leading `<img=0>` / `<img=1>` from script-supplied names before comparing.
	public static func stripIcon(_ s: String) -> String {
		(s.hasPrefix("<img=0>") || s.hasPrefix("<img=1>")) ? String(s.dropFirst(7)) : s
	}

	// MARK: server updates

	/// UPDATE_FRIENDLIST (rt4 `Protocol`): update or append the friend, then bubble-sort with
	/// same-world friends first and offline ones last. Returns the "has logged in/out" chat notice.
	/// `rawName37` still carries the sign bit, which rt4 inverts into `sameGame`.
	@discardableResult
	public mutating func updateFriend(rawName37: Int64, world: Int, rank: Int, worldName: String?, ownWorld: Int) -> String? {
		let sameGame = rawName37 >= 0
		let name37 = rawName37 & Int64.max
		let wn = worldName ?? ""
		var notice: String?
		if let i = friends.firstIndex(where: { $0.name37 == name37 }) {
			if friends[i].world != world {
				let name = WordPack.displayName(name37)
				if world > 0 { notice = name + " has logged in." }
				if world == 0 { notice = name + " has logged out." }
			}
			friends[i].world = world
			friends[i].worldName = wn
			friends[i].rank = rank
			friends[i].sameGame = sameGame
		} else if friends.count < Self.friendLimit {
			friends.append(Friend(name37: name37, world: world, worldName: wn, rank: rank, sameGame: sameGame))
		}
		// rt4's bubble sort: swap when the right neighbour is on our world and the left is not,
		// or the left is offline and the right is not.
		var n = friends.count
		while n > 0 {
			n -= 1
			var sorted = true
			for i in 0..<n {
				let l = friends[i].world, r = friends[i + 1].world
				if (l != ownWorld && ownWorld == r) || (l == 0 && r != 0) {
					sorted = false
					friends.swapAt(i, i + 1)
				}
			}
			if sorted { break }
		}
		return notice
	}

	/// UPDATE_IGNORELIST: replaces the whole list.
	public mutating func setIgnores(_ names: [Int64]) { ignores = names }

	/// JOIN_CLAN_CHAT.
	public mutating func joinClan(_ j: ClanChannelJoin?, selfName37: Int64) {
		guard let j else {
			clanOwner = nil; clanName = nil; clanMembers = []
			return
		}
		clanName = Base37.decode(j.name37)
		clanOwner = Base37.decode(j.owner37)
		clanMinKick = j.minKick
		guard let members = j.members else { return }
		for m in members where m.name37 == selfName37 { clanRank = m.rank }
		// rt4 bubble-sorts by the decoded name, byte-wise ascending.
		clanMembers = members.sorted { Self.compare($0.username, $1.username) < 0 }
	}

	/// UPDATE_CLAN: add, change or remove one member, keeping the sorted order rt4 keeps.
	public mutating func updateClan(name37: Int64, world: Int, rank: Int, worldName: String?, removed: Bool, selfName37: Int64) {
		if removed {
			if let i = clanMembers.firstIndex(where: { $0.name37 == name37 && $0.world == world }) { clanMembers.remove(at: i) }
			return
		}
		let member = ClanMember(name37: name37, world: world, rank: rank, worldName: worldName ?? "")
		var n = clanMembers.count - 1
		while n >= 0 {
			let c = Self.compare(clanMembers[n].username, member.username)
			if c == 0 {
				clanMembers[n].world = world
				clanMembers[n].rank = rank
				clanMembers[n].worldName = member.worldName
				if name37 == selfName37 { clanRank = rank }
				return
			}
			if c < 0 { break }
			n -= 1
		}
		// rt4's array holds 100 members.
		if clanMembers.count >= 100 { return }
		clanMembers.insert(member, at: n + 1)
		if name37 == selfName37 { clanRank = rank }
	}

	/// rt4 `JagString.method3139`: byte-wise comparison, the shorter string first on a common prefix.
	static func compare(_ a: String, _ b: String) -> Int {
		let x = Array(a.utf8), y = Array(b.utf8)
		for i in 0..<min(x.count, y.count) where x[i] != y[i] { return x[i] < y[i] ? -1 : 1 }
		return x.count == y.count ? 0 : (x.count < y.count ? -1 : 1)
	}

	// MARK: queries (the CS2 ops)

	public func indexOfFriend(_ name: String) -> Int {
		let n = Base37.encode(Self.stripIcon(name))
		return n == 0 ? -1 : (friends.firstIndex { $0.name37 == n } ?? -1)
	}
	public func isIgnored(_ name: String) -> Bool {
		let n = Base37.encode(Self.stripIcon(name))
		return n != 0 && ignores.contains(n)
	}
	/// rt4 `FriendsList.contains`: also true for ourselves.
	public func isFriend(_ name: String, selfName37: Int64) -> Bool {
		let n = Base37.encode(Self.stripIcon(name))
		return n != 0 && (friends.contains { $0.name37 == n } || n == selfName37)
	}

	// MARK: client-side changes (rt4 `FriendsList.add/remove`, `IgnoreList.add/remove`)

	public mutating func addFriend(_ name: String, selfName37: Int64, members: Bool) -> SocialAction {
		let n = Base37.encode(name)
		if n == 0 { return SocialAction() }
		if (friends.count >= Self.freeFriendLimit && !members) || friends.count >= Self.friendLimit {
			return SocialAction(notice: "Your friend list is full. Max of 100 for free users, and 200 for members")
		}
		let shown = WordPack.displayName(n)
		if friends.contains(where: { $0.name37 == n }) { return SocialAction(notice: shown + " is already on your friend list") }
		if ignores.contains(n) { return SocialAction(notice: "Please remove " + shown + " from your ignore list first") }
		if n == selfName37 { return SocialAction(notice: "You can't add yourself to your own friend list") }
		friends.append(Friend(name37: n, world: 0, worldName: "", rank: 0, sameGame: false))
		return SocialAction(message: .friendAdd(n))
	}

	public mutating func removeFriend(_ name: String) -> SocialAction {
		let n = Base37.encode(name)
		guard n != 0, let i = friends.firstIndex(where: { $0.name37 == n }) else { return SocialAction() }
		friends.remove(at: i)
		return SocialAction(message: .friendDel(n))
	}

	public mutating func addIgnore(_ name: String, selfName37: Int64) -> SocialAction {
		let n = Base37.encode(name)
		if n == 0 { return SocialAction() }
		if ignores.count >= Self.ignoreLimit { return SocialAction(notice: "Your ignore list is full. Max of 100 users") }
		let shown = WordPack.displayName(n)
		if ignores.contains(n) { return SocialAction(notice: shown + " is already on your ignore list") }
		if friends.contains(where: { $0.name37 == n }) { return SocialAction(notice: "Please remove " + shown + " from your friend list first") }
		if n == selfName37 { return SocialAction(notice: "You can't add yourself to your own ignore list") }
		ignores.append(n)
		return SocialAction(message: .ignoreAdd(n))
	}

	public mutating func removeIgnore(_ name: String) -> SocialAction {
		let n = Base37.encode(name)
		guard n != 0, let i = ignores.firstIndex(of: n) else { return SocialAction() }
		ignores.remove(at: i)
		return SocialAction(message: .ignoreDel(n))
	}

	/// rt4 `ClanChat.kick`: only members currently in the channel can be kicked.
	public func kick(_ name: String) -> SocialAction {
		let n = Base37.encode(name)
		guard n != 0, let m = clanMembers.first(where: { $0.name37 == n }) else { return SocialAction() }
		return SocialAction(message: .clanKick(name37: m.name37))
	}
}
