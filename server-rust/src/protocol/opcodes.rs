//! RSC protocol opcodes for client and server communication.

/// Incoming opcodes (client -> server).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum OpcodeIn {
    // Session opcodes
    Login = 0,
    Logout = 1,
    Ping = 5,

    // Movement opcodes
    WalkToPoint = 16,
    WalkToEntity = 17,

    // Chat opcodes
    PublicChat = 30,
    PrivateMessage = 31,
    AddFriend = 32,
    RemoveFriend = 33,
    AddIgnore = 34,
    RemoveIgnore = 35,

    // Player interaction
    AttackPlayer = 40,
    FollowPlayer = 41,
    TradeRequest = 42,
    DuelRequest = 43,

    // NPC interaction
    AttackNpc = 50,
    TalkToNpc = 51,
    UseItemOnNpc = 52,
    CastSpellOnNpc = 53,

    // Object interaction
    UseObject = 60,
    UseItemOnObject = 61,

    // Ground item interaction
    PickupItem = 70,
    DropItem = 71,
    UseItemOnGroundItem = 72,

    // Inventory
    WieldItem = 80,
    UnwieldItem = 81,
    UseItem = 82,
    UseItemOnItem = 83,

    // Skills
    PrayerActivated = 90,
    PrayerDeactivated = 91,
    CastSpell = 92,
    CastSpellOnSelf = 93,

    // Trading
    TradeAccept = 100,
    TradeDecline = 101,
    TradeUpdate = 102,
    TradeConfirm = 103,

    // Dueling
    DuelAccept = 110,
    DuelDecline = 111,
    DuelUpdate = 112,
    DuelConfirm = 113,

    // Banking
    BankOpen = 120,
    BankClose = 121,
    BankDeposit = 122,
    BankWithdraw = 123,

    // Shop
    ShopOpen = 130,
    ShopClose = 131,
    ShopBuy = 132,
    ShopSell = 133,

    // Settings
    SettingsUpdate = 140,
    PrivacySettings = 141,

    // Commands
    Command = 200,

    // Unknown/invalid
    Unknown = 255,
}

impl From<u8> for OpcodeIn {
    fn from(value: u8) -> Self {
        match value {
            0 => OpcodeIn::Login,
            1 => OpcodeIn::Logout,
            5 => OpcodeIn::Ping,
            16 => OpcodeIn::WalkToPoint,
            17 => OpcodeIn::WalkToEntity,
            30 => OpcodeIn::PublicChat,
            31 => OpcodeIn::PrivateMessage,
            32 => OpcodeIn::AddFriend,
            33 => OpcodeIn::RemoveFriend,
            34 => OpcodeIn::AddIgnore,
            35 => OpcodeIn::RemoveIgnore,
            40 => OpcodeIn::AttackPlayer,
            41 => OpcodeIn::FollowPlayer,
            42 => OpcodeIn::TradeRequest,
            43 => OpcodeIn::DuelRequest,
            50 => OpcodeIn::AttackNpc,
            51 => OpcodeIn::TalkToNpc,
            52 => OpcodeIn::UseItemOnNpc,
            53 => OpcodeIn::CastSpellOnNpc,
            60 => OpcodeIn::UseObject,
            61 => OpcodeIn::UseItemOnObject,
            70 => OpcodeIn::PickupItem,
            71 => OpcodeIn::DropItem,
            72 => OpcodeIn::UseItemOnGroundItem,
            80 => OpcodeIn::WieldItem,
            81 => OpcodeIn::UnwieldItem,
            82 => OpcodeIn::UseItem,
            83 => OpcodeIn::UseItemOnItem,
            90 => OpcodeIn::PrayerActivated,
            91 => OpcodeIn::PrayerDeactivated,
            92 => OpcodeIn::CastSpell,
            93 => OpcodeIn::CastSpellOnSelf,
            100 => OpcodeIn::TradeAccept,
            101 => OpcodeIn::TradeDecline,
            102 => OpcodeIn::TradeUpdate,
            103 => OpcodeIn::TradeConfirm,
            110 => OpcodeIn::DuelAccept,
            111 => OpcodeIn::DuelDecline,
            112 => OpcodeIn::DuelUpdate,
            113 => OpcodeIn::DuelConfirm,
            120 => OpcodeIn::BankOpen,
            121 => OpcodeIn::BankClose,
            122 => OpcodeIn::BankDeposit,
            123 => OpcodeIn::BankWithdraw,
            130 => OpcodeIn::ShopOpen,
            131 => OpcodeIn::ShopClose,
            132 => OpcodeIn::ShopBuy,
            133 => OpcodeIn::ShopSell,
            140 => OpcodeIn::SettingsUpdate,
            141 => OpcodeIn::PrivacySettings,
            200 => OpcodeIn::Command,
            _ => OpcodeIn::Unknown,
        }
    }
}

/// Outgoing opcodes (server -> client).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum OpcodeOut {
    // Session opcodes
    LoginResponse = 0,
    Logout = 1,

    // World updates
    PlayerPositionUpdate = 10,
    NpcPositionUpdate = 11,
    GroundItemUpdate = 12,
    GameObjectUpdate = 13,
    WallObjectUpdate = 14,

    // Player updates
    PlayerAppearance = 20,
    PlayerStats = 21,
    PlayerInventory = 22,
    PlayerEquipment = 23,
    PlayerSettings = 24,

    // Chat
    ChatMessage = 30,
    PrivateMessage = 31,
    ServerMessage = 32,
    QuestMessage = 33,

    // Combat
    DamageUpdate = 40,
    DeathScreen = 41,

    // Interface
    OpenBank = 50,
    OpenShop = 51,
    OpenTrade = 52,
    OpenDuel = 53,
    CloseInterface = 54,

    // Dialogue
    NpcDialogue = 60,
    OptionDialogue = 61,

    // Sound/Effects
    PlaySound = 70,
    Teleport = 71,
    Bubble = 72,

    // Friends/Ignore
    FriendList = 80,
    FriendUpdate = 81,
    IgnoreList = 82,

    // Skills
    StatUpdate = 90,
    ExperienceUpdate = 91,
    FatigueUpdate = 92,

    // Misc
    WorldInfo = 100,
    SystemUpdate = 101,
}

impl From<OpcodeOut> for u8 {
    fn from(opcode: OpcodeOut) -> Self {
        opcode as u8
    }
}
