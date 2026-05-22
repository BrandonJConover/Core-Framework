/**
 * TerrainMesh530 — zone-wide terrain mesh builder. Given a heightmap +
 * per-tile FloType ids, produces a single RawModel530-shaped mesh with
 * 4 vertices and 2 triangles per emitted tile, ready for the renderer.
 *
 * Pure data math: no Js5Cache, no Scene/Region/Game dependency. Caller
 * supplies a TerrainTileSource (already-loaded arrays) and a FloType
 * resolver. Verified offline via .terrain-mesh-test.mjs.
 *
 * Source of truth (read-only):
 *   reference/rt4-client/client/src/main/java/rt4/SceneGraph.java
 *     - setTile           per-tile mesh dispatcher  (line 1259)
 *     - method2610        PlainTile rasterizer      (line 3855)
 *       reads tileHeights[plane][x][z], [x+1][z], [x+1][z+1], [x][z+1]
 *       emits 2 CCW triangles sharing the (x+1,z)-(x,z+1) diagonal
 *   reference/rt4-client/client/src/main/java/rt4/PlainTile.java
 *   reference/rt4-client/client/src/main/java/rt4/FloType.java (already ported)
 *
 * Triangle winding (rt4 CCW from above looking down):
 *
 *     (x,z+1) D ─────── C (x+1,z+1)
 *             │ \   tri1
 *             │   \
 *      tri2   │     \
 *             │       \
 *     (x,z)   A ─────── B (x+1,z)
 *
 *   tri1 = C → D → B   (NE, NW(z+1), SE)
 *   tri2 = A → B → D   (SW, SE(x+1,z), NW(z+1))
 *   shared edge: B–D (the SW/NE diagonal, in (x,z) terms x+1,z to x,z+1)
 *
 * Tile size: 128 units. World coords:
 *   vertex.x = (originX + x) * 128
 *   vertex.y = -height            (rt4 stores heights as positive up; world y is down)
 *   vertex.z = (originZ + z) * 128
 *
 * Overlay vs underlay: when overlay floor id is non-empty (-1 sentinel)
 * its FloType color overrides the underlay (rt4 default occludeUnderlay
 * = true). When overlay is empty, the underlay color is used. When both
 * are empty the tile is skipped entirely.
 */

import { RawModel530Data } from "../cache/def/RawModel530";
import { FloType530Data } from "../cache/def/FloType530";

/** Caller-supplied terrain data for one zone, one plane. */
export interface TerrainTileSource {
    /** Zone width / depth in tiles. */
    sizeX: number;
    sizeZ: number;
    /**
     * Corner heights, length (sizeX+1) * (sizeZ+1) when fully populated.
     * For zones sized at sizeX*sizeZ (rt4 stores 105×105 for 104×104 tiles),
     * the heightAt() helper clamps to the last in-bounds value when (x+1)
     * or (z+1) exceeds sizeX/sizeZ — this matches rt4's edge-clamp behavior.
     * Indexing: heights[z * stride + x], stride = heightStride.
     */
    heights: number[];
    /** Stride for heights row (typically sizeX or sizeX+1). */
    heightStride: number;
    /**
     * Overlay FloType id per tile. -1 (or 0) means no overlay. Indexing:
     * floorOverlays[z * sizeX + x].
     */
    floorOverlays: number[];
    /** Underlay FloType id per tile. -1 / 0 = none. */
    floorUnderlays: number[];
    /** Tile plane (0..3). Tiles whose plane != planeFilter are skipped. */
    tilePlane: number[];
    /** Only emit tiles where tilePlane[i] === planeFilter. */
    planeFilter: number;
}

export interface TerrainMeshBuildOptions {
    /** rt4 standard 128 units per tile. */
    tileSizeUnits?: number;
    /** Origin offset in tile coordinates (added before * tileSizeUnits). */
    originX?: number;
    originZ?: number;
    /** When true, attach a triangleTextures array (texture id per triangle, -1 when none). */
    emitTextures?: boolean;
}

/**
 * Sample a corner height with rt4's edge-clamp semantics: indices that
 * exceed sizeX/sizeZ are folded back to the boundary (mirrors how
 * rt4 fills heights[105][105] at zone edges from neighbor zones).
 */
