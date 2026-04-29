/**
 * BasType530 — TypeScript port of rt4-client BasType.java.
 *
 * Resolves the animation set + body-model rotation/translation table that
 * NpcType530.bastypeid (and the equivalent player record) points to.
 * Without this every NPC and the local player render with anim ids = -1
 * — visible but never walking, never idling, never turning.
 *
 * Source of truth:
 *   reference/rt4-client/client/src/main/java/rt4/BasType.java       (decode opcodes 1-45)
 *   reference/rt4-client/client/src/main/java/rt4/BasTypeList.java   (cache layout)
 *
 * Cache layout: idx2 ("configs"), group 32, file id = bas type id.
 * (BasTypeList.init at client.java:1549 takes js5Archive2; BasTypeList.get
 * fetches `archive.fetchFile(32, id)` at line 24.)
 */

import { Js5Cache } from "../../Js5Cache";

class BasReader {
    public buf: Uint8Array;
    public pos: number;

    constructor(buf: Uint8Array, pos: number = 0) {
        this.buf = buf;
        this.pos = pos;
    }

    g1(): number { return this.buf[this.pos++] & 0xFF; }
    g1b(): number { const b = this.buf[this.pos++]; return (b << 24) >> 24; }

    g2(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        return (a << 8) | b;
    }

    /** Signed 16-bit BE (rt4 Buffer.g2b). */
    g2b(): number {
        const v = this.g2();
        return v >= 0x8000 ? v - 0x10000 : v;
    }
}

export interface BasType530Data {
    id: number;

    /** Per-body-id [rotX, rotY, rotZ, transX, transY, transZ] (op 27). null when unset. */
    modelRotateTranslate: (number[] | null)[] | null;

    // Walk / idle (op 1)
    idleAnimationId: number;
    walkAnimation: number;

    // Slow walk (ops 2-5)
    slowWalkAnimationId: number;
    slowWalkFullTurnAnimationId: number;
    slowWalkCCWTurnAnimationId: number;
    slowWalkCWTurnAnimationId: number;

    // Run (ops 6-9)
    runAnimationId: number;
    runFullTurnAnimationId: number;
    runCCWTurnAnimationId: number;
    runCWTurnAnimationId: number;

    // Walk turn (ops 40-42)
    walkFullTurnAnimationId: number;
    walkCCWTurnAnimationId: number;
    walkCWTurnAnimationId: number;

    // Standing turn (ops 38-39)
    standingCCWTurn: number;
    standingCWTurn: number;

    // Movement physics (ops 26, 29-37)
    anInt1059: number;     // op 26 first byte * 4
    anInt1050: number;     // op 26 second byte * 4
    yawAcceleration: number;
    yawMaxSpeed: number;
    rollAcceleration: number;
    rollMaxSpeed: number;
    rollTargetAngle: number;
    pitchAcceleration: number;
    pitchMaxSpeed: number;
    pitchTargetAngle: number;
    movementAcceleration: number;
}

function makeDefault(id: number): BasType530Data {
    return {
        id,
        modelRotateTranslate: null,
        idleAnimationId: -1,
        walkAnimation: -1,
        slowWalkAnimationId: -1,
        slowWalkFullTurnAnimationId: -1,
        slowWalkCCWTurnAnimationId: -1,
        slowWalkCWTurnAnimationId: -1,
        runAnimationId: -1,
        runFullTurnAnimationId: -1,
        runCCWTurnAnimationId: -1,
        runCWTurnAnimationId: -1,
        walkFullTurnAnimationId: -1,
        walkCCWTurnAnimationId: -1,
        walkCWTurnAnimationId: -1,
        standingCCWTurn: -1,
        standingCWTurn: -1,
        anInt1059: 0,
        anInt1050: 0,
        yawAcceleration: 0,
        yawMaxSpeed: 0,
        rollAcceleration: 0,
        rollMaxSpeed: 0,
        rollTargetAngle: 0,
        pitchAcceleration: 0,
        pitchMaxSpeed: 0,
        pitchTargetAngle: 0,
        movementAcceleration: -1,
    };
}

