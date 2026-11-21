// String and buffer helpers from rsc-c's utility.c that the client uses.

import Foundation

public enum ClientUtil {
    static let bitmask: [Int] = (0...32).map { $0 == 32 ? -1 : (1 << $0) - 1 }

    static let certificateItems: [(certificate: Int, item: Int)] = [
        (517, 151), (521, 152), (519, 153), (518, 155), (528, 170), (529, 171), (532, 172), (530, 173),
        (1271, 220), (536, 369), (535, 370), (534, 372), (533, 373), (520, 383), (531, 384), (1272, 483),
        (1273, 486), (1275, 492), (1274, 495), (631, 545), (630, 546), (629, 554), (628, 555), (713, 633),
        (712, 634), (711, 635), (1270, 814),
    ]

    static func isAlnum(_ c: UInt8) -> Bool {
        (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57)
    }

    /// format_auth_string: pads to `maxLength` with spaces, anything not alphanumeric becomes '_'.
    public static func formatAuthString(_ raw: String, _ maxLength: Int) -> String {
        let bytes = Surface.bytes(raw)
        var out = [UInt8]()
        for i in 0..<maxLength {
            if i >= bytes.count { out.append(32) } else { out.append(isAlnum(bytes[i]) ? bytes[i] : 95) }
        }
        return String(decoding: out, as: Latin1.self)
    }

    public static func encodeUsername(_ username: String) -> Int64 {
        var cleaned: [UInt8] = Surface.bytes(username).map { c in
            if (c >= 97 && c <= 122) || (c >= 48 && c <= 57) { return c }
            if c >= 65 && c <= 90 { return c + 32 }
            return 32
        }
        while let f = cleaned.first, f == 32 || (f >= 9 && f <= 13) { cleaned.removeFirst() }
        while let l = cleaned.last, l == 32 || (l >= 9 && l <= 13) { cleaned.removeLast() }
        if cleaned.count > Mudclient.maxUserLength { cleaned = Array(cleaned.prefix(Mudclient.maxUserLength)) }
        var encoded: Int64 = 0
        for c in cleaned {
            encoded = encoded &* 37
            if c >= 97 && c <= 122 { encoded += 1 + Int64(c) - 97 } else if c >= 48 && c <= 57 {
                encoded += 27 + Int64(c) - 48
            }
        }
        return encoded
    }

    public static func decodeUsername(_ value: Int64) -> String {
        if value < 0 { return "invalidName" }
        var encoded = value
        var decoded = [UInt8]()
        while encoded != 0 {
            let c = UInt8(encoded % 37)
            encoded /= 37
            if c == 0 {
                decoded.append(32)
            } else if c < 27 {
                decoded.append(encoded % 37 == 0 ? c + 65 - 1 : c + 97 - 1)
            } else {
                decoded.append(c + 48 - 27)
            }
        }
        return String(decoding: decoded.reversed(), as: Latin1.self)
    }

    public static func ipToString(_ ip: Int32) -> String {
        "\((ip >> 24) & 0xff).\((ip >> 16) & 0xff).\((ip >> 8) & 0xff).\(ip & 0xff)"
    }

    public static func formatNumberCommas(_ number: Int) -> String {
        if number < 1000 { return String(number) }
        return formatNumberCommas(number / 1000) + "," + String(format: "%03d", number % 1000)
    }

    public static func formatConfirmAmount(_ amount: Int) -> String {
        var formatted = String(amount)
        var i = formatted.count - 3
        while i > 0 {
            let idx = formatted.index(formatted.startIndex, offsetBy: i)
            formatted = String(formatted[..<idx]) + "," + String(formatted[idx...])
            i -= 3
        }
        let length = formatted.count
        if length > 8 {
            return "@gre@\(formatted.prefix(length - 8)) million @whi@(\(formatted))"
        } else if length > 4 {
            return "@cya@\(formatted.prefix(length - 4)) K @whi@(\(formatted))"
        }
        return formatted
    }

    public static func formatAmountSuffix(_ amount: Int, useColour: Bool, convertTenThousands: Bool,
                                          useCommas: Bool) -> String {
        var scale: Float = 1
        var colour = ""
        var suffix = ""
        if amount >= 10_000_000 {
            scale = 1_000_000; colour = "@gre@"; suffix = "M"
        } else if amount >= (convertTenThousands ? 10000 : 100_000) {
            scale = 1000; colour = "@whi@"; suffix = "K"
        }
        let scaled = Int(floorf(Float(amount) / scale))
        let digits = useCommas ? formatNumberCommas(scaled) : String(scaled)
        return (useColour ? colour : "") + digits + suffix
    }

