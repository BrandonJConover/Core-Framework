/**
 * LocType530 — TypeScript port of rt4-client LocType.java + LocTypeList.java.
 *
 * Standalone parser for 530-native scenery (location) definitions stored in idx16.
 * Group/file scheme matches rt4 LocTypeList: groupId = id >>> 8, fileId = id & 0xFF.
 * Models referenced by op1/op5 live in idx7 (resolved by downstream renderers; this
 * parser only emits the model id table).
 *
 * Mirror of LocType.java decode() — every opcode the deob references is implemented
 * here so the byte stream stays aligned even for fields we don't yet consume.
 *
 * NOTE: opcode numbering here MUST match the deob exactly; the reference reads opcode
 * 22 as "computeVertexColors / sharelight" (NOT contoured-ground, that's op21), op88 as
 * "castshadow=false" (NOT mapsceneIcon, mapsceneIcon=mapscene which is op102), etc.
 * The task brief used different mnemonics in places — the deob is the source of truth.
 */
import { Js5Cache } from "../../Js5Cache";

/** Decoded shape constants from LocType.java (informational; consumers may use these). */
export const LocShape = {
    WALL_STRAIGHT: 0,
    WALL_DIAGONALCORNER: 1,
    WALL_L: 2,
    WALL_SQUARECORNER: 3,
    WALL_DIAGONAL: 9,
    WALLDECOR_STRAIGHT_XOFFSET: 4,
    WALLDECOR_STRAIGHT_ZOFFSET: 5,
    WALLDECOR_DIAGONAL_XOFFSET: 6,
    WALLDECOR_DIAGONAL_ZOFFSET: 7,
    WALLDECOR_DIAGONAL_BOTH: 8,
    CENTREPIECE_STRAIGHT: 10,
    CENTREPIECE_DIAGONAL: 11,
    ROOF_STRAIGHT: 12,
    ROOF_DIAGONAL_WITH_ROOFEDGE: 13,
    ROOF_DIAGONAL: 14,
    ROOF_L_CONCAVE: 15,
    ROOF_L_CONVEX: 16,
    ROOF_FLAT: 17,
    ROOFEDGE_STRAIGHT: 18,
    ROOFEDGE_DIAGONALCORNER: 19,
    ROOFEDGE_L: 20,
    ROOFEDGE_SQUARECORNER: 21,
    GROUNDDECOR: 22,
} as const;

/** Heterogeneous param-table value (op249). */
export type LocParamValue = { kind: "int"; value: number } | { kind: "string"; value: string };

/** Mirrors every public/private field LocType.java holds after decode(). */
export interface LocType530Data {
    id: number;

    // op1/op5 — model lists.
    // shapes is null when op5 was used (single-shape model list); non-null after op1.
    shapes: number[] | null;
    models: number[] | null;

    // op2 — name (default "null").
    name: string;

    // op14/op15 — footprint in tiles.
    width: number;
    length: number;

    // op17 — clears blockwalk and blockrange.
    // op18 — clears blockrange only.
    // op27 — sets blockwalk = 1.
    blockwalk: number;     // default 2; op17→0, op27→1
    blockrange: boolean;   // default true; op17/op18→false

    // op19 — interactType (-1 → resolved by postDecode based on models/ops).
    interactable: number;

    // op21 — hillskewType = 1 (contoured ground).
    // op81 — hillskewType = 2 + amount (g1*256).
    // op93 — hillskewType = 3 + amount (g2).
    // op94 — hillskewType = 4.
    // op95 — hillskewType = 5.
    hillskewType: number;
    hillskewAmount: number;

    // op22 — share-light (compute vertex colors with neighbours).
    computeVertexColors: boolean;
    // op23 — occlude flag.
    occlude: boolean;
    // op24 — anim seq id (-1 if absent / 65535 sentinel).
    anim: number;
    // op28 — wall offset (default 16).
    walloff: number;
    // op29 — ambient lighting tweak (signed byte).
    ambient: number;
    // op39 — contrast (signed byte * 5).
    contrast: number;

    // op30..34 — interaction op strings (5 slots). null in slot ⇒ no op or "Hidden".
    ops: (string | null)[];

