/**
 * Model530Animator — skeletal vertex transform for rev-530 models.
 *
 * Bridges decoded RawModel530Data + AnimFrame530Data → mutated vertex
 * positions / per-triangle tints. Mirrors the rt4-client per-bone path:
 *
 *   rt4.Model.method4555      — single-frame whole-model apply (shadow)
 *   rt4.Model.method4553      — single OR cross-faded per-bone apply
 *   rt4.SoftwareModel.method4569 — bone-grouped per-vertex transform
 *   rt4.SoftwareModel.method4567 — full-model fallback transform
 *   rt4.RawModel.createBones  — derives boneVertices/boneTriangles from
 *                               vertexBones/triangleBones
 *
 * The 530 skeletal model uses two indirections:
 *
 *   AnimBase.bones[transformIdx][k] = bone-group id
 *   boneVertices[bone-group id]     = list of vertex indices
 *
 * So a single transform "type" applies to a *list* of vertex groups,
 * each in turn being a flat list of vertex indices. This is unlike the
 * older 377/RSC model where a single bone-id directly indexed vertices.
 *
 * State is split:
 *
 *   ModelBoneIndex   immutable per-RawModel — the bone-group → vertex
 *                    index lookup tables. Built once with createBones().
 *
 *   ModelPose        per-instance, per-tick — copies of vertex positions
 *                    + per-triangle alpha/colors plus the type-0 pivot
 *                    register. Mutated in place by applyAnimFrame*.
 *
 * The renderer reads ModelPose every frame; the rest pose lives in
 * RawModel530Data and is never written.
 *
 * No dependencies on Js5Cache / Game / Scene — this is pure data math
 * and is fully unit-testable offline.
 */

import { RawModel530Data } from "../../cache/def/RawModel530";
import { AnimBase530Data, AnimFrame530Data } from "../../cache/def/AnimFrameset530";

// ── Sin/cos tables (rt4 MathUtils.sin/cos: 2048 entries, fixed-point Q16) ──

const SIN: Int32Array = new Int32Array(2048);
const COS: Int32Array = new Int32Array(2048);
{
    for (let i = 0; i < 2048; i++) {
        const radians = i * 0.0030679615;
        SIN[i] = Math.trunc(Math.sin(radians) * 65536);
        COS[i] = Math.trunc(Math.cos(radians) * 65536);
    }
}

// ── ModelBoneIndex ────────────────────────────────────────────────

/** Immutable per-model bone → vertex/triangle lookup tables. */
export interface ModelBoneIndex {
    /** boneVertices[boneId] = vertex indices owned by this bone. */
    boneVertices: number[][];
    /** boneTriangles[boneId] = triangle indices owned by this bone. null when source had no triangleBones. */
    boneTriangles: number[][] | null;
}

/**
 * Compute boneVertices + boneTriangles. Mirrors RawModel.createBones().
 * Pure function — does not mutate `m`.
 */
export function createBones(m: RawModel530Data): ModelBoneIndex {
    let boneVertices: number[][] = [];
    if (m.vertexBones) {
        let maxBone = 0;
        const counts: number[] = [];
        for (let i = 0; i < 256; i++) counts.push(0);
        for (let i = 0; i < m.vertexCount; i++) {
            const b = m.vertexBones[i];
            counts[b]++;
            if (b > maxBone) maxBone = b;
        }
        boneVertices = new Array(maxBone + 1);
        const writeIdx: number[] = new Array(maxBone + 1);
        for (let i = 0; i <= maxBone; i++) {
            boneVertices[i] = new Array(counts[i]);
            for (let j = 0; j < counts[i]; j++) boneVertices[i][j] = 0;
            writeIdx[i] = 0;
        }
        for (let i = 0; i < m.vertexCount; i++) {
            const b = m.vertexBones[i];
            boneVertices[b][writeIdx[b]++] = i;
        }
    }

    let boneTriangles: number[][] | null = null;
    if (m.triangleBones) {
        let maxBone = 0;
        const counts: number[] = [];
        for (let i = 0; i < 256; i++) counts.push(0);
        for (let i = 0; i < m.triangleCount; i++) {
            const b = m.triangleBones[i];
            counts[b]++;
            if (b > maxBone) maxBone = b;
        }
        boneTriangles = new Array(maxBone + 1);
        const writeIdx: number[] = new Array(maxBone + 1);
        for (let i = 0; i <= maxBone; i++) {
            boneTriangles[i] = new Array(counts[i]);
            for (let j = 0; j < counts[i]; j++) boneTriangles[i][j] = 0;
            writeIdx[i] = 0;
        }
        for (let i = 0; i < m.triangleCount; i++) {
            const b = m.triangleBones[i];
            boneTriangles[b][writeIdx[b]++] = i;
        }
    }

    return { boneVertices, boneTriangles };
}

