/// Client -> server game packets. Bodies are ported from rt4's senders
/// (`ClientProt` helpers, `Cheat.java`, `Protocol` keepalive).
public enum ClientMessage {
	/// rt4 sends NO_TIMEOUT every 50 client cycles (~1 s) while idle.
	case keepAlive
	/// `::command` from the chatbox (rt4 `Cheat`), without the leading "::".
	case command(String)
	/// Public chat (rt4 `ScriptRunner` 5008): `colour` 0...11, `effect` 0...5, `text` already
	/// packed by `WordPack.encode` (length smart + huffman bytes).
	case publicChat(colour: Int, effect: Int, text: [UInt8])
	/// Private message (rt4 `ScriptRunner` 5009) to `name37`; `text` packed by `WordPack.encode`.
	case privateMessage(name37: Int64, text: [UInt8])
	/// Walk to a world tile. `path` is the client pathfinder's turn points
	/// before `dest`, in walking order (world coords); empty lets the server
	/// path to `dest` itself.
	case walk(destX: Int, destZ: Int, path: [(x: Int, z: Int)] = [], ctrlRun: Bool = false, minimap: Bool = false)
	/// IF_BUTTON1...IF_BUTTON10: option `op` (1...10) of component `component`
	/// (`interface << 16 | index`); `child` is the CS2-created child or the
	/// inventory slot, -1 for the component itself (rt4 `ClientProt.method4512`).
	case ifButton(op: Int, component: Int, child: Int)
	/// Opcode 10: an if1 button (button types 1, 4, 5) pressed (rt4 `MiniMenu` actions 8/51/59).
	case ifButtonLegacy(component: Int)
	/// Opcode 132: an if1 "continue" button (button type 6; rt4 `MiniMenu.method10`).
	case ifContinue(component: Int, child: Int)
	/// CLOSE_MODAL (rt4 `ClientProt.closeWidget`).
	case closeModal
	/// FRIENDLIST_ADD / FRIENDLIST_DEL / IGNORELIST_ADD / IGNORELIST_DEL (rt4 `FriendsList.add/remove`,
	/// `IgnoreList.add/remove`): the base-37 name.
	case friendAdd(Int64), friendDel(Int64), ignoreAdd(Int64), ignoreDel(Int64)
	/// FRIEND_SETRANK (rt4 `FriendsList.setRank`): friends-chat rank for a friend.
	case friendSetRank(name37: Int64, rank: Int)
	/// CLAN_JOINCHAT_LEAVECHAT (rt4 `ClanChat.join/leave`): join the channel owned by `name37`, 0 leaves.
	case clanJoinLeave(name37: Int64)
	/// CLAN_KICKUSER (rt4 `ClanChat.kick`).
	case clanKick(name37: Int64)
	/// Opcode 77: walk toward an interaction target; same layout as `walk` (rt4 `method3502` with argument 2).
	case walkInteract(destX: Int, destZ: Int, path: [(x: Int, z: Int)] = [], ctrlRun: Bool = false)
	/// OPNPC1...5 (`option` 1...5) on npc index `index` (rt4 `MiniMenu` actions 17, 16, 4, 19, 2).
	case opNpc(option: Int, index: Int)
	/// Examine an npc by its (resolved) type id (rt4 action 1007).
	case examineNpc(typeId: Int)
	/// A player option: `action` is the `MiniMenu` code (30 option 1, 6, 31 follow, 29 trade, 10, 44, 37, 57).
	case opPlayer(action: Int, index: Int)
	/// OPLOC1...5 on loc `id` at world tile (`x`, `z`).
	case opLoc(option: Int, id: Int, x: Int, z: Int)
	/// Examine a loc by type id (rt4 action 1004).
	case examineLoc(id: Int)
	/// OPOBJ1...5 on ground item `id` at world tile (`x`, `z`).
	case opObj(option: Int, id: Int, x: Int, z: Int)
	/// Examine a ground item by type id (rt4 action 1002).
	case examineObj(id: Int)
	/// RESUME_P_COUNTDIALOG / RESUME_P_NAMEDIALOG / RESUME_P_STRINGDIALOG.
	case resumeCount(Int32)
	case resumeName(String)
	case resumeString(String)
	/// rt4 SOUND_SONGEND: the song that finished, so the server can pick the next one.
	case songEnd(Int)

	// MARK: targeting (rt4 `MiniMenu.doAction`, "Use" and spell target modes)

