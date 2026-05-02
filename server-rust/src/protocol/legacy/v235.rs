//! mudclient235 wire-byte → `OpcodeIn` table.
//!
//! Pure data port of the `toOpcodeEnum` switch/case block in
//! `server-java-modern/src/com/openrsc/server/net/rsc/parsers/impl/Payload235Parser.java`.
//!
//! mudclient235 uses a completely different byte assignment from all earlier
//! revisions. It was released post-2009 for the retro-revival era and adds
//! RSC175 Security Settings, which causes four opcode bytes (4, 8, 197, 247)
//! to be ambiguous depending on whether the player is logged in and what
//! context they're in.
//!
//! ## Conflict resolution (bytes 4, 8, 197, 247)
//!
//! The Java server resolves these at runtime using player state
//! (`player.isLoggedIn()`, `player.getDuel().isDuelActive()`, packet length).
//! The Rust server currently resolves statically by choosing the **logged-in**
//! path (the most common case for a running server):
//!   * 4   → `CAST_ON_INVENTORY_ITEM`  (vs `FORGOT_PASSWORD` pre-login)
//!   * 8   → `DUEL_FIRST_SETTINGS_CHANGED` (vs `RECOVERY_ATTEMPT` pre-login)
//!   * 197 → `DUEL_DECLINED`           (vs `CHANGE_RECOVERY_REQUEST` pre-login)
//!   * 247 → `GROUND_ITEM_TAKE`        (vs `CHANGE_DETAILS_REQUEST` pre-login)
//!
//! Pre-login packets with these bytes will be mis-routed as game actions and
//! silently dropped, which is safe. True runtime disambiguation requires
//! session-state access in the decoder — acceptable future work.

#![allow(dead_code)]

use super::super::opcodes::OpcodeIn;

