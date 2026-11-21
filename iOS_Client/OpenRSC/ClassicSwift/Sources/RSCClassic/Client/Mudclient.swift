// The game client: port of rsc-c's mudclient.c. State lives here; each UI
// file of rsc-c (ui/*.c) becomes an extension in Client/UI.

import Foundation

public struct ServerBoundary {
    public var model: GameModel?
    public var x = 0, y = 0, id = 0, direction = 0
    public var alreadyInMenu = false
}

public struct ItemSpawn {
    public var model: GameModel?
    public var x = 0, y = 0, z = 0, id = 0
    public var alreadyInMenu = false
}

public struct Scenery {
    public var x = 0, y = 0, id = 0, direction = 0
    public var model: GameModel?
    public var alreadyInMenu = false
}

public struct MagicBubble { public var x = 0, y = 0, type = 0, time = 0 }
public struct ActionBubble { public var x = 0, y = 0, scale = 0, item = 0 }
public struct HealthBar { public var x = 0, y = 0, missing = 0 }
public struct OverworldText { public var text = "", x = 0, y = 0; public var colour: Int32 = 0 }

public struct MenuEntry {
    public var type = 0
    public var actionText = ""
    public var targetText = ""
    public var wikiPage = ""
    public var x = 0, y = 0
    public var index = 0
    public var sourceIndex = 0
    public var targetIndex = 0
}

public enum LoginStage: Int { case welcome = 0, new = 1, existing = 2, recover = 3, world = 4 }
public enum MessageTab: Int { case all = 0, chat = 1, quest = 2, `private` = 3 }
public enum MessageType: Int { case chat = 2, game = 3, bor = 4, quest = 5, `private` = 6 }
public enum ConfirmType: Int { case none = 0, tutorial = 1, optionsDefault = 2, optionsVanilla = 3 }

/// What the client needs from the app: presenting frames, the keyboard and sound.
public protocol MudclientHost: AnyObject {
    /// surface_draw: the frame in `surface.pixels` is complete.
    func present(_ mud: Mudclient)
    func triggerKeyboard(text: String, isPassword: Bool, x: Int, y: Int, width: Int, height: Int,
                         font: FontStyle, isCentred: Bool)
    func playSound(_ pcm: [Int16])
}

public final class Mudclient {
    // MARK: Constants (mudclient.h)
    public static let zoomMin = 450, zoomMax = 2250, zoomIndoors = 550, zoomOutdoors = 750
    public static let magicLoc = 128
    public static let vanillaWidth = 512, vanillaHeight = 346, minWidth = 320, minHeight = 240
    public static let width = 512, height = 346
    public static let version = 203
    public static let socialListMax = 100
    public static let inputTextLength = 20, inputPmLength = 80, inputDigitsLength = 14
    public static let gameObjectsMax = 1000, wallObjectsMax = 500, objectsMax = 1500
    public static let playersServerMax = 2000, playersMax = 500, npcsServerMax = 5000, npcsMax = 500
    public static let groundItemsMax = 5000, prayerCount = 50, playerSkillCount = 18
    public static let playerStatEquipmentCount = 5, projectileRangeMax = 40
    public static let receivedMessageMax = 50, actionBubbleMax = 50, healthBarMax = 50
    public static let magicBubbleMax = 50, overworldTextMax = 128
    public static let inventoryItemsMax = 30, pathStepsMax = 8000, bankItemsMax = 256
    public static let shopItemsMax = 256, tradeItemsMax = 14, duelItemsMax = 8, experienceDropsMax = 100
    public static let spriteLimit = 4000
    public static let loadingWidth = 277, loadingHeight = 20
    public static let objectAnimationDistance = 7
    public static let messageHistoryLength = 5, messageFlashTime = 200
    public static let hbarSpriteOffset = 23, hbarWidth = 512
    public static let usernameLength = 20, passwordLength = 20, maxUserLength = 12
    public static let chatMessageMaxInputLength = 80
    // npc / object / item ids
    public static let shiftyManId = 24, giantBatId = 43
    public static let windmillSailsId = 74, fireId = 97, fireplaceId = 274, oddWellId = 466
    public static let lightningId = 1031, fireSpellId = 1036, spellChargeId = 1147
    public static let torchId = 51, skullTorchId = 143, clawSpellId = 1142
    public static let oddLookingWallId = 22
    public static let coinsId = 10, fountainId = 17

    public static let animatedModels = [
        "torcha2", "torcha3", "torcha4", "skulltorcha2", "skulltorcha3", "skulltorcha4", "firea2", "firea3",
        "fireplacea2", "fireplacea3", "firespell2", "firespell3", "lightning2", "lightning3", "clawspell2",
        "clawspell3", "clawspell4", "clawspell5", "spellcharge2", "spellcharge3",
    ]
    /// Animations whose 2001 TGA sprites have more detail than the 2002 ones.
    static let animsOlderIsBetter = ["camel", "bat", "battleaxe", "bear", "fbody1", "fhead1", "fplatemailtop",
                                     "head1", "head2", "head3", "head4", "platemailtop", "staff", "body1"]

    // MARK: Engine
    public weak var host: MudclientHost?
    public let options: Options
    public var gameData = GameData()
    public let cacheDirectory: URL
    public var surface: Surface!
    public var scene: Scene!
    public var world: World!
    public var packetStream: PacketStream?
    public var gameModels = [GameModel?](repeating: nil, count: gameObjectsMax)
    public var itemModels: [GameModel?] = []
    public var soundData: [UInt8]?

