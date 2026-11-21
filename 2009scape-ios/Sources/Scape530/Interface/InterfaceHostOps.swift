import Foundation

/// Game-query and client-action opcodes (rt4 `ScriptRunner`, the 3xxx-6xxx
/// ranges), answered from `GameState` where the client has the data and with
/// the values a fresh 2009 client would report otherwise.
extension InterfaceScriptHost {
	/// rt4 `PlayerSkillXpTable.xpLevelLookup`: xp needed for level n + 2.
	static let xpLevelLookup: [Int] = {
		var out: [Int] = []
		var total = 0
		for n in 1...99 {
			total += Int(pow(2.0, Double(n) / 7.0) * 300.0 + Double(n))
			out.append(total / 4)
		}
		return out
	}()

	/// rt4 `Protocol` UPDATE_STAT: base level from experience.
	static func baseLevel(xp: Int32) -> Int {
		var level = 1
		for i in 0..<98 where xpLevelLookup[i] <= Int(xp) { level = i + 2 }
		return level
	}

	func statLevel(_ skill: Int) -> Int {
		if let s = game.stats[skill] { return s.level }
		return skill == 3 ? 10 : 1
	}

	func statBase(_ skill: Int) -> Int {
		if let s = game.stats[skill] { return Self.baseLevel(xp: s.xp) }
		return skill == 3 ? 10 : 1
	}

	/// Standard combat level formula (the server's, which rt4 trusts via the player's level).
	func combatLevel() -> Int {
		let att = statBase(0), def = statBase(1), str = statBase(2), hp = statBase(3)
		let ranged = statBase(4), prayer = statBase(5), magic = statBase(6)
		let base = 0.25 * Double(def + hp + prayer / 2)
		let melee = 0.325 * Double(att + str)
		let range = 0.325 * Double(ranged * 3 / 2)
		let mage = 0.325 * Double(magic * 3 / 2)
		return Int(base + max(melee, max(range, mage)))
	}

	func coordPacked() -> Int32 {
		guard let w = game.selfWorld else { return 0 }
		return Int32(truncatingIfNeeded: (w.plane << 28) | (w.x << 14) | w.z)
	}