/// Returns the semantic opcode for a mudclient235 wire byte,
/// or `None` if the byte is unknown for this revision.
///
/// See module-level doc for the static resolution of conflicting bytes.
#[inline]
pub fn decode(byte: u8) -> Option<OpcodeIn> {
    Some(match byte {
        67  => OpcodeIn::HEARTBEAT,
        16  => OpcodeIn::WALK_TO_ENTITY,
        187 => OpcodeIn::WALK_TO_POINT,
        31  => OpcodeIn::CONFIRM_LOGOUT,
        102 => OpcodeIn::LOGOUT,
        59  => OpcodeIn::BLINK,
        29  => OpcodeIn::COMBAT_STYLE_CHANGED,
        116 => OpcodeIn::QUESTION_DIALOG_ANSWER,
        235 => OpcodeIn::PLAYER_APPEARANCE_CHANGE,
        132 => OpcodeIn::SOCIAL_ADD_IGNORE,
        195 => OpcodeIn::SOCIAL_ADD_FRIEND,
        218 => OpcodeIn::SOCIAL_SEND_PRIVATE_MESSAGE,
        167 => OpcodeIn::SOCIAL_REMOVE_FRIEND,
        241 => OpcodeIn::SOCIAL_REMOVE_IGNORE,
        176 => OpcodeIn::DUEL_FIRST_ACCEPTED,
        33  => OpcodeIn::DUEL_OFFER_ITEM,
        77  => OpcodeIn::DUEL_SECOND_ACCEPTED,
        14  => OpcodeIn::INTERACT_WITH_BOUNDARY,
        127 => OpcodeIn::INTERACT_WITH_BOUNDARY2,
        180 => OpcodeIn::CAST_ON_BOUNDARY,
        161 => OpcodeIn::USE_WITH_BOUNDARY,
        153 => OpcodeIn::NPC_TALK_TO,
        202 => OpcodeIn::NPC_COMMAND,
        190 => OpcodeIn::NPC_ATTACK,
        50  => OpcodeIn::CAST_ON_NPC,
        135 => OpcodeIn::NPC_USE_ITEM,
        229 => OpcodeIn::PLAYER_CAST_PVP,
        113 => OpcodeIn::PLAYER_USE_ITEM,
        171 => OpcodeIn::PLAYER_ATTACK,
        103 => OpcodeIn::PLAYER_DUEL,
        142 => OpcodeIn::PLAYER_INIT_TRADE_REQUEST,
        165 => OpcodeIn::PLAYER_FOLLOW,
        249 => OpcodeIn::CAST_ON_GROUND_ITEM,
        53  => OpcodeIn::GROUND_ITEM_USE_ITEM,
        91  => OpcodeIn::ITEM_USE_ITEM,
        170 => OpcodeIn::ITEM_UNEQUIP_FROM_INVENTORY,
        169 => OpcodeIn::ITEM_EQUIP_FROM_INVENTORY,
        90  => OpcodeIn::ITEM_COMMAND,
        246 => OpcodeIn::ITEM_DROP,
        137 => OpcodeIn::CAST_ON_SELF,
        158 => OpcodeIn::CAST_ON_LAND,
        136 => OpcodeIn::OBJECT_COMMAND,
        79  => OpcodeIn::OBJECT_COMMAND2,
        99  => OpcodeIn::CAST_ON_SCENERY,
        115 => OpcodeIn::USE_ITEM_ON_SCENERY,
        166 => OpcodeIn::SHOP_CLOSE,
        236 => OpcodeIn::SHOP_BUY,
        221 => OpcodeIn::SHOP_SELL,
        55  => OpcodeIn::PLAYER_ACCEPTED_INIT_TRADE_REQUEST,
        230 => OpcodeIn::PLAYER_DECLINED_TRADE,
        46  => OpcodeIn::PLAYER_ADDED_ITEMS_TO_TRADE_OFFER,
        104 => OpcodeIn::PLAYER_ACCEPTED_TRADE,
        60  => OpcodeIn::PRAYER_ACTIVATED,
        254 => OpcodeIn::PRAYER_DEACTIVATED,
        111 => OpcodeIn::GAME_SETTINGS_CHANGED,
        216 => OpcodeIn::CHAT_MESSAGE,
        38  => OpcodeIn::COMMAND,
        64  => OpcodeIn::PRIVACY_SETTINGS_CHANGED,
        206 => OpcodeIn::REPORT_ABUSE,
        212 => OpcodeIn::BANK_CLOSE,
        22  => OpcodeIn::BANK_WITHDRAW,
        23  => OpcodeIn::BANK_DEPOSIT,
        45  => OpcodeIn::SLEEPWORD_ENTERED,
        84  => OpcodeIn::SKIP_TUTORIAL,
        0   => OpcodeIn::LOGIN,
        2   => OpcodeIn::REGISTER_ACCOUNT,
        25  => OpcodeIn::CHANGE_PASS,
        208 => OpcodeIn::SET_RECOVERY,
        253 => OpcodeIn::SET_DETAILS,
        196 => OpcodeIn::CANCEL_RECOVERY_REQUEST,

        // --- Conflict bytes: statically resolved to logged-in path ---
        // See module-level doc for the pre-login alternatives.
        4   => OpcodeIn::CAST_ON_INVENTORY_ITEM,    // pre-login: FORGOT_PASSWORD
        8   => OpcodeIn::DUEL_FIRST_SETTINGS_CHANGED, // pre-login: RECOVERY_ATTEMPT
        197 => OpcodeIn::DUEL_DECLINED,             // pre-login: CHANGE_RECOVERY_REQUEST
        247 => OpcodeIn::GROUND_ITEM_TAKE,          // pre-login: CHANGE_DETAILS_REQUEST

        _   => return None,
    })
}

/// Resolve a conflict byte for v235 given the current login state.
///
/// The Java server calls `resolveOpcode(packet, player)` at runtime.
/// This function provides the same disambiguation for callers that have
/// access to session state.
///
/// `is_logged_in` should be `true` when the session's state is `LoggedIn`.
/// `packet_len` is the payload length (needed for byte 247 disambiguation).
/// `duel_active` should be `true` if the player is currently in a duel.
pub fn decode_with_context(
    byte: u8,
    is_logged_in: bool,
    packet_len: usize,
    duel_active: bool,
) -> Option<OpcodeIn> {
    match byte {
        4 => Some(if is_logged_in {
            OpcodeIn::CAST_ON_INVENTORY_ITEM
        } else {
            OpcodeIn::FORGOT_PASSWORD
        }),
        8 => Some(if is_logged_in {
            OpcodeIn::DUEL_FIRST_SETTINGS_CHANGED
        } else {
            OpcodeIn::RECOVERY_ATTEMPT
        }),
        197 => Some(if duel_active {
            OpcodeIn::DUEL_DECLINED
        } else {
            OpcodeIn::CHANGE_RECOVERY_REQUEST
        }),
        247 => Some(if packet_len > 1 {
            OpcodeIn::GROUND_ITEM_TAKE
        } else {
            OpcodeIn::CHANGE_DETAILS_REQUEST
        }),
        _ => decode(byte),
    }
}