function heightAt(src: TerrainTileSource, x: number, z: number): number {
    let cx = x, cz = z;
    if (cx < 0) cx = 0;
    if (cz < 0) cz = 0;
    const maxIdx = src.heights.length - 1;
    let idx = cz * src.heightStride + cx;
    if (idx > maxIdx) idx = maxIdx;
    return src.heights[idx];
}

function tileFloorIds(src: TerrainTileSource, x: number, z: number): { overlay: number; underlay: number; plane: number } {
    const i = z * src.sizeX + x;
    return {
        overlay: src.floorOverlays[i] ?? -1,
        underlay: src.floorUnderlays[i] ?? -1,
        plane: src.tilePlane[i] ?? 0,
    };
}

/**
 * Resolve the per-tile color from overlay (priority) or underlay. Returns
 * { color, texture } where color is the FloType530.baseColor (rgb pass-through
 * with -1 sentinel for "no color") and texture is the FloType530.texture id
 * (-1 when none). Returns null when both layers are empty.
 */
function resolveFloor(
    overlay: number,
    underlay: number,
    floLookup: (id: number) => FloType530Data | null,
): { color: number; texture: number } | null {
    if (underlay !== -1 && underlay !== 0) {
        const f = floLookup(underlay);
        if (f) return { color: f.baseColor, texture: f.texture };
    }
    if (overlay !== -1 && overlay !== 0) {
        const f = floLookup(overlay);
        if (f) return { color: f.baseColor, texture: f.texture };
    }
    return null;
}

function trimHslLightness(hsl: number, lightness: number): number {
    if (hsl === -1) return 12345678;
    lightness = ((lightness * (hsl & 127)) / 128) | 0;
    if (lightness < 2) lightness = 2;
    else if (lightness > 126) lightness = 126;
    return (hsl & 65408) + lightness;
}

function cornerLight(src: TerrainTileSource, x: number, z: number): number {
    const lx = -50;
    const ly = -60;
    const lz = -50;
    const dx = heightAt(src, x + 1, z) - heightAt(src, x - 1, z);
    const dz = heightAt(src, x, z + 1) - heightAt(src, x, z - 1);
    const len = Math.sqrt(dx * dx + dz * dz + 65536);
    const nx = ((dx << 8) / len) | 0;
    const ny = ((-65536) / len) | 0;
    const nz = ((dz << 8) / len) | 0;
    const denom = ((Math.sqrt(lx * lx + ly * ly + lz * lz) * 1024) / 256) | 0;
    let light = 96 + (((lx * nx + ly * ny + lz * nz) / denom) | 0);
    if (light < 48) light = 48;
    else if (light > 126) light = 126;
    return light;
}

/**
 * Build a single RawModel530-shaped mesh covering all tiles in `src`
 * matching `src.planeFilter`. Empty tiles (both overlay and underlay
 * unset) are skipped. Edge tiles clamp corner heights to the zone boundary.
 */