    public var gameWidth = width
    public var gameHeight = height

    // MARK: Input
    public var keyLeft = false, keyRight = false, keyUp = false, keyDown = false
    public var keyPageUp = false, keyPageDown = false, keyHome = false, keyTab = false
    public var key1 = false, key2 = false, key3 = false, key4 = false, key5 = false
    public var middleButtonDown = false
    public var originMouseX = 0, originRotation = 0
    public var lastMouseSampleTicks = 0, lastMouseSampleX = 0, cameraMomentum = 0
    public var mouseScrollDelta = 0
    public var mouseActionTimeout = 0
    public var mouseX = 0, mouseY = 0
    public var mouseButtonDown = 0
    public var lastMouseButtonDown = 0
    public var mouseButtonClick = 0
    public var mouseItemCountIncrement = 0
    public var mouseButtonDownTime = 0
    public var mouseClickXHistory: [Int] = []
    public var mouseClickYHistory: [Int] = []
    public var mouseClickCount = 0
    public var mouseClickXStep = 0, mouseClickXX = 0, mouseClickXY = 0
    public static var finger1X = 0, finger1Y = 0, finger1Down = 0
    public static var finger2X = 0, finger2Y = 0, finger2Down = 0

    // MARK: Loading and timing
    public var loadingStep = 1
    public var loadingProgressPercent = 0
    public var loadingProgressText = "Loading"
    public var errorLoadingData = false
    public var timings = [Int](repeating: 0, count: 10)
    public var stopTimeout = 0
    public var fps = 0
    public var targetFps = 20

    // MARK: Text input
    public var inputTextCurrent = "", inputTextFinal = ""
    public var inputPmCurrent = "", inputPmFinal = ""
    public var inputDigitsCurrent = "", inputDigitsFinal = 0

    public var maxReadTries = 0
    public var worldFullTimeout = 0
    public var moderatorLevel = 0
    public var autoLoginAttempts = 0

    // MARK: Social (ui/social-tab.c)
    public var panelSocialList: Panel!
    public var showDialogSocialInput = 0
    public var controlListSocial = 0
    public var uiTabSocialSubTab = 0
    public var messageIndex = 0
    public var messageTokens = [Int](repeating: 0, count: socialListMax)
    public var friendListCount = 0
    public var friendList = [Int64](repeating: 0, count: socialListMax * 2)
    public var friendListOnline = [Int](repeating: 0, count: socialListMax * 2)
    public var ignoreListCount = 0
    public var ignoreList = [Int64](repeating: 0, count: socialListMax * 2)
    public var privateMessageTarget: Int64 = 0

    // MARK: Options tab
    public var settingsCameraAuto = 0, settingsBlockChat = 0, settingsBlockPrivate = 0
    public var settingsBlockTrade = 0, settingsBlockDuel = 0, settingsMouseButtonOne = 0
    public var settingsSoundDisabled = 0
    public var showChangePasswordStep = 0
    public var changePasswordOld = "", changePasswordNew = ""

    public var packetLastRead: UInt64 = 0
    public var incomingPacket = [UInt8](repeating: 0, count: 5000)
    public var username = "", password = ""

    // MARK: Sprite bases
    public var spriteMedia = SpriteBase.media
    public var spriteUtil = SpriteBase.util
    public var spriteItem = SpriteBase.item
    public var spriteLogo = SpriteBase.logo
    public var spriteProjectile = SpriteBase.projectile
    public var spriteTexture = SpriteBase.texture
    public var spriteTextureWorld = SpriteBase.textureWorld

    public var sceneSpriteCount = 0

    // MARK: Login (ui/login.c)
    public var panelLoginWelcome: Panel!
    public var panelLoginNewUser: Panel!
    public var panelLoginExistingUser: Panel!
    public var controlWelcomeNewUser = 0, controlWelcomeExistingUser = 0
    public var controlWelcomeOptions = 0, controlWelcomeWorlds = 0
    public var referId = 0
    public var controlLoginNewOk = 0
    public var controlRegisterStatus = 0, controlRegisterStatusBottom = 0, controlRegisterUser = 0
    public var controlRegisterPassword = 0, controlRegisterConfirmPassword = 0, controlRegisterCheckbox = 0
    public var controlRegisterSubmit = 0, controlRegisterCancel = 0
    public var controlLoginStatus = 0, controlLoginStatusBottom = 0, controlLoginUsername = 0
    public var controlLoginPassword = 0, controlLoginOk = 0, controlLoginCancel = 0, controlLoginRecover = 0
    public var loginScreen = LoginStage.welcome
    public var loginUsername = "", loginPass = ""
    public var loginPrompt = ""
    public var loginUsernameDisplay = ""
    public var loginScreenStatus = ""
    public var sessionId: Int64 = 0
    public var loggedIn = false

    // MARK: Message tabs
    public var panelMessageTabs: Panel!
    public var controlTextListAll = 0, controlTextListChat = 0
    public var controlTextListQuest = 0, controlTextListPrivate = 0
    public var messageTabSelected = MessageTab.all
    public var messageTabFlashAll = 0, messageTabFlashHistory = 0
    public var messageTabFlashQuest = 0, messageTabFlashPrivate = 0
    public var messageHistory = [String](repeating: "", count: messageHistoryLength)
    public var messageHistoryTimeout = [Int](repeating: 0, count: messageHistoryLength)
    public var loginTimer = 0
    public var systemUpdate = 0

