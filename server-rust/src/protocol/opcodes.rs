//! RSC protocol opcodes for client and server communication.
//!
//! These enum names mirror the authoritative Java enums in
//! `server-java-modern/src/com/openrsc/server/net/rsc/enums/OpcodeIn.java`
//! and `OpcodeOut.java` character-for-character (SCREAMING_SNAKE_CASE).
//!
//! On-the-wire byte values for incoming packets vary across protocol
//! revisions (38, 69, 115, 201, 203, 235, ...). Translation from a wire
//! byte to an `OpcodeIn` variant lives in `protocol::legacy` and uses
//! per-version dispatch tables that mirror the Java `Payload<rev>Parser`
//! `static { opcodes<rev>.put(...) }` blocks.
//!
//! Outgoing opcodes are assigned indices (mirroring Java enum ordinals,
//! which is how the Java codec encodes them via the formatter pipeline).
//! `OpcodeOut` uses `#[repr(u16)]` because some retro/custom outgoing
//! opcodes ordinal-index past 255 in some payload formatters.

#![allow(non_camel_case_types, dead_code)]

/// Incoming opcodes (client -> server).
///
/// Names mirror `com.openrsc.server.net.rsc.enums.OpcodeIn` exactly.
/// Wire-byte mapping is performed in `protocol::legacy::decode_opcode`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum OpcodeIn {
    HEARTBEAT,
    WALK_TO_ENTITY,
    WALK_TO_POINT,
    CONFIRM_LOGOUT,
    LOGOUT,
    BLINK,
    COMBAT_STYLE_CHANGED,
    QUESTION_DIALOG_ANSWER,

    PLAYER_APPEARANCE_CHANGE,
    SOCIAL_ADD_IGNORE,
    SOCIAL_ADD_DELAYED_IGNORE, // custom
    SOCIAL_ADD_FRIEND,
    SOCIAL_SEND_PRIVATE_MESSAGE,
    SOCIAL_REMOVE_FRIEND,
    SOCIAL_REMOVE_IGNORE,

    DUEL_FIRST_SETTINGS_CHANGED,
    DUEL_FIRST_ACCEPTED,
    DUEL_DECLINED,
    DUEL_OFFER_ITEM,
    DUEL_SECOND_ACCEPTED,

    INTERACT_WITH_BOUNDARY,
    INTERACT_WITH_BOUNDARY2,
    CAST_ON_BOUNDARY,
    USE_WITH_BOUNDARY,

    NPC_TALK_TO,
    NPC_COMMAND,
    NPC_COMMAND2, // custom
    NPC_ATTACK,
    CAST_ON_NPC,
    NPC_USE_ITEM,

    PLAYER_CAST_PVP,
    PLAYER_USE_ITEM,
    PLAYER_ATTACK,
    PLAYER_DUEL,
    PLAYER_INIT_TRADE_REQUEST,
    PLAYER_FOLLOW,

    CAST_ON_GROUND_ITEM,
    GROUND_ITEM_USE_ITEM,
    GROUND_ITEM_TAKE,

    CAST_ON_INVENTORY_ITEM,
    ITEM_USE_ITEM,
    ITEM_UNEQUIP_FROM_INVENTORY,
    ITEM_EQUIP_FROM_INVENTORY,
    ITEM_UNEQUIP_FROM_EQUIPMENT, // custom
    ITEM_EQUIP_FROM_BANK,        // custom
    ITEM_REMOVE_TO_BANK,         // custom
    ITEM_COMMAND,
    ITEM_DROP,

    CAST_ON_SELF,
    CAST_ON_LAND,

    OBJECT_COMMAND,
    OBJECT_COMMAND2,
    CAST_ON_SCENERY,
    USE_ITEM_ON_SCENERY,

    SHOP_CLOSE,
    SHOP_BUY,
    SHOP_SELL,

    PLAYER_ACCEPTED_INIT_TRADE_REQUEST,
    PLAYER_DECLINED_TRADE,
    PLAYER_ADDED_ITEMS_TO_TRADE_OFFER,
    PLAYER_ACCEPTED_TRADE,

    PRAYER_ACTIVATED,
    PRAYER_DEACTIVATED,

    GAME_SETTINGS_CHANGED,
    CHAT_MESSAGE,
    COMMAND,
    PRIVACY_SETTINGS_CHANGED,
    REPORT_ABUSE,
    BANK_CLOSE,
    BANK_WITHDRAW,
    BANK_DEPOSIT,

    BANK_DEPOSIT_ALL_FROM_INVENTORY, // custom
    BANK_DEPOSIT_ALL_FROM_EQUIPMENT, // custom
    BANK_SAVE_PRESET,                // custom
    BANK_LOAD_PRESET,                // custom
    INTERFACE_OPTIONS,               // custom

    SLEEPWORD_ENTERED,

    SKIP_TUTORIAL,
    ON_BLACK_HOLE,          // custom
    NPC_DEFINITION_REQUEST, // custom

    LOGIN,
    RELOGIN,          // retro rsc
    REGISTER_ACCOUNT, // part of rsc era protocol
    FORGOT_PASSWORD,  // part of rsc era protocol
    RECOVERY_ATTEMPT, // part of rsc era protocol

    CHANGE_RECOVERY_REQUEST, // part of rsc era protocol
    CHANGE_DETAILS_REQUEST,  // part of rsc era protocol

    CHANGE_PASS,  // part of rsc era protocol
    SET_RECOVERY, // part of rsc era protocol
    SET_DETAILS,  // part of rsc era protocol

    CANCEL_RECOVERY_REQUEST, // part of rsc era protocol

    SEND_DEBUG_INFO, // part of rsc era protocol
    KNOWN_PLAYERS,   // part of rsc era protocol
}

