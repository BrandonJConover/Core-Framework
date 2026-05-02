// .terrain-render-wire-test.mjs — offline gates for P3b TerrainAdapter530.
//
// Hand-rolls a fixture Game with 105×105 sloped heightmap + 104×104
// floor-id grids, runs buildLandscape530 (inline mirror), then
// attachLandscape530 against a fake Model530Bridge. Asserts mesh has
// non-zero verts/tris and the Scene's per-plane landscape slot is set.
//
// Run:    node 2009scape-web/client-patch/.terrain-render-wire-test.mjs

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── inlined buildTerrainMesh (mirrors TerrainMesh530.ts, same shape
//    as .terrain-mesh-test.mjs). Minimal — emits 4 verts + 2 tris per
//    valid tile, colors from the FloType lookup. ────────────────────

function heightAt(src, x, z) {
    const cx = x < 0 ? 0 : x;
    const cz = z < 0 ? 0 : z;
    const stride = src.heightStride;
    const maxIdx = src.heights.length - 1;
    let idx = cz * stride + cx;
    if (idx > maxIdx) idx = maxIdx;
    return src.heights[idx];
}

function tileFloorIds(src, x, z) {
    const i = z * src.sizeX + x;
    return {
        overlay: src.floorOverlays[i] ?? -1,
        underlay: src.floorUnderlays[i] ?? -1,
        plane: src.tilePlane[i] ?? 0,
    };
}

function resolveFloor(overlay, underlay, floLookup) {
    if (overlay !== -1 && overlay !== 0) {
        const f = floLookup(overlay);
        if (f) return { color: f.baseColor, texture: f.texture };
    }
    if (underlay !== -1 && underlay !== 0) {
        const f = floLookup(underlay);
        if (f) return { color: f.baseColor, texture: f.texture };
    }
    return null;
}

function buildTerrainMesh(src, floLookup, opts = {}) {
    const tileSize = opts.tileSizeUnits ?? 128;
    const ox = opts.originX ?? 0;
    const oz = opts.originZ ?? 0;
    const verts = { x: [], y: [], z: [] };
    const tris = { a: [], b: [], c: [] };
    const triColors = [];
    const triTextures = [];
    let tileCount = 0;

    for (let z = 0; z < src.sizeZ; z++) {
        for (let x = 0; x < src.sizeX; x++) {
            const ids = tileFloorIds(src, x, z);
            if (ids.plane !== src.planeFilter) continue;
            const resolved = resolveFloor(ids.overlay, ids.underlay, floLookup);
            if (!resolved) continue;

            // 4 corners
            const h0 = heightAt(src, x, z);
            const h1 = heightAt(src, x + 1, z);
            const h2 = heightAt(src, x + 1, z + 1);
            const h3 = heightAt(src, x, z + 1);

            const v0 = verts.x.length;
            verts.x.push(ox + x * tileSize);
            verts.y.push(-h0);
            verts.z.push(oz + z * tileSize);
            verts.x.push(ox + (x + 1) * tileSize);
            verts.y.push(-h1);
            verts.z.push(oz + z * tileSize);
            verts.x.push(ox + (x + 1) * tileSize);
            verts.y.push(-h2);
            verts.z.push(oz + (z + 1) * tileSize);
            verts.x.push(ox + x * tileSize);
            verts.y.push(-h3);
            verts.z.push(oz + (z + 1) * tileSize);

            // 2 tris (SW,SE,NW + SE,NE,NW)
            tris.a.push(v0,     v0 + 1);
            tris.b.push(v0 + 1, v0 + 2);
            tris.c.push(v0 + 3, v0 + 3);
            triColors.push(resolved.color, resolved.color);
            triTextures.push(resolved.texture ?? -1, resolved.texture ?? -1);
            tileCount++;
        }
    }

    return {
        id: -1,
        vertexCount: verts.x.length,
        triangleCount: tris.a.length,
        texturedCount: 0,
        vertexX: verts.x,
        vertexY: verts.y,
        vertexZ: verts.z,
        vertexBones: null,
        triangleVertexA: tris.a,
        triangleVertexB: tris.b,
        triangleVertexC: tris.c,
        triangleColors: triColors,
        triangleTextures: triTextures,
        triangleAlpha: null, trianglePriorities: null, triangleInfo: null,
        triangleBones: null, triangleTextureIndex: null,
        textureTypes: null, textureFacesP: null, textureFacesM: null, textureFacesN: null,
        priority: 0,
        _tileCount: tileCount,
    };
}

// ── inlined TerrainAdapter530 ──

function tileSourceForPlane(game, plane, sizeX = 104, sizeZ = 104) {
    const heights = new Array((sizeX + 1) * (sizeZ + 1)).fill(0);
    const floorOverlays = new Array(sizeX * sizeZ).fill(-1);
    const floorUnderlays = new Array(sizeX * sizeZ).fill(-1);
    const tilePlane = new Array(sizeX * sizeZ).fill(plane);

    if (game.anIntArrayArrayArray891) {
        const planeRow = game.anIntArrayArrayArray891[plane];
        if (planeRow) {
            for (let z = 0; z <= sizeZ; z++) {
                for (let x = 0; x <= sizeX; x++) {
                    const v = planeRow[x]?.[z];
                    if (typeof v === "number") heights[z * (sizeX + 1) + x] = v;
                }
            }
        }
    }
    for (let z = 0; z < sizeZ; z++) {
        for (let x = 0; x < sizeX; x++) {
            const i = z * sizeX + x;
            if (game.floorOverlayIds) {
                const v = game.floorOverlayIds[plane]?.[x]?.[z];
                if (typeof v === "number") floorOverlays[i] = v;
            }
            if (game.floorUnderlayIds) {
                const v = game.floorUnderlayIds[plane]?.[x]?.[z];
                if (typeof v === "number") floorUnderlays[i] = v;
            }
        }
    }
    return { sizeX, sizeZ, heightStride: sizeX + 1, heights, floorOverlays, floorUnderlays, tilePlane, planeFilter: plane };
}

function floLookupFor(game) {
    return (id) => {
        if (id < 0) return null;
        return game.floTypeCache?.get(id) ?? null;
    };
}

function buildLandscape530(game, plane) {
    return buildTerrainMesh(tileSourceForPlane(game, plane), floLookupFor(game));
}

function attachLandscape530(scene, plane, mesh, bridge) {
    if (!mesh || mesh.vertexCount === 0) return null;
    if (plane < 0 || plane > 3) return null;
    const bridged = bridge.attachModel(mesh);
    if (!bridged) return null;
    if (!scene.landscape530) scene.landscape530 = [null, null, null, null];
    const prior = scene.landscape530[plane];
    if (prior && typeof prior.reset === "function") prior.reset();
    scene.landscape530[plane] = bridged;
    return bridged;
}

// ── fixtures ────────────────────────────────────────────────────────

const SIZE = 104;
function array3d(planes, dim1, dim2, fill) {
    const out = [];
    for (let p = 0; p < planes; p++) {
        const row = [];
        for (let i = 0; i < dim1; i++) {
            const inner = new Array(dim2).fill(fill);
            row.push(inner);
        }
        out.push(row);
    }
    return out;
}

// Heights: 4×105×105 with a sloped (x+z)*4 fill.
const heights = array3d(4, SIZE + 1, SIZE + 1, 0);
for (let p = 0; p < 4; p++) {
    for (let x = 0; x <= SIZE; x++) {
        for (let z = 0; z <= SIZE; z++) {
            heights[p][x][z] = (x + z) * 4;
        }
    }
}

// Floor ids: 4×104×104. Plane 0 fills the centre 6×6 region with overlay=10
// and underlay=20; everything else stays -1 so it doesn't emit. Plane 1 fills
// a single tile to verify planeFilter excludes it.
const overlays = array3d(4, SIZE, SIZE, -1);
const underlays = array3d(4, SIZE, SIZE, -1);
for (let x = 50; x < 56; x++) {
    for (let z = 50; z < 56; z++) {
        overlays[0][x][z] = 10;
        underlays[0][x][z] = 20;
    }
}
overlays[1][70][70] = 10;   // should be excluded when planeFilter=0

// FloType cache: two distinct entries with distinct base colors.
const floTypeCache = new Map();
floTypeCache.set(10, { id: 10, baseColor: 0xAABB00, texture: -1 });
floTypeCache.set(20, { id: 20, baseColor: 0x00CCDD, texture: -1 });

const game = {
    anIntArrayArrayArray891: heights,
    floorOverlayIds: overlays,
    floorUnderlayIds: underlays,
    floTypeCache,
};

// ── run gates ───────────────────────────────────────────────────────

const meshPlane0 = buildLandscape530(game, 0);
if (meshPlane0.vertexCount === 0) throw new Error("plane 0 mesh empty");
if (meshPlane0.triangleCount === 0) throw new Error("plane 0 mesh tri count 0");

const expectedTiles = 6 * 6;     // 6×6 region we filled on plane 0
const expectedVerts = expectedTiles * 4;
const expectedTris = expectedTiles * 2;
if (meshPlane0.vertexCount !== expectedVerts) {
    throw new Error(`plane 0 vertCount expected ${expectedVerts} got ${meshPlane0.vertexCount}`);
}
if (meshPlane0.triangleCount !== expectedTris) {
    throw new Error(`plane 0 triCount expected ${expectedTris} got ${meshPlane0.triangleCount}`);
}

// Plane 1 should yield 1 tile (= 4 verts, 2 tris) since we filled one cell
// at (70,70). Confirms planeFilter routes correctly.
const meshPlane1 = buildLandscape530(game, 1);
if (meshPlane1.vertexCount !== 4) {
    throw new Error(`plane 1 vertCount expected 4 got ${meshPlane1.vertexCount}`);
}

// Bridge stub.
let resetCalls = 0;
const fakeBridge = {
    attachModel(mesh) {
        return {
            vertCount: mesh.vertexCount,
            triCount: mesh.triangleCount,
            reset() { resetCalls++; },
        };
    },
};

const scene = {};

// First attach plane 0.
const a0 = attachLandscape530(scene, 0, meshPlane0, fakeBridge);
if (!a0) throw new Error("plane 0 attach returned null");
if (!scene.landscape530) throw new Error("scene.landscape530 not allocated");
if (scene.landscape530[0] !== a0) throw new Error("scene.landscape530[0] not pointing at attached");
if (scene.landscape530[1] !== null) throw new Error("scene.landscape530[1] should still be null");
if (resetCalls !== 0) throw new Error(`first attach should not reset (count=${resetCalls})`);

// Re-attach plane 0 — prior should reset.
const a0b = attachLandscape530(scene, 0, meshPlane0, fakeBridge);
if (a0b === a0) throw new Error("re-attach didn't produce new bridged model");
if (resetCalls !== 1) throw new Error(`re-attach should reset prior exactly once (count=${resetCalls})`);

// Empty mesh must not touch the slot.
const aEmpty = attachLandscape530(scene, 2, { vertexCount: 0 }, fakeBridge);
if (aEmpty !== null) throw new Error("empty-mesh attach should return null");
if (scene.landscape530[2] !== null) throw new Error("empty-mesh attach must not populate slot");

// Out-of-range plane.
const aOOR = attachLandscape530(scene, 7, meshPlane0, fakeBridge);
if (aOOR !== null) throw new Error("plane=7 attach should return null");

// ── trace ──

const trace = [
    `# Captured by .terrain-render-wire-test.mjs at ${new Date().toISOString()}`,
    `# Gates: tileSourceForPlane reshape, buildLandscape530 plane filter, attachLandscape530 idempotent`,
    `# Plane 0 fixture: 6×6 painted region (36 tiles) yielding ${expectedVerts} verts / ${expectedTris} tris`,
    `# Plane 1 fixture: single tile yielding 4 verts / 2 tris`,
    ``,
    `[TerrainAdapter530] attached plane=0 verts=${meshPlane0.vertexCount} tris=${meshPlane0.triangleCount}`,
    `[TerrainAdapter530] plane filter ok: plane=1 emitted ${meshPlane1.vertexCount} verts (1 tile)`,
    `[TerrainAdapter530] reset() count after re-attach=${resetCalls} (expected 1)`,
    `[TerrainAdapter530] empty-mesh + out-of-range plane attach returned null`,
].join("\n") + "\n";

const tracePath = join(__dirname, ".terrain-render-wire-trace.txt");
writeFileSync(tracePath, trace);
console.log(`[terrain-render-wire] trace captured at ${tracePath}`);
console.log(`[terrain-render-wire] all assertions passed`);
