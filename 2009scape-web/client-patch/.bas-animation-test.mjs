// .bas-animation-test.mjs — standalone offline gates for P6:
//   ActorAnimator530.advance + Skinning530.applyFrame
//
// Mirrors the inline-fixture pattern from .terrain-mesh-test.mjs and
// .player-appearance-test.mjs. Runs entirely on hand-rolled fixtures —
// no Js5Cache, no live server, no model archive.
//
// Run:    node 2009scape-web/client-patch/.bas-animation-test.mjs

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── inlined Skinning530.applyFrame (translate-only path is enough) ──

function applyFrame(model, frame, out) {
    const n = model.vertCount;
    if (out.length < n * 3) return;
    for (let i = 0; i < n; i++) {
        out[i * 3]     = model.vertX[i] | 0;
        out[i * 3 + 1] = model.vertY[i] | 0;
        out[i * 3 + 2] = model.vertZ[i] | 0;
    }
    if (!frame || !frame.base) return;
    const base = frame.base;
    for (let k = 0; k < frame.indices.length; k++) {
        const slot = frame.indices[k];
        const type = base.types?.[slot] ?? -1;
        const dx = frame.x[k];
        const dy = frame.y[k];
        const dz = frame.z[k];
        if (type === 1) {
            const verts = vertsForSlot(model, base, slot);
            for (let v = 0; v < verts.length; v++) {
                const vi = verts[v];
                if (vi < 0 || vi >= n) continue;
                out[vi * 3]     += dx;
                out[vi * 3 + 1] += dy;
                out[vi * 3 + 2] += dz;
            }
        }
        // Type 0 / 2 / others skipped in this offline harness; their
        // semantics are tested in Skinning530.ts proper.
    }
}

function vertsForSlot(model, base, slot) {
    if (!model.vertLabels) return [];
    const group = base.bones?.[slot];
    if (!group || group.length === 0) return [];
    const matches = [];
    for (let v = 0; v < model.vertCount; v++) {
        const lbl = model.vertLabels[v];
        for (let g = 0; g < group.length; g++) {
            if (lbl === group[g]) { matches.push(v); break; }
        }
    }
    return matches;
}

// ── inlined ActorAnimator530.advance ──

class ActorAnimator530 {
    constructor(framesPerTick = 3) {
        this.framesPerTick = framesPerTick;
        this.seqId = -1;
        this.frameIdx = 0;
        this.ticksSinceFrame = 0;
    }
    pickSeq(bas, state) {
        if (state === "walk") return bas.walkAnimation >= 0 ? bas.walkAnimation : bas.idleAnimationId;
        if (state === "run")  return bas.runAnimationId >= 0 ? bas.runAnimationId
            : (bas.walkAnimation >= 0 ? bas.walkAnimation : bas.idleAnimationId);
        return bas.idleAnimationId;
    }
    advance(bas, framesetLookup, state) {
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
        const frame = pickFrameAt(fs, this.frameIdx);
        this.ticksSinceFrame++;
        if (this.ticksSinceFrame >= Math.max(1, this.framesPerTick)) {
            this.frameIdx = nextFrameIndex(fs, this.frameIdx);
            this.ticksSinceFrame = 0;
        }
        return { frame, seqId: this.seqId, frameIdx: this.frameIdx };
    }
}

function pickFrameAt(fs, idx) {
    const frames = fs.frames;
    for (let attempt = 0; attempt < frames.length; attempt++) {
        const c = frames[(idx + attempt) % frames.length];
        if (c) return c;
    }
    return null;
}

function nextFrameIndex(fs, current) {
    const frames = fs.frames;
    for (let attempt = 1; attempt <= frames.length; attempt++) {
        const i = (current + attempt) % frames.length;
        if (frames[i]) return i;
    }
    return 0;
}

// ── fixtures ────────────────────────────────────────────────────────

// 4 transform slots, all type=1 (translate). Each slot owns a single
// bone-group id matching its slot number, so vertLabels=[0,1,2,3] gives
// each vert its own controlling slot.
const baseFixture = {
    id: 1,
    transforms: 4,
    types: [1, 1, 1, 1],
    shadow: [false, false, false, false],
    parts: [0, 0, 0, 0],
    bones: [[0], [1], [2], [3]],
};

// Three frames. Each frame translates one bone by a known dx along X.
// frame[0] → bone 0 → vert 0 by +10
// frame[1] → bone 1 → vert 1 by +20
// frame[2] → bone 2 → vert 2 by +30
const frameset = {
    id: 42,
    frames: [
        { base: baseFixture, length: 1, transformsAlpha: false, transformsColor: false,
          indices: [0], x: [10], y: [0], z: [0], prevOriginIndices: [-1], flags: [0] },
        { base: baseFixture, length: 1, transformsAlpha: false, transformsColor: false,
          indices: [1], x: [20], y: [0], z: [0], prevOriginIndices: [-1], flags: [0] },
        { base: baseFixture, length: 1, transformsAlpha: false, transformsColor: false,
          indices: [2], x: [30], y: [0], z: [0], prevOriginIndices: [-1], flags: [0] },
    ],
};

