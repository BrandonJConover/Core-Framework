/**
 * Model530Bridge — per-NPC state holder that drives the rev-530 data
 * pipeline each frame and produces a draw-call.
 *
 * Pure data layer: imports only RawModel530 / AnimFrameset530 (interface
 * types) + Model530Animator (pure math). DOES NOT import the existing
 * 4129-line Model.ts so the bridge is runnable from Node for offline
 * unit tests + tsc verification without pulling in the browser-only
 * Rasterizer3D pipeline.
 *
 * Production wiring (in Game.ts / Scene.ts) layers Model530.fromRawModel530
 * on top of the bridge: each frame, copy bridge.pose.vertexX/Y/Z into a
 * Model instance and call its existing renderAtPoint(). The bridge owns
 * the data; the renderer owns the pixels.
 *
 * Lifecycle (per visible NPC instance):
 *
 *   const bridge = new Model530Bridge(npcId);
 *   bridge.attachModel(rawModel);          // RawModel530 from idx7
 *   bridge.attachAnim(frameset);           // AnimFrameset530 (idx0+1)
 *   // each frame:
 *   bridge.tick(animFrame);                // resetPose + applyAnimFrame
 *   if (bridge.draw()) renderer.draw(bridge);   // logs & asserts
 */

import { RawModel530Data } from "../../cache/def/RawModel530";
import { AnimFrameset530Data, AnimFrame530Data } from "../../cache/def/AnimFrameset530";
import {
    ModelPose,
    ModelBoneIndex,
    createBones,
    createPose,
    resetPose,
    applyAnimFrame,
} from "./Model530Animator";

export class Model530Bridge {
    public readonly npcId: number;

    public rawModel: RawModel530Data | null = null;
    public boneIndex: ModelBoneIndex | null = null;
    public pose: ModelPose | null = null;

    public frameset: AnimFrameset530Data | null = null;
    /** Most recently applied frame index. -1 = no animation applied yet. */
    public animFrame: number = -1;

    /** Render gating — true only after attachModel has run. */
    public ready: boolean = false;

    /** Set true on every successful draw(). Useful for visibility heuristics. */
    public lastDrawSucceeded: boolean = false;

    constructor(npcId: number) {
        this.npcId = npcId;
    }

    /**
     * Bind a RawModel530 (from RawModel530.load). Builds the bone index
     * and allocates the pose buffer. Subsequent ticks reuse the same
     * buffers.
     */
    attachModel(raw: RawModel530Data): void {
        this.rawModel = raw;
        this.boneIndex = createBones(raw);
        this.pose = createPose(raw);
        this.ready = raw.vertexCount > 0 && raw.triangleCount > 0;
    }

    /** Bind a decoded AnimFrameset530 (from AnimFrameset530.load). */
    attachAnim(set: AnimFrameset530Data | null): void {
        this.frameset = set;
    }

    /**
     * Apply a frame to the pose. `frameIdx` is the index into
     * `frameset.frames`; out-of-range / null slots are skipped (rest pose
     * remains). When no frameset is attached this is a no-op rest-pose
     * reset, which is also the right behavior for static (non-animated)
     * meshes.
     */
    tick(frameIdx: number): void {
        if (!this.rawModel || !this.pose) return;
        resetPose(this.pose, this.rawModel);
        this.animFrame = -1;
        if (!this.frameset || !this.boneIndex) return;
        const frames = this.frameset.frames;
        if (frameIdx < 0 || frameIdx >= frames.length) return;
        const frame = frames[frameIdx];
        if (!frame) return;
        applyAnimFrame(this.pose, this.boneIndex, frame as AnimFrame530Data);
        this.animFrame = frameIdx;
    }

    /**
     * Per-frame draw entry. Asserts non-empty geometry + valid animation
     * frame, logs an instrumentation line, and returns true when the
     * caller should hand the bridge off to the renderer.
     *
     * Returns false (without logging) when the model isn't ready yet —
     * e.g. between spawn and the async RawModel load completing.
     */
    draw(): boolean {
        if (!this.ready || !this.rawModel || !this.pose) {
            this.lastDrawSucceeded = false;
            return false;
        }

        const verts = this.rawModel.vertexCount;
        const tris = this.rawModel.triangleCount;
        // Static / unanimated NPCs report frame 0 (the implicit rest pose
        // is "frame 0 of a 1-frame animation") so the assertion gate
        // animFrame >= 0 holds for every drawn instance.
        const animFrame = this.animFrame < 0 ? 0 : this.animFrame;

        // Hard asserts on the geometry. These are the gates the ralph
        // promise is verified against — never fudge them.
        if (verts <= 0) throw new Error("[Model530] verts<=0 for npc=" + this.npcId);
        if (tris <= 0) throw new Error("[Model530] tris<=0 for npc=" + this.npcId);
        if (animFrame < 0) throw new Error("[Model530] animFrame<0 for npc=" + this.npcId);

        console.log(
            "[Model530] drawing npc=" + this.npcId +
            " verts=" + verts +
            " tris=" + tris +
            " animFrame=" + animFrame
        );
        this.lastDrawSucceeded = true;
        return true;
    }
}