// ── ModelPose ─────────────────────────────────────────────────────

/**
 * Per-instance vertex + tint state. Created once per visible model
 * instance. Each animation tick the renderer:
 *   1. Calls resetPose(pose, raw)               — restores rest pose.
 *   2. Calls applyAnimFrame(pose, idx, frame)   — mutates positions / tints.
 *   3. Reads vertexX/Y/Z + triangleAlpha/Colors back to a vertex buffer.
 */
export interface ModelPose {
    /** Per-vertex absolute position (Int32 to match rt4 fixed-point math). */
    vertexX: Int32Array;
    vertexY: Int32Array;
    vertexZ: Int32Array;
    /** Per-triangle alpha (signed byte; null when source had no triangleAlpha). */
    triangleAlpha: Int8Array | null;
    /** Per-triangle HSL16 color (always present after rest copy). */
    triangleColors: Int32Array;
    /** Type-0 origin pivot — set by type-0 transforms, consumed by type-2/3. */
    pivotX: number;
    pivotY: number;
    pivotZ: number;
    /** Set true any time a type-7 transform runs. Renderer uses this to skip cached gouraud. */
    colorsChanged: boolean;
}

/** Allocate a fresh pose buffer matching the rest pose of `m`. */
export function createPose(m: RawModel530Data): ModelPose {
    const vCount = m.vertexCount;
    const tCount = m.triangleCount;
    const vx = new Int32Array(vCount);
    const vy = new Int32Array(vCount);
    const vz = new Int32Array(vCount);
    for (let i = 0; i < vCount; i++) {
        vx[i] = m.vertexX[i] | 0;
        vy[i] = m.vertexY[i] | 0;
        vz[i] = m.vertexZ[i] | 0;
    }
    const colors = new Int32Array(tCount);
    for (let i = 0; i < tCount; i++) colors[i] = (m.triangleColors[i] | 0) & 0xFFFF;
    let alpha: Int8Array | null = null;
    if (m.triangleAlpha) {
        alpha = new Int8Array(tCount);
        for (let i = 0; i < tCount; i++) alpha[i] = m.triangleAlpha[i] | 0;
    }
    return {
        vertexX: vx,
        vertexY: vy,
        vertexZ: vz,
        triangleAlpha: alpha,
        triangleColors: colors,
        pivotX: 0, pivotY: 0, pivotZ: 0,
        colorsChanged: false,
    };
}

/** Restore the rest pose into an existing buffer (avoids re-allocating). */
export function resetPose(pose: ModelPose, m: RawModel530Data): void {
    const vCount = m.vertexCount;
    const tCount = m.triangleCount;
    for (let i = 0; i < vCount; i++) {
        pose.vertexX[i] = m.vertexX[i] | 0;
        pose.vertexY[i] = m.vertexY[i] | 0;
        pose.vertexZ[i] = m.vertexZ[i] | 0;
    }
    for (let i = 0; i < tCount; i++) pose.triangleColors[i] = (m.triangleColors[i] | 0) & 0xFFFF;
    if (pose.triangleAlpha && m.triangleAlpha) {
        for (let i = 0; i < tCount; i++) pose.triangleAlpha[i] = m.triangleAlpha[i] | 0;
    }
    pose.pivotX = 0;
    pose.pivotY = 0;
    pose.pivotZ = 0;
    pose.colorsChanged = false;
}

