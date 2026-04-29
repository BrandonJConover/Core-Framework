// Player colour palettes ported from mudclient.java lines 142-169. The server
// transmits indices into these tables (one byte per channel) for hair, top,
// bottom, and skin; CharacterBillboards multiplies the chosen palette entry
// in as the per-layer mask colour.

import Foundation

enum PlayerPalettes {
    /// `mudclient.playerClothingColors` — 15 entries used for top + bottom.
    /// Java uses Unicode-escape literals to splice 16-bit values into the int
    /// array; this table preserves the *Java integer values*, including the
    /// odd partial-RGB entries (\ue000 = 0xE000, etc.) so we render exactly
    /// what the desktop client renders.
    static let clothing: [Int32] = [
        0xFF0000, 16744448, 16769024, 10543104, 0xE000, 0x8000,
        0xA080, 0xB0FF, 0x80FF, 12528, 14680288, 3158064,
        6307840, 8409088, 0xFFFFFF
    ]

    /// `mudclient.playerHairColors` — 10 entries (player-selectable).
    static let hair: [Int32] = [
        16760880, 16752704, 8409136, 6307872, 3158064, 16736288,
        16728064, 0xFFFFFF, 0xFF00, 0xFFFF
    ]

    /// `mudclient.playerSkinColors` — first 5 are player-selectable, the rest
    /// are NPC-only entries. Indexed exactly as the Java table so server-sent
    /// indices map 1:1.
    static let skin: [Int32] = [
        0xECDED0, 0xCCB366, 0xB38C40, 0x997326, 0x906020,

        0x000000, 0x000004, 0x0066FF, 0x009000, 0x3CB371,
        0x55BFEE, 0x55CFFF, 0x604020, 0x663300, 0x6F5737,
        0x705010, 0x804000, 0x996633, 0x999999, 0xAC9E90,
        0xDCC399, 0xDCCEA0, 0xDCFFD0, 0xDD3040, 0xEADED2,
        0xECEED0, 0xECFED0, 0xECFFD0, 0xFCEEE0, 0xFF3333,
        0xFF9F55, 0xFFDED2, 0xFFFEF0, 0xFFFFFF,

        0x00A0A0, 0xFFFF00, 0xFF69B4, 0x0180A2, 0x86668e,
        0x663399, 0xB5FF1D, 0xA0C0C0, 0x608080
    ]

    /// Bounds-safe lookup. Server-supplied byte indices come straight off the
    /// wire so we clamp to avoid a crash on unexpected values.
    static func clothingColour(_ idx: Int) -> Int32 {
        guard idx >= 0 && idx < clothing.count else { return clothing[0] }
        return clothing[idx]
    }
    static func hairColour(_ idx: Int) -> Int32 {
        guard idx >= 0 && idx < hair.count else { return hair[0] }
        return hair[idx]
    }
    static func skinColour(_ idx: Int) -> Int32 {
        guard idx >= 0 && idx < skin.count else { return skin[0] }
        return skin[idx]
    }
}