    // op40 — palette recolor pairs.
    recol_s: number[] | null;   // unsigned shorts
    recol_d: number[] | null;
    // op41 — texture remap pairs.
    retex_s: number[] | null;
    retex_d: number[] | null;
    // op42 — recolor palette indices (signed bytes).
    recol_p: number[] | null;

    // op60 — minimap function/icon id.
    mapfunction: number;
    // op62 — model is mirrored.
    mirror: boolean;
    // op64 — active flag (false ⇒ scene-graph-static, no animation/cursor).
    active: boolean;
    // op65/66/67 — model resize (default 128).
    resizex: number;
    resizey: number;
    resizez: number;
    // op69 — bitmask of blocked sides for projectiles.
    blocksides: number;
    // op70/71/72 — model translation offsets (signed shorts).
    xoff: number;
    yoff: number;
    zoff: number;
    // op73 — force decor flag.
    forcedecor: boolean;
    // op74 — break route finding (sets blockwalk=0/blockrange=false in postDecode).
    breakroutefinding: boolean;
    // op75 — supports items above (-1 → defaulted by postDecode from blockwalk).
    supportitems: number;

    // op77/op92 — multi-loc transform (varbit / varp / default-shape sentinel(op92) +
    // child id table). multiLocs layout matches the deob: [child0, …, childN, default].
    // For op92 the default is the secondary g2 sentinel (or -1); for op77 default = -1.
    multiLocs: number[] | null;
    multiLocVarbit: number;
    multiLocVarp: number;

    // op78 — single ambient sound: id + range.
    bgsound: number;
    bgsoundrange: number;
    // op79 — random ambient sounds: min/max interval, range, and id pool.
    bgsoundmin: number;
    bgsoundmax: number;
    bgsounds: number[] | null;

    // op82 — render flag (forces always-render even when occluded?).
    render: boolean;
    // op88 — castshadow toggle.
    castshadow: boolean;
    // op89 — disable randomized animation start frame.
    allowrandomizedanimation: boolean;
    // op90 — unknown (aBoolean211).
    aBoolean211: boolean;
    // op91 — members-only.
    members: boolean;
    // op96 — hasanimation flag.
    hasanimation: boolean;
    // op97 — mapscene rotated.
    mapSceneRotated: boolean;
    // op98 — unknown (aBoolean214).
    aBoolean214: boolean;
    // op99/op100 — cursor1/cursor2 (op + id).
    cursor1Op: number;
    cursor1: number;
    cursor2Op: number;
    cursor2: number;
    // op101 — mapscene angle offset.
    mapSceneAngleOffset: number;
    // op102 — mapscene id.
    mapscene: number;

    // op249 — heterogeneous params keyed by 24-bit id.
    params: { [key: number]: LocParamValue } | null;
}

/** Self-contained byte reader matching rt4-client Buffer semantics for unsigned/signed widths. */
class LocBuf {
    pos: number = 0;
    constructor(private readonly data: Uint8Array) {}

    eof(): boolean { return this.pos >= this.data.byteLength; }

    g1(): number { return this.data[this.pos++] & 0xFF; }
    g1b(): number {
        const v = this.data[this.pos++] & 0xFF;
        return v > 127 ? v - 256 : v;
    }
    g2(): number {
        const a = this.data[this.pos++] & 0xFF;
        const b = this.data[this.pos++] & 0xFF;
        return (a << 8) | b;
    }
    g2b(): number {
        // Big-endian signed short (rt4 Buffer.g2b).
        const v = this.g2();
        return v > 32767 ? v - 65536 : v;
    }
    g3(): number {
        const a = this.data[this.pos++] & 0xFF;
        const b = this.data[this.pos++] & 0xFF;
        const c = this.data[this.pos++] & 0xFF;
        return (a << 16) | (b << 8) | c;
    }
    g4(): number {
        const a = this.data[this.pos++] & 0xFF;
        const b = this.data[this.pos++] & 0xFF;
        const c = this.data[this.pos++] & 0xFF;
        const d = this.data[this.pos++] & 0xFF;
        return ((a << 24) | (b << 16) | (c << 8) | d) | 0;
    }
    /** Null-terminated cp1252-ish string (treat as Latin-1 for now). */
    gjstr(): string {
        let s = "";
        const end = this.data.byteLength;
        while (this.pos < end && this.data[this.pos] !== 0) {
            s += String.fromCharCode(this.data[this.pos++] & 0xFF);
        }
        if (this.pos < end) this.pos++; // skip terminator
        return s;
    }
}

