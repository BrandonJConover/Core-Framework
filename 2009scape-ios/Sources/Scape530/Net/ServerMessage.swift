/// Typed server -> client game messages. Each decoder is a port of the
/// matching branch of rt4 `Protocol.readPacketInternal` (field order and byte
/// transforms are rt4's; the comments name the rt4 locals where they were
/// unnamed). Decoding is strict: a typed decoder must consume the payload
/// exactly, which is what keeps the port honest against a live server.
public enum ServerMessage: Equatable {
	// Map / world
	case rebuildNormal(RebuildNormal)
	/// REBUILD_REGION (214): a dynamic (instanced) region; `RebuildNormal.chunks` holds the 13x13x4 chunk template.
	case rebuildRegion(RebuildNormal)
	case zonePartialFollows(chunkX: Int, chunkZ: Int)
	case zoneFullFollows(chunkX: Int, chunkZ: Int)
	case zonePartialEnclosed(chunkX: Int, chunkZ: Int, updates: [ZoneUpdate])
	case zoneUpdate(ZoneUpdate)
	case teleportLocalPlayer(localX: Int, localZ: Int, plane: Int, jump: Bool)
	case clearMinimapFlag
	case setMinimapState(Int)

	// Variables
	case varp(id: Int, value: Int32)
	case varbit(id: Int, value: Int32)
	case varc(id: Int, value: Int32)
	case resetClientVarcache
	case forceVarpRefresh

	// Player stats
	case updateStat(skill: Int, level: Int, xp: Int32)
	case runEnergy(Int)
	case runWeight(Int)
	case setInteraction(slot: Int, option: String?, cursor: Int, top: Bool)
	case setWalkText(String?)

	// Chat / social
	case gameMessage(String)
	/// MESSAGE_PRIVATE: a private message from `name37`; `text` is the huffman-packed body (rt4 `formatChatMessage`).
	case privateMessage(name37: Int64, messageId: Int64, rights: Int, text: [UInt8])
	/// MESSAGE_PRIVATE_ECHO: our own private message sent to `name37`, echoed back.
	case privateMessageEcho(name37: Int64, text: [UInt8])
	/// SPOTANIM_ENTITY (rt4 opcode 56): a graphic on an npc or player (`target` flags the kind), or on a ground tile.
	case spotAnimEntity(delay: Int, height: Int, target: Int32, gfx: Int)
	case chatFilterSettings(publicFilter: Int, privateFilter: Int, tradeFilter: Int)
	case friendlistLoaded(state: Int)
	case updateFriend(name37: Int64, world: Int, rank: Int, worldName: String?)
	case ignoreList([Int64])
	/// JOIN_CLAN_CHAT: the channel we joined, or nil when the server cleared it (owner 0).
	case joinClanChat(ClanChannelJoin?)
	/// UPDATE_CLAN: one member joined, changed world or rank (`removed` false), or left (`removed` true).
	case updateClan(name37: Int64, world: Int, rank: Int, worldName: String?, removed: Bool)
	/// MESSAGE_CLANCHANNEL: a typed clan chat line (`text` is the huffman-packed body).
	case clanMessage(name37: Int64, clan37: Int64, messageId: Int64, rights: Int, text: [UInt8])
	/// MESSAGE_QUICKCHAT_PRIVATE (247): a private quick chat phrase; `values` are the undecoded dynamic values.
	case quickChatPrivate(name37: Int64, messageId: Int64, rights: Int, phrase: Int, values: [UInt8])
	/// MESSAGE_QUICKCHAT_PRIVATE_ECHO (141): our own private quick chat echoed back.
	case quickChatPrivateEcho(name37: Int64, phrase: Int, values: [UInt8])
	/// CLAN_QUICK_CHAT (81): a quick chat phrase in the clan channel.
	case quickChatClan(name37: Int64, clan37: Int64, messageId: Int64, rights: Int, phrase: Int, values: [UInt8])
	case lastLoginInfo(ip: Int32)
	/// UPDATE_UID192 (169): rt4 writes these 24 bytes to its `random.dat`; the client keeps no such file.
	case updateRandomFile
	/// REFLECTION_CHECK_REPLY request (114): rt4 answers it from `ReflectionCheck.loop`; `entries` is the number of checks.
	case reflectionCheck(id: Int32, entries: Int)
	/// URL_OPEN (42): the page the server wants shown.
	case urlOpen(String)
	/// SET_SETTINGS_STRING (142): rt4 keeps it as `client.settings` (and stores it in a browser cookie).
	case settingsString(String)