// ── Per-bone transform (rt4 SoftwareModel.method4569) ─────────────

function transformBones(
    pose: ModelPose,
    idx: ModelBoneIndex,
    type: number,
    boneIds: number[],
    dx: number,
    dy: number,
    dz: number,
): void {
    const vx = pose.vertexX;
    const vy = pose.vertexY;
    const vz = pose.vertexZ;
    const bv = idx.boneVertices;

    if (type === 0) {
        // Build pivot from the centroid of the affected vertices.
        let count = 0;
        let sx = 0, sy = 0, sz = 0;
        for (let bi = 0; bi < boneIds.length; bi++) {
            const bone = boneIds[bi];
            if (bone >= bv.length) continue;
            const verts = bv[bone];
            for (let vi = 0; vi < verts.length; vi++) {
                const v = verts[vi];
                sx += vx[v];
                sy += vy[v];
                sz += vz[v];
                count++;
            }
        }
        if (count > 0) {
            pose.pivotX = (sx / count | 0) + dx;
            pose.pivotY = (sy / count | 0) + dy;
            pose.pivotZ = (sz / count | 0) + dz;
        } else {
            pose.pivotX = dx;
            pose.pivotY = dy;
            pose.pivotZ = dz;
        }
        return;
    }

    if (type === 1) {
        for (let bi = 0; bi < boneIds.length; bi++) {
            const bone = boneIds[bi];
            if (bone >= bv.length) continue;
            const verts = bv[bone];
            for (let vi = 0; vi < verts.length; vi++) {
                const v = verts[vi];
                vx[v] += dx;
                vy[v] += dy;
                vz[v] += dz;
            }
        }
        return;
    }

    if (type === 2) {
        const px = pose.pivotX, py = pose.pivotY, pz = pose.pivotZ;
        for (let bi = 0; bi < boneIds.length; bi++) {
            const bone = boneIds[bi];
            if (bone >= bv.length) continue;
            const verts = bv[bone];
            for (let vi = 0; vi < verts.length; vi++) {
                const v = verts[vi];
                let x = vx[v] - px;
                let y = vy[v] - py;
                let z = vz[v] - pz;
                // Z rotation (rt4 dz)
                if (dz !== 0) {
                    const s = SIN[dz & 0x7FF];
                    const c = COS[dz & 0x7FF];
                    const nx = (y * s + x * c + 32767) >> 16;
                    y = (y * c + 32767 - x * s) >> 16;
                    x = nx;
                }
                // X rotation (rt4 dx)
                if (dx !== 0) {
                    const s = SIN[dx & 0x7FF];
                    const c = COS[dx & 0x7FF];
                    const ny = (y * c + 32767 - z * s) >> 16;
                    z = (y * s + z * c + 32767) >> 16;
                    y = ny;
                }
                // Y rotation (rt4 dy)
                if (dy !== 0) {
                    const s = SIN[dy & 0x7FF];
                    const c = COS[dy & 0x7FF];
                    const nz = (z * s + x * c + 32767) >> 16;
                    x = (z * c + 32767 - x * s) >> 16;
                    z = nz;
                }
                vx[v] = x + px;
                vy[v] = y + py;
                vz[v] = z + pz;
            }
        }
        return;
    }

    if (type === 3) {
        const px = pose.pivotX, py = pose.pivotY, pz = pose.pivotZ;
        for (let bi = 0; bi < boneIds.length; bi++) {
            const bone = boneIds[bi];
            if (bone >= bv.length) continue;
            const verts = bv[bone];
            for (let vi = 0; vi < verts.length; vi++) {
                const v = verts[vi];
                let x = vx[v] - px;
                let y = vy[v] - py;
                let z = vz[v] - pz;
                x = ((x * dx) / 128) | 0;
                y = ((y * dy) / 128) | 0;
                z = ((z * dz) / 128) | 0;
                vx[v] = x + px;
                vy[v] = y + py;
                vz[v] = z + pz;
            }
        }
        return;
    }

    if (type === 5) {
        // Per-triangle alpha tint. Only meaningful when boneTriangles exists.
        if (!idx.boneTriangles || !pose.triangleAlpha) return;
        const bt = idx.boneTriangles;
        const a = pose.triangleAlpha;
        for (let bi = 0; bi < boneIds.length; bi++) {
            const bone = boneIds[bi];
            if (bone >= bt.length) continue;
            const tris = bt[bone];
            for (let ti = 0; ti < tris.length; ti++) {
                const t = tris[ti];
                let v = (a[t] & 0xFF) + dx * 8;
                if (v < 0) v = 0;
                else if (v > 255) v = 255;
                a[t] = v;
            }
        }
        return;
    }

    if (type === 7) {
        // Per-triangle HSL16 tint.
        if (!idx.boneTriangles) return;
        const bt = idx.boneTriangles;
        const c = pose.triangleColors;
        for (let bi = 0; bi < boneIds.length; bi++) {
            const bone = boneIds[bi];
            if (bone >= bt.length) continue;
            const tris = bt[bone];
            for (let ti = 0; ti < tris.length; ti++) {
                const t = tris[ti];
                const col = c[t] & 0xFFFF;
                let h = (col >> 10) & 0x3F;
                let s = (col >> 7) & 0x7;
                let l = col & 0x7F;
                h = (h + dx) & 0x3F;
                s = s + dy;
                if (s < 0) s = 0; else if (s > 7) s = 7;
                l = l + dz;
                if (l < 0) l = 0; else if (l > 127) l = 127;
                c[t] = ((h << 10) | (s << 7) | l) & 0xFFFF;
            }
        }
        pose.colorsChanged = true;
        return;
    }
}

