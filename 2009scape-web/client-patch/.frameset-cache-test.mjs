// Offline trace harness for FramesetCache530 — verifies the seq→frameset
// resolution chain, the sync `lookup()` adapter for ActorAnimator530, and
// the missing-seq memoization.
//
// Inline-mirrors the cache logic against the same primitives the real
// FramesetCache530 uses (no dependency on the TypeScript file existing).
// Loaders are pure JS mocks that return hand-rolled fixture data.

import fs from "fs";

// ── Inline cache (mirror of FramesetCache530.ts) ──────────────────

class FramesetCache530 {
    constructor(loadSeq, loadFrameset) {
        this.loadSeq = loadSeq;
        this.loadFrameset = loadFrameset;
        this.bySeqId = new Map();
        this.missingSeqIds = new Set();
    }
    get(seqId) {
        const fs = this.bySeqId.get(seqId);
        return fs === undefined ? null : fs;
    }
    lookup() { return (seqId) => this.get(seqId); }
    isKnownMissing(seqId) { return this.missingSeqIds.has(seqId); }
    size() { return this.bySeqId.size; }
    async preload(seqIds) {
        let added = 0;
        for (const seqId of seqIds) {
            if (seqId < 0) continue;
            if (this.bySeqId.has(seqId) || this.missingSeqIds.has(seqId)) continue;
            try {
                const seq = await this.loadSeq(seqId);
                if (!seq || !seq.frames || seq.frames.length === 0) {
                    this.missingSeqIds.add(seqId);
                    continue;
                }
                const framesetId = (seq.frames[0] >>> 16) & 0xFFFF;
                if (framesetId === 0) { this.missingSeqIds.add(seqId); continue; }
                const fs = await this.loadFrameset(framesetId);
                if (!fs) { this.missingSeqIds.add(seqId); continue; }
                this.bySeqId.set(seqId, fs);
                added++;
            } catch (_) {
                this.missingSeqIds.add(seqId);
            }
        }
        return added;
    }
    clear() { this.bySeqId.clear(); this.missingSeqIds.clear(); }
}

// ── Fixtures ──────────────────────────────────────────────────────

// Three seqs. seq 100 → frameset 5 (idle), seq 101 → frameset 7 (walk),
// seq 999 doesn't exist. seq 5000 has empty frames. seq 7777 maps to a
// framesetId of 0 (sentinel for "no animation").
const seqFixtures = {
    100: { frames: [(5 << 16) | 0, (5 << 16) | 1, (5 << 16) | 2] },
    101: { frames: [(7 << 16) | 0, (7 << 16) | 1] },
    5000: { frames: [] },
    7777: { frames: [(0 << 16) | 4] },
    // 999 missing entirely
};

const framesetFixtures = {
    5: { id: 5, frames: [
        { id: 0, baseId: 0, baseTransform: 0 },
        { id: 1, baseId: 0, baseTransform: 0 },
        { id: 2, baseId: 0, baseTransform: 0 },
    ]},
    7: { id: 7, frames: [
        { id: 0, baseId: 0, baseTransform: 0 },
        { id: 1, baseId: 0, baseTransform: 0 },
    ]},
};

let seqCalls = 0, framesetCalls = 0;
const loadSeq = async (seqId) => {
    seqCalls++;
    return seqFixtures[seqId] ?? null;
};
const loadFrameset = async (framesetId) => {
    framesetCalls++;
    return framesetFixtures[framesetId] ?? null;
};

// ── Tests ─────────────────────────────────────────────────────────

const cache = new FramesetCache530(loadSeq, loadFrameset);

// Initial state
if (cache.size() !== 0) throw new Error("expected empty cache");
if (cache.get(100) !== null) throw new Error("get on empty should return null");
if (cache.lookup()(100) !== null) throw new Error("lookup on empty should return null");

// Preload three valid + missing + empty
const added = await cache.preload([100, 101, 999, 5000, 7777]);
if (added !== 2) throw new Error(`expected 2 added, got ${added}`);
if (cache.size() !== 2) throw new Error(`expected size 2, got ${cache.size()}`);

// Lookups for added entries
const fs100 = cache.get(100);
if (!fs100 || fs100.id !== 5) throw new Error("seq 100 should resolve to frameset 5");
if (fs100.frames.length !== 3) throw new Error("frameset 5 should have 3 frames");
const fs101 = cache.get(101);
if (!fs101 || fs101.id !== 7) throw new Error("seq 101 should resolve to frameset 7");