export function buildTerrainMesh(
    src: TerrainTileSource,
    floLookup: (id: number) => FloType530Data | null,
    opts: TerrainMeshBuildOptions = {},
): RawModel530Data {
    const tileSize = opts.tileSizeUnits ?? 128;
    const ox = opts.originX ?? 0;
    const oz = opts.originZ ?? 0;
    const emitTextures = opts.emitTextures ?? false;

    const vertexX: number[] = [];
    const vertexY: number[] = [];
    const vertexZ: number[] = [];
    const triA: number[] = [];
    const triB: number[] = [];
    const triC: number[] = [];
    const triColors: number[] = [];
    const triColorA: number[] = [];
    const triColorB: number[] = [];
    const triColorC: number[] = [];
    const triTextures: number[] = emitTextures ? [] : [];

    let tilesEmitted = 0;
    for (let z = 0; z < src.sizeZ; z++) {
        for (let x = 0; x < src.sizeX; x++) {
            const ids = tileFloorIds(src, x, z);
            if (ids.plane !== src.planeFilter) continue;
            const floor = resolveFloor(ids.overlay, ids.underlay, floLookup);
            if (!floor) continue;

            // 4 corner heights, rt4-clamp at zone edges.
            const hA = heightAt(src, x,     z);     // (x,   z)   — corner A (SW in (x,z))
            const hB = heightAt(src, x + 1, z);     // (x+1, z)   — corner B
            const hC = heightAt(src, x + 1, z + 1); // (x+1, z+1) — corner C
            const hD = heightAt(src, x,     z + 1); // (x,   z+1) — corner D
            const cA = trimHslLightness(floor.color, cornerLight(src, x, z));
            const cB = trimHslLightness(floor.color, cornerLight(src, x + 1, z));
            const cC = trimHslLightness(floor.color, cornerLight(src, x + 1, z + 1));
            const cD = trimHslLightness(floor.color, cornerLight(src, x, z + 1));

            // World-space vertex base index (every tile owns its own 4 verts;
            // not shared with neighbors — keeps per-tile color tinting clean).
            const v = vertexX.length;
            const wxA = (ox + x)     * tileSize;
            const wxB = (ox + x + 1) * tileSize;
            const wzA = (oz + z)     * tileSize;
            const wzD = (oz + z + 1) * tileSize;

            vertexX.push(wxA, wxB, wxB, wxA); // A, B, C, D
            vertexY.push(-hA, -hB, -hC, -hD); // y axis points up = -height
            vertexZ.push(wzA, wzA, wzD, wzD);

            // Triangle indices (rt4 CCW winding):
            //   tri1 = (C, D, B)  — indices v+2, v+3, v+1
            //   tri2 = (A, B, D)  — indices v+0, v+1, v+3
            triA.push(v + 2, v + 0);
            triB.push(v + 3, v + 1);
            triC.push(v + 1, v + 3);
            triColors.push(floor.color, floor.color);
            triColorA.push(cC, cA);
            triColorB.push(cD, cB);
            triColorC.push(cB, cD);
            if (emitTextures) {
                triTextures.push(floor.texture, floor.texture);
            }
            tilesEmitted++;
        }
    }

    return {
        id: -1,
        vertexCount: vertexX.length,
        triangleCount: triA.length,
        texturedCount: 0,
        vertexX, vertexY, vertexZ,
        vertexBones: null,
        triangleVertexA: triA,
        triangleVertexB: triB,
        triangleVertexC: triC,
        triangleInfo: null,
        trianglePriorities: null,
        triangleAlpha: null,
        triangleBones: null,
        triangleTextures: emitTextures ? triTextures : null,
        triangleTextureIndex: null,
        triangleColors: triColors,
        triangleColorA: triColorA,
        triangleColorB: triColorB,
        triangleColorC: triColorC,
        priority: 0,
        textureTypes: null,
        textureFacesP: null,
        textureFacesM: null,
        textureFacesN: null,
        texturesScaleX: null,
        texturesScaleY: null,
        texturesScaleZ: null,
        textureRotationY: null,
        textureExtraA: null,
        textureExtraB: null,
        cubeExtraA: null,
        cubeExtraB: null,
    };
}

/** Convenience: count tiles in `src` that would be emitted (filter-matched + non-empty). */
export function countEmittableTiles(
    src: TerrainTileSource,
    floLookup: (id: number) => FloType530Data | null,
): number {
    let n = 0;
    for (let z = 0; z < src.sizeZ; z++) {
        for (let x = 0; x < src.sizeX; x++) {
            const ids = tileFloorIds(src, x, z);
            if (ids.plane !== src.planeFilter) continue;
            if (resolveFloor(ids.overlay, ids.underlay, floLookup) !== null) n++;
        }
    }
    return n;
}

export interface TerrainMeshChunk530 {
    rawModel: RawModel530Data;
    minTileX: number;
    maxTileX: number;
    minTileZ: number;
    maxTileZ: number;
}

