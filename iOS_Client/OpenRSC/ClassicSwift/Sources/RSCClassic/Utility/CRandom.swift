// glibc's rand()/srand() (the TYPE_3 additive feedback generator). rsc-c uses
// rand() for terrain vertex ambience, so matching it keeps terrain shading
// identical to the C client built against glibc.

public final class CRandom {
    public static let shared = CRandom()
    public static let randMax: Int32 = 2147483647

    private var ring = [UInt32](repeating: 0, count: 34)
    private var n = 0

    public init(seed: UInt32 = 1) { self.seed(seed) }

    public func seed(_ value: UInt32) {
        var st = [Int32](repeating: 0, count: 31)
        st[0] = value == 0 ? 1 : Int32(bitPattern: value)
        for k in 1..<31 {
            let word = Int64(st[k - 1])
            let hi = word / 127773, lo = word % 127773
            var w = 16807 * lo - 2836 * hi
            if w < 0 { w += 2147483647 }
            st[k] = Int32(truncatingIfNeeded: w)
        }
        var r = [UInt32](repeating: 0, count: 344)
        for k in 0..<31 { r[k] = UInt32(bitPattern: st[k]) }
        for k in 31..<34 { r[k] = r[k - 31] }
        for k in 34..<344 { r[k] = r[k - 31] &+ r[k - 3] }
        for k in 310..<344 { ring[k % 34] = r[k] }
        n = 344
    }

    /// The next rand() value, 0...RAND_MAX.
    public func next() -> Int32 {
        let v = ring[(n - 31) % 34] &+ ring[(n - 3) % 34]
        ring[n % 34] = v
        n += 1
        if n >= 34 * 1_000_000 { n -= 34 * 999_999 }
        return Int32(bitPattern: v >> 1)
    }

    /// `(float)rand() / (float)RAND_MAX`, as rsc-c writes it.
    public func nextUnitFloat() -> Float {
        Float(next()) / Float(CRandom.randMax)
    }
}
