/// Server -> client game packet opcodes (rev 530).
/// Generated from reference/rt4-client `ServerProt.java`; names are rt4's (with its NXT-naming notes).
public enum ServerProt {
	public static let rebuildNormal = 162
	public static let rebuildRegion = 214 // Dynamic regions
	public static let updateZoneFullFollows = 112 // NXT naming
	public static let updateZonePartialFollows = 26 // NXT naming
	public static let updateZonePartialEnclosed = 230 // NXT naming
	public static let objCount = 14 // NXT naming
	public static let mapProjanim2 = 16
	public static let spotanimSpecific = 17 // NXT naming
	public static let locAnim = 20 // NXT naming
	public static let objReveal = 33 // NXT naming
	public static let soundArea = 97 // NXT naming
	public static let mapProjanim = 104 // NXT naming
	public static let mapProjanim3 = 121
	public static let objAdd = 135 // NXT naming
	public static let locAdd = 179 // NXT naming
	public static let locDel = 195 // NXT naming
	public static let locAddChange = 202 // NXT naming
	public static let objDel = 240 // NXT naming
	public static let npcInfo = 32 // NXT naming
	public static let playerInfo = 225 // NXT naming
	public static let varbitSmall = 37 // NXT naming
	public static let varbitLarge = 84 // NXT naming
	public static let varpSmall = 60 // NXT naming
	public static let varpLarge = 226 // NXT naming
	public static let clientSetvarcSmall = 65 // NXT naming
	public static let clientSetvarcLarge = 69 // NXT naming
	public static let resetClientVarcache = 89 // NXT naming (?)
	public static let forceVarpRefresh = 128
	public static let messageGame = 70 // NXT naming
	public static let ifSetcolour = 2 // NXT naming
	public static let chatFilterSettings = 232 // NXT naming
	public static let messagePrivate = 0 // NXT naming
	public static let messageQuickchatPrivate = 247 // NXT naming
	public static let messagePrivateEcho = 71 // NXT naming
	public static let messageQuickchatPrivateEcho = 141 // NXT naming
	public static let messageClanchannel = 54 // NXT naming
	public static let clanQuickChat = 81
	public static let joinClanChat = 55
	public static let friendlistLoaded = 197 // NXT naming (?)
	public static let updateFriendlist = 62 // NXT naming (?)
	public static let updateIgnorelist = 126 // NXT naming
	public static let ifSethide = 21 // NXT naming (?)
	public static let ifSetanim = 36 // NXT naming (?)
	public static let ifSetobject = 50 // NXT naming
	public static let ifSetplayerhead = 66 // NXT naming (?) - double check if this is correct or if it's IF_SETPLAYERMODEL_SELF etc
	public static let ifSetnpchead = 73 // NXT naming
	public static let ifSetmodel = 130 // NXT naming
	public static let ifSetposition = 119 // NXT naming
	public static let ifSetangle = 132 // NXT naming
	public static let ifOpensub = 145 // NXT naming (?)
	public static let ifClosesub = 149 // NXT naming (?)
	public static let ifOpentop = 155 // NXT naming (?)
	public static let setInterfaceSettings = 165
	public static let ifSetscrollpos = 220 // NXT naming
	public static let ifSettext1 = 171
	public static let ifSettext2 = 48
	public static let ifSettext3 = 123
	public static let widgetstructSetting = 9
	public static let interfaceAnimateRotate = 207
	public static let gameFrameUnk = 209
	public static let deleteInventory = 191
	public static let switchWidget = 176
	public static let generateChatHeadFromBody = 111
	public static let updateInvClear = 144
	public static let updateInvPartial = 22 // NXT naming
	public static let updateInvFull = 105 // NXT naming
	public static let logout = 86 // NXT naming
	public static let updateRunenergy = 234 // NXT naming
	public static let updateRunweight = 159 // NXT naming (?)
	public static let updateRebootTimer = 85 // NXT naming
	public static let updateStat = 38 // NXT naming
	public static let midiSong = 4 // NXT naming
	public static let midiJingle = 208 // NXT naming
	public static let synthSound = 172 // NXT naming
	public static let hintArrow = 217 // NXT naming (?)
	public static let updateUid192 = 169 // NXT naming (?)
	public static let urlOpen = 42 // NXT naming
	public static let camReset = 24 // NXT naming
	public static let camShake = 27 // NXT naming
	public static let spotanimEntity = 56
	public static let npcAnimSpecific = 102 // NXT naming
	public static let camLookat = 125 // NXT naming
	public static let resetAnims = 131 // NXT naming
	public static let lastLoginInfo = 164 // NXT naming (?)
	public static let camForceangle = 187 // NXT naming
	public static let locAnimSpecific = 235 // NXT naming
	public static let runCs2 = 115
	public static let setInteraction = 44
	public static let grandExchangeOffers = 116
	public static let clearMinimapFlag = 153
	public static let setMinimapState = 192
	public static let reflectionCheatCheck = 114
	public static let teleportLocalPlayer = 13
	public static let setSettingsString = 142
	public static let setWalkText = 160
	public static let cameraDetach = 154
	public static let updateClan = 196

	/// rt4 `Protocol.PACKET_LENGTHS`: fixed size, -1 = byte length prefix, -2 = short length prefix.
	public static let lengths: [Int] = [
		-1, 0, 8, 0, 2, 0, 0, 0, 0, 12, 0, 1, 0, 3, 7, 0,
		15, 6, 0, 0, 4, 7, -2, -1, 2, 0, 2, 8, 0, 0, 0, 0,
		-2, 5, 0, 0, 8, 3, 6, 0, 0, 0, -1, 0, -1, 0, 0, 6,
		-2, 0, 12, 0, 0, 0, -1, -2, 10, 0, 0, 0, 3, 0, -1, 0,
		0, 5, 6, 0, 0, 8, -1, -1, 0, 8, 0, 0, 0, 0, 0, 0,
		0, -1, 0, 0, 6, 2, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0,
		0, 5, 0, 0, 0, 0, 5, 0, 0, -2, 0, 0, 0, 0, 0, 12,
		2, 0, -2, -2, 20, 0, 0, 10, 0, 15, 0, -1, 0, 8, -2, 0,
		0, 0, 8, 0, 12, 0, 0, 7, 0, 0, 0, 0, 0, -1, -1, 0,
		4, 5, 0, 0, 0, 6, 0, 0, 0, 0, 8, 9, 0, 0, 0, 2,
		-1, 0, -2, 0, 4, 14, 0, 0, 0, 24, 0, -2, 5, 0, 0, 0,
		10, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0, 2,
		1, 0, 0, 2, -1, 1, 0, 0, 0, 0, 14, 0, 0, 0, 0, 10,
		5, 0, 0, 0, 0, 0, -2, 0, 0, 9, 0, 0, 8, 0, 0, 0,
		0, -2, 6, 0, 0, 0, -2, 0, 3, 0, 1, 7, 0, 0, 0, 0,
		3, 0, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, 3, 0, 0,
	]
}
