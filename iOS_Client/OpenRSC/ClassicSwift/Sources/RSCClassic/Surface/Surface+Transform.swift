// Rotated minimap sprites and the scaled/skewed/masked entity sprite path
// from rsc-c's surface.c.

import Foundation

extension Surface {
    public func drawMinimapSprite(x: Int, y: Int, id: Int, rotation: Int, scale: Int) {
        let rotation = rotation & 255
        let j1 = width
        let k1 = height
        var i2 = -(spriteWidthFull[id] / 2)
        var j2 = -(spriteHeightFull[id] / 2)
        if spriteTranslate[id] {
            i2 += spriteTranslateX[id]
            j2 += spriteTranslateY[id]
        }
        var k2 = i2 + spriteWidth[id]
        var l2 = j2 + spriteHeight[id]
        var i3 = k2
        var j3 = j2
        var k3 = i2
        var l3 = l2

        let i4 = Tables.sinCos512[rotation] * scale
        let j4 = Tables.sinCos512[rotation + 256] * scale
        let k4 = x + ((j2 * i4 + i2 * j4) >> 22)
        let l4 = y + ((j2 * j4 - i2 * i4) >> 22)
        let i5 = x + ((j3 * i4 + i3 * j4) >> 22)
        let j5 = y + ((j3 * j4 - i3 * i4) >> 22)
        let k5 = x + ((l2 * i4 + k2 * j4) >> 22)
        let l5 = y + ((l2 * j4 - k2 * i4) >> 22)
        let i6 = x + ((l3 * i4 + k3 * j4) >> 22)
        let j6 = y + ((l3 * j4 - k3 * i4) >> 22)

        if scale == 192 && (rotation & 0x3f) == (anInt348 & 0x3f) {
            anInt346 += 1
        } else if scale == 128 {
            anInt348 = rotation
        } else {
            anInt347 += 1
        }

        var k6 = l4
        var l6 = l4
        if j5 < k6 { k6 = j5 } else if j5 > l6 { l6 = j5 }
        if l5 < k6 { k6 = l5 } else if l5 > l6 { l6 = l5 }
        if j6 < k6 { k6 = j6 } else if j6 > l6 { l6 = j6 }
        if k6 < boundsMinY { k6 = boundsMinY }
        if l6 > boundsMaxY { l6 = boundsMaxY }

        if rotations0.count != k1 + 1 {
            rotations0 = [Int](repeating: 0, count: k1 + 1)
            rotations1 = rotations0; rotations2 = rotations0
            rotations3 = rotations0; rotations4 = rotations0; rotations5 = rotations0
        }

        if k6 <= l6 {
            for i in k6...l6 {
                rotations0[i] = 99_999_999
                rotations1[i] = -99_999_999
            }
        }

        var i8 = 0, k8 = 0, i9 = 0
        let sw = spriteWidth[id]
        let sh = spriteHeight[id]
        i2 = 0; j2 = 0
        i3 = sw - 1; j3 = 0
        k2 = sw - 1; l2 = sh - 1
        k3 = 0; l3 = sh - 1

        if j6 != l4 {
            i8 = ((i6 - k4) << 8) / (j6 - l4)
            i9 = ((l3 - j2) << 8) / (j6 - l4)
        }

        var j7 = 0, k7 = 0, l7 = 0, l8 = 0
        if l4 > j6 {
            l7 = i6 << 8; l8 = l3 << 8; j7 = j6; k7 = l4
        } else {
            l7 = k4 << 8; l8 = j2 << 8; j7 = l4; k7 = j6
        }
        if j7 < 0 { l7 -= i8 * j7; l8 -= i9 * j7; j7 = 0 }
        if k7 > k1 - 1 { k7 = k1 - 1 }
        if j7 <= k7 {
            for i in j7...k7 {
                rotations0[i] = l7
                rotations1[i] = l7
                l7 += i8
                rotations2[i] = 0
                rotations3[i] = 0
                rotations4[i] = l8
                rotations5[i] = l8
                l8 += i9
            }
        }

        if j5 != l4 {
            i8 = ((i5 - k4) << 8) / (j5 - l4)
            k8 = ((i3 - i2) << 8) / (j5 - l4)
        }
        var j8 = 0
        if l4 > j5 {
            l7 = i5 << 8; j8 = i3 << 8; j7 = j5; k7 = l4
        } else {
            l7 = k4 << 8; j8 = i2 << 8; j7 = l4; k7 = j5
        }
        if j7 < 0 { l7 -= i8 * j7; j8 -= k8 * j7; j7 = 0 }
        if k7 > k1 - 1 { k7 = k1 - 1 }
        if j7 <= k7 {
            for i in j7...k7 {
                if l7 < rotations0[i] { rotations0[i] = l7; rotations2[i] = j8; rotations4[i] = 0 }
                if l7 > rotations1[i] { rotations1[i] = l7; rotations3[i] = j8; rotations5[i] = 0 }
                l7 += i8
                j8 += k8
            }
        }

        if l5 != j5 {
            i8 = ((k5 - i5) << 8) / (l5 - j5)
            i9 = ((l2 - j3) << 8) / (l5 - j5)
        }
        if j5 > l5 {
            l7 = k5 << 8; j8 = k2 << 8; l8 = l2 << 8; j7 = l5; k7 = j5
        } else {
            l7 = i5 << 8; j8 = i3 << 8; l8 = j3 << 8; j7 = j5; k7 = l5
        }
        if j7 < 0 { l7 -= i8 * j7; l8 -= i9 * j7; j7 = 0 }
        if k7 > k1 - 1 { k7 = k1 - 1 }
        if j7 <= k7 {
            for i in j7...k7 {
                if l7 < rotations0[i] { rotations0[i] = l7; rotations2[i] = j8; rotations4[i] = l8 }
                if l7 > rotations1[i] { rotations1[i] = l7; rotations3[i] = j8; rotations5[i] = l8 }
                l7 += i8
                l8 += i9
            }
        }

        if j6 != l5 {
            i8 = ((i6 - k5) << 8) / (j6 - l5)
            k8 = ((k3 - k2) << 8) / (j6 - l5)
        }
        if l5 > j6 {
            l7 = i6 << 8; j8 = k3 << 8; l8 = l3 << 8; j7 = j6; k7 = l5
        } else {
            l7 = k5 << 8; j8 = k2 << 8; l8 = l2 << 8; j7 = l5; k7 = j6
        }
        if j7 < 0 { l7 -= i8 * j7; j8 -= k8 * j7; j7 = 0 }
        if k7 > k1 - 1 { k7 = k1 - 1 }
        if j7 <= k7 {
            for i in j7...k7 {
                if l7 < rotations0[i] { rotations0[i] = l7; rotations2[i] = j8; rotations4[i] = l8 }
                if l7 > rotations1[i] { rotations1[i] = l7; rotations3[i] = j8; rotations5[i] = l8 }
                l7 += i8
                j8 += k8
            }
        }

        guard let src = spritePixels[id] else { return }
        var l10 = k6 * j1
        var i = k6
        while i < l6 {
            var j11 = rotations0[i] >> 8
            var k11 = rotations1[i] >> 8
            if k11 - j11 <= 0 {
                l10 += j1
            } else {
                var l11 = rotations2[i] << 9
                let i12 = ((rotations3[i] << 9) - l11) / (k11 - j11)
                var j12 = rotations4[i] << 9
                let k12 = ((rotations5[i] << 9) - j12) / (k11 - j11)
                if j11 < boundsMinX {
                    l11 += (boundsMinX - j11) * i12
                    j12 += (boundsMinX - j11) * k12
                    j11 = boundsMinX
                }
                if k11 > boundsMaxX { k11 = boundsMaxX }
                if !interlace || i & 1 == 0 {
                    var destPos = l10 + j11
                    var n = j11 - k11
                    let translate = spriteTranslate[id]
                    while n < 0 {
                        let c = src[(l11 >> 17) + (j12 >> 17) * sw]
                        if !translate || c != 0 { pixels[destPos] = c }
                        destPos += 1
                        l11 += i12
                        j12 += k12
                        n += 1
                    }
                }
                l10 += j1
            }
            i += 1
        }
    }

