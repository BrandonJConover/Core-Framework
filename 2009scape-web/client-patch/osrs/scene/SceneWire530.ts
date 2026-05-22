/**
 * SceneWire530 — single orchestrator that ties together the five offline-
 * verified rev-530 scene modules:
 *
 *   TerrainAdapter530          → landscape mesh per plane
 *   NpcAttacher530             → NPC appearance attach
 *   PlayerAvatarAttacher530    → player avatar attach
 *   ActorAnimator530           → per-actor BAS-driven animation tick
 *   LocMesh530 (composeLocMesh)→ loc spawn mesh build
 *
 * Designed as a pure facade so Game.ts only needs:
 *   - one import
 *   - one construction call (typically in startUp / login completion)
 *   - one call per hook point (rebuildLandscape / rebuildNpcAppearance / …)
 *
 * The orchestrator owns the per-actor animator map, but otherwise stores
 * no state. Every method is structurally typed against the host objects
 * (npc / player / scene) so the trace harness can pass plain fixtures.
 *
 * Bridge contract — `AppearanceBridge.attachModel(raw)` is a FACTORY that
 * returns a fresh bridged model per call (matching the design of
 * NpcAttacher530 / PlayerAvatarAttacher530 / TerrainAdapter530). In
 * production the factory wraps `new Model530Bridge(id)` + `attachModel(raw)`.
 */

import {
    TerrainHostGame,
    AppearanceBridge,
    BridgedAppearanceModel,
    SceneLandscapeHost,
    buildLandscape530,
    attachLandscape530,
} from "./TerrainAdapter530";
import { NpcAvatarHost, attachNpcAppearance530 } from "./NpcAttacher530";
import { PlayerAvatarHost, attachPlayerAvatar530 } from "./PlayerAvatarAttacher530";
import {
    ActorAnimator530,
    ActorAnimState,
    FramesetLookup,
} from "./ActorAnimator530";
import type { RawModel530Data } from "../cache/def/RawModel530";
import type { BasType530Data } from "../cache/def/BasType530";
import type { LocType530Data } from "../cache/def/LocType530";
import type { AnimFrame530Data } from "../cache/def/AnimFrameset530";
import { composeLocMesh } from "../media/renderable/LocMesh530";

export interface SceneWire530Deps {
    /** Factory: each call returns a fresh bridged model (Model530Bridge wrapper). */
    bridge: AppearanceBridge;
    /** Resolve a seq id to a frameset for animator advance(). Returns null when missing. */
    framesetLookup: FramesetLookup;
    /** Resolve a model id to its decoded raw model. Used by composeLocMesh. */
    rawModelLoader: (id: number) => Promise<RawModel530Data | null>;
}

export interface RebuildLandscapeStats {
    /** Number of planes whose landscape mesh was attached this call. */
    attached: number;
    /** Total vertices across the attached planes. */
    verts: number;
    /** Total triangles across the attached planes. */
    tris: number;
}

export class SceneWire530 {
    private animators = new Map<number, ActorAnimator530>();
    private rebuiltPlanesSet = new Set<number>();

    constructor(public readonly deps: SceneWire530Deps) {}

    /**
     * Rebuild every plane's landscape mesh from the host's height/floor
     * arrays and attach the bridged result to `scene.landscape530[plane]`.
     * Called once after REBUILD_NORMAL completes terrain decode.
     */
    rebuildLandscape(
        host: TerrainHostGame,
        scene: SceneLandscapeHost,
        planes: number = 4,
    ): RebuildLandscapeStats {
        let attached = 0;
        let verts = 0;
        let tris = 0;
        for (let plane = 0; plane < planes; plane++) {
            const mesh = buildLandscape530(host, plane);
            if (attachLandscape530(scene, plane, mesh, this.deps.bridge)) {
                this.rebuiltPlanesSet.add(plane);
                attached++;
                verts += mesh.vertexCount;
                tris += mesh.triangleCount;
            }
        }
        return { attached, verts, tris };
    }

    /**
     * Attach a freshly composed NPC mesh. Called from the NPC_INFO
     * mask-block handler when appearance changes.
     */
    rebuildNpcAppearance(
        npc: NpcAvatarHost,
        mesh: RawModel530Data | null,
    ): BridgedAppearanceModel | null {
        return attachNpcAppearance530(npc, mesh, this.deps.bridge);
    }

    /**
     * Attach a freshly composed avatar mesh to a player. Called from the
     * PLAYER_INFO mask-block handler when appearance changes.
     */
    rebuildPlayerAvatar(
        player: PlayerAvatarHost,
        mesh: RawModel530Data | null,
    ): BridgedAppearanceModel | null {
        return attachPlayerAvatar530(player, mesh, this.deps.bridge);
    }

    /**
     * Compose a loc spawn mesh — resolves shape variant, loads constituent
     * raw models, applies recolor / retexture / orientation / scale /
     * translate. Returns null when no model resolves.
     */
    async rebuildLocMesh(
        loc: LocType530Data,
        shapeIndex: number,
        orientation: number,
    ): Promise<RawModel530Data | null> {
        return composeLocMesh(loc, shapeIndex, this.deps.rawModelLoader, {
            orientation,
            skipScale: false,
            skipRecolor: false,
        });
    }

    /**
     * Compose AND attach a loc mesh in one step. Returns the bridged
     * model (or null when the compose returned null).
     */
    async rebuildAndAttachLoc(
        host: { appearanceModel530?: BridgedAppearanceModel | null },
        loc: LocType530Data,
        shapeIndex: number,
        orientation: number,
    ): Promise<BridgedAppearanceModel | null> {
        const mesh = await this.rebuildLocMesh(loc, shapeIndex, orientation);
        if (!mesh) return null;
        const bridged = this.deps.bridge.attachModel(mesh);
        if (!bridged) return null;
        if (host.appearanceModel530 && typeof host.appearanceModel530.reset === "function") {
            host.appearanceModel530.reset();
        }
        host.appearanceModel530 = bridged;
        return bridged;
    }

    /**
     * Per-tick animation advance for one actor. Lazily creates an
     * `ActorAnimator530` keyed by `actorKey` (typically the npc/player id)
     * and returns the frame to apply this tick (or null when none).
     */
    tickActor(
        actorKey: number,
        bas: BasType530Data | null,
        state: ActorAnimState,
    ): AnimFrame530Data | null {
        let animator = this.animators.get(actorKey);
        if (!animator) {
            animator = new ActorAnimator530();
            this.animators.set(actorKey, animator);
        }
        return animator.advance(bas, this.deps.framesetLookup, state).frame;
    }

    /** Drop an actor's animator state when the actor leaves the scene. */
    dropActor(actorKey: number): void {
        this.animators.delete(actorKey);
    }

    /** Number of animators currently tracked (visible-actor count proxy). */
    animatorCount(): number {
        return this.animators.size;
    }

    /** Set of planes that have been rebuilt at least once this session. */
    rebuiltPlanes(): ReadonlySet<number> {
        return this.rebuiltPlanesSet;
    }
}