    public var combatStyle = 0
    public var logoutTimeout = 0
    public var combatTimeout = 0

    // MARK: Entities
    public var objectCount = 0
    public var objects = [Scenery](repeating: Scenery(), count: objectsMax)
    public var wallObjectCount = 0
    public var wallObjects = [ServerBoundary](repeating: ServerBoundary(), count: wallObjectsMax)
    public var playerServerIndexes = [Int](repeating: 0, count: playersMax)
    public var playerServer = [GameCharacter?](repeating: nil, count: playersServerMax)
    public var playerCount = 0
    public var players = [GameCharacter?](repeating: nil, count: playersMax)
    public var knownPlayerCount = 0
    public var knownPlayers = [GameCharacter?](repeating: nil, count: playersMax)
    public var localPlayerServerIndex = 0
    public var localPlayer = GameCharacter()
    public var combatTarget: GameCharacter?
    public var npcsServer = [GameCharacter?](repeating: nil, count: npcsServerMax)
    public var npcCount = 0
    public var npcs = [GameCharacter?](repeating: nil, count: npcsMax)
    public var knownNpcCount = 0
    public var knownNpcs = [GameCharacter?](repeating: nil, count: npcsMax)
    public var groundItemCount = 0
    public var groundItems = [ItemSpawn](repeating: ItemSpawn(), count: groundItemsMax)

    // MARK: Sleep
    public var isSleeping = false
    public var sleepWordDelayTimer = 0
    public var sleepWordDelay = 1
    public var fatigueSleeping = 0
    public var sleepingStatusText: String?

    public var fogOfWar = false

    public var objectAnimationCount = 0, objectAnimationCycle = 0, lastObjectAnimationCycle = 0
    public var torchAnimationCycle = 0, lastTorchAnimationCycle = 0
    public var clawAnimationCycle = 0, lastClawAnimationCycle = 0

    public var receivedMessagesCount = 0
    public var receivedMessageX = [Int](repeating: 0, count: receivedMessageMax)
    public var receivedMessageY = [Int](repeating: 0, count: receivedMessageMax)
    public var receivedMessageMidPoint = [Int](repeating: 0, count: receivedMessageMax)
    public var receivedMessageHeight = [Int](repeating: 0, count: receivedMessageMax)
    public var receivedMessages = [String](repeating: "", count: receivedMessageMax)

    // MARK: Camera
    public var cameraAngle = 1
    public var cameraRotation = 128
    public var cameraZoom = 0
    public var cameraRotationTime = 0
    public var cameraRotationX = 0, cameraRotationY = 0
    public var cameraRotationXIncrement = 2, cameraRotationYIncrement = 2
    public var cameraAutoRotatePlayerX = 0, cameraAutoRotatePlayerY = 0
    public var cameraAutoCounter = 0

    // MARK: Region
    public var isInWilderness = false
    public var loadingArea = false
    public var planeWidth = 0, planeHeight = 0, planeIndex = 0, planeMultiplier = 0
    public var regionX = 0, regionY = 0, localRegionX = 0, localRegionY = 0
    public var lastPlaneIndex = -1
    public var localLowerX = 0, localLowerY = 0, localUpperX = 0, localUpperY = 0

    public var showWildernessWarning = 0
    public var deathScreenTimeout = 0

    public var actionBubbleCount = 0
    public var actionBubbles = [ActionBubble](repeating: ActionBubble(), count: actionBubbleMax)
    public var healthBarCount = 0
    public var healthBars = [HealthBar](repeating: HealthBar(), count: healthBarMax)
    public var magicBubbleCount = 0
    public var magicBubbles = [MagicBubble](repeating: MagicBubble(), count: magicBubbleMax)
    public var overworldTextCount = 0
    public var overworldText = [OverworldText](repeating: OverworldText(), count: overworldTextMax)

    // MARK: UI tabs
    public var showUITab = 0
    public var uiTabMinX = 0, uiTabMaxX = 0, uiTabMinY = 0, uiTabMaxY = 0
    public var minimapRandomRotation = 0, minimapRandomScale = 0

    // MARK: Menu
    public var showRightClickMenu = false
    public var menuItemsCount = 0
    public var menuIndices: [Int] = Array(repeating: 0, count: 32)
    public var menuItems: [MenuEntry] = Array(repeating: MenuEntry(), count: 32)
    public var menuWidth = 0, menuHeight = 0, menuX = 0, menuY = 0

    // MARK: Inventory
    public var inventoryItemsCount = 0
    public var inventoryItemId = [Int](repeating: 0, count: inventoryItemsMax)
    public var inventoryItemStackCount = [Int](repeating: 0, count: inventoryItemsMax)
    public var inventoryEquipped = [Int](repeating: 0, count: inventoryItemsMax)
    public var selectedItemInventoryIndex = -1
    public var selectedItemName = ""

    // MARK: Stats
    public var panelQuests: Panel!
    public var controlListQuest = 0
    public var questComplete = [Int](repeating: 0, count: StatsTab.questNames.count)
    public var uiTabStatsSubTab = 0
    public var playerSkillCurrent = [Int](repeating: 0, count: playerSkillCount)
    public var playerSkillBase = [Int](repeating: 0, count: playerSkillCount)
    public var playerExperience = [Int](repeating: 0, count: playerSkillCount)
    public var playerQuestPoints = 0
    public var statFatigue = 0
    public var playerStatEquipment = [Int](repeating: 0, count: playerStatEquipmentCount)