	public func perform(_ op: HostOpSpec, ints a: [Int32], strings s: [String]) -> HostResult {
		func i(_ n: Int) -> Int { n < a.count ? Int(a[n]) : 0 }
		func r(_ v: Int) -> HostResult { HostResult(ints: [Int32(truncatingIfNeeded: v)]) }
		func b(_ v: Bool) -> HostResult { r(v ? 1 : 0) }
		if let result = performClientOps(op, ints: a, strings: s) { return result }
		if let result = performPreference(op, ints: a) { return result }
		if let result = performQuickChat(op, ints: a, strings: s) { return result }
		if let result = performWorldMap(op, ints: a, strings: s) { return result } // WorldMap/
		switch op.name {
		// MARK: styled context menu (rt4 `ScriptRunner` 5424-5426)
		case "loginBackgroundSetup": menuStyle = MenuStyle(a.map { Int($0) })
		case "loginBackgroundClear": menuStyle = nil
		case "setClientOpt5426": defaultCursor = i(0)

		// MARK: client actions
		case "chatMessage":
			game.chatLog.add(type: 0, name: "", message: s.first ?? "")
			chatAt = transmitTimer
		case "sayPublic": sayPublic(s.first ?? "")
		case "sendPrivateMessage": sendPrivateMessage(to: s.first ?? "", text: s.count > 1 ? s[1] : "")
		case "closeWidget": closeModals(); send(.closeModal)
		case "sendIntegerInput": send(.resumeCount(Int32(s.first ?? "") ?? 0))
		case "sendNameInput": send(.resumeName(s.first ?? ""))
		case "sendStringInput": send(.resumeString(s.first ?? ""))
		case "clientCycle": return r(loop)
		case "geOfferIsSelling": return r(stockOffer(i(0)).type)
		case "geOfferItem": return r(stockOffer(i(0)).item)
		case "geOfferPrice": return r(Int(stockOffer(i(0)).price))
		case "geOfferCount": return r(Int(stockOffer(i(0)).count))
		case "geOfferCompletedCount": return r(Int(stockOffer(i(0)).completedCount))
		case "geOfferCompletedGold": return r(Int(stockOffer(i(0)).completedGold))
		case "geOfferNotStarted": return b(stockOffer(i(0)).status == 0)
		case "geOfferStatus2": return b(stockOffer(i(0)).status == 2)
		case "geOfferDone": return b(stockOffer(i(0)).status == 5)
		case "geOfferStatus1": return b(stockOffer(i(0)).status == 1)

		// MARK: player state
		case "invItemId": return r(game.inventories[i(0)]?[i(1)]?.id ?? -1)
		case "invItemCount": return r(Int(game.inventories[i(0)]?[i(1)]?.count ?? 0))
		case "invTotalCount":
			var n = 0
			for it in (game.inventories[i(0)] ?? [:]).values where it.id == i(1) { n += Int(it.count) }
			return r(n)
		case "invSize": return r(inventorySize(i(0)))
		case "invFreeSlots": return r(inventoryFreeSlots(i(0)))
		case "statLevel": return r(statLevel(i(0)))
		case "statBaseLevel": return r(statBase(i(0)))
		case "statXp": return r(Int(game.stats[i(0)]?.xp ?? 0))
		case "myCoord": return HostResult(ints: [coordPacked()])
		case "isMembersWorld": return b(game.account?.mapMembers ?? false)
		case "clientRights": return r(game.account?.staffModLevel ?? 0)
		case "systemUpdateTimer": return r(game.rebootSeconds * 30)
		case "worldId": return HostResult(ints: [worldId])
		case "runEnergy": return r(game.runEnergy)
		case "weight": return r(game.weight)
		case "isMembersAccount": return b(game.account?.member ?? false)
		case "combatLevel": return r(combatLevel())
		case "blackmarks": return r(game.account?.blackmarks ?? 0)
		case "isUnderageNoConsent": return b((game.account?.underage ?? false) && !(game.account?.parentalChatConsent ?? false))
		case "isQuickChatOnly": return b(game.account?.mapQuickChat ?? false)
		case "loginTypeInfo", "language", "affiliate", "hasManyBlackmarks": return r(0)

		// MARK: friends / ignore / clan (rt4 `ScriptRunner` 3600-3629, backed by `game.social`)
		case "friendCount":
			// rt4: -2 until the friend list is requested, -1 while it loads.
			let st = game.social.friendsState
			return r(st == 0 ? -2 : (st == 1 ? -1 : game.social.friends.count))
		case "friendName":
			guard game.social.friendsState == 2, let f = friend(i(0)) else { return HostResult(strings: [""]) }
			return HostResult(strings: [f.displayName])
		case "friendWorld": return r(game.social.friendsState == 2 ? (friend(i(0))?.world ?? 0) : 0)
		case "friendRank": return r(game.social.friendsState == 2 ? (friend(i(0))?.rank ?? 0) : 0)
		case "friendWorldName":
			return HostResult(strings: [game.social.friendsState == 2 ? (friend(i(0))?.worldName ?? "") : ""])
		case "friendSameGame": return b(game.social.friendsState == 2 && (friend(i(0))?.sameGame ?? false))
		case "friendSetRank":
			let n = Base37.encode(s.first ?? "")
			send(.friendSetRank(name37: n, rank: i(0)))
		case "friendAdd": socialAction(game.social.addFriend(s.first ?? "", selfName37: game.selfName37, members: game.account?.member ?? false))
		case "friendRemove": socialAction(game.social.removeFriend(s.first ?? ""))
		case "ignoreAdd": socialAction(game.social.addIgnore(s.first ?? "", selfName37: game.selfName37))
		case "ignoreRemove": socialAction(game.social.removeIgnore(s.first ?? ""))
		case "isFriend": return b(game.social.isFriend(s.first ?? "", selfName37: game.selfName37))
		case "isIgnored": return b(game.social.isIgnored(s.first ?? ""))
		case "friendIndexOf": return r(game.social.indexOfFriend(s.first ?? ""))
		case "ignoreCount": return r(game.social.friendsState == 0 ? -1 : game.social.ignores.count)
		case "ignoreName":
			let list = game.social.ignores
			guard game.social.friendsState != 0, i(0) >= 0, i(0) < list.count else { return HostResult(strings: [""]) }
			return HostResult(strings: [WordPack.displayName(list[i(0)])])
		case "clanName": return HostResult(strings: [game.social.clanName.map { WordPack.titleCase($0) } ?? ""])
		case "clanOwner": return HostResult(strings: [game.social.clanOwner.map { WordPack.titleCase($0) } ?? ""])
		case "clanMemberCount": return r(game.social.inClan ? game.social.clanMembers.count : -1)
		case "clanMemberName": return HostResult(strings: [clanMember(i(0))?.displayName ?? ""])
		case "clanMemberWorld": return r(clanMember(i(0))?.world ?? 0)
		case "clanMemberRank": return r(clanMember(i(0))?.rank ?? 0)
		case "clanMemberWorldName": return HostResult(strings: [clanMember(i(0))?.worldName ?? ""])
		case "clanMemberIsSelf":
			let me = game.selfName37
			return b(me != 0 && clanMember(i(0))?.name37 == me)
		case "clanMinKick": return r(game.social.clanMinKick)
		case "clanMyRank": return r(game.social.clanRank)
		case "clanKick": socialAction(game.social.kick(s.first ?? ""))
		case "clanJoin":
			let n = Base37.encode(s.first ?? "")
			if n != 0 { send(.clanJoinLeave(name37: n)) }
		case "clanLeave": send(.clanJoinLeave(name37: 0))

		// MARK: chat
		case "chatMessageCount": return r(game.chatLog.size)
		case "chatMessageText": return HostResult(strings: [game.chatLog.line(i(0))?.message ?? ""])
		case "chatMessageType": return r(game.chatLog.line(i(0))?.type ?? -1)
		case "chatMessageName": return HostResult(strings: [game.chatLog.line(i(0))?.name ?? ""])
		case "chatMessageClan": return HostResult(strings: [game.chatLog.line(i(0))?.clan ?? ""])
		case "chatMessagePhrase": return r(game.chatLog.line(i(0))?.phraseId ?? -1)
		case "publicChatFilter": return r(game.chatFilters.public)
		case "privateChatFilter": return r(game.chatFilters.private)
		case "tradeChatFilter": return r(game.chatFilters.trade)
		case "myName":
			if let n = game.players?.players[game.players?.selfIndex ?? -1]?.appearance?.name37, n != 0 { return HostResult(strings: [WordPack.displayName(n)]) }
			return HostResult(strings: [varcstr(32)])

		// MARK: keyboard modifiers
		// rt4 ScriptRunner 5100-5102: `Keyboard.pressedKeys[KEY_ALT / KEY_CTRL / KEY_SHIFT]`.
		case "isHoldingAlt": return b(keyboard.isPressed(KeyCode.alt))
		case "isHoldingCtrl": return b(keyboard.isPressed(KeyCode.ctrl))
		case "isHoldingShift": return b(keyboard.isPressed(KeyCode.shift))

		// MARK: display (a window the size of the canvas: resizable, or fixed 765x503)
		case "windowMode": return r(windowModeValue())
		case "setWindowMode": onSetWindowMode(min(max(i(0), 0), 2)) // rt4: out of range -> 0
		case "leaveFullscreen": break
		case "setWindowSize": return r(0)
		case "displayModeCount": return r(1)
		case "displayModeSize": return HostResult(ints: [Int32(canvas.w), Int32(canvas.h)])
		case "currentDisplayModeIndex": return r(0)
		case "viewportSize": return HostResult(ints: [Int32(canvas.w), Int32(canvas.h)])
		case "viewportMax6204", "viewportMax6205": return HostResult(ints: [Int32(canvas.w), Int32(canvas.h)])

		// MARK: clock (rt4 `ScriptRunner` 6300-6303)
		case "minutes": return r(Int(Date().timeIntervalSince1970 / 60))
		case "daysSinceLaunch": return r(Int(Date().timeIntervalSince1970 / 86400) - 11745)
		case "year": return r(Calendar(identifier: .gregorian).component(.year, from: Date()))

		// MARK: login (rt4 `LoginManager`)
		case "directLogin":
			if loginReply != -3 {
				loginWorldSelector = i(0)
				onDirectLogin(s.first ?? "", s.count > 1 ? s[1] : "")
			}
		case "resetLoginReply": if loginReply != -3, loginReply != 1 { loginReply = -2 }
		case "loginReply": return HostResult(ints: [loginReply])
		case "loginDetailedReply": return HostResult(ints: [loginDisallowResult])
		case "worldSwitchTimer": return r(Int(worldSwitchTimer))
		case "lastLoginAddress": return HostResult(strings: [""])
		case "isUsingWebsiteLogin": return r(0)
		// rt4 `ScriptRunner` 5601 `LoginManager.method3395`: release a login held at reply 1 (the video-advert wait).
		case "skipLoginStage10": onSkipLoginStage()

		// MARK: world list (rt4 `WorldList`, CS2 6500-6507; see `Net/WorldList.swift`)
		// Only on the login screen (rt4 requires `gameState == 10` and no login or list request in progress).
		case "worldListFetch":
			guard loginReply != -3 else { return r(1) }
			return r(worldList.fetch() == -1 ? 0 : 1)
		case "worldFirst": return worldRow(worldList.firstWorld())
		case "worldNext": return worldRow(worldList.nextWorld())
		case "worldInfo":
			// 6506 leaves out the id the walk ops lead with; an unknown world reads flags -1.
			guard let w = worldList.world(i(0)) ?? pendingWorld(i(0)) else { return HostResult(ints: [-1, 0, 0], strings: ["", ""]) }
			return HostResult(ints: Array(worldRow(w).ints.dropFirst()), strings: worldRow(w).strings)
		case "worldHop":
			guard loginReply != -3, let w = worldList.world(i(0)) ?? pendingWorld(i(0)) else { return r(0) }
			return r(onWorldHop(w) ? 1 : 0)
		case "lastWorld": return r(prefs.lastWorldId)
		case "setLastWorld": prefs.lastWorldId = i(0)
		case "worldSort":
			worldList.sort(primaryKey: i(0), primaryReverse: i(1) == 1, secondaryKey: i(2), secondaryReverse: i(3) == 1)
		case "setFavouriteWorlds": prefs.favoriteWorlds = (0...2).contains(i(0)) ? i(0) : 0
		case "favoriteWorlds": return r(prefs.favoriteWorlds)
		case "setPref6600": prefs.unknownFlag = i(0) == 1
		case "pref6601": return b(prefs.unknownFlag)

		case "cameraMoveTo", "cameraPointAt", "cameraUnlock", "cameraSetAngles", "cameraPitch", "cameraYaw":
			if let v = cameraOp(op.name, a.map(Int.init)), op.name == "cameraPitch" || op.name == "cameraYaw" { return r(v) }
		default:
			break
		}
		return HostResult()
	}

