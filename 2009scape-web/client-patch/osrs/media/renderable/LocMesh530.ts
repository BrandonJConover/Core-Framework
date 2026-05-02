/**
 * LocMesh530 — rev-530 game-object (loc) mesh compositor.
 *
 * Locs are static-or-near-static world objects: trees, doors, statues,
 * walls, fences, signposts. Each LocType530 references model ids via
 * a flat 1D `models` array, optionally paired with a `shapes` array
 * that maps each model to a specific shape variant. The compositor
 * resolves the right variant, loads each RawModel530, merges, applies
 * the LocType's color/texture/scale/translate transforms, and rotates
 * by the per-instance orientation (0..3 = 0°/90°/180°/270° around Y).
 *
 * Source of truth (read-only):
 *   reference/rt4-client/client/src/main/java/rt4/LocType.java
 *     getRawModel(arg0=orientation, arg1=requestedShape)   line 263
 *       L272-302  shapes==null path: concat all models, shape must be 10
 *       L303-329  shapes!=null path: find shapes[i]==arg1, single model
 *       L334      deep-copy via RawModel(parent, copy-flags)
 *       L335-338  wall-decor (shape=4, orientation>3) extra translate
 *       L339-346  arg0 & 0x3 → swapXz / negateXz / method1689
 *       L348-355  recolor loop (per-pair on composite)
 *       L357-360  retexture loop (per-pair on composite)
 *       L362-363  resize when any axis != 128
 *       L365-367  translate when any offset != 0
 *   reference/rt4-client/client/src/main/java/rt4/RawModel.java
 *     L462  negateXz   x'=-x, z'=-z              (orientation 2)
 *     L471  swapXz     x'=z,  z'=-x              (orientation 1)
 *     L1890 method1689 x'=-z, z'=x               (orientation 3)
 *
 * Reuses helpers exported by PlayerAppearance530:
 *   mergeRawModels(models[]) → composite
 *   recolorModel(m, src, dst)
 *   retextureModel(m, src, dst)
 *
 * Constants per rt4 LocType decode:
 *   resizex/y/z default 128 (1.0× scale; only resize when any != 128)
 *   xoff/yoff/zoff default 0 (only translate when any != 0)
 *   CENTREPIECE_STRAIGHT shape id = 10 (used when shapes==null)
 */

import { RawModel530Data } from "../../cache/def/RawModel530";
import { LocType530Data } from "../../cache/def/LocType530";
import {
    mergeRawModels,
    recolorModel,
    retextureModel,
} from "./PlayerAppearance530";

/** rt4 LocType "centrepiece straight" shape — the only shape valid when shapes==null. */
export const SHAPE_CENTREPIECE_STRAIGHT = 10;

/** Per-spawn options consumed by composeLocMesh. */
export interface LocComposeOptions {
    /** 0..3 → 0°/90°/180°/270° rotation around Y. Default 0. */
    orientation: number;
    /** Skip the per-instance scale + translate. Useful for tests. Default false. */
    skipScale: boolean;
    /** Skip the recolor/retexture loops. Useful for tests. Default false. */
    skipRecolor: boolean;
}

const DEFAULT_OPTS: LocComposeOptions = {
    orientation: 0,
    skipScale: false,
    skipRecolor: false,
};

// ── Resolve ──────────────────────────────────────────────────────

/**
 * Return the model ids contributing to a given shape variant.
 *
 * Mirrors rt4 LocType.getRawModel's shape-resolution branch:
 *
 *   shapes == null: requestedShape MUST be SHAPE_CENTREPIECE_STRAIGHT
 *                   (10). Returns all entries from `models[]` flat.
 *   shapes != null: linear-search shapes[] for the first index where
 *                   shapes[i] == requestedShape; returns [models[i]].
 *                   Returns [] if no match.
 *
 * Returns [] for both no-models and shape-mismatch — caller distinguishes
 * by checking loc.models against null itself if it cares.
 */
export function resolveLocModels(loc: LocType530Data, shapeIndex: number): number[] {
    if (!loc.models || loc.models.length === 0) return [];
    if (loc.shapes === null || loc.shapes === undefined) {
        if (shapeIndex !== SHAPE_CENTREPIECE_STRAIGHT) return [];
        return loc.models.slice();
    }
    for (let i = 0; i < loc.shapes.length; i++) {
        if (loc.shapes[i] === shapeIndex) {
            if (i < loc.models.length) return [loc.models[i]];
            return [];
        }
    }
    return [];
}

