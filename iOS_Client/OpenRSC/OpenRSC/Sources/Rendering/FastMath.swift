import Foundation

/// Port of orsc.util.FastMath from the Java desktop client.
/// Provides precomputed trig tables and bitwise utility functions
/// used throughout the 3D rendering engine.
struct FastMath {

    // MARK: - Lookup Tables

    /// 33 entries: index n holds (1 << n) - 1, with the last entry being -1 (all bits set).
    static let bitwiseMaskForShift: [Int32] = [
        0, 1, 3, 7, 15, 31, 63, 127, 255, 511, 1023, 2047, 4095,
        8191, 16383, 32767, 65535, 131071, 262143, 524287, 1048575,
        2097151, 4194303, 8388607, 16777215, 33554431, 67108863,
        134217727, 268435455, 536870911, 1073741823, 2147483647, -1
    ]

    /// 512-entry trig table.
    /// [0..<256]   = sin(i * 0.02454369) * 32768
    /// [256..<512] = cos(i * 0.02454369) * 32768
    static let trigTable256: [Int32] = {
        var table = [Int32](repeating: 0, count: 512)
        for i in 0..<256 {
            table[i]       = Int32(sin(Double(i) * 0.02454369) * 32768.0)
            table[256 + i] = Int32(cos(Double(i) * 0.02454369) * 32768.0)
        }
        return table
    }()

    /// 2048-entry trig table.
    /// [0..<1024]    = sin(i * 0.00613592315) * 32768
    /// [1024..<2048] = cos(i * 0.00613592315) * 32768
    static let trigTable1024: [Int32] = {
        var table = [Int32](repeating: 0, count: 2048)
        for i in 0..<1024 {
            table[i]        = Int32(sin(Double(i) * 0.00613592315) * 32768.0)
            table[1024 + i] = Int32(cos(Double(i) * 0.00613592315) * 32768.0)
        }
        return table
    }()

    /// Duplicate of `trigTable1024` — kept for 1:1 parity with the Java source.
    static let trigTable_1024: [Int32] = {
        var table = [Int32](repeating: 0, count: 2048)
        for i in 0..<1024 {
            table[i]        = Int32(sin(Double(i) * 0.00613592315) * 32768.0)
            table[1024 + i] = Int32(cos(Double(i) * 0.00613592315) * 32768.0)
        }
        return table
    }()

    // MARK: - Utility Functions

    /// Bitwise AND — trivial in Swift but kept for port parity.
    @inline(__always)
    static func bitwiseAnd(_ a: Int32, _ b: Int32) -> Int32 {
        return a & b
    }

    /// Bitwise OR — trivial in Swift but kept for port parity.
    @inline(__always)
    static func bitwiseOr(_ a: Int32, _ b: Int32) -> Int32 {
        return a | b
    }

    /// Converts a signed byte to an unsigned byte value (0...255).
    @inline(__always)
    static func byteToUByte(_ val: Int8) -> Int32 {
        return Int32(val) & 255
    }

    /// Population count / nearest power of two helper.
    /// Returns the number of set bits in `value` (popcount).
    static func nearestPowerOfTwo(_ value: Int32) -> Int32 {
        var n = value
        n = (0x5555_5555 & (n >> 1)) + (0x5555_5555 & n)
        n = ((n & -858_993_460) >> 2) + (0x3333_3333 & n)
        n = (n + (n >> 4)) & 0x0F0F_0F0F
        n += n >> 8
        n += n >> 16
        return 255 & n
    }

    /// Returns the next power of two >= `n`.
    static func nextPowerOfTwo(_ value: Int32) -> Int32 {
        var n = value &- 1
        n |= n >> 1
        n |= n >> 2
        n |= n >> 4
        n |= n >> 8
        n |= n >> 16
        return n &+ 1
    }
}
