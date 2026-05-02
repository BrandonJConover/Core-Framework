/**
 * TextureMaterial530 — TypeScript port of the rev-530 procedural texture
 * stack: rt4-client Texture.java + all 40 TextureOp* subclasses + the
 * TextureOp29 sub-op family + the per-texture metadata table at idx26.
 *
 * Two record kinds are exposed:
 *
 *   TextureMaterial530         a single texture's procedural-op graph,
 *                              loaded from idx9 group=textureId file=0.
 *
 *   TextureMaterialList530     the `aBoolean*Array*` bitfield of which
 *                              texture ids exist plus their per-id
 *                              flags (alpha, opaque, blend, average-rgb,
 *                              effect type, transparency etc.). Loaded
 *                              from idx26 group=0 file=0.
 *
 * Sources of truth:
 *   reference/rt4-client/client/src/main/java/rt4/Texture.java        (432 lines)
 *   reference/rt4-client/client/src/main/java/rt4/TextureOp.java
 *   reference/rt4-client/client/src/main/java/rt4/TextureOp{4,5,11..38}.java
 *   reference/rt4-client/client/src/main/java/rt4/TextureOp{Binary,Clamp,
 *     ColorFill,ColorGradient,Combine,Curve,Flip,HorizontalGradient,
 *     Interpolate,Invert,Monochrome,MonochromeFill,Noise,Range,Sprite,
 *     Texture,Tile,TiledSprite,VerticalGradient}.java
 *   reference/rt4-client/client/src/main/java/rt4/TextureOp29SubOp{1,2,3,4}.java
 *   reference/rt4-client/client/src/main/java/rt4/Js5GlTextureProvider.java
 *
 * Cache layout (per Js5GlTextureProvider + GlTexture):
 *   TextureMaterial   idx9  group=textureId  file=0
 *   List metadata     idx26 group=0          file=0
 *   (init at client.java:1583 — Js5GlTextureProvider(js5Archive9, js5Archive26, ...).
 *
 * This port covers the byte-format decode path only. The CPU pixel-evaluation
 * path inside each TextureOp's getColorOutput() is a renderer-tier port
 * left for the future Metal / WebGL fragment-side material implementation.
 * Decoded ops carry every field needed for that future work.
 */

import { Js5Cache } from "../../Js5Cache";

class TexReader {
    public buf: Uint8Array;
    public pos: number;
    constructor(buf: Uint8Array, pos: number = 0) { this.buf = buf; this.pos = pos; }

    g1(): number { return this.buf[this.pos++] & 0xFF; }
    g1b(): number { const b = this.buf[this.pos++]; return (b << 24) >> 24; }
    g2(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        return (a << 8) | b;
    }
    g2b(): number {
        const v = this.g2();
        return v >= 0x8000 ? v - 0x10000 : v;
    }
    g3(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        const c = this.buf[this.pos++] & 0xFF;
        return ((a << 16) | (b << 8) | c) >>> 0;
    }
    g4(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        const c = this.buf[this.pos++] & 0xFF;
        const d = this.buf[this.pos++] & 0xFF;
        return ((a << 24) | (b << 16) | (c << 8) | d) | 0;
    }
}

// ── TextureOp29 sub-ops (parametric noise field stencils) ──

export interface TexOp29SubOp1 {
    kind: 1;
    a: number; b: number; c: number; d: number; rgb24: number; flag: number;
}
export interface TexOp29SubOp2 {
    kind: 2;
    a: number; b: number; c: number; d: number; rgb1: number; rgb2: number; flag: number;
}
export interface TexOp29SubOp3 {
    kind: 3;
    a: number; b: number; c: number; d: number;
    e: number; f: number; g: number; h: number;
    rgb24: number; flag: number;
}
export interface TexOp29SubOp4 {
    kind: 4;
    a: number; b: number; c: number; d: number; rgb1: number; rgb2: number; flag: number;
}
export type TexOp29SubOp = TexOp29SubOp1 | TexOp29SubOp2 | TexOp29SubOp3 | TexOp29SubOp4;

