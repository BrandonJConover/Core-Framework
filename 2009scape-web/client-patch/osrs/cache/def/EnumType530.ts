/**
 * EnumType530 — TypeScript port of rt4-client EnumType.java.
 *
 * An enum is a typed key→value map with both a key-type tag and a value-
 * type tag. CS2 scripts use enums heavily for ad-hoc lookup tables (eg.
 * skill→cape mapping, combat-style→anim, dialogue branch tables).
 *
 * Two table flavours selected by the per-table opcode:
 *   opcode 5: keys are int, values are strings
 *   opcode 6: keys are int, values are ints
 * Either way the file holds at most ONE table block.
 *
 * Source of truth:
 *   reference/rt4-client/client/src/main/java/rt4/EnumType.java
 *   reference/rt4-client/client/src/main/java/rt4/EnumTypeList.java
 *
 * Cache layout (per EnumTypeList.get + getGroupId/getFileId):
 *   idx17, group = id >>> 8, file = id & 0xFF
 *   (init at client.java:1555 — EnumTypeList.init(js5Archive17)).
 */

import { Js5Cache } from "../../Js5Cache";

class EnumReader {
    public buf: Uint8Array;
    public pos: number;
    constructor(buf: Uint8Array, pos: number = 0) { this.buf = buf; this.pos = pos; }
    g1(): number { return this.buf[this.pos++] & 0xFF; }
    g2(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        return (a << 8) | b;
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

export interface EnumType530Data {
    id: number;
    /** Key type tag (rt4 char-style code: 'i' = 105 etc.). op 1 */
    keyType: number;
    /** Value type tag (115 = string, others = int). op 2 */
    valueType: number;
    /** Default string when looked up key is missing and value is a string. op 3 */
    defaultString: string;
    /** Default int when looked up key is missing and value is an int. op 4 */
    defaultInt: number;
    /**
     * Decoded table. null when no op-5/op-6 block. Keys are always int.
     * Values are string when valueIsString === true, otherwise int.
     */
    intToString: Map<number, string> | null;
    intToInt: Map<number, number> | null;
    /** Convenience: matches whether op 5 (string-valued) was the table type. */
    valueIsString: boolean;
}

function makeDefault(id: number): EnumType530Data {
    return {
        id,
        keyType: 0,
        valueType: 0,
        defaultString: "null",
        defaultInt: 0,
        intToString: null,
        intToInt: null,
        valueIsString: false,
    };
}

function decode(data: Uint8Array, id: number): EnumType530Data {
    const out = makeDefault(id);
    if (!data || data.byteLength === 0) return out;
    const r = new EnumReader(data);
    while (r.pos < r.buf.byteLength) {
        const opcode = r.g1();
        if (opcode === 0) break;
        if (opcode === 1) {
            out.keyType = r.g1();
        } else if (opcode === 2) {
            out.valueType = r.g1();
        } else if (opcode === 3) {
            out.defaultString = r.gjstr();
        } else if (opcode === 4) {
            out.defaultInt = r.g4();
        } else if (opcode === 5 || opcode === 6) {
            const size = r.g2();
            if (opcode === 5) {
                const m = new Map<number, string>();
                for (let i = 0; i < size; i++) {
                    const k = r.g4();
                    const v = r.gjstr();
                    m.set(k, v);
                }
                out.intToString = m;
                out.valueIsString = true;
            } else {
                const m = new Map<number, number>();
                for (let i = 0; i < size; i++) {
                    const k = r.g4();
                    const v = r.g4();
                    m.set(k, v);
                }
                out.intToInt = m;
                out.valueIsString = false;
            }
        } else {
            console.warn("[EnumType530] unknown opcode " + opcode + " — aborting decode for enum " + id);
        }
    }
    return out;
}

/** Lookup helper for string-valued enums. */
export function enumGetString(e: EnumType530Data, key: number): string {
    if (!e.intToString) return e.defaultString;
    const v = e.intToString.get(key);
    return v === undefined ? e.defaultString : v;
}

/** Lookup helper for int-valued enums. */
export function enumGetInt(e: EnumType530Data, key: number): number {
    if (!e.intToInt) return e.defaultInt;
    const v = e.intToInt.get(key);
    return v === undefined ? e.defaultInt : v;
}

export class EnumType530 {
    public static readonly INDEX = 17;
    static decode(data: Uint8Array, id: number): EnumType530Data { return decode(data, id); }
    static async load(js5Cache: Js5Cache, id: number): Promise<EnumType530Data | null> {
        if (id < 0) return null;
        const groupId = id >>> 8;
        const fileId = id & 0xFF;
        const data = await js5Cache.getFileBytes(EnumType530.INDEX, groupId, fileId);
        if (!data || data.byteLength === 0) return null;
        return decode(data, id);
    }
}
