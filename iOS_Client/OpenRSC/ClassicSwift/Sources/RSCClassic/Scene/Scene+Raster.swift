// Port of scene.c's scanline generation and rasterisers.

extension Scene {
    // MARK: - Scanlines

    private struct Edge {
        var x: Int32 = 0, dx: Int32 = 0, s: Int32 = 0, ds: Int32 = 0
        var start: Int32 = 12345678, end: Int32 = -12345678
    }

    /// The unrolled 3- and 4-sided cases from scene_generate_scanlines, folded into one loop over edges
    /// (same edge order, same arithmetic).
    private func edgeScanlines(_ pairs: [(Int, Int)]) {
        let by = Int32(baseY)
        let limit = by &+ Int32(clipY) &- 1
        var edges = [Edge](repeating: Edge(), count: pairs.count)
        for (n, (p, q)) in pairs.enumerated() {
            let yp = planeY[p] &+ by, yq = planeY[q] &+ by
            let xp = planeX[p], xq = planeX[q]
            let sp = vertexShade[p], sq = vertexShade[q]
            var e = Edge()
            if yq != yp {
                e.dx = ((xq &- xp) << 8) / (yq &- yp)
                e.ds = ((sq &- sp) << 8) / (yq &- yp)
                if yp < yq {
                    e.x = xp << 8; e.s = sp << 8; e.start = yp; e.end = yq
                } else {
                    e.x = xq << 8; e.s = sq << 8; e.start = yq; e.end = yp
                }
                if e.start < 0 {
                    e.x &-= e.dx &* e.start
                    e.s &-= e.ds &* e.start
                    e.start = 0
                }
                if e.end > limit { e.end = limit }
            }
            edges[n] = e
        }
        var mn = edges[0].start
        var mx = edges[0].end
        for e in edges.dropFirst() where e.start < mn { mn = e.start }
        for e in edges.dropFirst() where e.end > mx { mx = e.end }
        minY = Int(mn)
        maxY = Int(mx)

        var startX: Int32 = 0, endX: Int32 = 0, startS: Int32 = 0, endS: Int32 = 0
        var y = mn
        while y < mx {
            if y >= edges[0].start && y < edges[0].end {
                startX = edges[0].x; endX = startX
                startS = edges[0].s; endS = startS
                edges[0].x &+= edges[0].dx
                edges[0].s &+= edges[0].ds
            } else {
                startX = 655360
                endX = -655360
            }
            for n in 1..<edges.count where y >= edges[n].start && y < edges[n].end {
                let x = edges[n].x
                if x < startX { startX = x; startS = edges[n].s }
                if x > endX { endX = x; endS = edges[n].s }
                edges[n].x &+= edges[n].dx
                edges[n].s &+= edges[n].ds
            }
            scanlines[Int(y)] = Scanline(startX: startX, endX: endX, startS: startS, endS: endS)
            y += 1
        }
        if minY < baseY - clipY { minY = baseY - clipY }
    }

