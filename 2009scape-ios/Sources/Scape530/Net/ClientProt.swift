/// Client -> server game packet opcodes (rev 530).
/// Generated from reference/rt4-client `ClientProt.java`; names are rt4's (with its NXT-naming notes).
public enum ClientProt {
	public static let clientCheat = 44
	/// rt4 `ScriptRunner` op 5008 (`p1isaac(237)`): public chat with colour and effect bytes.
	public static let publicChat = 237
	/// rt4 `ScriptRunner` op 5009 (`p1isaac(201)`): private message to a base-37 name.
	public static let privateMessage = 201
	public static let clanJoinchatLeavechat = 104
	public static let clanKickuser = 162 // or CLANCHANNEL_KICKUSER
	public static let friendlistAdd = 120
	public static let friendlistDel = 57
	public static let friendSetrank = 188
	public static let ignorelistAdd = 34
	public static let ignorelistDel = 213
	public static let windowStatus = 243 // assumed
	public static let transmitvarVerifyid = 177
	public static let eventMouseMove = 123
	public static let eventMouseClick = 75
	public static let eventCameraPosition = 21
	public static let eventAppletFocus = 22
	public static let resumePCountdialog = 23
	public static let resumePNamedialog = 244
	public static let resumePStringdialog = 65
	public static let setChatfiltersettings = 157
	public static let bugReport = 99
	public static let soundSongend = 137
	public static let moveGameclick = 215
	public static let moveMinimapclick = 39
	public static let closeModal = 184
	public static let noTimeout = 93 // assumed
	/// Walk toward an interaction target (rt4 `ClientProt.method3502` with argument 2).
	public static let moveInteract = 77
	/// OPNPC1...5 (rt4 `MiniMenu` actions 17, 16, 4, 19, 2).
	public static let opNpc = [78, 3, 148, 30, 218]
	public static let examineNpc = 72
	/// OPLOC1...5 (actions 42, 50, 49, 46, 1001).
	public static let opLoc = [254, 194, 84, 247, 170]
	public static let examineLoc = 94
	/// OPOBJ1...5 for ground items (actions 21, 34, 18, 20, 24).
	public static let opObj = [228, 109, 66, 33, 48]
	public static let examineObj = 92
}