function decode29SubOp(r: TexReader): TexOp29SubOp | null {
    const kind = r.g1();
    if (kind === 0) {
        return {
            kind: 1,
            a: r.g2b(), b: r.g2b(), c: r.g2b(), d: r.g2b(),
            rgb24: r.g3(), flag: r.g1(),
        };
    } else if (kind === 1) {
        return {
            kind: 3,
            a: r.g2b(), b: r.g2b(), c: r.g2b(), d: r.g2b(),
            e: r.g2b(), f: r.g2b(), g: r.g2b(), h: r.g2b(),
            rgb24: r.g3(), flag: r.g1(),
        };
    } else if (kind === 2) {
        return {
            kind: 4,
            a: r.g2b(), b: r.g2b(), c: r.g2b(), d: r.g2b(),
            rgb1: r.g3(), rgb2: r.g3(), flag: r.g1(),
        };
    } else if (kind === 3) {
        return {
            kind: 2,
            a: r.g2b(), b: r.g2b(), c: r.g2b(), d: r.g2b(),
            rgb1: r.g3(), rgb2: r.g3(), flag: r.g1(),
        };
    }
    return null;
}

// ── TextureOp ────────────────────────────────────────────────────

/**
 * One node in a procedural-texture op graph. `kind` is the rt4 type id (the
 * second byte of each op record, also the index into Texture.create()'s
 * switch). Each op carries:
 *   - inputs[]  — indices into Texture.aClass3_Sub1Array22 of source ops.
 *   - cache     — anInt5840 (image-cache stride; 255 means "use texture height").
 *   - monochrome — true when the op produces a single-channel output.
 *   - fields    — strongly-typed per-kind fields (see the discriminated union below).
 */
export interface TextureOpBase {
    kind: number;
    /** Input op indices (rt4 aClass3_Sub1Array42 references). */
    inputs: number[];
    /** rt4 anInt5840 — used by method4632 to size the per-op image cache. */
    cache: number;
    /** Whether this op outputs a monochrome stream (vs RGB triple). */
    monochrome: boolean;
    /** Whatever per-kind data the decode-loop captured. Always non-null. */
    fields: TextureOpFields;
}