    func generateScanlines(_ plane: Int, _ model: GameModel, _ face: Int) {
        if plane == 3 {
            edgeScanlines([(0, 2), (0, 1), (1, 2)])
        } else if plane == 4 {
            edgeScanlines([(0, 3), (0, 1), (1, 2), (2, 3)])
        } else {
            let by = Int32(baseY)
            planeY[0] &+= by
            minY = Int(planeY[0]); maxY = minY
            for y in 1..<max(plane, 1) {
                planeY[y] &+= by
                let i2 = Int(planeY[y])
                if i2 < minY { minY = i2 } else if i2 > maxY { maxY = i2 }
            }
            if minY < baseY - clipY { minY = baseY - clipY }
            if maxY >= baseY + clipY { maxY = baseY + clipY - 1 }
            if minY >= maxY { return }
            for y in minY..<maxY {
                scanlines[y].startX = 655360
                scanlines[y].endX = -655360
            }
            let mxY = Int32(maxY)
            let j2 = plane - 1
            var i3 = planeY[0]
            var i4 = planeY[j2]
            if i3 < i4 {
                var x = planeX[0] << 8
                let dx = ((planeX[j2] &- planeX[0]) << 8) / (i4 &- i3)
                var s = vertexShade[0] << 8
                let ds = ((vertexShade[j2] &- vertexShade[0]) << 8) / (i4 &- i3)
                if i3 < 0 { x &-= dx &* i3; s &-= ds &* i3; i3 = 0 }
                if i4 > mxY { i4 = mxY }
                var y = i3
                while y <= i4 {
                    scanlines[Int(y)] = Scanline(startX: x, endX: x, startS: s, endS: s)
                    x &+= dx; s &+= ds
                    y += 1
                }
            } else if i3 > i4 {
                var x = planeX[j2] << 8
                let dx = ((planeX[0] &- planeX[j2]) << 8) / (i3 &- i4)
                var s = vertexShade[j2] << 8
                let ds = ((vertexShade[0] &- vertexShade[j2]) << 8) / (i3 &- i4)
                if i4 < 0 { x &-= dx &* i4; s &-= ds &* i4; i4 = 0 }
                if i3 > mxY { i3 = mxY }
                var y = i4
                while y <= i3 {
                    scanlines[Int(y)] = Scanline(startX: x, endX: x, startS: s, endS: s)
                    x &+= dx; s &+= ds
                    y += 1
                }
            }
            for y in 0..<max(j2, 0) {
                let k5 = y + 1
                var j3 = planeY[y]
                var j4 = planeY[k5]
                if j3 < j4 {
                    var x = planeX[y] << 8
                    let dx = ((planeX[k5] &- planeX[y]) << 8) / (j4 &- j3)
                    var s = vertexShade[y] << 8
                    let ds = ((vertexShade[k5] &- vertexShade[y]) << 8) / (j4 &- j3)
                    if j3 < 0 { x &-= dx &* j3; s &-= ds &* j3; j3 = 0 }
                    if j4 > mxY { j4 = mxY }
                    var r = j3
                    while r <= j4 {
                        let n = Int(r)
                        if x < scanlines[n].startX { scanlines[n].startX = x; scanlines[n].startS = s }
                        if x > scanlines[n].endX { scanlines[n].endX = x; scanlines[n].endS = s }
                        x &+= dx; s &+= ds
                        r += 1
                    }
                } else if j3 > j4 {
                    var x = planeX[k5] << 8
                    let dx = ((planeX[y] &- planeX[k5]) << 8) / (j3 &- j4)
                    var s = vertexShade[k5] << 8
                    let ds = ((vertexShade[y] &- vertexShade[k5]) << 8) / (j3 &- j4)
                    if j4 < 0 { x &-= dx &* j4; s &-= ds &* j4; j4 = 0 }
                    if j3 > mxY { j3 = mxY }
                    var r = j4
                    while r <= j3 {
                        let n = Int(r)
                        if x < scanlines[n].startX { scanlines[n].startX = x; scanlines[n].startS = s }
                        if x > scanlines[n].endX { scanlines[n].endX = x; scanlines[n].endS = s }
                        x &+= dx; s &+= ds
                        r += 1
                    }
                }
            }
            if minY < baseY - clipY { minY = baseY - clipY }
        }

        if mousePickingActive && mouseY >= minY && mouseY < maxY {
            let sl = scanlines[mouseY]
            if mouseX >= Int(sl.startX >> 8) && mouseX <= Int(sl.endX >> 8) && sl.startX <= sl.endX &&
                !model.unpickable && model.isLocalPlayer![face] == 0 {
                mousePick(model, face)
            }
        }
    }

    // MARK: - Rasterise