    // MARK: World list
    public var panelLoginWorldlist: Panel!
    public var controlListWorlds = 0
    public var controlWorldlistButton = 0
    public var worlds: [WorldEntry] = []
    public var server = ""
    public var port = 0
    public var rsaExponent = ""
    public var rsaModulus = ""

    // MARK: Magic
    public var panelMagic: Panel!
    public var controlListMagic = 0
    public var uiTabMagicSubTab = 0
    public var selectedSpell = -1
    public var prayerOn = [Bool](repeating: false, count: prayerCount)

    public var walkPathX = [Int](repeating: 0, count: pathStepsMax)
    public var walkPathY = [Int](repeating: 0, count: pathStepsMax)

    // MARK: Appearance
    public var panelAppearance: Panel!
    public var controlAppearanceHeadLeft = 0, controlAppearanceHeadRight = 0
    public var controlAppearanceHairLeft = 0, controlAppearanceHairRight = 0
    public var controlAppearanceGenderLeft = 0, controlAppearanceGenderRight = 0
    public var controlAppearanceTopLeft = 0, controlAppearanceTopRight = 0
    public var controlAppearanceSkinLeft = 0, controlAppearanceSkinRight = 0
    public var controlAppearanceBottomLeft = 0, controlAppearanceBottomRight = 0
    public var controlAppearanceAccept = 0
    public var showAppearanceChange = false
    public var appearanceHeadType = 0
    public var appearanceHeadGender = 1
    public var appearanceBodyType = 1
    public var appearanceHairColour = 2
    public var appearanceTopColour = 8
    public var appearanceSkinColour = 0
    public var appearanceBottomColour = 14

    // MARK: Dialogs
    public var showOptionMenu = false
    public var optionMenuCount = 0
    public var optionMenuEntry = [String](repeating: "", count: 5)
    public var showDialogWelcome = false
    public var welcomeScreenAlreadyShown = false
    public var welcomeLastIp = 0, welcomeDaysAgo = 0, welcomeRecoverySetDays = 0, welcomeUnreadMessages = 0
    public var welcomeLastIpString = ""
    public var showDialogServerMessage = false
    public var serverMessageBoxTop = false
    public var serverMessage = ""
    public var serverMessagePage = 0
    public var serverMessageNext = ""

    // MARK: Bank
    public var showDialogBank = false
    public var newBankItemCount = 0
    public var newBankItems = [Int](repeating: 0, count: bankItemsMax)
    public var newBankItemsCount = [Int](repeating: 0, count: bankItemsMax)
    public var bankItemCount = 0
    public var bankItems = [Int](repeating: 0, count: bankItemsMax)
    public var bankItemsCount = [Int](repeating: 0, count: bankItemsMax)
    public var bankItemsMax = 48
    public var bankActivePage = 0
    public var bankSelectedItemSlot = -1
    public var bankSelectedItem = -2
    public var bankOfferType = 0
    public var bankLastDepositOffer = 0, bankLastWithdrawOffer = 0
    public var bankScrollRow = 0, bankLastScroll = 0
    public var bankHandleDragged = false
    public var bankVisibleRows = 0
    public var bankSearchFocus = false

    // MARK: Shop
    public var showDialogShop = false
    public var shopItems = [Int](repeating: 0, count: shopItemsMax)
    public var shopItemsCount = [Int](repeating: 0, count: shopItemsMax)
    public var shopItemsPrice = [Int](repeating: 0, count: shopItemsMax)
    public var shopSelectedItemIndex = 0, shopSelectedItemType = 0
    public var shopBuyPriceMod = 0, shopSellPriceMod = 0

    // MARK: Trade and duel
    public var transactionItemCount = 0
    public var transactionItems = [Int](repeating: 0, count: tradeItemsMax)
    public var transactionItemsCount = [Int](repeating: 0, count: tradeItemsMax)
    public var transactionRecipientAccepted = 0, transactionAccepted = 0
    public var transactionRecipientName = ""
    public var transactionRecipientItemCount = 0
    public var transactionRecipientItems = [Int](repeating: 0, count: tradeItemsMax)
    public var transactionRecipientItemsCount = [Int](repeating: 0, count: tradeItemsMax)
    public var transactionSelectedItem = 0, transactionLastOffer = 0, transactionOfferType = 0, transactionTab = 0
    public var transactionRecipientConfirmName: Int64 = 0
    public var transactionConfirmItemCount = 0
    public var transactionConfirmItems = [Int](repeating: 0, count: tradeItemsMax)
    public var transactionConfirmItemsCount = [Int](repeating: 0, count: tradeItemsMax)
    public var transactionRecipientConfirmItemCount = 0
    public var transactionRecipientConfirmItems = [Int](repeating: 0, count: tradeItemsMax)
    public var transactionRecipientConfirmItemsCount = [Int](repeating: 0, count: tradeItemsMax)
    public var transactionConfirmAccepted = 0
    public var showDialogTrade = false, showDialogTradeConfirm = false
    public var showDialogDuel = false, showDialogDuelConfirm = false
    public var duelOptionRetreat = 0, duelOptionMagic = 0, duelOptionPrayer = 0, duelOptionWeapons = 0