export type TextureOpFields =
    | { kind: 0;  v: number; }                                            // MonochromeFill (anInt3894)
    | { kind: 1;  rgb24: number; }                                        // ColorFill (g3 → packed into r/g/b)
    | { kind: 2;  }                                                        // HorizontalGradient
    | { kind: 3;  }                                                        // VerticalGradient
    | { kind: 4;  i0: number; i1: number; i2: number; i3: number;          // TextureOp4
                  i4: number; i5: number; i6: number; i7: number; }
    | { kind: 5;  i0: number; i1: number; }                                // TextureOp5
    | { kind: 6;  min: number; max: number; }                              // Clamp (+ monochrome flag handled at base level)
    | { kind: 7;  func: number; }                                          // Combine
    | { kind: 8;  i0: number; markers: number[][]; }                       // Curve  (anInt5852 + per-marker (g2,g2))
    | { kind: 9;  flipX: boolean; flipY: boolean; }                        // Flip
    | { kind: 10; preset: number; samples: number[][] | null; }            // ColorGradient
    | { kind: 11; i0: number; i1: number; i2: number; }                    // TextureOp11
    | { kind: 12; i0: number; i1: number; i3: number; }                    // TextureOp12
    | { kind: 13; }                                                        // Noise
    | { kind: 14; v: number; }                                             // TextureOp14
    | { kind: 15; i0: number; i1: number; i2: number; i3: number;          // TextureOp15
                  i4: number; i5: number; i6: number; }
    | { kind: 16; i0: number; i1: number; i2: number; }                    // TextureOp16
    | { kind: 17; angle: number; ratioU: number; ratioV: number; }         // TextureOp17 (g2b + (g1b<<12)/100)
    | { kind: 18; spriteId: number; }                                      // TiledSprite (inherits from Sprite)
    | { kind: 19; threshold: number; }                                     // TextureOp19 (anInt3292 = g2 << 4)
    | { kind: 20; horizTiles: number; vertTiles: number; }                 // Tile
    | { kind: 21; }                                                        // Interpolate
    | { kind: 22; }                                                        // Invert
    | { kind: 23; }                                                        // TextureOp23
    | { kind: 24; }                                                        // Monochrome
    | { kind: 25; i0: number; i1: number; i2: number; i3: number;          // TextureOp25
                  rgbR: number; rgbG: number; rgbB: number; }
    | { kind: 26; min: number; max: number; }                              // Binary
    | { kind: 27; i0: number; i1: number; i2: number; }                    // TextureOp27
    | { kind: 28; i0: number; i1: number; i2: number; i3: number;          // TextureOp28
                  i4: number; i5: number; i6: number; i7: number; i8: number; }
    | { kind: 29; subOps: TexOp29SubOp[]; }                                 // TextureOp29
    | { kind: 30; min: number; max: number; }                              // Range
    | { kind: 31; i0: number; i1: number; i2: number; i3: number; }        // TextureOp31
    | { kind: 32; i0: number; i1: number; i2: number; }                    // TextureOp32
    | { kind: 33; i0: number; flag: boolean; }                              // TextureOp33
    | { kind: 34; flag: boolean; count: number; offset: number;            // TextureOp34
                  values: number[] | null; pair0: number; pair1: number;
                  v4: number; v5: number; v6: number; }
    | { kind: 35; v: number; }                                             // TextureOp35
    | { kind: 36; textureId: number; }                                     // TextureOpTexture
    | { kind: 37; i0: number; i1: number; i2: number; i3: number;          // TextureOp37
                  i4: number; i5: number; i6: number; }
    | { kind: 38; i0: number; i1: number; i2: number; i3: number; i4: number; } // TextureOp38
    | { kind: 39; spriteId: number; }                                      // Sprite
    | { kind: -1; };                                                       // unknown / unsupported

/** Allocate an empty fields record for `kind`, mirroring rt4 constructor defaults. */
function makeFields(kind: number): TextureOpFields {
    switch (kind) {
        case 0:  return { kind: 0,  v: 0 };
        case 1:  return { kind: 1,  rgb24: 0 };
        case 2:  return { kind: 2 };
        case 3:  return { kind: 3 };
        case 4:  return { kind: 4,  i0: 0, i1: 0, i2: 0, i3: 0, i4: 0, i5: 0, i6: 0, i7: 0 };
        case 5:  return { kind: 5,  i0: 0, i1: 0 };
        case 6:  return { kind: 6,  min: 0, max: 0 };
        case 7:  return { kind: 7,  func: 0 };
        case 8:  return { kind: 8,  i0: 0, markers: [] };
        case 9:  return { kind: 9,  flipX: false, flipY: false };
        case 10: return { kind: 10, preset: 0, samples: null };
        case 11: return { kind: 11, i0: 0, i1: 0, i2: 0 };
        case 12: return { kind: 12, i0: 0, i1: 0, i3: 0 };
        case 13: return { kind: 13 };
        case 14: return { kind: 14, v: 0 };
        case 15: return { kind: 15, i0: 0, i1: 0, i2: 0, i3: 0, i4: 0, i5: 0, i6: 0 };
        case 16: return { kind: 16, i0: 0, i1: 0, i2: 0 };
        case 17: return { kind: 17, angle: 0, ratioU: 0, ratioV: 0 };
        case 18: return { kind: 18, spriteId: -1 };
        case 19: return { kind: 19, threshold: 0 };
        case 20: return { kind: 20, horizTiles: 0, vertTiles: 0 };
        case 21: return { kind: 21 };
        case 22: return { kind: 22 };
        case 23: return { kind: 23 };
        case 24: return { kind: 24 };
        case 25: return { kind: 25, i0: 0, i1: 0, i2: 0, i3: 0, rgbR: 0, rgbG: 0, rgbB: 0 };
        case 26: return { kind: 26, min: 0, max: 0 };
        case 27: return { kind: 27, i0: 0, i1: 0, i2: 0 };
        case 28: return { kind: 28, i0: 0, i1: 0, i2: 0, i3: 0, i4: 0, i5: 0, i6: 0, i7: 0, i8: 0 };
        case 29: return { kind: 29, subOps: [] };
        case 30: return { kind: 30, min: 0, max: 0 };
        case 31: return { kind: 31, i0: 0, i1: 0, i2: 0, i3: 0 };
        case 32: return { kind: 32, i0: 0, i1: 0, i2: 0 };
        case 33: return { kind: 33, i0: 0, flag: false };
        case 34: return { kind: 34, flag: false, count: 0, offset: 0, values: null,
                          pair0: 0, pair1: 0, v4: 0, v5: 0, v6: 0 };
        case 35: return { kind: 35, v: 0 };
        case 36: return { kind: 36, textureId: -1 };
        case 37: return { kind: 37, i0: 0, i1: 0, i2: 0, i3: 0, i4: 0, i5: 0, i6: 0 };
        case 38: return { kind: 38, i0: 0, i1: 0, i2: 0, i3: 0, i4: 0 };
        case 39: return { kind: 39, spriteId: -1 };
        default: return { kind: -1 };
    }
}

