// Textbook RSA (m^e mod n) for the login block, matching rsc-c's lib/rsa/rsa-tiny.c.
// Keys are hex strings like the world list's ("00010001", "87cef7...").

public struct RSA {
    let exponent: [UInt32]   // little-endian 32-bit limbs
    let modulus: [UInt32]

    public init?(exponentHex: String, modulusHex: String) {
        guard let e = RSA.limbs(hex: exponentHex), let n = RSA.limbs(hex: modulusHex),
              !RSA.isZero(n) else { return nil }
        exponent = e
        modulus = n
    }

    /// Encrypts `input` (big-endian bytes) and returns the result big-endian with
    /// leading zero bytes stripped, like rsa_crypt.
    public func crypt(_ input: [UInt8]) -> [UInt8] {
        var base = RSA.trim(RSA.limbs(bytes: input))
        base = RSA.mod(base, modulus)
        var result: [UInt32] = [1]
        let bits = RSA.bitCount(exponent)
        if bits > 0 {
            for bit in stride(from: bits - 1, through: 0, by: -1) {
                result = RSA.mod(RSA.mul(result, result), modulus)
                if (exponent[bit / 32] >> UInt32(bit % 32)) & 1 != 0 {
                    result = RSA.mod(RSA.mul(result, base), modulus)
                }
            }
        }
        result = RSA.mod(result, modulus)
        var out = [UInt8]()
        for limb in result.reversed() {
            out += [UInt8(limb >> 24), UInt8(limb >> 16 & 0xff), UInt8(limb >> 8 & 0xff), UInt8(limb & 0xff)]
        }
        while let first = out.first, first == 0 { out.removeFirst() }
        return out
    }

    // MARK: - Minimal unsigned bignum helpers

    static func limbs(hex: String) -> [UInt32]? {
        var bytes = [UInt8]()
        let chars = Array(hex.utf8)
        var i = chars.count % 2 == 1 ? -1 : 0
        while i < chars.count {
            let hi = i < 0 ? 0 : hexValue(chars[i])
            let lo = hexValue(chars[i + 1])
            guard let h = hi, let l = lo else { return nil }
            bytes.append(h << 4 | l)
            i += 2
        }
        return trim(limbs(bytes: bytes))
    }

    private static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: return c - 0x30
        case 0x41...0x46: return c - 0x41 + 10
        case 0x61...0x66: return c - 0x61 + 10
        default: return nil
        }
    }

    static func limbs(bytes: [UInt8]) -> [UInt32] {
        var out = [UInt32](repeating: 0, count: (bytes.count + 3) / 4)
        for (i, b) in bytes.reversed().enumerated() {
            out[i / 4] |= UInt32(b) << UInt32(8 * (i % 4))
        }
        return out
    }

    static func trim(_ a: [UInt32]) -> [UInt32] {
        var a = a
        while a.count > 1 && a.last == 0 { a.removeLast() }
        return a.isEmpty ? [0] : a
    }

    static func isZero(_ a: [UInt32]) -> Bool { a.allSatisfy { $0 == 0 } }

    static func bitCount(_ a: [UInt32]) -> Int {
        let a = trim(a)
        guard let top = a.last, top != 0 else { return 0 }
        return (a.count - 1) * 32 + (32 - top.leadingZeroBitCount)
    }

    static func mul(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var out = [UInt32](repeating: 0, count: a.count + b.count)
        for i in 0..<a.count {
            var carry: UInt64 = 0
            for j in 0..<b.count {
                let t = UInt64(a[i]) * UInt64(b[j]) + UInt64(out[i + j]) + carry
                out[i + j] = UInt32(truncatingIfNeeded: t)
                carry = t >> 32
            }
            out[i + b.count] = UInt32(carry)
        }
        return trim(out)
    }

    static func compare(_ a: [UInt32], _ b: [UInt32]) -> Int {
        let a = trim(a), b = trim(b)
        if a.count != b.count { return a.count < b.count ? -1 : 1 }
        for i in stride(from: a.count - 1, through: 0, by: -1) where a[i] != b[i] {
            return a[i] < b[i] ? -1 : 1
        }
        return 0
    }

    /// a mod n by shift-and-subtract (operands are at most ~1024 bits here).
    static func mod(_ a: [UInt32], _ n: [UInt32]) -> [UInt32] {
        if compare(a, n) < 0 { return trim(a) }
        var r: [UInt32] = [0]
        for bit in stride(from: bitCount(a) - 1, through: 0, by: -1) {
            // r = r << 1 | bit
            var carry = (a[bit / 32] >> UInt32(bit % 32)) & 1
            for i in 0..<r.count {
                let next = r[i] >> 31
                r[i] = r[i] << 1 | carry
                carry = next
            }
            if carry != 0 { r.append(carry) }
            if compare(r, n) >= 0 { r = sub(r, n) }
        }
        return trim(r)
    }

    static func sub(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var out = a
        var borrow: Int64 = 0
        for i in 0..<out.count {
            var t = Int64(out[i]) - borrow - (i < b.count ? Int64(b[i]) : 0)
            if t < 0 { t += 1 << 32; borrow = 1 } else { borrow = 0 }
            out[i] = UInt32(t)
        }
        return trim(out)
    }
}
