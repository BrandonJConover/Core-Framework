/**
 * PlayerAppearance530 — TypeScript port of the rev-530 player avatar
 * pipeline. Decodes the APPEARANCE block from PLAYER_INFO into a clean
 * record, composes the avatar mesh by resolving each of the 12 slots
 * to either an IdkType wardrobe piece or an ObjType equipment item,
 * merges the per-slot RawModel530s into a single composite, and applies
 * the 5-color palette recolor (body + skin tables).
 *
 * Source of truth (rt4 reference, read-only):
 *   reference/rt4-client/client/src/main/java/rt4/PlayerAppearance.java
 *     - method1954        body composition  (line 247)
 *     - method1956        head composition  (line 537)
 *     - method1946        head merge x3     (line 132)
 *     - aShortArray65/41  source colors     (body / skin)
 *     - destinationBodyColors/SkinColors    palette tables
 *   reference/rt4-client/client/src/main/java/rt4/IdkType.java
 *   reference/rt4-client/client/src/main/java/rt4/ObjType.java
 *     - manwear/manwear2/manwear3    op 23/24/78 (male body models)
 *     - womanwear/womanwear2/womanwear3 op 25/26/79 (female body models)
 *
 * Byte format (the canonical 530 mask, mirrored verbatim against the
 * existing parseAppearanceMask path in PacketHandler530.ts:1599):
 *
 *   g1     settings   (bit0=female, bit2=showSkillLevel)
 *   g1b    skull
 *   g1b    prayer / head icon
 *   12 ×   { g1 upper; if upper==0 → empty; else g1 lower → raw=upper<<8|lower
 *           if slot==0 && raw==0xFFFF → npcTransform: g2 npcId, g1 team }
 *   raw < 32768  → IdkType id (raw)
 *   raw >= 32768 → ObjType id (raw - 32768)
 *   5  ×   g1     color palette indices (hair, torso, legs, feet, skin)
 *   g2     basId (animation skeleton id)
 *   8  ×   g1     base37 username (skipped, captured into username buffer)
 *   g1     combat level
 *   if (settings & 0x4): g2 skillLevel  else: skip 2
 *   g1     soundRadius; if !=0 skip 8
 *
 * Pipeline (composeAppearanceModel):
 *
 *   for slot in 0..11:
 *     if slot.kind == "idk":
 *       models = IdkType530.bodyModels                  (op 2)
 *     elif slot.kind == "obj":
 *       gender == 0:  [obj.manwear, obj.manwear2, obj.manwear3]  (filtered != -1)
 *       gender == 1:  [obj.womanwear, obj.womanwear2, obj.womanwear3]
 *     load each RawModel530 → mergeRawModels → recolor 5 channels →
 *     return composite RawModel530Data ready for Model530Bridge.attachModel
 */

import { RawModel530Data } from "../../cache/def/RawModel530";
import { IdkType530Data } from "../../cache/def/IdkType530";
import { ObjType530Data } from "../../cache/def/ObjType530";

// ── Slot encoding ─────────────────────────────────────────────────

/** A single decoded appearance slot. */
export type AppearanceSlot =
    | { kind: "empty" }
    | { kind: "idk"; idkId: number }
    | { kind: "obj"; objId: number };

/** Raw decoded record from parseAppearanceMask. */
export interface PlayerAppearance530Data {
    /** 12 mixed wardrobe + equipment slots. */
    slots: AppearanceSlot[];
    /** 5 palette indices: hair, torso, legs, feet, skin. */
    colors: number[];
    /** Animation skeleton id (BasType530 lookup). */
    basId: number;
    /** 0 = male, 1 = female. Derived from settings bit 0. */
    gender: number;
    /** Skull icon id. -1 / 0 = none. */
    skull: number;
    /** Prayer / overhead icon. -1 = none. */
    prayer: number;
    /** When set, the player is visually transformed into this NPC type. -1 = none. */
    npcTransform: number;
    /** Combat level shown in right-click menu. */
    combatLevel: number;
    /** Skill level (only present when settings.bit2 == 1). 0 otherwise. */
    skillLevel: number;
    /** Stable cache key derived from slots + colors + gender. */
    bodyHash: number;
    /** Settings byte verbatim. */
    settings: number;
}

// ── Reader ────────────────────────────────────────────────────────

