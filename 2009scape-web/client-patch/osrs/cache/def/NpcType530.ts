/**
 * NpcType530 — TypeScript port of rt4-client's NpcType.java decode().
 *
 * Mirrors the rev-530 NPC definition byte format exactly. Each opcode handler
 * follows the deob's order and read sizes. If a byte goes wrong here, every NPC
 * decoded after the offending opcode in that file will be corrupt — so any
 * future tweak must keep parity with NpcType.java.
 *
 * Source of truth:
 *   reference/rt4-client/client/src/main/java/rt4/NpcType.java        (decode opcodes)
 *   reference/rt4-client/client/src/main/java/rt4/NpcTypeList.java    (idx layout)
 *   reference/rt4-client/client/src/main/java/rt4/client.java         (archive wiring)
 *
 * 530 NPC definitions live in idx18. NpcTypeList resolves a flat NPC id to:
 *   groupId = id >>> 7
 *   fileId  = id & 0x7F
 * i.e. 128 NPCs per group, multi-file group with one file per NPC.
 * Npc model ids referenced by opcode 1 still point at idx7.
 *
 * Use Js5Cache.getFileBytes(7, groupId, fileId) to fetch the bytes; the
 * Js5Group unpack already happens inside that helper.
 *
 * This module is intentionally self-contained — it imports only Js5Cache for
 * cache fetches, and does not touch the in-tree (377-era) Buffer class. The
 * rt4 Buffer read primitives (g1/g1b/g2/g3/g4/gjstr) are inlined here against
 * a plain Uint8Array, exactly matching rt4 byte order.
 */

import { Js5Cache } from "../../Js5Cache";

// ── Inlined rt4 Buffer reader (Uint8Array-backed) ──
class NpcReader {
    public buf: Uint8Array;
    public pos: number;

    constructor(buf: Uint8Array) {
        this.buf = buf;
        this.pos = 0;
    }

    /** Unsigned byte (rt4 Buffer.g1). */
    g1(): number {
        return this.buf[this.pos++] & 0xFF;
    }

    /** Signed byte (rt4 Buffer.g1b). */
    g1b(): number {
        const b = this.buf[this.pos++];
        return (b << 24) >> 24;
    }

    /** Unsigned 16-bit big-endian (rt4 Buffer.g2). */
    g2(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        return (a << 8) | b;
    }

    /** Unsigned 24-bit big-endian (rt4 Buffer.g3). Used for param keys. */
    g3(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        const c = this.buf[this.pos++] & 0xFF;
        return ((a << 16) | (b << 8) | c) >>> 0;
    }

    /** Signed 32-bit big-endian (rt4 Buffer.g4). */
    g4(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        const c = this.buf[this.pos++] & 0xFF;
        const d = this.buf[this.pos++] & 0xFF;
        return ((a << 24) | (b << 16) | (c << 8) | d) | 0;
    }

    /** NUL-terminated ASCII string (rt4 Buffer.gjstr). */
    gjstr(): string {
        let s = "";
        const end = this.buf.length;
        while (this.pos < end && this.buf[this.pos] !== 0) {
            s += String.fromCharCode(this.buf[this.pos++] & 0xFF);
        }
        if (this.pos < end) this.pos++; // consume NUL
        return s;
    }
}

/** A single param entry from opcode 249. Either an int or a string. */
export interface NpcParam {
    key: number;
    isString: boolean;
    intValue?: number;
    stringValue?: string;
}

/** Strongly-typed shape of every field NpcType.java tracks. */
export interface NpcType530Data {
    id: number;

    // Models / display
    modelIndices: number[] | null;          // op 1
    headmodels: number[] | null;            // op 60
    modeloffsets: (number[] | null)[] | null; // op 121 — 3-tuples, sparse

    // Recolor / retexture
    recol_s: number[] | null;               // op 40 source colors
    recol_d: number[] | null;               // op 40 destination colors
    recol_p: number[] | null;               // op 42 palette indices (signed bytes)
    retex_s: number[] | null;               // op 41 source textures
    retex_d: number[] | null;               // op 41 destination textures

    // Identity
    name: string;                           // op 2
    combatLevel: number;                    // op 95
    size: number;                           // op 12
    ops: (string | null)[];                 // op 30..34