	/// "Use item -> npc" (action 26, opcode 115). `component`/`slot`/`itemId` are the selected inventory item.
	case useItemOnNpc(component: Int, slot: Int, itemId: Int, npc: Int)
	/// "Use item -> loc" (action 14, opcode 134) at world tile (`x`, `z`).
	case useItemOnLoc(component: Int, slot: Int, itemId: Int, locId: Int, x: Int, z: Int)
	/// "Use item -> ground item" (action 33, opcode 101).
	case useItemOnObj(component: Int, slot: Int, itemId: Int, objId: Int, x: Int, z: Int)
	/// "Use item -> player" (action 1, opcode 248).
	case useItemOnPlayer(component: Int, slot: Int, itemId: Int, player: Int)
	/// "Use item -> inventory item" (action 40, opcode 27).
	case useItemOnItem(component: Int, slot: Int, itemId: Int, targetComponent: Int, targetSlot: Int, targetItem: Int)
	/// Spell (or other target-mode component, `child` = its created-component index, -1 when static) on an npc (action 45, opcode 239).
	case spellOnNpc(component: Int, child: Int, npc: Int)
	/// Spell on a loc (action 38, opcode 233).
	case spellOnLoc(component: Int, child: Int, locId: Int, x: Int, z: Int)
	/// Spell on a ground item (action 39, opcode 73).
	case spellOnObj(component: Int, child: Int, objId: Int, x: Int, z: Int)
	/// Spell on a player (action 15, opcode 195).
	case spellOnPlayer(component: Int, child: Int, player: Int)
	/// Spell on an inventory item (action 3, opcode 253).
	case spellOnItem(component: Int, child: Int, targetComponent: Int, targetSlot: Int, targetItem: Int)
	/// Spell on another interface component (action 12, opcode 82).
	case spellOnComponent(component: Int, child: Int, targetComponent: Int, targetChild: Int)
	/// Spell on a ground tile (action 11 with key 1, opcode 131) at world tile (`x`, `z`).
	case spellOnTile(component: Int, child: Int, x: Int, z: Int)
	/// An inventory item option (rt4 `MiniMenu` actions 47, 5, 43, 35, 58 for the item's `iops` 1...5 and
	/// 25, 23, 48, 7, 13 for the component's own `invOptions`).
	case invItemOp(action: Int, component: Int, slot: Int, itemId: Int)
	/// MOVE_ITEM (opcode 231): an inventory drag from slot `from` to slot `to`; `insert` is rt4 "inserting" (shift) mode.
	case moveItem(component: Int, from: Int, to: Int, insert: Bool)
	/// IF_DRAG (opcode 79): a draggable if3 component released over another one.
	case ifDrag(component: Int, child: Int, targetComponent: Int, targetChild: Int)

	/// rt4 `ClientProt.method4512`: the opcode for IF_BUTTON1...10.
	static let ifButtonOpcodes = [155, 196, 124, 199, 234, 168, 166, 64, 53, 9]