    func rasterize(_ vertexCount: Int, _ faceFill: Int, _ model: GameModel) {
        var fill = faceFill
        if fill == -2 { return }
        let cx = Int32(clipX)

        if fill >= 0 {
            if fill >= textureCount { fill = 0 }
            prepareTexture(fill)
            let texture = texturePixels[fill]!.pointer
            let vx = vertexX[0], vy = vertexY[0], vz = vertexZ[0]
            let i3 = vx &- vertexX[1], k3 = vy &- vertexY[1], i4 = vz &- vertexZ[1]
            let last = vertexCount - 1
            let i6 = vertexX[last] &- vx, j7 = vertexY[last] &- vy, k8 = vertexZ[last] &- vz

            if textureDimension[fill] == 1 {
                var l9 = (i6 &* vy &- j7 &* vx) << 12
                let k10 = (j7 &* vz &- k8 &* vy) << 7
                var i11 = (k8 &* vx &- i6 &* vz) << 3
                var k11 = (i3 &* vy &- k3 &* vx) << 12
                let i12 = (k3 &* vz &- i4 &* vy) << 7
                var k12 = (i4 &* vx &- i3 &* vz) << 3
                var i13 = (k3 &* i6 &- i3 &* j7) << 5
                let k13 = i4 &* j7 &- k3 &* k8
                var i14 = (i3 &* k8 &- i4 &* i6) >> 4
                let k14 = k10 >> 4, i15 = i12 >> 4, k15 = k13 >> 4
                let i16 = Int32(minY - baseY)
                var k16 = Int32(width)
                var i17 = Int32(baseX) &+ Int32(minY) &* k16
                var inc = 1
                l9 &+= i11 &* i16
                k11 &+= k12 &* i16
                i13 &+= i14 &* i16
                if interlace {
                    if minY & 1 == 1 {
                        minY += 1
                        l9 &+= i11; k11 &+= k12; i13 &+= i14; i17 &+= k16
                    }
                    i11 <<= 1; k12 <<= 1; i14 <<= 1; k16 <<= 1
                    inc = 2
                }
                let alpha = textureBackTransparent[fill]
                var i = minY
                while i < maxY {
                    let sl = scanlines[i]
                    var j = sl.startX >> 8
                    let e = sl.endX >> 8
                    var length = e &- j
                    if length > 0 {
                        var s = sl.startS
                        let ds = (sl.endS &- s) / length
                        if j < -cx {
                            s &+= (-cx &- j) &* ds
                            j = -cx
                            length = e &- j
                        }
                        if e > cx { length = cx &- j }
                        let r = raster + Int(i17 &+ j)
                        if alpha {
                            Scene.texture128AlphaKeyScanline(r, texture, l9 &+ k14 &* j, k11 &+ i15 &* j,
                                                             i13 &+ k15 &* j, k10, i12, k13, length, s, ds)
                        } else {
                            Scene.texture128Scanline(r, texture, l9 &+ k14 &* j, k11 &+ i15 &* j,
                                                     i13 &+ k15 &* j, k10, i12, k13, length, s, ds << 2)
                        }
                    }
                    l9 &+= i11; k11 &+= k12; i13 &+= i14; i17 &+= k16
                    i += inc
                }
                return
            }

            var i10 = (i6 &* vy &- j7 &* vx) << 11
            let l10 = (j7 &* vz &- k8 &* vy) << 6
            var j11 = (k8 &* vx &- i6 &* vz) << 2
            var l11 = (i3 &* vy &- k3 &* vx) << 11
            let j12 = (k3 &* vz &- i4 &* vy) << 6
            var l12 = (i4 &* vx &- i3 &* vz) << 2
            var j13 = (k3 &* i6 &- i3 &* j7) << 5
            let l13 = i4 &* j7 &- k3 &* k8
            var j14 = (i3 &* k8 &- i4 &* i6) >> 4
            let l14 = l10 >> 4, j15 = j12 >> 4, l15 = l13 >> 4
            let j16 = Int32(minY - baseY)
            var l16 = Int32(width)
            var j17 = Int32(baseX) &+ Int32(minY) &* l16
            var inc = 1
            i10 &+= j11 &* j16
            l11 &+= l12 &* j16
            j13 &+= j14 &* j16
            if interlace {
                if minY & 1 == 1 {
                    minY += 1
                    i10 &+= j11; l11 &+= l12; j13 &+= j14; j17 &+= l16
                }
                j11 <<= 1; l12 <<= 1; j14 <<= 1; l16 <<= 1
                inc = 2
            }
            let alpha = textureBackTransparent[fill]
            var i = minY
            while i < maxY {
                let sl = scanlines[i]
                var j = sl.startX >> 8
                let e = sl.endX >> 8
                var length = e &- j
                if length > 0 {
                    var s = sl.startS
                    let ds = (sl.endS &- s) / length
                    if j < -cx {
                        s &+= (-cx &- j) &* ds
                        j = -cx
                        length = e &- j
                    }
                    if e > cx { length = cx &- j }
                    let r = raster + Int(j17 &+ j)
                    if alpha {
                        Scene.texture64AlphaKeyScanline(r, texture, i10 &+ l14 &* j, l11 &+ j15 &* j,
                                                        j13 &+ l15 &* j, l10, j12, l13, length, s, ds)
                    } else {
                        Scene.texture64Scanline(r, texture, i10 &+ l14 &* j, l11 &+ j15 &* j,
                                                j13 &+ l15 &* j, l10, j12, l13, length, s, ds)
                    }
                }
                i10 &+= j11; l11 &+= l12; j13 &+= j14; j17 &+= l16
                i += inc
            }
            return
        }

        let rampSize = Int(Scene.rampSize)
        for i in 0..<Scene.rampCount {
            if gradientBase[i] == fill {
                gradientRamp = i * rampSize
                break
            }
            if i == Scene.rampCount - 1 {
                // rsc-c picks the slot with rand() (shared with terrain ambience); the slot only affects caching.
                let index = min(Int(CRandom.shared.nextUnitFloat() * Float(Scene.rampCount)), Scene.rampCount - 1)
                gradientBase[index] = fill
                let f = -1 - fill
                let r = ((f >> 10) & 0x1f) * 8, g = ((f >> 5) & 0x1f) * 8, b = (f & 0x1f) * 8
                for j in 0..<256 {
                    let d = j * j
                    let dr = (r * d) / 0x10000, dg = (g * d) / 0x10000, db = (b * d) / 0x10000
                    gradientRamps[index * rampSize + (rampSize - 1) - j] = Int32((dr << 16) + (dg << 8) + db)
                }
                gradientRamp = index * rampSize
            }
        }
        let ramp = gradientRamps.pointer + gradientRamp

        var i2 = Int32(width)
        var l2 = Int32(baseX) &+ Int32(minY) &* i2
        var inc = 1
        if interlace {
            if minY & 1 == 1 {
                minY += 1
                l2 &+= i2
            }
            i2 <<= 1
            inc = 2
        }
        let translucent = model.transparent
        var i = minY
        while i < maxY {
            let sl = scanlines[i]
            var j = sl.startX >> 8
            let e = sl.endX >> 8
            var length = e &- j
            if length > 0 {
                var index = sl.startS
                let step = (sl.endS &- index) / length
                if j < -cx {
                    index &+= (-cx &- j) &* step
                    j = -cx
                    length = e &- j
                }
                if e > cx { length = cx &- j }
                let r = raster + Int(l2 &+ j)
                if translucent {
                    Scene.colourTranslucentScanline(r, 0 &- length, ramp, index, step)
                } else {
                    Scene.colourScanline(r, 0 &- length, ramp, index, step)
                }
            }
            l2 &+= i2
            i += inc
        }
    }