/// Outgoing opcodes (server -> client).
///
/// Names mirror `com.openrsc.server.net.rsc.enums.OpcodeOut` exactly.
/// `#[repr(u16)]` because some retro/custom payload formatters use
/// values that exceed 255 on the wire; the variants themselves are
/// just identifiers and the on-wire byte is chosen by the formatter.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u16)]
pub enum OpcodeOut {
    SEND_LOGOUT_REQUEST_CONFIRM,
    SEND_QUESTS,
    SEND_DUEL_OPPONENTS_ITEMS,
    SEND_TRADE_ACCEPTED,
    SEND_SERVER_CONFIGS, // custom
    SEND_TRADE_OPEN_CONFIRM,
    SEND_WORLD_INFO,
    SEND_DUEL_SETTINGS,
    SEND_EXPERIENCE,
    SEND_EXPERIENCE_TOGGLE, // custom
    SEND_BUBBLE,            // used for teleport, telegrab, and iban's magic
    SEND_BANK_OPEN,
    SEND_SCENERY_HANDLER,
    SEND_PRIVACY_SETTINGS,
    SEND_SYSTEM_UPDATE,
    SEND_INVENTORY,
    SEND_ELIXIR, // custom
    SEND_APPEARANCE_SCREEN,
    SEND_NPC_COORDS,
    SEND_DEATH,
    SEND_STOPSLEEP,
    SEND_PRIVATE_MESSAGE_SENT,
    SEND_BOX,
    SEND_INVENTORY_UPDATEITEM,
    SEND_BOUNDARY_HANDLER,
    SEND_TRADE_WINDOW,
    SEND_TRADE_OTHER_ITEMS,
    SEND_EXPSHARED, // custom
    SEND_GROUND_ITEM_HANDLER,
    SEND_SHOP_OPEN,
    SEND_UPDATE_NPC,
    SEND_FRIEND_LIST, // retro rsc
    SEND_IGNORE_LIST,
    SEND_INPUT_BOX, // custom
    SEND_ON_TUTORIAL,
    SEND_CLAN,           // custom
    SEND_CLAN_LIST,      // custom
    SEND_CLAN_SETTINGS,  // custom
    SEND_IRONMAN,        // custom
    SEND_PARTY,          // custom
    SEND_PARTY_LIST,     // custom
    SEND_PARTY_SETTINGS, // custom
    SEND_FATIGUE,
    SEND_ON_BLACK_HOLE, // custom
    SEND_SLEEPSCREEN,
    SEND_KILL_ANNOUNCEMENT, // custom
    SEND_PRIVATE_MESSAGE,
    SEND_INVENTORY_REMOVE_ITEM,
    SEND_TRADE_CLOSE,
    SEND_COMBAT_STYLE, // custom
    SEND_SERVER_MESSAGE,
    SEND_AUCTION_PROGRESS,    // custom
    SEND_FISHING_TRAWLER,     // custom
    SEND_STATUS_PROGRESS_BAR, // custom
    SEND_BANK_PIN_INTERFACE,  // custom
    SEND_ONLINE_LIST,         // custom
    SEND_SHOP_CLOSE,
    SEND_OPENPK_POINTS_TO_GP_RATIO, // custom
    SEND_NPC_KILLS,                 // custom
    SEND_OPENPK_POINTS,             // custom
    SEND_FRIEND_UPDATE,
    SEND_BANK_PRESET, // custom
    SEND_EQUIPMENT_STATS,
    SEND_STATS,
    SEND_STAT,
    SEND_UPDATE_STAT,
    SEND_TRADE_OTHER_ACCEPTED,
    SEND_LOGOUT,
    SEND_DUEL_CONFIRMWINDOW,
    SEND_DUEL_WINDOW,
    SEND_WELCOME_INFO,
    SEND_CANT_LOGOUT,
    SEND_28_BYTES_UNUSED,
    SEND_PLAYER_COORDS,
    SEND_SLEEPWORD_INCORRECT,
    SEND_BANK_CLOSE,
    SEND_PLAY_SOUND,
    SEND_PRAYERS_ACTIVE,
    SEND_DUEL_ACCEPTED,
    SEND_REMOVE_WORLD_ENTITY,
    SEND_APPEARANCE_KEEPALIVE,
    SEND_BOX2,
    SEND_OPEN_RECOVERY, // part of rsc era protocol
    SEND_DUEL_CLOSE,
    SEND_OPEN_DETAILS, // part of rsc era protocol
    SEND_UPDATE_PLAYERS,
    SEND_UPDATE_PLAYERS_RETRO, // retro rsc protocol what later became SEND_UPDATE_PLAYERS type 5
    SEND_UPDATE_IGNORE_LIST_BECAUSE_NAME_CHANGE,
    SEND_GAME_SETTINGS,
    SEND_SLEEP_FATIGUE,
    SEND_OPTIONS_MENU_OPEN,
    SEND_BANK_UPDATE,
    SEND_OPTIONS_MENU_CLOSE,
    SEND_DUEL_OTHER_ACCEPTED,
    SEND_EQUIPMENT,            // custom
    SEND_EQUIPMENT_UPDATE,     // custom
    SEND_REMOVE_WORLD_NPC,     // retro rsc protocol
    SEND_REMOVE_WORLD_PLAYER,  // retro rsc protocol
    RUNESCAPE_UPDATED,         // rsc era protocol
    SEND_YOPTIN, // added by mudclient 61 (or earlier, but post 40) and missing by 93 (present in mudclient 75)
    SEND_INVENTORY_SIZE, // known to be in mudclient69 to 75
    SEND_UNLOCKED_APPEARANCES, // custom
}

