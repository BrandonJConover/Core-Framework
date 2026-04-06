import Foundation

// MARK: - Shader
//
// Port of orsc.graphics.three.Shader from the Java desktop client.
//
// Contains six overloaded `shadeScanline` variants that fill one horizontal
// scanline of a textured (or texture-blended) polygon into the pixel buffer.
// This is THE hottest code path in the entire software renderer — called
// thousands of times per frame — so every method is `@inlinable` and inner
// loops use unsafe buffer pointers to eliminate bounds checks.
//
// Two texture coordinate modes are supported:
//   - Normal 128x128: mask 0x3F80, shift >> 7, lighting shift >> 23,
//     lighting-U merge mask 6291456 (0x600000), U low mask 16383 (0x3FFF)
//   - Large  256x256: mask 0x0FC0, shift >> 6, lighting shift >> 20,
//     lighting-U merge mask 786432  (0x0C0000), U low mask 4095  (0x0FFF)
//
// Java `>>>` (unsigned right shift) is emulated by reinterpreting the Int32
// value as UInt32 before shifting, then converting back.

enum Shader {

    // MARK: - Helpers

    /// Java `>>>` equivalent: unsigned right shift on a 32-bit value stored as Int32.
    @inline(__always)
    private static func unsignedRightShift(_ value: Int32, _ shift: Int32) -> Int32 {
        return Int32(bitPattern: UInt32(bitPattern: value) >> UInt32(shift))
    }

    // =========================================================================
    // MARK: - Overload 1  (128x128, textured with transparency)
    // =========================================================================
    // Java signature:
    //   static void shadeScanline(int var0, int var1, int var2, int var3,
    //       int[] var4, int var5, int var6, int var7, int var8, int var9,
    //       int var10, int var11, int var12, int var13, int[] var14, int var15)
    //
    // Called from Scene.java ~line 1956:
    //   Shader.shadeScanline(var23, 10, 0, 0, this.pixelData,
    //       var25 + var8*var30, var38, var8*var28 + var19,
    //       var22 + var8*var29, var8 + var33, var26, var39,
    //       0, var20, this.resourceDatabase[var5], var37)
    //
    // Parameters (meaningful names):
    //   var0  = texU delta per span (dTexU_dZ)
    //   var1  = sentinel/unused (always 10)
    //   var2  = initial texU (unused; overwritten)
    //   var3  = initial texV (unused; overwritten)
    //   var4  = pixelData (destination buffer)
    //   var5  = Z (perspective divisor, initial)
    //   var6  = lighting value (initial, fixed-point)
    //   var7  = texU numerator
    //   var8  = texV numerator
    //   var9  = dest pixel offset
    //   var10 = Z step per span
    //   var11 = lighting step
    //   var12 = unused (always 0)
    //   var13 = texV delta per span (dTexV_dZ)
    //   var14 = texture data (source)
    //   var15 = pixel count (scanline width)