// ── Frame application ─────────────────────────────────────────────

/**
 * Apply a single AnimFrame530 to a pose.
 *
 * Mirrors rt4 method4553's "single frame" branch (when frameB is null):
 *   for each frame slot k:
 *     if mask gating excludes this slot, skip
 *     if prevOriginIndex[k] != -1, run a synthetic type-0 reset
 *     run base.types[idx[k]] with delta x/y/z[k]
 */
export function applyAnimFrame(
    pose: ModelPose,
    idx: ModelBoneIndex,
    frame: AnimFrame530Data,
    /** Optional bitmask gate over base.parts (rt4 arg8). 65535 = all parts. */
    partMask: number = 0xFFFF,
    /** Optional per-transform-slot gate (rt4 arg5). false slots are skipped unless type==0. */
    slotMask: boolean[] | null = null,
    /** Polarity for `slotMask` (rt4 arg6). */
    slotMaskPolarity: boolean = false,
): void {
    const base = frame.base;
    for (let k = 0; k < frame.length; k++) {
        const slot = frame.indices[k];
        const type = base.types[slot];
        if (slotMask && slotMask[slot] !== slotMaskPolarity && type !== 0) continue;

        const partsBits = partMask & base.parts[slot];
        if (partsBits !== 0xFFFF) {
            // rt4 has a partial-mask path (method4577) that we don't yet
            // implement (it filters per-vertex by occupancy). For now we
            // skip masked slots entirely — the visible side-effect is
            // single-part swaps not animating. Whole-model anims work.
            continue;
        }

        const prevOrigin = frame.prevOriginIndices[k];
        if (prevOrigin !== -1) {
            transformBones(pose, idx, 0, base.bones[prevOrigin], 0, 0, 0);
        }

        transformBones(pose, idx, type, base.bones[slot], frame.x[k], frame.y[k], frame.z[k]);
    }
}