	// Interfaces
	/// rt4 names opcode 145 IF_OPENSUB, but its handler sets the top-level interface.
	case ifOpenTop(id: Int, reset: Int)
	/// rt4 names opcode 155 IF_OPENTOP, but it opens `component` inside `parent`.
	case ifOpenSub(parent: Int32, component: Int, type: Int)
	case ifCloseSub(parent: Int32)
	/// SWITCH_WIDGET (176): the interface open at `source` moves to `target`.
	case switchWidget(source: Int32, target: Int32)
	/// GAME_FRAME_UNK (209): runs the `onDialogAbort` hooks of the top-level interface.
	case dialogAbort
	/// DELETE_INVENTORY (191).
	case deleteInventory(inv: Int)
	case ifSetHide(component: Int32, hidden: Bool)
	case ifSetText(component: Int32, text: String)
	case ifSetAnim(component: Int32, seq: Int)
	case ifSetModel(component: Int32, model: Int)
	case ifSetNpcHead(component: Int32, npc: Int)
	case ifSetPlayerHead(component: Int32)
	case ifSetObject(component: Int32, obj: Int, zoomOrCount: Int32)
	case ifSetColour(component: Int32, colour: Int)
	case ifSetPosition(component: Int32, x: Int, y: Int)
	case ifSetAngle(component: Int32, pitch: Int, yaw: Int, scale: Int)
	case ifSetScrollPos(component: Int32, pos: Int)
	case ifSetEvents(component: Int32, start: Int, end: Int, mask: Int32)
	case runClientScript(id: Int32, args: [ScriptArg])
	/// WIDGETSTRUCT_SETTING (9): sets the target param (rt4 `ServerActiveProperties.targetParam`) of `start...end` children.
	case widgetStructSetting(component: Int32, start: Int, end: Int, param: Int)
	/// GENERATE_CHAT_HEAD_FROM_BODY (111): a type-7 model (a head built from three identity kits of the local player).
	case chatHeadFromBody(component: Int32, kit1: Int, kit2: Int, kit3: Int)
	/// INTERFACE_ANIMATE_ROTATE (207): the component's model turns by `yawStep` / `pitchStep` per cycle.
	case modelRotation(component: Int32, pitchStep: Int, yawStep: Int)

	// Inventories
	case invFull(component: Int32, inv: Int, items: [InvItem])
	case invPartial(component: Int32, inv: Int, slots: [(slot: Int, item: InvItem)])
	case invClear(component: Int32)

	// Audio
	case midiSong(Int)
	case midiJingle(id: Int, volume: Int)
	case synthSound(id: Int, loops: Int, delay: Int)

	// World actors and animations
	/// HINT_ARROW (217).
	case hintArrow(HintArrow)
	/// NPC_ANIM_SPECIFIC (102): npc index `npc` plays `seq` after `delay` cycles (65535 = -1).
	case npcAnim(npc: Int, delay: Int, seq: Int)
	/// LOC_ANIM_SPECIFIC (235): the loc of `shape` / `rotation` at a world tile plays `seq` (-1 stops it).
	case locAnimSpecific(level: Int, x: Int, z: Int, shape: Int, rotation: Int, seq: Int)
	/// RESET_ANIMS (131): every player and npc drops its current animation.
	case resetAnims

	// Camera (rt4 `Camera`)
	/// CAMERA_DETACH (154), rt4 `Camera.method2722(true, ...)`: the camera flies to scene tile (`x`, `z`) at `height`.
	case camMoveTo(x: Int, z: Int, height: Int, speed: Int, rotationSpeed: Int)
	/// CAM_LOOKAT (125), rt4 `Camera.method3849`: the camera turns to look at scene tile (`x`, `z`) at `height`.
	case camLookAt(x: Int, z: Int, height: Int, speed: Int, rotationSpeed: Int)
	/// CAM_FORCEANGLE (187).
	case camForceAngle(yaw: Int, pitch: Int)
	/// CAM_SHAKE (27): axis `axis` 0...4 (x, y, z, yaw, pitch).
	case camShake(axis: Int, jitter: Int, amplitude: Int, frequency: Int, phase: Int)
	/// CAM_RESET (24).
	case camReset

	// Grand Exchange
	/// GRAND_EXCHANGE_OFFERS (116): offer slot `slot` 0...5; nil is an empty slot.
	case grandExchangeOffer(slot: Int, offer: StockOffer?)

	// Session
	case logout
	case rebootTimer(seconds: Int)

	/// Framed correctly but not decoded yet (PLAYER_INFO, NPC_INFO, ...).
	case unhandled(opcode: Int, payload: [UInt8])

	public enum ScriptArg: Equatable {
		case int(Int32)
		case string(String)
	}

	/// rt4 `StockMarketOffer`.
	public struct StockOffer: Equatable {
		/// `statusAndType & 7`: 0 not started, 1 and 2 in progress / aborted, 5 done (the CS2 `ge_*` queries test these).
		public var status: Int
		/// rt4 `getType()`: 1 selling, 0 buying.
		public var type: Int
		public var item: Int
		public var price: Int32
		public var count: Int32
		public var completedCount: Int32
		public var completedGold: Int32
		public init(status: Int, type: Int, item: Int, price: Int32, count: Int32, completedCount: Int32, completedGold: Int32) {
			self.status = status; self.type = type; self.item = item; self.price = price
			self.count = count; self.completedCount = completedCount; self.completedGold = completedGold
		}
	}