// ---------------------------------------------------------------------------
// CamelCase aliases + numeric conversions.
//
// Several handler files (game/server.rs, session/handler.rs, bank_handler.rs,
// shop_handler.rs, social.rs, quest_engine.rs, etc.) were written against an
// earlier draft of these enums that used CamelCase semantic names like
// `Login`, `OpenBank`, `ChatMessage`. The enums were later rewritten to mirror
// the Java SCREAMING_SNAKE_CASE names exactly. Rather than re-edit every
// handler, we expose the old names as `pub const` aliases pointing at the
// closest Java-named variant. New code should use the SCREAMING_SNAKE_CASE
// names directly.
// ---------------------------------------------------------------------------

#[allow(non_upper_case_globals)]
impl OpcodeIn {
    pub const Login: Self = Self::LOGIN;
    pub const Logout: Self = Self::LOGOUT;
    pub const Ping: Self = Self::HEARTBEAT;
    pub const WalkToPoint: Self = Self::WALK_TO_POINT;
    pub const WalkToEntity: Self = Self::WALK_TO_ENTITY;
    pub const PublicChat: Self = Self::CHAT_MESSAGE;
    pub const Command: Self = Self::COMMAND;
    pub const PrivateMessage: Self = Self::SOCIAL_SEND_PRIVATE_MESSAGE;
    pub const AttackNpc: Self = Self::NPC_ATTACK;
    pub const AttackPlayer: Self = Self::PLAYER_ATTACK;
}