    // MARK: - Scanline fillers

    static func texture128Scanline(_ r: UnsafeMutablePointer<Int32>, _ texture: UnsafeMutablePointer<Int32>,
                                   _ k0: Int32, _ l0: Int32, _ i10: Int32, _ j1: Int32, _ k1: Int32, _ l1: Int32,
                                   _ length: Int32, _ k20: Int32, _ l2: Int32) {
        if length <= 0 { return }
        let shift: Int32 = 7, size: Int32 = 128, area: Int32 = 128 * 128 - 128
        var raster = r
        var k = k0, l = l0, i1 = i10, k2 = k20
        var i: Int32 = 0, j: Int32 = 0, i3: Int32 = 0, j3: Int32 = 0, i4: Int32 = 0
        if i1 != 0 {
            i = (k / i1) << shift
            j = (l / i1) << shift
        }
        if i < 0 { i = 0 } else if i > area { i = area }
        k &+= j1; l &+= k1; i1 &+= l1
        if i1 != 0 {
            i3 = (k / i1) << shift
            j3 = (l / i1) << shift
        }
        if i3 < 0 { i3 = 0 } else if i3 > area { i3 = area }
        var k3 = (i3 &- i) / 16
        var l3 = (j3 &- j) / 16
        var n = length / 16
        while n > 0 {
            for _ in 0..<4 {
                i = (i & (area + (size - 1))) &+ (k2 & 0x600000)
                i4 = k2 >> 23
                k2 &+= l2
                for _ in 0..<4 {
                    raster.pointee = texture[Int((j & area) &+ (i >> shift))] >> i4
                    raster += 1
                    i &+= k3; j &+= l3
                }
            }
            i = i3; j = j3
            k &+= j1; l &+= k1; i1 &+= l1
            if i1 != 0 {
                i3 = (k / i1) << shift
                j3 = (l / i1) << shift
            }
            if i3 < 0 { i3 = 0 } else if i3 > area { i3 = area }
            k3 = (i3 &- i) / 16
            l3 = (j3 &- j) / 16
            n -= 1
        }
        var m: Int32 = 0
        while m < (length & 0xf) {
            if m & 3 == 0 {
                i = (i & (area + (size - 1))) &+ (k2 & 0x600000)
                i4 = k2 >> 23
                k2 &+= l2
            }
            raster.pointee = texture[Int((j & area) &+ (i >> shift))] >> i4
            raster += 1
            i &+= k3; j &+= l3
            m += 1
        }
    }

