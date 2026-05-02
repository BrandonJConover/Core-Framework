// .player-appearance-test.mjs — standalone trace harness for PlayerAppearance530.
//
// Pure ESM, mirrors the inline-fixture pattern from .first-light-test.mjs.
// Verifies the data-side completion gates:
//   1. parseAppearanceMask consumes a hand-rolled mask byte stream cleanly.
//   2. resolveSlot returns model ids per-slot using fixture Idk/Obj records.
//   3. mergeRawModels concatenates correctly: composite vertexCount ==
//      sum of slot vertexCounts.
//   4. Equipping a different weapon between two applyAppearanceMask calls
//      mutates the composite vertex buffer (vertexCount or positions
//      differ).
//
// Run with:    node 2009scape-web/client-patch/.player-appearance-test.mjs

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── inlined PlayerAppearance530 logic (mirrors PlayerAppearance530.ts) ──

class AppearanceReader {
    constructor(buf, pos = 0) { this.buf = buf; this.pos = pos; }
    g1() { return this.buf[this.pos++] & 0xFF; }
    g1b() {
        const v = this.buf[this.pos++];
        return (v << 24) >> 24;
    }
    g2() {
        const a = this.buf[this.pos++] & 0xFF;
        const b = this.buf[this.pos++] & 0xFF;
        return (a << 8) | b;
    }
    skip(n) { this.pos += n; }
}

function parseAppearanceMask(bytes) {
    if (bytes.byteLength < 4) return null;
    const r = new AppearanceReader(bytes);
    const settings = r.g1();
    const gender = settings & 0x1;
    const showSkillLevel = (settings & 0x4) !== 0;
    const skull = r.g1b();
    const prayer = r.g1b();
    const slots = [];
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
            npcTransform = r.g2();
            r.skip(1);
            for (let p2 = part; p2 < 12; p2++) slots.push({ kind: "empty" });
            break;
        }
        if (raw < 32768) slots.push({ kind: "idk", idkId: raw });
        else slots.push({ kind: "obj", objId: raw - 32768 });
    }
    const colors = [];
    for (let i = 0; i < 5; i++) colors.push(r.g1());
    const basId = r.g2();
    r.skip(8);
    const combatLevel = r.g1();
    let skillLevel = 0;
    if (showSkillLevel) skillLevel = r.g2();
    else r.skip(2);
    const soundRadius = r.g1();
    if (soundRadius !== 0) r.skip(8);
    return {
        slots, colors, basId, gender, skull, prayer,
        npcTransform, combatLevel, skillLevel, settings,
    };
}

function resolveSlot(slot, gender, idkLookup, objLookup) {
    const r = { modelIds: [], recolSrc: [], recolDst: [], retexSrc: [], retexDst: [] };
    if (slot.kind === "empty") return r;
    if (slot.kind === "idk") {
        const idk = idkLookup(slot.idkId);
        if (!idk || idk.disable) return r;
        if (idk.bodyModels) for (const m of idk.bodyModels) r.modelIds.push(m);
        return r;
    }
    const obj = objLookup(slot.objId);
    if (!obj) return r;
    const ids = gender === 0
        ? [obj.manwear, obj.manwear2, obj.manwear3]
        : [obj.womanwear, obj.womanwear2, obj.womanwear3];
    for (const id of ids) {
        if (id !== -1 && id !== undefined) r.modelIds.push(id);
    }
    return r;
}

function shallowCopyRawModel(m) {
    return JSON.parse(JSON.stringify(m));
}

