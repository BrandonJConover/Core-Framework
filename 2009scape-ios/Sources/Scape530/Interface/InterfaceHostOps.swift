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
		switch op.name {
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

		// MARK: player state
		case "invItemId": return r(game.inventories[i(0)]?[i(1)]?.id ?? -1)
		case "invItemCount": return r(Int(game.inventories[i(0)]?[i(1)]?.count ?? 0))
		case "invTotalCount":
			var n = 0
			for it in (game.inventories[i(0)] ?? [:]).values where it.id == i(1) { n += Int(it.count) }
			return r(n)
		case "invSize": return r(game.inventorySizes[i(0)] ?? 0)
		case "invFreeSlots":
			let inv = i(0)
			return r(max((game.inventorySizes[inv] ?? 0) - (game.inventories[inv]?.count ?? 0), 0))
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
		case "loginTypeInfo", "language", "affiliate", "hasManyBlackmarks", "isFemale": return r(0)

		// MARK: friends / ignore / clan (nothing loaded yet)
		case "friendCount", "ignoreCount", "clanMemberCount", "clanMinKick", "clanMyRank": return r(0)
		case "isFriend", "isIgnored": return r(0)
		case "friendIndexOf": return r(-1)

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
		case "setChatFilters": game.chatFilters = (i(0), i(1), i(2))
		case "myName":
			if let n = game.players?.players[game.players?.selfIndex ?? -1]?.appearance?.name37, n != 0 { return HostResult(strings: [WordPack.displayName(n)]) }
			return HostResult(strings: [varcstr(32)])

		// MARK: keyboard modifiers
		case "isHoldingAlt", "isHoldingCtrl", "isHoldingShift": return r(0)

		// MARK: display (we are a resizable window the size of the canvas)
		case "windowMode": return r(2)
		case "setWindowMode", "leaveFullscreen": break
		case "setWindowSize": return r(0)
		case "displayModeCount": return r(1)
		case "displayModeSize": return HostResult(ints: [Int32(canvas.w), Int32(canvas.h)])
		case "currentDisplayModeIndex": return r(0)
		case "favouriteWorlds": return r(0)
		case "viewportSize": return HostResult(ints: [Int32(canvas.w), Int32(canvas.h)])
		case "viewportMax6204", "viewportMax6205": return HostResult(ints: [Int32(canvas.w), Int32(canvas.h)])

		// MARK: clock (rt4 `ScriptRunner` 6300-6303)
		case "minutes": return r(Int(Date().timeIntervalSince1970 / 60))
		case "daysSinceLaunch": return r(Int(Date().timeIntervalSince1970 / 86400) - 11745)
		case "year": return r(Calendar(identifier: .gregorian).component(.year, from: Date()))

		// MARK: login (rt4 `LoginManager`)
		case "directLogin":
			if loginReply != -3 { onDirectLogin(s.first ?? "", s.count > 1 ? s[1] : "") }
		case "resetLoginReply": if loginReply != -3 { loginReply = -2 }
		case "loginReply": return HostResult(ints: [loginReply])
		case "loginDetailedReply": return HostResult(ints: [loginDisallowResult])
		case "worldSwitchTimer": return r(0)
		case "lastLoginAddress": return HostResult(strings: [""])
		case "isUsingWebsiteLogin": return r(0)

		// MARK: world list: just the world we are connecting to
		case "worldListFetch": return r(1)
		case "worldFirst": return HostResult(ints: [worldId, 0, 0, 0], strings: ["-", "2009scape"])
		case "worldNext": return HostResult(ints: [-1, 0, 0, 0], strings: ["", ""])
		case "worldInfo":
			guard Int32(i(0)) == worldId else { return HostResult(ints: [-1, 0, 0], strings: ["", ""]) }
			return HostResult(ints: [0, 0, 0], strings: ["-", "2009scape"])
		case "worldHop": return r(0)
		case "lastWorld": return HostResult(ints: [worldId])
		case "setLastWorld": break

		default:
			break
		}
		return HostResult()
	}

	/// rt4 `ClientProt.closeWidget`: closes every modal (type 0) sub-interface.
	func closeModals() {
		for (parent, type) in openTypes where type == 0 {
			game.interfaces.open[parent] = nil
			openTypes[parent] = nil
		}
	}
}