    // Render properties
    resizeX: number;                        // op 97
    resizeY: number;                        // op 98
    toprenderpriority: boolean;             // op 99
    ambient: number;                        // op 100
    contrast: number;                       // op 101 (already x5)
    headicon: number;                       // op 102
    rotationspeed: number;                  // op 103
    minimapdisplay: boolean;                // op 93
    interactive: boolean;                   // op 107
    rotationflag: boolean;                  // op 109
    hasshadow: boolean;                     // op 111
    shadowcolor1: number;                   // op 113
    shadowcolor2: number;                   // op 113
    shadowcolormodifier1: number;           // op 114 (signed)
    shadowcolormodifier2: number;           // op 114 (signed)
    loginscreenproperties: number;          // op 119 (signed)

    // Hit / interface
    hitBarId: number;                       // op 122
    iconHeight: number;                     // op 123
    spawndirection: number;                 // op 125 (signed)
    minimapmarkerobjectentry: number;       // op 126
    bastypeid: number;                      // op 127

    // Sounds (op 134)
    idleSound: number;
    crawlSound: number;
    walkSound: number;
    runSound: number;
    soundRadius: number;

    // Cursors
    cursor1Op: number;                      // op 135
    cursor1: number;                        // op 135
    cursor2Op: number;                      // op 136
    cursor2: number;                        // op 136
    attackCursor: number;                   // op 137

    // Multi-NPC variant table (ops 106 / 118)
    multiNpcVarbit: number;
    multiNpcVarp: number;
    multiNpcs: number[] | null;             // length = N+2; trailing entry is fallback id

    // Free-form params (op 249)
    params: Map<number, NpcParam> | null;
}

/**
 * Parsed rev-530 NPC definition. The fields map 1:1 onto NpcType.java.
 * Construct via NpcType530.load(cache, id) or new NpcType530() + decode().
 */
export class NpcType530 implements NpcType530Data {
    /** rt4 client wires NpcTypeList.init(models=idx7, archive=idx18). */
    public static readonly INDEX = 18;

    id: number = -1;

    modelIndices: number[] | null = null;
    headmodels: number[] | null = null;
    modeloffsets: (number[] | null)[] | null = null;

    recol_s: number[] | null = null;
    recol_d: number[] | null = null;
    recol_p: number[] | null = null;
    retex_s: number[] | null = null;
    retex_d: number[] | null = null;

    name: string = "null";
    combatLevel: number = -1;
    size: number = 1;
    ops: (string | null)[] = [null, null, null, null, null];

    resizeX: number = 128;
    resizeY: number = 128;
    toprenderpriority: boolean = false;
    ambient: number = 0;
    contrast: number = 0;
    headicon: number = -1;
    rotationspeed: number = 32;
    minimapdisplay: boolean = true;
    interactive: boolean = true;
    rotationflag: boolean = true;
    hasshadow: boolean = true;
    shadowcolor1: number = 0;
    shadowcolor2: number = 0;
    shadowcolormodifier1: number = -96;
    shadowcolormodifier2: number = -16;
    loginscreenproperties: number = 0;

    hitBarId: number = -1;
    iconHeight: number = -1;
    spawndirection: number = 7;
    minimapmarkerobjectentry: number = -1;
    bastypeid: number = -1;

    idleSound: number = -1;
    crawlSound: number = -1;
    walkSound: number = -1;
    runSound: number = -1;
    soundRadius: number = 0;

    cursor1Op: number = -1;
    cursor1: number = -1;
    cursor2Op: number = -1;
    cursor2: number = -1;
    attackCursor: number = -1;

    multiNpcVarbit: number = -1;
    multiNpcVarp: number = -1;
    multiNpcs: number[] | null = null;

    params: Map<number, NpcParam> | null = null;

    /**
     * Decode a 530-format NPC definition file. Mirrors NpcType.decode():
     *   while (true) { op = g1(); if (op === 0) break; this.decodeOp(op, buf); }
     */
    decode(buf: Uint8Array): void {
        const reader = new NpcReader(buf);
        while (true) {
            const opcode = reader.g1();
            if (opcode === 0) return;
            this.decodeOp(opcode, reader);
        }
    }