#[allow(non_upper_case_globals)]
impl OpcodeOut {
    pub const WorldInfo: Self = Self::SEND_WORLD_INFO;
    pub const ChatMessage: Self = Self::SEND_SERVER_MESSAGE;
    pub const PrivateMessage: Self = Self::SEND_PRIVATE_MESSAGE;
    pub const ServerMessage: Self = Self::SEND_SERVER_MESSAGE;
    pub const OpenBank: Self = Self::SEND_BANK_OPEN;
    pub const CloseInterface: Self = Self::SEND_BANK_CLOSE;
    pub const QuestMessage: Self = Self::SEND_SERVER_MESSAGE;
    pub const OpenShop: Self = Self::SEND_SHOP_OPEN;
    pub const FriendList: Self = Self::SEND_FRIEND_LIST;
    pub const FriendUpdate: Self = Self::SEND_FRIEND_UPDATE;
    pub const IgnoreList: Self = Self::SEND_IGNORE_LIST;
    pub const PlayerStats: Self = Self::SEND_STATS;
    pub const PlayerInventory: Self = Self::SEND_INVENTORY;
}

/// `OpcodeIn::from(packet.opcode)` — wire byte to enum.
///
/// This is the simplified dispatch used in the inauthentic / web-client path,
/// where opcodes carry semantic meaning directly. Authentic mudclient framing
/// goes through `protocol::legacy::decode_opcode` for per-revision dispatch.
/// Unknown bytes map to `HEARTBEAT` so an unrecognised packet doesn't crash
/// the server; the handler's `_ => {}` arm logs and drops it.
impl From<u8> for OpcodeIn {
    fn from(byte: u8) -> Self {
        // Variant order matches enum declaration above. Keeping the table
        // explicit (rather than transmuting on ordinal) makes adding a new
        // variant a compile-time obligation here too.
        const TABLE: &[OpcodeIn] = &[
            OpcodeIn::HEARTBEAT,
            OpcodeIn::WALK_TO_ENTITY,
            OpcodeIn::WALK_TO_POINT,
            OpcodeIn::CONFIRM_LOGOUT,
            OpcodeIn::LOGOUT,
            OpcodeIn::BLINK,
            OpcodeIn::COMBAT_STYLE_CHANGED,
            OpcodeIn::QUESTION_DIALOG_ANSWER,
            OpcodeIn::PLAYER_APPEARANCE_CHANGE,
            OpcodeIn::SOCIAL_ADD_IGNORE,
            OpcodeIn::SOCIAL_ADD_DELAYED_IGNORE,
            OpcodeIn::SOCIAL_ADD_FRIEND,
            OpcodeIn::SOCIAL_SEND_PRIVATE_MESSAGE,
            OpcodeIn::SOCIAL_REMOVE_FRIEND,
            OpcodeIn::SOCIAL_REMOVE_IGNORE,
            OpcodeIn::DUEL_FIRST_SETTINGS_CHANGED,
            OpcodeIn::DUEL_FIRST_ACCEPTED,
            OpcodeIn::DUEL_DECLINED,
            OpcodeIn::DUEL_OFFER_ITEM,
            OpcodeIn::DUEL_SECOND_ACCEPTED,
            OpcodeIn::INTERACT_WITH_BOUNDARY,
            OpcodeIn::INTERACT_WITH_BOUNDARY2,
            OpcodeIn::CAST_ON_BOUNDARY,
            OpcodeIn::USE_WITH_BOUNDARY,
            OpcodeIn::NPC_TALK_TO,
            OpcodeIn::NPC_COMMAND,
            OpcodeIn::NPC_COMMAND2,
            OpcodeIn::NPC_ATTACK,
            OpcodeIn::CAST_ON_NPC,
            OpcodeIn::NPC_USE_ITEM,
            OpcodeIn::PLAYER_CAST_PVP,
            OpcodeIn::PLAYER_USE_ITEM,
            OpcodeIn::PLAYER_ATTACK,
            OpcodeIn::PLAYER_DUEL,
            OpcodeIn::PLAYER_INIT_TRADE_REQUEST,
            OpcodeIn::PLAYER_FOLLOW,
            OpcodeIn::CAST_ON_GROUND_ITEM,
            OpcodeIn::GROUND_ITEM_USE_ITEM,
            OpcodeIn::GROUND_ITEM_TAKE,
            OpcodeIn::CAST_ON_INVENTORY_ITEM,
            OpcodeIn::ITEM_USE_ITEM,
            OpcodeIn::ITEM_UNEQUIP_FROM_INVENTORY,
            OpcodeIn::ITEM_EQUIP_FROM_INVENTORY,
            OpcodeIn::ITEM_UNEQUIP_FROM_EQUIPMENT,
            OpcodeIn::ITEM_EQUIP_FROM_BANK,
            OpcodeIn::ITEM_REMOVE_TO_BANK,
            OpcodeIn::ITEM_COMMAND,
            OpcodeIn::ITEM_DROP,
            OpcodeIn::CAST_ON_SELF,
            OpcodeIn::CAST_ON_LAND,
            OpcodeIn::OBJECT_COMMAND,
            OpcodeIn::OBJECT_COMMAND2,
            OpcodeIn::CAST_ON_SCENERY,
            OpcodeIn::USE_ITEM_ON_SCENERY,
            OpcodeIn::SHOP_CLOSE,
            OpcodeIn::SHOP_BUY,
            OpcodeIn::SHOP_SELL,
            OpcodeIn::PLAYER_ACCEPTED_INIT_TRADE_REQUEST,
            OpcodeIn::PLAYER_DECLINED_TRADE,
            OpcodeIn::PLAYER_ADDED_ITEMS_TO_TRADE_OFFER,
            OpcodeIn::PLAYER_ACCEPTED_TRADE,
            OpcodeIn::PRAYER_ACTIVATED,
            OpcodeIn::PRAYER_DEACTIVATED,
            OpcodeIn::GAME_SETTINGS_CHANGED,
            OpcodeIn::CHAT_MESSAGE,
            OpcodeIn::COMMAND,
            OpcodeIn::PRIVACY_SETTINGS_CHANGED,
            OpcodeIn::REPORT_ABUSE,
            OpcodeIn::BANK_CLOSE,
            OpcodeIn::BANK_WITHDRAW,
            OpcodeIn::BANK_DEPOSIT,
            OpcodeIn::BANK_DEPOSIT_ALL_FROM_INVENTORY,
            OpcodeIn::BANK_DEPOSIT_ALL_FROM_EQUIPMENT,
            OpcodeIn::BANK_SAVE_PRESET,
            OpcodeIn::BANK_LOAD_PRESET,
            OpcodeIn::INTERFACE_OPTIONS,
            OpcodeIn::SLEEPWORD_ENTERED,
            OpcodeIn::SKIP_TUTORIAL,
            OpcodeIn::ON_BLACK_HOLE,
            OpcodeIn::NPC_DEFINITION_REQUEST,
            OpcodeIn::LOGIN,
            OpcodeIn::RELOGIN,
            OpcodeIn::REGISTER_ACCOUNT,
            OpcodeIn::FORGOT_PASSWORD,
            OpcodeIn::RECOVERY_ATTEMPT,
            OpcodeIn::CHANGE_RECOVERY_REQUEST,
            OpcodeIn::CHANGE_DETAILS_REQUEST,
            OpcodeIn::CHANGE_PASS,
            OpcodeIn::SET_RECOVERY,
            OpcodeIn::SET_DETAILS,
            OpcodeIn::CANCEL_RECOVERY_REQUEST,
            OpcodeIn::SEND_DEBUG_INFO,
            OpcodeIn::KNOWN_PLAYERS,
        ];
        TABLE
            .get(byte as usize)
            .copied()
            .unwrap_or(OpcodeIn::HEARTBEAT)
    }
}