	/// HINT_ARROW: rt4 `MapMarker`.
	public struct HintArrow: Equatable {
		/// Marker slot 0...3 (`flags >> 6`).
		public var slot: Int
		/// 0 cleared, 1 npc, 2 tile, 10 player (rt4 folds the tile types 3...6 into 2 and keeps the offset in `offsetX/Z`).
		public var type: Int
		/// Index into `hint_headicons` / `hint_mapmarkers` / `hint_mapedge` (rt4 `anInt4048`).
		public var sprite: Int
		/// Npc or player index for types 1 and 10.
		public var target: Int
		/// World tile for type 2, and the position inside the tile in 1/128 tile units (64 centred; types 3...6 sit on an edge).
		public var tileX = 0, tileZ = 0, height = 0
		public var offsetX = 0, offsetZ = 0
		/// The 3D arrow model hovering over the local player (rt4 `MapMarker.playerModelId`), -1 for none.
		public var model = -1
	}

	public struct InvItem: Equatable {
		/// Object id, or -1 for an empty slot (rt4 sends id + 1).
		public var id: Int
		public var count: Int32
	}

	public struct DecodeError: Error, CustomStringConvertible {
		public let opcode: Int
		public let detail: String
		public var description: String { "opcode \(opcode): \(detail)" }
	}

	public static func == (a: ServerMessage, b: ServerMessage) -> Bool {
		String(describing: a) == String(describing: b)
	}

	public static func decode(_ packet: GamePacket) throws -> ServerMessage {
		try decodeTracked(packet).message
	}

	/// `decode` plus the packet's "tracknum": the 16-bit sequence number rt4 `Protocol` reads in every interface /
	/// CS2 / camera packet and feeds to `setVerifyId` (nil for packets that carry none).
	public static func decodeTracked(_ packet: GamePacket) throws -> (message: ServerMessage, track: Int?) {
		var p = Packet(packet.payload)
		let msg: ServerMessage
		do {
			guard let m = try decodeBody(packet.opcode, &p) else {
				return (.unhandled(opcode: packet.opcode, payload: packet.payload), nil)
			}
			msg = m
		} catch let e as PacketUnderflow {
			throw DecodeError(opcode: packet.opcode, detail: "\(e)")
		}
		guard p.offset == packet.payload.count else {
			throw DecodeError(opcode: packet.opcode, detail: "consumed \(p.offset) of \(packet.payload.count) bytes")
		}
		return (msg, p.track)
	}

	static func nullable(_ v: Int) -> Int { v == 65535 ? -1 : v }