    static func texture128AlphaKeyScanline(_ r: UnsafeMutablePointer<Int32>, _ texture: UnsafeMutablePointer<Int32>,
                                           _ l0: Int32, _ i10: Int32, _ j10: Int32, _ k1: Int32, _ l1: Int32,
                                           _ i2: Int32, _ length: Int32, _ l20: Int32, _ i30: Int32) {
        alphaKeyScanline(r, texture, l0, i10, j10, k1, l1, i2, length, l20, i30, shift: 7, mask: 0x600000, toneShift: 23)
    }

    static func texture64AlphaKeyScanline(_ r: UnsafeMutablePointer<Int32>, _ texture: UnsafeMutablePointer<Int32>,
                                          _ l0: Int32, _ i10: Int32, _ j10: Int32, _ k1: Int32, _ l1: Int32,
                                          _ i2: Int32, _ length: Int32, _ l20: Int32, _ i30: Int32) {
        alphaKeyScanline(r, texture, l0, i10, j10, k1, l1, i2, length, l20, i30, shift: 6, mask: 0xc0000, toneShift: 20)
    }

    /// scene_texture128_alphakey_scanline and scene_texture64_alphakey_scanline differ only in these constants.
    @inline(__always)
    private static func alphaKeyScanline(_ r: UnsafeMutablePointer<Int32>, _ texture: UnsafeMutablePointer<Int32>,
                                         _ l0: Int32, _ i10: Int32, _ j10: Int32, _ k1: Int32, _ l1: Int32,
                                         _ i2: Int32, _ length: Int32, _ l20: Int32, _ i30: Int32,
                                         shift: Int32, mask: Int32, toneShift: Int32) {
        if length <= 0 { return }
        let size: Int32 = 1 << shift
        let area = size * size - size
        var raster = r
        var l = l0, i1 = i10, j1 = j10, l2 = l20
        let i3 = i30 << 2
        var j: Int32 = 0, k: Int32 = 0, j3: Int32 = 0, k3: Int32 = 0
        if j1 != 0 {
            j3 = (l / j1) << shift
            k3 = (i1 / j1) << shift
        }
        if j3 < 0 { j3 = 0 } else if j3 > area { j3 = area }
        var n = length
        while n > 0 {
            l &+= k1; i1 &+= l1; j1 &+= i2
            j = j3; k = k3
            if j1 != 0 {
                j3 = (l / j1) << shift
                k3 = (i1 / j1) << shift
            }
            if j3 < 0 { j3 = 0 } else if j3 > area { j3 = area }
            let l3 = (j3 &- j) >> 4
            let i4 = (k3 &- k) >> 4
            var k4 = l2 >> toneShift
            j &+= l2 & mask
            l2 &+= i3
            if n < 16 {
                var m: Int32 = 0
                while m < n {
                    let colour = texture[Int((k & area) &+ (j >> shift))] >> k4
                    if colour != 0 { raster.pointee = colour }
                    raster += 1
                    j &+= l3; k &+= i4
                    if m & 3 == 3 {
                        j = (j & (area + size - 1)) &+ (l2 & mask)
                        k4 = l2 >> toneShift
                        l2 &+= i3
                    }
                    m += 1
                }
            } else {
                for a in 0..<4 {
                    for _ in 0..<4 {
                        let colour = texture[Int((k & area) &+ (j >> shift))] >> k4
                        if colour != 0 { raster.pointee = colour }
                        raster += 1
                        j &+= l3; k &+= i4
                    }
                    if a == 3 { break }
                    j = (j & (area + size - 1)) &+ (l2 & mask)
                    k4 = l2 >> toneShift
                    l2 &+= i3
                }
            }
            n -= 16
        }
    }