class AppearanceReader {
    public buf: Uint8Array;
    public pos: number;
    constructor(buf: Uint8Array, pos: number = 0) { this.buf = buf; this.pos = pos; }
    g1(): number { return this.buf[this.pos++] & 0xFF; }
    g1b(): number {
        const v = this.buf[this.pos++];
        return (v << 24) >> 24;
    }
    g2(): number {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        return (a << 8) | b;
    }
    skip(n: number): void { this.pos += n; }
}

// ── parseAppearanceMask ──────────────────────────────────────────

/**
 * Decode the APPEARANCE block (the bytes the server emits inside the
 * APPEARANCE mask of PLAYER_INFO). Returns null when the block can't be
 * fully consumed (truncated mask) — caller should fall back to the
 * cached appearance.
 */
export function parseAppearanceMask(bytes: Uint8Array): PlayerAppearance530Data | null {
    if (bytes.byteLength < 4) return null;
    const r = new AppearanceReader(bytes);

    const settings = r.g1();
    const gender = settings & 0x1;
    const showSkillLevel = (settings & 0x4) !== 0;
    const skull = r.g1b();
    const prayer = r.g1b();

    const slots: AppearanceSlot[] = [];
    let npcTransform = -1;

    for (let part = 0; part < 12; part++) {
        const upper = r.g1();
        if (upper === 0) {
            slots.push({ kind: "empty" });
            continue;
        }
        const lower = r.g1();
        const raw = (upper << 8) | lower;

        if (part === 0 && raw === 0xFFFF) {
            // NPC transform: read npc id then team byte. Remaining slots
            // become empty — the npcTransform field replaces the avatar.
            npcTransform = r.g2();
            r.skip(1);
            for (let p2 = part; p2 < 12; p2++) slots.push({ kind: "empty" });
            break;
        }

        if (raw < 32768) {
            slots.push({ kind: "idk", idkId: raw });
        } else {
            slots.push({ kind: "obj", objId: raw - 32768 });
        }
    }

    const colors: number[] = [];
    for (let i = 0; i < 5; i++) colors.push(r.g1());

    const basId = r.g2();

    // Username (8 bytes, base37 — we don't decode it here; consumers
    // already have the player's name from the login channel).
    r.skip(8);

    const combatLevel = r.g1();
    let skillLevel = 0;
    if (showSkillLevel) {
        skillLevel = r.g2();
    } else {
        r.skip(2);
    }

    const soundRadius = r.g1();
    if (soundRadius !== 0) r.skip(8);

    return {
        slots,
        colors,
        basId,
        gender,
        skull,
        prayer,
        npcTransform,
        combatLevel,
        skillLevel,
        bodyHash: hashAppearance(slots, colors, gender),
        settings,
    };
}

function hashAppearance(slots: AppearanceSlot[], colors: number[], gender: number): number {
    let h = (gender * 31) | 0;
    for (let i = 0; i < slots.length; i++) {
        const s = slots[i];
        let key = 0;
        if (s.kind === "idk") key = (s.idkId | 0) | 0x40000;
        else if (s.kind === "obj") key = (s.objId | 0) | 0x80000;
        h = (Math.imul(h, 31) + key) | 0;
    }
    for (let i = 0; i < colors.length; i++) {
        h = (Math.imul(h, 17) + colors[i]) | 0;
    }
    return h >>> 0;
}

// ── mergeRawModels ───────────────────────────────────────────────

/**
 * Concatenate N RawModel530s into one. Mirrors the rt4
 * `RawModel(RawModel[] models, int count)` constructor: vertex arrays
 * are copied flat, triangle indices are rebased by the running
 * vertex-offset, color/alpha/priority arrays are concatenated, textured
 * faces are likewise rebased.
 *
 * Returns null when models is empty. When models has one entry it
 * returns a shallow alias (no copy) — the caller must NOT mutate the
 * returned data unless they pass `forceCopy = true`.
 */