    public static func levelDifferenceColour(_ d: Int) -> String {
        var colour = ""
        if d < 0 { colour = "@or1@" }
        if d < -3 { colour = "@or2@" }
        if d < -6 { colour = "@or3@" }
        if d < -9 { colour = "@red@" }
        if d > 0 { colour = "@gr1@" }
        if d > 3 { colour = "@gr2@" }
        if d > 6 { colour = "@gr3@" }
        if d > 9 { colour = "@gre@" }
        return colour
    }

    public static func ulawToLinear(_ input: ArraySlice<UInt8>) -> [Int16] {
        input.map { b in
            let u = ~UInt16(b)
            var t = Int16(truncatingIfNeeded: (Int(u & 0xf) << 3) + 0x84)
            t = t << Int16((u & 0x70) >> 4)
            return (u & 0x80) != 0 ? 0x84 &- t : t &- 0x84
        }
    }

    public static func urlEncode(_ s: String) -> String {
        let hex = Array("0123456789abcdef".utf8)
        var out = [UInt8]()
        for c in Surface.bytes(s) {
            if isAlnum(c) { out.append(c) } else {
                let sc = Int(Int8(bitPattern: c))
                out += [37, hex[(sc >> 4) & 15], hex[sc & 15]]
            }
        }
        return String(decoding: out, as: Latin1.self)
    }

    public static func certificateItemId(_ itemId: Int) -> Int {
        certificateItems.first { $0.certificate == itemId }?.item ?? -1
    }

    public static func isIPAddress(_ address: String) -> Bool {
        var segment = 0, segments = 0
        for c in address.utf8 {
            if c >= 48 && c <= 57 {
                segment = segment * 10 + Int(c - 48)
                if segment > 255 { return false }
            } else if c == 46 {
                segments += 1
                if segments > 3 { return false }
                segment = 0
            } else { return false }
        }
        return segments == 3
    }

    public static func distance(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) -> Double {
        sqrt(pow(Double(x2 - x1), 2) + pow(Double(y2 - y1), 2))
    }

    // MARK: Packet buffer readers

    public static func unsignedByte(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) }
    public static func signedByte(_ b: [UInt8], _ o: Int) -> Int { Int(Int8(bitPattern: b[o])) }
    public static func unsignedShort(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) << 8 | Int(b[o + 1]) }
    public static func signedShort(_ b: [UInt8], _ o: Int) -> Int {
        Int(Int16(bitPattern: UInt16(b[o]) << 8 | UInt16(b[o + 1])))
    }
    public static func unsignedInt(_ b: [UInt8], _ o: Int) -> Int {
        Int(Int32(bitPattern: UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])))
    }
    public static func unsignedLong(_ b: [UInt8], _ o: Int) -> Int64 {
        (Int64(unsignedInt(b, o)) << 32) + Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: unsignedInt(b, o + 4))))
    }
    public static func stackInt(_ b: [UInt8], _ o: Int) -> Int {
        if b[o] < 128 { return Int(b[o]) }
        return ((Int(b[o]) - 128) << 24) + (Int(b[o + 1]) << 16) + (Int(b[o + 2]) << 8) + Int(b[o + 3])
    }

    /// get_bit_mask: `nbits` bits starting at bit `offset`.
    public static func bitMask(_ b: [UInt8], _ offset: Int, _ nbits: Int) -> Int {
        var byteOffset = offset >> 3
        var bitOffset = 8 - (offset & 7)
        var nbits = nbits
        var bits = 0
        while nbits > bitOffset {
            bits += (Int(b[byteOffset]) & bitmask[bitOffset]) << (nbits - bitOffset)
            byteOffset += 1
            nbits -= bitOffset
            bitOffset = 8
        }
        if nbits == bitOffset {
            bits += Int(b[byteOffset]) & bitmask[bitOffset]
        } else {
            bits += (Int(b[byteOffset]) >> (bitOffset - nbits)) & bitmask[nbits]
        }
        return bits
    }
}