    public var showDialogOfferX = false
    public var offerId = 0, offerMax = 0

    public var showDialogConfirm = false
    public var confirmTextTop = "", confirmTextBottom = ""
    public var confirmType = ConfirmType.none

    // MARK: Additional options
    public var showAdditionalOptions = false
    public var optionsTab = 0
    public var panelGameOptions: Panel!
    public var panelControlOptions: Panel!
    public var panelUIOptions: Panel!
    public var panelBankOptions: Panel!
    public var gameOptions = [OptionBinding?](repeating: nil, count: 50)
    public var controlOptions = [OptionBinding?](repeating: nil, count: 50)
    public var uiOptions = [OptionBinding?](repeating: nil, count: 50)
    public var bankOptions = [OptionBinding?](repeating: nil, count: 50)

    // MARK: Experience drops
    public var experienceDropSkill = [Int](repeating: 0, count: experienceDropsMax)
    public var experienceDropAmount = [Int](repeating: 0, count: experienceDropsMax)
    public var experienceDropY = [Float](repeating: 0, count: experienceDropsMax)
    public var experienceDropSpeed = [Float](repeating: 0, count: experienceDropsMax)
    public var experienceDropCount = 0

    public var selectedWiki = false

    /// mudclient_new
    public init(cacheDirectory: URL, options: Options = Options()) {
        self.cacheDirectory = cacheDirectory
        self.options = options
        options.load()
        cameraZoom = options.zoomCamera != 0 ? Mudclient.zoomOutdoors : Mudclient.zoomIndoors
        mouseClickXHistory = Array(repeating: 0, count: 8192)
        mouseClickYHistory = Array(repeating: 0, count: 8192)
    }

    // MARK: - Small helpers

    /// mudclient_is_touch: rsc-c's mobile build always lays out for touch.
    public var isTouchLayout: Bool { true }

    var isCompact: Bool { surface.width < Mudclient.vanillaWidth || surface.height < Mudclient.vanillaHeight }

    public func setTargetFps(_ fps: Int) { targetFps = 1000 / fps }
    public func resetTimings() { for i in 0..<10 { timings[i] = 0 } }
    public func start() { if stopTimeout >= 0 { stopTimeout = 0 } }
    public func stop() { if stopTimeout >= 0 { stopTimeout = 4000 / targetFps } }

    /// surface_draw
    public func draw() { host?.present(self) }

    /// mudclient_start_application_common, minus the window: makes the surface.
    public func createSurface(width: Int, height: Int) {
        gameWidth = width
        gameHeight = height
        let s = Surface(width: width, height: height, limit: Mudclient.spriteLimit)
        s.host = self
        s.spriteUtil = spriteUtil
        s.spriteItem = spriteItem
        s.setBounds(minX: 0, minY: 0, maxX: width, maxY: height)
        surface = s
    }

    /// The panel offsets mudclient_resize applies once the surface exists.
    public func applyPanelOffsets() {
        let touch = isTouchLayout
        let fullOffsetX = surface.width - Mudclient.width
        let fullOffsetY = surface.height - Mudclient.height
        let halfOffsetX = surface.width / 2 - Mudclient.width / 2
        let halfOffsetY = surface.height / 2 - Mudclient.height / 2
        let dynamicOffsetX = surface.width / 2 - (isCompact ? Mudclient.minWidth : Mudclient.vanillaWidth) / 2
        let dynamicOffsetY = surface.height / 2 - (isCompact ? Mudclient.minHeight : Mudclient.vanillaHeight) / 2
        for p in [panelLoginWelcome, panelLoginNewUser, panelLoginExistingUser, panelLoginWorldlist, panelAppearance] {
            p?.offsetX = dynamicOffsetX
            p?.offsetY = dynamicOffsetY
        }
        if let p = panelMessageTabs, !touch { p.offsetY = fullOffsetY }
        for p in [panelQuests, panelMagic, panelSocialList] {
            p?.offsetX = fullOffsetX
            if touch { p?.offsetY = fullOffsetY }
        }
        for p in [panelGameOptions, panelControlOptions, panelUIOptions, panelBankOptions] {
            p?.offsetX = halfOffsetX
            p?.offsetY = halfOffsetY
        }
    }

    // MARK: - Loading (mudclient_draw_loading_progress .. mudclient_load_sounds)

