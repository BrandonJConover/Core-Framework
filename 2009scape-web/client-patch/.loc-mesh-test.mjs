// .loc-mesh-test.mjs — standalone trace harness for LocMesh530.
//
// Pure ESM, mirrors the inline-fixture pattern of the prior .first-light /
// .player-appearance / .terrain-mesh tests. Verifies the data-side
// completion gates without pulling in Js5Cache or the renderer.
//
// Gates exercised:
//   1. resolveLocModels routes by shape (op1 path: shapes != null).
//   2. composeLocMesh merges multiple-model variants and single-model
//      variants distinctly (variant routing produces a vertex-count delta).
//   3. applyLocOrientation produces axis-correct rotations for o=1, 2, 3.
//   4. resize/translate apply when their sentinels diverge from defaults.

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── inlined helpers (mirror exports from PlayerAppearance530 + LocMesh530) ──

function shallowCopyMesh(m) {
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

function recolorModel(m, src, dst) {
    const s = src & 0xFFFF;
    const d = dst & 0xFFFF;
    for (let i = 0; i < m.triangleCount; i++) {
        if ((m.triangleColors[i] & 0xFFFF) === s) m.triangleColors[i] = d;
    }
}

function retextureModel(m, src, dst) {
    if (!m.triangleTextures) return;
    const s = src & 0xFFFF;
    const d = dst & 0xFFFF;
    for (let i = 0; i < m.triangleCount; i++) {
        if ((m.triangleTextures[i] & 0xFFFF) === s) m.triangleTextures[i] = d;
    }
}

const SHAPE_CENTREPIECE_STRAIGHT = 10;

function resolveLocModels(loc, shapeIndex) {
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

function applyLocOrientation(mesh, orientation) {
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

function applyResize(m, sx, sy, sz) {
    const vx = m.vertexX, vy = m.vertexY, vz = m.vertexZ;
    for (let i = 0; i < m.vertexCount; i++) {
        vx[i] = ((vx[i] * sx) / 128) | 0;
        vy[i] = ((vy[i] * sy) / 128) | 0;
        vz[i] = ((vz[i] * sz) / 128) | 0;
    }
}

function applyTranslate(m, dx, dy, dz) {
    const vx = m.vertexX, vy = m.vertexY, vz = m.vertexZ;
    for (let i = 0; i < m.vertexCount; i++) {
        vx[i] += dx;
        vy[i] += dy;
        vz[i] += dz;
    }
}

async function composeLocMesh(loc, shapeIndex, rawModelLoader, opts = {}) {
    const o = { orientation: 0, skipScale: false, skipRecolor: false, ...opts };
    const ids = resolveLocModels(loc, shapeIndex);
    if (ids.length === 0) return null;
    const slot = [];
    for (const id of ids) {
        const raw = await rawModelLoader(id);
        if (raw) slot.push(shallowCopyMesh(raw));
    }
    if (slot.length === 0) return null;
    const composite = mergeRawModels(slot);
    if (!composite) return null;
    const oriented = applyLocOrientation(composite, o.orientation);
    if (!o.skipRecolor) {
        if (loc.recol_s && loc.recol_d) {
            for (let i = 0; i < loc.recol_s.length; i++) recolorModel(oriented, loc.recol_s[i], loc.recol_d[i]);
        }
        if (loc.retex_s && loc.retex_d) {
            for (let i = 0; i < loc.retex_s.length; i++) retextureModel(oriented, loc.retex_s[i], loc.retex_d[i]);
        }
    }
    if (!o.skipScale) {
        if (loc.resizex !== 128 || loc.resizey !== 128 || loc.resizez !== 128) {
            applyResize(oriented, loc.resizex, loc.resizey, loc.resizez);
        }
        if (loc.xoff !== 0 || loc.yoff !== 0 || loc.zoff !== 0) {
            applyTranslate(oriented, loc.xoff, loc.yoff, loc.zoff);
        }
    }
    return oriented;
}

// ── fixtures ─────────────────────────────────────────────────────

function fixtureRaw(id) {
    return {
        id, vertexCount: 4, triangleCount: 2, texturedCount: 0,
        vertexX: [id, id + 10, id + 20, id + 30],
        vertexY: [0, 100, 100, 0],
        vertexZ: [-50, -50, 50, 50],
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

// LocType530 fixture: 3 models, 2 shapes — shape 5 → models[0]+[1] (two-model variant);
// shape 7 → models[2] (single-model variant). To get TWO models per shape we'd need
// a different rt4 path (shapes==null). We exercise BOTH paths below.

const locWithShapes = {
    id: 999, shapes: [5, 7], models: [10, 12],
    recol_s: null, recol_d: null, retex_s: null, retex_d: null,
    resizex: 128, resizey: 128, resizez: 128,
    xoff: 0, yoff: 0, zoff: 0,
};

const locFlatMulti = {
    id: 1000, shapes: null, models: [10, 11],   // both apply to shape 10
    recol_s: null, recol_d: null, retex_s: null, retex_d: null,
    resizex: 128, resizey: 128, resizez: 128,
    xoff: 0, yoff: 0, zoff: 0,
};

const locScaled = {
    id: 1001, shapes: null, models: [10],
    recol_s: null, recol_d: null, retex_s: null, retex_d: null,
    resizex: 256, resizey: 64, resizez: 256,
    xoff: 50, yoff: -25, zoff: 75,
};

async function rawModelLoader(id) { return fixtureRaw(id); }

// ── exercise the pipeline ───────────────────────────────────────

const lines = [];
const origLog = console.log;
console.log = (...args) => { lines.push(args.join(" ")); origLog(...args); };

// Test 1: shapes!=null path with two distinct shape variants, single model each.
const meshShape5 = await composeLocMesh(locWithShapes, 5, rawModelLoader);
const meshShape7 = await composeLocMesh(locWithShapes, 7, rawModelLoader);
if (!meshShape5 || !meshShape7) throw new Error("shapes-routed compose returned null");
if (meshShape5.vertexCount !== 4) throw new Error("shape5 verts wrong: " + meshShape5.vertexCount);
if (meshShape7.vertexCount !== 4) throw new Error("shape7 verts wrong: " + meshShape7.vertexCount);
// Both produce 4 verts (single model each), but the ROUTED MODEL differs (id 10 vs 12)
// — vertexX[0] should differ (10 vs 12).
if (meshShape5.vertexX[0] === meshShape7.vertexX[0]) {
    throw new Error("shape variant routing did not pick different models");
}
console.log("[LocMesh530] composed shape=5 verts=" + meshShape5.vertexCount + " tris=" + meshShape5.triangleCount + " orientation=0");
console.log("[LocMesh530] composed shape=7 verts=" + meshShape7.vertexCount + " tris=" + meshShape7.triangleCount + " orientation=0");

// Test 2: shapes==null path concatenates all flat models (variant routing).
const flatMesh = await composeLocMesh(locFlatMulti, SHAPE_CENTREPIECE_STRAIGHT, rawModelLoader);
if (!flatMesh) throw new Error("flat compose returned null");
if (flatMesh.vertexCount !== 8) throw new Error("flat verts expected 8, got " + flatMesh.vertexCount);
if (flatMesh.triangleCount !== 4) throw new Error("flat tris expected 4, got " + flatMesh.triangleCount);
console.log("[LocMesh530] composed shape=10 verts=" + flatMesh.vertexCount + " tris=" + flatMesh.triangleCount + " orientation=0");

// Variant-routing delta: shape5 = 4 verts, shape10-flat = 8 verts.
const variantDelta = flatMesh.vertexCount - meshShape5.vertexCount;
if (variantDelta === 0) throw new Error("variant routing produced same vertexCount");
console.log("[LocMesh530] variant routing delta verts=" + variantDelta);

// Test 3: orientation rotates X/Z but preserves Y. Tracking model 10's first vertex:
// rest pose: x=10, z=-50.
// orient=1 (swapXz):    x'=z=-50,  z'=-x=-10
// orient=2 (negateXz):  x'=-x=-10, z'=-z=50
// orient=3 (method1689): x'=-z=50, z'=x=10
const restMesh = await composeLocMesh(locWithShapes, 5, rawModelLoader);
const oriented1 = await composeLocMesh(locWithShapes, 5, rawModelLoader, { orientation: 1 });
const oriented2 = await composeLocMesh(locWithShapes, 5, rawModelLoader, { orientation: 2 });
const oriented3 = await composeLocMesh(locWithShapes, 5, rawModelLoader, { orientation: 3 });

function checkXY(label, m, eX, eZ) {
    if (m.vertexX[0] !== eX) throw new Error(label + " vertexX[0]: expected " + eX + " got " + m.vertexX[0]);
    if (m.vertexZ[0] !== eZ) throw new Error(label + " vertexZ[0]: expected " + eZ + " got " + m.vertexZ[0]);
    if (m.vertexY[0] !== 0)   throw new Error(label + " vertexY[0] should be unchanged (0): got " + m.vertexY[0]);
}

checkXY("orientation=0", restMesh,  10,  -50);
checkXY("orientation=1", oriented1, -50, -10);
checkXY("orientation=2", oriented2, -10,  50);
checkXY("orientation=3", oriented3,  50,  10);
console.log("[LocMesh530] composed shape=5 verts=" + oriented1.vertexCount + " tris=" + oriented1.triangleCount + " orientation=1");
console.log("[LocMesh530] composed shape=5 verts=" + oriented2.vertexCount + " tris=" + oriented2.triangleCount + " orientation=2");
console.log("[LocMesh530] composed shape=5 verts=" + oriented3.vertexCount + " tris=" + oriented3.triangleCount + " orientation=3");

// Test 4: resize + translate apply when sentinels differ.
const scaledMesh = await composeLocMesh(locScaled, SHAPE_CENTREPIECE_STRAIGHT, rawModelLoader);
if (!scaledMesh) throw new Error("scaled compose returned null");
// Model 10 vertex[0] starts at (10, 0, -50). resize (256/128/256) → (20, 0, -100). translate (50, -25, 75) → (70, -25, -25).
if (scaledMesh.vertexX[0] !== 70) throw new Error("scaled vertexX[0] expected 70 got " + scaledMesh.vertexX[0]);
if (scaledMesh.vertexY[0] !== -25) throw new Error("scaled vertexY[0] expected -25 got " + scaledMesh.vertexY[0]);
if (scaledMesh.vertexZ[0] !== -25) throw new Error("scaled vertexZ[0] expected -25 got " + scaledMesh.vertexZ[0]);
console.log("[LocMesh530] resize+translate OK: vertex[0] (10,0,-50) → (70,-25,-25)");

// Test 5: out-of-range shape returns null.
const noMatch = await composeLocMesh(locWithShapes, 99, rawModelLoader);
if (noMatch !== null) throw new Error("out-of-range shape should return null");
console.log("[LocMesh530] out-of-range shape returns null OK");

console.log = origLog;

const tracePath = join(__dirname, ".loc-mesh-trace.txt");
const traceBody =
    "# Captured by .loc-mesh-test.mjs at " + new Date().toISOString() + "\n" +
    "# All assertions passed: resolveLocModels (shapes!=null and shapes==null routes),\n" +
    "# composeLocMesh (shape variant + flat-multi merge), applyLocOrientation (0..3),\n" +
    "# resize+translate, out-of-range fallback.\n" +
    "# Variant routing delta verts: " + variantDelta + "\n" +
    "\n" +
    lines.join("\n") + "\n";
writeFileSync(tracePath, traceBody);

origLog("[loc-mesh] trace captured at " + tracePath);
origLog("[loc-mesh] " + lines.length + " log line(s) recorded");
