/**
 * SeqType530 — TypeScript port of rt4-client SeqType.java.
 *
 * Animation sequences. NpcType530.bastypeid → BasType530 → walk/idle anim
 * IDs that are SeqType ids; SpotAnimType530.seqId is also a SeqType id.
 * The decoded record holds frame ids + per-frame delays + sound effects
 * + loop/move metadata.
 *
 * Source of truth:
 *   reference/rt4-client/client/src/main/java/rt4/SeqType.java
 *   reference/rt4-client/client/src/main/java/rt4/SeqTypeList.java
 *
 * Cache layout (per SeqTypeList.get + getGroupId/getFileId):
 *   idx20, group = id >>> 7, file = id & 0x7F
 *   (init at client.java:1548 — `js5Archive20` is `archive` arg).
 */

import { Js5Cache } from "../../Js5Cache";

class SeqReader {
    public buf: Uint8Array;
    public pos: number;
    constructor(buf: Uint8Array, pos: number = 0) { this.buf = buf; this.pos = pos; }
    g1(): number { return this.buf[this.pos++] & 0xFF; }
    g2(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        return (a << 8) | b;
    }
    g3(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        const c = this.buf[this.pos++] & 0xFF;
        return ((a << 16) | (b << 8) | c) >>> 0;
    }
}

export interface SeqType530Data {
    id: number;

    /** Per-frame: high 16 bits = AnimFrameset id, low 16 bits = frame within frameset. */
    frames: number[] | null;        // op 1
    /** Per-frame delay in client ticks. */
    frameDelay: number[] | null;    // op 1
    /** Optional secondary frameset (for compound transforms). */
    frameset: number[] | null;      // op 12

    /** Per-frame group flags (for transitions). null when unset. */
    framegroup: boolean[] | null;   // op 3

    replayoff: number;              // op 2
    priority: number;               // op 5  default 5
    mainhand: number;               // op 6
    offhand: number;                // op 7
    replaycount: number;            // op 8  default 99
    looptype: number;               // op 9  default -1 → 0/2 in postDecode
    movetype: number;               // op 10 default -1 → 0/2 in postDecode
    exactmove: number;              // op 11 default 2

    soundeffect: (number[] | null)[] | null; // op 13: per-frame [soundId(g3), then count-1 g2 entries]

    aBoolean278: boolean;           // op 14
    tween: boolean;                 // op 15
    aBoolean280: boolean;           // op 16
    stretches: boolean;             // op 4
}

function makeDefault(id: number): SeqType530Data {
    return {
        id,
        frames: null,
        frameDelay: null,
        frameset: null,
        framegroup: null,
        replayoff: -1,
        priority: 5,
        mainhand: -1,
        offhand: -1,
        replaycount: 99,
        looptype: -1,
        movetype: -1,
        exactmove: 2,
        soundeffect: null,
        aBoolean278: false,
        tween: false,
        aBoolean280: false,
        stretches: false,
    };
}

function decode(data: Uint8Array, id: number): SeqType530Data {
    const out = makeDefault(id);
    if (!data || data.byteLength === 0) {
        postDecode(out);
        return out;
    }
    const r = new SeqReader(data);
    while (r.pos < r.buf.byteLength) {
        const opcode = r.g1();
        if (opcode === 0) break;
        decodeOpcode(out, opcode, r);
    }
    postDecode(out);
    return out;
}

function decodeOpcode(out: SeqType530Data, opcode: number, r: SeqReader): void {
    if (opcode === 1) {
        const count = r.g2();
        const frameDelay: number[] = [];
        for (let i = 0; i < count; i++) frameDelay.push(r.g2());
        const frames: number[] = [];
        for (let i = 0; i < count; i++) frames.push(r.g2());
        for (let i = 0; i < count; i++) frames[i] += r.g2() << 16;
        out.frameDelay = frameDelay;
        out.frames = frames;
    } else if (opcode === 2) {
        out.replayoff = r.g2();
    } else if (opcode === 3) {
        const count = r.g1();
        const fg: boolean[] = [];
        for (let i = 0; i < 256; i++) fg.push(false);
        for (let i = 0; i < count; i++) fg[r.g1()] = true;
        out.framegroup = fg;
    } else if (opcode === 4) {
        out.stretches = true;
    } else if (opcode === 5) {
        out.priority = r.g1();
    } else if (opcode === 6) {
        out.mainhand = r.g2();
    } else if (opcode === 7) {
        out.offhand = r.g2();
    } else if (opcode === 8) {
        out.replaycount = r.g1();
    } else if (opcode === 9) {
        out.looptype = r.g1();
    } else if (opcode === 10) {
        out.movetype = r.g1();
    } else if (opcode === 11) {
        out.exactmove = r.g1();
    } else if (opcode === 12) {
        const count = r.g1();
        const fs: number[] = [];
        for (let i = 0; i < count; i++) fs.push(r.g2());
        for (let i = 0; i < count; i++) fs[i] += r.g2() << 16;
        out.frameset = fs;
    } else if (opcode === 13) {
        const count = r.g2();
        const se: (number[] | null)[] = [];
        for (let i = 0; i < count; i++) {
            const c2 = r.g1();
            if (c2 > 0) {
                const arr: number[] = [r.g3()];
                for (let j = 1; j < c2; j++) arr.push(r.g2());
                se.push(arr);
            } else {
                se.push(null);
            }
        }
        out.soundeffect = se;
    } else if (opcode === 14) {
        out.aBoolean278 = true;
    } else if (opcode === 15) {
        out.tween = true;
    } else if (opcode === 16) {
        out.aBoolean280 = true;
    } else {
        console.warn("[SeqType530] unknown opcode " + opcode + " — aborting decode for seq " + out.id);
    }
}

function postDecode(out: SeqType530Data): void {
    if (out.looptype === -1) out.looptype = out.framegroup == null ? 0 : 2;
    if (out.movetype === -1) out.movetype = out.framegroup == null ? 0 : 2;
}

export class SeqType530 {
    public static readonly INDEX = 20;
    static decode(data: Uint8Array, id: number): SeqType530Data { return decode(data, id); }
    static async load(js5Cache: Js5Cache, id: number): Promise<SeqType530Data | null> {
        if (id < 0) return null;
        const groupId = id >>> 7;
        const fileId = id & 0x7F;
        const data = await js5Cache.getFileBytes(SeqType530.INDEX, groupId, fileId);
        if (!data || data.byteLength === 0) return null;
        return decode(data, id);
    }
}