/** rt4 constructor's `super(arity, monochrome)` initial values, by op kind. */
function defaultMonochrome(kind: number): boolean {
    switch (kind) {
        case 0: case 2: case 3: case 13: case 24:                            // Mono*, gradients, noise
            return true;
        case 21: case 22: case 32: case 38:                                  // interp/invert/op32/op38 default mono
            return true;
        case 19:                                                             // TextureOp19 starts color, may flip to mono via opcode 1
            return false;
        default:
            return false;
    }
}

/**
 * Apply a single `decode(opcode, buffer)` call, mirroring per-class rt4
 * decoders. `op` is the in-progress op being filled in.
 */
function applyOpDecode(op: TextureOpBase, opcode: number, r: TexReader): void {
    const f: any = op.fields; // narrowed below by kind switch via direct field writes
    switch (op.kind) {
        case 0: { // MonochromeFill
            if (opcode === 0) f.v = (r.g1() << 12) / 255 | 0;
            return;
        }
        case 1: { // ColorFill
            if (opcode === 0) f.rgb24 = r.g3();
            return;
        }
        case 4: {
            if (opcode === 0) f.i0 = r.g1();
            else if (opcode === 1) f.i1 = r.g1();
            else if (opcode === 2) f.i2 = r.g2();
            else if (opcode === 3) f.i3 = r.g2();
            else if (opcode === 4) f.i4 = r.g2();
            else if (opcode === 5) f.i5 = r.g2();
            else if (opcode === 6) f.i6 = r.g2();
            else if (opcode === 7) f.i7 = r.g2();
            return;
        }
        case 5: {
            if (opcode === 0) f.i0 = r.g1();
            else if (opcode === 1) f.i1 = r.g1();
            else if (opcode === 2) op.monochrome = r.g1() === 1;
            return;
        }
        case 6: { // Clamp
            if (opcode === 0) f.min = r.g2();
            else if (opcode === 1) f.max = r.g2();
            else if (opcode === 2) op.monochrome = r.g1() === 1;
            return;
        }
        case 7: { // Combine
            if (opcode === 0) f.func = r.g1();
            else if (opcode === 1) op.monochrome = r.g1() === 1;
            return;
        }
        case 8: { // Curve
            if (opcode !== 0) return;
            f.i0 = r.g1();
            const n = r.g1();
            const m: number[][] = [];
            for (let i = 0; i < n; i++) m.push([r.g2(), r.g2()]);
            f.markers = m;
            return;
        }
        case 9: { // Flip
            if (opcode === 0) f.flipX = r.g1() === 1;
            else if (opcode === 1) f.flipY = r.g1() === 1;
            else if (opcode === 2) op.monochrome = r.g1() === 1;
            return;
        }
        case 10: { // ColorGradient
            if (opcode !== 0) return;
            const preset = r.g1();
            f.preset = preset;
            if (preset !== 0) return;
            const n = r.g1();
            const samples: number[][] = [];
            for (let i = 0; i < n; i++) {
                const t = r.g2();
                const a = r.g1() << 4;
                const b = r.g1() << 4;
                const c = r.g1() << 4;
                samples.push([t, a, b, c]);
            }
            f.samples = samples;
            return;
        }
        case 11: {
            if (opcode === 0) f.i0 = r.g2();
            else if (opcode === 1) f.i1 = r.g2();
            else if (opcode === 2) f.i2 = r.g2();
            return;
        }
        case 12: {
            if (opcode === 0) f.i0 = r.g1();
            else if (opcode === 1) f.i1 = r.g1();
            else if (opcode === 3) f.i3 = r.g1();
            return;
        }
        case 14: {
            if (opcode === 0) f.v = r.g2();
            return;
        }
        case 15: {
            if (opcode === 0) { f.i0 = r.g1(); f.i6 = f.i0; }   // anInt2645 = anInt2646 = g1
            else if (opcode === 1) f.i1 = r.g1();
            else if (opcode === 2) f.i2 = r.g2();
            else if (opcode === 3) f.i3 = r.g1();
            else if (opcode === 4) f.i4 = r.g1();
            else if (opcode === 5) f.i5 = r.g1();
            else if (opcode === 6) f.i6 = r.g1();
            return;
        }
        case 16: {
            if (opcode === 0) f.i0 = r.g1();
            else if (opcode === 1) f.i1 = r.g1();
            else if (opcode === 2) f.i2 = r.g2();
            return;
        }
        case 17: {
            if (opcode === 0) f.angle = r.g2b();
            else if (opcode === 1) f.ratioU = (r.g1b() << 12) / 100 | 0;
            else if (opcode === 2) f.ratioV = (r.g1b() << 12) / 100 | 0;
            return;
        }
        case 18: case 39: { // TiledSprite (inherits Sprite) and Sprite
            if (opcode === 0) f.spriteId = r.g2();
            return;
        }
        case 19: {
            if (opcode === 0) f.threshold = r.g2() << 4;
            else if (opcode === 1) op.monochrome = r.g1() === 1;
            return;
        }
        case 20: {
            if (opcode === 0) f.horizTiles = r.g1();
            else if (opcode === 1) f.vertTiles = r.g1();
            return;
        }
        case 21: case 22: {
            if (opcode === 0) op.monochrome = r.g1() === 1;
            return;
        }
        case 23: {
            if (opcode === 0) op.monochrome = r.g1() === 1;
            return;
        }
        case 25: {
            if (opcode === 0) f.i0 = r.g2();
            else if (opcode === 1) f.i1 = r.g2();
            else if (opcode === 2) f.i2 = r.g2();
            else if (opcode === 3) f.i3 = r.g2();
            else if (opcode === 4) {
                const v = r.g3();
                f.rgbB = (v >> 12) & 0x0;          // rt4 mask is 0x0 — always 0; preserved verbatim.
                f.rgbG = (v >> 4) & 0xFF0;
                f.rgbR = ((v & 0xFF0000) << 4) | 0;
            }
            return;
        }
        case 26: { // Binary
            if (opcode === 0) f.min = r.g2();
            else if (opcode === 1) f.max = r.g2();
            return;
        }
        case 27: {
            if (opcode === 0) f.i0 = r.g1();
            else if (opcode === 1) f.i1 = r.g2();
            else if (opcode === 2) f.i2 = r.g1();
            return;
        }
        case 28: {
            if (opcode === 0) f.i0 = r.g1();
            else if (opcode === 1) f.i1 = r.g2();
            else if (opcode === 2) f.i2 = r.g2();
            else if (opcode === 3) f.i3 = r.g2();
            else if (opcode === 4) f.i4 = r.g2();
            else if (opcode === 5) f.i5 = r.g2();
            else if (opcode === 6) f.i6 = r.g1();
            else if (opcode === 7) f.i7 = r.g2();
            else if (opcode === 8) f.i8 = r.g2();
            return;
        }
        case 29: {
            if (opcode === 0) {
                const n = r.g1();
                const list: TexOp29SubOp[] = [];
                for (let i = 0; i < n; i++) {
                    const sub = decode29SubOp(r);
                    if (sub) list.push(sub);
                }
                f.subOps = list;
            } else if (opcode === 1) {
                op.monochrome = r.g1() === 1;
            }
            return;
        }
        case 30: { // Range
            if (opcode === 0) f.min = r.g2();
            else if (opcode === 1) f.max = r.g2();
            else if (opcode === 2) op.monochrome = r.g1() === 1;
            return;
        }
        case 31: {
            if (opcode === 0) f.i0 = r.g2();
            else if (opcode === 1) f.i1 = r.g2();
            else if (opcode === 2) f.i2 = r.g2();
            else if (opcode === 3) f.i3 = r.g2();
            return;
        }
        case 32: {
            if (opcode === 0) f.i0 = r.g2();
            else if (opcode === 1) f.i1 = r.g2();
            else if (opcode === 2) f.i2 = r.g2();
            return;
        }
        case 33: {
            if (opcode === 0) f.i0 = r.g2();
            else if (opcode === 1) f.flag = r.g1() === 1;
            return;
        }
        case 34: {
            if (opcode === 0) f.flag = r.g1() === 1;
            else if (opcode === 1) f.count = r.g1();
            else if (opcode === 2) {
                f.offset = r.g2b();
                if (f.offset < 0) {
                    const arr: number[] = [];
                    for (let i = 0; i < f.count; i++) arr.push(r.g2b());
                    f.values = arr;
                }
            }
            else if (opcode === 3) { f.pair0 = r.g1(); f.pair1 = f.pair0; }
            else if (opcode === 4) f.v4 = r.g1();
            else if (opcode === 5) f.v5 = r.g1();
            else if (opcode === 6) f.v6 = r.g1();
            return;
        }
        case 35: {
            if (opcode === 0) f.v = r.g2();
            return;
        }
        case 36: {
            if (opcode === 0) f.textureId = r.g2();
            return;
        }
        case 37: {
            if (opcode === 0) f.i0 = r.g2();
            else if (opcode === 1) f.i1 = r.g2();
            else if (opcode === 2) f.i2 = r.g2();
            else if (opcode === 3) f.i3 = r.g2();
            else if (opcode === 4) f.i4 = r.g2();
            else if (opcode === 5) f.i5 = r.g2();
            else if (opcode === 6) f.i6 = r.g2();
            return;
        }
        case 38: {
            if (opcode === 0) f.i0 = r.g1();
            else if (opcode === 1) f.i1 = r.g2();
            else if (opcode === 2) f.i2 = r.g1();
            else if (opcode === 3) f.i3 = r.g2();
            else if (opcode === 4) f.i4 = r.g2();
            return;
        }
        // Ops without their own decode override (no bytes consumed):
        case 2: case 3: case 13: case 24:
            return;
    }
    // Unknown kind / unhandled opcode — log and stop. The caller will
    // bail out for this texture; the rest of the cache stays usable.
    throw new Error("[TextureMaterial530] op kind " + op.kind +
        " has no handler for opcode " + opcode);
}

