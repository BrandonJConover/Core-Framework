/**
 * StructType530 — TypeScript port of rt4-client StructType.java.
 *
 * A struct is an indirection record: a sparse table of params whose keys
 * are 24-bit ParamType ids and whose values are either ints or strings.
 * EnumType / ObjType / NpcType lookups occasionally indirect through a
 * StructType so that several records can share an override map.
 *
 * Source of truth:
 *   reference/rt4-client/client/src/main/java/rt4/StructType.java
 *   reference/rt4-client/client/src/main/java/rt4/StructTypeList.java
 *
 * Cache layout (per StructTypeList.get):
 *   idx2, group = 26, file = id
 *   (init at client.java:1547 — StructTypeList.init(js5Archive2)).
 */

import { Js5Cache } from "../../Js5Cache";

class StructReader {
    public buf: Uint8Array;
    public pos: number;
    constructor(buf: Uint8Array, pos: number = 0) { this.buf = buf; this.pos = pos; }
    g1(): number { return this.buf[this.pos++] & 0xFF; }
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
    gjstr(): string {
        let s = "";
        while (this.pos < this.buf.length && this.buf[this.pos] !== 0) {
            s += String.fromCharCode(this.buf[this.pos++] & 0xFF);
        }
        if (this.pos < this.buf.length) this.pos++;
        return s;
    }
}

/** Single entry from the param table (opcode 249). */
export interface StructParam {
    /** 24-bit ParamType id used as the lookup key. */
    key: number;
    /** When true, value is a string; otherwise it's an int. */
    isString: boolean;
    intValue?: number;
    stringValue?: string;
}

export interface StructType530Data {
    id: number;
    /** Param overrides, keyed by ParamType id. null when no opcode-249 block. */
    params: StructParam[] | null;
}

function decode(data: Uint8Array, id: number): StructType530Data {
    const out: StructType530Data = { id, params: null };
    if (!data || data.byteLength === 0) return out;
    const r = new StructReader(data);
    while (r.pos < r.buf.byteLength) {
        const opcode = r.g1();
        if (opcode === 0) break;
        if (opcode === 249) {
            const count = r.g1();
            const list: StructParam[] = [];
            for (let i = 0; i < count; i++) {
                const isString = r.g1() === 1;
                const key = r.g3();
                if (isString) {
                    list.push({ key, isString: true, stringValue: r.gjstr() });
                } else {
                    list.push({ key, isString: false, intValue: r.g4() });
                }
            }
            out.params = list;
        } else {
            console.warn("[StructType530] unknown opcode " + opcode + " — aborting decode for struct " + id);
        }
    }
    return out;
}

/** Look up a param int by key. Returns the supplied default when missing. */
export function structGetInt(s: StructType530Data, key: number, def: number): number {
    if (!s.params) return def;
    for (const p of s.params) {
        if (p.key === key && !p.isString) return p.intValue!;
    }
    return def;
}

/** Look up a param string by key. Returns the supplied default when missing. */
export function structGetString(s: StructType530Data, key: number, def: string): string {
    if (!s.params) return def;
    for (const p of s.params) {
        if (p.key === key && p.isString) return p.stringValue!;
    }
    return def;
}

export class StructType530 {
    public static readonly INDEX = 2;
    public static readonly GROUP = 26;
    static decode(data: Uint8Array, id: number): StructType530Data { return decode(data, id); }
    static async load(js5Cache: Js5Cache, id: number): Promise<StructType530Data | null> {
        if (id < 0) return null;
        const data = await js5Cache.getFileBytes(StructType530.INDEX, StructType530.GROUP, id);
        if (!data || data.byteLength === 0) return null;
        return decode(data, id);
    }
}
