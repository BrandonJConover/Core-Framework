// .npc-appearance-test.mjs — offline gates for P5 NPC render wire.
//
// Hand-rolls 2 NpcType530Data fixtures (one with 1 modelIndex, one
// with 2 modelIndices + a recolor src/dst pair), per-id RawModel530Data
// fixtures, and asserts that composeNpcModel + attachNpcAppearance530
// produce the expected composite + recolor effect + idempotent attach.
//
// Run:    node 2009scape-web/client-patch/.npc-appearance-test.mjs

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── inlined mergeRawModels (mirrors PlayerAppearance530.ts) ──

function mergeRawModels(models, forceCopy = false) {
    const valid = models.filter(m => m !== null && m !== undefined);
    if (valid.length === 0) return null;
    if (valid.length === 1 && !forceCopy) return valid[0];

    let totalV = 0, totalT = 0, totalTex = 0;
    let needsBones = false, needsAlpha = false, needsPri = false;
    let needsTex = false, needsTexIdx = false, needsInfo = false;
    for (const m of valid) {
        totalV += m.vertexCount;
        totalT += m.triangleCount;
        totalTex += m.texturedCount ?? 0;
        if (m.vertexBones) needsBones = true;
        if (m.triangleAlpha) needsAlpha = true;
        if (m.trianglePriorities) needsPri = true;
        if (m.triangleTextures) needsTex = true;
        if (m.triangleTextureIndex) needsTexIdx = true;
        if (m.triangleInfo) needsInfo = true;
    }

    const out = {
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
    };

    let vOff = 0, tOff = 0;
    for (const m of valid) {
        for (let i = 0; i < m.vertexCount; i++) {
            out.vertexX[vOff + i] = m.vertexX[i];
            out.vertexY[vOff + i] = m.vertexY[i];
            out.vertexZ[vOff + i] = m.vertexZ[i];
            if (out.vertexBones) out.vertexBones[vOff + i] = m.vertexBones ? m.vertexBones[i] : 0;
        }
        for (let i = 0; i < m.triangleCount; i++) {
            out.triangleVertexA[tOff + i] = m.triangleVertexA[i] + vOff;
            out.triangleVertexB[tOff + i] = m.triangleVertexB[i] + vOff;
            out.triangleVertexC[tOff + i] = m.triangleVertexC[i] + vOff;
            out.triangleColors[tOff + i] = m.triangleColors[i];
            if (out.triangleTextures) {
                out.triangleTextures[tOff + i] = m.triangleTextures ? m.triangleTextures[i] : -1;
            }
            if (out.triangleAlpha) out.triangleAlpha[tOff + i] = m.triangleAlpha ? m.triangleAlpha[i] : 0;
            if (out.trianglePriorities) out.trianglePriorities[tOff + i] = m.trianglePriorities ? m.trianglePriorities[i] : 0;
            if (out.triangleInfo) out.triangleInfo[tOff + i] = m.triangleInfo ? m.triangleInfo[i] : 0;
        }
        vOff += m.vertexCount;
        tOff += m.triangleCount;
    }
    return out;
}

// ── inlined NpcAppearance530 ──

async function composeNpcModel(npcType, rawModelLoader) {
    const ids = npcType.modelIndices;
    if (!ids || ids.length === 0) return null;
    const parts = [];
    for (let i = 0; i < ids.length; i++) parts.push(await rawModelLoader(ids[i]));
    const merged = mergeRawModels(parts, true);
    if (!merged) return null;
    if (npcType.recol_s && npcType.recol_d) applyRecolor(merged, npcType.recol_s, npcType.recol_d);
    if (npcType.retex_s && npcType.retex_d) applyRetex(merged, npcType.retex_s, npcType.retex_d);
    return merged;
}

