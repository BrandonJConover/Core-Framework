/**
 * AnimFrameset530 — TypeScript port of rt4-client AnimFrameset.java +
 * AnimBase.java + AnimFrame.java (the rev-530 skeletal animation stack).
 *
 * Three layered records:
 *
 *   AnimBase     idx1 group=0 file=baseId
 *     "Skeleton" definition: one entry per bone-transform slot, each
 *     describing the transform type (0=origin, 1=translate, 2=rotate,
 *     3=scale, 5=alpha-tint, 7=color-tint) plus the body parts the
 *     transform drives.
 *
 *   AnimFrame    idx0 group=framesetId file=frameId
 *     A keyframe: per-bone delta values referencing a single AnimBase.
 *     The first 2 bytes of the frame blob are the baseId; the next
 *     byte is the header length (= AnimBase.transforms processed);
 *     the rest is two parallel cursors over the same bytes (header
 *     attributes + interleaved gsmart deltas for x/y/z and rot/scale).
 *
 *   AnimFrameset idx0 group=framesetId
 *     A bundle of AnimFrames sharing one or more AnimBase skeletons.
 *     `frames[fileId]` populates only the slots present in the group's
 *     fileIds list — sparse layouts produce nulls for missing ids.
 *
 * Source of truth:
 *   reference/rt4-client/client/src/main/java/rt4/AnimBase.java       (57 lines)
 *   reference/rt4-client/client/src/main/java/rt4/AnimFrame.java     (140 lines)
 *   reference/rt4-client/client/src/main/java/rt4/AnimFrameset.java   (77 lines)
 *   reference/rt4-client/client/src/main/java/rt4/SeqTypeList.java
 *     (init at client.java:1548 — basesArchive=js5Archive1, animsArchive=js5Archive0)
 */

import { Js5Cache } from "../../Js5Cache";

class AnimReader {
    public buf: Uint8Array;
    public pos: number;
    constructor(buf: Uint8Array, pos: number = 0) { this.buf = buf; this.pos = pos; }

    g1(): number { return this.buf[this.pos++] & 0xFF; }

    g2(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        return (a << 8) | b;
    }

    /** rt4 Buffer.gsmart — signed variable-length: 1 byte (-64..63) or 2 bytes (-16384..16383). */
    gsmart(): number {
        const peek = this.buf[this.pos] & 0xFF;
        if (peek < 128) return this.g1() - 64;
        return this.g2() - 0xC000;
    }
}

// ── AnimBase ───────────────────────────────────────────────────────

export interface AnimBase530Data {
    id: number;
    /** Transform-slot count. Each slot carries (type, shadow, parts, bones[]) below. */
    transforms: number;
    /** types[i]: 0=origin, 1=translate, 2=rotate, 3=scale, 5=alphaTint, 7=colorTint. */
    types: number[];
    /** shadow[i]: whether this bone's transform affects shadow rendering. */
    shadow: boolean[];
    /** parts[i]: bit flags identifying which body parts the bone drives. */
    parts: number[];
    /** bones[i]: list of bone-group ids whose vertices this transform applies to. */
    bones: number[][];
}

function decodeBase(data: Uint8Array, id: number): AnimBase530Data {
    const r = new AnimReader(data);
    const transforms = r.g1();
    const types: number[] = [];
    const shadow: boolean[] = [];
    const parts: number[] = [];
    const bones: number[][] = [];
    for (let i = 0; i < transforms; i++) types.push(r.g1());
    for (let i = 0; i < transforms; i++) shadow.push(r.g1() === 1);
    for (let i = 0; i < transforms; i++) parts.push(r.g2());
    const boneCounts: number[] = [];
    for (let i = 0; i < transforms; i++) boneCounts.push(r.g1());
    for (let i = 0; i < transforms; i++) {
        const list: number[] = [];
        const n = boneCounts[i];
        for (let j = 0; j < n; j++) list.push(r.g1());
        bones.push(list);
    }
    return { id, transforms, types, shadow, parts, bones };
}

