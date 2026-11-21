/// A component as scripts see it: the static component (`child == -1`, id =
/// `interface << 16 | index`) or a dynamic child made by `cc_create`
/// (rt4 `Component.createdComponentId`).
public struct ComponentRef: Hashable {
	public var id: Int
	public var child: Int
	public init(id: Int, child: Int = -1) { self.id = id; self.child = child }
}

/// Component setters (rt4 `ScriptRunner` opcodes 1000-1399). Arguments arrive
/// in stack push order (first pushed first), except where noted.
public enum ComponentSetter {
	/// [x, y, xMode, yMode] (modes clamped to 0...5)
	case position
	/// [width, height, widthMode, heightMode] (modes clamped to 0...4)
	case size
	case hidden, aspect, noClickThrough
	case scrollPos, rgb, filled, trans, lineWidth, sprite, angle2d, spriteTiling, model
	/// [xOffset, zOffset, xAngle, yAngle, yOffset, zoom]
	case modelRotation
	case animation, modelOrtho, font
	/// [halign, valign, linespacing]
	case textAlignment
	case shadowed, outlineThickness, shadowColor, vFlip, hFlip, scrollMax
	/// op 1121, two shorts (aShort11/aShort10)
	case opcode1121
	case hasAlpha, modelZoom
	/// [obj, count, drawText(0/1)]
	case item
	case npcHead, selfHead, otherPlayerHead, playerFull
	/// [interface component id, child index] (child -1 = static)
	case draggable
	case dragRenderBehaviour, dragDeadZone, dragDeadTime
	/// op 1308: [first popped, second popped]
	case opcode1308
	/// op 1309: [slot (0-based), value]
	case opEnabled
}

/// Component getters (opcodes 1500-1899 / 2500-2899).
public enum ComponentGetter {
	case x, y, width, height, hidden, layer
	case scrollX, scrollY, scrollMaxH, scrollMaxV, modelZoom, modelXAngle, modelYOffset, modelYAngle, alpha, modelXOffset, modelZOffset, spriteId
	case objId, objCount, childIndex, targetMask
}

public enum ComponentStringSetter { case text, optionBase, optionCircumfix }

/// One game-state opcode the interpreter cannot answer by itself. `name` says
/// what it is; stack effects are fixed by the spec, so the host only has to
/// supply values. Missing results are padded with 0 / "".
public struct HostOpSpec {
	public let opcode: Int
	public let name: String
	public let ints: Int, strings: Int, outInts: Int, outStrings: Int
}

public struct HostResult {
	public var ints: [Int32] = []
	public var strings: [String] = []
	public init(ints: [Int32] = [], strings: [String] = []) { self.ints = ints; self.strings = strings }
}

/// Everything the CS2 interpreter needs from the outside world.
public protocol ScriptHost: AnyObject {
	// MARK: variables
	func varp(_ id: Int) -> Int32
	/// rt4 `VarpDomain.method2766` (client-side set; the host fires transmits).
	func setVarp(_ id: Int, _ value: Int32)
	func varc(_ id: Int) -> Int32
	func setVarc(_ id: Int, _ value: Int32)
	func varcstr(_ id: Int) -> String
	func setVarcstr(_ id: Int, _ value: String)

	// MARK: component tree
	func componentExists(_ id: Int) -> Bool
	/// rt4 `Cs1ScriptRunner.method1015` (CS2 3108 / 3109): arms the drag of a component grabbed at (offsetX, offsetY).
	func armDrag(_ ref: ComponentRef, offsetX: Int, offsetY: Int)
	func createChild(of parent: Int, type: Int, index: Int) throws -> ComponentRef
	func deleteChild(_ ref: ComponentRef) throws
	func deleteChildren(of parent: Int)
	/// rt4 `InterfaceList.method1418`: the child `index` of `id` (-1 = id itself).
	func child(of id: Int, index: Int) -> ComponentRef?
	/// Number of leading non-nil dynamic children (opcode 2703).
	func childCount(of id: Int) -> Int
	/// Opcodes 2702/2704/2705: is something open at `parent` (optionally with this interface)?
	func isInterfaceOpen(parent: Int, interface: Int?) -> Bool

