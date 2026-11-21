// Bob Jenkins' ISAAC generator (public domain), as in rsc-c's lib/isaac.c.
// Used to scramble packet opcodes after login.

public struct ISAAC {
    public var randrsl = [UInt32](repeating: 0, count: 256)
    var randcnt: UInt32 = 0
    var mm = [UInt32](repeating: 0, count: 256)
    var aa: UInt32 = 0
    var bb: UInt32 = 0
    var cc: UInt32 = 0

    public init() {}

    /// Seeds from up to 256 words (the client uses the 4 session keys, rest zero).
    public init(seed: [UInt32]) {
        for (i, v) in seed.prefix(256).enumerated() { randrsl[i] = v }
        initialise(useSeed: true)
    }

    public mutating func next() -> UInt32 {
        if randcnt == 0 {
            generate()
            randcnt = 256
        }
        randcnt -= 1
        return randrsl[Int(randcnt)]
    }

    mutating func generate() {
        cc = cc &+ 1
        bb = bb &+ cc
        for i in 0..<256 {
            let x = mm[i]
            switch i % 4 {
            case 0: aa ^= aa << 13
            case 1: aa ^= aa >> 6
            case 2: aa ^= aa << 2
            default: aa ^= aa >> 16
            }
            aa = mm[(i + 128) % 256] &+ aa
            let y = mm[Int((x >> 2) % 256)] &+ aa &+ bb
            mm[i] = y
            bb = mm[Int((y >> 10) % 256)] &+ x
            randrsl[i] = bb
        }
    }

    public mutating func initialise(useSeed: Bool) {
        aa = 0; bb = 0; cc = 0
        var a: UInt32 = 0x9e3779b9, b = a, c = a, d = a, e = a, f = a, g = a, h = a

        func mix() {
            a ^= b << 11; d = d &+ a; b = b &+ c
            b ^= c >> 2; e = e &+ b; c = c &+ d
            c ^= d << 8; f = f &+ c; d = d &+ e
            d ^= e >> 16; g = g &+ d; e = e &+ f
            e ^= f << 10; h = h &+ e; f = f &+ g
            f ^= g >> 4; a = a &+ f; g = g &+ h
            g ^= h << 8; b = b &+ g; h = h &+ a
            h ^= a >> 9; c = c &+ h; a = a &+ b
        }

        mm = [UInt32](repeating: 0, count: 256)
        for _ in 0..<4 { mix() }

        for i in stride(from: 0, to: 256, by: 8) {
            if useSeed {
                a = a &+ randrsl[i]; b = b &+ randrsl[i + 1]; c = c &+ randrsl[i + 2]; d = d &+ randrsl[i + 3]
                e = e &+ randrsl[i + 4]; f = f &+ randrsl[i + 5]; g = g &+ randrsl[i + 6]; h = h &+ randrsl[i + 7]
            }
            mix()
            mm[i] = a; mm[i + 1] = b; mm[i + 2] = c; mm[i + 3] = d
            mm[i + 4] = e; mm[i + 5] = f; mm[i + 6] = g; mm[i + 7] = h
        }

        if useSeed {
            for i in stride(from: 0, to: 256, by: 8) {
                a = a &+ mm[i]; b = b &+ mm[i + 1]; c = c &+ mm[i + 2]; d = d &+ mm[i + 3]
                e = e &+ mm[i + 4]; f = f &+ mm[i + 5]; g = g &+ mm[i + 6]; h = h &+ mm[i + 7]
                mix()
                mm[i] = a; mm[i + 1] = b; mm[i + 2] = c; mm[i + 3] = d
                mm[i + 4] = e; mm[i + 5] = f; mm[i + 6] = g; mm[i + 7] = h
            }
        }

        generate()
        randcnt = 256
    }
}
