/**
 * ObjType530 — TypeScript port of rt4-client's ObjType.java item-definition decoder
 * (the rev-530 replacement for the old 377 ItemDefinition).
 *
 * The 530 cache stores item ("ObjType") definitions in idx19. ObjTypeList.get()
 * fetches them with:
 *     groupId = id >>> 8
 *     fileId  = id & 0xFF
 * (i.e. up to 256 obj definitions per group). The group payload is a single
 * Js5-compressed file per logical objId, decoded via the opcode loop below.
 *
 * Mirrors ObjType.decode() opcode-for-opcode. Anything the deob handles is
 * handled here; anything it doesn't is left out by design. Field names track
 * the deob 1:1 so this parser can be cross-checked against the Java source.
 *
 * This file is intentionally standalone — it does NOT plug into the existing
 * 377-derived ItemDefinition. Wiring is the next step (see report).
 */

import { Js5Cache } from "../../Js5Cache";

/**
 * Fully-decoded 530 item definition. Field names match rt4 ObjType.java; defaults
 * track the Java field initialisers (e.g. cost=1, ops[2]="Take", iops[4]="Drop",
 * resizeX/Y/Z=128, zoom2d=2000, all wear/head ids = -1).
 */
export interface ObjType530Data {
    /** ObjType id this definition was loaded for. */
    id: number;

    // ── Identity ──
    name: string;
    /** Description was removed in 530's ObjType (no opcode 3). Kept undefined; never set by decode. */
    description?: string;

    // ── Display model + 2D rendering ──
    model: number;             // op1
    zoom2d: number;            // op4   default 2000
    xAngle2D: number;          // op5
    yAngle2D: number;          // op6
    xOffset2D: number;         // op7   (signed 16)
    yOffset2D: number;         // op8   (signed 16)
    zAngle2D: number;          // op95
    resizeX: number;           // op110 default 128
    resizeY: number;           // op111 default 128
    resizeZ: number;           // op112 default 128
    ambient: number;           // op113 (signed byte)
    contrast: number;          // op114 (signed byte * 5)

    // ── Inventory / stack / shop ──
    /** 1 = always stackable (op11); 0 = single. */
    stackable: number;
    cost: number;              // op12 default 1
    members: boolean;          // op16
    stockMarket: boolean;      // op65
    team: number;              // op115
    /** opcode 96: rt4 calls this "dummyitem". 1 = client-side dummy (placeholder). */
    dummyItem: number;

    // ── Wear models (man + woman, three-piece). All -1 when unset. ──
    manwear: number;           // op23
    manwear2: number;          // op24
    manwear3: number;          // op78
    womanwear: number;         // op25
    womanwear2: number;        // op26
    womanwear3: number;        // op79

    // ── Head models (man + woman, two-piece). All -1 when unset. ──
    manhead: number;           // op90
    manhead2: number;          // op92
    womanhead: number;         // op91
    womanhead2: number;        // op93

    // ── Wear-model translation offsets (signed bytes). ──
    manWearXOff: number;       // op125
    manWearYOff: number;
    manWearZOff: number;
    womanWearXOff: number;     // op126
    womanWearYOff: number;
    womanWearZOff: number;

    // ── Ground / inventory option strings (fixed length 5 each). ──
    // ops[2] defaults to "Take"; iops[4] defaults to "Drop". Slot may hold null
    // if explicitly cleared by the server-side def.
    ops: (string | null)[];    // op30..op34
    iops: (string | null)[];   // op35..op39

    // ── Color and texture replacement tables. ──
    // recol_s/recol_d are the source/dest HSL16 values (op40).
    // recol_p (op42) is an optional per-replacement palette index byte.
    // retex_s/retex_d are texture id replacements (op41).
    recol_s: number[] | null;  // signed shorts
    recol_d: number[] | null;
    recol_p: number[] | null;  // signed bytes
    retex_s: number[] | null;  // signed shorts
    retex_d: number[] | null;

    // ── Stackable-model swap table (op100..op109). 10-slot parallel arrays. ──
    countobj: number[] | null;
    countco: number[] | null;

    // ── Cert / lent linking. ──
    certlink: number;          // op97   default -1
    certtemplate: number;      // op98   default -1
    lentLink: number;          // op121  default -1
    lentTemplate: number;      // op122  default -1