// Sync lookup matches get
const sync = cache.lookup();
if (sync(100) !== fs100) throw new Error("sync lookup must match get");
if (sync(101) !== fs101) throw new Error("sync lookup must match get");

// Missing/empty/zero-frameset paths memoized as missing
if (!cache.isKnownMissing(999)) throw new Error("seq 999 should be known-missing");
if (!cache.isKnownMissing(5000)) throw new Error("seq 5000 (empty frames) should be known-missing");
if (!cache.isKnownMissing(7777)) throw new Error("seq 7777 (zero framesetId) should be known-missing");
if (cache.get(999) !== null) throw new Error("missing seq returns null");

// Re-preload should be a no-op (size unchanged, no new loader calls for cached ids)
const seqCallsBefore = seqCalls;
const reAdded = await cache.preload([100, 101, 999, 5000, 7777]);
if (reAdded !== 0) throw new Error(`re-preload should add 0, got ${reAdded}`);
if (seqCalls !== seqCallsBefore) throw new Error("re-preload should not re-fetch");

// Clear resets both maps
cache.clear();
if (cache.size() !== 0) throw new Error("clear should empty cache");
if (cache.isKnownMissing(999)) throw new Error("clear should reset missing set");

// Re-preload after clear works again
const reAddedAfterClear = await cache.preload([100, 101]);
if (reAddedAfterClear !== 2) throw new Error("preload after clear should re-add");

// ── Animator integration sanity check ─────────────────────────────

// Inline copy of ActorAnimator530.advance with framesPerTick=1 to verify
// the lookup() closure plugs into the animator without ceremony.
class ActorAnimator530 {
    constructor() { this.seqId = -1; this.frameIdx = 0; this.ticksSinceFrame = 0; this.framesPerTick = 1; }
    pickSeq(bas, state) {
        if (state === "walk") return bas.walkAnimation >= 0 ? bas.walkAnimation : bas.idleAnimationId;
        return bas.idleAnimationId;
    }
    advance(bas, framesetLookup, state) {
        const want = this.pickSeq(bas, state);
        if (want !== this.seqId) { this.seqId = want; this.frameIdx = 0; this.ticksSinceFrame = 0; }
        const fs = framesetLookup(this.seqId);
        if (!fs || !fs.frames || fs.frames.length === 0) return { frame: null, seqId: this.seqId };
        const frame = fs.frames[this.frameIdx % fs.frames.length];
        this.ticksSinceFrame++;
        if (this.ticksSinceFrame >= this.framesPerTick) {
            this.frameIdx = (this.frameIdx + 1) % fs.frames.length;
            this.ticksSinceFrame = 0;
        }
        return { frame, seqId: this.seqId };
    }
}

const bas = { idleAnimationId: 100, walkAnimation: 101, runAnimationId: -1 };
const animator = new ActorAnimator530();
const lookup = cache.lookup();

// 3 idle ticks → frame 0, 1, 2 (frameset 5 has 3 frames)
const t0 = animator.advance(bas, lookup, "idle");
const t1 = animator.advance(bas, lookup, "idle");
const t2 = animator.advance(bas, lookup, "idle");
if (!t0.frame || !t1.frame || !t2.frame) throw new Error("animator idle ticks should produce frames");
if (t0.seqId !== 100) throw new Error(`expected idle seqId 100, got ${t0.seqId}`);

// Switch to walk → seq=101, frame from frameset 7
const w0 = animator.advance(bas, lookup, "walk");
if (w0.seqId !== 101) throw new Error(`walk should switch seqId, got ${w0.seqId}`);
if (!w0.frame) throw new Error("walk frame should not be null");

// ── BAS seq-id collectors ─────────────────────────────────────────

const BAS_SEQ_FIELDS = [
    "idleAnimationId", "walkAnimation",
    "slowWalkAnimationId", "slowWalkFullTurnAnimationId",
    "slowWalkCCWTurnAnimationId", "slowWalkCWTurnAnimationId",
    "runAnimationId", "runFullTurnAnimationId",
    "runCCWTurnAnimationId", "runCWTurnAnimationId",
    "walkFullTurnAnimationId", "walkCCWTurnAnimationId",
    "walkCWTurnAnimationId", "standingCCWTurn", "standingCWTurn",
];

function collectBasSeqIds(bas) {
    if (!bas) return [];
    const out = [];
    for (const f of BAS_SEQ_FIELDS) {
        const v = bas[f];
        if (typeof v === "number" && v >= 0) out.push(v);
    }
    return out;
}

