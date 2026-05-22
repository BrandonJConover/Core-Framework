/**
 * FloType530 — TypeScript port of rt4-client FloType.java + FloTypeList.java.
 *
 * Standalone parser for 530-native terrain underlay (floor) definitions stored in
 * idx2, group 4, file = floId. Mirrors the deob opcode-by-opcode.
 *
 * The deob exposes only a small set of opcodes (1, 2, 3, 5, 7, 8, 9, 10, 11, 12, 13,
 * 14). The brief mentioned "hue/saturation/lightness adjusts" — those are NOT first-
 * class decode opcodes in the 530 deob (they're derived at scene-build time from
 * baseColor via ColorUtils.rgbToHsl). We surface baseColor/secondaryColor as both raw
 * RGB and the rt4 method492() result (HSL packed int, or -1 for the magic 0xFF00FF
 * sentinel) so downstream code can choose.
 */
import { Js5Cache } from "../../Js5Cache";

export interface FloType530Data {
    id: number;

    // Raw RGB (24-bit) values exactly as decoded — useful for diagnostics/logging.
    baseColorRgb: number;
    secondaryColorRgb: number;
    // rt4 method492(): rgbToHsl(color), or -1 when color === 0xFF00FF (magenta sentinel
    // = "transparent / no underlay"). These are the values the renderer ultimately uses.
    baseColor: number;
    secondaryColor: number;

    // op2 — texture id (8-bit form, kept for legacy carts).
    // op3 — texture id (16-bit, 65535 ⇒ -1 sentinel). op3 overrides op2 in the deob.
    texture: number;

    // op5 — clears occludeUnderlay flag.
    occludeUnderlay: boolean;

    // op8 — sets a *static* class field (FloType.anInt865 = id). This is a global
    // last-decoded marker, not an instance field. We surface it through markerId so
    // callers can reproduce the side-effect if anything downstream depends on it.
    // (Most code paths don't.)
    markerId: number; // -1 unless op8 fired.

    // op9 — anInt5885 (texture-related render param, default 128).
    anInt5885: number;

    // op10 — clears aBoolean311 (default true).
    aBoolean311: boolean;

    // op11 — texture brightness (default 8).
    textureBrightness: number;

    // op12 — blendTexture flag.
    blendTexture: boolean;

    // op13 — water color (24-bit RGB, default 1190717 = 0x122BBD).
    waterColor: number;

    // op14 — water opacity (default 16; see deob comment for visual meaning).
    waterOpacity: number;
}

class FloBuf {
    pos: number = 0;
    constructor(private readonly data: Uint8Array) {}

    eof(): boolean { return this.pos >= this.data.byteLength; }

    g1(): number { return this.data[this.pos++] & 0xFF; }
    g2(): number {
        const a = this.data[this.pos++] & 0xFF;
        const b = this.data[this.pos++] & 0xFF;
        return (a << 8) | b;
    }
    g3(): number {
        const a = this.data[this.pos++] & 0xFF;
        const b = this.data[this.pos++] & 0xFF;
        const c = this.data[this.pos++] & 0xFF;
        return (a << 16) | (b << 8) | c;
    }
}

function rgbToHsl(rgb: number): number {
    const r = ((rgb >> 16) & 0xff) / 256.0;
    const g = ((rgb >> 8) & 0xff) / 256.0;
    const b = (rgb & 0xff) / 256.0;
    const min = Math.min(r, g, b);
    const max = Math.max(r, g, b);
    const light = (min + max) / 2.0;
    let hue = 0.0;
    let sat = 0.0;

    if (min !== max) {
        sat = light < 0.5 ? (max - min) / (min + max) : (max - min) / (2.0 - max - min);
        if (max === r) {
            hue = (g - b) / (max - min);
        } else if (max === g) {
            hue = (b - r) / (max - min) + 2.0;
        } else {
            hue = (r - g) / (max - min) + 4.0;
        }
    }

    hue /= 6.0;
    let h = (hue * 256.0) | 0;
    let s = (sat * 256.0) | 0;
    let l = (light * 256.0) | 0;
    if (s < 0) s = 0;
    else if (s > 255) s = 255;
    if (l < 0) l = 0;
    else if (l > 255) l = 255;
    if (l > 243) s >>= 4;
    else if (l > 217) s >>= 3;
    else if (l > 192) s >>= 2;
    else if (l > 179) s >>= 1;
    return ((h >> 2) << 10) + ((s >> 5) << 7) + (l >> 1);
}