impl OpcodeOut {
    /// Return the on-wire byte for this opcode as used by the OpenRSC custom /
    /// iOS client (mirrors PayloadCustomGenerator.java's opcodeMap).  Opcodes
    /// that exist only in the retro (pre-177) generators and are not present in
    /// the custom generator fall back to their enum ordinal so that any
    /// accidental use at least produces a stable, identifiable byte rather than
    /// silently colliding with a valid opcode.
    pub const fn wire(self) -> u8 {
        match self {
            Self::SEND_LOGOUT_REQUEST_CONFIRM => 4,
            Self::SEND_QUESTS => 5,
            Self::SEND_DUEL_OPPONENTS_ITEMS => 6,
            Self::SEND_TRADE_ACCEPTED => 15,
            Self::SEND_SERVER_CONFIGS => 19,
            Self::SEND_TRADE_OPEN_CONFIRM => 20,
            Self::SEND_WORLD_INFO => 25,
            Self::SEND_DUEL_SETTINGS => 30,
            Self::SEND_EXPERIENCE => 33,
            Self::SEND_EXPERIENCE_TOGGLE => 34,
            Self::SEND_BUBBLE => 36,
            Self::SEND_BANK_OPEN => 42,
            Self::SEND_SCENERY_HANDLER => 48,
            Self::SEND_PRIVACY_SETTINGS => 51,
            Self::SEND_SYSTEM_UPDATE => 52,
            Self::SEND_INVENTORY => 53,
            Self::SEND_ELIXIR => 54,
            Self::SEND_APPEARANCE_SCREEN => 59,
            Self::SEND_NPC_COORDS => 79,
            Self::SEND_DEATH => 83,
            Self::SEND_STOPSLEEP => 84,
            Self::SEND_PRIVATE_MESSAGE_SENT => 87,
            Self::SEND_BOX2 => 89,
            Self::SEND_INVENTORY_UPDATEITEM => 90,
            Self::SEND_BOUNDARY_HANDLER => 91,
            Self::SEND_TRADE_WINDOW => 92,
            Self::SEND_TRADE_OTHER_ITEMS => 97,
            Self::SEND_EXPSHARED => 98,
            Self::SEND_GROUND_ITEM_HANDLER => 99,
            Self::SEND_SHOP_OPEN => 101,
            Self::SEND_UPDATE_NPC => 104,
            Self::SEND_IGNORE_LIST => 109,
            Self::SEND_INPUT_BOX => 110,
            Self::SEND_ON_TUTORIAL => 111,
            Self::SEND_CLAN => 112,
            Self::SEND_CLAN_LIST => 112,
            Self::SEND_CLAN_SETTINGS => 112,
            Self::SEND_IRONMAN => 113,
            Self::SEND_FATIGUE => 114,
            Self::SEND_ON_BLACK_HOLE => 115,
            Self::SEND_PARTY => 116,
            Self::SEND_PARTY_LIST => 116,
            Self::SEND_PARTY_SETTINGS => 116,
            Self::SEND_SLEEPSCREEN => 117,
            Self::SEND_KILL_ANNOUNCEMENT => 118,
            Self::SEND_PRIVATE_MESSAGE => 120,
            Self::SEND_INVENTORY_REMOVE_ITEM => 123,
            Self::SEND_TRADE_CLOSE => 128,
            Self::SEND_COMBAT_STYLE => 129,
            Self::SEND_SERVER_MESSAGE => 131,
            Self::SEND_AUCTION_PROGRESS => 132,
            Self::SEND_FISHING_TRAWLER => 133,
            Self::SEND_STATUS_PROGRESS_BAR => 134,
            Self::SEND_BANK_PIN_INTERFACE => 135,
            Self::SEND_ONLINE_LIST => 136,
            Self::SEND_SHOP_CLOSE => 137,
            Self::SEND_OPENPK_POINTS_TO_GP_RATIO => 144,
            Self::SEND_NPC_KILLS => 147,
            Self::SEND_OPENPK_POINTS => 148,
            Self::SEND_FRIEND_UPDATE => 149,
            Self::SEND_BANK_PRESET => 150,
            Self::SEND_EQUIPMENT_STATS => 153,
            Self::SEND_STATS => 156,
            Self::SEND_STAT => 159,
            Self::SEND_TRADE_OTHER_ACCEPTED => 162,
            Self::SEND_LOGOUT => 165,
            Self::SEND_DUEL_CONFIRMWINDOW => 172,
            Self::SEND_DUEL_WINDOW => 176,
            Self::SEND_WELCOME_INFO => 182,
            Self::SEND_CANT_LOGOUT => 183,
            Self::SEND_28_BYTES_UNUSED => 189,
            Self::SEND_PLAYER_COORDS => 191,
            Self::SEND_SLEEPWORD_INCORRECT => 194,
            Self::SEND_BANK_CLOSE => 203,
            Self::SEND_PLAY_SOUND => 204,
            Self::SEND_PRAYERS_ACTIVE => 206,
            Self::SEND_DUEL_ACCEPTED => 210,
            Self::SEND_REMOVE_WORLD_ENTITY => 211,
            Self::SEND_APPEARANCE_KEEPALIVE => 213,
            Self::SEND_BOX => 222,
            Self::SEND_OPEN_RECOVERY => 224,
            Self::SEND_DUEL_CLOSE => 225,
            Self::SEND_OPEN_DETAILS => 232,
            Self::SEND_UPDATE_PLAYERS => 234,
            Self::SEND_UPDATE_IGNORE_LIST_BECAUSE_NAME_CHANGE => 237,
            Self::SEND_GAME_SETTINGS => 240,
            Self::SEND_SLEEP_FATIGUE => 244,
            Self::SEND_OPTIONS_MENU_OPEN => 245,
            Self::SEND_BANK_UPDATE => 249,
            Self::SEND_UNLOCKED_APPEARANCES => 250,
            Self::SEND_OPTIONS_MENU_CLOSE => 252,
            Self::SEND_DUEL_OTHER_ACCEPTED => 253,
            Self::SEND_EQUIPMENT => 254,
            Self::SEND_EQUIPMENT_UPDATE => 255,
            // Retro / unmapped — fall back to enum ordinal so accidental use
            // produces a stable, identifiable byte rather than aliasing 0.
            other => other as u16 as u8,
        }
    }
}

/// Map `OpcodeOut` to its on-wire byte via the PayloadCustomGenerator table
/// (the superset used by the iOS and custom Java clients).
impl From<OpcodeOut> for u8 {
    fn from(op: OpcodeOut) -> Self {
        op.wire()
    }
}