    /**
     * Per-opcode dispatch. Order, types, and read counts match
     * NpcType.java.decode(int, Buffer) — do NOT reorder reads or skip
     * unknown opcodes; either breaks alignment for every later opcode in
     * the file.
     */
    private decodeOp(opcode: number, r: NpcReader): void {
        let count: number;
        let i: number;

        if (opcode === 1) {
            // Body model indices (g2 each, 65535 → -1).
            count = r.g1();
            this.modelIndices = new Array(count);
            for (i = 0; i < count; i++) {
                let mid = r.g2();
                if (mid === 65535) mid = -1;
                this.modelIndices[i] = mid;
            }
        } else if (opcode === 2) {
            this.name = r.gjstr();
        } else if (opcode === 12) {
            this.size = r.g1();
        } else if (opcode >= 30 && opcode < 35) {
            // Right-click options 0..4
            const op = r.gjstr();
            // The rt4 client compares against LocalizedText.HIDDEN. For our
            // purposes we treat the literal "hidden" (case-insensitive) as
            // a sentinel meaning "no option here".
            this.ops[opcode - 30] = op.toLowerCase() === "hidden" ? null : op;
        } else if (opcode === 40) {
            // Recolor table (source → dest)
            count = r.g1();
            this.recol_s = new Array(count);
            this.recol_d = new Array(count);
            for (i = 0; i < count; i++) {
                this.recol_s[i] = r.g2();
                this.recol_d[i] = r.g2();
            }
        } else if (opcode === 41) {
            // Retexture table
            count = r.g1();
            this.retex_s = new Array(count);
            this.retex_d = new Array(count);
            for (i = 0; i < count; i++) {
                this.retex_s[i] = r.g2();
                this.retex_d[i] = r.g2();
            }
        } else if (opcode === 42) {
            // Palette recolor mask (signed bytes)
            count = r.g1();
            this.recol_p = new Array(count);
            for (i = 0; i < count; i++) {
                this.recol_p[i] = r.g1b();
            }
        } else if (opcode === 60) {
            // Head model indices
            count = r.g1();
            this.headmodels = new Array(count);
            for (i = 0; i < count; i++) {
                this.headmodels[i] = r.g2();
            }
        } else if (opcode === 93) {
            this.minimapdisplay = false;
        } else if (opcode === 95) {
            this.combatLevel = r.g2();
        } else if (opcode === 97) {
            this.resizeX = r.g2();
        } else if (opcode === 98) {
            this.resizeY = r.g2();
        } else if (opcode === 99) {
            this.toprenderpriority = true;
        } else if (opcode === 100) {
            this.ambient = r.g1b();
        } else if (opcode === 101) {
            // rt4 stores contrast pre-multiplied by 5 (see NpcType.java line 637).
            this.contrast = r.g1b() * 5;
        } else if (opcode === 102) {
            this.headicon = r.g2();
        } else if (opcode === 103) {
            this.rotationspeed = r.g2();
        } else if (opcode === 106 || opcode === 118) {
            // Multi-NPC variant table.
            //   op 106: varbit, varp, length, ids[length+1]
            //   op 118: varbit, varp, defaultId, length, ids[length+1]
            // multiNpcs[length+1] holds the fallback id (defaultId for op 118,
            //   -1 for op 106). Total array size = length + 2.
            this.multiNpcVarbit = r.g2();
            if (this.multiNpcVarbit === 65535) this.multiNpcVarbit = -1;
            this.multiNpcVarp = r.g2();
            if (this.multiNpcVarp === 65535) this.multiNpcVarp = -1;
            let fallback = -1;
            if (opcode === 118) {
                fallback = r.g2();
                if (fallback === 65535) fallback = -1;
            }
            const last = r.g1();
            this.multiNpcs = new Array(last + 2);
            for (let local = 0; local <= last; local++) {
                let mid = r.g2();
                if (mid === 65535) mid = -1;
                this.multiNpcs[local] = mid;
            }
            this.multiNpcs[last + 1] = fallback;
        } else if (opcode === 107) {
            this.interactive = false;
        } else if (opcode === 109) {
            this.rotationflag = false;
        } else if (opcode === 111) {
            this.hasshadow = false;
        } else if (opcode === 113) {
            // Two shadow colors stored as signed shorts in rt4
            // (cast back from g2). Stored unsigned here; downstream
            // consumers that need signed can `(v << 16) >> 16`.
            this.shadowcolor1 = r.g2();
            this.shadowcolor2 = r.g2();
        } else if (opcode === 114) {
            this.shadowcolormodifier1 = r.g1b();
            this.shadowcolormodifier2 = r.g1b();
        } else if (opcode === 115) {
            // rt4 reads 2 unused bytes; preserve byte alignment.
            r.g1();
            r.g1();
        } else if (opcode === 119) {
            this.loginscreenproperties = r.g1b();
        } else if (opcode === 121) {
            // Per-body-model offset table. Indexed by submodel slot.
            // Requires modelIndices to have already been read (op 1).
            const slots = this.modelIndices ? this.modelIndices.length : 0;
            this.modeloffsets = new Array(slots);
            for (i = 0; i < slots; i++) this.modeloffsets[i] = null;
            count = r.g1();
            for (i = 0; i < count; i++) {
                const slot = r.g1();
                const off = [r.g1b(), r.g1b(), r.g1b()];
                if (this.modeloffsets && slot < slots) {
                    this.modeloffsets[slot] = off;
                }
            }
        } else if (opcode === 122) {
            this.hitBarId = r.g2();
        } else if (opcode === 123) {
            this.iconHeight = r.g2();
        } else if (opcode === 125) {
            this.spawndirection = r.g1b();
        } else if (opcode === 126) {
            this.minimapmarkerobjectentry = r.g2();
        } else if (opcode === 127) {
            this.bastypeid = r.g2();
        } else if (opcode === 128) {
            // 1 unused byte in rt4 — keep alignment.
            r.g1();
        } else if (opcode === 134) {
            // Sound block.
            this.idleSound = r.g2();
            if (this.idleSound === 65535) this.idleSound = -1;
            this.crawlSound = r.g2();
            if (this.crawlSound === 65535) this.crawlSound = -1;
            this.walkSound = r.g2();
            if (this.walkSound === 65535) this.walkSound = -1;
            this.runSound = r.g2();
            if (this.runSound === 65535) this.runSound = -1;
            this.soundRadius = r.g1();
        } else if (opcode === 135) {
            this.cursor1Op = r.g1();
            this.cursor1 = r.g2();
        } else if (opcode === 136) {
            this.cursor2Op = r.g1();
            this.cursor2 = r.g2();
        } else if (opcode === 137) {
            this.attackCursor = r.g2();
        } else if (opcode === 138) {
            // Later rev-530 cache extension. This client has no mapped field
            // for the extra cursor/interface id, but it is a g2 in the data.
            r.g2();
        } else if (opcode === 159) {
            // Later rev-530 cache extension. Preserve stream alignment.
            r.g2();
        } else if (opcode === 249) {
            // Free-form parameter table.
            //   count        g1
            //   for each:    type(g1: 1=string, 0=int), key(g3), value(gjstr|g4)
            count = r.g1();
            if (this.params === null) this.params = new Map<number, NpcParam>();
            for (i = 0; i < count; i++) {
                const isString = r.g1() === 1;
                const key = r.g3();
                if (isString) {
                    const stringValue = r.gjstr();
                    this.params.set(key, { key: key, isString: true, stringValue: stringValue });
                } else {
                    const intValue = r.g4();
                    this.params.set(key, { key: key, isString: false, intValue: intValue });
                }
            }
        } else {
            // Unknown opcode — rt4 silently no-ops here, but since we don't
            // know the byte width we cannot safely advance the cursor. This
            // means *every* later opcode in the file will read garbage. The
            // only correct response when this fires in production is "log
            // it, accept the def is partly populated, stop decoding".
            // Mirror the deob's behaviour by stopping early instead of
            // looping forever on bad data.
            // eslint-disable-next-line no-console
            console.warn("[NpcType530] unknown opcode " + opcode + " at pos " + r.pos + " — aborting decode for npc " + this.id);
            // Move cursor to end so the outer loop sees op=0 (or runs out).
            r.pos = r.buf.length;
        }
    }