// ── Orientation primitives (rt4 RawModel orientation transforms) ──

/**
 * Rotate a mesh in place by the rt4 orientation index (0..3). Uses pure
 * integer x/z swaps + sign flips — NO trig table — exactly matching
 * RawModel.swapXz / negateXz / method1689.
 *
 *   0 → identity
 *   1 → swapXz       x'=z,  z'=-x
 *   2 → negateXz     x'=-x, z'=-z
 *   3 → method1689   x'=-z, z'=x
 */
export function applyLocOrientation(mesh: RawModel530Data, orientation: number): RawModel530Data {
    const o = orientation & 0x3;
    if (o === 0) return mesh;

    const out = shallowCopyMesh(mesh);
    const vx = out.vertexX;
    const vz = out.vertexZ;
    const n = out.vertexCount;

    if (o === 1) {
        for (let i = 0; i < n; i++) {
            const tmp = vx[i];
            vx[i] = vz[i];
            vz[i] = -tmp;
        }
    } else if (o === 2) {
        for (let i = 0; i < n; i++) {
            vx[i] = -vx[i];
            vz[i] = -vz[i];
        }
    } else {
        for (let i = 0; i < n; i++) {
            const tmp = vz[i];
            vz[i] = vx[i];
            vx[i] = -tmp;
        }
    }

    return out;
}

// ── Compose ──────────────────────────────────────────────────────

/**
 * Build the composite mesh for a loc at a given shape variant + orientation.
 * Mirrors rt4 LocType.getRawModel's algorithm step-for-step.
 *
 * Returns null when no model is resolved. Does NOT mutate the cached
 * RawModel530 data — every per-slot model is shallow-copied before
 * recolor/retexture/resize/translate touch it.
 */
export async function composeLocMesh(
    loc: LocType530Data,
    shapeIndex: number,
    rawModelLoader: (id: number) => Promise<RawModel530Data | null>,
    options?: Partial<LocComposeOptions>,
): Promise<RawModel530Data | null> {
    const opts: LocComposeOptions = { ...DEFAULT_OPTS, ...(options ?? {}) };

    // Phase 1: resolve model ids for this shape.
    const modelIds = resolveLocModels(loc, shapeIndex);
    if (modelIds.length === 0) return null;

    // Phase 2: load + deep-copy each model. The deep copy is essential —
    // the rt4 path calls `new RawModel(parent, ...)` which produces an
    // independent instance, and our recolor/translate mutators below
    // would otherwise corrupt the shared cache.
    const slotModels: RawModel530Data[] = [];
    for (const id of modelIds) {
        const raw = await rawModelLoader(id);
        if (!raw) continue;
        slotModels.push(shallowCopyMesh(raw));
    }
    if (slotModels.length === 0) return null;

    // Phase 3: merge. mergeRawModels handles the single-model case
    // efficiently (returns the slot model itself when length===1) — but
    // we already deep-copied so passing forceCopy=false is safe.
    const composite = mergeRawModels(slotModels);
    if (!composite) return null;

    // Phase 4: orient. rt4 applies orientation BEFORE recolor/retexture
    // (line 339-346 vs 348+) but the order doesn't affect the result —
    // both are vertex-or-color-table transforms that commute. We do
    // orient first so subsequent transforms see the rotated bounds.
    const oriented = applyLocOrientation(composite, opts.orientation);

    // Phase 5: per-pair recolor + retexture (rt4 LocType.java#L348-360).
    if (!opts.skipRecolor) {
        if (loc.recol_s && loc.recol_d) {
            for (let i = 0; i < loc.recol_s.length; i++) {
                recolorModel(oriented, loc.recol_s[i], loc.recol_d[i]);
            }
        }
        if (loc.retex_s && loc.retex_d) {
            for (let i = 0; i < loc.retex_s.length; i++) {
                retextureModel(oriented, loc.retex_s[i], loc.retex_d[i]);
            }
        }
    }

    // Phase 6: resize (per-axis scale around origin). rt4 LocType.java#L362-363.
    if (!opts.skipScale) {
        if (loc.resizex !== 128 || loc.resizey !== 128 || loc.resizez !== 128) {
            applyResize(oriented, loc.resizex, loc.resizey, loc.resizez);
        }

        // Phase 7: translate. rt4 LocType.java#L365-367.
        if (loc.xoff !== 0 || loc.yoff !== 0 || loc.zoff !== 0) {
            applyTranslate(oriented, loc.xoff, loc.yoff, loc.zoff);
        }
    }

    return oriented;
}