	public func encode(_ cipher: inout IsaacRandom) -> [UInt8] {
		var p = Packet(capacity: 64)
		func op(_ o: Int) { p.p1(o + cipher.nextKey()) }
		switch self {
		case .keepAlive:
			op(ClientProt.noTimeout)
		case .command(let c):
			op(ClientProt.clientCheat)
			p.p1(Cp1252.encode(c).count + 1)
			p.pjstr(c)
		case let .publicChat(colour, effect, text):
			op(ClientProt.publicChat)
			p.p1(text.count + 2)
			p.p1(colour)
			p.p1(effect)
			p.pdata(text)
		case let .privateMessage(name37, text):
			op(ClientProt.privateMessage)
			p.p1(text.count + 8)
			p.p8(name37)
			p.pdata(text)
		case let .ifButton(n, component, child):
			op(Self.ifButtonOpcodes[min(max(n, 1), 10) - 1])
			p.p4(component)
			p.p2(child)
		case .ifButtonLegacy(let component):
			op(10)
			p.p4(component)
		case let .ifContinue(component, child):
			// imp4(component), ip2(child)
			op(132)
			let v = Int32(truncatingIfNeeded: component)
			p.p1(Int(v >> 8)); p.p1(Int(v)); p.p1(Int(v >> 24)); p.p1(Int(v >> 16))
			p.ip2(child)
		case .closeModal:
			op(ClientProt.closeModal)
		case .friendAdd(let n): op(ClientProt.friendlistAdd); p.p8(n)
		case .friendDel(let n): op(ClientProt.friendlistDel); p.p8(n)
		case .ignoreAdd(let n): op(ClientProt.ignorelistAdd); p.p8(n)
		case .ignoreDel(let n): op(ClientProt.ignorelistDel); p.p8(n)
		case let .friendSetRank(n, rank):
			op(ClientProt.friendSetrank)
			p.p1add(rank)
			p.p8(n)
		case .clanJoinLeave(let n): op(ClientProt.clanJoinchatLeavechat); p.p8(n)
		case .clanKick(let n): op(ClientProt.clanKickuser); p.p8(n)
		case .songEnd(let id):
			op(ClientProt.soundSongend)
			p.p4(Int32(truncatingIfNeeded: id))
		case .resumeCount(let v):
			op(ClientProt.resumePCountdialog)
			p.p4(v)
		case .resumeName(let name):
			op(ClientProt.resumePNamedialog)
			p.p8(Base37.encode(name))
		case .resumeString(let s):
			op(ClientProt.resumePStringdialog)
			p.p1(Cp1252.encode(s).count + 1)
			p.pjstr(s)
		case let .walkInteract(destX, destZ, path, ctrlRun):
			let points = Array((path.map { ($0.x, $0.z) } + [(destX, destZ)]).prefix(25))
			op(ClientProt.moveInteract)
			p.p1(points.count * 2 + 3)
			p.p1add(ctrlRun ? 1 : 0)
			let (fx, fz) = points[0]
			p.p2(fx)
			p.p2add(fz)
			for (x, z) in points.dropFirst() {
				p.p1add(x - fx)
				p.p1sub(z - fz)
			}
		case let .opNpc(option, index):
			// rt4 `MiniMenu.doAction` NPC_ACTION_1...5.
			op(ClientProt.opNpc[min(max(option, 1), 5) - 1])
			switch option {
			case 2: p.ip2add(index)
			case 3: p.p2add(index)
			case 4: p.p2(index)
			default: p.ip2(index)
			}
		case .examineNpc(let typeId):
			op(ClientProt.examineNpc)
			p.p2(typeId)
		case let .opPlayer(action, index):
			switch action {
			case 30: op(68); p.ip2add(index)
			case 31: op(71); p.ip2add(index)
			case 29: op(180); p.ip2add(index)
			case 37: op(114); p.ip2add(index)
			case 57: op(175); p.p2add(index)
			case 44: op(133); p.ip2(index)
			case 6: op(106); p.p2(index)
			default: op(4); p.ip2(index) // action 10
			}
		case let .opLoc(option, id, x, z):
			op(ClientProt.opLoc[min(max(option, 1), 5) - 1])
			switch option {
			case 1: p.ip2(x); p.p2add(id); p.p2(z)
			case 2: p.ip2add(z); p.ip2(x); p.p2(id)
			case 3: p.ip2add(id); p.ip2add(z); p.ip2(x)
			case 4: p.ip2(z); p.ip2add(x); p.p2(id)
			default: p.ip2add(id); p.ip2add(x); p.ip2add(z)
			}
		case .examineLoc(let id):
			op(ClientProt.examineLoc)
			p.ip2add(id)
		case let .opObj(option, id, x, z):
			op(ClientProt.opObj[min(max(option, 1), 5) - 1])
			switch option {
			case 1: p.p2(id); p.ip2(x); p.ip2add(z)
			case 2: p.ip2(z); p.p2(x); p.ip2add(id)
			case 3: p.ip2(x); p.p2(id); p.ip2add(z)
			case 4: p.p2(id); p.p2(x); p.ip2(z)
			default: p.p2add(x); p.ip2add(id); p.ip2(z)
			}
		case .examineObj(let id):
			op(ClientProt.examineObj)
			p.ip2add(id)
		case let .useItemOnNpc(c, slot, item, npc):
			op(115)
			p.mp4(c); p.ip2(slot); p.ip2(npc); p.ip2add(item)
		case let .useItemOnLoc(c, slot, item, loc, x, z):
			op(134)
			p.p2add(x); p.p2(item); p.ip2(z); p.p2(slot); p.mp4(c); p.p2add(loc)
		case let .useItemOnObj(c, slot, item, obj, x, z):
			op(101)
			p.ip2add(x); p.ip2(slot); p.ip2(item); p.ip2(obj); p.ip2add(z); p.mp4(c)
		case let .useItemOnPlayer(c, slot, item, player):
			op(248)
			p.ip2add(player); p.p2(item); p.p2(slot); p.mp4(c)
		case let .useItemOnItem(c, slot, item, tc, ts, ti):
			op(27)
			p.p2(slot); p.ip4(tc); p.ip2(ts); p.ip4(c); p.ip2add(item); p.ip2add(ti)
		case let .spellOnNpc(c, child, npc):
			op(239)
			p.ip4(c); p.p2add(child); p.ip2add(npc)
		case let .spellOnLoc(c, child, loc, x, z):
			op(233)
			p.ip2add(z); p.p2add(x); p.ip2add(child); p.imp4(c); p.p2add(loc)
		case let .spellOnObj(c, child, obj, x, z):
			op(73)
			p.imp4(c); p.p2(z); p.ip2add(obj); p.ip2add(x); p.ip2(child)
		case let .spellOnPlayer(c, child, player):
			op(195)
			p.p2add(child); p.ip4(c); p.ip2add(player)
		case let .spellOnItem(c, child, tc, ts, ti):
			op(253)
			p.ip4(c); p.ip2add(ts); p.ip4(tc); p.p2add(ti); p.ip2(child)
		case let .spellOnComponent(c, child, tc, tchild):
			op(82)
			p.p2(child); p.imp4(tc); p.p4(c); p.ip2add(tchild)
		case let .spellOnTile(c, child, x, z):
			op(131)
			p.mp4(c); p.p2add(x); p.ip2add(child); p.p2add(z)
		case let .invItemOp(action, c, slot, item):
			switch action {
			case 47: op(156); p.ip2add(slot); p.p2add(item); p.ip4(c)
			case 5: op(55); p.ip2(item); p.p2add(slot); p.imp4(c)
			case 43: op(153); p.ip4(c); p.ip2(slot); p.ip2(item)
			case 35: op(161); p.ip4(c); p.ip2add(item); p.ip2add(slot)
			case 58: op(135); p.p2add(item); p.p2add(slot); p.mp4(c)
			case 25: op(81); p.p2add(slot); p.p2(item); p.imp4(c)
			case 23: op(206); p.p2add(item); p.ip2(slot); p.ip4(c)
			case 48: op(154); p.ip2(slot); p.imp4(c); p.ip2add(item)
			case 7: op(85); p.imp4(c); p.p2(slot); p.p2add(item)
			default: op(6); p.p4(c); p.p2add(slot); p.ip2(item) // action 13
			}
		case let .moveItem(c, from, to, insert):
			op(231)
			p.p2(to); p.ip4(c); p.p2add(from); p.p1sub(insert ? 1 : 0)
		case let .ifDrag(c, child, tc, tchild):
			op(79)
			p.mp4(c); p.ip2(tchild); p.p4(tc); p.ip2(child)
		case let .walk(destX, destZ, path, ctrlRun, minimap):
			// rt4 (`ClientProt` walk sender) sends the first waypoint as an
			// absolute tile, then the following ones as offsets from it
			// (x as add, z as sub), truncated to 25 points.
			let points = Array((path.map { ($0.x, $0.z) } + [(destX, destZ)]).prefix(25))
			let steps = points.count
			op(minimap ? ClientProt.moveMinimapclick : ClientProt.moveGameclick)
			p.p1(steps * 2 + 3 + (minimap ? 14 : 0))
			p.p1add(ctrlRun ? 1 : 0)
			let (fx, fz) = points[0]
			p.p2(fx)
			p.p2add(fz)
			for (x, z) in points.dropFirst() {
				p.p1add(x - fx)
				p.p1sub(z - fz)
			}
			if minimap {
				// rt4 appends 14 bytes of camera/minimap state; zeros are accepted.
				p.pdata([UInt8](repeating: 0, count: 14))
			}
		}
		return p.written
	}
}

extension Packet {
	/// rt4 `Buffer.mp4`: a 4-byte value as bytes 2, 3, 0, 1 (middle-endian).
	mutating func mp4(_ v: Int) {
		p1(v >> 16); p1(v >> 24); p1(v); p1(v >> 8)
	}

	/// rt4 `Buffer.imp4`: a 4-byte value as bytes 1, 0, 3, 2 (inverse middle-endian).
	mutating func imp4(_ v: Int) {
		p1(v >> 8); p1(v); p1(v >> 24); p1(v >> 16)
	}
}