    public func drawLoadingProgress(_ percent: Int, _ text: String) {
        surface.blackScreen()
        surface.drawBox(x: 0, y: 0, width: 128, height: 128, colour: Colour.black)
        if options.lowmem == 0 {
            let logo = Mudclient.spriteLimit - 1
            if surface.spriteWidth[logo] != 0 {
                let logoX = gameWidth / 2 - surface.spriteWidth[logo] / 2 - 2
                let logoY = gameHeight / 2 - surface.spriteHeight[logo] / 2 - 46
                surface.drawSprite(x: logoX, y: logoY, id: logo)
            }
        }
        let barX = Int(Float(gameWidth) / 2 - Float(Mudclient.loadingWidth) / 2)
        let barY = gameHeight / 2 + 2
        let width = Int(Float(percent) / 100 * Float(Mudclient.loadingWidth))
        surface.drawBorder(x: barX - 2, y: barY - 2, width: Mudclient.loadingWidth + 4,
                           height: Mudclient.loadingHeight + 4, colour: Colour.grey84)
        surface.drawBox(x: barX, y: barY, width: Mudclient.loadingWidth, height: Mudclient.loadingHeight,
                        colour: Colour.black)
        surface.drawBox(x: barX, y: barY, width: width, height: Mudclient.loadingHeight, colour: Colour.grey84)
        var cx = surface.width / 2 - 1
        var cy = surface.height / 2 + 16
        if surface.fonts.count > 2 {
            surface.drawStringCentre(text, x: cx, y: cy, font: .regular12, colour: Colour.greyC6)
        }
        if surface.fonts.count > 3 {
            cy += 20
            surface.drawStringCentre("Created by JAGeX - visit www.jagex.com", x: cx, y: cy, font: .bold13,
                                     colour: Colour.greyC6)
            cx += 7
            cy += 16
            let date = "2001-2002 Andrew Gower and Jagex Ltd"
            let iconX = cx - surface.textWidth(date, font: .bold13) / 2 - 8
            surface.drawCircle(x: iconX + 2, y: cy - 5, radius: 5, colour: Colour.greyC6, alpha: 255)
            surface.drawCircle(x: iconX + 2, y: cy - 5, radius: 4, colour: Colour.black, alpha: 255)
            surface.drawString("c", x: iconX, y: cy - 2, font: .regular11, colour: Colour.greyC6)
            surface.drawStringCentre(date, x: cx, y: cy, font: .bold13, colour: Colour.greyC6)
        }
        draw()
    }