/** rt4 TextureOp constructor's `super(arity, ...)` arity, by op kind. */
function inputArity(kind: number): number {
    switch (kind) {
        // Single-input ops:
        case 6: case 9: case 14: case 15: case 17: case 19:
        case 20: case 22: case 23: case 24: case 26: case 27:
        case 30: case 31: case 32: case 33:
            return 1;
        // Two-input ops:
        case 7: case 21: case 25: case 38:
            return 2;
        // Three-input ops:
        case 5: case 11: case 16: case 28: case 35: case 37:
            return 3;
        // Four-input ops:
        case 4: case 12:
            return 4;
        // Five-input / op-specific:
        case 8: case 10: case 29: case 34:
            return 1;
        // Leaves (no children):
        case 0: case 1: case 2: case 3: case 13: case 18: case 36: case 39:
            return 0;
        default:
            return 0;
    }
}

// ── Texture record (single-id procedural pipeline) ──

export interface TextureMaterial530Data {
    id: number;
    /** All ops in declaration order. ops[i].inputs reference indices in this same array. */
    ops: TextureOpBase[];
    /** Index of the "main" output op (Texture.aClass3_Sub1_1). */
    mainOpIndex: number;
    /** Index of the alpha-output op (Texture.aClass3_Sub1_2). */
    alphaOpIndex: number;
    /** Sprite ids referenced by leaf TextureOpSprite/TextureOpTiledSprite ops (deduplicated). */
    spriteIds: number[];
    /** Texture ids referenced by leaf TextureOpTexture ops (deduplicated). */
    textureIds: number[];
}