	static func decodeBody(_ op: Int, _ p: inout Packet) throws -> ServerMessage? {
		switch op {
		case ServerProt.rebuildNormal:
			return .rebuildNormal(try RebuildNormal(payload: p.data).consumingAll(&p))
		case ServerProt.rebuildRegion:
			return .rebuildRegion(try RebuildNormal(dynamicPayload: p.data).consumingAll(&p))
		case ServerProt.updateZonePartialFollows:
			let x = try p.g1neg()
			let z = try p.g1()
			return .zonePartialFollows(chunkX: x, chunkZ: z)
		case ServerProt.updateZoneFullFollows:
			let x = try p.g1()
			let z = try p.g1neg()
			return .zoneFullFollows(chunkX: x, chunkZ: z)
		case ServerProt.updateZonePartialEnclosed:
			let z = try p.g1add()
			let x = try p.g1sub()
			var updates: [ZoneUpdate] = []
			while p.remaining > 0 {
				let sub = try p.g1()
				updates.append(try ZoneUpdate.decode(sub, &p))
			}
			return .zonePartialEnclosed(chunkX: x, chunkZ: z, updates: updates)
		case _ where ZoneUpdate.opcodes.contains(op):
			return .zoneUpdate(try ZoneUpdate.decode(op, &p))
		case ServerProt.teleportLocalPlayer:
			let x = try p.g1sub()
			let flags = try p.g1add()
			let z = try p.g1()
			return .teleportLocalPlayer(localX: x, localZ: z, plane: flags >> 1, jump: flags & 1 == 1)
		case ServerProt.clearMinimapFlag:
			return .clearMinimapFlag
		case ServerProt.setMinimapState:
			return .setMinimapState(try p.g1())

		case ServerProt.varpSmall:
			let id = try p.g2add()
			let v = try p.g1bneg()
			return .varp(id: id, value: Int32(v))
		case ServerProt.varpLarge:
			let v = try p.g4()
			let id = try p.g2add()
			return .varp(id: id, value: v)
		case ServerProt.varbitSmall:
			let v = try p.g1add()
			let id = try p.ig2()
			return .varbit(id: id, value: Int32(v))
		case ServerProt.varbitLarge:
			let v = try p.ig4()
			let id = try p.ig2add()
			return .varbit(id: id, value: v)
		case ServerProt.clientSetvarcSmall:
			p.track = try p.ig2()
			let v = try p.g1neg()
			let id = try p.ig2add()
			return .varc(id: id, value: Int32(v))
		case ServerProt.clientSetvarcLarge:
			p.track = try p.ig2add()
			let v = try p.g4()
			let id = try p.g2add()
			return .varc(id: id, value: v)
		case ServerProt.resetClientVarcache:
			return .resetClientVarcache
		case ServerProt.forceVarpRefresh:
			return .forceVarpRefresh

		case ServerProt.updateStat:
			let level = try p.g1add()
			let xp = try p.img4()
			let skill = try p.g1()
			return .updateStat(skill: skill, level: level, xp: xp)
		case ServerProt.updateRunenergy:
			return .runEnergy(try p.g1())
		case ServerProt.updateRunweight:
			return .runWeight(try p.g2b())
		case ServerProt.setInteraction:
			let cursor = nullable(try p.ig2add())
			let top = try p.g1()
			let slot = try p.g1()
			let option = try p.gjstr()
			return .setInteraction(slot: slot, option: option.lowercased() == "null" ? nil : option, cursor: cursor, top: top == 0)
		case ServerProt.setWalkText:
			return .setWalkText(p.remaining == 0 ? nil : try p.gjstr())

		case ServerProt.messageGame:
			return .gameMessage(try p.gjstr())
		case ServerProt.messagePrivate:
			let name = try p.g8()
			let top = try p.g2()
			let bot = try p.g3()
			let rights = try p.g1()
			return .privateMessage(name37: name, messageId: Int64(bot) + (Int64(top) << 32), rights: rights, text: try p.gdata(p.remaining))
		case ServerProt.messagePrivateEcho:
			let name = try p.g8()
			return .privateMessageEcho(name37: name, text: try p.gdata(p.remaining))
		case ServerProt.spotanimEntity:
			let delay = try p.g2()
			let height = try p.ig2()
			let target = try p.img4()
			let gfx = try p.ig2add()
			return .spotAnimEntity(delay: delay, height: height, target: target, gfx: gfx)
		case ServerProt.chatFilterSettings:
			return .chatFilterSettings(publicFilter: try p.g1(), privateFilter: try p.g1(), tradeFilter: try p.g1())
		case ServerProt.friendlistLoaded:
			return .friendlistLoaded(state: try p.g1())
		case ServerProt.updateFriendlist:
			// rt4: name37, world, then a flags byte; world != 0 adds the world name.
			let name = try p.g8()
			let world = try p.g2()
			let rank = try p.g1()
			let worldName = world > 0 ? try p.gjstr() : nil
			return .updateFriend(name37: name, world: world, rank: rank, worldName: worldName)
		case ServerProt.updateIgnorelist:
			var names: [Int64] = []
			while p.remaining >= 8 { names.append(try p.g8()) }
			return .ignoreList(names)
		case ServerProt.joinClanChat:
			let owner = try p.g8()
			if owner == 0 { return .joinClanChat(nil) }
			let name = try p.g8()
			let minKick = try p.g1b()
			let size = try p.g1()
			// rt4: a size of 255 changes only the header and leaves the member list alone.
			if size == 255 { return .joinClanChat(ClanChannelJoin(owner37: owner, name37: name, minKick: minKick, members: nil)) }
			var members: [ClanMember] = []
			for _ in 0..<size {
				let key = try p.g8()
				let world = try p.g2()
				let rank = try p.g1b()
				members.append(ClanMember(name37: key, world: world, rank: rank, worldName: try p.gjstr()))
			}
			return .joinClanChat(ClanChannelJoin(owner37: owner, name37: name, minKick: minKick, members: members))
		case ServerProt.updateClan:
			let raw = try p.g8()
			let world = try p.g2()
			let rank = try p.g1b()
			// rt4: the sign bit marks a removal, which carries no world name.
			if raw < 0 { return .updateClan(name37: raw & Int64.max, world: world, rank: rank, worldName: nil, removed: true) }
			return .updateClan(name37: raw, world: world, rank: rank, worldName: try p.gjstr(), removed: false)
		case ServerProt.messageClanchannel:
			let name = try p.g8()
			_ = try p.g1b()
			let clan = try p.g8()
			let top = try p.g2()
			let bot = try p.g3()
			let rights = try p.g1()
			return .clanMessage(name37: name, clan37: clan, messageId: Int64(bot) + (Int64(top) << 32), rights: rights, text: try p.gdata(p.remaining))
		case ServerProt.messageQuickchatPrivate:
			let name = try p.g8()
			let top = try p.g2()
			let bot = try p.g3()
			let rights = try p.g1()
			let phrase = try p.g2()
			return .quickChatPrivate(name37: name, messageId: Int64(bot) + (Int64(top) << 32), rights: rights, phrase: phrase, values: try p.gdata(p.remaining))
		case ServerProt.messageQuickchatPrivateEcho:
			let name = try p.g8()
			let phrase = try p.g2()
			return .quickChatPrivateEcho(name37: name, phrase: phrase, values: try p.gdata(p.remaining))
		case ServerProt.clanQuickChat:
			let name = try p.g8()
			_ = try p.g1b()
			let clan = try p.g8()
			let top = try p.g2()
			let bot = try p.g3()
			let rights = try p.g1()
			let phrase = try p.g2()
			return .quickChatClan(name37: name, clan37: clan, messageId: Int64(bot) + (Int64(top) << 32), rights: rights, phrase: phrase, values: try p.gdata(p.remaining))
		case ServerProt.lastLoginInfo:
			return .lastLoginInfo(ip: try p.img4())

		case ServerProt.ifOpentop:
			let type = try p.g1()
			let parent = try p.mg4()
			p.track = try p.g2add()
			let component = try p.g2()
			return .ifOpenSub(parent: parent, component: component, type: type)
		case ServerProt.ifOpensub:
			let id = try p.ig2add()
			let reset = try p.g1add()
			p.track = try p.ig2add()
			return .ifOpenTop(id: id, reset: reset)
		case ServerProt.ifClosesub:
			p.track = try p.g2()
			return .ifCloseSub(parent: try p.g4())
		case ServerProt.switchWidget:
			let source = try p.img4()
			p.track = try p.g2add()
			return .switchWidget(source: source, target: try p.img4())
		case ServerProt.gameFrameUnk:
			return .dialogAbort
		case ServerProt.deleteInventory:
			return .deleteInventory(inv: try p.ig2())
		case ServerProt.ifSethide:
			let hidden = try p.g1neg()
			p.track = try p.g2()
			let id = try p.ig4()
			return .ifSetHide(component: id, hidden: hidden == 1)
		case ServerProt.ifSettext1:
			let id = try p.mg4()
			let text = try p.gjstr()
			p.track = try p.g2add()
			return .ifSetText(component: id, text: text)
		case ServerProt.ifSettext2:
			p.track = try p.g2()
			let text = try p.gjstr()
			let id = try p.ig2add()
			return .ifSetText(component: Int32(id), text: text)
		case ServerProt.ifSettext3:
			let id = try p.ig2()
			p.track = try p.g2add()
			let text = try p.gjstr()
			return .ifSetText(component: Int32(id), text: text)
		case ServerProt.ifSetanim:
			let id = try p.mg4()
			let seq = try p.ig2b()
			p.track = try p.g2add()
			return .ifSetAnim(component: id, seq: seq)
		case ServerProt.ifSetmodel:
			let id = try p.ig4()
			p.track = try p.ig2add()
			let model = try p.g2add()
			return .ifSetModel(component: id, model: nullable(model))
		case ServerProt.ifSetnpchead:
			let npc = nullable(try p.g2add())
			let id = try p.ig4()
			p.track = try p.ig2()
			return .ifSetNpcHead(component: id, npc: npc)
		case ServerProt.ifSetplayerhead:
			p.track = try p.ig2add()
			return .ifSetPlayerHead(component: try p.img4())
		case ServerProt.ifSetobject:
			let zoom = try p.g4()
			let id = try p.mg4()
			let obj = nullable(try p.ig2add())
			p.track = try p.ig2()
			return .ifSetObject(component: id, obj: obj, zoomOrCount: zoom)
		case ServerProt.ifSetcolour:
			let id = try p.img4()
			p.track = try p.g2add()
			return .ifSetColour(component: id, colour: try p.ig2add())
		case ServerProt.ifSetposition:
			p.track = try p.g2add()
			let id = try p.ig4()
			let x = try p.g2b()
			let y = try p.g2badd()
			return .ifSetPosition(component: id, x: x, y: y)
		case ServerProt.ifSetangle:
			let pitch = try p.g2()
			p.track = try p.g2add()
			let scale = try p.ig2add()
			let yaw = try p.ig2add()
			let id = try p.g4()
			return .ifSetAngle(component: id, pitch: pitch, yaw: yaw, scale: scale)
		case ServerProt.ifSetscrollpos:
			let id = try p.mg4()
			let pos = try p.ig2()
			p.track = try p.g2()
			return .ifSetScrollPos(component: id, pos: pos)
		case ServerProt.setInterfaceSettings:
			p.track = try p.ig2()
			let end = nullable(try p.ig2())
			let id = try p.g4()
			let start = nullable(try p.g2add())
			let mask = try p.img4()
			return .ifSetEvents(component: id, start: start, end: end, mask: mask)
		case ServerProt.runCs2:
			p.track = try p.g2()
			let types = Array(try p.gjstr())
			var args = [ScriptArg](repeating: .int(0), count: types.count)
			for i in stride(from: types.count - 1, through: 0, by: -1) {
				args[i] = types[i] == "s" ? .string(try p.gjstr()) : .int(try p.g4())
			}
			let id = try p.g4()
			return .runClientScript(id: id, args: args)

		case ServerProt.updateInvFull:
			let component = try p.g4()
			var inv = try p.g2()
			if component < -70000 { inv += 32768 }
			let total = try p.g2()
			var items: [InvItem] = []
			items.reserveCapacity(total)
			for _ in 0..<total {
				var count = Int32(try p.g1sub())
				if count == 255 { count = try p.g4() }
				let id = try p.g2()
				items.append(InvItem(id: id - 1, count: count))
			}
			return .invFull(component: component, inv: inv, items: items)
		case ServerProt.updateInvPartial:
			let component = try p.g4()
			var inv = try p.g2()
			if component < -70000 { inv += 32768 }
			var slots: [(Int, InvItem)] = []
			while p.remaining > 0 {
				let slot = try p.gsmarts()
				let id = try p.g2()
				var count: Int32 = 0
				if id != 0 {
					count = Int32(try p.g1())
					if count == 255 { count = try p.g4() }
				}
				slots.append((slot, InvItem(id: id - 1, count: count)))
			}
			return .invPartial(component: component, inv: inv, slots: slots)
		case ServerProt.updateInvClear:
			return .invClear(component: try p.mg4())

		case ServerProt.midiSong:
			return .midiSong(nullable(try p.ig2add()))
		case ServerProt.midiJingle:
			let volume = try p.ig3()
			let id = nullable(try p.ig2())
			return .midiJingle(id: id, volume: volume)
		case ServerProt.synthSound:
			let id = try p.g2()
			let loops = try p.g1()
			let delay = try p.g2()
			return .synthSound(id: nullable(id), loops: loops, delay: delay)

		case ServerProt.widgetstructSetting:
			let value = try p.ig2add()
			let parent = try p.ig4()
			p.track = try p.g2add()
			let end = nullable(try p.ig2())
			let start = nullable(try p.g2add())
			return .widgetStructSetting(component: parent, start: start, end: end, param: value)
		case ServerProt.generateChatHeadFromBody:
			p.track = try p.g2add()
			let id = try p.mg4()
			let v1 = try p.ig2add()
			let v2 = try p.ig2()
			let v3 = try p.ig2add()
			return .chatHeadFromBody(component: id, kit1: v2, kit2: v3, kit3: v1)
		case ServerProt.interfaceAnimateRotate:
			let id = try p.mg4()
			p.track = try p.g2add()
			let pitchStep = try p.g2()
			let yawStep = try p.g2add()
			return .modelRotation(component: id, pitchStep: pitchStep, yawStep: yawStep)
		case ServerProt.updateUid192:
			_ = try p.gdata(24)
			return .updateRandomFile
		case ServerProt.reflectionCheatCheck:
			let size = try p.g1()
			let id = try p.g4()
			for _ in 0..<size { try ReflectionRequest.skip(&p) }
			return .reflectionCheck(id: id, entries: size)
		case ServerProt.urlOpen:
			return .urlOpen(Cp1252.decode(try p.gdata(p.remaining)))
		case ServerProt.setSettingsString:
			return .settingsString(try p.gjstr())

		case ServerProt.hintArrow:
			return .hintArrow(try HintArrow.decode(&p))
		case ServerProt.npcAnimSpecific:
			let npc = try p.ig2()
			let delay = try p.g1sub()
			let seq = try p.g2()
			return .npcAnim(npc: npc, delay: delay, seq: nullable(seq))
		case ServerProt.locAnimSpecific:
			let t = try p.g1sub()
			let seq = nullable(try p.g2())
			let pos = try p.g4()
			let packed = Int(UInt32(bitPattern: pos))
			return .locAnimSpecific(level: (packed >> 28) & 3, x: (packed >> 14) & 0x3FFF, z: packed & 0x3FFF, shape: t >> 2, rotation: t & 3, seq: seq)
		case ServerProt.resetAnims:
			return .resetAnims

		case ServerProt.cameraDetach:
			p.track = try p.g2()
			let x = try p.g1(), z = try p.g1()
			let height = try p.g2()
			let speed = try p.g1(), rotationSpeed = try p.g1()
			return .camMoveTo(x: x, z: z, height: height, speed: speed, rotationSpeed: rotationSpeed)
		case ServerProt.camLookat:
			p.track = try p.g2()
			let x = try p.g1(), z = try p.g1()
			let height = try p.g2()
			let speed = try p.g1(), rotationSpeed = try p.g1()
			return .camLookAt(x: x, z: z, height: height, speed: speed, rotationSpeed: rotationSpeed)
		case ServerProt.camForceangle:
			let yaw = try p.ig2()
			p.track = try p.g2()
			let pitch = try p.g2()
			return .camForceAngle(yaw: yaw, pitch: pitch)
		case ServerProt.camShake:
			p.track = try p.g2()
			let axis = try p.g1()
			let jitter = try p.g1(), amplitude = try p.g1(), frequency = try p.g1()
			let phase = try p.g2()
			return .camShake(axis: axis, jitter: jitter, amplitude: amplitude, frequency: frequency, phase: phase)
		case ServerProt.camReset:
			p.track = try p.g2()
			return .camReset

		case ServerProt.grandExchangeOffers:
			let slot = try p.g1()
			let status = try p.g1b()
			if status == 0 {
				// rt4 reads no further for an empty slot (the server still pads the packet to its fixed size).
				p.offset = p.data.count
				return .grandExchangeOffer(slot: slot, offer: nil)
			}
			let item = try p.g2()
			let price = try p.g4(), count = try p.g4(), done = try p.g4(), gold = try p.g4()
			let flags = status & 0xFF
			return .grandExchangeOffer(slot: slot, offer: StockOffer(status: flags & 7, type: (flags & 8) == 8 ? 1 : 0, item: item,
			                                                        price: price, count: count, completedCount: done, completedGold: gold))

		case ServerProt.logout:
			return .logout
		case ServerProt.updateRebootTimer:
			return .rebootTimer(seconds: try p.g2() * 30 / 50)
		default:
			return nil
		}
	}
}