    /// mudclient_read_data_file: reads a cache archive, drawing the same progress frames.
    public func readDataFile(_ file: String, _ description: String, _ percent: Int) -> JagArchive? {
        drawLoadingProgress(percent, "Loading \(description) - 0%")
        let url = cacheDirectory.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url), data.count >= 6 else { return nil }
        drawLoadingProgress(percent, "Loading \(description) - 5%")
        drawLoadingProgress(percent, "Loading \(description) - 100%")
        drawLoadingProgress(percent, "Unpacking \(description)")
        return try? JagArchive(fileBytes: [UInt8](data))
    }

    public func loadJagex() {
        guard let jag = readDataFile("jagex.jag", "Jagex library", 0) else { return }
        try? MediaLoader.loadJagex(jag, into: surface, lowmem: options.lowmem != 0)
    }

    public func loadGameConfig() {
        guard let jag = readDataFile("config\(options.versionConfig).jag", "Configuration", 10),
              let data = try? GameData(config: jag, members: options.members != 0, version: options.versionConfig)
        else { errorLoadingData = true; return }
        gameData = data
        if options.members != 0 && options.renameHerblawItems != 0 {
            gameData.modifyUnidentifiedHerbs()
            gameData.modifyUnfinishedPotions()
        }
        if options.renameHerblawItems != 0 { gameData.modifyPotionDosage() }
    }

    public func loadMedia() {
        guard let jag = readDataFile("media\(options.versionMedia).jag", "2d graphics", 20) else {
            errorLoadingData = true; return
        }
        do {
            try MediaLoader.loadMedia(jag, into: surface, gameData: gameData, version: options.versionMedia,
                                      lowmem: options.lowmem != 0)
        } catch { errorLoadingData = true }
    }

    public func loadEntities() {
        guard let entityJag = readDataFile("entity\(options.versionEntity).jag", "people and monsters", 30) else {
            errorLoadingData = true; return
        }
        var legacyJag: JagArchive?
        if options.tgaSprites != 0 { legacyJag = readDataFile("entity8.jag", "people and monsters", 37) }
        let entityIsTGA = CacheVersion.entityIsTGA(options.versionEntity)
        if entityIsTGA { legacyJag = entityJag }
        let index = (try? entityJag.file("index.dat")) ?? nil
        var memJag: JagArchive?
        var memIndex: [UInt8]?
        if options.members != 0 && !entityIsTGA {
            guard let jag = readDataFile("entity\(options.versionEntity).mem", "member graphics", 45) else {
                errorLoadingData = true; return
            }
            memJag = jag
            memIndex = (try? jag.file("index.dat")) ?? nil
        }

        func find(_ name: String, _ archive: JagArchive?) -> ([UInt8], [UInt8]?)? {
            if let d = (try? archive?.file(name)) ?? nil { return (d, index) }
            if options.members != 0, let d = (try? memJag?.file(name)) ?? nil { return (d, memIndex) }
            return nil
        }
        func parse(_ id: Int, _ found: ([UInt8], [UInt8]?), _ frames: Int, _ tga: Bool) {
            if tga {
                try? surface.parseSpriteTGA(id: id, data: found.0, columns: frames, rows: 1)
            } else if let idx = found.1 {
                surface.parseSprite(id: id, spriteData: found.0, indexData: idx, frameCount: frames)
            }
        }

        var animationIndex = 0
        var i = 0
        outer: while i < gameData.animations.count {
            let name = gameData.animations[i].name
            for j in 0..<i where gameData.animations[j].name == name {
                gameData.animations[i].fileId = gameData.animations[j].fileId
                i += 1
                continue outer
            }
            var olderIsBetter = false
            var ext = "dat"
            var archive: JagArchive? = entityJag
            if entityIsTGA {
                olderIsBetter = true
                ext = "tga"
            } else if options.tgaSprites != 0 && Mudclient.animsOlderIsBetter.contains(name) {
                olderIsBetter = true
                ext = "tga"
                archive = legacyJag
            }
            if let found = find("\(name).\(ext)", archive) {
                parse(animationIndex, found, 15, olderIsBetter)
                var skipF = false
                if gameData.animations[i].hasA != 0 {
                    if olderIsBetter && name == "camel" {
                        olderIsBetter = false
                        ext = "dat"
                        archive = entityJag
                    }
                    if let a = find("\(name)a.\(ext)", archive) {
                        parse(animationIndex + 15, a, 3, olderIsBetter)
                    } else {
                        skipF = true
                    }
                }
                if !skipF && gameData.animations[i].hasF != 0, let f = find("\(name)f.\(ext)", archive) {
                    parse(animationIndex + 18, f, 9, olderIsBetter)
                }
                if gameData.animations[i].gender != 0 {
                    for j in animationIndex..<(animationIndex + 27) { surface.loadSprite(id: j) }
                }
            }
            gameData.animations[i].fileId = animationIndex
            animationIndex += 27
            i += 1
        }
    }

    public func loadTextures() {
        guard let jag = readDataFile("textures\(options.versionTextures).jag", "Textures", 50) else {
            errorLoadingData = true; return
        }
        do { try MediaLoader.loadTextures(jag, into: surface, scene: scene, gameData: gameData) } catch {
            errorLoadingData = true
        }
    }

    public func loadModels() {
        if options.lowmem == 0 {
            for name in Mudclient.animatedModels { _ = gameData.modelIndex(name) }
        }
        let file = "models\(options.versionModels).jag"
        guard let jag = readDataFile(file, "3d models", 60) else { errorLoadingData = true; return }
        for i in 0..<gameData.modelNames.count {
            let name = gameData.modelNames[i]
            let model: GameModel
            if let data = (try? jag.file("\(name).ob3")) ?? nil {
                model = GameModel(ob3: data)
            } else {
                model = GameModel(vertices: 1, faces: 1)
            }
            if name == "giantcrystal" { model.transparent = true }
            gameModels[i] = model
        }
        if options.groundItemModels != 0 {
            let maxSprite = gameData.items.map(\.sprite).max() ?? 0
            itemModels = Array(repeating: nil, count: maxSprite)
            for i in 0..<maxSprite {
                if let data = (try? jag.file("item-\(i).ob3")) ?? nil { itemModels[i] = GameModel(ob3: data) }
            }
        }
    }

    public func loadMaps() {
        let v = options.versionMaps
        world.mapPack = readDataFile("maps\(v).jag", "map", 70)
        if options.members != 0 { world.memberMapPack = readDataFile("maps\(v).mem", "members map", 75) }
        if CacheVersion.hasSeparateLand(v) {
            world.landscapePack = readDataFile("land\(v).jag", "landscape", 80)
            if options.members != 0 {
                world.memberLandscapePack = readDataFile("land\(v).mem", "members landscape", 85)
            }
        }
    }

    public func loadSounds() {
        guard let jag = readDataFile("sounds\(options.versionSounds).mem", "Sound effects", 90) else { return }
        soundData = jag.body
    }

    /// mudclient_start_game: loads everything and builds the login screen.
    public func startGame() {
        loadGameConfig()
        if errorLoadingData { return }
        setTargetFps(50)
        Panel.baseSpriteStart = spriteUtil
        createTabPanels()

        loadMedia()
        if errorLoadingData { return }
        loadEntities()
        if errorLoadingData { return }

        scene = options.lowmem != 0
            ? Scene(surface: surface, modelCount: 7500, polygonCount: 7500, maxSpriteCount: 1000)
            : Scene(surface: surface, modelCount: 15000, polygonCount: 15000, maxSpriteCount: 1000)
        scene.setBounds(width: gameWidth, height: gameHeight - 12)
        scene.clipFar3d = 2400
        scene.clipFar2d = 2400
        scene.fogZDistance = 2300

        world = World(scene: scene, surface: surface, gameData: gameData, version: options.versionMaps)
        world.baseMediaSprite = spriteMedia
        world.thickWalls = options.thickWalls != 0

        loadTextures()
        if errorLoadingData { return }
        loadModels()
        if errorLoadingData { return }
        loadMaps()
        if errorLoadingData { return }
        if options.members != 0 && options.lowmem == 0 { loadSounds() }

        drawLoadingProgress(100, "Starting game...")
        createMessageTabsPanel()
        createLoginPanels()
        createAppearancePanel()
        createOptionsPanel()
        resetLoginScreen()
        worldlistNew()
        if options.lowmem == 0 { renderLoginSceneSprites() }
    }

    /// The quest, magic and social list panels built at the top of mudclient_start_game.
    func createTabPanels() {
        let touch = isTouchLayout
        var x = Mudclient.width - 199
        var y = UITabs.buttonSize + 1
        panelQuests = makePanel(5)
        panelQuests.forceDesktopLists = true
        if touch {
            x = uiTabsTouchX - StatsTab.width - 1
            y = (uiTabsTouchY + UITabs.touchHeight) - StatsTab.compactHeight - StatsTab.tabHeight - 5
        }
        controlListQuest = panelQuests.addTextListInteractive(
            x: x, y: y + StatsTab.tabHeight, width: StatsTab.width, height: StatsTab.height - StatsTab.tabHeight,
            font: .bold12, maxLength: 500, alternativeColour: true)
        panelMagic = makePanel(5)
        if touch {
            x = uiTabsTouchX - MagicTab.width - 1
            y = uiTabsTouchY + 10
        }
        controlListMagic = panelMagic.addTextListInteractive(
            x: x, y: y + MagicTab.tabHeight - (touch ? 11 : 0), width: MagicTab.width, height: 90 + (touch ? 16 : 0),
            font: .bold12, maxLength: 500, alternativeColour: true)
        panelSocialList = makePanel(5)
        controlListSocial = panelSocialList.addTextListInteractive(
            x: x, y: y + SocialTab.tabHeight + 16 - (touch ? 11 : 0), width: 196, height: 126 + (touch ? 16 : 0),
            font: .bold12, maxLength: 500, alternativeColour: true)
    }

    func makePanel(_ max: Int) -> Panel {
        let p = Panel(surface: surface, max: max)
        p.host = self
        return p
    }

    var uiTabsTouchX: Int { surface.width - UITabs.buttonSize - 11 }
    var uiTabsTouchY: Int { (surface.height - UITabs.touchHeight) - 30 }

    // MARK: - Drawing helpers

    public func drawBlueBar() {
        var bars = 1
        if surface.width > Mudclient.hbarWidth { bars += surface.width / Mudclient.hbarWidth }
        for i in 0..<bars {
            surface.drawSprite(x: i * Mudclient.hbarWidth, y: surface.height - 16 + (surface.height < 268 ? 4 : 0),
                               id: spriteMedia + 22)
        }
    }

    public func triggerKeyboard(text: String, isPassword: Bool, x: Int, y: Int, width: Int, height: Int,
                                font: FontStyle, isCentred: Bool) {
        host?.triggerKeyboard(text: text, isPassword: isPassword, x: x, y: y, width: width, height: height,
                              font: font, isCentred: isCentred)
    }
}