/** Default-construct a LocType530Data with the same defaults as LocType.java field initialisers. */
function defaultData(id: number): LocType530Data {
    return {
        id,
        shapes: null,
        models: null,
        name: "null",
        width: 1,
        length: 1,
        blockwalk: 2,
        blockrange: true,
        interactable: -1,
        hillskewType: 0,
        hillskewAmount: -1,
        computeVertexColors: false,
        occlude: false,
        anim: -1,
        walloff: 16,
        ambient: 0,
        contrast: 0,
        ops: [null, null, null, null, null],
        recol_s: null,
        recol_d: null,
        retex_s: null,
        retex_d: null,
        recol_p: null,
        mapfunction: -1,
        mirror: false,
        active: true,
        resizex: 128,
        resizey: 128,
        resizez: 128,
        blocksides: 0,
        xoff: 0,
        yoff: 0,
        zoff: 0,
        forcedecor: false,
        breakroutefinding: false,
        supportitems: -1,
        multiLocs: null,
        multiLocVarbit: -1,
        multiLocVarp: -1,
        bgsound: -1,
        bgsoundrange: 0,
        bgsoundmin: 0,
        bgsoundmax: 0,
        bgsounds: null,
        render: false,
        castshadow: true,
        allowrandomizedanimation: true,
        aBoolean211: false,
        members: false,
        hasanimation: false,
        mapSceneRotated: false,
        aBoolean214: false,
        cursor1Op: -1,
        cursor1: -1,
        cursor2Op: -1,
        cursor2: -1,
        mapSceneAngleOffset: 0,
        mapscene: -1,
        params: null,
    };
}

/**
 * Decode + postDecode pass per LocType.java. The buffer is consumed until either an
 * opcode-0 terminator is read or the stream ends. Unknown opcodes throw — matching
 * the deob behaviour of falling out of the if/else chain with no consumption (which
 * would desync the reader on every subsequent loc, so we surface it instead).
 */
export class LocType530 {
    /**
     * Parse one LocType buffer. Returns a fully-populated data record.
     * Callers should never receive null from a valid buffer; null only for empty input.
     */
    static decode(data: Uint8Array, id: number): LocType530Data | null {
        if (!data) return null;
        const buf = new LocBuf(data);
        const out = defaultData(id);

        while (true) {
            if (buf.eof()) break;
            const opcode = buf.g1();
            if (opcode === 0) break;
            LocType530.decodeOpcode(buf, opcode, out);
        }

        LocType530.postDecode(out);
        return out;
    }

