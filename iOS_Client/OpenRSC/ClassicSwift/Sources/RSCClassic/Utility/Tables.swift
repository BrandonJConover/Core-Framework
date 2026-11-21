// Shared lookup tables and colours from rsc-c's utility.c / colours.h.

import Foundation

public enum Colour {
    public static let black: Int32 = 0x000000
    public static let blue: Int32 = 0x0000ff
    public static let cyan: Int32 = 0x00ffff
    public static let green: Int32 = 0x00ff00
    public static let grey98: Int32 = 0x989898
    public static let grey80: Int32 = 0x808080
    public static let grey84: Int32 = 0x848484
    public static let greyA0: Int32 = 0xa0a0a0
    public static let greyB5: Int32 = 0xb5b5b5
    public static let greyBE: Int32 = 0xbebebe
    public static let greyC6: Int32 = 0xc6c6c6
    public static let greyC9: Int32 = 0xc9c9c9
    public static let greyD0: Int32 = 0xd0d0d0
    public static let greyDC: Int32 = 0xdcdcdc
    public static let magenta: Int32 = 0xff00ff
    public static let orange: Int32 = 0xff8000
    public static let red: Int32 = 0xff0000
    public static let white: Int32 = 0xffffff
    public static let yellow: Int32 = 0xffff00

    public static let messageTabOrange: Int32 = 0xffc832
    public static let messageTabPurple: Int32 = 0xc8c8ff
    public static let messageTabRed: Int32 = 0xff3232
    public static let messageTabWiki: Int32 = 0x438ab6
    public static let titleBar: Int32 = 0x0000c0
    public static let duelBar: Int32 = 0xc90b1d
    public static let uiLabel: Int32 = 0x000084

    /// Colour for an inline `@xyz@` code, or -1 if the code isn't known.
    /// "ran" picks a random colour (magenta when ranTargetFps < 1).
    public static func fromCode(_ code: String, ranTargetFps: Int = 10) -> Int {
        switch code {
        case "red": return 0xff0000
        case "lre": return 0xff9040
        case "yel": return 0xffff00
        case "gre": return 0x00ff00
        case "blu": return 0x0000ff
        case "cya": return 0x00ffff
        case "mag": return 0xff00ff
        case "whi": return 0xffffff
        case "bla": return 0x000000
        case "dre": return 0xc00000
        case "ora": return 0xff9040
        case "ran":
            if ranTargetFps < 1 { return 0xff00ff }
            return RandomColour.next(targetFps: ranTargetFps)
        case "or1": return 0xffb000
        case "or2": return 0xff7000
        case "or3": return 0xff3000
        case "gr1": return 0xc0ff00
        case "gr2": return 0x80ff00
        case "gr3": return 0x40ff00
        default: return -1
        }
    }

    private enum RandomColour {
        nonisolated(unsafe) static var colour = 0
        nonisolated(unsafe) static var nextChange: TimeInterval = 0

        static func next(targetFps: Int) -> Int {
            let fresh = Int.random(in: 0...0xffffff)
            guard targetFps < 50 else { return fresh }
            let now = ProcessInfo.processInfo.systemUptime
            if now >= nextChange {
                colour = fresh
                nextChange = now + 1.0 / Double(targetFps)
            }
            return colour
        }
    }
}

public enum Tables {
    public static let sinCos512: [Int] = {
        var t = [Int](repeating: 0, count: 512)
        for i in 0..<256 {
            t[i] = Int(sin(Double(i) * 0.02454369) * 32768)
            t[i + 256] = Int(cos(Double(i) * 0.02454369) * 32768)
        }
        return t
    }()

    public static let sinCos2048: [Int] = {
        var t = [Int](repeating: 0, count: 2048)
        for i in 0..<1024 {
            t[i] = Int(sin(Double(i) * 0.00613592315) * 32768)
            t[i + 1024] = Int(cos(Double(i) * 0.00613592315) * 32768)
        }
        return t
    }()

    /// The font character set (rsc-c disables "£", so that slot holds "A").
    public static let charSet: [UInt8] = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!\"A$%^&*()-_=+[{]};:'@#~,<.>/?\\| ".utf8)

    /// Offset of each byte's glyph record in a font file (9 bytes per glyph).
    public static let characterWidth: [Int] = (0..<256).map { c in
        (charSet.firstIndex(of: UInt8(c)) ?? 74) * 9
    }
}