function decodeTextureMaterial(data: Uint8Array, id: number): TextureMaterial530Data | null {
    const r = new TexReader(data);
    const opCount = r.g1();
    const ops: TextureOpBase[] = [];

    // Phase 1: per-op headers + decode loop.
    // rt4: for (i in opCount) { method3680(buf) }
    //   method3680: g1 (skipped), g1 (kind), then `op = create(kind)`,
    //               op.anInt5840 = g1(), arg-count = g1(),
    //               then arg-count iterations of {opcode = g1; op.decode(opcode, buf)};
    //               op.postDecode().
    // After method3680: arg-count more g1() reads collect input refs into local14[i][].
    const inputBuckets: number[][] = [];

    for (let i = 0; i < opCount; i++) {
        r.g1(); // discarded prefix (rt4 reads but never stores it)
        const kind = r.g1();
        const op: TextureOpBase = {
            kind,
            inputs: [],
            cache: 0,
            monochrome: defaultMonochrome(kind),
            fields: makeFields(kind),
        };
        op.cache = r.g1();
        const argCount = r.g1();
        for (let j = 0; j < argCount; j++) {
            const opcode = r.g1();
            applyOpDecode(op, opcode, r);
        }
        // postDecode is mostly a no-op in rt4 — caching strategies set up
        // later. Nothing in the byte stream changes.
        // The rt4 loop's input-arity matches the constructor's `super(arity)`,
        // not the runtime arg-count. Read inputArity(kind) bytes of input refs.
        const arity = inputArity(kind);
        const inputs: number[] = [];
        for (let j = 0; j < arity; j++) inputs.push(r.g1());
        inputBuckets.push(inputs);
        ops.push(op);
    }

    // Phase 2: resolve input references (rt4: aClass3_Sub1Array42[k] = ops[refs[k]]).
    for (let i = 0; i < opCount; i++) {
        ops[i].inputs = inputBuckets[i];
    }

    // Phase 3: read the two final-stage refs (main output + alpha output).
    const mainOpIndex = r.g1();
    const alphaOpIndex = r.g1();

    // Collect leaf references for downstream consumers.
    const spriteSet: Map<number, true> = new Map();
    const textureSet: Map<number, true> = new Map();
    for (const op of ops) {
        if (op.fields.kind === 18 || op.fields.kind === 39) {
            if (op.fields.spriteId >= 0) spriteSet.set(op.fields.spriteId, true);
        } else if (op.fields.kind === 36) {
            if (op.fields.textureId >= 0) textureSet.set(op.fields.textureId, true);
        }
    }
    const spriteIds: number[] = [];
    spriteSet.forEach((_, k) => spriteIds.push(k));
    const textureIds: number[] = [];
    textureSet.forEach((_, k) => textureIds.push(k));

    return { id, ops, mainOpIndex, alphaOpIndex, spriteIds, textureIds };
}