    @inlinable
    static func shadeScanline(
        _ var0: Int32,  _ var1: Int32,  _ var2_in: Int32, _ var3_in: Int32,
        _ var4: inout [Int32],
        _ var5_in: Int32, _ var6_in: Int32, _ var7_in: Int32,
        _ var8_in: Int32, _ var9_in: Int32, _ var10: Int32, _ var11_in: Int32,
        _ var12_in: Int32, _ var13: Int32,
        _ var14: [Int32],
        _ var15: Int32
    ) {
        guard var15 > 0 else { return }

        var var2 = var2_in
        var var3 = var3_in
        var var5 = var5_in
        var var6 = var6_in
        var var7 = var7_in
        var var8 = var8_in
        var var9 = var9_in
        var var11 = var11_in
        var var12 = var12_in

        var var16: Int32 = 0
        var var17: Int32 = 0
        var11 <<= 2

        if var5 != 0 {
            var17 = (var8 / var5) << 7
            var16 = (var7 / var5) << 7
        }

        if var16 < 0 {
            var16 = 0
        } else if var16 > 0x3F80 {
            var16 = 0x3F80
        }

        var4.withUnsafeMutableBufferPointer { destBuf in
            var14.withUnsafeBufferPointer { srcBuf in
                var var20 = var15
                while var20 > 0 {
                    var7 = var7 &+ var13
                    var3 = var17
                    var5 = var5 &+ var10
                    var2 = var16
                    var8 = var8 &+ var0

                    if var5 != 0 {
                        var16 = (var7 / var5) << 7
                        var17 = (var8 / var5) << 7
                    }

                    if var16 >= 0 {
                        if var16 > 0x3F80 { var16 = 0x3F80 }
                    } else {
                        var16 = 0
                    }

                    let var18 = (var16 &- var2) >> 4
                    let var19 = (var17 &- var3) >> 4
                    var var21 = var6 >> 23
                    var2 = var2 &+ (6291456 & var6)
                    var6 = var6 &+ var11

                    if var20 < 16 {
                        for var22 in 0..<var20 {
                            var12 = unsignedRightShift(
                                srcBuf[Int((var3 & 0x3F80) &+ (var2 >> 7))],
                                var21
                            )
                            if var12 != 0 {
                                destBuf[Int(var9)] = var12
                            }
                            var9 &+= 1
                            var2 = var2 &+ var18
                            var3 = var3 &+ var19
                            if (var22 & 3) == 3 {
                                var2 = (var6 & 6291456) &+ (16383 & var2)
                                var21 = var6 >> 23
                                var6 = var6 &+ var11
                            }
                        }
                    } else {
                        // Unrolled 16-pixel block
                        var12 = unsignedRightShift(srcBuf[Int((var3 & 0x3F80) &+ (var2 >> 7))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var2 = var2 &+ var18; var9 &+= 1; var3 = var3 &+ var19

                        var12 = unsignedRightShift(srcBuf[Int((var2 >> 7) &+ (0x3F80 & var3))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var9 &+= 1; var3 = var3 &+ var19; var2 = var2 &+ var18

                        var12 = unsignedRightShift(srcBuf[Int((var2 >> 7) &+ (0x3F80 & var3))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var9 &+= 1; var3 = var3 &+ var19; var2 = var2 &+ var18

                        var12 = unsignedRightShift(srcBuf[Int((var2 >> 7) &+ (var3 & 0x3F80))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var2 = var2 &+ var18; var3 = var3 &+ var19; var9 &+= 1

                        // Pixel 4: lighting update
                        var21 = var6 >> 23
                        var2 = (var6 & 6291456) &+ (16383 & var2)
                        var6 = var6 &+ var11

                        var12 = unsignedRightShift(srcBuf[Int((var3 & 0x3F80) &+ (var2 >> 7))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var2 = var2 &+ var18; var9 &+= 1; var3 = var3 &+ var19

                        var12 = unsignedRightShift(srcBuf[Int((0x3F80 & var3) &+ (var2 >> 7))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var9 &+= 1; var2 = var2 &+ var18; var3 = var3 &+ var19

                        var12 = unsignedRightShift(srcBuf[Int((var2 >> 7) &+ (0x3F80 & var3))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var2 = var2 &+ var18; var3 = var3 &+ var19; var9 &+= 1

                        var12 = unsignedRightShift(srcBuf[Int((var2 >> 7) &+ (var3 & 0x3F80))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var3 = var3 &+ var19; var9 &+= 1; var2 = var2 &+ var18

                        // Pixel 8: lighting update
                        var21 = var6 >> 23
                        var2 = (var2 & 16383) &+ (6291456 & var6)

                        var12 = unsignedRightShift(srcBuf[Int((var2 >> 7) &+ (var3 & 0x3F80))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var6 = var6 &+ var11; var9 &+= 1; var2 = var2 &+ var18; var3 = var3 &+ var19

                        var12 = unsignedRightShift(srcBuf[Int((var2 >> 7) &+ (var3 & 0x3F80))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var3 = var3 &+ var19; var9 &+= 1; var2 = var2 &+ var18

                        var12 = unsignedRightShift(srcBuf[Int((0x3F80 & var3) &+ (var2 >> 7))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var3 = var3 &+ var19; var2 = var2 &+ var18; var9 &+= 1

                        var12 = unsignedRightShift(srcBuf[Int((var2 >> 7) &+ (var3 & 0x3F80))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var2 = var2 &+ var18; var3 = var3 &+ var19; var9 &+= 1

                        // Pixel 12: lighting update
                        var2 = (var2 & 16383) &+ (var6 & 6291456)
                        var21 = var6 >> 23

                        var12 = unsignedRightShift(srcBuf[Int((var3 & 0x3F80) &+ (var2 >> 7))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var6 = var6 &+ var11; var3 = var3 &+ var19; var9 &+= 1; var2 = var2 &+ var18

                        var12 = unsignedRightShift(srcBuf[Int((var2 >> 7) &+ (var3 & 0x3F80))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var9 &+= 1; var2 = var2 &+ var18; var3 = var3 &+ var19

                        var12 = unsignedRightShift(srcBuf[Int((var2 >> 7) &+ (var3 & 0x3F80))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var3 = var3 &+ var19; var2 = var2 &+ var18; var9 &+= 1

                        var12 = unsignedRightShift(srcBuf[Int((0x3F80 & var3) &+ (var2 >> 7))], var21)
                        if var12 != 0 { destBuf[Int(var9)] = var12 }
                        var9 &+= 1
                    }

                    var20 &-= 16
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Overload 2  (128x128, opaque textured — no transparency check)
    // =========================================================================
    // Java signature:
    //   static void shadeScanline(int var0, int var1, byte var2, int var3,
    //       int val, int valStep, int[] src, int dH, int var8, int var9,
    //       int high, int low, int[] dest, int var13, int var14)
    //
    // Called from Scene.java ~line 1990 (walls):
    //   Shader.shadeScanline(var22 + var29*var8, var20, (byte)50,
    //       var25 + var8*var30, var38, var39<<2, this.resourceDatabase[var5],
    //       var8 + var33, var8*var28 + var19, var26, 0, 0,
    //       this.pixelData, var23, var37)
    //
    // The byte var2 is always 50 at the valid call site (guard check).

    @inlinable
    static func shadeScanline(
        _ var0_in: Int32, _ var1: Int32, _ var2: Int8, _ var3_in: Int32,
        _ val_in: Int32, _ valStep: Int32,
        _ src: [Int32],
        _ dH_in: Int32, _ var8_in: Int32, _ var9: Int32,
        _ high_in: Int32, _ low_in: Int32,
        _ dest: inout [Int32],
        _ var13: Int32, _ var14: Int32
    ) {
        guard var14 > 0 else { return }
        guard var2 == 50 else { return }

        var var0 = var0_in
        var var3 = var3_in
        var val = val_in
        var dH = dH_in
        var var8 = var8_in
        var high = high_in
        var low = low_in

        var var15: Int32 = 0
        var var16: Int32 = 0

        if var3 != 0 {
            low = (var8 / var3) << 7
            high = (var0 / var3) << 7
        }

        var shift: Int32 = 0
        if low < 0 {
            low = 0
        } else if low > 0x3F80 {
            low = 0x3F80
        }

        // Advance perspective one span ahead
        var3 = var3 &+ var9
        var0 = var0 &+ var13
        var8 = var8 &+ var1

        if var3 != 0 {
            var16 = (var0 / var3) << 7
            var15 = (var8 / var3) << 7
        }

        if var15 >= 0 {
            if var15 > 0x3F80 { var15 = 0x3F80 }
        } else {
            var15 = 0
        }

        var lowStep  = (var15 &- low) >> 4
        var highStep = (var16 &- high) >> 4

        dest.withUnsafeMutableBufferPointer { destBuf in
            src.withUnsafeBufferPointer { srcBuf in

                // Full 16-pixel spans
                var var20 = var14 >> 4
                while var20 > 0 {
                    low = low &+ (val & 6291456)
                    shift = val >> 23
                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((0x3F80 & high) &+ (low >> 7))], shift)
                    dH &+= 1; val = val &+ valStep; low = low &+ lowStep; high = high &+ highStep

                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((low >> 7) &+ (0x3F80 & high))], shift)
                    dH &+= 1; high = high &+ highStep; low = low &+ lowStep

                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((low >> 7) &+ (0x3F80 & high))], shift)
                    dH &+= 1; high = high &+ highStep; low = low &+ lowStep

                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((low >> 7) &+ (0x3F80 & high))], shift)
                    dH &+= 1; high = high &+ highStep; low = low &+ lowStep

                    // Lighting update
                    low = (6291456 & val) &+ (16383 & low)
                    shift = val >> 23
                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((low >> 7) &+ (high & 0x3F80))], shift)
                    dH &+= 1; val = val &+ valStep; low = low &+ lowStep; high = high &+ highStep

                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((0x3F80 & high) &+ (low >> 7))], shift)
                    dH &+= 1; low = low &+ lowStep; high = high &+ highStep

                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((low >> 7) &+ (0x3F80 & high))], shift)
                    dH &+= 1; high = high &+ highStep; low = low &+ lowStep

                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((0x3F80 & high) &+ (low >> 7))], shift)
                    dH &+= 1; high = high &+ highStep; low = low &+ lowStep

                    // Lighting update
                    low = (val & 6291456) &+ (16383 & low)
                    shift = val >> 23
                    val = val &+ valStep
                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((high & 0x3F80) &+ (low >> 7))], shift)
                    dH &+= 1; low = low &+ lowStep; high = high &+ highStep

                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((0x3F80 & high) &+ (low >> 7))], shift)
                    dH &+= 1; low = low &+ lowStep; high = high &+ highStep

                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((low >> 7) &+ (0x3F80 & high))], shift)
                    dH &+= 1; high = high &+ highStep; low = low &+ lowStep

                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((low >> 7) &+ (high & 0x3F80))], shift)
                    dH &+= 1; low = low &+ lowStep; high = high &+ highStep

                    // Lighting update
                    low = (16383 & low) &+ (6291456 & val)
                    shift = val >> 23
                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((low >> 7) &+ (0x3F80 & high))], shift)
                    dH &+= 1; val = val &+ valStep; low = low &+ lowStep; high = high &+ highStep

                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((low >> 7) &+ (high & 0x3F80))], shift)
                    dH &+= 1; low = low &+ lowStep; high = high &+ highStep

                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((low >> 7) &+ (0x3F80 & high))], shift)
                    dH &+= 1; high = high &+ highStep; low = low &+ lowStep

                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((low >> 7) &+ (0x3F80 & high))], shift)

                    // Advance to next 16-pixel span
                    low = var15
                    high = var16
                    var0 = var0 &+ var13
                    var3 = var3 &+ var9
                    var8 = var8 &+ var1

                    if var3 != 0 {
                        var16 = (var0 / var3) << 7
                        var15 = (var8 / var3) << 7
                    }

                    if var15 >= 0 {
                        if var15 > 0x3F80 { var15 = 0x3F80 }
                    } else {
                        var15 = 0
                    }

                    highStep = (var16 &- high) >> 4
                    lowStep  = (var15 &- low) >> 4

                    var20 &-= 1
                }

                // Remainder pixels
                for var20 in 0..<(15 & var14) {
                    if (var20 & 3) == 0 {
                        shift = val >> 23
                        low = (val & 6291456) &+ (16383 & low)
                        val = val &+ valStep
                    }
                    destBuf[Int(dH)] = unsignedRightShift(srcBuf[Int((low >> 7) &+ (high & 0x3F80))], shift)
                    dH &+= 1
                    high = high &+ highStep
                    low  = low  &+ lowStep
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Overload 3  (128x128, textured + 50% blend with existing pixel)
    // =========================================================================
    // Java signature:
    //   static void shadeScanline(int var0, int var1, int var2, int var3,
    //       int var4, int var5, int var6, int var7, int var8, int var9,
    //       int[] var10, int var11, int var12, int[] var13, byte var14)
    //
    // Called from Scene.java ~line 2021:
    //   Shader.shadeScanline(var33 + var8, var22 + var8*var29, var19 + var8*var28,
    //       0, var38, var23, 0, var25 + var8*var30, var20, var39<<2,
    //       this.resourceDatabase[var5], var37, var26, this.pixelData, (byte)119)
    //
    // This variant reads the destination pixel, halves it, and adds
    // the texture sample on top — producing a 50% transparency blend.

    @inlinable
    static func shadeScanline(
        _ var0_in: Int32, _ var1_in: Int32, _ var2_in: Int32, _ var3_in: Int32,
        _ var4_in: Int32, _ var5_in: Int32, _ var6_in: Int32,
        _ var7_in: Int32, _ var8_in: Int32, _ var9_in: Int32,
        _ var10: [Int32],
        _ var11: Int32, _ var12_in: Int32,
        _ var13: inout [Int32],
        _ var14: Int8
    ) {
        guard var11 > 0 else { return }

        var var0 = var0_in
        var var1 = var1_in
        var var2 = var2_in
        var var3 = var3_in
        var var4 = var4_in
        var var5 = var5_in
        var var6 = var6_in
        var var7 = var7_in
        var var8 = var8_in
        var var9 = var9_in
        var var12 = var12_in

        var var15: Int32 = 0
        var var16: Int32 = 0
        var var19: Int32 = 0

        if var7 != 0 {
            var3 = (var1 / var7) << 7
            var6 = (var2 / var7) << 7
        }

        var7 = var7 &+ var12

        if var6 >= 0 {
            if var6 > 0x3F80 { var6 = 0x3F80 }
        } else {
            var6 = 0
        }

        var1 = var1 &+ var5
        var2 = var2 &+ var8

        if var7 != 0 {
            var15 = (var2 / var7) << 7
            var16 = (var1 / var7) << 7
        }

        if var15 >= 0 {
            if var15 > 0x3F80 { var15 = 0x3F80 }
        } else {
            var15 = 0
        }

        var var17 = (var15 &- var6) >> 4
        var var18 = (var16 &- var3) >> 4

        var13.withUnsafeMutableBufferPointer { destBuf in
            var10.withUnsafeBufferPointer { srcBuf in

                var var20 = var11 >> 4
                while var20 > 0 {
                    var19 = var4 >> 23
                    var6 = var6 &+ (var4 & 6291456)
                    var4 = var4 &+ var9

                    // 16 unrolled pixels with 50% blend: dest = (dest >> 1 & 0x7F7F7F) + (tex >>> shift)
                    destBuf[Int(var0)] = ((destBuf[Int(var0)] >> 1) & 8355711)
                        &+ unsignedRightShift(srcBuf[Int((var6 >> 7) &+ (var3 & 0x3F80))], var19)
                    var0 &+= 1; var3 = var3 &+ var18; var6 = var6 &+ var17

                    destBuf[Int(var0)] = ((destBuf[Int(var0)] >> 1) & 8355711)
                        &+ unsignedRightShift(srcBuf[Int((var6 >> 7) &+ (0x3F80 & var3))], var19)
                    var0 &+= 1; var6 = var6 &+ var17; var3 = var3 &+ var18

                    destBuf[Int(var0)] = unsignedRightShift(srcBuf[Int((0x3F80 & var3) &+ (var6 >> 7))], var19)
                        &+ (((destBuf[Int(var0)]) & 16711422) >> 1)
                    var0 &+= 1; var3 = var3 &+ var18; var6 = var6 &+ var17

                    destBuf[Int(var0)] = (((destBuf[Int(var0)]) & 16711422) >> 1)
                        &+ unsignedRightShift(srcBuf[Int((var3 & 0x3F80) &+ (var6 >> 7))], var19)
                    var0 &+= 1; var3 = var3 &+ var18; var6 = var6 &+ var17

                    // Lighting update
                    var19 = var4 >> 23
                    var6 = (var6 & 16383) &+ (var4 & 6291456)
                    var4 = var4 &+ var9

                    destBuf[Int(var0)] = ((destBuf[Int(var0)] >> 1) & 8355711)
                        &+ unsignedRightShift(srcBuf[Int((0x3F80 & var3) &+ (var6 >> 7))], var19)
                    var0 &+= 1; var3 = var3 &+ var18; var6 = var6 &+ var17

                    destBuf[Int(var0)] = unsignedRightShift(srcBuf[Int((var6 >> 7) &+ (var3 & 0x3F80))], var19)
                        &+ ((destBuf[Int(var0)] >> 1) & 8355711)
                    var0 &+= 1; var3 = var3 &+ var18; var6 = var6 &+ var17

                    destBuf[Int(var0)] = (((destBuf[Int(var0)]) & 16711423) >> 1)
                        &+ unsignedRightShift(srcBuf[Int((var3 & 0x3F80) &+ (var6 >> 7))], var19)
                    var0 &+= 1; var6 = var6 &+ var17; var3 = var3 &+ var18

                    destBuf[Int(var0)] = unsignedRightShift(srcBuf[Int((var6 >> 7) &+ (0x3F80 & var3))], var19)
                        &+ (((destBuf[Int(var0)]) & 16711423) >> 1)
                    var0 &+= 1; var6 = var6 &+ var17; var3 = var3 &+ var18

                    // Lighting update
                    var6 = (16383 & var6) &+ (var4 & 6291456)
                    var19 = var4 >> 23

                    destBuf[Int(var0)] = ((16711423 & (destBuf[Int(var0)])) >> 1)
                        &+ unsignedRightShift(srcBuf[Int((var6 >> 7) &+ (var3 & 0x3F80))], var19)
                    var0 &+= 1; var4 = var4 &+ var9; var3 = var3 &+ var18; var6 = var6 &+ var17

                    destBuf[Int(var0)] = ((destBuf[Int(var0)] >> 1) & 8355711)
                        &+ unsignedRightShift(srcBuf[Int((var6 >> 7) &+ (0x3F80 & var3))], var19)
                    var0 &+= 1; var6 = var6 &+ var17; var3 = var3 &+ var18

                    destBuf[Int(var0)] = unsignedRightShift(srcBuf[Int((var3 & 0x3F80) &+ (var6 >> 7))], var19)
                        &+ ((8355711 & (destBuf[Int(var0)] >> 1)))
                    var0 &+= 1; var6 = var6 &+ var17; var3 = var3 &+ var18

                    destBuf[Int(var0)] = ((16711423 & (destBuf[Int(var0)])) >> 1)
                        &+ unsignedRightShift(srcBuf[Int((0x3F80 & var3) &+ (var6 >> 7))], var19)
                    var0 &+= 1; var3 = var3 &+ var18; var6 = var6 &+ var17

                    // Lighting update
                    var6 = (var6 & 16383) &+ (var4 & 6291456)
                    var19 = var4 >> 23

                    destBuf[Int(var0)] = ((8355711 & (destBuf[Int(var0)] >> 1)))
                        &+ unsignedRightShift(srcBuf[Int((var6 >> 7) &+ (var3 & 0x3F80))], var19)
                    var0 &+= 1; var4 = var4 &+ var9; var6 = var6 &+ var17; var3 = var3 &+ var18

                    destBuf[Int(var0)] = ((destBuf[Int(var0)] >> 1) & 8355711)
                        &+ unsignedRightShift(srcBuf[Int((var6 >> 7) &+ (0x3F80 & var3))], var19)
                    var0 &+= 1; var6 = var6 &+ var17; var3 = var3 &+ var18

                    destBuf[Int(var0)] = unsignedRightShift(srcBuf[Int((var3 & 0x3F80) &+ (var6 >> 7))], var19)
                        &+ ((destBuf[Int(var0)] >> 1) & 8355711)
                    var0 &+= 1; var6 = var6 &+ var17; var3 = var3 &+ var18

                    destBuf[Int(var0)] = ((destBuf[Int(var0)] >> 1) & 8355711)
                        &+ unsignedRightShift(srcBuf[Int((var6 >> 7) &+ (0x3F80 & var3))], var19)

                    // Advance to next span
                    var7 = var7 &+ var12
                    var1 = var1 &+ var5
                    var2 = var2 &+ var8
                    var3 = var16
                    var6 = var15

                    if var7 != 0 {
                        var16 = (var1 / var7) << 7
                        var15 = (var2 / var7) << 7
                    }

                    if var15 >= 0 {
                        if var15 > 0x3F80 { var15 = 0x3F80 }
                    } else {
                        var15 = 0
                    }

                    var18 = (var16 &- var3) >> 4
                    var17 = (var15 &- var6) >> 4

                    var20 &-= 1
                }

                // Remainder pixels
                for var20 in 0..<(var11 & 15) {
                    if (var20 & 3) == 0 {
                        var6 = (var4 & 6291456) &+ (var6 & 16383)
                        var19 = var4 >> 23
                        var4 = var4 &+ var9
                    }
                    destBuf[Int(var0)] = unsignedRightShift(srcBuf[Int((var3 & 0x3F80) &+ (var6 >> 7))], var19)
                        &+ (((destBuf[Int(var0)]) & 16711422) >> 1)
                    var0 &+= 1
                    var6 = var6 &+ var17
                    var3 = var3 &+ var18
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Overload 4  (256x256, textured + 50% blend with existing pixel)
    // =========================================================================
    // Java signature:
    //   static void shadeScanline(int[] var0, int var1, int var2, int var3,
    //       int var4, int var5, int var6, int var7, int var8, int var9,
    //       int[] var10, boolean var11, int var12, int var13, int var14)
    //
    // Called from Scene.java ~line 2097:
    //   Shader.shadeScanline(this.pixelData, var23, var26, var8*var30 + var25,
    //       var39, var38, var8 + var33, var37, var28*var8 + var19,
    //       0, this.resourceDatabase[var5], false, var20,
    //       var8*var29 + var22, 0)

    @inlinable
    static func shadeScanline(
        _ var0: inout [Int32], _ var1: Int32, _ var2_in: Int32, _ var3_in: Int32,
        _ var4_in: Int32, _ var5_in: Int32, _ var6_in: Int32,
        _ var7: Int32, _ var8_in: Int32, _ var9_in: Int32,
        _ var10: [Int32],
        _ var11: Bool, _ var12: Int32, _ var13_in: Int32, _ var14_in: Int32
    ) {
        guard var7 > 0 else { return }

        var var2 = var2_in
        var var3 = var3_in
        var var4 = var4_in
        var var5 = var5_in
        var var6 = var6_in
        var var8 = var8_in
        var var9 = var9_in
        var var13 = var13_in
        var var14 = var14_in

        var var15: Int32 = 0
        var var16: Int32 = 0

        if var3 != 0 {
            var16 = (var13 / var3) << 6
            var15 = (var8 / var3) << 6
        }

        var4 <<= 2

        if var15 < 0 {
            var15 = 0
        } else if var15 > 0xFC0 {
            var15 = 0xFC0
        }

        var0.withUnsafeMutableBufferPointer { destBuf in
            var10.withUnsafeBufferPointer { srcBuf in
                var var19 = var7
                while var19 > 0 {
                    var3 = var3 &+ var2
                    var14 = var15
                    var8 = var8 &+ var12
                    var9 = var16
                    var13 = var13 &+ var1

                    if var3 != 0 {
                        var15 = (var8 / var3) << 6
                        var16 = (var13 / var3) << 6
                    }

                    if var15 >= 0 {
                        if var15 > 0xFC0 { var15 = 0xFC0 }
                    } else {
                        var15 = 0
                    }

                    let var18 = (var16 &- var9) >> 4
                    let var17 = (var15 &- var14) >> 4
                    var var20 = var5 >> 20
                    var14 = var14 &+ (var5 & 786432)
                    var5 = var5 &+ var4

                    if var19 >= 16 {
                        destBuf[Int(var6)] = ((destBuf[Int(var6)] >> 1) & 0x7f7f7f)
                            &+ unsignedRightShift(srcBuf[Int((0xFC0 & var9) &+ (var14 >> 6))], var20)
                        var6 &+= 1; var14 = var14 &+ var17; var9 = var9 &+ var18

                        destBuf[Int(var6)] = (((destBuf[Int(var6)]) & 0xfefeff) >> 1)
                            &+ unsignedRightShift(srcBuf[Int((0xFC0 & var9) &+ (var14 >> 6))], var20)
                        var6 &+= 1; var9 = var9 &+ var18; var14 = var14 &+ var17

                        destBuf[Int(var6)] = (((0xfefeff & destBuf[Int(var6)])) >> 1)
                            &+ unsignedRightShift(srcBuf[Int((var9 & 0xFC0) &+ (var14 >> 6))], var20)
                        var6 &+= 1; var9 = var9 &+ var18; var14 = var14 &+ var17

                        destBuf[Int(var6)] = (((destBuf[Int(var6)]) & 0xfefeff) >> 1)
                            &+ unsignedRightShift(srcBuf[Int((var14 >> 6) &+ (0xFC0 & var9))], var20)
                        var6 &+= 1; var14 = var14 &+ var17; var9 = var9 &+ var18

                        // Lighting update
                        var14 = (var5 & 786432) &+ (4095 & var14)
                        var20 = var5 >> 20

                        destBuf[Int(var6)] = unsignedRightShift(srcBuf[Int((var9 & 0xFC0) &+ (var14 >> 6))], var20)
                            &+ (((destBuf[Int(var6)]) & 0xFEFEFE) >> 1)
                        var6 &+= 1; var5 = var5 &+ var4; var14 = var14 &+ var17; var9 = var9 &+ var18

                        destBuf[Int(var6)] = unsignedRightShift(srcBuf[Int((var14 >> 6) &+ (0xFC0 & var9))], var20)
                            &+ (((destBuf[Int(var6)]) & 0xfefeff) >> 1)
                        var6 &+= 1; var14 = var14 &+ var17; var9 = var9 &+ var18

                        destBuf[Int(var6)] = unsignedRightShift(srcBuf[Int((0xFC0 & var9) &+ (var14 >> 6))], var20)
                            &+ (((destBuf[Int(var6)]) & 0xfefeff) >> 1)
                        var6 &+= 1; var9 = var9 &+ var18; var14 = var14 &+ var17

                        destBuf[Int(var6)] = unsignedRightShift(srcBuf[Int((0xFC0 & var9) &+ (var14 >> 6))], var20)
                            &+ (((0xfefeff & destBuf[Int(var6)])) >> 1)
                        var6 &+= 1; var14 = var14 &+ var17; var9 = var9 &+ var18

                        // Lighting update
                        var14 = (786432 & var5) &+ (4095 & var14)
                        var20 = var5 >> 20

                        destBuf[Int(var6)] = unsignedRightShift(srcBuf[Int((0xFC0 & var9) &+ (var14 >> 6))], var20)
                            &+ (((destBuf[Int(var6)]) & 0xFEFEFE) >> 1)
                        var6 &+= 1; var5 = var5 &+ var4; var14 = var14 &+ var17; var9 = var9 &+ var18

                        destBuf[Int(var6)] = unsignedRightShift(srcBuf[Int((var9 & 0xFC0) &+ (var14 >> 6))], var20)
                            &+ ((destBuf[Int(var6)] >> 1) & 0x7f7f7f)
                        var6 &+= 1; var9 = var9 &+ var18; var14 = var14 &+ var17

                        destBuf[Int(var6)] = unsignedRightShift(srcBuf[Int((0xFC0 & var9) &+ (var14 >> 6))], var20)
                            &+ (((destBuf[Int(var6)]) & 0xfefeff) >> 1)
                        var6 &+= 1; var14 = var14 &+ var17; var9 = var9 &+ var18

                        destBuf[Int(var6)] = (((0xFEFEFE & destBuf[Int(var6)])) >> 1)
                            &+ unsignedRightShift(srcBuf[Int((var14 >> 6) &+ (var9 & 0xFC0))], var20)
                        var6 &+= 1; var14 = var14 &+ var17; var9 = var9 &+ var18

                        // Lighting update
                        var14 = (var5 & 786432) &+ (var14 & 4095)
                        var20 = var5 >> 20

                        destBuf[Int(var6)] = unsignedRightShift(srcBuf[Int((var9 & 0xFC0) &+ (var14 >> 6))], var20)
                            &+ (((0xFEFEFE & destBuf[Int(var6)])) >> 1)
                        var6 &+= 1; var5 = var5 &+ var4; var14 = var14 &+ var17; var9 = var9 &+ var18

                        destBuf[Int(var6)] = (((destBuf[Int(var6)]) & 0xfefeff) >> 1)
                            &+ unsignedRightShift(srcBuf[Int((var9 & 0xFC0) &+ (var14 >> 6))], var20)
                        var6 &+= 1; var14 = var14 &+ var17; var9 = var9 &+ var18

                        destBuf[Int(var6)] = unsignedRightShift(srcBuf[Int((0xFC0 & var9) &+ (var14 >> 6))], var20)
                            &+ ((destBuf[Int(var6)] >> 1) & 0x7f7f7f)
                        var6 &+= 1; var9 = var9 &+ var18; var14 = var14 &+ var17

                        destBuf[Int(var6)] = unsignedRightShift(srcBuf[Int((var14 >> 6) &+ (0xFC0 & var9))], var20)
                            &+ (((destBuf[Int(var6)]) & 0xfefeff) >> 1)
                        var6 &+= 1
                    } else {
                        for var21 in 0..<var19 {
                            destBuf[Int(var6)] = unsignedRightShift(srcBuf[Int((var14 >> 6) &+ (var9 & 0xFC0))], var20)
                                &+ (((0xFEFEFE & destBuf[Int(var6)])) >> 1)
                            var6 &+= 1
                            var9  = var9  &+ var18
                            var14 = var14 &+ var17
                            if (var21 & 3) == 3 {
                                var20 = var5 >> 20
                                var14 = (var14 & 4095) &+ (786432 & var5)
                                var5 = var5 &+ var4
                            }
                        }
                    }

                    var19 &-= 16
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Overload 5  (256x256, opaque textured — no transparency check)
    // =========================================================================
    // Java signature:
    //   static void shadeScanline(int var0, int var1, int var2, int var3,
    //       int var4, int[] src, int var6, int var7, int var8, int var9,
    //       int[] dest, int var11, int var12, int var13, int var14)
    //
    // Called from Scene.java ~line 2126 (floors):
    //   Shader.shadeScanline(var39, 1121159302, var23, var8*var29 + var22,
    //       var20, this.resourceDatabase[var5], var38, 0,
    //       var19 + var28*var8, 0, this.pixelData,
    //       var33 + var8, var25 + var8*var30, var26, var37)
    //
    // Note: var1 == 1121159302 is a sentinel/unused value.

    @inlinable
    static func shadeScanline(
        _ var0_in: Int32, _ var1_sentinel: Int32, _ var2_in: Int32, _ var3_in: Int32,
        _ var4: Int32,
        _ src: [Int32],
        _ var6_in: Int32, _ var7_in: Int32, _ var8_in: Int32, _ var9_in: Int32,
        _ dest: inout [Int32],
        _ var11_in: Int32, _ var12_in: Int32, _ var13: Int32, _ var14: Int32
    ) {
        guard var14 > 0 else { return }

        var var0 = var0_in
        var var2 = var2_in
        var var3 = var3_in
        var var6 = var6_in
        var var7 = var7_in
        var var8 = var8_in
        var var9 = var9_in
        var var11 = var11_in
        var var12 = var12_in

        var var15: Int32 = 0
        var var16: Int32 = 0

        if var12 != 0 {
            var16 = (var3 / var12) << 6
            var15 = (var8 / var12) << 6
        }

        var0 <<= 2

        if var15 >= 0 {
            if var15 > 4032 { var15 = 4032 }
        } else {
            var15 = 0
        }

        dest.withUnsafeMutableBufferPointer { destBuf in
            src.withUnsafeBufferPointer { srcBuf in
                var var19 = var14
                while var19 > 0 {
                    var12 = var12 &+ var13
                    var8  = var8  &+ var4
                    var3  = var3  &+ var2
                    var9  = var15
                    var7  = var16

                    if var12 != 0 {
                        var15 = (var8 / var12) << 6
                        var16 = (var3 / var12) << 6
                    }

                    if var15 < 0 {
                        var15 = 0
                    } else if var15 > 4032 {
                        var15 = 4032
                    }

                    let var18 = (var16 &- var7) >> 4
                    let var17 = (var15 &- var9) >> 4
                    var var20 = var6 >> 20
                    var9 = var9 &+ (786432 & var6)
                    var6 = var6 &+ var0

                    if var19 >= 16 {
                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var7 & 4032) &+ (var9 >> 6))], var20)
                        var11 &+= 1; var7 = var7 &+ var18; var9 = var9 &+ var17

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var9 >> 6) &+ (var7 & 4032))], var20)
                        var11 &+= 1; var7 = var7 &+ var18; var9 = var9 &+ var17

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var9 >> 6) &+ (4032 & var7))], var20)
                        var11 &+= 1; var9 = var9 &+ var17; var7 = var7 &+ var18

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var9 >> 6) &+ (4032 & var7))], var20)
                        var11 &+= 1; var9 = var9 &+ var17; var7 = var7 &+ var18

                        // Lighting update
                        var20 = var6 >> 20
                        var9 = (var6 & 786432) &+ (4095 & var9)
                        var6 = var6 &+ var0

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((4032 & var7) &+ (var9 >> 6))], var20)
                        var11 &+= 1; var7 = var7 &+ var18; var9 = var9 &+ var17

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var7 & 4032) &+ (var9 >> 6))], var20)
                        var11 &+= 1; var9 = var9 &+ var17; var7 = var7 &+ var18

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var7 & 4032) &+ (var9 >> 6))], var20)
                        var11 &+= 1; var7 = var7 &+ var18; var9 = var9 &+ var17

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var9 >> 6) &+ (4032 & var7))], var20)
                        var11 &+= 1; var9 = var9 &+ var17; var7 = var7 &+ var18

                        // Lighting update
                        var20 = var6 >> 20
                        var9 = (786432 & var6) &+ (4095 & var9)
                        var6 = var6 &+ var0

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var7 & 4032) &+ (var9 >> 6))], var20)
                        var11 &+= 1; var7 = var7 &+ var18; var9 = var9 &+ var17

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var9 >> 6) &+ (var7 & 4032))], var20)
                        var11 &+= 1; var7 = var7 &+ var18; var9 = var9 &+ var17

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var7 & 4032) &+ (var9 >> 6))], var20)
                        var11 &+= 1; var7 = var7 &+ var18; var9 = var9 &+ var17

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((4032 & var7) &+ (var9 >> 6))], var20)
                        var11 &+= 1; var7 = var7 &+ var18; var9 = var9 &+ var17

                        // Lighting update
                        var20 = var6 >> 20
                        var9 = (4095 & var9) &+ (var6 & 786432)
                        var6 = var6 &+ var0

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var7 & 4032) &+ (var9 >> 6))], var20)
                        var11 &+= 1; var7 = var7 &+ var18; var9 = var9 &+ var17

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var9 >> 6) &+ (var7 & 4032))], var20)
                        var11 &+= 1; var7 = var7 &+ var18; var9 = var9 &+ var17

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var9 >> 6) &+ (var7 & 4032))], var20)
                        var11 &+= 1; var9 = var9 &+ var17; var7 = var7 &+ var18

                        destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((4032 & var7) &+ (var9 >> 6))], var20)
                        var11 &+= 1
                    } else {
                        for var21 in 0..<var19 {
                            destBuf[Int(var11)] = unsignedRightShift(srcBuf[Int((var9 >> 6) &+ (4032 & var7))], var20)
                            var11 &+= 1
                            var7  = var7  &+ var18
                            var9  = var9  &+ var17
                            if (3 & var21) == 3 {
                                var20 = var6 >> 20
                                var9 = (var6 & 786432) &+ (4095 & var9)
                                var6 = var6 &+ var0
                            }
                        }
                    }

                    var19 &-= 16
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Overload 6  (256x256, textured with transparency)
    // =========================================================================
    // Java signature:
    //   static void shadeScanline(int var0, int var1, int var2, byte var3,
    //       int var4, int var5, int var6, int var7, int[] var8, int[] var9,
    //       int var10, int var11, int var12, int var13, int var14, int var15)
    //
    // Called from Scene.java ~line 2165 (fountain spray, wooden fences):
    //   Shader.shadeScanline(var37, var30*var8 + var25, 0, (byte)25,
    //       0, var20, var26, var39, this.resourceDatabase[var5],
    //       this.pixelData, var8 + var33, var8*var28 + var19,
    //       0, var23, var38, var29*var8 + var22)
    //
    // The byte var3 is always 25 at the valid call site (guard check).

    @inlinable
    static func shadeScanline(
        _ var0_in: Int32, _ var1_in: Int32, _ var2_in: Int32, _ var3: Int8,
        _ var4_in: Int32, _ var5: Int32, _ var6_in: Int32,
        _ var7_in: Int32,
        _ var8: [Int32],
        _ var9: inout [Int32],
        _ var10_in: Int32, _ var11_in: Int32, _ var12_in: Int32,
        _ var13_in: Int32, _ var14_in: Int32, _ var15_in: Int32
    ) {
        var var0 = var0_in
        guard var0 > 0 else { return }
        guard var3 == 25 else { return }

        var var1 = var1_in
        var var2 = var2_in
        var var4 = var4_in
        var var6 = var6_in
        var var7 = var7_in
        var var10 = var10_in
        var var11 = var11_in
        var var12 = var12_in
        var var13 = var13_in
        var var14 = var14_in
        var var15 = var15_in

        var var16: Int32 = 0
        var var17: Int32 = 0

        if var1 != 0 {
            var16 = (var11 / var1) << 6
            var17 = (var15 / var1) << 6
        }

        var7 <<= 2

        if var16 >= 0 {
            if var16 > 4032 { var16 = 4032 }
        } else {
            var16 = 0
        }

        var9.withUnsafeMutableBufferPointer { destBuf in
            var8.withUnsafeBufferPointer { srcBuf in
                var var20 = var0
                while var20 > 0 {
                    var4  = var17
                    var12 = var16
                    var11 = var11 &+ var5
                    var1  = var1  &+ var6
                    var15 = var15 &+ var13

                    if var1 != 0 {
                        var17 = (var15 / var1) << 6
                        var16 = (var11 / var1) << 6
                    }

                    if var16 < 0 {
                        var16 = 0
                    } else if var16 > 4032 {
                        var16 = 4032
                    }

                    let var19 = (var17 &- var4) >> 4
                    let var18 = (var16 &- var12) >> 4
                    var12 = var12 &+ (786432 & var14)
                    var var21 = var14 >> 20
                    var14 = var14 &+ var7

                    if var20 >= 16 {
                        // Unrolled 16 pixels with transparency check
                        var2 = unsignedRightShift(srcBuf[Int((var12 >> 6) &+ (4032 & var4))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var10 &+= 1; var4 = var4 &+ var19; var12 = var12 &+ var18

                        var2 = unsignedRightShift(srcBuf[Int((var12 >> 6) &+ (var4 & 4032))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var4 = var4 &+ var19; var10 &+= 1; var12 = var12 &+ var18

                        var2 = unsignedRightShift(srcBuf[Int((var12 >> 6) &+ (4032 & var4))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var4 = var4 &+ var19; var10 &+= 1; var12 = var12 &+ var18

                        var2 = unsignedRightShift(srcBuf[Int((4032 & var4) &+ (var12 >> 6))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var10 &+= 1; var12 = var12 &+ var18; var4 = var4 &+ var19

                        // Lighting update
                        var21 = var14 >> 20
                        var12 = (786432 & var14) &+ (4095 & var12)
                        var14 = var14 &+ var7

                        var2 = unsignedRightShift(srcBuf[Int((var12 >> 6) &+ (4032 & var4))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var10 &+= 1; var12 = var12 &+ var18; var4 = var4 &+ var19

                        var2 = unsignedRightShift(srcBuf[Int((var4 & 4032) &+ (var12 >> 6))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var10 &+= 1; var12 = var12 &+ var18; var4 = var4 &+ var19

                        var2 = unsignedRightShift(srcBuf[Int((var4 & 4032) &+ (var12 >> 6))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var10 &+= 1; var12 = var12 &+ var18; var4 = var4 &+ var19

                        var2 = unsignedRightShift(srcBuf[Int((var4 & 4032) &+ (var12 >> 6))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var4 = var4 &+ var19; var10 &+= 1; var12 = var12 &+ var18

                        // Lighting update
                        var12 = (var12 & 4095) &+ (var14 & 786432)
                        var21 = var14 >> 20

                        var2 = unsignedRightShift(srcBuf[Int((var12 >> 6) &+ (var4 & 4032))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var14 = var14 &+ var7; var10 &+= 1; var12 = var12 &+ var18; var4 = var4 &+ var19

                        var2 = unsignedRightShift(srcBuf[Int((var12 >> 6) &+ (4032 & var4))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var4 = var4 &+ var19; var12 = var12 &+ var18; var10 &+= 1

                        var2 = unsignedRightShift(srcBuf[Int((var12 >> 6) &+ (4032 & var4))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var12 = var12 &+ var18; var4 = var4 &+ var19; var10 &+= 1

                        var2 = unsignedRightShift(srcBuf[Int((var4 & 4032) &+ (var12 >> 6))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var10 &+= 1; var12 = var12 &+ var18; var4 = var4 &+ var19

                        // Lighting update
                        var21 = var14 >> 20
                        var12 = (var14 & 786432) &+ (var12 & 4095)
                        var14 = var14 &+ var7

                        var2 = unsignedRightShift(srcBuf[Int((var4 & 4032) &+ (var12 >> 6))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var4 = var4 &+ var19; var12 = var12 &+ var18; var10 &+= 1

                        var2 = unsignedRightShift(srcBuf[Int((var4 & 4032) &+ (var12 >> 6))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var10 &+= 1; var12 = var12 &+ var18; var4 = var4 &+ var19

                        var2 = unsignedRightShift(srcBuf[Int((var4 & 4032) &+ (var12 >> 6))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var4 = var4 &+ var19; var10 &+= 1; var12 = var12 &+ var18

                        var2 = unsignedRightShift(srcBuf[Int((4032 & var4) &+ (var12 >> 6))], var21)
                        if var2 != 0 { destBuf[Int(var10)] = var2 }
                        var10 &+= 1
                    } else {
                        for var22 in 0..<var20 {
                            var2 = unsignedRightShift(srcBuf[Int((var12 >> 6) &+ (4032 & var4))], var21)
                            if var2 != 0 { destBuf[Int(var10)] = var2 }
                            var10 &+= 1
                            var12 = var12 &+ var18
                            var4  = var4  &+ var19
                            if (3 & var22) == 3 {
                                var21 = var14 >> 20
                                var12 = (4095 & var12) &+ (var14 & 786432)
                                var14 = var14 &+ var7
                            }
                        }
                    }

                    var20 &-= 16
                }
            }
        }
    }
}