function method492(rgb: number): number {
    return rgb === 0xFF00FF ? -1 : rgbToHsl(rgb);
}

function defaultData(id: number): FloType530Data {
    return {
        id,
        baseColorRgb: 0,
        secondaryColorRgb: -1,
        baseColor: 0,
        secondaryColor: -1,
        texture: -1,
        occludeUnderlay: true,
        markerId: -1,
        anInt5885: 128,
        aBoolean311: true,
        textureBrightness: 8,
        blendTexture: false,
        waterColor: 1190717, // 0x122BBD — rt4 default.
        waterOpacity: 16,
    };
}

export class FloType530 {
    /** Per-id record cache. Populated as a side-effect of load() so any
     *  caller that has previously requested an id can hit it synchronously
     *  via cache530.get(id). The TerrainAdapter530 floLookup uses this to
     *  resolve overlay/underlay floor records during landscape mesh build. */
    public static cache530: Map<number, FloType530Data> | null = null;

    /** Parse a single FloType buffer. Returns null on empty input. */
    static decode(data: Uint8Array, id: number): FloType530Data | null {
        if (!data) return null;
        const buf = new FloBuf(data);
        const out = defaultData(id);

        while (true) {
            if (buf.eof()) break;
            const opcode = buf.g1();
            if (opcode === 0) break;
            FloType530.decodeOpcode(buf, opcode, out, id);
        }

        return out;
    }

    private static decodeOpcode(buf: FloBuf, opcode: number, out: FloType530Data, id: number): void {
        if (opcode === 1) {
            out.baseColorRgb = buf.g3();
            out.baseColor = method492(out.baseColorRgb);
        } else if (opcode === 2) {
            out.texture = buf.g1();
        } else if (opcode === 3) {
            const tex = buf.g2();
            out.texture = tex === 65535 ? -1 : tex;
        } else if (opcode === 5) {
            out.occludeUnderlay = false;
        } else if (opcode === 7) {
            out.secondaryColorRgb = buf.g3();
            out.secondaryColor = method492(out.secondaryColorRgb);
        } else if (opcode === 8) {
            // Deob writes the id to a static global (FloType.anInt865 = id). We surface
            // it through markerId for callers that want to mirror the side-effect.
            out.markerId = id;
        } else if (opcode === 9) {
            out.anInt5885 = buf.g2();
        } else if (opcode === 10) {
            out.aBoolean311 = false;
        } else if (opcode === 11) {
            out.textureBrightness = buf.g1();
        } else if (opcode === 12) {
            out.blendTexture = true;
        } else if (opcode === 13) {
            out.waterColor = buf.g3();
        } else if (opcode === 14) {
            out.waterOpacity = buf.g1();
        } else {
            // Unknown opcode — surface rather than silently desync the next file.
            throw new Error("FloType530: unknown opcode " + opcode + " at offset " + (buf.pos - 1) + " (id=" + id + ")");
        }
    }

    /**
     * Resolve a FloType from idx2. All floors live in group 4 of idx2, with file id
     * matching the floor id directly (per FloTypeList.method4395).
     */
    static async load(js5Cache: Js5Cache, floId: number): Promise<FloType530Data | null> {
        if (floId < 0) return null;
        if (FloType530.cache530) {
            const hit = FloType530.cache530.get(floId);
            if (hit !== undefined) return hit;
        }
        const data = await js5Cache.getFileBytes(2, 4, floId);
        if (!data || data.byteLength === 0) return null;
        const decoded = FloType530.decode(data, floId);
        if (decoded && FloType530.cache530) FloType530.cache530.set(floId, decoded);
        return decoded;
    }
}