    /// Scale, grey and skin colour masks, skew and horizontal flip; used for entities and items.
    public func drawSpriteTransformMask(x: Int, y: Int, width drawWidth: Int, height drawHeight: Int, id: Int,
                                        maskColour: Int32, skinColour: Int32, skewX: Int, flip: Bool) {
        var x = x, y = y, dw = drawWidth, dh = drawHeight
        let mask = maskColour == 0 ? Colour.white : maskColour
        let skin = skinColour == 0 ? Colour.white : skinColour

        let sw = spriteWidth[id]
        let sh = spriteHeight[id]
        var offsetX = 0
        var offsetY = 0
        var i3 = skewX << 16
        var widthRatio = (sw << 16) / dw
        var heightRatio = (sh << 16) / dh
        let l3 = -((skewX << 16) / dh)

        if spriteTranslate[id] {
            let fw = spriteWidthFull[id], fh = spriteHeightFull[id]
            widthRatio = (fw << 16) / dw
            heightRatio = (fh << 16) / dh
            var tx = spriteTranslateX[id]
            let ty = spriteTranslateY[id]
            if flip { tx = fw - sw - tx }
            x += (tx * dw + fw - 1) / fw
            let l5 = (ty * dh + fh - 1) / fh
            y += l5
            i3 += l5 * l3
            if (tx * dw) % fw != 0 { offsetX = ((fw - ((tx * dw) % fw)) << 16) / dw }
            if (ty * dh) % fh != 0 { offsetY = ((fh - ((ty * dh) % fh)) << 16) / dh }
            dw = ((sw << 16) - offsetX + widthRatio - 1) / widthRatio
            dh = ((sh << 16) - offsetY + heightRatio - 1) / heightRatio
        }

        var j4 = y * width
        i3 += x << 16
        if y < boundsMinY {
            let clip = boundsMinY - y
            dh -= clip
            y = boundsMinY
            j4 += clip * width
            offsetY += heightRatio * clip
            i3 += l3 * clip
        }
        if y + dh >= boundsMaxY { dh -= y + dh - boundsMaxY + 1 }

        var yInc = (j4 / width) & 1
        if !interlace { yInc = 2 }

        let startX = flip ? (sw << 16) - offsetX - 1 : offsetX
        let stepX = flip ? -widthRatio : widthRatio
        let dual = skin != Colour.white
        let m = Int(mask), s = Int(skin)
        let mr = (m >> 16) & 0xff, mg = (m >> 8) & 0xff, mb = m & 0xff
        let sr = (s >> 16) & 0xff, sg = (s >> 8) & 0xff, sb = s & 0xff

        let raster = spritePixels[id]
        let colours = spriteColours[id]
        let palette = spritePalette[id]
        if raster == nil && (colours == nil || palette == nil) { return }

        var j = startX
        var k = offsetY
        var destPos = j4
        var k2 = i3
        for _ in stride(from: -dh, to: 0, by: 1) {
            let row = (k >> 16) * sw
            var xStart = k2 >> 16
            var w = dw
            if xStart < boundsMinX {
                let clip = boundsMinX - xStart
                w -= clip
                xStart = boundsMinX
                j += stepX * clip
            }
            if xStart + w >= boundsMaxX { w -= xStart + w - boundsMaxX }

            yInc = 1 - yInc
            if yInc != 0 {
                var px = xStart
                while px < xStart + w {
                    var colour: Int32
                    if let raster {
                        colour = raster[(j >> 16) + row]
                    } else {
                        let index = colours![(j >> 16) + row]
                        colour = index == 0 ? 0 : palette![Int(index)]
                        if index == 0 { j += stepX; px += 1; continue }
                    }
                    if raster == nil || colour != 0 {
                        let c = Int(colour)
                        let r = (c >> 16) & 0xff, g = (c >> 8) & 0xff, b = c & 0xff
                        if r == g && g == b {
                            pixels[px + destPos] = Int32(truncatingIfNeeded: (((r * mr) >> 8) << 16) + (((g * mg) >> 8) << 8) + ((b * mb) >> 8))
                        } else if dual && r == 255 && g == b {
                            pixels[px + destPos] = Int32(truncatingIfNeeded: (((r * sr) >> 8) << 16) + (((g * sg) >> 8) << 8) + ((b * sb) >> 8))
                        } else {
                            pixels[px + destPos] = colour
                        }
                    }
                    j += stepX
                    px += 1
                }
            }
            k += heightRatio
            j = startX
            destPos += width
            k2 += l3
        }
    }
}