function mergeRawModels(models) {
    const valid = models.filter(m => m !== null);
    if (valid.length === 0) return null;
    if (valid.length === 1) return valid[0];
    let totalV = 0, totalT = 0;
    for (const m of valid) { totalV += m.vertexCount; totalT += m.triangleCount; }
    const out = {
        id: -1,
        vertexCount: totalV, triangleCount: totalT, texturedCount: 0,
        vertexX: new Array(totalV), vertexY: new Array(totalV), vertexZ: new Array(totalV),
        vertexBones: null,
        triangleVertexA: new Array(totalT), triangleVertexB: new Array(totalT), triangleVertexC: new Array(totalT),
        triangleInfo: null, trianglePriorities: null, triangleAlpha: null,
        triangleBones: null, triangleTextures: null, triangleTextureIndex: null,
        triangleColors: new Array(totalT),
        priority: 0,
        textureTypes: null, textureFacesP: null, textureFacesM: null, textureFacesN: null,
        texturesScaleX: null, texturesScaleY: null, texturesScaleZ: null,
        textureRotationY: null, textureExtraA: null, textureExtraB: null,
        cubeExtraA: null, cubeExtraB: null,
    };
    let vOff = 0, tOff = 0;
    for (const m of valid) {
        for (let i = 0; i < m.vertexCount; i++) {
            out.vertexX[vOff + i] = m.vertexX[i];
            out.vertexY[vOff + i] = m.vertexY[i];
            out.vertexZ[vOff + i] = m.vertexZ[i];
        }
        for (let i = 0; i < m.triangleCount; i++) {
            out.triangleVertexA[tOff + i] = m.triangleVertexA[i] + vOff;
            out.triangleVertexB[tOff + i] = m.triangleVertexB[i] + vOff;
            out.triangleVertexC[tOff + i] = m.triangleVertexC[i] + vOff;
            out.triangleColors[tOff + i] = m.triangleColors[i];
        }
        vOff += m.vertexCount;
        tOff += m.triangleCount;
    }
    return out;
}

async function composeAppearanceModel(app, idkLookup, objLookup, rawModelLoader) {
    const allModelIds = [];
    const resolutions = [];
    for (const slot of app.slots) {
        const res = resolveSlot(slot, app.gender, idkLookup, objLookup);
        resolutions.push(res);
        for (const id of res.modelIds) allModelIds.push(id);
    }
    if (allModelIds.length === 0) return null;
    const cache = new Map();
    for (const id of allModelIds) {
        if (!cache.has(id)) cache.set(id, await rawModelLoader(id));
    }
    const perSlotModels = [];
    for (let s = 0; s < app.slots.length; s++) {
        const res = resolutions[s];
        for (const modelId of res.modelIds) {
            const cached = cache.get(modelId);
            if (!cached) continue;
            perSlotModels.push(shallowCopyRawModel(cached));
        }
    }
    if (perSlotModels.length === 0) return null;
    return mergeRawModels(perSlotModels);
}

function applyAppearanceMask(player, maskBytes) {
    const decoded = parseAppearanceMask(maskBytes);
    if (!decoded) return false;
    player.appearance530 = decoded;
    player.appearanceDirty = true;
    return true;
}

// ── fixtures ─────────────────────────────────────────────────────

// 8 fixture RawModel ids, each 4 vertices / 2 triangles. Vertex
// positions encode the model id so the composite buffer uniquely
// reflects which models were merged.
function fixtureRaw(id) {
    return {
        id, vertexCount: 4, triangleCount: 2, texturedCount: 0,
        vertexX: [id, id + 1, id + 2, id + 3],
        vertexY: [id * 10, id * 10 + 1, id * 10 + 2, id * 10 + 3],
        vertexZ: [id * 100, id * 100 + 1, id * 100 + 2, id * 100 + 3],
        vertexBones: null,
        triangleVertexA: [0, 1], triangleVertexB: [1, 2], triangleVertexC: [2, 3],
        triangleInfo: null, trianglePriorities: null, triangleAlpha: null,
        triangleBones: null, triangleTextures: null, triangleTextureIndex: null,
        triangleColors: [id * 256, id * 256 + 1],
        priority: 0,
        textureTypes: null, textureFacesP: null, textureFacesM: null, textureFacesN: null,
        texturesScaleX: null, texturesScaleY: null, texturesScaleZ: null,
        textureRotationY: null, textureExtraA: null, textureExtraB: null,
        cubeExtraA: null, cubeExtraB: null,
    };
}

