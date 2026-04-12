import Foundation

// Port of Isaac.java (orsc.net.Isaac).
// All arithmetic uses wrapping operators (&+, &-, &*, &<<, &>>)
// because Java silently wraps 32-bit int overflow, but Swift traps.
final class ISAACCipher {
    private static let golden: UInt32 = 0x9E3779B9  // -1640531527 as UInt32

    private var mem = [UInt32](repeating: 0, count: 256)
    private var rsl = [UInt32](repeating: 0, count: 256)
    private var aa: UInt32 = 0
    private var bb: UInt32 = 0
    private var cc: UInt32 = 0
    private var gen: Int = 0

    init(seed: [Int]) {
        var s = [UInt32](repeating: 0, count: min(seed.count, 256))
        for (i, v) in seed.enumerated() where i < 256 {
            s[i] = UInt32(bitPattern: Int32(v))
        }
        for (i, v) in s.enumerated() { rsl[i] = v }
        initialize()
    }

    // Returns the next ISAAC value (matches Isaac.next()).
    func next() -> UInt32 {
        gen -= 1
        if gen < 0 {
            generate()
            gen = 255
        }
        return rsl[gen]
    }

    // MARK: - Private

    private func generate() {
        cc = cc &+ 1
        bb = bb &+ cc

        for i in 0..<256 {
            let x = mem[i]
            switch i & 3 {
            case 0: aa = aa ^ (aa &<< 13)
            case 1: aa = aa ^ (aa >> 6)
            case 2: aa = aa ^ (aa &<< 2)
            default: aa = aa ^ (aa >> 16)
            }
            aa = aa &+ mem[(i &+ 128) & 255]
            let y = mem[Int(x >> 2) & 255] &+ aa &+ bb
            mem[i] = y
            bb = mem[Int(y >> 10) & 255] &+ x
            rsl[i] = bb
        }
    }

    private func initialize() {
        let g = ISAACCipher.golden
        var a = g, b = g, c = g, d = g, e = g, f = g, h = g, gv = g

        // Mix 4 times
        for _ in 0..<4 {
            a = a ^ (b &<< 11); d = d &+ a; b = b &+ c
            b = b ^ (c >> 2);   e = e &+ b; c = c &+ d
            c = c ^ (d &<< 8);  f = f &+ c; d = d &+ e; gv = gv &+ d
            d = d ^ (e >> 16);  e = e &+ f
            e = e ^ (f &<< 10); h = h &+ e; f = f &+ gv
            f = f ^ (gv >> 4);  gv = gv &+ h; a = a &+ f
            gv = gv ^ (h &<< 8); h = h &+ a
            h = h ^ (a >> 9);   a = a &+ b; c = c &+ h
        }

        // First pass with seed
        var i = 0
        while i < 256 {
            a = a &+ rsl[i];     e = e &+ rsl[i &+ 4]
            b = b &+ rsl[i &+ 1]; f = f &+ rsl[i &+ 5]
            c = c &+ rsl[i &+ 2]; gv = gv &+ rsl[i &+ 6]
            d = d &+ rsl[i &+ 3]; h = h &+ rsl[i &+ 7]
            mix(&a, &b, &c, &d, &e, &f, &gv, &h)
            mem[i] = a; mem[i &+ 1] = b; mem[i &+ 2] = c; mem[i &+ 3] = d
            mem[i &+ 4] = e; mem[i &+ 5] = f; mem[i &+ 6] = gv; mem[i &+ 7] = h
            i &+= 8
        }

        // Second pass
        i = 0
        while i < 256 {
            a = a &+ mem[i];     e = e &+ mem[i &+ 4]
            b = b &+ mem[i &+ 1]; f = f &+ mem[i &+ 5]
            c = c &+ mem[i &+ 2]; gv = gv &+ mem[i &+ 6]
            d = d &+ mem[i &+ 3]; h = h &+ mem[i &+ 7]
            mix(&a, &b, &c, &d, &e, &f, &gv, &h)
            mem[i] = a; mem[i &+ 1] = b; mem[i &+ 2] = c; mem[i &+ 3] = d
            mem[i &+ 4] = e; mem[i &+ 5] = f; mem[i &+ 6] = gv; mem[i &+ 7] = h
            i &+= 8
        }

        generate()
        gen = 256
    }

    private func mix(_ a: inout UInt32, _ b: inout UInt32, _ c: inout UInt32, _ d: inout UInt32,
                     _ e: inout UInt32, _ f: inout UInt32, _ g: inout UInt32, _ h: inout UInt32) {
        a = a ^ (b &<< 11); d = d &+ a; b = b &+ c
        b = b ^ (c >> 2);   e = e &+ b; c = c &+ d
        c = c ^ (d &<< 8);  f = f &+ c; d = d &+ e; g = g &+ d
        d = d ^ (e >> 16);  e = e &+ f
        e = e ^ (f &<< 10); h = h &+ e; f = f &+ g
        f = f ^ (g >> 4);   g = g &+ h; a = a &+ f
        g = g ^ (h &<< 8);  h = h &+ a
        h = h ^ (a >> 9);   a = a &+ b; c = c &+ h
    }
}