export function mergeRawModels(
    models: (RawModel530Data | null)[],
    forceCopy: boolean = false,
): RawModel530Data | null {
    const valid = models.filter((m): m is RawModel530Data => m !== null);
    if (valid.length === 0) return null;
    if (valid.length === 1 && !forceCopy) return valid[0];

    let totalV = 0, totalT = 0, totalTex = 0;
    let needsBones = false, needsAlpha = false, needsPri = false;
    let needsTex = false, needsTexIdx = false, needsInfo = false;
    for (const m of valid) {
        totalV += m.vertexCount;
        totalT += m.triangleCount;
        totalTex += m.texturedCount;
        if (m.vertexBones) needsBones = true;
        if (m.triangleAlpha) needsAlpha = true;
        if (m.trianglePriorities) needsPri = true;
        if (m.triangleTextures) needsTex = true;
        if (m.triangleTextureIndex) needsTexIdx = true;
        if (m.triangleInfo) needsInfo = true;
    }

    const out: RawModel530Data = {
        id: -1,
        vertexCount: totalV,
        triangleCount: totalT,
        texturedCount: totalTex,
        vertexX: new Array(totalV),
        vertexY: new Array(totalV),
        vertexZ: new Array(totalV),
        vertexBones: needsBones ? new Array(totalV) : null,
        triangleVertexA: new Array(totalT),
        triangleVertexB: new Array(totalT),
        triangleVertexC: new Array(totalT),
        triangleInfo: needsInfo ? new Array(totalT) : null,
        trianglePriorities: needsPri ? new Array(totalT) : null,
        triangleAlpha: needsAlpha ? new Array(totalT) : null,
        triangleBones: null,
        triangleTextures: needsTex ? new Array(totalT) : null,
        triangleTextureIndex: needsTexIdx ? new Array(totalT) : null,
        triangleColors: new Array(totalT),
        priority: 0,
        textureTypes: totalTex > 0 ? new Array(totalTex) : null,
        textureFacesP: totalTex > 0 ? new Array(totalTex) : null,
        textureFacesM: totalTex > 0 ? new Array(totalTex) : null,
        textureFacesN: totalTex > 0 ? new Array(totalTex) : null,
        texturesScaleX: null,
        texturesScaleY: null,
        texturesScaleZ: null,
        textureRotationY: null,
        textureExtraA: null,
        textureExtraB: null,
        cubeExtraA: null,
        cubeExtraB: null,
    };

    let vOff = 0, tOff = 0, texOff = 0;
    for (const m of valid) {
        for (let i = 0; i < m.vertexCount; i++) {
            out.vertexX[vOff + i] = m.vertexX[i];
            out.vertexY[vOff + i] = m.vertexY[i];
            out.vertexZ[vOff + i] = m.vertexZ[i];
            if (out.vertexBones) {
                out.vertexBones[vOff + i] = m.vertexBones ? m.vertexBones[i] : 0;
            }
        }
        for (let i = 0; i < m.triangleCount; i++) {
            out.triangleVertexA[tOff + i] = m.triangleVertexA[i] + vOff;
            out.triangleVertexB[tOff + i] = m.triangleVertexB[i] + vOff;
            out.triangleVertexC[tOff + i] = m.triangleVertexC[i] + vOff;
            out.triangleColors[tOff + i] = m.triangleColors[i];
            if (out.triangleInfo) out.triangleInfo[tOff + i] = m.triangleInfo ? m.triangleInfo[i] : 0;
            if (out.trianglePriorities) out.trianglePriorities[tOff + i] = m.trianglePriorities ? m.trianglePriorities[i] : 0;
            if (out.triangleAlpha) out.triangleAlpha[tOff + i] = m.triangleAlpha ? m.triangleAlpha[i] : 0;
            if (out.triangleTextures) out.triangleTextures[tOff + i] = m.triangleTextures ? m.triangleTextures[i] : -1;
            if (out.triangleTextureIndex) {
                const idx = m.triangleTextureIndex ? m.triangleTextureIndex[i] : -1;
                out.triangleTextureIndex[tOff + i] = idx >= 0 ? idx + texOff : -1;
            }
        }
        for (let i = 0; i < m.texturedCount; i++) {
            if (out.textureTypes && m.textureTypes) out.textureTypes[texOff + i] = m.textureTypes[i];
            if (out.textureFacesP && m.textureFacesP) out.textureFacesP[texOff + i] = m.textureFacesP[i] + vOff;
            if (out.textureFacesM && m.textureFacesM) out.textureFacesM[texOff + i] = m.textureFacesM[i] + vOff;
            if (out.textureFacesN && m.textureFacesN) out.textureFacesN[texOff + i] = m.textureFacesN[i] + vOff;
        }
        vOff += m.vertexCount;
        tOff += m.triangleCount;
        texOff += m.texturedCount;
    }

    return out;
}