// ── List metadata at idx26 group=0 file=0 ──

export interface TextureMaterialList530Data {
    /** Number of texture-id slots. Length of every per-id field below. */
    count: number;
    /** Whether texture id `i` exists at all (gates every other field). */
    exists: boolean[];
    /** Per-texture flags. rt4 booleans aBoolean*Array9{0..3} — see Js5GlTextureProvider.java:84+. */
    isOpaque: boolean[];      // aBooleanArray91
    blends: boolean[];        // aBooleanArray89
    averagesRgb: boolean[];   // aBooleanArray90
    isAnimated: boolean[];    // aBooleanArray93
    /** Per-texture signed bytes (animation params, blend factors). */
    sb1: number[];            // aByteArray59 (g1b)
    sb2: number[];            // aByteArray60 (g1b)
    /** Per-texture average color (signed short). */
    avgRgb: number[];         // aShortArray59 (g2b)
    /** Per-texture combined-rgb byte (g1). */
    rgbCombined: number[];    // aByteArray61 (g1)
    /** Per-texture material type tag (g1). */
    materialType: number[];   // aByteArray62 (g1)
}

function decodeMaterialList(data: Uint8Array): TextureMaterialList530Data {
    const r = new TexReader(data);
    const count = r.g2();

    const exists: boolean[] = [];
    const isOpaque: boolean[] = [];
    const blends: boolean[] = [];
    const averagesRgb: boolean[] = [];
    const isAnimated: boolean[] = [];
    const sb1: number[] = [];
    const sb2: number[] = [];
    const avgRgb: number[] = [];
    const rgbCombined: number[] = [];
    const materialType: number[] = [];

    for (let i = 0; i < count; i++) exists.push(r.g1() === 1);
    for (let i = 0; i < count; i++) averagesRgb.push(exists[i] ? r.g1() === 1 : false);
    for (let i = 0; i < count; i++) isOpaque.push(exists[i] ? r.g1() === 1 : false);
    for (let i = 0; i < count; i++) blends.push(exists[i] ? r.g1() === 1 : false);
    for (let i = 0; i < count; i++) isAnimated.push(exists[i] ? r.g1() === 1 : false);
    for (let i = 0; i < count; i++) sb1.push(exists[i] ? r.g1b() : 0);
    for (let i = 0; i < count; i++) sb2.push(exists[i] ? r.g1b() : 0);
    for (let i = 0; i < count; i++) avgRgb.push(exists[i] ? r.g2b() : 0);
    for (let i = 0; i < count; i++) rgbCombined.push(exists[i] ? r.g1() : 0);
    for (let i = 0; i < count; i++) materialType.push(exists[i] ? r.g1() : 0);

    return {
        count, exists, isOpaque, blends, averagesRgb, isAnimated,
        sb1, sb2, avgRgb, rgbCombined, materialType,
    };
}

