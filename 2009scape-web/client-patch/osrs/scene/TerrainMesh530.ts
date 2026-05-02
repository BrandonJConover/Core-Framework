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
    // FloType ids in rt4 are 1-based per FloType.java (client subtracts 1 for cache lookup).
    // Here we treat -1 / 0 as "no floor" — caller should pre-shift if their data uses 1-based ids.
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