// ── Recolor ──────────────────────────────────────────────────────

/** rt4 PlayerAppearance.aShortArray65 — body source colors (5 channels). */
export const BODY_SOURCE_COLORS: number[] = [8741, 12, 64030, 43162, 7531];
/** rt4 PlayerAppearance.aShortArray41 — skin source colors (5 channels). */
export const SKIN_SOURCE_COLORS: number[] = [8741, 12, 64030, 43162, 7531];

/**
 * Replace `srcColor` with `dstColor` everywhere in the model's
 * triangleColors. Mirrors rt4 RawModel.recolor(short, short).
 */
export function recolorModel(m: RawModel530Data, srcColor: number, dstColor: number): void {
    const s = srcColor & 0xFFFF;
    const d = dstColor & 0xFFFF;
    for (let i = 0; i < m.triangleCount; i++) {
        if ((m.triangleColors[i] & 0xFFFF) === s) m.triangleColors[i] = d;
    }
}

/**
 * Replace `srcTex` with `dstTex` in the model's triangleTextures (when
 * present). Mirrors rt4 RawModel.retexture(short, short).
 */
export function retextureModel(m: RawModel530Data, srcTex: number, dstTex: number): void {
    if (!m.triangleTextures) return;
    const s = srcTex & 0xFFFF;
    const d = dstTex & 0xFFFF;
    for (let i = 0; i < m.triangleCount; i++) {
        if ((m.triangleTextures[i] & 0xFFFF) === s) m.triangleTextures[i] = d;
    }
}

// ── composeAppearanceModel ───────────────────────────────────────

/** Per-slot model-id resolver result. */
export interface SlotResolution {
    /** Model ids contributing to this slot's mesh (in concat order). */
    modelIds: number[];
    /** Recolor source/destination shorts inherited from the slot's IdkType / ObjType. */
    recolSrc: number[];
    recolDst: number[];
    /** Retexture source/destination shorts inherited from the slot. */
    retexSrc: number[];
    retexDst: number[];
}

/**
 * Resolve a slot to its contributing model ids. Empty slot returns
 * empty arrays. IdkType slots use bodyModels; ObjType slots use the
 * gender-appropriate manwear* / womanwear* fields (filtered for -1).
 */
export function resolveSlot(
    slot: AppearanceSlot,
    gender: number,
    idkLookup: (id: number) => IdkType530Data | null,
    objLookup: (id: number) => ObjType530Data | null,
): SlotResolution {
    const r: SlotResolution = {
        modelIds: [], recolSrc: [], recolDst: [], retexSrc: [], retexDst: [],
    };
    if (slot.kind === "empty") return r;

    if (slot.kind === "idk") {
        const idk = idkLookup(slot.idkId);
        if (!idk || idk.disable) return r;
        if (idk.bodyModels) for (const m of idk.bodyModels) r.modelIds.push(m);
        if (idk.recol_s && idk.recol_d) {
            for (let i = 0; i < idk.recol_s.length; i++) {
                r.recolSrc.push(idk.recol_s[i]);
                r.recolDst.push(idk.recol_d[i]);
            }
        }
        if (idk.retex_s && idk.retex_d) {
            for (let i = 0; i < idk.retex_s.length; i++) {
                r.retexSrc.push(idk.retex_s[i]);
                r.retexDst.push(idk.retex_d[i]);
            }
        }
        return r;
    }

    // slot.kind === "obj"
    const obj = objLookup(slot.objId);
    if (!obj) return r;
    const ids = gender === 0
        ? [obj.manwear, obj.manwear2, obj.manwear3]
        : [obj.womanwear, obj.womanwear2, obj.womanwear3];
    for (const id of ids) {
        if (id !== -1 && id !== undefined) r.modelIds.push(id);
    }
    // ObjType530 carries recol_s/recol_d/retex_s/retex_d analogous to IdkType.
    const o = obj as any;
    if (o.recol_s && o.recol_d) {
        for (let i = 0; i < o.recol_s.length; i++) {
            r.recolSrc.push(o.recol_s[i]);
            r.recolDst.push(o.recol_d[i]);
        }
    }
    if (o.retex_s && o.retex_d) {
        for (let i = 0; i < o.retex_s.length; i++) {
            r.retexSrc.push(o.retex_s[i]);
            r.retexDst.push(o.retex_d[i]);
        }
    }
    return r;
}

