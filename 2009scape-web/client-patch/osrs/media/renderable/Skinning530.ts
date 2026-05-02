// Skinning530 — applies an AnimFrame530's per-bone deltas to a model's
// vertex positions, producing a new vert buffer the renderer can read.
//
// Scope (P6, offline gates only):
//   - Type 0 (origin) — sets the rotation pivot for subsequent bones.
//   - Type 1 (translate) — adds (dx, dy, dz) to every vertex labelled
//     with the affected bone.
//   - Type 2 (rotate) — small-angle Euler about the current origin.
//   - Other types (scale=3, alpha=5, color=7, etc.) are logged-and-skipped.
//
// The function never allocates: callers pass a pre-allocated Float32Array
// (length = 3 * model.vertCount) that this fills in place.
//
// rt4 reference: Model.method606 / method607.

import type { AnimFrame530Data, AnimBase530Data } from "../../cache/def/AnimFrameset530";

export interface SkinTargetModel {
    vertCount: number;
    /** Base-pose X / Y / Z arrays — same shape RawModel530Data exposes. */
    vertX: Int32Array | number[];
    vertY: Int32Array | number[];
    vertZ: Int32Array | number[];
    /** vertLabels[k] = bone index controlling vertex k. -1 = unaffected. */
    vertLabels?: Int32Array | number[];
}

let warnedTypes: Set<number> | null = null;

/**
 * Apply `frame` to `model`'s base verts, writing the result into `out`.
 * `out.length` must be at least `3 * model.vertCount`. Layout: x0, y0, z0, x1, y1, z1, ...
 */
export function applyFrame(
    model: SkinTargetModel,
    frame: AnimFrame530Data | null,
    out: Float32Array,
): void {
    const n = model.vertCount;
    if (out.length < n * 3) return;

    // 1) Copy base pose into out.
    for (let i = 0; i < n; i++) {
        out[i * 3]     = model.vertX[i] | 0;
        out[i * 3 + 1] = model.vertY[i] | 0;
        out[i * 3 + 2] = model.vertZ[i] | 0;
    }

    if (!frame || !frame.base) return;

    // 2) Walk the frame's per-slot deltas and apply by transform type.
    const base: AnimBase530Data = frame.base;
    let originX = 0, originY = 0, originZ = 0;

    for (let k = 0; k < frame.indices.length; k++) {
        const slot = frame.indices[k];
        const type = base.types?.[slot] ?? -1;
        const dx = frame.x[k];
        const dy = frame.y[k];
        const dz = frame.z[k];

        if (type === 0) {
            // Origin — sets the pivot for subsequent rotate/scale slots.
            originX = dx;
            originY = dy;
            originZ = dz;
            continue;
        }

        if (type === 1) {
            // Translate — adds (dx, dy, dz) to every vert this bone owns.
            const verts = vertsForSlot(model, base, slot);
            for (let v = 0; v < verts.length; v++) {
                const vi = verts[v];
                if (vi < 0 || vi >= n) continue;
                out[vi * 3]     += dx;
                out[vi * 3 + 1] += dy;
                out[vi * 3 + 2] += dz;
            }
            continue;
        }

        if (type === 2) {
            // Rotate — small-angle Euler about the current origin. Use the
            // fast 8192-step sin/cos LUT for hot-path speed; rt4 quantises
            // to an 11-bit angle.
            const verts = vertsForSlot(model, base, slot);
            const sinX = sinTable[dx & 8191];
            const cosX = cosTable[dx & 8191];
            const sinY = sinTable[dy & 8191];
            const cosY = cosTable[dy & 8191];
            const sinZ = sinTable[dz & 8191];
            const cosZ = cosTable[dz & 8191];
            for (let v = 0; v < verts.length; v++) {
                const vi = verts[v];
                if (vi < 0 || vi >= n) continue;
                const px = out[vi * 3]     - originX;
                const py = out[vi * 3 + 1] - originY;
                const pz = out[vi * 3 + 2] - originZ;
                // Z rotation
                let nx = (px * cosZ + py * sinZ) | 0;
                let ny = (py * cosZ - px * sinZ) | 0;
                // X rotation
                let nz = (pz * cosX + ny * sinX) | 0;
                ny = (ny * cosX - pz * sinX) | 0;
                // Y rotation
                const nx2 = (nx * cosY + nz * sinY) | 0;
                nz = (nz * cosY - nx * sinY) | 0;
                out[vi * 3]     = nx2 + originX;
                out[vi * 3 + 1] = ny + originY;
                out[vi * 3 + 2] = nz + originZ;
            }
            continue;
        }

        // Skip unsupported transform types; warn once per type.
        warnSkippedType(type);
    }
}

/** Return the vertex indices controlled by `slot`'s bone group. */
function vertsForSlot(
    model: SkinTargetModel,
    base: AnimBase530Data,
    slot: number,
): readonly number[] {
    // rt4 maps verts to transforms via two arrays:
    //   base.bones[slot] — list of bone-group ids the slot drives
    //   model.vertLabels[v] — bone-group id this vertex belongs to
    // Vertex v is affected by slot k iff vertLabels[v] ∈ base.bones[k].
    if (!model.vertLabels) return EMPTY;
    const group = base.bones?.[slot];
    if (!group || group.length === 0) return EMPTY;
    const matches: number[] = [];
    for (let v = 0; v < model.vertCount; v++) {
        const lbl = model.vertLabels[v];
        for (let g = 0; g < group.length; g++) {
            if (lbl === group[g]) { matches.push(v); break; }
        }
    }
    return matches;
}

const EMPTY: readonly number[] = [];

// ── Trig LUT (8192 step). Built lazily on first import — cheap, ~64 KB
//   total, allocated once for the lifetime of the page.

const TRIG_STEPS = 8192;
const sinTable = new Float32Array(TRIG_STEPS);
const cosTable = new Float32Array(TRIG_STEPS);
{
    const TWO_PI = Math.PI * 2;
    for (let i = 0; i < TRIG_STEPS; i++) {
        const a = (i / TRIG_STEPS) * TWO_PI;
        sinTable[i] = Math.sin(a);
        cosTable[i] = Math.cos(a);
    }
}

function warnSkippedType(t: number): void {
    if (!warnedTypes) warnedTypes = new Set<number>();
    if (warnedTypes.has(t)) return;
    warnedTypes.add(t);
    if (typeof console !== "undefined") {
        console.warn(`[Skinning530] skipped unsupported transform type=${t}`);
    }
}