// ── Public API ───────────────────────────────────────────────────

/** Single texture-material record loader. */
export class TextureMaterial530 {
    /** rt4 idx number for procedural-texture records. */
    public static readonly INDEX = 9;

    static decode(data: Uint8Array, id: number): TextureMaterial530Data | null {
        try {
            return decodeTextureMaterial(data, id);
        } catch (e) {
            console.warn("[TextureMaterial530] decode failed for id=" + id + ": " + e);
            return null;
        }
    }

    static async load(js5Cache: Js5Cache, id: number): Promise<TextureMaterial530Data | null> {
        if (id < 0) return null;
        const data = await js5Cache.getFileBytes(TextureMaterial530.INDEX, id, 0);
        if (!data || data.byteLength === 0) return null;
        return TextureMaterial530.decode(data, id);
    }
}

/** Texture-list metadata loader (idx26 group=0 file=0). */
export class TextureMaterialList530 {
    public static readonly INDEX = 26;
    public static readonly GROUP = 0;
    public static readonly FILE = 0;

    static decode(data: Uint8Array): TextureMaterialList530Data {
        return decodeMaterialList(data);
    }

    static async load(js5Cache: Js5Cache): Promise<TextureMaterialList530Data | null> {
        const data = await js5Cache.getFileBytes(
            TextureMaterialList530.INDEX,
            TextureMaterialList530.GROUP,
            TextureMaterialList530.FILE,
        );
        if (!data || data.byteLength === 0) return null;
        return decodeMaterialList(data);
    }
}