	/// rt4 `StockMarketManager.offers[slot]`; an out-of-range slot reads as an empty offer.
	func stockOffer(_ slot: Int) -> ServerMessage.StockOffer {
		slot >= 0 && slot < game.stockOffers.count ? game.stockOffers[slot] : GameState.emptyOffer
	}

	/// Until the list has arrived the world we are on stands in for itself. rt4 never asks earlier (it loads the list
	/// before the login screen opens); the login script reads this world's flags to see whether it is a PvP world.
	func pendingWorld(_ id: Int) -> WorldEntry? {
		guard !worldList.loaded, id == Int(worldId) else { return nil }
		return WorldEntry(id: id, country: 0, flags: 0, activity: "-", hostname: "")
	}

	/// The values rt4 pushes for `getFirstWorldData` / `getNextWorldData` / 6506: id, flags, country flag, players
	/// and the activity and country name strings; -1 for the id (and zeros) when there is no such world.
	func worldRow(_ w: WorldEntry?) -> HostResult {
		guard let w else { return HostResult(ints: [-1, 0, 0, 0], strings: ["", ""]) }
		let c = worldList.country(of: w)
		return HostResult(ints: [Int32(w.id), w.flags, Int32(c.flag), Int32(w.players)], strings: [w.activity, c.name])
	}

