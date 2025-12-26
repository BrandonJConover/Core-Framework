namespace OpenRSC.Server.Network;

/// <summary>
/// Incoming packet opcodes from client to server.
/// </summary>
public enum OpcodeIn : byte
{
    // Connection
    Login = 0,
    Logout = 1,
    Ping = 67,

    // Movement
    WalkToPoint = 16,
    WalkToEntity = 187,

    // Combat
    AttackPlayer = 171,
    AttackNpc = 190,
    CastOnPlayer = 229,
    CastOnNpc = 50,
    CastOnSelf = 137,
    CastOnGroundItem = 249,
    CastOnInventoryItem = 158,
    CastOnObject = 99,
    CastOnBoundary = 180,
    CastOnGround = 158,

    // Items
    DropItem = 246,
    PickupItem = 247,
    UseItem = 91,
    UseItemOnObject = 115,
    UseItemOnBoundary = 161,
    UseItemOnNpc = 135,
    UseItemOnPlayer = 113,
    UseItemOnGroundItem = 53,
    UseItemOnItem = 91,
    WieldItem = 169,
    UnwieldItem = 170,

    // Objects
    ObjectAction = 136,
    ObjectAction2 = 79,
    BoundaryAction = 14,
    BoundaryAction2 = 127,

    // NPCs
    NpcTalk = 153,
    NpcCommand = 202,
    NpcUseItem = 135,

    // Player interaction
    TradeRequest = 142,
    TradeAccept = 55,
    TradeDecline = 230,
    TradeConfirm = 104,
    TradeUpdateOffer = 46,
    DuelRequest = 103,
    DuelAccept = 176,
    DuelDecline = 197,
    DuelConfirm = 77,
    DuelUpdateOffer = 33,
    Follow = 165,

    // Chat
    PublicChat = 216,
    PrivateMessage = 218,
    AddFriend = 195,
    RemoveFriend = 167,
    AddIgnore = 132,
    RemoveIgnore = 241,

    // Interface
    BankClose = 212,
    BankDeposit = 23,
    BankWithdraw = 22,
    ShopClose = 166,
    ShopBuy = 236,
    ShopSell = 221,

    // Character
    CharacterDesign = 235,
    ChangeAppearance = 11,
    ChangeSettings = 111,
    CommandString = 38,

    // Misc
    ReportAbuse = 206,
    Sleep = 84,
    SleepWord = 45
}

/// <summary>
/// Outgoing packet opcodes from server to client.
/// </summary>
public enum OpcodeOut : byte
{
    // World updates
    PlayerCoords = 191,
    NpcCoords = 79,
    UpdatePlayers = 234,
    UpdateNpcs = 104,
    SceneryHandler = 48,
    BoundaryHandler = 91,
    GroundItemHandler = 99,
    ClearLocations = 211,

    // Player state
    PlayerStats = 156,
    PlayerStatEquipmentBonus = 153,
    PlayerStatFatigue = 114,
    PlayerStatFatigueAsleep = 244,
    PlayerStatExperience = 33,
    PlayerQuestList = 5,
    PlayerInventory = 53,

    // Combat
    PlayerDied = 83,

    // Interface
    ShowBank = 42,
    HideBank = 171,
    UpdateBankItem = 249,
    ShowShop = 101,
    HideShop = 137,
    ShowDialogue = 245,
    HideDialogue = 252,
    ShowMenu = 245,

    // Chat
    Message = 131,
    PrivateMessageSent = 87,
    PrivateMessageReceived = 120,
    FriendList = 71,
    FriendUpdate = 149,
    IgnoreList = 109,

    // System
    ServerMessage = 131,
    Logout = 4,
    LogoutDeny = 183,
    WorldInfo = 25,

    // Trading
    TradeOpen = 92,
    TradeOwnOffer = 90,
    TradeOtherOffer = 97,
    TradeConfirmation = 93,
    TradeClose = 94,

    // Dueling
    DuelOpen = 163,
    DuelUpdate = 160,
    DuelConfirmation = 172,
    DuelClose = 225,

    // Misc
    PlaySound = 204,
    Teleport = 145,
    ShowSleepScreen = 117,
    WakeUp = 84
}