    /** Single-opcode dispatch. Mirrors LocType.java decode(buffer, opcode) exactly. */
    private static decodeOpcode(buf: LocBuf, opcode: number, out: LocType530Data): void {
        let count: number;
        let len: number;

        if (opcode === 1) {
            // Model list with per-entry shape: [g2 modelId, g1 shape] × count.
            count = buf.g1();
            if (count > 0) {
                // The deob allows skipping when models already populated (replay path
                // in the live client). We always populate.
                out.shapes = new Array<number>(count);
                out.models = new Array<number>(count);
                for (len = 0; len < count; len++) {
                    out.models[len] = buf.g2();
                    out.shapes[len] = buf.g1();
                }
            }
        } else if (opcode === 2) {
            out.name = buf.gjstr();
        } else if (opcode === 5) {
            // Single-shape model list: [g2 modelId] × count. shapes cleared to null.
            count = buf.g1();
            if (count > 0) {
                out.models = new Array<number>(count);
                out.shapes = null;
                for (len = 0; len < count; len++) {
                    out.models[len] = buf.g2();
                }
            }
        } else if (opcode === 14) {
            out.width = buf.g1();
        } else if (opcode === 15) {
            out.length = buf.g1();
        } else if (opcode === 17) {
            out.blockwalk = 0;
            out.blockrange = false;
        } else if (opcode === 18) {
            out.blockrange = false;
        } else if (opcode === 19) {
            out.interactable = buf.g1();
        } else if (opcode === 21) {
            out.hillskewType = 1;
        } else if (opcode === 22) {
            out.computeVertexColors = true;
        } else if (opcode === 23) {
            out.occlude = true;
        } else if (opcode === 24) {
            const anim = buf.g2();
            out.anim = anim === 65535 ? -1 : anim;
        } else if (opcode === 27) {
            out.blockwalk = 1;
        } else if (opcode === 28) {
            out.walloff = buf.g1();
        } else if (opcode === 29) {
            out.ambient = buf.g1b();
        } else if (opcode === 39) {
            out.contrast = buf.g1b() * 5;
        } else if (opcode >= 30 && opcode < 35) {
            const op = buf.gjstr();
            // The reference compares case-insensitively against LocalizedText.HIDDEN
            // ("Hidden") and nulls the slot if it matches. We replicate with a fixed
            // English literal — fine for the 530 cache, but note this is locale-dependent
            // in the deob.
            out.ops[opcode - 30] = op.toLowerCase() === "hidden" ? null : op;
        } else if (opcode === 40) {
            count = buf.g1();
            out.recol_s = new Array<number>(count);
            out.recol_d = new Array<number>(count);
            for (len = 0; len < count; len++) {
                out.recol_s[len] = buf.g2();
                out.recol_d[len] = buf.g2();
            }
        } else if (opcode === 41) {
            count = buf.g1();
            out.retex_s = new Array<number>(count);
            out.retex_d = new Array<number>(count);
            for (len = 0; len < count; len++) {
                out.retex_s[len] = buf.g2();
                out.retex_d[len] = buf.g2();
            }
        } else if (opcode === 42) {
            count = buf.g1();
            out.recol_p = new Array<number>(count);
            for (len = 0; len < count; len++) {
                out.recol_p[len] = buf.g1b();
            }
        } else if (opcode === 60) {
            out.mapfunction = buf.g2();
        } else if (opcode === 62) {
            out.mirror = true;
        } else if (opcode === 64) {
            out.active = false;
        } else if (opcode === 65) {
            out.resizex = buf.g2();
        } else if (opcode === 66) {
            out.resizey = buf.g2();
        } else if (opcode === 67) {
            out.resizez = buf.g2();
        } else if (opcode === 69) {
            out.blocksides = buf.g1();
        } else if (opcode === 70) {
            out.xoff = buf.g2b();
        } else if (opcode === 71) {
            out.yoff = buf.g2b();
        } else if (opcode === 72) {
            out.zoff = buf.g2b();
        } else if (opcode === 73) {
            out.forcedecor = true;
        } else if (opcode === 74) {
            out.breakroutefinding = true;
        } else if (opcode === 75) {
            out.supportitems = buf.g1();
        } else if (opcode === 77 || opcode === 92) {
            // Transform / multi-loc table.
            // op77: [g2 varbit, g2 varp, g1 lastIdx, (g2 child) × (lastIdx+1)] →
            //       multiLocs = [...children, -1]
            // op92: [g2 varbit, g2 varp, g2 defaultSentinel, g1 lastIdx, (g2 child) × (lastIdx+1)]
            //       multiLocs = [...children, defaultSentinel]
            // Sentinel handling: 65535 → -1 for varbit, varp, child entries, AND the op92 default.
            let defaultId = -1;
            const varbit = buf.g2();
            out.multiLocVarbit = varbit === 65535 ? -1 : varbit;
            const varp = buf.g2();
            out.multiLocVarp = varp === 65535 ? -1 : varp;
            if (opcode === 92) {
                const def = buf.g2();
                defaultId = def === 65535 ? -1 : def;
            }
            const last = buf.g1();
            const arr = new Array<number>(last + 2);
            for (let i = 0; i <= last; i++) {
                const child = buf.g2();
                arr[i] = child === 65535 ? -1 : child;
            }
            arr[last + 1] = defaultId;
            out.multiLocs = arr;
        } else if (opcode === 78) {
            out.bgsound = buf.g2();
            out.bgsoundrange = buf.g1();
        } else if (opcode === 79) {
            out.bgsoundmin = buf.g2();
            out.bgsoundmax = buf.g2();
            out.bgsoundrange = buf.g1();
            count = buf.g1();
            out.bgsounds = new Array<number>(count);
            for (len = 0; len < count; len++) {
                out.bgsounds[len] = buf.g2();
            }
        } else if (opcode === 81) {
            out.hillskewType = 2;
            // amount = (byte * 256) — the deob multiplies before storing as short.
            out.hillskewAmount = buf.g1() * 256;
        } else if (opcode === 82) {
            out.render = true;
        } else if (opcode === 88) {
            out.castshadow = false;
        } else if (opcode === 89) {
            out.allowrandomizedanimation = false;
        } else if (opcode === 90) {
            out.aBoolean211 = true;
        } else if (opcode === 91) {
            out.members = true;
        } else if (opcode === 93) {
            out.hillskewType = 3;
            out.hillskewAmount = buf.g2();
        } else if (opcode === 94) {
            out.hillskewType = 4;
        } else if (opcode === 95) {
            out.hillskewType = 5;
        } else if (opcode === 96) {
            out.hasanimation = true;
        } else if (opcode === 97) {
            out.mapSceneRotated = true;
        } else if (opcode === 98) {
            out.aBoolean214 = true;
        } else if (opcode === 99) {
            out.cursor1Op = buf.g1();
            out.cursor1 = buf.g2();
        } else if (opcode === 100) {
            out.cursor2Op = buf.g1();
            out.cursor2 = buf.g2();
        } else if (opcode === 101) {
            out.mapSceneAngleOffset = buf.g1();
        } else if (opcode === 102) {
            out.mapscene = buf.g2();
        } else if (opcode === 249) {
            // Param table: count, then [g1 isString, g3 key, (gjstr|g4) value] × count.
            count = buf.g1();
            if (out.params === null) out.params = {};
            for (let i = 0; i < count; i++) {
                const isString = buf.g1() === 1;
                const key = buf.g3();
                if (isString) {
                    out.params[key] = { kind: "string", value: buf.gjstr() };
                } else {
                    out.params[key] = { kind: "int", value: buf.g4() };
                }
            }
        } else {
            // Unknown opcode — surface so we don't silently desync the rest of the
            // group. If a future cache rev adds an opcode, add it here.
            throw new Error("LocType530: unknown opcode " + opcode + " at offset " + (buf.pos - 1) + " (id=" + out.id + ")");
        }
    }