	// MARK: component properties
	func set(_ ref: ComponentRef, _ setter: ComponentSetter, _ args: [Int32])
	func setString(_ ref: ComponentRef, _ setter: ComponentStringSetter, _ value: String)
	/// Opcode 1300: `slot` 0...9.
	func setOption(_ ref: ComponentRef, slot: Int, _ text: String)
	func clearOptions(_ ref: ComponentRef)
	/// Hook setters 1400-1429. `args` nil clears the hook; `triggers` are the
	/// varp/inv/stat/varc ids of a `...Y` hook.
	func setHook(_ ref: ComponentRef, _ hook: String, args: [ServerMessage.ScriptArg]?, triggers: [Int32]?)
	func get(_ ref: ComponentRef, _ getter: ComponentGetter) -> Int32
	func text(of ref: ComponentRef) -> String
	func option(of ref: ComponentRef, slot: Int) -> String
	func optionBase(of ref: ComponentRef) -> String

	// MARK: fonts
	/// rt4 `FontMetrics.getParagraphLineCount`.
	func paragraphLineCount(font: Int, text: String, width: Int) -> Int32
	/// rt4 `FontMetrics.getMaxLineWidth`.
	func maxLineWidth(font: Int, text: String, width: Int) -> Int32

	// MARK: everything else (chat, friends, inventories, world map, camera, ...)
	func perform(_ op: HostOpSpec, ints: [Int32], strings: [String]) -> HostResult
}

/// Defaults: host answers 0 / "" / nothing, components do not exist.
extension ScriptHost {
	public func varp(_ id: Int) -> Int32 { 0 }
	public func setVarp(_ id: Int, _ value: Int32) {}
	public func varc(_ id: Int) -> Int32 { 0 }
	public func setVarc(_ id: Int, _ value: Int32) {}
	public func varcstr(_ id: Int) -> String { "" }
	public func setVarcstr(_ id: Int, _ value: String) {}
	public func componentExists(_ id: Int) -> Bool { false }
	public func armDrag(_ ref: ComponentRef, offsetX: Int, offsetY: Int) {}
	public func createChild(of parent: Int, type: Int, index: Int) throws -> ComponentRef { ComponentRef(id: parent, child: index) }
	public func deleteChild(_ ref: ComponentRef) throws {}
	public func deleteChildren(of parent: Int) {}
	public func child(of id: Int, index: Int) -> ComponentRef? { nil }
	public func childCount(of id: Int) -> Int { 0 }
	public func isInterfaceOpen(parent: Int, interface: Int?) -> Bool { false }
	public func set(_ ref: ComponentRef, _ setter: ComponentSetter, _ args: [Int32]) {}
	public func setString(_ ref: ComponentRef, _ setter: ComponentStringSetter, _ value: String) {}
	public func setOption(_ ref: ComponentRef, slot: Int, _ text: String) {}
	public func clearOptions(_ ref: ComponentRef) {}
	public func setHook(_ ref: ComponentRef, _ hook: String, args: [ServerMessage.ScriptArg]?, triggers: [Int32]?) {}
	public func get(_ ref: ComponentRef, _ getter: ComponentGetter) -> Int32 { 0 }
	public func text(of ref: ComponentRef) -> String { "" }
	public func option(of ref: ComponentRef, slot: Int) -> String { "" }
	public func optionBase(of ref: ComponentRef) -> String { "" }
	public func paragraphLineCount(font: Int, text: String, width: Int) -> Int32 { 1 }
	public func maxLineWidth(font: Int, text: String, width: Int) -> Int32 { Int32(text.unicodeScalars.count * 6) }
	public func perform(_ op: HostOpSpec, ints: [Int32], strings: [String]) -> HostResult { HostResult() }
}

/// Everything about one script invocation that hook placeholders refer to
/// (rt4 `HookRequest`).
public struct ScriptRequest {
	public var args: [ServerMessage.ScriptArg]
	public var mouseX = 0, mouseY = 0
	public var source: ComponentRef?
	public var op = 0
	public var target: ComponentRef?
	public var keyCode = 0, keyChar = 0
	public var opBase = ""

	public init(args: [ServerMessage.ScriptArg]) { self.args = args }
}

public enum ScriptError: Error, CustomStringConvertible {
	case unportedOpcode(opcode: Int, script: Int, name: String?, pc: Int)
	case failure(String, script: Int, name: String?, pc: Int, opcode: Int)