// 530 wire format: upper byte 0 = empty slot, so IdkType ids in the wire
// stream must have a non-zero upper byte. Use ids 256+ to avoid the
// sentinel collision.
const idkFixtures = {
    256:  { id: 256,  feature: 0, disable: false, bodyModels: [10],
            headModels: [-1, -1, -1, -1, -1], recol_s: null, recol_d: null, retex_s: null, retex_d: null },  // head
    512:  { id: 512,  feature: 1, disable: false, bodyModels: [20],
            headModels: [-1, -1, -1, -1, -1], recol_s: null, recol_d: null, retex_s: null, retex_d: null },  // jaw
    768:  { id: 768,  feature: 2, disable: false, bodyModels: [30],
            headModels: [-1, -1, -1, -1, -1], recol_s: null, recol_d: null, retex_s: null, retex_d: null },  // torso
    1024: { id: 1024, feature: 3, disable: false, bodyModels: [40],
            headModels: [-1, -1, -1, -1, -1], recol_s: null, recol_d: null, retex_s: null, retex_d: null },  // arms
    1280: { id: 1280, feature: 4, disable: false, bodyModels: [50],
            headModels: [-1, -1, -1, -1, -1], recol_s: null, recol_d: null, retex_s: null, retex_d: null },  // hands
    1536: { id: 1536, feature: 5, disable: false, bodyModels: [60],
            headModels: [-1, -1, -1, -1, -1], recol_s: null, recol_d: null, retex_s: null, retex_d: null },  // legs
    1792: { id: 1792, feature: 6, disable: false, bodyModels: [70],
            headModels: [-1, -1, -1, -1, -1], recol_s: null, recol_d: null, retex_s: null, retex_d: null },  // feet
};

const objFixtures = {
    1042: { id: 1042, manwear: 80, manwear2: -1, manwear3: -1, womanwear: 80, womanwear2: -1, womanwear3: -1 }, // bronze sword
    1044: { id: 1044, manwear: 81, manwear2: 82, manwear3: -1, womanwear: 81, womanwear2: 82, womanwear3: -1 }, // mithril sword (different model count)
};

function idkLookup(id) { return idkFixtures[id] ?? null; }
function objLookup(id) { return objFixtures[id] ?? null; }
async function rawModelLoader(id) { return fixtureRaw(id); }

// Build a mask byte stream representing a player wearing all 7 wardrobe
// pieces in slots 0..6, with `weaponObjId` equipped in slot 7.
function buildMask(weaponObjId) {
    const bytes = [];
    bytes.push(0);              // settings: gender=0 (male), no skill level
    bytes.push(0);              // skull
    bytes.push(0);              // prayer
    // 7 wardrobe slots (idk ids 256, 512, 768, 1024, 1280, 1536, 1792)
    for (let i = 0; i < 7; i++) {
        const idkId = (i + 1) * 256;
        bytes.push((idkId >> 8) & 0xFF);
        bytes.push(idkId & 0xFF);
    }
    // slot 7: equipped weapon (raw = objId + 32768)
    const enc = weaponObjId + 32768;
    bytes.push((enc >> 8) & 0xFF);
    bytes.push(enc & 0xFF);
    // slots 8..11: empty
    for (let i = 8; i < 12; i++) bytes.push(0);
    // 5 colors
    for (let i = 0; i < 5; i++) bytes.push(i);
    // basId (g2)
    bytes.push(0); bytes.push(42);
    // 8-byte username
    for (let i = 0; i < 8; i++) bytes.push(0);
    // combat level
    bytes.push(99);
    // skip 2 (skill level not shown)
    bytes.push(0); bytes.push(0);
    // soundRadius
    bytes.push(0);
    return new Uint8Array(bytes);
}

// ── exercise the pipeline ────────────────────────────────────────

const lines = [];
const origLog = console.log;
console.log = (...args) => { lines.push(args.join(" ")); origLog(...args); };

const player = {};

// Run 1: equip 1042 (bronze sword, 1 wear-model)
const mask1 = buildMask(1042);
applyAppearanceMask(player, mask1);
const composite1 = await composeAppearanceModel(player.appearance530, idkLookup, objLookup, rawModelLoader);
if (!composite1) throw new Error("composite1 was null");

// Verify composite1 vertex count = 7 wardrobe + 1 weapon = 8 model fixtures, each 4 verts → 32
const expectedV1 = 8 * 4;
if (composite1.vertexCount !== expectedV1) {
    throw new Error("composite1 vertexCount mismatch: expected " + expectedV1 + " got " + composite1.vertexCount);
}
console.log("[PlayerAppearance530] composite1 verts=" + composite1.vertexCount + " tris=" + composite1.triangleCount);