function applyRecolor(model, src, dst) {
    if (!model.triangleColors) return 0;
    const pairCount = Math.min(src.length, dst.length);
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

function applyRetex(model, src, dst) {
    if (!model.triangleTextures) return 0;
    const pairCount = Math.min(src.length, dst.length);
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

// ── inlined NpcAttacher530 ──

function attachNpcAppearance530(npc, mesh, bridge) {
    if (!mesh || mesh.vertexCount === 0) return null;
    const bridged = bridge.attachModel(mesh);
    if (!bridged) return null;
    if (npc.appearanceModel530 && typeof npc.appearanceModel530.reset === "function") {
        npc.appearanceModel530.reset();
    }
    npc.appearanceModel530 = bridged;
    return bridged;
}

// ── fixtures ────────────────────────────────────────────────────────

// Per-model fixture: 4 verts, 2 triangles, distinct face colors so we
// can spot recolor effects.
function tinyModel(id, baseColor) {
    return {
        id,
        vertexCount: 4,
        triangleCount: 2,
        texturedCount: 0,
        vertexX: [0, 10, 10, 0], vertexY: [0, 0, 0, 0], vertexZ: [0, 0, 10, 10],
        vertexBones: null,
        triangleVertexA: [0, 0],
        triangleVertexB: [1, 2],
        triangleVertexC: [2, 3],
        triangleColors: [baseColor, baseColor + 1],
        triangleAlpha: null,
        trianglePriorities: null,
        triangleInfo: null,
        triangleTextures: [10, 11],
        triangleTextureIndex: null,
        textureTypes: null, textureFacesP: null, textureFacesM: null, textureFacesN: null,
    };
}

const modelLib = {
    100: tinyModel(100, 0x1111),
    200: tinyModel(200, 0x2222),
};

const loader = async (id) => modelLib[id] ?? null;

// Fixture A: single modelIndex, no recolor.
const npcA = {
    id: 1, modelIndices: [100],
    recol_s: null, recol_d: null,
    retex_s: null, retex_d: null,
};

// Fixture B: two modelIndices + recolor pair (replaces 0x2222 → 0xBEEF).
const npcB = {
    id: 2, modelIndices: [100, 200],
    recol_s: [0x2222],
    recol_d: [0xBEEF],
    retex_s: [10],
    retex_d: [99],
};

// ── run gates ───────────────────────────────────────────────────────

const meshA = await composeNpcModel(npcA, loader);
const meshB = await composeNpcModel(npcB, loader);

// Composite vert/tri counts.
if (meshA.vertexCount !== 4) throw new Error(`A vert expected 4 got ${meshA.vertexCount}`);
if (meshB.vertexCount !== 8) throw new Error(`B vert expected 8 got ${meshB.vertexCount}`);
if (meshB.triangleCount !== 4) throw new Error(`B tri expected 4 got ${meshB.triangleCount}`);

// Index rebase: every triangle index must point inside the merged vert array.
for (let i = 0; i < meshB.triangleCount; i++) {
    const a = meshB.triangleVertexA[i], b = meshB.triangleVertexB[i], c = meshB.triangleVertexC[i];
    if (a < 0 || a >= meshB.vertexCount) throw new Error(`triA idx out of range at ${i}: ${a}`);
    if (b < 0 || b >= meshB.vertexCount) throw new Error(`triB idx out of range at ${i}: ${b}`);
    if (c < 0 || c >= meshB.vertexCount) throw new Error(`triC idx out of range at ${i}: ${c}`);
}

// Recolor: 0x2222 entries from model 200 must have been replaced.
let recolorReplaced = 0;
for (const c of meshB.triangleColors) if (c === 0xBEEF) recolorReplaced++;
if (recolorReplaced !== 1) {
    // model 200 had 1 face colored 0x2222 (the other was 0x2223)
    throw new Error(`recolor replacement count expected 1 got ${recolorReplaced}, colors=${meshB.triangleColors.map(x=>x.toString(16))}`);
}

// Retex: 10 → 99 across all faces that had 10.
let retexReplaced = 0;
for (const t of meshB.triangleTextures) if (t === 99) retexReplaced++;
// Both models had 1 face with texture id 10 → 2 replacements expected.
if (retexReplaced !== 2) {
    throw new Error(`retex replacement count expected 2 got ${retexReplaced}, textures=${JSON.stringify(meshB.triangleTextures)}`);
}

// Attacher: bridge stub that records reset() calls.
let resetCalls = 0;
const fakeBridge = {
    attachModel(mesh) {
        return { vertCount: mesh.vertexCount, reset() { resetCalls++; }, _id: Math.random() };
    },
};

const npcRecord = {};

const attached1 = attachNpcAppearance530(npcRecord, meshA, fakeBridge);
if (!npcRecord.appearanceModel530) throw new Error("first attach: appearanceModel530 not set");
if (resetCalls !== 0) throw new Error(`first attach should not reset (count=${resetCalls})`);

const attached2 = attachNpcAppearance530(npcRecord, meshB, fakeBridge);
if (npcRecord.appearanceModel530 === attached1) throw new Error("second attach did not replace prior");
if (npcRecord.appearanceModel530 !== attached2) throw new Error("appearanceModel530 not pointing at second bridged model");
if (resetCalls !== 1) throw new Error(`second attach should reset prior exactly once (count=${resetCalls})`);

// Empty-mesh attach: must not touch the slot.
const attached3 = attachNpcAppearance530(npcRecord, null, fakeBridge);
if (attached3 !== null) throw new Error("null mesh attach should return null");
if (npcRecord.appearanceModel530 !== attached2) throw new Error("null mesh attach must not replace prior");

// ── trace ──

const trace = [
    `# Captured by .npc-appearance-test.mjs at ${new Date().toISOString()}`,
    `# All assertions passed: composeNpcModel, mergeRawModels, applyRecolor, applyRetex, attachNpcAppearance530`,
    `# Fixture A: 1 modelIndex (id=100). Fixture B: 2 modelIndices (100+200) + recolor + retex.`,
    ``,
    `[NpcAppearance530] composed verts=${meshB.vertexCount} tris=${meshB.triangleCount}`,
    `[NpcAppearance530] recolor-replaced=${recolorReplaced} retex-replaced=${retexReplaced}`,
    `[NpcAttacher530] attach+replace ok (resetCalls=${resetCalls})`,
    `[NpcAppearance530] index rebase OK: maxIdx=${Math.max(...meshB.triangleVertexA, ...meshB.triangleVertexB, ...meshB.triangleVertexC)} verts=${meshB.vertexCount}`,
].join("\n") + "\n";

const tracePath = join(__dirname, ".npc-appearance-trace.txt");
writeFileSync(tracePath, trace);
console.log(`[npc-appearance] trace captured at ${tracePath}`);
console.log(`[npc-appearance] all assertions passed`);
