// Port of Client_Base/src/orsc/util/FastMath.java
// All integer fields use Int32 to match Java `int` for fixed-point math correctness.

import Foundation

final class FastMath {

    // 512 entries: sin at [0..255], cos at [256..511]
    static let trigTable256: [Int32] = {
        var table = [Int32](repeating: 0, count: 512)
        for i in 0 ..< 256 {
            table[i]       = Int32(32768.0 * Foundation.sin(0.02454369 * Double(i)))
            table[256 + i] = Int32(32768.0 * Foundation.cos(Double(i) * 0.02454369))
        }
        return table
    }()

    // 2048 entries: sin at [0..1023], cos at [1024..2047]
    static let trigTable1024: [Int32] = {
        var table = [Int32](repeating: 0, count: 2048)
        for i in 0 ..< 1024 {
            table[i]        = Int32(Foundation.sin(Double(i) * 0.00613592315) * 32768.0)
            table[i + 1024] = Int32(Foundation.cos(Double(i) * 0.00613592315) * 32768.0)
        }
        return table
    }()

    // Private in Java but kept for completeness; identical layout to trigTable256.
    private static let trigTable_256: [Int32] = {
        var table = [Int32](repeating: 0, count: 512)
        for i in 0 ..< 256 {
            table[i]       = Int32(Foundation.sin(0.02454369 * Double(i)) * 32768.0)
            table[256 + i] = Int32(Foundation.cos(Double(i) * 0.02454369) * 32768.0)
        }
        return table
    }()

    // 2048 entries: sin at [0..1023], cos at [1024..2047]
    // Note: Java uses offset 1024 (not i+1024) for the cos half here.
    static let trigTable_1024: [Int32] = {
        var table = [Int32](repeating: 0, count: 2048)
        for i in 0 ..< 1024 {
            table[i]        = Int32(Foundation.sin(Double(i) * 0.00613592315) * 32768.0)
            table[1024 + i] = Int32(Foundation.cos(Double(i) * 0.00613592315) * 32768.0)
        }
        return table
    }()

    // 33-entry bitmask table. bitwiseMaskForShift[i] == (1 << i) - 1 for i < 32;
    // bitwiseMaskForShift[32] == -1 (all bits set, wraps as signed Int32).
    static let bitwiseMaskForShift: [Int32] = [
        0, 1, 3, 7, 15, 31, 63, 127, 255, 511, 1023, 2047, 4095,
        8191, 16383, 32767, 65535, 131071, 262143, 524287, 1048575, 2097151, 4194303, 8388607, 16777215,
        33554431, 67108863, 134217727, 268435455, 536870911, 1073741823, Int32.max, -1
    ]

    static func bitwiseAnd(_ a: Int32, _ b: Int32) -> Int32 {
        return a & b
    }

    static func bitwiseOr(_ a: Int32, _ b: Int32) -> Int32 {
        return a | b
    }

    static func byteToUByte(_ val: Int8) -> Int32 {
        return Int32(val) & 255
    }

    /// Returns the population count (number of set bits) of var0.
    /// Java doc says "Returns 1 if var0 is a power of two. Otherwise returns the closest power of two"
    /// but the implementation is actually a Hamming-weight / popcount.
    static func nearestPowerOfTwo(_ var0: Int32, _ var1: Int8) -> Int32 {
        var n = var0
        n = (0x55555555 & (n >> 1)) &+ (0x55555555 & n)
        n = ((n & Int32(bitPattern: 0xCCCCCCCC)) >> 2) &+ (0x33333333 & n)
        n = (n &+ (n >> 4)) & 0x0F0F0F0F
        n = n &+ (n >> 8)
        n = n &+ (n >> 16)
        return 255 & n
    }

    static func nextPowerOfTwo(_ n: Int32) -> Int32 {
        var n = n &- 1
        n |= n >> 1
        n |= n >> 2
        n |= n >> 4
        n |= n >> 8
        n |= n >> 16
        return n &+ 1
    }
}