// Run 2: equip 1044 (mithril sword, 2 wear-models — adds an extra 4 verts/2 tris)
const mask2 = buildMask(1044);
applyAppearanceMask(player, mask2);
const composite2 = await composeAppearanceModel(player.appearance530, idkLookup, objLookup, rawModelLoader);
if (!composite2) throw new Error("composite2 was null");

const expectedV2 = 9 * 4;   // 7 + 2 weapon parts
if (composite2.vertexCount !== expectedV2) {
    throw new Error("composite2 vertexCount mismatch: expected " + expectedV2 + " got " + composite2.vertexCount);
}
console.log("[PlayerAppearance530] composite2 verts=" + composite2.vertexCount + " tris=" + composite2.triangleCount);

// Vertex-buffer diff. Different weapon → different model ids → different composite.
const deltaV = composite2.vertexCount - composite1.vertexCount;
if (deltaV === 0) {
    // Same vertex count but check positions differ.
    let bufDiff = 0;
    const len = Math.min(composite1.vertexX.length, composite2.vertexX.length);
    for (let i = 0; i < len; i++) {
        if (composite1.vertexX[i] !== composite2.vertexX[i]) bufDiff++;
    }
    if (bufDiff === 0) throw new Error("equip swap produced identical vertex buffers");
    console.log("[PlayerAppearance530] equip swap delta verts=0 positions=" + bufDiff);
} else {
    console.log("[PlayerAppearance530] equip swap delta verts=" + deltaV);
}

// Spot-check: the rebased triangle indices in composite2 should max out
// at vertexCount-1, never exceed totalV.
let maxIdx = 0;
for (let i = 0; i < composite2.triangleCount; i++) {
    maxIdx = Math.max(maxIdx, composite2.triangleVertexA[i], composite2.triangleVertexB[i], composite2.triangleVertexC[i]);
}
if (maxIdx >= composite2.vertexCount) {
    throw new Error("triangle index " + maxIdx + " out of bounds for vertexCount " + composite2.vertexCount);
}
console.log("[PlayerAppearance530] index rebase OK: maxIdx=" + maxIdx + " verts=" + composite2.vertexCount);

// Decode round-trip: parseAppearanceMask should yield gender=0, basId=42,
// 7 idk slots + 1 obj slot + 4 empty.
const decoded = parseAppearanceMask(mask2);
if (decoded.gender !== 0) throw new Error("decoded gender wrong");
if (decoded.basId !== 42) throw new Error("decoded basId wrong: " + decoded.basId);
if (decoded.combatLevel !== 99) throw new Error("decoded combatLevel wrong: " + decoded.combatLevel);
const idkSlots = decoded.slots.filter(s => s.kind === "idk").length;
const objSlots = decoded.slots.filter(s => s.kind === "obj").length;
const emptySlots = decoded.slots.filter(s => s.kind === "empty").length;
if (idkSlots !== 7 || objSlots !== 1 || emptySlots !== 4) {
    throw new Error("slot kinds wrong: idk=" + idkSlots + " obj=" + objSlots + " empty=" + emptySlots);
}
console.log("[PlayerAppearance530] decode OK: gender=" + decoded.gender + " basId=" + decoded.basId + " idk=" + idkSlots + " obj=" + objSlots + " empty=" + emptySlots);

console.log = origLog;

const tracePath = join(__dirname, ".player-appearance-trace.txt");
const traceBody =
    "# Captured by .player-appearance-test.mjs at " + new Date().toISOString() + "\n" +
    "# All assertions passed: parseAppearanceMask, resolveSlot, mergeRawModels, applyAppearanceMask, equip-swap delta\n" +
    "# Composite1 (bronze sword 1042): " + composite1.vertexCount + " verts / " + composite1.triangleCount + " tris\n" +
    "# Composite2 (mithril sword 1044): " + composite2.vertexCount + " verts / " + composite2.triangleCount + " tris\n" +
    "# Equip-swap delta: " + (composite2.vertexCount - composite1.vertexCount) + " verts\n" +
    "\n" +
    lines.join("\n") + "\n";
writeFileSync(tracePath, traceBody);

origLog("[player-appearance] trace captured at " + tracePath);
origLog("[player-appearance] " + lines.length + " log line(s) recorded");