export function chunkTerrainMesh530(mesh: RawModel530Data, chunkTiles: number = 16, tileSizeUnits: number = 128): TerrainMeshChunk530[] {
    const buckets = new Map<string, {
        minTileX: number; maxTileX: number; minTileZ: number; maxTileZ: number;
        vertexX: number[]; vertexY: number[]; vertexZ: number[];
        triA: number[]; triB: number[]; triC: number[]; triColors: number[]; triColorA: number[]; triColorB: number[]; triColorC: number[];
    }>();
    const getBucket = (tileX: number, tileZ: number) => {
        const chunkX = Math.floor(tileX / chunkTiles);
        const chunkZ = Math.floor(tileZ / chunkTiles);
        const key = chunkX + ":" + chunkZ;
        let bucket = buckets.get(key);
        if (!bucket) {
            bucket = {
                minTileX: chunkX * chunkTiles,
                maxTileX: chunkX * chunkTiles + chunkTiles,
                minTileZ: chunkZ * chunkTiles,
                maxTileZ: chunkZ * chunkTiles + chunkTiles,
                vertexX: [], vertexY: [], vertexZ: [],
                triA: [], triB: [], triC: [], triColors: [], triColorA: [], triColorB: [], triColorC: [],
            };
            buckets.set(key, bucket);
        }
        return bucket;
    };

    for (let i = 0; i < mesh.triangleCount; i += 2) {
        const a = mesh.triangleVertexA[i];
        const b = mesh.triangleVertexB[i];
        const c = mesh.triangleVertexC[i];
        const tileX = Math.floor(Math.min(mesh.vertexX[a], mesh.vertexX[b], mesh.vertexX[c]) / tileSizeUnits);
        const tileZ = Math.floor(Math.min(mesh.vertexZ[a], mesh.vertexZ[b], mesh.vertexZ[c]) / tileSizeUnits);
        const bucket = getBucket(tileX, tileZ);
        const remap = new Map<number, number>();
        const copyVertex = (src: number): number => {
            const hit = remap.get(src);
            if (hit !== undefined) return hit;
            const dst = bucket.vertexX.length;
            bucket.vertexX.push(mesh.vertexX[src]);
            bucket.vertexY.push(mesh.vertexY[src]);
            bucket.vertexZ.push(mesh.vertexZ[src]);
            remap.set(src, dst);
            return dst;
        };
        const end = Math.min(i + 2, mesh.triangleCount);
        for (let tri = i; tri < end; tri++) {
            bucket.triA.push(copyVertex(mesh.triangleVertexA[tri]));
            bucket.triB.push(copyVertex(mesh.triangleVertexB[tri]));
            bucket.triC.push(copyVertex(mesh.triangleVertexC[tri]));
            bucket.triColors.push(mesh.triangleColors[tri]);
            bucket.triColorA.push(mesh.triangleColorA?.[tri] ?? mesh.triangleColors[tri]);
            bucket.triColorB.push(mesh.triangleColorB?.[tri] ?? mesh.triangleColors[tri]);
            bucket.triColorC.push(mesh.triangleColorC?.[tri] ?? mesh.triangleColors[tri]);
        }
    }

    return Array.from(buckets.values()).map((bucket) => ({
        minTileX: bucket.minTileX,
        maxTileX: bucket.maxTileX,
        minTileZ: bucket.minTileZ,
        maxTileZ: bucket.maxTileZ,
        rawModel: {
            id: -1,
            vertexCount: bucket.vertexX.length,
            triangleCount: bucket.triA.length,
            texturedCount: 0,
            vertexX: bucket.vertexX,
            vertexY: bucket.vertexY,
            vertexZ: bucket.vertexZ,
            vertexBones: null,
            triangleVertexA: bucket.triA,
            triangleVertexB: bucket.triB,
            triangleVertexC: bucket.triC,
            triangleInfo: null,
            trianglePriorities: null,
            triangleAlpha: null,
            triangleBones: null,
            triangleTextures: null,
            triangleTextureIndex: null,
            triangleColors: bucket.triColors,
            triangleColorA: bucket.triColorA,
            triangleColorB: bucket.triColorB,
            triangleColorC: bucket.triColorC,
            priority: 0,
            textureTypes: null,
            textureFacesP: null,
            textureFacesM: null,
            textureFacesN: null,
            texturesScaleX: null,
            texturesScaleY: null,
            texturesScaleZ: null,
            textureRotationY: null,
            textureExtraA: null,
            textureExtraB: null,
            cubeExtraA: null,
            cubeExtraB: null,
        },
    }));
}