	/// rt4 `InvTypeList.get(id).size` (opcode `getItemContainerLength`): the configured slot count.
	func inventorySize(_ inv: Int) -> Int { ((try? store.inv(inv)) ?? nil)?.size ?? 0 }

	/// rt4 `Inv.getFreeSpace`: the configured size less the occupied slots; a negative id has no room.
	func inventoryFreeSlots(_ inv: Int) -> Int {
		if inv < 0 { return 0 }
		return max(inventorySize(inv) - (game.inventories[inv]?.count ?? 0), 0)
	}

	/// A friend row for a script index, or nil when it is out of range.
	func friend(_ i: Int) -> Friend? { i >= 0 && i < game.social.friends.count ? game.social.friends[i] : nil }
	/// A clan member for a script index; nil when we are in no channel or the index is out of range.
	func clanMember(_ i: Int) -> ClanMember? {
		game.social.inClan && i >= 0 && i < game.social.clanMembers.count ? game.social.clanMembers[i] : nil
	}

	/// Sends the packet of a list change and files its notice in the chat history, then wakes the friends hooks
	/// (rt4 sets `FriendsList.transmitAt` when it changes either list).
	func socialAction(_ a: SocialAction) {
		if let n = a.notice { game.chatLog.add(type: 0, name: "", message: n); chatAt = transmitTimer }
		if let m = a.message { send(m); friendAt = transmitTimer }
	}

	/// rt4 `ClientProt.closeWidget`: closes every modal (type 0) sub-interface.
	func closeModals() {
		for (parent, type) in openTypes where type == 0 {
			game.interfaces.open[parent] = nil
			openTypes[parent] = nil
		}
	}
}