    // ── Cursor overrides (ground-action and inv-action cursors). ──
    cursor1Op: number;         // op127 first byte (which op slot)
    cursor1: number;           // op127 short  (cursor sprite id)
    cursor2Op: number;         // op128 first byte
    cursor2: number;           // op128 short

    // ── Param table (op249 — "cs2 params"). number-keyed; values are int|string. ──
    params: { [key: number]: number | string } | null;
}

/** Reusable little reader over a Uint8Array with the rt4 helper names. */
class ObjReader {
    public pos: number = 0;
    constructor(public readonly data: Uint8Array) {}

    g1(): number {
        return this.data[this.pos++] & 0xFF;
    }
    /** signed byte (rt4 g1b). */
    g1b(): number {
        const b = this.data[this.pos++] & 0xFF;
        return (b << 24) >> 24;
    }
    g2(): number {
        const a = this.data[this.pos++] & 0xFF;
        const b = this.data[this.pos++] & 0xFF;
        return (a << 8) | b;
    }
    /** unsigned 24-bit big-endian (rt4 g3). Used by op249 param keys. */
    g3(): number {
        const a = this.data[this.pos++] & 0xFF;
        const b = this.data[this.pos++] & 0xFF;
        const c = this.data[this.pos++] & 0xFF;
        return (a << 16) | (b << 8) | c;
    }
    /** signed 32-bit big-endian (rt4 g4). */
    g4(): number {
        const a = this.data[this.pos++] & 0xFF;
        const b = this.data[this.pos++] & 0xFF;
        const c = this.data[this.pos++] & 0xFF;
        const d = this.data[this.pos++] & 0xFF;
        return ((a << 24) | (b << 16) | (c << 8) | d) | 0;
    }
    /** NUL-terminated string (rt4 gjstr — used for all decoded strings). */
    gjstr(): string {
        let s = "";
        const end = this.data.byteLength;
        while (this.pos < end) {
            const c = this.data[this.pos++] & 0xFF;
            if (c === 0) break;
            s += String.fromCharCode(c);
        }
        return s;
    }
    /**
     * Smart-int (rt4 gsmart). Used elsewhere in the cache, NOT by ObjType.decode.
     * Provided here to keep parity with the helper set named in the spec.
     *   peek < 128  → unsigned byte   (range 0..127)
     *   peek >= 128 → unsigned short - 32768 (range 0..32767)
     */
    gsmart(): number {
        const peek = this.data[this.pos] & 0xFF;
        if (peek < 128) {
            return this.g1();
        }
        return this.g2() - 32768;
    }
    /**
     * Big-smart-int (rt4 gbigsmart, aka g4smart in some sources). Used elsewhere
     * in the cache (e.g. interface defs), NOT by ObjType.decode. Reads either
     * one short (high bit clear) or a 4-byte int (high bit set, masked off).
     *   peek < 0x8000 → unsigned short
     *   else          → 32-bit int with the top bit cleared
     */
    gbigsmart(): number {
        const peekHi = this.data[this.pos] & 0xFF;
        if (peekHi < 0x80) {
            // High bit clear → 16-bit field
            const v = this.g2();
            return v === 32767 ? -1 : v;
        }
        return this.g4() & 0x7FFFFFFF;
    }
}

/**
 * Hidden ground-option sentinel — when a server-side def writes "Hidden" as a
 * ground op string the client treats it as a slot blanker (ObjType.java:292).
 */
const HIDDEN_OP = "Hidden";

/**
 * Build a fresh ObjType530Data with the same field defaults the deob's Java
 * field initialisers set before decode() runs.
 */
function makeDefault(id: number): ObjType530Data {
    return {
        id: id,
        name: "null",
        model: 0,
        zoom2d: 2000,
        xAngle2D: 0,
        yAngle2D: 0,
        xOffset2D: 0,
        yOffset2D: 0,
        zAngle2D: 0,
        resizeX: 128,
        resizeY: 128,
        resizeZ: 128,
        ambient: 0,
        contrast: 0,
        stackable: 0,
        cost: 1,
        members: false,
        stockMarket: false,
        team: 0,
        dummyItem: 0,
        manwear: -1,
        manwear2: -1,
        manwear3: -1,
        womanwear: -1,
        womanwear2: -1,
        womanwear3: -1,
        manhead: -1,
        manhead2: -1,
        womanhead: -1,
        womanhead2: -1,
        manWearXOff: 0,
        manWearYOff: 0,
        manWearZOff: 0,
        womanWearXOff: 0,
        womanWearYOff: 0,
        womanWearZOff: 0,
        // ops[2] = "Take", iops[4] = "Drop" — matches the LocalizedText defaults
        // baked into the ObjType.java field initialisers.
        ops: [null, null, "Take", null, null],
        iops: [null, null, null, null, "Drop"],
        recol_s: null,
        recol_d: null,
        recol_p: null,
        retex_s: null,
        retex_d: null,
        countobj: null,
        countco: null,
        certlink: -1,
        certtemplate: -1,
        lentLink: -1,
        lentTemplate: -1,
        cursor1Op: -1,
        cursor1: -1,
        cursor2Op: -1,
        cursor2: -1,
        params: null,
    };
}

