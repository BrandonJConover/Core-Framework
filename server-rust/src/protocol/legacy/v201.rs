//! mudclient201 wire-byte → `OpcodeIn` table.
//!
//! Pure data port of the `static { opcodes201.put(...) }` block in
//! `server-java-modern/src/com/openrsc/server/net/rsc/parsers/impl/Payload201Parser.java`.
//!
//! mudclient201.jar was released 2004-12-13 and was the last protocol
//! before the anti-bot "banking trap"; it's the final F2P-era protocol.
//! Note: BANK_DEPOSIT/BANK_WITHDRAW have a different *payload* layout
//! in v201 vs v203 (no magic-number suffix); that's handled at parse
//! time, not in this byte → opcode table.

#![allow(dead_code)]

use super::super::opcodes::OpcodeIn;

/// Returns the semantic opcode for a mudclient201 wire byte,
/// or `None` if the byte is unknown for this revision.
#[inline]
pub fn decode(byte: u8) -> Option<OpcodeIn> {
    Some(match byte {
        186 => OpcodeIn::HEARTBEAT,
        226 => OpcodeIn::WALK_TO_ENTITY,
        211 => OpcodeIn::WALK_TO_POINT,
        104 => OpcodeIn::CONFIRM_LOGOUT,
        3   => OpcodeIn::LOGOUT,
        74  => OpcodeIn::COMBAT_STYLE_CHANGED,
        189 => OpcodeIn::QUESTION_DIALOG_ANSWER,
        238 => OpcodeIn::PLAYER_APPEARANCE_CHANGE,
        254 => OpcodeIn::SOCIAL_ADD_IGNORE,
        232 => OpcodeIn::SOCIAL_ADD_FRIEND,
        59  => OpcodeIn::SOCIAL_SEND_PRIVATE_MESSAGE,
        52  => OpcodeIn::SOCIAL_REMOVE_FRIEND,
        244 => OpcodeIn::SOCIAL_REMOVE_IGNORE,
        125 => OpcodeIn::DUEL_FIRST_ACCEPTED,
        229 => OpcodeIn::DUEL_OFFER_ITEM,
        175 => OpcodeIn::DUEL_SECOND_ACCEPTED,
        100 => OpcodeIn::INTERACT_WITH_BOUNDARY,
        121 => OpcodeIn::INTERACT_WITH_BOUNDARY2,
        76  => OpcodeIn::CAST_ON_BOUNDARY,
        71  => OpcodeIn::USE_WITH_BOUNDARY,
        159 => OpcodeIn::NPC_TALK_TO,
        89  => OpcodeIn::NPC_COMMAND,
        118 => OpcodeIn::NPC_ATTACK,
        10  => OpcodeIn::CAST_ON_NPC,
        143 => OpcodeIn::NPC_USE_ITEM,
        56  => OpcodeIn::PLAYER_CAST_PVP,
        11  => OpcodeIn::PLAYER_USE_ITEM,
        124 => OpcodeIn::PLAYER_ATTACK,
        217 => OpcodeIn::PLAYER_DUEL,
        62  => OpcodeIn::PLAYER_INIT_TRADE_REQUEST,
        91  => OpcodeIn::PLAYER_FOLLOW,
        18  => OpcodeIn::CAST_ON_GROUND_ITEM,
        255 => OpcodeIn::GROUND_ITEM_USE_ITEM,
        235 => OpcodeIn::ITEM_USE_ITEM,
        40  => OpcodeIn::ITEM_UNEQUIP_FROM_INVENTORY,
        199 => OpcodeIn::ITEM_EQUIP_FROM_INVENTORY,
        24  => OpcodeIn::ITEM_COMMAND,
        123 => OpcodeIn::ITEM_DROP,
        44  => OpcodeIn::CAST_ON_SELF,
        201 => OpcodeIn::CAST_ON_LAND,
        38  => OpcodeIn::OBJECT_COMMAND,
        172 => OpcodeIn::OBJECT_COMMAND2,
        237 => OpcodeIn::CAST_ON_SCENERY,
        127 => OpcodeIn::USE_ITEM_ON_SCENERY,
        92  => OpcodeIn::SHOP_CLOSE,
        67  => OpcodeIn::SHOP_BUY,
        177 => OpcodeIn::SHOP_SELL,
        94  => OpcodeIn::PLAYER_ACCEPTED_INIT_TRADE_REQUEST,
        27  => OpcodeIn::PLAYER_DECLINED_TRADE,
        144 => OpcodeIn::PLAYER_ADDED_ITEMS_TO_TRADE_OFFER,
        102 => OpcodeIn::PLAYER_ACCEPTED_TRADE,
        202 => OpcodeIn::PRAYER_ACTIVATED,
        162 => OpcodeIn::PRAYER_DEACTIVATED,
        165 => OpcodeIn::GAME_SETTINGS_CHANGED,
        249 => OpcodeIn::CHAT_MESSAGE,
        32  => OpcodeIn::COMMAND,
        247 => OpcodeIn::PRIVACY_SETTINGS_CHANGED,
        215 => OpcodeIn::REPORT_ABUSE,
        78  => OpcodeIn::BANK_CLOSE,
        131 => OpcodeIn::BANK_WITHDRAW,
        190 => OpcodeIn::BANK_DEPOSIT,
        142 => OpcodeIn::SLEEPWORD_ENTERED,
        // Both 0 and 1 map to LOGIN in the authentic table.
        0   => OpcodeIn::LOGIN,
        1   => OpcodeIn::LOGIN,
        166 => OpcodeIn::CAST_ON_INVENTORY_ITEM,
        138 => OpcodeIn::DUEL_FIRST_SETTINGS_CHANGED,
        43  => OpcodeIn::DUEL_DECLINED,
        253 => OpcodeIn::GROUND_ITEM_TAKE,
        241 => OpcodeIn::KNOWN_PLAYERS,
        _ => return None,
    })
}