// ── Vertex-buffer helpers ────────────────────────────────────────

/** Per-axis scale around the model origin. Mirrors rt4 RawModel.resize. */
function applyResize(m: RawModel530Data, sx: number, sy: number, sz: number): void {
    const vx = m.vertexX;
    const vy = m.vertexY;
    const vz = m.vertexZ;
    const n = m.vertexCount;
    // rt4 stores resize as Q7 fixed-point: 128 = 1.0×.
    for (let i = 0; i < n; i++) {
        vx[i] = ((vx[i] * sx) / 128) | 0;
        vy[i] = ((vy[i] * sy) / 128) | 0;
        vz[i] = ((vz[i] * sz) / 128) | 0;
    }
}

/** Per-axis translate. Mirrors rt4 RawModel.translate. */
function applyTranslate(m: RawModel530Data, dx: number, dy: number, dz: number): void {
    const vx = m.vertexX;
    const vy = m.vertexY;
    const vz = m.vertexZ;
    const n = m.vertexCount;
    for (let i = 0; i < n; i++) {
        vx[i] += dx;
        vy[i] += dy;
        vz[i] += dz;
    }
}

/**
 * Deep-copy every array a downstream mutator (recolor / orient / resize /
 * translate) might touch. Any shared reference would corrupt the cached
 * source RawModel530 in the caller's loader.
 */
function shallowCopyMesh(m: RawModel530Data): RawModel530Data {
    return {
        id: m.id,
        vertexCount: m.vertexCount,
        triangleCount: m.triangleCount,
        texturedCount: m.texturedCount,
        vertexX: m.vertexX.slice(),
        vertexY: m.vertexY.slice(),
        vertexZ: m.vertexZ.slice(),
        vertexBones: m.vertexBones ? m.vertexBones.slice() : null,
        triangleVertexA: m.triangleVertexA.slice(),
        triangleVertexB: m.triangleVertexB.slice(),
        triangleVertexC: m.triangleVertexC.slice(),
        triangleInfo: m.triangleInfo ? m.triangleInfo.slice() : null,
        trianglePriorities: m.trianglePriorities ? m.trianglePriorities.slice() : null,
        triangleAlpha: m.triangleAlpha ? m.triangleAlpha.slice() : null,
        triangleBones: m.triangleBones ? m.triangleBones.slice() : null,
        triangleTextures: m.triangleTextures ? m.triangleTextures.slice() : null,
        triangleTextureIndex: m.triangleTextureIndex ? m.triangleTextureIndex.slice() : null,
        triangleColors: m.triangleColors.slice(),
        priority: m.priority,
        textureTypes: m.textureTypes ? m.textureTypes.slice() : null,
        textureFacesP: m.textureFacesP ? m.textureFacesP.slice() : null,
        textureFacesM: m.textureFacesM ? m.textureFacesM.slice() : null,
        textureFacesN: m.textureFacesN ? m.textureFacesN.slice() : null,
        texturesScaleX: m.texturesScaleX ? m.texturesScaleX.slice() : null,
        texturesScaleY: m.texturesScaleY ? m.texturesScaleY.slice() : null,
        texturesScaleZ: m.texturesScaleZ ? m.texturesScaleZ.slice() : null,
        textureRotationY: m.textureRotationY ? m.textureRotationY.slice() : null,
        textureExtraA: m.textureExtraA ? m.textureExtraA.slice() : null,
        textureExtraB: m.textureExtraB ? m.textureExtraB.slice() : null,
        cubeExtraA: m.cubeExtraA ? m.cubeExtraA.slice() : null,
        cubeExtraB: m.cubeExtraB ? m.cubeExtraB.slice() : null,
    };
}
