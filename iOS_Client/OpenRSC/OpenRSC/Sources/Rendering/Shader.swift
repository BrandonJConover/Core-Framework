// Port of Client_Base/src/orsc/graphics/three/Shader.java
//
// Shader contains six static scanline-fill overloads.  In the Java source every
// overload is named `shadeScanline`; Swift does not support overloading by
// parameter count alone when the types are the same, so each variant is given a
// descriptive name that encodes its purpose.  The call-sites in Scene.swift must
// use the matching name.
//
// Naming convention used here:
//   shadeScanlineTransparentNormal    – overload A: transparent (skip 0) 64×64 texture
//   shadeScanlineOpaqueNormal         – overload B: opaque 64×64 texture (guard byte==50)
//   shadeScanlineBlendNormal          – overload C: 50 % background blend + 64×64 texture
//   shadeScanlineBlendLarge           – overload D: 50 % background blend + 256×256 texture
//   shadeScanlineOpaqueLarge          – overload E: opaque 256×256 texture
//   shadeScanlineTransparentLarge     – overload F: transparent (skip 0) 256×256 texture (guard byte==25)
//
// All integer arithmetic uses Int32 with Swift overflow operators (&+, &-, &*, &>>)
// exactly as Java `int` silently wraps.  The >>> logical-right-shift from Java is
// emulated with `Int32(bitPattern: UInt32(bitPattern: x) >> n)`.
//
// Hot-path pixel writes use UnsafeMutablePointer so the compiler does not emit
// bounds checks on every store.

import Foundation

// MARK: - Logical right-shift helper (Java >>>)

@inline(__always)
private func logicalRightShift(_ value: Int32, _ shift: Int32) -> Int32 {
    Int32(bitPattern: UInt32(bitPattern: value) >> UInt32(shift & 31))
}

// MARK: - bitwiseAnd helper (matches FastMath.bitwiseAnd semantics)

@inline(__always)
private func bitwiseAnd(_ a: Int32, _ b: Int32) -> Int32 { a & b }

// MARK: - Shader

/// Scanline rasterizer — direct port of `orsc.graphics.three.Shader`.
///
/// The caller (Scene) must set `pixelData` and `pixelDataCount` before invoking
/// any `shadeScanline` variant.
final class Shader {

    // MARK: Framebuffer reference

    /// Pointer into the caller's pixel buffer.  Must be set before use.
    var pixelData: UnsafeMutablePointer<Int32>?
    var pixelDataCount: Int = 0

    // MARK: Texture storage

    /// Up to 50 textures; each is a flat Int32 array.
    var textures: [[Int32]] = []

    // MARK: - Overload A: Transparent normal (64×64) texture scanline
    //
    // Java signature:
    //   static void shadeScanline(int var0, int var1, int var2, int var3,
    //                             int[] var4, int var5, int var6,
    //                             int var7, int var8, int var9,
    //                             int var10, int var11, int var12,
    //                             int var13, int[] var14, int var15)
    //
    // Functional role:
    //   Transparent texture fill using a 64×64 texture (mask 0x3F80, shift >>7).
    //   Pixels with value 0 are skipped (not written).
    //   Uses 16-pixel Bresenham perspective-correction spans.
    //   var4  = destination pixel buffer (pixelData)
    //   var14 = source texture
    //   var15 = pixel count (width of scanline)
    //   var9  = starting write index into var4