extension RebuildNormal {
	fileprivate func consumingAll(_ p: inout Packet) -> RebuildNormal {
		p.offset = p.data.count
		return self
	}
}

/// Sub-packets of the zone update bus (rt4 `Protocol.readZonePacket`).
/// Positions are 0-7 within the current zone unless noted.
public enum ZoneUpdate: Equatable {
	case locAdd(x: Int, z: Int, id: Int, shape: Int, rotation: Int)
	case locDel(x: Int, z: Int, shape: Int, rotation: Int)
	case locAnim(x: Int, z: Int, shape: Int, rotation: Int, seq: Int)
	case locAddChange(x: Int, z: Int, shape: Int, rotation: Int, raw: [Int])
	/// `hiddenFrom` is the player index rt4 skips (the dropper's own copy).
	case objAdd(x: Int, z: Int, id: Int, count: Int, hiddenFrom: Int)
	case objDel(x: Int, z: Int, id: Int)
	case objCount(x: Int, z: Int, id: Int, oldCount: Int, newCount: Int)
	/// Ground item visible to this player (rt4 adds it like a normal drop).
	case objReveal(x: Int, z: Int, id: Int, count: Int)
	case spotAnim(x: Int, z: Int, id: Int, height: Int, delay: Int)
	case soundArea(x: Int, z: Int, id: Int, radius: Int, loops: Int, delay: Int)
	/// The three projectile variants; fields kept raw until the renderer needs them.
	case projectile(opcode: Int, raw: [Int])