public enum UITabs {
    public static let width = 245
    public static let buttonSize = 35
    public static let touchHeight = (buttonSize - 2) * 6 + 1
    public static let labelHeight = 10
    public static let inventory = 1, map = 2, stats = 3, magic = 4, social = 5, options = 6
}

public enum StatsTab {
    public static let width = 196, height = 275, compactHeight = 171, tabHeight = 24

    public static let shortSkillNames = [
        "Attack", "Defense", "Strength", "Hits", "Ranged", "Prayer", "Magic", "Cooking", "Woodcut",
        "Fletching", "Fishing", "Firemaking", "Crafting", "Smithing", "Mining", "Herblaw", "Agility", "Thieving"]
    public static let skillNames = [
        "Attack", "Defense", "Strength", "Hits", "Ranged", "Prayer", "Magic", "Cooking", "Woodcutting",
        "Fletching", "Fishing", "Firemaking", "Crafting", "Smithing", "Mining", "Herblaw", "Agility", "Thieving"]
    public static let equipmentStatNames = ["Armour", "WeaponAim", "WeaponPower", "Magic", "Prayer"]
    static let freeQuests = [
        "Black knight's fortress", "Cook's assistant", "Demon slayer", "Doric's quest", "The restless ghost",
        "Goblin diplomacy", "Ernest the chicken", "Imp catcher", "Pirate's treasure", "Prince Ali rescue",
        "Romeo & Juliet", "Sheep shearer", "Shield of Arrav", "The knight's sword", "Vampire slayer",
        "Witch's potion", "Dragon slayer"]
    static let membersQuests = [
        "Witch's house", "Lost city", "Hero's quest", "Druidic ritual", "Merlin's crystal", "Scorpion catcher",
        "Family crest", "Tribal totem", "Fishing contest", "Monk's friend", "Temple of Ikov", "Clock tower",
        "The Holy Grail", "Fight Arena", "Tree Gnome Village", "The Hazeel Cult", "Sheep Herder", "Plague City",
        "Sea Slug", "Waterfall quest", "Biohazard", "Jungle potion", "Grand tree", "Shilo village",
        "Underground pass", "Observatory quest", "Tourist trap", "Watchtower", "Dwarf Cannon", "Murder Mystery",
        "Digsite", "Gertrude's Cat", "Legend's Quest"]
    /// quest_names: members quests carry a " (members)" suffix.
    public static let questNames = freeQuests + membersQuests.map { "\($0) (members)" }

    /// experience_array: total experience needed for each level (init_stats_tab_global).
    public static let experienceArray: [Int] = {
        var out = [Int](repeating: 0, count: 100)
        var total: Int32 = 0
        for i in 0..<99 {
            let level = i + 1
            let exp = Int32(Double(level) + 300 * pow(2, Double(Float(level) / 7)))
            total = total &+ exp
            out[i] = Int(total & 0xffffffc)
        }
        return out
    }()
}

public enum MagicTab {
    public static let width = 196, height = 182, tabHeight = 24
}

public enum SocialTab {
    public static let width = 196, height = 182, tabHeight = 24
    public static let dialogAddWidth = 300, dialogHeight = 70, cancelSize = 40
    public static let friendOnline = 255
    public static let addFriend = 1, messageFriend = 2, addIgnore = 3
}

extension Mudclient: PanelHost {
    public var isTouch: Bool { isTouchLayout }
    public var offHandleScrollDrag: Bool { options.offHandleScrollDrag != 0 }
}