    func shadeScanlineTransparentNormal(
        var0:  Int32, var1:  Int32, var2:  Int32, var3:  Int32,
        dest:  UnsafeMutablePointer<Int32>,
        var5:  Int32, var6:  Int32,
        var7:  Int32, var8:  Int32, var9:  Int32,
        var10: Int32, var11: Int32, var12: Int32,
        var13: Int32, texture: UnsafePointer<Int32>, var15: Int32
    ) {
        guard var15 > 0 else { return }

        // Sentinel recursive call in Java is dead code — omitted.

        var lVar2  = var2
        var lVar3  = var3
        var lVar5  = var5
        var lVar6  = var6
        var lVar7  = var7
        var lVar8  = var8
        var lVar9  = var9
        let lVar11 = var11 &<< 2
        var lVar12 = var12
        var lVar16: Int32 = 0
        var lVar17: Int32 = 0

        if lVar5 != 0 {
            lVar17 = (lVar8 / lVar5) &<< 7
            lVar16 = (lVar7 / lVar5) &<< 7
        }

        if lVar16 < 0 { lVar16 = 0 } else if lVar16 > 0x3F80 { lVar16 = 0x3F80 }

        var count = var15
        while count > 0 {
            lVar7 = lVar7 &+ var13
            lVar3 = lVar17
            lVar5 = lVar5 &+ var10
            lVar2 = lVar16
            lVar8 = lVar8 &+ var0
            if lVar5 != 0 {
                lVar16 = (lVar7 / lVar5) &<< 7
                lVar17 = (lVar8 / lVar5) &<< 7
            }

            if lVar16 < 0 { lVar16 = 0 } else if lVar16 > 0x3F80 { lVar16 = 0x3F80 }

            let var18: Int32 = (lVar16 &- lVar2) >> 4
            let var19: Int32 = (lVar17 &- lVar3) >> 4
            var var21:  Int32 = lVar6 >> 23
            lVar2 = lVar2 &+ (6291456 & lVar6)
            lVar6 = lVar6 &+ lVar11

            if count < 16 {
                // Tail loop
                var k: Int32 = 0
                while k < count {
                    let texIdx = (lVar3 & 0x3F80) &+ (lVar2 >> 7)
                    lVar12 = logicalRightShift(texture[Int(texIdx)], var21)
                    if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                    lVar9 = lVar9 &+ 1
                    lVar2 = lVar2 &+ var18
                    lVar3 = lVar3 &+ var19
                    if (k & 3) == 3 {
                        lVar2 = (lVar6 & 6291456) &+ (16383 & lVar2)
                        var21 = lVar6 >> 23
                        lVar6 = lVar6 &+ lVar11
                    }
                    k += 1
                }
            } else {
                // Full 16-pixel unrolled block
                lVar12 = logicalRightShift(texture[Int((lVar3 & 0x3F80) &+ (lVar2 >> 7))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar2 &+= var18; lVar9 &+= 1; lVar3 &+= var19

                lVar12 = logicalRightShift(texture[Int((lVar2 >> 7) &+ (0x3F80 & lVar3))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar9 &+= 1; lVar3 &+= var19; lVar2 &+= var18

                lVar12 = logicalRightShift(texture[Int((lVar2 >> 7) &+ (0x3F80 & lVar3))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar9 &+= 1; lVar3 &+= var19; lVar2 &+= var18

                lVar12 = logicalRightShift(texture[Int((lVar2 >> 7) &+ (lVar3 & 0x3F80))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar2 &+= var18; lVar3 &+= var19; lVar9 &+= 1

                // Mid-span correction (pixel 4)
                var21 = lVar6 >> 23
                lVar2 = (lVar6 & 6291456) &+ (16383 & lVar2)
                lVar6 &+= lVar11

                lVar12 = logicalRightShift(texture[Int((lVar3 & 0x3F80) &+ (lVar2 >> 7))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar2 &+= var18; lVar9 &+= 1; lVar3 &+= var19

                lVar12 = logicalRightShift(texture[Int((0x3F80 & lVar3) &+ (lVar2 >> 7))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar9 &+= 1; lVar2 &+= var18; lVar3 &+= var19

                lVar12 = logicalRightShift(texture[Int((lVar2 >> 7) &+ (0x3F80 & lVar3))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar2 &+= var18; lVar3 &+= var19; lVar9 &+= 1

                lVar12 = logicalRightShift(texture[Int((lVar2 >> 7) &+ (lVar3 & 0x3F80))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar3 &+= var19; lVar9 &+= 1; lVar2 &+= var18

                // Mid-span correction (pixel 8)
                var21 = lVar6 >> 23
                lVar2 = (lVar2 & 16383) &+ (6291456 & lVar6)

                lVar12 = logicalRightShift(texture[Int((lVar2 >> 7) &+ (lVar3 & 0x3F80))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar6 &+= lVar11; lVar9 &+= 1; lVar2 &+= var18; lVar3 &+= var19

                lVar12 = logicalRightShift(texture[Int((lVar2 >> 7) &+ (lVar3 & 0x3F80))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar3 &+= var19; lVar9 &+= 1; lVar2 &+= var18

                lVar12 = logicalRightShift(texture[Int((0x3F80 & lVar3) &+ (lVar2 >> 7))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar3 &+= var19; lVar2 &+= var18; lVar9 &+= 1

                lVar12 = logicalRightShift(texture[Int((lVar2 >> 7) &+ (lVar3 & 0x3F80))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar2 &+= var18; lVar3 &+= var19; lVar9 &+= 1

                // Mid-span correction (pixel 12)
                lVar2 = (lVar2 & 16383) &+ (lVar6 & 6291456)
                var21 = lVar6 >> 23

                lVar12 = logicalRightShift(texture[Int((lVar3 & 0x3F80) &+ (lVar2 >> 7))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar6 &+= lVar11; lVar3 &+= var19; lVar9 &+= 1; lVar2 &+= var18

                lVar12 = logicalRightShift(texture[Int((lVar2 >> 7) &+ (lVar3 & 0x3F80))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar9 &+= 1; lVar2 &+= var18; lVar3 &+= var19

                lVar12 = logicalRightShift(texture[Int((lVar2 >> 7) &+ (lVar3 & 0x3F80))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar3 &+= var19; lVar2 &+= var18; lVar9 &+= 1

                lVar12 = logicalRightShift(texture[Int((0x3F80 & lVar3) &+ (lVar2 >> 7))], var21)
                if lVar12 != 0 { dest[Int(lVar9)] = lVar12 }
                lVar9 &+= 1
            }
            count -= 16
        }
    }

    // MARK: - Overload B: Opaque normal (64×64) texture scanline  (guard: var2 == 50)
    //
    // Java signature:
    //   static void shadeScanline(int var0, int var1, byte var2, int var3,
    //                             int val, int valStep, int[] src,
    //                             int dH, int var8, int var9, int high, int low,
    //                             int[] dest, int var13, int var14)
    //
    // The Java body only executes when var2 == 50.
    // texture lookup: src[(low >> 7) + (high & 0x3F80)]
    // Writes directly (no skip-0 test).

    func shadeScanlineOpaqueNormal(
        var0: Int32, var1: Int32, var2: Int8, var3: Int32,
        val:  Int32, valStep: Int32, src: UnsafePointer<Int32>,
        dH:   Int32, var8: Int32, var9: Int32,
        high: Int32, low:  Int32,
        dest: UnsafeMutablePointer<Int32>,
        var13: Int32, var14: Int32
    ) {
        guard var14 > 0 && var2 == 50 else { return }

        var lVar0  = var0
        let lVar1  = var1
        var lVar3  = var3
        var lVal   = val
        let lValStep = valStep
        var lDH    = dH
        var lVar8  = var8
        let lVar9  = var9
        var lHigh  = high
        var lLow   = low
        let lVar13 = var13
        let lVar14 = var14

        var lVar15: Int32 = 0
        var lVar16: Int32 = 0

        if lVar3 != 0 {
            lLow  = (lVar8 / lVar3) &<< 7
            lHigh = (lVar0 / lVar3) &<< 7
        }

        var shift: Int32 = 0
        if lLow < 0 { lLow = 0 } else if lLow > 0x3F80 { lLow = 0x3F80 }

        lVar3  = lVar3 &+ lVar9
        lVar0  = lVar0 &+ lVar13
        lVar8  = lVar8 &+ lVar1
        if lVar3 != 0 {
            lVar16 = (lVar0 / lVar3) &<< 7
            lVar15 = (lVar8 / lVar3) &<< 7
        }
        if lVar15 < 0 { lVar15 = 0 } else if lVar15 > 0x3F80 { lVar15 = 0x3F80 }

        var lowStep:  Int32 = (lVar15 &- lLow)  >> 4
        var highStep: Int32 = (lVar16 &- lHigh) >> 4

        // Full 16-pixel blocks
        var remaining = lVar14 >> 4
        while remaining > 0 {
            lLow = lLow &+ (lVal & 6291456)
            shift = lVal >> 23
            dest[Int(lDH)] = logicalRightShift(src[Int((0x3F80 & lHigh) &+ (lLow >> 7))], shift)
            lDH &+= 1; lVal &+= lValStep; lLow &+= lowStep; lHigh &+= highStep

            dest[Int(lDH)] = logicalRightShift(src[Int((lLow >> 7) &+ (0x3F80 & lHigh))], shift)
            lHigh &+= highStep; lLow &+= lowStep; lDH &+= 1

            dest[Int(lDH)] = logicalRightShift(src[Int((lLow >> 7) &+ (0x3F80 & lHigh))], shift)
            lHigh &+= highStep; lLow &+= lowStep; lDH &+= 1

            dest[Int(lDH)] = logicalRightShift(src[Int((lLow >> 7) &+ (0x3F80 & lHigh))], shift)
            lHigh &+= highStep; lLow &+= lowStep; lDH &+= 1

            lLow = (6291456 & lVal) &+ (16383 & lLow)
            shift = lVal >> 23
            dest[Int(lDH)] = logicalRightShift(src[Int((lLow >> 7) &+ (lHigh & 0x3F80))], shift)
            lDH &+= 1; lVal &+= lValStep; lLow &+= lowStep; lHigh &+= highStep

            dest[Int(lDH)] = logicalRightShift(src[Int((0x3F80 & lHigh) &+ (lLow >> 7))], shift)
            lLow &+= lowStep; lHigh &+= highStep; lDH &+= 1

            dest[Int(lDH)] = logicalRightShift(src[Int((lLow >> 7) &+ (0x3F80 & lHigh))], shift)
            lHigh &+= highStep; lLow &+= lowStep; lDH &+= 1

            dest[Int(lDH)] = logicalRightShift(src[Int((0x3F80 & lHigh) &+ (lLow >> 7))], shift)
            lHigh &+= highStep; lLow &+= lowStep; lDH &+= 1

            lLow = (lVal & 6291456) &+ (16383 & lLow)
            shift = lVal >> 23
            lVal &+= lValStep
            dest[Int(lDH)] = logicalRightShift(src[Int((lHigh & 0x3F80) &+ (lLow >> 7))], shift)
            lLow &+= lowStep; lHigh &+= highStep; lDH &+= 1

            dest[Int(lDH)] = logicalRightShift(src[Int((0x3F80 & lHigh) &+ (lLow >> 7))], shift)
            lLow &+= lowStep; lHigh &+= highStep; lDH &+= 1

            dest[Int(lDH)] = logicalRightShift(src[Int((lLow >> 7) &+ (0x3F80 & lHigh))], shift)
            lHigh &+= highStep; lLow &+= lowStep; lDH &+= 1

            dest[Int(lDH)] = logicalRightShift(src[Int((lLow >> 7) &+ (lHigh & 0x3F80))], shift)
            lLow &+= lowStep; lHigh &+= highStep; lDH &+= 1

            lLow = (16383 & lLow) &+ (6291456 & lVal)
            shift = lVal >> 23
            dest[Int(lDH)] = logicalRightShift(src[Int((lLow >> 7) &+ (0x3F80 & lHigh))], shift)
            lDH &+= 1; lVal &+= lValStep; lLow &+= lowStep; lHigh &+= highStep

            dest[Int(lDH)] = logicalRightShift(src[Int((lLow >> 7) &+ (lHigh & 0x3F80))], shift)
            lLow &+= lowStep; lHigh &+= highStep; lDH &+= 1

            dest[Int(lDH)] = logicalRightShift(src[Int((lLow >> 7) &+ (0x3F80 & lHigh))], shift)
            lHigh &+= highStep; lLow &+= lowStep; lDH &+= 1

            dest[Int(lDH)] = logicalRightShift(src[Int((lLow >> 7) &+ (0x3F80 & lHigh))], shift)
            lDH &+= 1

            // Recalculate perspective-correct UV for next span
            lLow  = lVar15
            lHigh = lVar16
            lVar0  = lVar0 &+ lVar13
            lVar3  = lVar3 &+ lVar9
            lVar8  = lVar8 &+ lVar1
            if lVar3 != 0 {
                lVar16 = (lVar0 / lVar3) &<< 7
                lVar15 = (lVar8 / lVar3) &<< 7
            }
            if lVar15 < 0 { lVar15 = 0 } else if lVar15 > 0x3F80 { lVar15 = 0x3F80 }
            highStep = (lVar16 &- lLow)  >> 4   // note: Java uses lLow/lHigh after reset
            lowStep  = (lVar15 &- lHigh) >> 4

            remaining -= 1
        }

        // Tail (< 16 pixels)
        var k: Int32 = 0
        let tailCount = 15 & lVar14
        while k < tailCount {
            if (k & 3) == 0 {
                shift = lVal >> 23
                lLow  = (lVal & 6291456) &+ (16383 & lLow)
                lVal  = lVal &+ lValStep
            }
            dest[Int(lDH)] = logicalRightShift(src[Int((lLow >> 7) &+ (lHigh & 0x3F80))], shift)
            lDH &+= 1; lHigh &+= highStep; lLow &+= lowStep
            k += 1
        }
    }

    // MARK: - Overload C: Blend-with-background + normal (64×64) texture  (guard: byte var14 <= 97 triggers recursion — dead code omitted)
    //
    // Java signature:
    //   static void shadeScanline(int var0, int var1, int var2, int var3,
    //                             int var4, int var5, int var6,
    //                             int var7, int var8, int var9, int[] var10,
    //                             int var11, int var12, int[] var13, byte var14)
    //
    // The sentinel `if (var14 <= 97)` triggers a recursive call with out-of-range
    // values that is effectively dead code in practice.  We omit it.
    // Each pixel = (texture_pixel >>> shift) + ((dest[i] & 0xFEFEFE or similar) >> 1)
    // i.e. 50 % blend of existing pixel with texture.

    func shadeScanlineBlendNormal(
        var0: Int32, var1: Int32, var2: Int32, var3: Int32,
        var4: Int32, var5: Int32, var6: Int32,
        var7: Int32, var8: Int32, var9: Int32,
        texture: UnsafePointer<Int32>,
        var11: Int32, var12: Int32,
        dest:  UnsafeMutablePointer<Int32>,
        var14: Int8
    ) {
        guard var11 > 0 else { return }

        var lVar0  = var0
        var lVar1  = var1
        var lVar2  = var2
        var lVar3  = var3
        var lVar4  = var4
        let lVar5  = var5
        var lVar6  = var6
        var lVar7  = var7
        let lVar8  = var8
        let lVar9  = var9
        let lVar11 = var11
        let lVar12 = var12

        var lVar15: Int32 = 0
        var lVar16: Int32 = 0
        var lVar19: Int32 = 0

        if lVar7 != 0 {
            lVar3 = (lVar1 / lVar7) &<< 7
            lVar6 = (lVar2 / lVar7) &<< 7
        }

        lVar7 = lVar7 &+ lVar12
        if lVar6 < 0 { lVar6 = 0 } else if lVar6 > 0x3F80 { lVar6 = 0x3F80 }

        lVar1 = lVar1 &+ lVar5
        lVar2 = lVar2 &+ lVar8
        if lVar7 != 0 {
            lVar15 = (lVar2 / lVar7) &<< 7
            lVar16 = (lVar1 / lVar7) &<< 7
        }
        if lVar15 < 0 { lVar15 = 0 } else if lVar15 > 0x3F80 { lVar15 = 0x3F80 }

        var var17: Int32 = (lVar15 &- lVar6)  >> 4   // lowStep
        var var18: Int32 = (lVar16 &- lVar3)  >> 4   // highStep

        // Full 16-pixel blocks
        var blockCount = lVar11 >> 4
        while blockCount > 0 {
            lVar19 = lVar4 >> 23
            lVar6  = lVar6 &+ (lVar4 & 6291456)
            lVar4  = lVar4 &+ lVar9

            // 16 pixels unrolled
            dest[Int(lVar0)] = (bitwiseAnd(dest[Int(lVar0)] >> 1, 8355711)) &+
                logicalRightShift(texture[Int((lVar6 >> 7) &+ (lVar3 & 0x3F80))], lVar19)
            lVar0 &+= 1; lVar3 &+= var18; lVar6 &+= var17

            dest[Int(lVar0)] = (bitwiseAnd(dest[Int(lVar0)] >> 1, 8355711)) &+
                logicalRightShift(texture[Int((lVar6 >> 7) &+ (0x3F80 & lVar3))], lVar19)
            lVar0 &+= 1; lVar6 &+= var17; lVar3 &+= var18

            dest[Int(lVar0)] = logicalRightShift(texture[Int((0x3F80 & lVar3) &+ (lVar6 >> 7))], lVar19) &+
                (bitwiseAnd(16711422, dest[Int(lVar0)]) >> 1)
            lVar0 &+= 1; lVar3 &+= var18; lVar6 &+= var17

            dest[Int(lVar0)] = (bitwiseAnd(16711422, dest[Int(lVar0)]) >> 1) &+
                logicalRightShift(texture[Int((lVar3 & 0x3F80) &+ (lVar6 >> 7))], lVar19)
            lVar0 &+= 1; lVar3 &+= var18; lVar6 &+= var17

            lVar19 = lVar4 >> 23
            lVar6  = (lVar6 & 16383) &+ (lVar4 & 6291456)
            lVar4  = lVar4 &+ lVar9

            dest[Int(lVar0)] = (bitwiseAnd(dest[Int(lVar0)] >> 1, 8355711)) &+
                logicalRightShift(texture[Int((0x3F80 & lVar3) &+ (lVar6 >> 7))], lVar19)
            lVar0 &+= 1; lVar3 &+= var18; lVar6 &+= var17

            dest[Int(lVar0)] = logicalRightShift(texture[Int((lVar6 >> 7) &+ (lVar3 & 0x3F80))], lVar19) &+
                bitwiseAnd(dest[Int(lVar0)] >> 1, 8355711)
            lVar0 &+= 1; lVar3 &+= var18; lVar6 &+= var17

            dest[Int(lVar0)] = (bitwiseAnd(dest[Int(lVar0)], 16711423) >> 1) &+
                logicalRightShift(texture[Int((lVar3 & 0x3F80) &+ (lVar6 >> 7))], lVar19)
            lVar0 &+= 1; lVar6 &+= var17; lVar3 &+= var18

            dest[Int(lVar0)] = logicalRightShift(texture[Int((lVar6 >> 7) &+ (0x3F80 & lVar3))], lVar19) &+
                (bitwiseAnd(dest[Int(lVar0)], 16711423) >> 1)
            lVar0 &+= 1; lVar6 &+= var17; lVar3 &+= var18

            lVar6  = (16383 & lVar6) &+ (lVar4 & 6291456)
            lVar19 = lVar4 >> 23

            dest[Int(lVar0)] = (bitwiseAnd(16711423, dest[Int(lVar0)]) >> 1) &+
                logicalRightShift(texture[Int((lVar6 >> 7) &+ (lVar3 & 0x3F80))], lVar19)
            lVar4 &+= lVar9; lVar0 &+= 1; lVar3 &+= var18; lVar6 &+= var17

            dest[Int(lVar0)] = bitwiseAnd(dest[Int(lVar0)] >> 1, 8355711) &+
                logicalRightShift(texture[Int((lVar6 >> 7) &+ (0x3F80 & lVar3))], lVar19)
            lVar0 &+= 1; lVar6 &+= var17; lVar3 &+= var18

            dest[Int(lVar0)] = logicalRightShift(texture[Int((lVar3 & 0x3F80) &+ (lVar6 >> 7))], lVar19) &+
                bitwiseAnd(8355711, dest[Int(lVar0)] >> 1)
            lVar0 &+= 1; lVar6 &+= var17; lVar3 &+= var18

            dest[Int(lVar0)] = (bitwiseAnd(16711423, dest[Int(lVar0)]) >> 1) &+
                logicalRightShift(texture[Int((0x3F80 & lVar3) &+ (lVar6 >> 7))], lVar19)
            lVar0 &+= 1; lVar3 &+= var18; lVar6 &+= var17

            lVar6  = (lVar6 & 16383) &+ (lVar4 & 6291456)
            lVar19 = lVar4 >> 23

            dest[Int(lVar0)] = bitwiseAnd(8355711, dest[Int(lVar0)] >> 1) &+
                logicalRightShift(texture[Int((lVar6 >> 7) &+ (lVar3 & 0x3F80))], lVar19)
            lVar4 &+= lVar9; lVar0 &+= 1; lVar6 &+= var17; lVar3 &+= var18

            dest[Int(lVar0)] = bitwiseAnd(dest[Int(lVar0)] >> 1, 8355711) &+
                logicalRightShift(texture[Int((lVar6 >> 7) &+ (0x3F80 & lVar3))], lVar19)
            lVar0 &+= 1; lVar6 &+= var17; lVar3 &+= var18

            dest[Int(lVar0)] = logicalRightShift(texture[Int((lVar3 & 0x3F80) &+ (lVar6 >> 7))], lVar19) &+
                bitwiseAnd(dest[Int(lVar0)] >> 1, 8355711)
            lVar0 &+= 1; lVar6 &+= var17; lVar3 &+= var18

            dest[Int(lVar0)] = bitwiseAnd(dest[Int(lVar0)] >> 1, 8355711) &+
                logicalRightShift(texture[Int((lVar6 >> 7) &+ (0x3F80 & lVar3))], lVar19)
            lVar0 &+= 1

            // Recalculate UV for next 16-pixel span
            lVar7  = lVar7 &+ lVar12
            lVar1  = lVar1 &+ lVar5
            lVar2  = lVar2 &+ lVar8
            lVar3  = lVar16
            lVar6  = lVar15
            if lVar7 != 0 {
                lVar16 = (lVar1 / lVar7) &<< 7
                lVar15 = (lVar2 / lVar7) &<< 7
            }
            if lVar15 < 0 { lVar15 = 0 } else if lVar15 > 0x3F80 { lVar15 = 0x3F80 }
            var18 = (lVar16 &- lVar3) >> 4
            var17 = (lVar15 &- lVar6) >> 4

            blockCount -= 1
        }

        // Tail pixels
        var k: Int32 = 0
        let tailCount = lVar11 & 15
        while k < tailCount {
            if (k & 3) == 0 {
                lVar6  = (lVar4 & 6291456) &+ (lVar6 & 16383)
                lVar19 = lVar4 >> 23
                lVar4  = lVar4 &+ lVar9
            }
            dest[Int(lVar0)] = logicalRightShift(texture[Int((lVar3 & 0x3F80) &+ (lVar6 >> 7))], lVar19) &+
                (bitwiseAnd(dest[Int(lVar0)], 16711422) >> 1)
            lVar0 &+= 1; lVar6 &+= var17; lVar3 &+= var18
            k += 1
        }
    }

    // MARK: - Overload D: Blend-with-background + large (256×256) texture
    //
    // Java signature:
    //   static void shadeScanline(int[] var0, int var1, int var2, int var3,
    //                             int var4, int var5, int var6,
    //                             int var7, int var8, int var9, int[] var10,
    //                             boolean var11, int var12, int var13, int var14)
    //
    // Large texture: mask 0xFC0 for V, shift >>6 for U.  V row = 64 entries wide (6-bit).
    // var4 <<= 2 at start (the Bresenham accumulator step).
    // blend: (dest >> 1 & 0x7F7F7F) + (texel >>> shift)
    //        or (dest & 0xFEFEFF >> 1) + texel  — various mask constants used in Java.
    // dest and texture are passed as arrays in Java; here as unsafe pointers.

    func shadeScanlineBlendLarge(
        dest:    UnsafeMutablePointer<Int32>,
        var1:    Int32, var2: Int32, var3: Int32,
        var4:    Int32, var5: Int32, var6: Int32,
        var7:    Int32, var8: Int32, var9: Int32,
        texture: UnsafePointer<Int32>,
        var11:   Bool,
        var12:   Int32, var13: Int32, var14: Int32
    ) {
        guard var7 > 0 else { return }

        let lVar1  = var1
        let lVar2  = var2
        var lVar3  = var3
        let lVar4  = var4 &<< 2     // Java: var4 <<= 2
        var lVar5  = var5
        var lVar6  = var6
        let lVar7  = var7
        var lVar8  = var8
        let lVar12 = var12
        var lVar13 = var13
        var lVar14 = var14

        var lVar15: Int32 = 0
        var lVar16: Int32 = 0

        if lVar3 != 0 {
            lVar16 = (lVar13 / lVar3) &<< 6
            lVar15 = (lVar8  / lVar3) &<< 6
        }
        if lVar15 < 0 { lVar15 = 0 } else if lVar15 > 0xFC0 { lVar15 = 0xFC0 }

        var count = lVar7
        while count > 0 {
            lVar3  = lVar3 &+ lVar2
            lVar14 = lVar15           // save lVar15 into lVar14 (Java: var14 = var15)
            lVar8  = lVar8 &+ lVar12
            var lVar9_local = lVar16  // Java: var9 = var16
            lVar13 = lVar13 &+ lVar1
            if lVar3 != 0 {
                lVar15 = (lVar8  / lVar3) &<< 6
                lVar16 = (lVar13 / lVar3) &<< 6
            }
            if lVar15 < 0 { lVar15 = 0 } else if lVar15 > 0xFC0 { lVar15 = 0xFC0 }

            let var18: Int32 = (lVar16 &- lVar9_local) >> 4   // highStep
            let var17: Int32 = (lVar15 &- lVar14)      >> 4   // lowStep
            var var20:  Int32 = lVar5 >> 20
            lVar14 = lVar14 &+ (lVar5 & 786432)
            lVar5  = lVar5  &+ lVar4

            if count >= 16 {
                // Full 16-pixel unrolled block
                dest[Int(lVar6)] = bitwiseAnd(dest[Int(lVar6)] >> 1, 0x7F7F7F) &+
                    logicalRightShift(texture[Int((0xFC0 & lVar9_local) &+ (lVar14 >> 6))], var20)
                lVar6 &+= 1; lVar14 &+= var17; lVar9_local &+= var18

                dest[Int(lVar6)] = (bitwiseAnd(dest[Int(lVar6)], 0xFEFEFF) >> 1) &+
                    logicalRightShift(texture[Int((0xFC0 & lVar9_local) &+ (lVar14 >> 6))], var20)
                lVar6 &+= 1; lVar9_local &+= var18; lVar14 &+= var17

                dest[Int(lVar6)] = (bitwiseAnd(0xFEFEFF, dest[Int(lVar6)]) >> 1) &+
                    logicalRightShift(texture[Int((lVar9_local & 0xFC0) &+ (lVar14 >> 6))], var20)
                lVar6 &+= 1; lVar9_local &+= var18; lVar14 &+= var17

                dest[Int(lVar6)] = (bitwiseAnd(dest[Int(lVar6)], 0xFEFEFF) >> 1) &+
                    logicalRightShift(texture[Int((lVar14 >> 6) &+ (0xFC0 & lVar9_local))], var20)
                lVar6 &+= 1; lVar14 &+= var17; lVar9_local &+= var18

                var20  = lVar5 >> 20
                lVar14 = (lVar5 & 786432) &+ (4095 & lVar14)

                dest[Int(lVar6)] = logicalRightShift(texture[Int((lVar9_local & 0xFC0) &+ (lVar14 >> 6))], var20) &+
                    (bitwiseAnd(dest[Int(lVar6)], 0xFEFEFE) >> 1)
                lVar5 &+= lVar4; lVar6 &+= 1; lVar14 &+= var17; lVar9_local &+= var18

                dest[Int(lVar6)] = logicalRightShift(texture[Int((lVar14 >> 6) &+ (0xFC0 & lVar9_local))], var20) &+
                    (bitwiseAnd(dest[Int(lVar6)], 0xFEFEFF) >> 1)
                lVar6 &+= 1; lVar14 &+= var17; lVar9_local &+= var18

                dest[Int(lVar6)] = logicalRightShift(texture[Int((0xFC0 & lVar9_local) &+ (lVar14 >> 6))], var20) &+
                    (bitwiseAnd(dest[Int(lVar6)], 0xFEFEFF) >> 1)
                lVar6 &+= 1; lVar9_local &+= var18; lVar14 &+= var17

                dest[Int(lVar6)] = logicalRightShift(texture[Int((0xFC0 & lVar9_local) &+ (lVar14 >> 6))], var20) &+
                    (bitwiseAnd(0xFEFEFF, dest[Int(lVar6)]) >> 1)
                lVar6 &+= 1; lVar14 &+= var17; lVar9_local &+= var18

                lVar14 = (786432 & lVar5) &+ (4095 & lVar14)
                var20  = lVar5 >> 20

                dest[Int(lVar6)] = logicalRightShift(texture[Int((0xFC0 & lVar9_local) &+ (lVar14 >> 6))], var20) &+
                    (bitwiseAnd(dest[Int(lVar6)], 0xFEFEFE) >> 1)
                lVar5 &+= lVar4; lVar6 &+= 1; lVar14 &+= var17; lVar9_local &+= var18

                dest[Int(lVar6)] = logicalRightShift(texture[Int((lVar9_local & 0xFC0) &+ (lVar14 >> 6))], var20) &+
                    bitwiseAnd(dest[Int(lVar6)] >> 1, 0x7F7F7F)
                lVar6 &+= 1; lVar9_local &+= var18; lVar14 &+= var17

                dest[Int(lVar6)] = logicalRightShift(texture[Int((0xFC0 & lVar9_local) &+ (lVar14 >> 6))], var20) &+
                    (bitwiseAnd(dest[Int(lVar6)], 0xFEFEFF) >> 1)
                lVar6 &+= 1; lVar14 &+= var17; lVar9_local &+= var18

                dest[Int(lVar6)] = (bitwiseAnd(0xFEFEFE, dest[Int(lVar6)]) >> 1) &+
                    logicalRightShift(texture[Int((lVar14 >> 6) &+ (lVar9_local & 0xFC0))], var20)
                lVar6 &+= 1; lVar14 &+= var17; lVar9_local &+= var18

                lVar14 = (lVar5 & 786432) &+ (lVar14 & 4095)
                var20  = lVar5 >> 20

                dest[Int(lVar6)] = logicalRightShift(texture[Int((lVar9_local & 0xFC0) &+ (lVar14 >> 6))], var20) &+
                    (bitwiseAnd(0xFEFEFE, dest[Int(lVar6)]) >> 1)
                lVar5 &+= lVar4; lVar6 &+= 1; lVar14 &+= var17; lVar9_local &+= var18

                dest[Int(lVar6)] = (bitwiseAnd(dest[Int(lVar6)], 0xFEFEFF) >> 1) &+
                    logicalRightShift(texture[Int((lVar9_local & 0xFC0) &+ (lVar14 >> 6))], var20)
                lVar6 &+= 1; lVar14 &+= var17; lVar9_local &+= var18

                dest[Int(lVar6)] = logicalRightShift(texture[Int((0xFC0 & lVar9_local) &+ (lVar14 >> 6))], var20) &+
                    bitwiseAnd(dest[Int(lVar6)] >> 1, 0x7F7F7F)
                lVar6 &+= 1; lVar9_local &+= var18; lVar14 &+= var17

                dest[Int(lVar6)] = logicalRightShift(texture[Int((lVar14 >> 6) &+ (0xFC0 & lVar9_local))], var20) &+
                    (bitwiseAnd(dest[Int(lVar6)], 0xFEFEFF) >> 1)
                lVar6 &+= 1
            } else {
                // Tail loop
                var k: Int32 = 0
                while k < count {
                    dest[Int(lVar6)] = logicalRightShift(texture[Int((lVar14 >> 6) &+ (lVar9_local & 0xFC0))], var20) &+
                        (bitwiseAnd(0xFEFEFE, dest[Int(lVar6)]) >> 1)
                    lVar6 &+= 1; lVar9_local &+= var18; lVar14 &+= var17
                    if (k & 3) == 3 {
                        var20  = lVar5 >> 20
                        lVar14 = (lVar14 & 4095) &+ (786432 & lVar5)
                        lVar5  = lVar5 &+ lVar4
                    }
                    k += 1
                }
            }
            count -= 16
        }
    }

    // MARK: - Overload E: Opaque large (256×256) texture scanline
    //
    // Java signature:
    //   static void shadeScanline(int var0, int var1, int var2, int var3,
    //                             int var4, int[] src, int var6,
    //                             int var7, int var8, int var9, int[] dest,
    //                             int var11, int var12, int var13, int var14)
    //
    // Large texture: mask 4032 (= 0xFC0) for V, shift >>6 for U.
    // var0 <<= 2 at start.  Writes directly (no skip-0 test, no blend).

    func shadeScanlineOpaqueLarge(
        var0: Int32, var1: Int32, var2: Int32, var3: Int32,
        var4: Int32, src:  UnsafePointer<Int32>,
        var6: Int32, var7: Int32, var8: Int32, var9: Int32,
        dest: UnsafeMutablePointer<Int32>,
        var11: Int32, var12: Int32, var13: Int32, var14: Int32
    ) {
        guard var14 > 0 else { return }

        let lVar0  = var0 &<< 2
        let lVar2  = var2
        var lVar3  = var3
        let lVar4  = var4
        var lVar6  = var6
        var lVar8  = var8
        var lVar11 = var11
        var lVar12 = var12
        let lVar13 = var13

        var lVar15: Int32 = 0
        var lVar16: Int32 = 0

        if lVar12 != 0 {
            lVar16 = (lVar3 / lVar12) &<< 6
            lVar15 = (lVar8 / lVar12) &<< 6
        }
        if lVar15 < 0 { lVar15 = 0 } else if lVar15 > 4032 { lVar15 = 4032 }

        // Sentinel guard omitted (Java: if var1 != 1121159302 => recursive call)

        var count = var14
        while count > 0 {
            lVar12 = lVar12 &+ lVar13
            lVar8  = lVar8  &+ lVar4
            lVar3  = lVar3  &+ lVar2
            var lVar9_local = lVar15
            var lVar7_local = lVar16
            if lVar12 != 0 {
                lVar15 = (lVar8 / lVar12) &<< 6
                lVar16 = (lVar3 / lVar12) &<< 6
            }
            if lVar15 < 0 { lVar15 = 0 } else if lVar15 > 4032 { lVar15 = 4032 }

            let var18: Int32 = (lVar16 &- lVar7_local) >> 4
            let var17: Int32 = (lVar15 &- lVar9_local) >> 4
            var var20:  Int32 = lVar6 >> 20
            lVar9_local = lVar9_local &+ (786432 & lVar6)
            lVar6 = lVar6 &+ lVar0

            if count >= 16 {
                // Full 16-pixel unrolled block
                dest[Int(lVar11)] = logicalRightShift(src[Int((lVar7_local & 4032) &+ (lVar9_local >> 6))], var20)
                lVar11 &+= 1; lVar7_local &+= var18; lVar9_local &+= var17

                dest[Int(lVar11)] = logicalRightShift(src[Int((lVar9_local >> 6) &+ (lVar7_local & 4032))], var20)
                lVar11 &+= 1; lVar7_local &+= var18; lVar9_local &+= var17

                dest[Int(lVar11)] = logicalRightShift(src[Int((lVar9_local >> 6) &+ (4032 & lVar7_local))], var20)
                lVar11 &+= 1; lVar9_local &+= var17; lVar7_local &+= var18

                dest[Int(lVar11)] = logicalRightShift(src[Int((lVar9_local >> 6) &+ (4032 & lVar7_local))], var20)
                lVar11 &+= 1; lVar9_local &+= var17; lVar7_local &+= var18

                var20 = lVar6 >> 20
                lVar9_local = (lVar6 & 786432) &+ (4095 & lVar9_local)
                lVar6 &+= lVar0

                dest[Int(lVar11)] = logicalRightShift(src[Int((4032 & lVar7_local) &+ (lVar9_local >> 6))], var20)
                lVar11 &+= 1; lVar7_local &+= var18; lVar9_local &+= var17

                dest[Int(lVar11)] = logicalRightShift(src[Int((lVar7_local & 4032) &+ (lVar9_local >> 6))], var20)
                lVar11 &+= 1; lVar9_local &+= var17; lVar7_local &+= var18

                dest[Int(lVar11)] = logicalRightShift(src[Int((lVar7_local & 4032) &+ (lVar9_local >> 6))], var20)
                lVar11 &+= 1; lVar7_local &+= var18; lVar9_local &+= var17

                dest[Int(lVar11)] = logicalRightShift(src[Int((lVar9_local >> 6) &+ (4032 & lVar7_local))], var20)
                lVar11 &+= 1; lVar9_local &+= var17; lVar7_local &+= var18

                var20 = lVar6 >> 20
                lVar9_local = (786432 & lVar6) &+ (4095 & lVar9_local)
                lVar6 &+= lVar0

                dest[Int(lVar11)] = logicalRightShift(src[Int((lVar7_local & 4032) &+ (lVar9_local >> 6))], var20)
                lVar11 &+= 1; lVar7_local &+= var18; lVar9_local &+= var17

                dest[Int(lVar11)] = logicalRightShift(src[Int((lVar9_local >> 6) &+ (lVar7_local & 4032))], var20)
                lVar11 &+= 1; lVar7_local &+= var18; lVar9_local &+= var17

                dest[Int(lVar11)] = logicalRightShift(src[Int((lVar7_local & 4032) &+ (lVar9_local >> 6))], var20)
                lVar11 &+= 1; lVar7_local &+= var18; lVar9_local &+= var17

                dest[Int(lVar11)] = logicalRightShift(src[Int((4032 & lVar7_local) &+ (lVar9_local >> 6))], var20)
                lVar11 &+= 1; lVar7_local &+= var18; lVar9_local &+= var17

                var20 = lVar6 >> 20
                lVar9_local = (4095 & lVar9_local) &+ (lVar6 & 786432)
                lVar6 &+= lVar0

                dest[Int(lVar11)] = logicalRightShift(src[Int((lVar7_local & 4032) &+ (lVar9_local >> 6))], var20)
                lVar11 &+= 1; lVar7_local &+= var18; lVar9_local &+= var17

                dest[Int(lVar11)] = logicalRightShift(src[Int((lVar9_local >> 6) &+ (lVar7_local & 4032))], var20)
                lVar11 &+= 1; lVar7_local &+= var18; lVar9_local &+= var17

                dest[Int(lVar11)] = logicalRightShift(src[Int((lVar9_local >> 6) &+ (lVar7_local & 4032))], var20)
                lVar11 &+= 1; lVar9_local &+= var17; lVar7_local &+= var18

                dest[Int(lVar11)] = logicalRightShift(src[Int((4032 & lVar7_local) &+ (lVar9_local >> 6))], var20)
                lVar11 &+= 1
            } else {
                // Tail loop
                var k: Int32 = 0
                while k < count {
                    dest[Int(lVar11)] = logicalRightShift(src[Int((lVar9_local >> 6) &+ (4032 & lVar7_local))], var20)
                    lVar11 &+= 1; lVar7_local &+= var18; lVar9_local &+= var17
                    if (3 & k) == 3 {
                        var20 = lVar6 >> 20
                        lVar9_local = (lVar6 & 786432) &+ (4095 & lVar9_local)
                        lVar6 &+= lVar0
                    }
                    k += 1
                }
            }
            count -= 16
        }
    }

    // MARK: - Overload F: Transparent large (256×256) texture scanline  (guard: byte var3 == 25)
    //
    // Java signature:
    //   static void shadeScanline(int var0, int var1, int var2, byte var3,
    //                             int var4, int var5, int var6,
    //                             int var7, int[] var8, int[] var9,
    //                             int var10, int var11, int var12,
    //                             int var13, int var14, int var15)
    //
    // Large texture: mask 4032 (= 0xFC0) for V (var4), shift >>6 for U (var12).
    // Transparent: skip pixel write if texel == 0.
    // Only executes when var3 == 25.

    func shadeScanlineTransparentLarge(
        var0: Int32, var1: Int32, var2: Int32, var3: Int8,
        var4: Int32, var5: Int32, var6: Int32,
        var7: Int32,
        texture: UnsafePointer<Int32>,
        dest:    UnsafeMutablePointer<Int32>,
        var10: Int32, var11: Int32, var12: Int32,
        var13: Int32, var14: Int32, var15: Int32
    ) {
        guard var0 > 0 && var3 == 25 else { return }

        let lVar0  = var0
        var lVar1  = var1
        let lVar5  = var5
        let lVar6  = var6
        let lVar7  = var7 &<< 2
        var lVar10 = var10
        var lVar11 = var11
        let lVar13 = var13
        var lVar14 = var14
        var lVar15 = var15

        var lVar16: Int32 = 0
        var lVar17: Int32 = 0
        var lVar2:  Int32 = 0   // used as temp pixel value in Java (was var2)

        if lVar1 != 0 {
            lVar16 = (lVar11 / lVar1) &<< 6
            lVar17 = (lVar15 / lVar1) &<< 6
        }
        if lVar16 < 0 { lVar16 = 0 } else if lVar16 > 4032 { lVar16 = 4032 }

        var count = lVar0
        while count > 0 {
            var lVar4_span = lVar17
            var lVar12_span = lVar16

            lVar11 = lVar11 &+ lVar5
            lVar1  = lVar1  &+ lVar6
            lVar15 = lVar15 &+ lVar13
            if lVar1 != 0 {
                lVar17 = (lVar15 / lVar1) &<< 6
                lVar16 = (lVar11 / lVar1) &<< 6
            }
            if lVar16 < 0 { lVar16 = 0 } else if lVar16 > 4032 { lVar16 = 4032 }

            let var19: Int32 = (lVar17 &- lVar4_span)   >> 4
            let var18: Int32 = (lVar16 &- lVar12_span)  >> 4
            lVar12_span = lVar12_span &+ (786432 & lVar14)
            var var21:  Int32 = lVar14 >> 20
            lVar14 = lVar14 &+ lVar7

            if count >= 16 {
                // Full 16-pixel unrolled block
                lVar2 = logicalRightShift(texture[Int((lVar12_span >> 6) &+ (4032 & lVar4_span))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar10 &+= 1; lVar4_span &+= var19; lVar12_span &+= var18

                lVar2 = logicalRightShift(texture[Int((lVar12_span >> 6) &+ (lVar4_span & 4032))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar4_span &+= var19; lVar10 &+= 1; lVar12_span &+= var18

                lVar2 = logicalRightShift(texture[Int((lVar12_span >> 6) &+ (4032 & lVar4_span))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar4_span &+= var19; lVar10 &+= 1; lVar12_span &+= var18

                lVar2 = logicalRightShift(texture[Int((4032 & lVar4_span) &+ (lVar12_span >> 6))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar10 &+= 1; lVar12_span &+= var18; lVar4_span &+= var19

                var21 = lVar14 >> 20
                lVar12_span = (786432 & lVar14) &+ (4095 & lVar12_span)
                lVar14 &+= lVar7

                lVar2 = logicalRightShift(texture[Int((lVar12_span >> 6) &+ (4032 & lVar4_span))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar10 &+= 1; lVar12_span &+= var18; lVar4_span &+= var19

                lVar2 = logicalRightShift(texture[Int((lVar4_span & 4032) &+ (lVar12_span >> 6))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar10 &+= 1; lVar12_span &+= var18; lVar4_span &+= var19

                lVar2 = logicalRightShift(texture[Int((lVar4_span & 4032) &+ (lVar12_span >> 6))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar10 &+= 1; lVar12_span &+= var18; lVar4_span &+= var19

                lVar2 = logicalRightShift(texture[Int((lVar4_span & 4032) &+ (lVar12_span >> 6))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar4_span &+= var19; lVar10 &+= 1; lVar12_span &+= var18

                lVar12_span = (lVar12_span & 4095) &+ (lVar14 & 786432)
                var21 = lVar14 >> 20

                lVar2 = logicalRightShift(texture[Int((lVar12_span >> 6) &+ (lVar4_span & 4032))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar14 &+= lVar7; lVar10 &+= 1; lVar12_span &+= var18; lVar4_span &+= var19

                lVar2 = logicalRightShift(texture[Int((lVar12_span >> 6) &+ (4032 & lVar4_span))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar4_span &+= var19; lVar12_span &+= var18; lVar10 &+= 1

                lVar2 = logicalRightShift(texture[Int((lVar12_span >> 6) &+ (4032 & lVar4_span))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar12_span &+= var18; lVar4_span &+= var19; lVar10 &+= 1

                lVar2 = logicalRightShift(texture[Int((lVar4_span & 4032) &+ (lVar12_span >> 6))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar10 &+= 1; lVar12_span &+= var18; lVar4_span &+= var19

                var21 = lVar14 >> 20
                lVar12_span = (lVar14 & 786432) &+ (lVar12_span & 4095)
                lVar14 &+= lVar7

                lVar2 = logicalRightShift(texture[Int((lVar4_span & 4032) &+ (lVar12_span >> 6))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar4_span &+= var19; lVar12_span &+= var18; lVar10 &+= 1

                lVar2 = logicalRightShift(texture[Int((lVar4_span & 4032) &+ (lVar12_span >> 6))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar10 &+= 1; lVar12_span &+= var18; lVar4_span &+= var19

                lVar2 = logicalRightShift(texture[Int((lVar4_span & 4032) &+ (lVar12_span >> 6))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar4_span &+= var19; lVar10 &+= 1; lVar12_span &+= var18

                lVar2 = logicalRightShift(texture[Int((4032 & lVar4_span) &+ (lVar12_span >> 6))], var21)
                if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                lVar10 &+= 1
            } else {
                // Tail loop
                var k: Int32 = 0
                while k < count {
                    lVar2 = logicalRightShift(texture[Int((lVar12_span >> 6) &+ (4032 & lVar4_span))], var21)
                    if lVar2 != 0 { dest[Int(lVar10)] = lVar2 }
                    lVar10 &+= 1; lVar12_span &+= var18; lVar4_span &+= var19
                    if (3 & k) == 3 {
                        var21 = lVar14 >> 20
                        lVar12_span = (4095 & lVar12_span) &+ (lVar14 & 786432)
                        lVar14 &+= lVar7
                    }
                    k += 1
                }
            }
            count -= 16
        }
    }
}