    static func texture64Scanline(_ r: UnsafeMutablePointer<Int32>, _ texture: UnsafeMutablePointer<Int32>,
                                  _ k0: Int32, _ l0: Int32, _ i10: Int32, _ j1: Int32, _ k1: Int32, _ l1: Int32,
                                  _ length: Int32, _ k20: Int32, _ l20: Int32) {
        if length <= 0 { return }
        let shift: Int32 = 6, size: Int32 = 64, area: Int32 = 64 * 64 - 64
        var raster = r
        var k = k0, l = l0, i1 = i10, k2 = k20
        let l2 = l20 << 2
        var i: Int32 = 0, j: Int32 = 0, i3: Int32 = 0, j3: Int32 = 0
        if i1 != 0 {
            i3 = (k / i1) << shift
            j3 = (l / i1) << shift
        }
        if i3 < 0 { i3 = 0 } else if i3 > area { i3 = area }
        var n = length
        while n > 0 {
            k &+= j1; l &+= k1; i1 &+= l1
            i = i3; j = j3
            if i1 != 0 {
                i3 = (k / i1) << shift
                j3 = (l / i1) << shift
            }
            if i3 < 0 { i3 = 0 } else if i3 > area { i3 = area }
            let k3 = (i3 &- i) >> 4
            let l3 = (j3 &- j) >> 4
            var j4 = k2 >> 20
            i &+= k2 & 0xc0000
            k2 &+= l2
            if n < 16 {
                var m: Int32 = 0
                while m < n {
                    raster.pointee = texture[Int((j & area) &+ (i >> shift))] >> j4
                    raster += 1
                    i &+= k3; j &+= l3
                    if m & 3 == 3 {
                        i = (i & (area + size - 1)) &+ (k2 & 0xc0000)
                        j4 = k2 >> 20
                        k2 &+= l2
                    }
                    m += 1
                }
            } else {
                for a in 0..<4 {
                    for _ in 0..<4 {
                        raster.pointee = texture[Int((j & area) &+ (i >> shift))] >> j4
                        raster += 1
                        i &+= k3; j &+= l3
                    }
                    if a == 3 { break }
                    i = (i & (area + size - 1)) &+ (k2 & 0xc0000)
                    j4 = k2 >> 20
                    k2 &+= l2
                }
            }
            n -= 16
        }
    }

    static func colourTranslucentScanline(_ r: UnsafeMutablePointer<Int32>, _ i: Int32,
                                          _ ramp: UnsafeMutablePointer<Int32>, _ index0: Int32, _ inc0: Int32) {
        if i >= 0 { return }
        var raster = r
        let inc = inc0 &* 4
        var index = index0
        var colour = ramp[Int((index / rampSize) & 0xff)]
        index &+= inc
        var n = i / 16
        while n < 0 {
            for _ in 0..<4 {
                for _ in 0..<4 {
                    raster.pointee = colour &+ (((raster + 1).pointee >> 1) & 0x7f7f7f)
                    raster += 1
                }
                colour = ramp[Int((index / rampSize) & 0xff)]
                index &+= inc
            }
            n += 1
        }
        let rest = -(i % 16)
        var m: Int32 = 0
        while m < rest {
            raster.pointee = colour &+ (((raster + 1).pointee >> 1) & 0x7f7f7f)
            raster += 1
            if m & 3 == 3 {
                colour = ramp[Int((index / rampSize) & 0xff)]
                index &+= inc &* 2
            }
            m += 1
        }
    }

    static func colourScanline(_ r: UnsafeMutablePointer<Int32>, _ i: Int32,
                               _ ramp: UnsafeMutablePointer<Int32>, _ index0: Int32, _ inc0: Int32) {
        if i >= 0 { return }
        var raster = r
        let inc = inc0 &* 4
        var index = index0
        var colour = ramp[Int((index / rampSize) & 0xff)]
        index &+= inc
        var n = i / 16
        while n < 0 {
            for _ in 0..<4 {
                for _ in 0..<4 {
                    raster.pointee = colour
                    raster += 1
                }
                colour = ramp[Int((index / rampSize) & 0xff)]
                index &+= inc
            }
            n += 1
        }
        let rest = -(i % 16)
        var m: Int32 = 0
        while m < rest {
            raster.pointee = colour
            raster += 1
            if m & 3 == 3 {
                colour = ramp[Int((index >> 8) & 0xff)]
                index &+= inc
            }
            m += 1
        }
    }
}
