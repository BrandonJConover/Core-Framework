/**
 * InvType530 — TypeScript port of rt4-client InvType.java.
 *
 * Describes an inventory container's capacity. Each record is a single
 * field: the size (slot count) of that inventory. Used by the interface
 * code to size grids for player inventory, bank, equipment, etc.
 *
 * Source of truth:
 *   reference/rt4-client/client/src/main/java/rt4/InvType.java
 *   reference/rt4-client/client/src/main/java/rt4/InvTypeList.java
 *
 * Cache layout (per InvTypeList.get):
 *   idx2, group = 5, file = id
 *   (init at client.java:1554 — InvTypeList.init(js5Archive2)).
 */

import { Js5Cache } from "../../Js5Cache";

class InvReader {
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

export interface InvType530Data {
    id: number;
    /** Inventory slot count. op 2 */
    size: number;
}

function decode(data: Uint8Array, id: number): InvType530Data {
    const out: InvType530Data = { id, size: 0 };
    if (!data || data.byteLength === 0) return out;
    const r = new InvReader(data);
    while (r.pos < r.buf.byteLength) {
        const opcode = r.g1();
        if (opcode === 0) break;
        if (opcode === 2) {
            out.size = r.g2();
        } else {
            console.warn("[InvType530] unknown opcode " + opcode + " — aborting decode for inv " + id);
        }
    }
    return out;
}

export class InvType530 {
    public static readonly INDEX = 2;
    public static readonly GROUP = 5;
    static decode(data: Uint8Array, id: number): InvType530Data { return decode(data, id); }
    static async load(js5Cache: Js5Cache, id: number): Promise<InvType530Data | null> {
        if (id < 0) return null;
        const data = await js5Cache.getFileBytes(InvType530.INDEX, InvType530.GROUP, id);
        if (!data || data.byteLength === 0) return null;
        return decode(data, id);
    }
}