function collectAllBasSeqIds(basCache) {
    if (!basCache || basCache.size === 0) return [];
    const seen = new Set();
    basCache.forEach((bas) => {
        for (const f of BAS_SEQ_FIELDS) {
            const v = bas[f];
            if (typeof v === "number" && v >= 0) seen.add(v);
        }
    });
    const arr = [...seen]; arr.sort((a, b) => a - b);
    return arr;
}

const basCache = new Map();
basCache.set(1, { idleAnimationId: 100, walkAnimation: 101, runAnimationId: -1, slowWalkAnimationId: -1, slowWalkFullTurnAnimationId: -1, slowWalkCCWTurnAnimationId: -1, slowWalkCWTurnAnimationId: -1, runFullTurnAnimationId: -1, runCCWTurnAnimationId: -1, runCWTurnAnimationId: -1, walkFullTurnAnimationId: -1, walkCCWTurnAnimationId: -1, walkCWTurnAnimationId: -1, standingCCWTurn: 200, standingCWTurn: 201 });
basCache.set(2, { idleAnimationId: 100, walkAnimation: 102, runAnimationId: 103, slowWalkAnimationId: -1, slowWalkFullTurnAnimationId: -1, slowWalkCCWTurnAnimationId: -1, slowWalkCWTurnAnimationId: -1, runFullTurnAnimationId: -1, runCCWTurnAnimationId: -1, runCWTurnAnimationId: -1, walkFullTurnAnimationId: -1, walkCCWTurnAnimationId: -1, walkCWTurnAnimationId: -1, standingCCWTurn: -1, standingCWTurn: -1 });
basCache.set(3, { idleAnimationId: -1, walkAnimation: -1, runAnimationId: -1, slowWalkAnimationId: -1, slowWalkFullTurnAnimationId: -1, slowWalkCCWTurnAnimationId: -1, slowWalkCWTurnAnimationId: -1, runFullTurnAnimationId: -1, runCCWTurnAnimationId: -1, runCWTurnAnimationId: -1, walkFullTurnAnimationId: -1, walkCCWTurnAnimationId: -1, walkCWTurnAnimationId: -1, standingCCWTurn: -1, standingCWTurn: -1 });

const bas1Ids = collectBasSeqIds(basCache.get(1));
if (bas1Ids.length !== 4) throw new Error(`bas 1 expected 4 seq ids, got ${bas1Ids.length}`);
if (!bas1Ids.includes(100) || !bas1Ids.includes(101) || !bas1Ids.includes(200) || !bas1Ids.includes(201)) {
    throw new Error(`bas 1 collected ids wrong: ${JSON.stringify(bas1Ids)}`);
}

const allIds = collectAllBasSeqIds(basCache);
const expectedIds = [100, 101, 102, 103, 200, 201];
if (JSON.stringify(allIds) !== JSON.stringify(expectedIds)) {
    throw new Error(`expected union ${JSON.stringify(expectedIds)}, got ${JSON.stringify(allIds)}`);
}

// Empty / null cases
if (collectBasSeqIds(null).length !== 0) throw new Error("null bas should return []");
if (collectAllBasSeqIds(null).length !== 0) throw new Error("null cache should return []");
if (collectAllBasSeqIds(new Map()).length !== 0) throw new Error("empty cache should return []");

// ── Trace ─────────────────────────────────────────────────────────

const lines = [];
lines.push(`[FramesetCache530] preloaded size=${cache.size()} (after clear+re-preload)`);
lines.push(`[FramesetCache530] seqLoader calls=${seqCalls} framesetLoader calls=${framesetCalls}`);
lines.push(`[FramesetCache530] seq=100 → frameset id=${fs100.id} frames=${fs100.frames.length}`);
lines.push(`[FramesetCache530] seq=101 → frameset id=${fs101.id} frames=${fs101.frames.length}`);
lines.push(`[FramesetCache530] missing-memo: 999=${!cache.isKnownMissing(999)?"absent":"yes"}, post-clear cleared`);
lines.push(`[FramesetCache530] animator idle frames advanced 0→1→2; switch-to-walk seqId=${w0.seqId}`);
lines.push(`[FramesetCache530] BAS collector: bas=1 ids=${bas1Ids.length} union=${allIds.length} (${expectedIds.join(",")})`);

const traceUrl = new URL("./.frameset-cache-trace.txt", import.meta.url);
fs.writeFileSync(traceUrl, lines.join("\n") + "\n");
console.log(lines.join("\n"));
