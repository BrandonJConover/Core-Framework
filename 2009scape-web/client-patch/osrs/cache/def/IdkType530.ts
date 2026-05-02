/**
 * IdkType530 — TypeScript port of rt4-client IdkType.java.
 *
 * Identity-kit records: per-feature wardrobe pieces a player can equip
 * (head, hair, jaw, torso, arms, legs, hands, feet). Each record holds
 * up to 5 head-model ids + a body model array + recolor / retexture
 * tables, so the avatar renderer can stitch a player together at login.
 *
 * Source of truth:
 *   reference/rt4-client/client/src/main/java/rt4/IdkType.java
 *   reference/rt4-client/client/src/main/java/rt4/IdkTypeList.java
 *
 * Cache layout (per IdkTypeList.get):
 *   idx2, group = 3, file = id
 *   (init at client.java:1543 — IdkTypeList.init(js5Archive7, js5Archive2)).
 *
 * Note: the model bytes themselves come from idx7 (the modelsArchive arg);
 * this port only decodes the IdkType *definition*. RawModel530.load gates
 * actual mesh fetches.
 */

import { Js5Cache } from "../../Js5Cache";

class IdkReader {
    public buf: Uint8Array;
    public pos: number;
    constructor(buf: Uint8Array, pos: number = 0) { this.buf = buf; this.pos = pos; }
    g1(): number { return this.buf[this.pos++] & 0xFF; }
    g2(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        return (a << 8) | b;
    }
}

function signedShort(v: number): number {
    v &= 0xFFFF;
    return v >= 0x8000 ? v - 0x10000 : v;
}

export interface IdkType530Data {
    id: number;
    /** Wardrobe slot tag. op 1 — default -1. */
    feature: number;
    /** When true the entry is hidden from the design booth. op 3 */
    disable: boolean;
    /** Body model ids (idx7). op 2 — null when none. */
    bodyModels: number[] | null;
    /** Up to 5 head model ids. ops 60..64 (also 65..69 reserved). -1 when unset. */
    headModels: number[];
    /** Color replacement source/destination shorts. op 40 */
    recol_s: number[] | null;
    recol_d: number[] | null;
    /** Texture replacement source/destination shorts. op 41 */
    retex_s: number[] | null;
    retex_d: number[] | null;
}

function makeDefault(id: number): IdkType530Data {
    return {
        id,
        feature: -1,
        disable: false,
        bodyModels: null,
        headModels: [-1, -1, -1, -1, -1],
        recol_s: null,
        recol_d: null,
        retex_s: null,
        retex_d: null,
    };
}

function decodeOpcode(out: IdkType530Data, opcode: number, r: IdkReader): void {
    if (opcode === 1) {
        out.feature = r.g1();
    } else if (opcode === 2) {
        const count = r.g1();
        const m: number[] = [];
        for (let i = 0; i < count; i++) m.push(r.g2());
        out.bodyModels = m;
    } else if (opcode === 3) {
        out.disable = true;
    } else if (opcode === 40) {
        const count = r.g1();
        const s: number[] = [];
        const d: number[] = [];
        for (let i = 0; i < count; i++) { s.push(signedShort(r.g2())); d.push(signedShort(r.g2())); }
        out.recol_s = s;
        out.recol_d = d;
    } else if (opcode === 41) {
        const count = r.g1();
        const s: number[] = [];
        const d: number[] = [];
        for (let i = 0; i < count; i++) { s.push(signedShort(r.g2())); d.push(signedShort(r.g2())); }
        out.retex_s = s;
        out.retex_d = d;
    } else if (opcode >= 60 && opcode < 70) {
        const idx = opcode - 60;
        if (idx < out.headModels.length) {
            out.headModels[idx] = r.g2();
        } else {
            // rt4 only allocates 5 slots — opcodes 65..69 are observed but
            // discarded on the same `head[opcode-60]` write that would index
            // out of bounds. Skip to stay byte-compatible.
            r.g2();
        }
    } else {
        console.warn("[IdkType530] unknown opcode " + opcode + " — aborting decode for idk " + out.id);
    }
}

function decode(data: Uint8Array, id: number): IdkType530Data {
    const out = makeDefault(id);
    if (!data || data.byteLength === 0) return out;
    const r = new IdkReader(data);
    while (r.pos < r.buf.byteLength) {
        const opcode = r.g1();
        if (opcode === 0) break;
        decodeOpcode(out, opcode, r);
    }
    return out;
}

export class IdkType530 {
    public static readonly INDEX = 2;
    public static readonly GROUP = 3;
    static decode(data: Uint8Array, id: number): IdkType530Data { return decode(data, id); }
    static async load(js5Cache: Js5Cache, id: number): Promise<IdkType530Data | null> {
        if (id < 0) return null;
        const data = await js5Cache.getFileBytes(IdkType530.INDEX, IdkType530.GROUP, id);
        if (!data || data.byteLength === 0) return null;
        return decode(data, id);
    }
}