	static let opcodes: Set<Int> = [
		ServerProt.locAdd, ServerProt.locDel, ServerProt.locAnim, ServerProt.locAddChange,
		ServerProt.objAdd, ServerProt.objDel, ServerProt.objCount, ServerProt.objReveal,
		ServerProt.spotanimSpecific, ServerProt.soundArea,
		ServerProt.mapProjanim, ServerProt.mapProjanim2, ServerProt.mapProjanim3,
	]

	static func pos(_ b: Int) -> (Int, Int) { ((b >> 4) & 7, b & 7) }

	public struct Unknown: Error, CustomStringConvertible {
		public let opcode: Int
		public var description: String { "unknown zone sub-packet \(opcode)" }
	}

	static func decode(_ op: Int, _ p: inout Packet) throws -> ZoneUpdate {
		switch op {
		case ServerProt.locDel:
			let t = try p.g1neg()
			let (x, z) = pos(try p.g1())
			return .locDel(x: x, z: z, shape: t >> 2, rotation: t & 3)
		case ServerProt.locAdd:
			let t = try p.g1add()
			let (x, z) = pos(try p.g1())
			return .locAdd(x: x, z: z, id: try p.g2add(), shape: t >> 2, rotation: t & 3)
		case ServerProt.locAnim:
			let (x, z) = pos(try p.g1sub())
			let t = try p.g1sub()
			return .locAnim(x: x, z: z, shape: t >> 2, rotation: t & 3, seq: nullable(try p.ig2()))
		case ServerProt.locAddChange:
			let t = try p.g1()
			let (x, z) = pos(try p.g1())
			let raw = [try p.g1badd(), try p.g1badd(), try p.g1bsub(), try p.g2add(), try p.ig2(), try p.g1b(), try p.g2(), try p.ig2badd()]
			return .locAddChange(x: x, z: z, shape: t >> 2, rotation: t & 3, raw: raw)
		case ServerProt.objAdd:
			let hiddenFrom = try p.ig2add()
			let (x, z) = pos(try p.g1neg())
			let count = try p.ig2()
			let id = try p.ig2()
			return .objAdd(x: x, z: z, id: id, count: count, hiddenFrom: hiddenFrom)
		case ServerProt.objDel:
			let (x, z) = pos(try p.g1sub())
			return .objDel(x: x, z: z, id: try p.g2() & 0x7FFF)
		case ServerProt.objCount:
			let (x, z) = pos(try p.g1())
			return .objCount(x: x, z: z, id: try p.g2() & 0x7FFF, oldCount: try p.g2(), newCount: try p.g2())
		case ServerProt.objReveal:
			let id = try p.ig2()
			let (x, z) = pos(try p.g1())
			let count = try p.g2add()
			return .objReveal(x: x, z: z, id: id, count: count)
		case ServerProt.spotanimSpecific:
			let (x, z) = pos(try p.g1())
			return .spotAnim(x: x, z: z, id: try p.g2(), height: try p.g1(), delay: try p.g2())
		case ServerProt.soundArea:
			let (x, z) = pos(try p.g1())
			let id = ServerMessage.nullable(try p.g2())
			let packed = try p.g1()
			let delay = try p.g1()
			return .soundArea(x: x, z: z, id: id, radius: (packed >> 4) & 0xF, loops: packed & 7, delay: delay)
		case ServerProt.mapProjanim:
			var raw = [try p.g1(), try p.g1b(), try p.g1b(), try p.g2b(), try p.g2b(), try p.g2(), try p.g1b(), try p.g1(), try p.g2(), try p.g2(), try p.g1(), try p.g1()]
			if raw[10] == 255 { raw[10] = -1 }
			return .projectile(opcode: op, raw: raw)
		case ServerProt.mapProjanim2, ServerProt.mapProjanim3:
			let raw = [try p.g1(), try p.g1b(), try p.g1b(), try p.g2b(), try p.g2(), try p.g1(), try p.g1(), try p.g2(), try p.g2(), try p.g1(), try p.g1()]
			return .projectile(opcode: op, raw: raw)
		default:
			throw Unknown(opcode: op)
		}
	}
}