export class AnimBase530 {
    public static readonly INDEX = 1;
    public static readonly GROUP = 0;
    static decode(data: Uint8Array, id: number): AnimBase530Data { return decodeBase(data, id); }
    static async load(js5Cache: Js5Cache, baseId: number): Promise<AnimBase530Data | null> {
        if (baseId < 0) return null;
        const data = await js5Cache.getFileBytes(AnimBase530.INDEX, AnimBase530.GROUP, baseId);
        if (!data || data.byteLength === 0) return null;
        return decodeBase(data, baseId);
    }
}

// ── AnimFrame ──────────────────────────────────────────────────────

export interface AnimFrame530Data {
    base: AnimBase530Data;
    /** Number of populated slots (≤ base.transforms). */
    length: number;
    /** True when at least one slot has type 5 (alpha tint). */
    transformsAlpha: boolean;
    /** True when at least one slot has type 7 (color tint). */
    transformsColor: boolean;
    /** indices[k] = the AnimBase transform-slot index that delta k applies to. */
    indices: number[];
    /** Per-slot delta x. For type==2 (rotate) the value is reassembled (see decodeFrame). */
    x: number[];
    y: number[];
    z: number[];
    /** prevOriginIndices[k]: the most recent type-0 origin slot still in scope, or -1. */
    prevOriginIndices: number[];
    /** flags[k]: rt4 packs (attributes >>> 3 & 0x3) — top-bits of the per-slot attribute byte. */
    flags: number[];
}

function decodeFrame(bytes: Uint8Array, base: AnimBase530Data): AnimFrame530Data {
    // rt4 uses two cursors over the same byte array:
    //   headerBuffer.offset = 2 (skip the leading 2-byte baseId)
    //   then headerBuffer reads the headerLen byte plus headerLen attribute bytes
    //   buffer (the value cursor) starts immediately after the attribute block
    const headerR = new AnimReader(bytes, 2);
    const headerLen = headerR.g1();
    const valueR = new AnimReader(bytes, headerR.pos + headerLen);

    const indices: number[] = [];
    const xs: number[] = [];
    const ys: number[] = [];
    const zs: number[] = [];
    const prevOriginIndices: number[] = [];
    const flags: number[] = [];

    let len = 0;
    let prevOriginIndex = -1;
    let prevUsedOriginIndex = -1;
    let transformsAlpha = false;
    let transformsColor = false;

    for (let i = 0; i < headerLen; i++) {
        const type = base.types[i];
        if (type === 0) prevOriginIndex = i;
        const attributes = headerR.g1();
        if (attributes <= 0) continue;

        if (type === 0) prevUsedOriginIndex = i;

        const defaultValue = type === 3 ? 128 : 0;
        let dx = (attributes & 0x1) === 0 ? defaultValue : valueR.gsmart();
        let dy = (attributes & 0x2) === 0 ? defaultValue : valueR.gsmart();
        let dz = (attributes & 0x4) === 0 ? defaultValue : valueR.gsmart();

        if (type === 2) {
            // rt4: ((v & 0xFF) << 3) + ((v >> 8) & 0x7) — repack rotation
            // values into the format the model transformer expects.
            dx = (((dx & 0xFF) << 3) + ((dx >> 8) & 0x7)) | 0;
            dy = (((dy & 0xFF) << 3) + ((dy >> 8) & 0x7)) | 0;
            dz = (((dz & 0xFF) << 3) + ((dz >> 8) & 0x7)) | 0;
        }

        indices.push(i);
        xs.push(signedShort(dx));
        ys.push(signedShort(dy));
        zs.push(signedShort(dz));
        flags.push(((attributes >>> 3) & 0x3) | 0);

        let prevOrigin = -1;
        if (type === 1 || type === 2 || type === 3) {
            if (prevOriginIndex > prevUsedOriginIndex) {
                prevOrigin = prevOriginIndex;
                prevUsedOriginIndex = prevOriginIndex;
            }
        } else if (type === 5) {
            transformsAlpha = true;
        } else if (type === 7) {
            transformsColor = true;
        }
        prevOriginIndices.push(prevOrigin);
        len++;
    }

    if (valueR.pos !== bytes.length) {
        // rt4 throws here; we warn and continue. Surfacing the mismatch
        // helps catch base-mismatch bugs without breaking the rest of
        // the frameset.
        console.warn(
            "[AnimFrame530] trailing-byte mismatch (read " + valueR.pos +
            " of " + bytes.length + ") for base=" + base.id
        );
    }

    return {
        base,
        length: len,
        transformsAlpha,
        transformsColor,
        indices,
        x: xs,
        y: ys,
        z: zs,
        prevOriginIndices,
        flags,
    };
}

