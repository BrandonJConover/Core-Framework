// TerrainAdapter530 — pure glue between Game.ts's 3D height/floor
// arrays and the TerrainTileSource shape buildTerrainMesh expects.
// Plus a thin attacher that hands a built mesh through the live
// AppearanceBridge (Model530Bridge) and parks it on the Scene's
// per-plane landscape slot.
//
// Scope (P3b): glue only — `tileSourceForPlane`, `buildLandscape530`,
// `attachLandscape530`. The Scene/Game call sites that drive these
// (per-REBUILD_NORMAL trigger, per-render-tick draw) stay in their
// existing files; this adapter is pure-data + pure-attach.

import type { TerrainTileSource, TerrainMeshBuildOptions } from "./TerrainMesh530";
import { buildTerrainMesh } from "./TerrainMesh530";
import type { FloType530Data } from "../cache/def/FloType530";
import type { RawModel530Data } from "../cache/def/RawModel530";

/** Subset of `Game` that the adapter reads — typed structurally so the
 *  trace harness can pass a fixture without touching Game.ts. */
export interface TerrainHostGame {
    /** [plane][x][z], 105×105 per plane (corner heightmap). */
    anIntArrayArrayArray891?: number[][][] | null;
    /** [plane][x][z], 104×104. Tile-flag bits — encoded overlay/underlay
     *  ids live in the high/low nibbles depending on revision. */
    currentSceneTileFlags?: number[][][] | null;
    /** Optional dedicated overlay/underlay arrays the REBUILD_NORMAL
     *  decoder may stash; preferred over the packed flags when present. */
    floorOverlayIds?: number[][][] | null;
    floorUnderlayIds?: number[][][] | null;
    /** FloType530 record cache (id → data). */
    floTypeCache?: Map<number, FloType530Data> | null;
}

const DEFAULT_SIZE_X = 104;
const DEFAULT_SIZE_Z = 104;

/** Pull the heights + floor ids for `plane` out of the host game and
 *  reshape them into the flat-array TerrainTileSource. */
export function tileSourceForPlane(
    game: TerrainHostGame,
    plane: number,
    sizeX: number = DEFAULT_SIZE_X,
    sizeZ: number = DEFAULT_SIZE_Z,
): TerrainTileSource {
    const heights = new Array<number>((sizeX + 1) * (sizeZ + 1)).fill(0);
    const floorOverlays = new Array<number>(sizeX * sizeZ).fill(-1);
    const floorUnderlays = new Array<number>(sizeX * sizeZ).fill(-1);
    const tilePlane = new Array<number>(sizeX * sizeZ).fill(plane);

    const heightsSrc = game.anIntArrayArrayArray891;
    const overlaysSrc = game.floorOverlayIds ?? null;
    const underlaysSrc = game.floorUnderlayIds ?? null;

    if (heightsSrc) {
        // Heights array is [plane][x][z] with stride = sizeX+1 corner verts.
        const planeRow = heightsSrc[plane];
        if (planeRow) {
            for (let z = 0; z <= sizeZ; z++) {
                for (let x = 0; x <= sizeX; x++) {
                    const v = planeRow[x]?.[z];
                    if (typeof v === "number") {
                        heights[z * (sizeX + 1) + x] = v;
                    }
                }
            }
        }
    }

    for (let z = 0; z < sizeZ; z++) {
        for (let x = 0; x < sizeX; x++) {
            const i = z * sizeX + x;
            if (overlaysSrc) {
                const v = overlaysSrc[plane]?.[x]?.[z];
                if (typeof v === "number") floorOverlays[i] = v;
            }
            if (underlaysSrc) {
                const v = underlaysSrc[plane]?.[x]?.[z];
                if (typeof v === "number") floorUnderlays[i] = v;
            }
        }
    }

    return {
        sizeX,
        sizeZ,
        heightStride: sizeX + 1,
        heights,
        floorOverlays,
        floorUnderlays,
        tilePlane,
        planeFilter: plane,
    };
}

/** FloType lookup closure backed by the host game's cache. */
export function floLookupFor(game: TerrainHostGame): (id: number) => FloType530Data | null {
    return (id: number) => {
        if (id < 0) return null;
        return game.floTypeCache?.get(id) ?? null;
    };
}

/** One-shot build for a given plane. Returns the raw mesh; caller hands
 *  it to `attachLandscape530` to wire into the Scene. */
export function buildLandscape530(
    game: TerrainHostGame,
    plane: number,
    opts?: TerrainMeshBuildOptions,
): RawModel530Data {
    return buildTerrainMesh(tileSourceForPlane(game, plane), floLookupFor(game), opts);
}

// ── attach side ─────────────────────────────────────────────────────

export interface BridgedAppearanceModel {
    reset?: () => void;
    [key: string]: any;
}

export interface AppearanceBridge {
    attachModel(rawMesh: RawModel530Data): BridgedAppearanceModel | null;
}

/** Per-plane landscape slot the Scene reads from. Sidecar property —
 *  does not modify the legacy 377 landscape model paths. */
export interface SceneLandscapeHost {
    landscape530?: (BridgedAppearanceModel | null)[];
}

/**
 * Attach a freshly built landscape mesh to `scene.landscape530[plane]`.
 * Resets any previous bridged model first; no-op when `mesh` is null
 * or empty. Returns the new bridged model (or null when nothing was
 * attached).
 */
export function attachLandscape530(
    scene: SceneLandscapeHost,
    plane: number,
    mesh: RawModel530Data | null,
    bridge: AppearanceBridge,
): BridgedAppearanceModel | null {
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