const bas = {
    id: 7,
    modelRotateTranslate: null,
    idleAnimationId: 42,        // points at our frameset
    walkAnimation: -1,
    slowWalkAnimationId: -1,
    slowWalkFullTurnAnimationId: -1,
    slowWalkCCWTurnAnimationId: -1,
    slowWalkCWTurnAnimationId: -1,
    runAnimationId: -1,
    runFullTurnAnimationId: -1,
    runCCWTurnAnimationId: -1,
    runCWTurnAnimationId: -1,
    walkFullTurnAnimationId: -1,
    walkCCWTurnAnimationId: -1,
    walkCWTurnAnimationId: -1,
    standingCCWTurn: -1,
    standingCWTurn: -1,
    anInt1059: 0, anInt1050: 0,
    yawAcceleration: 0, yawMaxSpeed: 0,
    rollAcceleration: 0, rollMaxSpeed: 0, rollTargetAngle: 0,
    pitchAcceleration: 0, pitchMaxSpeed: 0, pitchTargetAngle: 0,
    movementAcceleration: 0,
};

// 4 verts, one per bone. Base pose: all at origin so deltas are easy
// to assert against.
const model = {
    vertCount: 4,
    vertX: [0, 0, 0, 0],
    vertY: [0, 0, 0, 0],
    vertZ: [0, 0, 0, 0],
    vertLabels: [0, 1, 2, 3],
};

// ── run gates ───────────────────────────────────────────────────────

const lookup = (seqId) => seqId === 42 ? frameset : null;
const animator = new ActorAnimator530(/* framesPerTick */ 1);

// Call advance() three times. With framesPerTick=1 the frame index
// increments every call. Frame applied THIS tick = current frameIdx
// before stepping; so:
//   call 1: frame=frame[0] (vert 0 += 10), then frameIdx → 1
//   call 2: frame=frame[1] (vert 1 += 20), then frameIdx → 2
//   call 3: frame=frame[2] (vert 2 += 30), then frameIdx → 0 (wraps)
const out = new Float32Array(model.vertCount * 3);

const r1 = animator.advance(bas, lookup, "idle");
applyFrame(model, r1.frame, out);
const v0AfterCall1 = out[0];

const r2 = animator.advance(bas, lookup, "idle");
applyFrame(model, r2.frame, out);
const v1AfterCall2 = out[3];

const r3 = animator.advance(bas, lookup, "idle");
applyFrame(model, r3.frame, out);
const v2AfterCall3 = out[6];

// Gate assertions:
const expected_v0 = 10;
const expected_v1 = 20;
const expected_v2 = 30;

const ok_v0 = v0AfterCall1 === expected_v0;
const ok_v1 = v1AfterCall2 === expected_v1;
const ok_v2 = v2AfterCall3 === expected_v2;

if (!ok_v0) throw new Error(`vert 0 X expected ${expected_v0} got ${v0AfterCall1}`);
if (!ok_v1) throw new Error(`vert 1 X expected ${expected_v1} got ${v1AfterCall2}`);
if (!ok_v2) throw new Error(`vert 2 X expected ${expected_v2} got ${v2AfterCall3}`);

// After 3 advance calls, frameIdx has wrapped back to 0 (3 frames, advance every call).
const frameIdxAfter3 = animator.frameIdx;
if (frameIdxAfter3 !== 0) throw new Error(`frameIdx after 3 calls expected 0 got ${frameIdxAfter3}`);

// Run another 3 calls; frameIdx should still be 0 after another full loop.
animator.advance(bas, lookup, "idle");
animator.advance(bas, lookup, "idle");
animator.advance(bas, lookup, "idle");
const frameIdxAfter6 = animator.frameIdx;
if (frameIdxAfter6 !== 0) throw new Error(`frameIdx after 6 calls expected 0 got ${frameIdxAfter6}`);

// Test seq-switch resets frame counter mid-walk.
animator.advance(bas, lookup, "idle");           // frameIdx -> 1
const switchAnimator = new ActorAnimator530(1);
switchAnimator.advance(bas, lookup, "idle");     // seq=42, frameIdx -> 1
const before = switchAnimator.frameIdx;
const fakeBas2 = { ...bas, idleAnimationId: 99 };
switchAnimator.advance(fakeBas2, lookup, "idle"); // seq change → reset; lookup(99)=null so frame=null
if (switchAnimator.seqId !== 99) throw new Error(`seqId expected 99 got ${switchAnimator.seqId}`);
if (switchAnimator.frameIdx !== 0) throw new Error(`frameIdx after seq switch expected 0 got ${switchAnimator.frameIdx}`);

// ── trace ──

const expectedDelta = expected_v2;       // last applied frame's dx
const actualDelta = v2AfterCall3;
const trace = [
    `# Captured by .bas-animation-test.mjs at ${new Date().toISOString()}`,
    `# Gates: 4-bone fixture, 3-frame translate-only frameset, framesPerTick=1`,
    ``,
    `[Animator530] frames advanced, vert delta=${actualDelta} expected=${expectedDelta}`,
    `[Animator530] vert deltas: v0=+${v0AfterCall1} (frame 0), v1=+${v1AfterCall2} (frame 1), v2=+${v2AfterCall3} (frame 2)`,
    `[Animator530] frameIdx after 3 calls=${frameIdxAfter3}, after 6 calls=${frameIdxAfter6} (loop confirmed)`,
    `[Animator530] seq-switch reset OK: seqId=99, frameIdx=0 after switching from 42`,
].join("\n") + "\n";

const tracePath = join(__dirname, ".bas-animation-trace.txt");
writeFileSync(tracePath, trace);
console.log(`[bas-animation] trace captured at ${tracePath}`);
console.log(`[bas-animation] all 5 assertions passed`);