function signedShort(v: number): number {
    v &= 0xFFFF;
    return v >= 0x8000 ? v - 0x10000 : v;
}

export class AnimFrame530 {
    static decode(bytes: Uint8Array, base: AnimBase530Data): AnimFrame530Data {
        return decodeFrame(bytes, base);
    }
}

// ── AnimFrameset ───────────────────────────────────────────────────

export interface AnimFrameset530Data {
    id: number;
    /**
     * Frames indexed by fileId. Length is the group's max-fileId+1; slots
     * not referenced by the group's fileIds list are null. Mirrors rt4
     * `frames[fileIds[i]] = new AnimFrame(...)` against an array sized
     * to `getGroupCapacity(id)`.
     */
    frames: (AnimFrame530Data | null)[];
}

export class AnimFrameset530 {
    public static readonly INDEX = 0;

    /**
     * Mirrors AnimFrameset.create + AnimFrameset(...) in rt4. Resolves
     * every frame in idx0 group=id, fetching each referenced AnimBase
     * once and caching it inside this call.
     */
    static async load(js5Cache: Js5Cache, id: number): Promise<AnimFrameset530Data | null> {
        if (id < 0) return null;
        const meta = await js5Cache.getMeta(AnimFrameset530.INDEX);
        if (!meta) return null;
        const groupSize = meta.groupSizes[id] || 0;
        if (groupSize === 0) return null;
        const fileIds = meta.fileIds[id]; // null when files are densely-packed 0..groupSize-1

        let capacity = 0;
        if (fileIds) {
            for (let i = 0; i < fileIds.length; i++) {
                if (fileIds[i] + 1 > capacity) capacity = fileIds[i] + 1;
            }
        } else {
            capacity = groupSize;
        }

        const frames: (AnimFrame530Data | null)[] = new Array(capacity);
        for (let i = 0; i < capacity; i++) frames[i] = null;

        const baseCache = new Map<number, AnimBase530Data>();
        const fileList = fileIds ?? rangeArray(groupSize);

        for (let i = 0; i < fileList.length; i++) {
            const fileId = fileList[i];
            const bytes = await js5Cache.getFileBytes(AnimFrameset530.INDEX, id, fileId);
            if (!bytes || bytes.byteLength < 3) continue;
            const baseId = ((bytes[0] & 0xFF) << 8) | (bytes[1] & 0xFF);
            let base = baseCache.get(baseId);
            if (!base) {
                const baseBytes = await js5Cache.getFileBytes(AnimBase530.INDEX, AnimBase530.GROUP, baseId);
                if (!baseBytes || baseBytes.byteLength === 0) continue;
                base = decodeBase(baseBytes, baseId);
                baseCache.set(baseId, base);
            }
            try {
                frames[fileId] = decodeFrame(bytes, base);
            } catch (e) {
                console.warn("[AnimFrameset530] frame decode failed for set=" + id + " file=" + fileId + ": " + e);
            }
        }

        return { id, frames };
    }
}

function rangeArray(n: number): number[] {
    const a: number[] = [];
    for (let i = 0; i < n; i++) a.push(i);
    return a;
}