/**
 * Decode a single ObjType opcode in-place onto `o`. Mirrors the giant
 * if/else-if ladder in ObjType.decode(Buffer, int) line-for-line.
 */
function decodeOp(r: ObjReader, op: number, o: ObjType530Data): void {
    if (op === 1) {
        o.model = r.g2();
    } else if (op === 2) {
        o.name = r.gjstr();
    } else if (op === 4) {
        o.zoom2d = r.g2();
    } else if (op === 5) {
        o.xAngle2D = r.g2();
    } else if (op === 6) {
        o.yAngle2D = r.g2();
    } else if (op === 7) {
        let v = r.g2();
        if (v > 32767) v -= 65536;
        o.xOffset2D = v;
    } else if (op === 8) {
        let v = r.g2();
        if (v > 32767) v -= 65536;
        o.yOffset2D = v;
    } else if (op === 11) {
        o.stackable = 1;
    } else if (op === 12) {
        o.cost = r.g4();
    } else if (op === 16) {
        o.members = true;
    } else if (op === 23) {
        o.manwear = r.g2();
    } else if (op === 24) {
        o.manwear2 = r.g2();
    } else if (op === 25) {
        o.womanwear = r.g2();
    } else if (op === 26) {
        o.womanwear2 = r.g2();
    } else if (op >= 30 && op <= 34) {
        // Ground options. "Hidden" = explicit null slot.
        const s = r.gjstr();
        o.ops[op - 30] = s.toLowerCase() === HIDDEN_OP.toLowerCase() ? null : s;
    } else if (op >= 35 && op <= 39) {
        // Inventory options.
        o.iops[op - 35] = r.gjstr();
    } else if (op === 40) {
        const count = r.g1();
        o.recol_s = new Array<number>(count);
        o.recol_d = new Array<number>(count);
        for (let i = 0; i < count; i++) {
            // Stored unsigned but cast back to signed short to match the Java
            // (short) cast in ObjType.java:305.
            const s = r.g2();
            const d = r.g2();
            o.recol_s[i] = s > 32767 ? s - 65536 : s;
            o.recol_d[i] = d > 32767 ? d - 65536 : d;
        }
    } else if (op === 41) {
        const count = r.g1();
        o.retex_s = new Array<number>(count);
        o.retex_d = new Array<number>(count);
        for (let i = 0; i < count; i++) {
            const s = r.g2();
            const d = r.g2();
            o.retex_s[i] = s > 32767 ? s - 65536 : s;
            o.retex_d[i] = d > 32767 ? d - 65536 : d;
        }
    } else if (op === 42) {
        const count = r.g1();
        o.recol_p = new Array<number>(count);
        for (let i = 0; i < count; i++) {
            o.recol_p[i] = r.g1b();
        }
    } else if (op === 65) {
        o.stockMarket = true;
    } else if (op === 78) {
        o.manwear3 = r.g2();
    } else if (op === 79) {
        o.womanwear3 = r.g2();
    } else if (op === 90) {
        o.manhead = r.g2();
    } else if (op === 91) {
        o.womanhead = r.g2();
    } else if (op === 92) {
        o.manhead2 = r.g2();
    } else if (op === 93) {
        o.womanhead2 = r.g2();
    } else if (op === 95) {
        o.zAngle2D = r.g2();
    } else if (op === 96) {
        o.dummyItem = r.g1();
    } else if (op === 97) {
        o.certlink = r.g2();
    } else if (op === 98) {
        o.certtemplate = r.g2();
    } else if (op >= 100 && op <= 109) {
        if (o.countobj === null) {
            o.countobj = new Array<number>(10);
            o.countco = new Array<number>(10);
            for (let i = 0; i < 10; i++) {
                o.countobj[i] = 0;
                o.countco![i] = 0;
            }
        }
        o.countobj[op - 100] = r.g2();
        o.countco![op - 100] = r.g2();
    } else if (op === 110) {
        o.resizeX = r.g2();
    } else if (op === 111) {
        o.resizeY = r.g2();
    } else if (op === 112) {
        o.resizeZ = r.g2();
    } else if (op === 113) {
        o.ambient = r.g1b();
    } else if (op === 114) {
        o.contrast = r.g1b() * 5;
    } else if (op === 115) {
        o.team = r.g1();
    } else if (op === 121) {
        o.lentLink = r.g2();
    } else if (op === 122) {
        o.lentTemplate = r.g2();
    } else if (op === 125) {
        o.manWearXOff = r.g1b();
        o.manWearYOff = r.g1b();
        o.manWearZOff = r.g1b();
    } else if (op === 126) {
        o.womanWearXOff = r.g1b();
        o.womanWearYOff = r.g1b();
        o.womanWearZOff = r.g1b();
    } else if (op === 127) {
        o.cursor1Op = r.g1();
        o.cursor1 = r.g2();
    } else if (op === 128) {
        o.cursor2Op = r.g1();
        o.cursor2 = r.g2();
    } else if (op === 129) {
        // ObjType.java:382 — read-and-discard. Two unknown fields the deob
        // doesn't store. Keep the read so the stream stays aligned.
        r.g1();
        r.g2();
    } else if (op === 130) {
        // Same as 129 — read-and-discard pair.
        r.g1();
        r.g2();
    } else if (op === 249) {
        // cs2 params table. Each entry: 1 byte type flag (1=string, else int),
        // 3 byte key, then payload (jstr or g4) per type.
        const size = r.g1();
        if (o.params === null) o.params = {};
        for (let i = 0; i < size; i++) {
            const isString = r.g1() === 1;
            const key = r.g3();
            if (isString) {
                o.params[key] = r.gjstr();
            } else {
                o.params[key] = r.g4();
            }
        }
    }
    // Unknown opcodes are silently ignored — same as the deob (its giant
    // if/else-if has no terminal else, so unmatched ops fall through).
}

