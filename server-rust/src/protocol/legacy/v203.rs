//! mudclient203 / mudclient204 wire-byte → `OpcodeIn` table.
//!
//! Pure data port of the `static { opcodes203.put(...) }` block in
//! `server-java-modern/src/com/openrsc/server/net/rsc/parsers/impl/Payload203Parser.java`.
//!
//! Both byte 0 and byte 1 map to `LOGIN` in the Java table; we mirror
//! that exactly. Java releases mudclient203.jar 2005-11-08 and
//! mudclient204.jar 2006-05-25; they share this protocol.

#![allow(dead_code)]

use super::super::opcodes::OpcodeIn;

/// Returns the semantic opcode for a mudclient203/204 wire byte,
/// or `None` if the byte is unknown for this revision.
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
        // Both 0 and 1 map to LOGIN in the authentic table.
        0   => OpcodeIn::LOGIN,
        1   => OpcodeIn::LOGIN,
        4   => OpcodeIn::CAST_ON_INVENTORY_ITEM,
        8   => OpcodeIn::DUEL_FIRST_SETTINGS_CHANGED,
        197 => OpcodeIn::DUEL_DECLINED,
        247 => OpcodeIn::GROUND_ITEM_TAKE,
        163 => OpcodeIn::KNOWN_PLAYERS,
        _ => return None,
    })
}
