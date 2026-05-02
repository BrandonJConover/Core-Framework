// ActorAnimator530 — per-actor animation state machine. Picks the right
// AnimFrameset based on the actor's current movement state, advances a
// frame index every `framesPerTick` render ticks, and exposes the
// current frame so the renderer's per-tick driver can hand it to
// Skinning530.applyFrame.
//
// rt4 reference: each actor type carries a BasType (animation set
// metadata: which seq id is "idle", "walk", "run", etc.). The animator
// resolves seq id → AnimFrameset, then walks the frameset.frames[]
// array linearly with wrap-around.

import type { BasType530Data } from "../cache/def/BasType530";
import type { AnimFrame530Data, AnimFrameset530Data } from "../cache/def/AnimFrameset530";

/** Movement state hint. The engine sets this on the actor each tick. */
export type ActorAnimState = "idle" | "walk" | "run";

export interface FramesetLookup {
    (seqId: number): AnimFrameset530Data | null;
}

export interface AdvanceResult {
    /** The frame to apply this tick, or null when no animation is active. */
    frame: AnimFrame530Data | null;
    /** Currently-selected seq id (-1 when none). Useful for diagnostics. */
    seqId: number;
    /** Currently-selected frame index. */
    frameIdx: number;
}

export class ActorAnimator530 {
    public seqId: number = -1;
    public frameIdx: number = 0;
    public ticksSinceFrame: number = 0;

    /** Number of render ticks between frame advances. Default 3 ≈ 150 ms
     *  at the standard 50 ms tick. The offline test harness constructs
     *  with `framesPerTick = 1` so frames advance every call. */
    constructor(public framesPerTick: number = 3) {}

    /** Map an actor state to the matching seq id from BasType. Falls back
     *  to idle when the requested state isn't authored on this BAS. */
    pickSeq(bas: BasType530Data, state: ActorAnimState): number {
        switch (state) {
            case "walk":
                if (bas.walkAnimation >= 0) return bas.walkAnimation;
                return bas.idleAnimationId;
            case "run":
                if (bas.runAnimationId >= 0) return bas.runAnimationId;
                if (bas.walkAnimation >= 0) return bas.walkAnimation;
                return bas.idleAnimationId;
            case "idle":
            default:
                return bas.idleAnimationId;
        }
    }

    /** Advance one render tick. Returns the frame to apply. When the
     *  picked seq id changes mid-walk the frame counter resets so the
     *  new animation always starts at frame 0. */
    advance(
        bas: BasType530Data | null,
        framesetLookup: FramesetLookup,
        state: ActorAnimState,
    ): AdvanceResult {
        if (!bas) return { frame: null, seqId: -1, frameIdx: 0 };
        const wantSeq = this.pickSeq(bas, state);
        if (wantSeq !== this.seqId) {
            this.seqId = wantSeq;
            this.frameIdx = 0;
            this.ticksSinceFrame = 0;
        }
        const fs = framesetLookup(this.seqId);
        if (!fs || !fs.frames || fs.frames.length === 0) {
            return { frame: null, seqId: this.seqId, frameIdx: this.frameIdx };
        }
        // Walk the populated frames in order. AnimFrameset's frames array
        // is sparse (rt4 indexes by file-id, leaving gaps null) — we
        // collapse to the first non-null entry per logical frame.
        const frame = pickFrameAt(fs, this.frameIdx);
        // Step the counter for the next tick.
        this.ticksSinceFrame++;
        if (this.ticksSinceFrame >= Math.max(1, this.framesPerTick)) {
            this.frameIdx = nextFrameIndex(fs, this.frameIdx);
            this.ticksSinceFrame = 0;
        }
        return { frame, seqId: this.seqId, frameIdx: this.frameIdx };
    }
}

/** Return the frame at a logical index, skipping null slots in the
 *  sparse frameset. */
function pickFrameAt(fs: AnimFrameset530Data, idx: number): AnimFrame530Data | null {
    const frames = fs.frames;
    if (!frames || frames.length === 0) return null;
    // Bounded scan — at most one full pass.
    for (let attempt = 0; attempt < frames.length; attempt++) {
        const candidate = frames[(idx + attempt) % frames.length];
        if (candidate) return candidate;
    }
    return null;
}

/** Wrap-around to the next non-null frame slot. */
function nextFrameIndex(fs: AnimFrameset530Data, current: number): number {
    const frames = fs.frames;
    if (!frames || frames.length === 0) return 0;
    for (let attempt = 1; attempt <= frames.length; attempt++) {
        const i = (current + attempt) % frames.length;
        if (frames[i]) return i;
    }
    return 0;
}
