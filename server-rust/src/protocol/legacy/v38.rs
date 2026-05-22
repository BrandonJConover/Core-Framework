//! mudclient38 wire-byte → `OpcodeIn` table.
//!
//! Pure data port of the `toOpcodeEnum` switch block in
//! `server-java-modern/src/com/openrsc/server/net/rsc/parsers/impl/Payload38Parser.java`.
//!
//! mudclient38 is the earliest publicly documented RSC protocol revision.
//! It predates duel, banking, and most account-security opcodes; those entries
//! are simply absent (return `None`) for this revision.

#![allow(dead_code)]

use super::super::opcodes::OpcodeIn;

/// Returns the semantic opcode for a mudclient38 wire byte,
/// or `None` if the byte is unknown for this revision.
#[inline]
pub fn decode(byte: u8) -> Option<OpcodeIn> {
    Some(match byte {
        5 => OpcodeIn::HEARTBEAT,
        215 => OpcodeIn::WALK_TO_ENTITY,
        255 => OpcodeIn::WALK_TO_POINT,
        1 => OpcodeIn::CONFIRM_LOGOUT,
        231 => OpcodeIn::COMBAT_STYLE_CHANGED,
        237 => OpcodeIn::QUESTION_DIALOG_ANSWER,
        236 => OpcodeIn::PLAYER_APPEARANCE_CHANGE,
        29 => OpcodeIn::SOCIAL_ADD_IGNORE,
        26 => OpcodeIn::SOCIAL_ADD_FRIEND,
        28 => OpcodeIn::SOCIAL_SEND_PRIVATE_MESSAGE,
        27 => OpcodeIn::SOCIAL_REMOVE_FRIEND,
        30 => OpcodeIn::SOCIAL_REMOVE_IGNORE,
        238 => OpcodeIn::INTERACT_WITH_BOUNDARY,
        229 => OpcodeIn::INTERACT_WITH_BOUNDARY2,
        223 => OpcodeIn::CAST_ON_BOUNDARY,
        239 => OpcodeIn::USE_WITH_BOUNDARY,
        245 => OpcodeIn::NPC_TALK_TO,
        244 => OpcodeIn::NPC_ATTACK,
        225 => OpcodeIn::CAST_ON_NPC,
        243 => OpcodeIn::NPC_USE_ITEM,
        226 => OpcodeIn::PLAYER_CAST_PVP,
        219 => OpcodeIn::PLAYER_USE_ITEM,
        228 => OpcodeIn::PLAYER_ATTACK,
        235 => OpcodeIn::PLAYER_INIT_TRADE_REQUEST,
        214 => OpcodeIn::PLAYER_FOLLOW,
        224 => OpcodeIn::CAST_ON_GROUND_ITEM,
        250 => OpcodeIn::GROUND_ITEM_USE_ITEM,
        240 => OpcodeIn::ITEM_USE_ITEM,
        248 => OpcodeIn::ITEM_UNEQUIP_FROM_INVENTORY,
        249 => OpcodeIn::ITEM_EQUIP_FROM_INVENTORY,
        246 => OpcodeIn::ITEM_COMMAND,
        251 => OpcodeIn::ITEM_DROP,
        227 => OpcodeIn::CAST_ON_SELF,
        221 => OpcodeIn::CAST_ON_LAND,
        242 => OpcodeIn::OBJECT_COMMAND,
        230 => OpcodeIn::OBJECT_COMMAND2,
        222 => OpcodeIn::CAST_ON_SCENERY,
        241 => OpcodeIn::USE_ITEM_ON_SCENERY,
        218 => OpcodeIn::SHOP_CLOSE,
        217 => OpcodeIn::SHOP_BUY,
        216 => OpcodeIn::SHOP_SELL,
        233 => OpcodeIn::PLAYER_DECLINED_TRADE,
        234 => OpcodeIn::PLAYER_ADDED_ITEMS_TO_TRADE_OFFER,
        232 => OpcodeIn::PLAYER_ACCEPTED_INIT_TRADE_REQUEST,
        3 => OpcodeIn::CHAT_MESSAGE,
        31 => OpcodeIn::PRIVACY_SETTINGS_CHANGED,
        0 => OpcodeIn::LOGIN,
        19 => OpcodeIn::LOGIN, // relogin
        2 => OpcodeIn::REGISTER_ACCOUNT,
        220 => OpcodeIn::CAST_ON_INVENTORY_ITEM,
        252 => OpcodeIn::GROUND_ITEM_TAKE,
        25 => OpcodeIn::CHANGE_PASS,
        213 => OpcodeIn::GAME_SETTINGS_CHANGED,
        17 => OpcodeIn::SEND_DEBUG_INFO,
        254 => OpcodeIn::KNOWN_PLAYERS,
        _ => return None,
    })
}