	public var description: String {
		switch self {
		case let .unportedOpcode(op, s, n, pc): return "CS2 unported opcode \(op) in script \(s) (\(n ?? "?")) at pc \(pc)"
		case let .failure(m, s, n, pc, op): return "CS2 error '\(m)' in script \(s) (\(n ?? "?")) at pc \(pc) opcode \(op)"
		}
	}
}

/// Specs for the opcodes routed to `ScriptHost.perform`.
enum HostOps {
	static let table: [Int: HostOpSpec] = {
		var t: [Int: HostOpSpec] = [:]
		func h(_ op: Int, _ name: String, i: Int = 0, s: Int = 0, oi: Int = 0, os: Int = 0) {
			t[op] = HostOpSpec(opcode: op, name: name, ints: i, strings: s, outInts: oi, outStrings: os)
		}
		// appearance (player designer)
		h(403, "setBaseIdentikit", i: 2); h(404, "setBaseColour", i: 2); h(410, "setFemale", i: 1)
		// misc client actions
		h(3100, "chatMessage", s: 1); h(3101, "animateSelf", i: 2); h(3103, "closeWidget")
		h(3104, "sendIntegerInput", s: 1); h(3105, "sendNameInput", s: 1); h(3106, "sendStringInput", s: 1)
		h(3107, "clickPlayerOption", i: 1, s: 1); h(3108, "runCs1OnComponent", i: 3); h(3109, "runCs1OnActive", i: 2); h(3110, "sendShortPacket111", i: 1)
		h(3200, "playSoundEffect", i: 3); h(3201, "playSong", i: 1); h(3202, "playJingle", i: 2)
		// player state
		h(3300, "clientCycle", oi: 1); h(3301, "invItemId", i: 2, oi: 1); h(3302, "invItemCount", i: 2, oi: 1)
		h(3303, "invTotalCount", i: 2, oi: 1); h(3304, "invSize", i: 1, oi: 1)
		h(3305, "statLevel", i: 1, oi: 1); h(3306, "statBaseLevel", i: 1, oi: 1); h(3307, "statXp", i: 1, oi: 1)
		h(3308, "myCoord", oi: 1); h(3312, "isMembersWorld", oi: 1); h(3316, "clientRights", oi: 1)
		h(3317, "systemUpdateTimer", oi: 1); h(3318, "worldId", oi: 1); h(3321, "runEnergy", oi: 1); h(3322, "weight", oi: 1)
		h(3323, "hasManyBlackmarks", oi: 1); h(3324, "blackmarks", oi: 1); h(3325, "isMembersAccount", oi: 1)
		h(3326, "combatLevel", oi: 1); h(3327, "isFemale", oi: 1); h(3328, "isUnderageNoConsent", oi: 1); h(3329, "isQuickChatOnly", oi: 1)
		h(3330, "invFreeSlots", i: 1, oi: 1); h(3331, "invParamTotalIgnoreStacks", i: 2, oi: 1); h(3332, "invParamTotal", i: 2, oi: 1)
		h(3333, "loginTypeInfo", oi: 1); h(3335, "language", oi: 1); h(3337, "affiliate", oi: 1)
		// friends / ignore / clan
		h(3600, "friendCount", oi: 1); h(3601, "friendName", i: 1, os: 1); h(3602, "friendWorld", i: 1, oi: 1); h(3603, "friendRank", i: 1, oi: 1)
		h(3604, "friendSetRank", i: 1, s: 1); h(3605, "friendAdd", s: 1); h(3606, "friendRemove", s: 1)
		h(3607, "ignoreAdd", s: 1); h(3608, "ignoreRemove", s: 1); h(3609, "isFriend", s: 1, oi: 1); h(3610, "friendWorldName", i: 1, os: 1)
		h(3611, "clanName", os: 1); h(3612, "clanMemberCount", oi: 1); h(3613, "clanMemberName", i: 1, os: 1)
		h(3614, "clanMemberWorld", i: 1, oi: 1); h(3615, "clanMemberRank", i: 1, oi: 1); h(3616, "clanMinKick", oi: 1)
		h(3617, "clanKick", s: 1); h(3618, "clanMyRank", oi: 1); h(3619, "clanJoin", s: 1); h(3620, "clanLeave")
		h(3621, "ignoreCount", oi: 1); h(3622, "ignoreName", i: 1, os: 1); h(3623, "isIgnored", s: 1, oi: 1)
		h(3624, "clanMemberIsSelf", i: 1, oi: 1); h(3625, "clanOwner", os: 1); h(3626, "clanMemberWorldName", i: 1, os: 1)
		h(3627, "friendSameGame", i: 1, oi: 1); h(3628, "friendIndexOf", s: 1, oi: 1); h(3629, "country", oi: 1)
		// grand exchange
		for (op, n) in [(3903, "geOfferIsSelling"), (3904, "geOfferItem"), (3905, "geOfferPrice"), (3906, "geOfferCount"),
			(3907, "geOfferCompletedCount"), (3908, "geOfferCompletedGold"), (3910, "geOfferNotStarted"), (3911, "geOfferStatus2"),
			(3912, "geOfferDone"), (3913, "geOfferStatus1")] { h(op, n, i: 1, oi: 1) }
		// obj search
		h(4210, "objSearch", i: 1, s: 1, oi: 1); h(4211, "objSearchNext", oi: 1); h(4212, "objSearchReset")
		// chat / privacy
		h(5000, "publicChatFilter", oi: 1); h(5001, "setChatFilters", i: 3); h(5002, "bugReport", i: 2, s: 1)
		h(5003, "chatMessageText", i: 1, os: 1); h(5004, "chatMessageType", i: 1, oi: 1); h(5005, "privateChatFilter", oi: 1)
		h(5008, "sayPublic", s: 1); h(5009, "sendPrivateMessage", s: 2); h(5010, "chatMessageName", i: 1, os: 1)
		h(5011, "chatMessageClan", i: 1, os: 1); h(5012, "chatMessagePhrase", i: 1, oi: 1); h(5015, "myName", os: 1)
		h(5016, "tradeChatFilter", oi: 1); h(5017, "chatMessageCount", oi: 1)
		// quick chat
		h(5050, "qcCatDescription", i: 1, os: 1); h(5051, "qcCatSubcategoryCount", i: 1, oi: 1); h(5052, "qcCatSubcategory", i: 2, oi: 1)
		h(5053, "qcCatPhraseCount", i: 1, oi: 1); h(5054, "qcCatPhrase", i: 2, oi: 1); h(5055, "qcPhraseText", i: 1, os: 1)
		h(5056, "qcPhraseResponseCount", i: 1, oi: 1); h(5057, "qcPhraseResponse", i: 2, oi: 1); h(5058, "qcBeginPhrase", i: 1)
		h(5059, "qcSendPublic"); h(5060, "qcSendPrivate", s: 1); h(5061, "qcSendClan"); h(5062, "qcCatSubcategoryShortcut", i: 2, oi: 1)
		h(5063, "qcCatPhraseShortcut", i: 2, oi: 1); h(5064, "qcSubcategoryByShortcut", i: 2, oi: 1); h(5065, "qcPhraseByShortcut", i: 2, oi: 1)
		h(5066, "qcPhraseDynamicCount", i: 1, oi: 1); h(5067, "qcPhraseDynamicCommand", i: 2, oi: 1); h(5068, "qcSetValue", i: 2)
		h(5069, "qcSetValue2", i: 2); h(5070, "qcDynamicParam", i: 3, oi: 1); h(5071, "qcSearch", i: 1, s: 1, oi: 1)
		h(5072, "qcSearchNext", oi: 1); h(5073, "qcSearchReset")
		// keyboard modifiers
		h(5100, "isHoldingAlt", oi: 1); h(5101, "isHoldingCtrl", oi: 1); h(5102, "isHoldingShift", oi: 1)
		// world map
		h(5200, "worldmapSetZoom", i: 1); h(5201, "worldmapZoom", oi: 1); h(5202, "worldmapOp5202", i: 1); h(5203, "worldmapOp5203", s: 1)
		h(5204, "worldmapOp5204", s: 1, os: 1); h(5205, "worldmapLoad", s: 1); h(5206, "worldmapNameAt", i: 1, os: 1)
		h(5207, "worldmapDisplayName", s: 1, os: 1); h(5208, "worldmapOp5208", oi: 2); h(5209, "worldmapOp5209", oi: 2)
		h(5210, "worldmapCentre", oi: 2); h(5211, "worldmapSize", oi: 2); h(5212, "worldmapLabel", oi: 1, os: 1)
		h(5213, "worldmapNextLabel", oi: 1, os: 1); h(5214, "worldmapSetPosition", i: 1); h(5215, "worldmapContains", i: 1, s: 1, oi: 1)
		h(5216, "worldmapOp5216", i: 1); h(5217, "worldmapOp5217", i: 1, oi: 1); h(5218, "worldmapDefaultZoom", oi: 1)
		h(5219, "worldmapOp5219", s: 1); h(5220, "worldmapLoaded", oi: 1)
		// display
		h(5300, "setWindowSize", i: 2, oi: 1); h(5301, "leaveFullscreen"); h(5302, "displayModeCount", oi: 1)
		h(5303, "displayModeSize", i: 1, oi: 2); h(5305, "currentDisplayModeIndex", oi: 1); h(5306, "windowMode", oi: 1)
		h(5307, "setWindowMode", i: 1); h(5308, "favoriteWorlds", oi: 1); h(5309, "setFavouriteWorlds", i: 1)
		// misc
		h(5400, "sendTwoStrings", i: 1, s: 2); h(5401, "setObjRecolour", i: 2); h(5405, "cameraSplineAlloc", i: 2)
		h(5406, "cameraSplinePoint", i: 7); h(5407, "cameraSplineLength", i: 1, oi: 1); h(5411, "quit")
		h(5419, "lastLoginAddress", os: 1); h(5420, "isUsingWebsiteLogin", oi: 1); h(5421, "openUrl", i: 1, s: 1)
		h(5422, "setPlayerNames", i: 1, s: 2); h(5423, "debugPrint", s: 1); h(5424, "loginBackgroundSetup", i: 11)
		h(5425, "loginBackgroundClear"); h(5426, "setClientOpt5426", i: 1); h(5427, "setMinimapOpt", i: 2)
		// camera
		h(5500, "cameraMoveTo", i: 4); h(5501, "cameraPointAt", i: 4); h(5502, "cameraSplineStart", i: 6); h(5503, "cameraUnlock")
		h(5504, "cameraSetAngles", i: 2); h(5505, "cameraPitch", oi: 1); h(5506, "cameraYaw", oi: 1)
		// login / account creation
		h(5600, "directLogin", i: 1, s: 2); h(5601, "skipLoginStage10"); h(5602, "resetLoginReply"); h(5603, "accountCheckInfo", i: 4)
		h(5604, "accountCheckName", s: 1); h(5605, "accountCreate", i: 4, s: 2); h(5606, "resetCreateReply"); h(5607, "loginReply", oi: 1)
		h(5608, "worldSwitchTimer", oi: 1); h(5609, "createReply", oi: 1); h(5610, "suggestedNames", os: 5); h(5611, "loginDetailedReply", oi: 1)
		// client settings
		for op in [6001, 6002, 6003, 6005, 6006, 6007, 6008, 6009, 6010, 6011, 6012, 6014, 6015, 6016, 6017, 6018, 6019, 6020, 6021, 6024, 6028] {
			h(op, "setting\(op)", i: 1)
		}
		h(6023, "setParticles", i: 1, oi: 1)
		for op in [6101, 6102, 6103, 6105, 6106, 6107, 6108, 6109, 6110, 6111, 6112, 6114, 6115, 6116, 6117, 6118, 6119, 6120, 6121, 6123, 6124, 6128] {
			h(op, "getSetting\(op)", oi: 1)
		}
		h(6200, "setViewport6200", i: 2); h(6201, "setViewport6201", i: 2); h(6202, "setViewportZoom", i: 4)
		h(6203, "viewportSize", oi: 2); h(6204, "viewportMax6204", oi: 2); h(6205, "viewportMax6205", oi: 2)
		// clock
		h(6300, "minutes", oi: 1); h(6301, "daysSinceLaunch", oi: 1); h(6302, "daysSinceLaunchOf", i: 3, oi: 1); h(6303, "year", oi: 1)
		// ads / worlds
		h(6405, "canShowVideoAd", oi: 1); h(6406, "isShowingVideoAd", oi: 1)
		h(6500, "worldListFetch", oi: 1); h(6501, "worldFirst", oi: 4, os: 2); h(6502, "worldNext", oi: 4, os: 2)
		h(6503, "worldHop", i: 1, oi: 1); h(6504, "setLastWorld", i: 1); h(6505, "lastWorld", oi: 1)
		h(6506, "worldInfo", i: 1, oi: 3, os: 2); h(6507, "worldSort", i: 4); h(6600, "setPref6600", i: 1); h(6601, "pref6601", oi: 1)
		return t
	}()
}
