/**
 * ParamType530 — TypeScript port of rt4-client ParamType.java.
 *
 * Params are tiny key/value descriptors used by ObjType / NpcType / LocType
 * to attach typed extra data without bloating the parent record. Each param
 * record is just a type tag (with one sentinel — type 115 means "string")
 * plus an optional default int and an optional default string.
 *
 * Source of truth:
 *   reference/rt4-client/client/src/main/java/rt4/ParamType.java
 *   reference/rt4-client/client/src/main/java/rt4/ParamTypeList.java
 *
 * Cache layout (per ParamTypeList.get):
 *   idx2, group = 11, file = id
 *   (init at client.java:1540 — ParamTypeList.init(js5Archive2),
 *    js5Archive2 = createJs5(idx 2)).
 */

import { Js5Cache } from "../../Js5Cache";

class ParamReader {
    public buf: Uint8Array;
    public pos: number;
    constructor(buf: Uint8Array, pos: number = 0) { this.buf = buf; this.pos = pos; }
    g1(): number { return this.buf[this.pos++] & 0xFF; }
    g4(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        const c = this.buf[this.pos++] & 0xFF;
        const d = this.buf[this.pos++] & 0xFF;
        return ((a << 24) | (b << 16) | (c << 8) | d) | 0;
    }
    gjstr(): string {
        let s = "";
        while (this.pos < this.buf.length && this.buf[this.pos] !== 0) {
            s += String.fromCharCode(this.buf[this.pos++] & 0xFF);
        }
        if (this.pos < this.buf.length) this.pos++;
        return s;
    }
}

export interface ParamType530Data {
    id: number;
    /** Type tag; 115 means "string-typed param", anything else is int. op 1 */
    type: number;
    /** Default integer value when no override is supplied. op 2 */
    defaultInt: number;
    /** Default string when isString() is true and no override is supplied. op 5 */
    defaultString: string | null;
    /** Convenience: type === 115 (the rt4 "is a string param" predicate). */
    isString: boolean;
}

function makeDefault(id: number): ParamType530Data {
    return { id, type: 0, defaultInt: 0, defaultString: null, isString: false };
}

function decodeOpcode(out: ParamType530Data, opcode: number, r: ParamReader): void {
    if (opcode === 1) out.type = r.g1();
    else if (opcode === 2) out.defaultInt = r.g4();
    else if (opcode === 5) out.defaultString = r.gjstr();
    else {
        console.warn("[ParamType530] unknown opcode " + opcode + " — aborting decode for param " + out.id);
    }
}

function decode(data: Uint8Array, id: number): ParamType530Data {
    const out = makeDefault(id);
    if (!data || data.byteLength === 0) return out;
    const r = new ParamReader(data);
    while (r.pos < r.buf.byteLength) {
        const opcode = r.g1();
        if (opcode === 0) break;
        decodeOpcode(out, opcode, r);
    }
    out.isString = out.type === 115;
    return out;
}

export class ParamType530 {
    public static readonly INDEX = 2;
    public static readonly GROUP = 11;
    static decode(data: Uint8Array, id: number): ParamType530Data { return decode(data, id); }
    static async load(js5Cache: Js5Cache, id: number): Promise<ParamType530Data | null> {
        if (id < 0) return null;
        const data = await js5Cache.getFileBytes(ParamType530.INDEX, ParamType530.GROUP, id);
        if (!data || data.byteLength === 0) return null;
        return decode(data, id);
    }
}
