// NpcAppearance530 — composes a single RawModel530-shaped mesh from an
// NpcType530 record's modelIndices, applies recolor + retexture lists,
// and hands the result back to a renderer that already knows how to
// bridge it via Model530Bridge.
//
// rt4 reference:
//   - NpcType.getModel() — assembles the same composite from
//     `modelIndices` + recol_s/d + retex_s/d.
//   - mergeRawModels(...) lives on PlayerAppearance530.ts; we re-use it
//     so Player and NPC paths produce the same RawModel530 shape.
//
// Scope: data-side compose only. Bridge attach is a sibling concern in
// NpcAttacher530.ts so this module stays import-free of the renderer.

import type { NpcType530Data } from "../cache/def/NpcType530";
import type { RawModel530Data } from "../cache/def/RawModel530";
import { mergeRawModels } from "../media/renderable/PlayerAppearance530";

/** Async loader the caller plugs in. Lets us mock RawModel530.load in
 *  the offline trace harness without touching Js5Cache. */
export type RawModel530Loader = (id: number) => Promise<RawModel530Data | null>;

/**
 * Build the composite render mesh for `npcType`. Returns null when the
 * type has no model entries or every load resolves null.
 *
 * The function is idempotent on its inputs: it does not mutate the
 * NpcType530Data record. The returned RawModel530Data IS mutated by
 * the recolor / retex passes, but it's freshly merged so the
 * underlying per-piece RawModel530Data caches are left untouched
 * (mergeRawModels copies into a new arrays struct when count > 1).
 */
export async function composeNpcModel(
    npcType: NpcType530Data,
    rawModelLoader: RawModel530Loader,
): Promise<RawModel530Data | null> {
    const ids = npcType.modelIndices;
    if (!ids || ids.length === 0) return null;

    const parts: (RawModel530Data | null)[] = [];
    for (let i = 0; i < ids.length; i++) {
        parts.push(await rawModelLoader(ids[i]));
    }
    // forceCopy=true so the recolor / retex passes don't mutate cached
    // single-piece RawModel530 instances when modelIndices.length === 1.
    const merged = mergeRawModels(parts, /* forceCopy */ true);
    if (!merged) return null;

    if (npcType.recol_s && npcType.recol_d) {
        applyRecolor(merged, npcType.recol_s, npcType.recol_d);
    }
    if (npcType.retex_s && npcType.retex_d) {
        applyRetex(merged, npcType.retex_s, npcType.retex_d);
    }
    return merged;
}

/** Find-and-replace per-triangle color codes. Source/destination arrays
 *  are paired by index (recol_s[i] → recol_d[i]). */
export function applyRecolor(
    model: RawModel530Data,
    src: number[],
    dst: number[],
): number {
    if (!model.triangleColors) return 0;
    const pairCount = Math.min(src.length, dst.length);
    if (pairCount === 0) return 0;
    let replaced = 0;
    const tc = model.triangleColors;
    for (let i = 0; i < tc.length; i++) {
        const c = tc[i];
        for (let p = 0; p < pairCount; p++) {
            if (c === src[p]) { tc[i] = dst[p]; replaced++; break; }
        }
    }
    return replaced;
}

/** Same shape as recolor but on the per-triangle texture id array. */
export function applyRetex(
    model: RawModel530Data,
    src: number[],
    dst: number[],
): number {
    if (!model.triangleTextures) return 0;
    const pairCount = Math.min(src.length, dst.length);
    if (pairCount === 0) return 0;
    let replaced = 0;
    const tt = model.triangleTextures;
    for (let i = 0; i < tt.length; i++) {
        const t = tt[i];
        if (t < 0) continue;
        for (let p = 0; p < pairCount; p++) {
            if (t === src[p]) { tt[i] = dst[p]; replaced++; break; }
        }
    }
    return replaced;
}