    /** Mirrors LocType.postDecode(): finalises interactable + supportitems defaults. */
    private static postDecode(out: LocType530Data): void {
        if (out.interactable === -1) {
            out.interactable = 0;
            // Default to interactable=1 if any rendered model exists for the standard
            // centrepiece shape OR no shape table was supplied (op5 single-shape list).
            if (out.models !== null && (out.shapes === null || out.shapes[0] === LocShape.CENTREPIECE_STRAIGHT)) {
                out.interactable = 1;
            }
            // Or any of the 5 op slots was set.
            for (let i = 0; i < 5; i++) {
                if (out.ops[i] !== null) {
                    out.interactable = 1;
                    break;
                }
            }
        }
        if (out.supportitems === -1) {
            out.supportitems = out.blockwalk === 0 ? 0 : 1;
        }
        // Note: LocTypeList.get() also applies breakroutefinding → blockwalk=0,
        // blockrange=false AFTER the type is constructed. Replicate so the type
        // reflects its true walk/range state.
        if (out.breakroutefinding) {
            out.blockwalk = 0;
            out.blockrange = false;
        }
    }

    /**
     * Resolve a LocType from idx16 by id. Returns null if the file is missing or empty.
     * Group/file scheme matches rt4 LocTypeList: groupId = id >>> 8, fileId = id & 0xFF.
     */
    static async load(js5Cache: Js5Cache, locId: number): Promise<LocType530Data | null> {
        if (locId < 0) return null;
        const groupId = locId >>> 8;
        const fileId = locId & 0xFF;
        const data = await js5Cache.getFileBytes(16, groupId, fileId);
        if (!data || data.byteLength === 0) return null;
        return LocType530.decode(data, locId);
    }
}