extension ServerMessage.HintArrow {
	/// rt4 `Protocol` HINT_ARROW. The server always sends the full 9 bytes (a cleared marker has type 0).
	static func decode(_ p: inout Packet) throws -> ServerMessage.HintArrow {
		let flags = try p.g1()
		var m = ServerMessage.HintArrow(slot: flags >> 6, type: flags & 0x3F, sprite: try p.g1(), target: -1)
		var offset = (x: 0, z: 0)
		if m.type == 1 || m.type == 10 {
			m.target = try p.g2()
			_ = try p.gdata(3)
		} else if m.type >= 2 && m.type <= 6 {
			// rt4 turns types 3...6 into tile markers on the east, west, south or north edge of the tile.
			switch m.type {
			case 2: offset = (64, 64)
			case 3: offset = (0, 64)
			case 4: offset = (128, 64)
			case 5: offset = (64, 0)
			default: offset = (64, 128)
			}
			m.type = 2
			m.tileX = try p.g2()
			m.tileZ = try p.g2()
			m.height = try p.g1()
		}
		m.offsetX = offset.x
		m.offsetZ = offset.z
		let model = try p.g2()
		m.model = model == 65535 ? -1 : model
		// A cleared marker carries nothing else; whatever the server padded the packet with is dropped.
		p.offset = p.data.count
		return m
	}
}

/// One check of a REFLECTION_CHECK packet (rt4 `ReflectionCheck.push`). The client has no Java reflection to answer
/// with, so a check is only skipped over and reported as failed (rt4 reports a missing class as -1).
enum ReflectionRequest {
	static func skip(_ p: inout Packet) throws {
		let type = try p.g1()
		if type == 0 || type == 1 || type == 2 {
			_ = try p.gjstr()
			_ = try p.gjstr()
			if type == 1 { _ = try p.g4() }
		} else if type == 3 || type == 4 {
			_ = try p.gjstr()
			_ = try p.gjstr()
			let n = try p.g1()
			for _ in 0..<n { _ = try p.gjstr() }
			if type == 3 {
				for _ in 0..<n {
					let len = try p.g4()
					_ = try p.gdata(Int(len))
				}
			}
		}
	}
}