    /**
     * Resolve and decode a 530 NPC by its flat id.
     *
     * NpcTypeList.java idx mapping (rt4):
     *   archive = idx18
     *   group = id >>> 7
     *   file  = id & 0x7F
     * Returns null if the cache is missing the group or the file is empty.
     */
    static async load(cache: Js5Cache, npcId: number): Promise<NpcType530 | null> {
        if (npcId < 0) return null;
        const groupId = npcId >>> 7;
        const fileId = npcId & 0x7F;
        const data = await cache.getFileBytes(NpcType530.INDEX, groupId, fileId);
        if (!data || data.byteLength === 0) return null;
        const npc = new NpcType530();
        npc.id = npcId;
        npc.decode(data);
        return npc;
    }

    /**
     * Lookup an int param with a default fallback. Mirrors NpcType.getParam(int, int).
     */
    getIntParam(key: number, fallback: number): number {
        if (!this.params) return fallback;
        const p = this.params.get(key);
        if (!p || p.isString) return fallback;
        return p.intValue !== undefined ? p.intValue : fallback;
    }

    /**
     * Lookup a string param with a default fallback.
     * Mirrors NpcType.getParam(int, JagString).
     */
    getStringParam(key: number, fallback: string): string {
        if (!this.params) return fallback;
        const p = this.params.get(key);
        if (!p || !p.isString) return fallback;
        return p.stringValue !== undefined ? p.stringValue : fallback;
    }
}