/**
 * Build the composite avatar mesh from a decoded appearance record.
 * Caller supplies sync-or-async IdkType / ObjType / RawModel resolvers
 * so the function is testable without Js5Cache.
 *
 * Returns null when no slot contributes any model.
 */
export async function composeAppearanceModel(
    app: PlayerAppearance530Data,
    idkLookup: (id: number) => IdkType530Data | null,
    objLookup: (id: number) => ObjType530Data | null,
    rawModelLoader: (id: number) => Promise<RawModel530Data | null>,
    /** Per-color-channel destination color tables, indexed [channel][paletteIdx]. */
    destBodyColors: number[][] | null = null,
    destSkinColors: number[][] | null = null,
): Promise<RawModel530Data | null> {
    // Phase 1: resolve all slots.
    const resolutions: SlotResolution[] = [];
    const allModelIds: number[] = [];
    for (const slot of app.slots) {
        const res = resolveSlot(slot, app.gender, idkLookup, objLookup);
        resolutions.push(res);
        for (const id of res.modelIds) allModelIds.push(id);
    }

    if (allModelIds.length === 0) return null;

    // Phase 2: load each unique model once.
    const cache = new Map<number, RawModel530Data | null>();
    for (const id of allModelIds) {
        if (!cache.has(id)) cache.set(id, await rawModelLoader(id));
    }

    // Phase 3: per-slot, fetch + apply per-slot recolor/retexture, then
    // collect the slot's models for the master merge. We deep-copy the
    // per-slot models before recolor so the cache stays clean.
    const perSlotModels: RawModel530Data[] = [];
    for (let s = 0; s < app.slots.length; s++) {
        const res = resolutions[s];
        for (const modelId of res.modelIds) {
            const cached = cache.get(modelId);
            if (!cached) continue;
            const copy = shallowCopyRawModel(cached);
            for (let i = 0; i < res.recolSrc.length; i++) {
                recolorModel(copy, res.recolSrc[i], res.recolDst[i]);
            }
            for (let i = 0; i < res.retexSrc.length; i++) {
                retextureModel(copy, res.retexSrc[i], res.retexDst[i]);
            }
            perSlotModels.push(copy);
        }
    }

    if (perSlotModels.length === 0) return null;

    // Phase 4: merge into one composite.
    const merged = mergeRawModels(perSlotModels, true);
    if (!merged) return null;

    // Phase 5: apply the player's 5-channel palette recolor.
    if (destBodyColors && destSkinColors && app.colors.length === 5) {
        for (let c = 0; c < 5; c++) {
            const palette = app.colors[c];
            if (destBodyColors[c] && palette < destBodyColors[c].length) {
                recolorModel(merged, BODY_SOURCE_COLORS[c], destBodyColors[c][palette]);
            }
            if (destSkinColors[c] && palette < destSkinColors[c].length) {
                recolorModel(merged, SKIN_SOURCE_COLORS[c], destSkinColors[c][palette]);
            }
        }
    }

    return merged;
}

function shallowCopyRawModel(m: RawModel530Data): RawModel530Data {
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

// ── applyAppearanceMask (top-level entry) ────────────────────────

/** Minimal Player shape PlayerAppearance530 mutates. */
export interface AppearanceTarget {
    appearance530?: PlayerAppearance530Data;
    composedModel530?: RawModel530Data | null;
    /** Set true after applyAppearanceMask runs so the renderer rebuilds. */
    appearanceDirty?: boolean;
}

/**
 * Top-level entry consumed by PacketHandler530's APPEARANCE handler.
 * Decodes the bytes into PlayerAppearance530Data, stores it on the
 * player, and marks the player dirty for the next composite rebuild.
 *
 * Composition itself is async (model loads from idx7) so it doesn't
 * happen here — Game.ts/Scene.ts polls `appearanceDirty` on the next
 * frame and runs composeAppearanceModel.
 */
export function applyAppearanceMask(player: AppearanceTarget, maskBytes: Uint8Array): boolean {
    const decoded = parseAppearanceMask(maskBytes);
    if (!decoded) return false;
    player.appearance530 = decoded;
    player.appearanceDirty = true;
    return true;
}