function decode(data: Uint8Array, id: number): BasType530Data {
    const out = makeDefault(id);
    if (!data || data.byteLength === 0) return out;
    const r = new BasReader(data);
    while (r.pos < r.buf.byteLength) {
        const opcode = r.g1();
        if (opcode === 0) return out;
        decodeOpcode(out, opcode, r);
    }
    return out;
}

function decodeOpcode(out: BasType530Data, opcode: number, r: BasReader): void {
    if (opcode === 1) {
        out.idleAnimationId = r.g2();
        out.walkAnimation = r.g2();
        if (out.walkAnimation === 65535) out.walkAnimation = -1;
        if (out.idleAnimationId === 65535) out.idleAnimationId = -1;
    } else if (opcode === 2) {
        out.slowWalkAnimationId = r.g2();
    } else if (opcode === 3) {
        out.slowWalkFullTurnAnimationId = r.g2();
    } else if (opcode === 4) {
        out.slowWalkCCWTurnAnimationId = r.g2();
    } else if (opcode === 5) {
        out.slowWalkCWTurnAnimationId = r.g2();
    } else if (opcode === 6) {
        out.runAnimationId = r.g2();
    } else if (opcode === 7) {
        out.runFullTurnAnimationId = r.g2();
    } else if (opcode === 8) {
        out.runCCWTurnAnimationId = r.g2();
    } else if (opcode === 9) {
        out.runCWTurnAnimationId = r.g2();
    } else if (opcode === 26) {
        // Two unsigned bytes scaled by 4. rt4 stores them as `short`s for
        // some reason (line 138-139); the cast doesn't change the value
        // since the source is already 0..255 * 4 = 0..1020.
        out.anInt1059 = (r.g1() * 4) | 0;
        out.anInt1050 = (r.g1() * 4) | 0;
    } else if (opcode === 27) {
        if (!out.modelRotateTranslate) {
            const arr: (number[] | null)[] = [];
            for (let i = 0; i < 12; i++) arr.push(null);
            out.modelRotateTranslate = arr;
        }
        const bodyId = r.g1();
        const tuple: number[] = [];
        for (let t = 0; t < 6; t++) tuple.push(r.g2b());
        out.modelRotateTranslate[bodyId] = tuple;
    } else if (opcode === 29) {
        out.yawAcceleration = r.g1();
    } else if (opcode === 30) {
        out.yawMaxSpeed = r.g2();
    } else if (opcode === 31) {
        out.rollAcceleration = r.g1();
    } else if (opcode === 32) {
        out.rollMaxSpeed = r.g2();
    } else if (opcode === 33) {
        out.rollTargetAngle = r.g2b();
    } else if (opcode === 34) {
        out.pitchAcceleration = r.g1();
    } else if (opcode === 35) {
        out.pitchMaxSpeed = r.g2();
    } else if (opcode === 36) {
        out.pitchTargetAngle = r.g2b();
    } else if (opcode === 37) {
        out.movementAcceleration = r.g1();
    } else if (opcode === 38) {
        out.standingCCWTurn = r.g2();
    } else if (opcode === 39) {
        out.standingCWTurn = r.g2();
    } else if (opcode === 40) {
        out.walkFullTurnAnimationId = r.g2();
    } else if (opcode === 41) {
        out.walkCCWTurnAnimationId = r.g2();
    } else if (opcode === 42) {
        out.walkCWTurnAnimationId = r.g2();
    } else if (opcode === 43 || opcode === 44 || opcode === 45) {
        // Read-and-discard (rt4 lines 185-191) — keeps the buffer position
        // aligned for any subsequent opcodes.
        r.g2();
    } else {
        // Unknown opcode — abort. We can't safely guess the byte width so
        // continuing risks misaligning the rest of the stream.
        console.warn("[BasType530] unknown opcode " + opcode + " at pos " + (r.pos - 1) + " — aborting decode for bas " + out.id);
    }
}

export class BasType530 {
    public static readonly INDEX = 2;
    public static readonly GROUP = 32;

    static decode(data: Uint8Array, id: number): BasType530Data {
        return decode(data, id);
    }

    static async load(js5Cache: Js5Cache, id: number): Promise<BasType530Data | null> {
        if (id < 0) return null;
        const data = await js5Cache.getFileBytes(BasType530.INDEX, BasType530.GROUP, id);
        if (!data || data.byteLength === 0) return null;
        return decode(data, id);
    }
}