/**
 * Apply a cross-faded blend of two frames sharing one base. Mirrors rt4
 * method4553's interpolated branch (the long path when arg2 != null and
 * arg3 != 0). `tNum / tDen` is the blend factor; tNum=0 returns frameA,
 * tNum=tDen returns frameB. Both frames must reference the same AnimBase.
 */
export function applyAnimFrameInterpolated(
    pose: ModelPose,
    idx: ModelBoneIndex,
    frameA: AnimFrame530Data,
    frameB: AnimFrame530Data,
    tNum: number,
    tDen: number,
    partMask: number = 0xFFFF,
): void {
    if (tDen === 0 || frameA.base !== frameB.base) {
        applyAnimFrame(pose, idx, frameA, partMask);
        return;
    }
    const base = frameA.base;
    let kA = 0;
    let kB = 0;
    for (let slot = 0; slot < base.transforms; slot++) {
        const aPresent = kA < frameA.length && frameA.indices[kA] === slot;
        const bPresent = kB < frameB.length && frameB.indices[kB] === slot;
        if (!aPresent && !bPresent) continue;

        const type = base.types[slot];
        const def = type === 3 ? 128 : 0;

        let ax = def, ay = def, az = def, aPrev = -1, aFlags = 0;
        if (aPresent) {
            ax = frameA.x[kA];
            ay = frameA.y[kA];
            az = frameA.z[kA];
            aPrev = frameA.prevOriginIndices[kA];
            aFlags = frameA.flags[kA];
            kA++;
        }
        let bx = def, by = def, bz = def, bPrev = -1, bFlags = 0;
        if (bPresent) {
            bx = frameB.x[kB];
            by = frameB.y[kB];
            bz = frameB.z[kB];
            bPrev = frameB.prevOriginIndices[kB];
            bFlags = frameB.flags[kB];
            kB++;
        }

        let dx: number, dy: number, dz: number;
        if ((aFlags & 0x2) !== 0 || (bFlags & 0x1) !== 0) {
            // rt4 "freeze A" override.
            dx = ax; dy = ay; dz = az;
        } else if (type === 2) {
            // Rotation: shortest-arc lerp on each component (mod 2048).
            dx = lerpAngle(ax, bx, tNum, tDen);
            dy = lerpAngle(ay, by, tNum, tDen);
            dz = lerpAngle(az, bz, tNum, tDen);
        } else if (type === 7) {
            // HSL hue uses 64-step shortest-arc; sat/lum lerp linearly.
            dx = lerpHue(ax, bx, tNum, tDen);
            dy = ay + ((by - ay) * tNum / tDen | 0);
            dz = az + ((bz - az) * tNum / tDen | 0);
        } else {
            dx = ax + ((bx - ax) * tNum / tDen | 0);
            dy = ay + ((by - ay) * tNum / tDen | 0);
            dz = az + ((bz - az) * tNum / tDen | 0);
        }

        if ((partMask & base.parts[slot]) !== 0xFFFF) continue;

        if (aPrev !== -1) {
            transformBones(pose, idx, 0, base.bones[aPrev], 0, 0, 0);
        } else if (bPrev !== -1) {
            transformBones(pose, idx, 0, base.bones[bPrev], 0, 0, 0);
        }

        transformBones(pose, idx, type, base.bones[slot], dx, dy, dz);
    }
}

function lerpAngle(a: number, b: number, num: number, den: number): number {
    let d = (b - a) & 0x7FF;
    if (d >= 1024) d -= 2048;
    return (a + (d * num / den | 0)) & 0x7FF;
}

function lerpHue(a: number, b: number, num: number, den: number): number {
    let d = (b - a) & 0x3F;
    if (d >= 32) d -= 64;
    return (a + (d * num / den | 0)) & 0x3F;
}