/**
 * Decode an entire ObjType payload. Mirrors ObjType.decode(Buffer):
 * loop reading 1-byte opcodes until 0, dispatching each.
 */
export function decodeObjType530(data: Uint8Array, id: number): ObjType530Data {
    const o = makeDefault(id);
    if (!data || data.byteLength === 0) return o;
    const r = new ObjReader(data);
    while (r.pos < data.byteLength) {
        const op = r.g1();
        if (op === 0) break;
        decodeOp(r, op, o);
    }
    return o;
}

/**
 * High-level loader that mirrors ObjTypeList.get() (without the cache, the
 * member-restriction shroud, and the cert/lent template merging — those are
 * the caller's responsibility, since the same generateCertificate / generateLent
 * logic also depends on a separate lookup of the linked obj id).
 *
 * Returns the parsed defn, or null if the cache doesn't have this id.
 *
 *   groupId = id >>> 8
 *   fileId  = id & 0xFF
 * Verified against rt4-client ObjTypeList.java (getGroupId/getFileId).
 */
export class ObjType530 {
    /** rt4-client puts ObjType data in idx19. */
    static readonly INDEX = 19;

    static getGroupId(objId: number): number { return objId >>> 8; }
    static getFileId(objId: number): number { return objId & 0xFF; }

    /**
     * Fetch + decode an item definition from the supplied 530 cache facade.
     * Returns null when the cache has no entry for this id (group missing,
     * file missing, or empty payload).
     *
     * NOTE: this does NOT yet apply ObjTypeList's certtemplate/lentTemplate
     * inheritance — callers that need the rendered cert version need to
     * re-load `certlink` and `certtemplate` and run the equivalent of
     * generateCertificate() themselves. That can be added once we wire this
     * into the existing ItemDefinition path.
     */
    static async load(js5Cache: Js5Cache, objId: number): Promise<ObjType530Data | null> {
        if (objId < 0) return null;
        const groupId = ObjType530.getGroupId(objId);
        const fileId = ObjType530.getFileId(objId);
        const bytes = await js5Cache.getFileBytes(ObjType530.INDEX, groupId, fileId);
        if (!bytes) return null;
        return decodeObjType530(bytes, objId);
    }
}
