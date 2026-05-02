/**
 * SpotAnimType530 — TypeScript port of rt4-client SpotAnimType.java.
 *
 * "Spot animations" are world-anchored fx (curse-cast splashes, hit
 * impacts, prayer sparkles, teleport flashes, etc.). Each entry holds
 * a model id, an optional anim sequence id, color/texture replacement
 * tables, plus pose tweaks.
 *
 * Source of truth:
 *   reference/rt4-client/client/src/main/java/rt4/SpotAnimType.java
 *   reference/rt4-client/client/src/main/java/rt4/SpotAnimTypeList.java
 *
 * Cache layout (per SpotAnimTypeList.get + method3681/method4010):
 *   idx21, group = id >>> 8, file = id & 0xFF
 *   (init at client.java:1550 — `js5Archive21` is `archive` arg).
 */

import { Js5Cache } from "../../Js5Cache";

class SpotReader {
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

export interface SpotAnimType530Data {
    id: number;
    modelId: number;       // op 1
    seqId: number;         // op 2 default -1
    resizeXZ: number;      // op 4 default 128
    resizeY: number;       // op 5 default 128
    angle: number;         // op 6 default 0
    ambient: number;       // op 7
    contrast: number;      // op 8
    aBoolean100: boolean;  // op 9

    /** op 40 — color replacement (signed shorts). null when unset. */
    recol_s: number[] | null;
    recol_d: number[] | null;
    /** op 41 — texture replacement (signed shorts). null when unset. */
    retex_s: number[] | null;
    retex_d: number[] | null;
}

function makeDefault(id: number): SpotAnimType530Data {
    return {
        id,
        modelId: -1,
        seqId: -1,
        resizeXZ: 128,
        resizeY: 128,
        angle: 0,
        ambient: 0,
        contrast: 0,
        aBoolean100: false,
        recol_s: null,
        recol_d: null,
        retex_s: null,
        retex_d: null,
    };
}

function decode(data: Uint8Array, id: number): SpotAnimType530Data {
    const out = makeDefault(id);
    if (!data || data.byteLength === 0) return out;
    const r = new SpotReader(data);
    while (r.pos < r.buf.byteLength) {
        const opcode = r.g1();
        if (opcode === 0) break;
        decodeOpcode(out, opcode, r);
    }
    return out;
}

function signedShort(v: number): number {
    v &= 0xFFFF;
    return v >= 0x8000 ? v - 0x10000 : v;
}

function decodeOpcode(out: SpotAnimType530Data, opcode: number, r: SpotReader): void {
    if (opcode === 1) out.modelId = r.g2();
    else if (opcode === 2) out.seqId = r.g2();
    else if (opcode === 4) out.resizeXZ = r.g2();
    else if (opcode === 5) out.resizeY = r.g2();
    else if (opcode === 6) out.angle = r.g2();
    else if (opcode === 7) out.ambient = r.g1();
    else if (opcode === 8) out.contrast = r.g1();
    else if (opcode === 9) out.aBoolean100 = true;
    else if (opcode === 40) {
        const size = r.g1();
        const s: number[] = [];
        const d: number[] = [];
        for (let i = 0; i < size; i++) { s.push(signedShort(r.g2())); d.push(signedShort(r.g2())); }
        out.recol_s = s;
        out.recol_d = d;
    } else if (opcode === 41) {
        const size = r.g1();
        const s: number[] = [];
        const d: number[] = [];
        for (let i = 0; i < size; i++) { s.push(signedShort(r.g2())); d.push(signedShort(r.g2())); }
        out.retex_s = s;
        out.retex_d = d;
    } else {
        console.warn("[SpotAnimType530] unknown opcode " + opcode + " — aborting decode for spot " + out.id);
    }
}

export class SpotAnimType530 {
    public static readonly INDEX = 21;
    static decode(data: Uint8Array, id: number): SpotAnimType530Data { return decode(data, id); }
    static async load(js5Cache: Js5Cache, id: number): Promise<SpotAnimType530Data | null> {
        if (id < 0) return null;
        const groupId = id >>> 8;
        const fileId = id & 0xFF;
        const data = await js5Cache.getFileBytes(SpotAnimType530.INDEX, groupId, fileId);
        if (!data || data.byteLength === 0) return null;
        return decode(data, id);
    }
}
