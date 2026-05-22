/**
 * FramesetCache530 — sync lookup adapter from a seq id to a decoded
 * AnimFrameset530Data. The animator (`ActorAnimator530`) wants a
 * synchronous `framesetLookup(seqId)` callback, but resolving a seq
 * goes through two async cache hits (idx20 → SeqType530, then idx0 →
 * AnimFrameset530). This cache pre-warms the seq→frameset mapping in
 * the background, so the per-tick render path stays sync.
 *
 * Resolution chain (per rt4 SeqType.java decode op 1 + AnimFrameset.java):
 *
 *   seqId
 *     └─ SeqType530.load(js5, seqId)            (idx20)
 *          └─ seq.frames[0] >>> 16              (high 16 bits = framesetId)
 *               └─ AnimFrameset530.load(js5, framesetId)  (idx0 + idx1)
 *                    └─ AnimFrameset530Data
 *
 * The cache is keyed by seqId (not framesetId) because a single
 * frameset can back many seqs and we want the animator's lookup key
 * to match the seq it requested. Multiple seqs sharing a frameset
 * resolve to the same `AnimFrameset530Data` instance — that's fine,
 * the animator only walks the frames array sequentially.
 *
 * Loaders are injected so the cache is pure-data and trivially
 * testable. `makeFramesetCache530(js5)` is the convenience factory
 * that wires the real `SeqType530.load` + `AnimFrameset530.load`.
 */

import { AnimFrameset530, AnimFrameset530Data } from "./AnimFrameset530";
import { SeqType530 } from "./SeqType530";
import type { BasType530Data } from "./BasType530";
import type { Js5Cache } from "../../Js5Cache";

/** Async loader: seq id → at least the frames table. */
export interface SeqFramesLoader {
    (seqId: number): Promise<{ frames: number[] | null } | null>;
}

/** Async loader: frameset id → decoded frameset data. */
export interface FramesetLoader {
    (framesetId: number): Promise<AnimFrameset530Data | null>;
}

export class FramesetCache530 {
    private readonly bySeqId: Map<number, AnimFrameset530Data> = new Map();
    private readonly missingSeqIds: Set<number> = new Set();

    constructor(
        private readonly loadSeq: SeqFramesLoader,
        private readonly loadFrameset: FramesetLoader,
    ) {}

    /** Sync lookup for the animator. Returns null when not yet preloaded. */
    get(seqId: number): AnimFrameset530Data | null {
        const fs = this.bySeqId.get(seqId);
        return fs === undefined ? null : fs;
    }

    /** Returns a closure suitable for `SceneWire530Deps.framesetLookup`. */
    lookup(): (seqId: number) => AnimFrameset530Data | null {
        return (seqId: number) => this.get(seqId);
    }

    /** Whether a seq id was attempted but resolved to nothing. Cached so
     *  repeated preloads don't re-hit the cache for known-empty ids. */
    isKnownMissing(seqId: number): boolean {
        return this.missingSeqIds.has(seqId);
    }

    /** Total cached entries (NPCs + players we've successfully resolved). */
    size(): number { return this.bySeqId.size; }

    /**
     * Pre-warm the cache for a list of seq ids. Each id is resolved
     * via `loadSeq` → first-frame framesetId → `loadFrameset`. Already-
     * cached ids are skipped. Errors per-id are silent (the entry is
     * marked missing). Returns the count newly added to the cache.
     */
    async preload(seqIds: number[]): Promise<number> {
        // Process in parallel chunks with explicit setTimeout(0) yields
        // between chunks. The serial-await version pinned the V8 main
        // thread for ~8 minutes against this cache (1961 ids × 2 fetches
        // each), starving input handlers long after the title screen drew.
        let added = 0;
        const CHUNK = 32;
        const candidates = seqIds.filter(
            (id) => id >= 0 && !this.bySeqId.has(id) && !this.missingSeqIds.has(id),
        );
        for (let base = 0; base < candidates.length; base += CHUNK) {
            const promises: Promise<void>[] = [];
            for (let i = 0; i < CHUNK && base + i < candidates.length; i++) {
                const seqId = candidates[base + i];
                promises.push((async () => {
                    try {
                        const seq = await this.loadSeq(seqId);
                        if (!seq || !seq.frames || seq.frames.length === 0) {
                            this.missingSeqIds.add(seqId);
                            return;
                        }
                        const framesetId = (seq.frames[0] >>> 16) & 0xFFFF;
                        if (framesetId === 0) {
                            this.missingSeqIds.add(seqId);
                            return;
                        }
                        const fs = await this.loadFrameset(framesetId);
                        if (!fs) {
                            this.missingSeqIds.add(seqId);
                            return;
                        }
                        this.bySeqId.set(seqId, fs);
                        added++;
                    } catch (_) {
                        this.missingSeqIds.add(seqId);
                    }
                })());
            }
            await Promise.all(promises);
            await new Promise<void>((res) => setTimeout(res, 0));
        }
        return added;
    }

    /** Drop every entry. Useful for cache flushes on teleport / world swap. */
    clear(): void {
        this.bySeqId.clear();
        this.missingSeqIds.clear();
    }
}

/**
 * Build a FramesetCache530 backed by the live Js5Cache. Wraps
 * `SeqType530.load` + `AnimFrameset530.load`. Used from Game.ts's
 * `getOrCreateSceneWire530()`.
 */
export function makeFramesetCache530(js5: Js5Cache): FramesetCache530 {
    return new FramesetCache530(
        async (seqId: number) => {
            const seq = await SeqType530.load(js5, seqId);
            if (!seq) return null;
            return { frames: seq.frames };
        },
        async (framesetId: number) => AnimFrameset530.load(js5, framesetId),
    );
}

// ── Seq-id collectors ────────────────────────────────────────────

/** Every BasType530 field that holds a SeqType id (>=0 means present). */
const BAS_SEQ_FIELDS: (keyof BasType530Data)[] = [
    "idleAnimationId",
    "walkAnimation",
    "slowWalkAnimationId",
    "slowWalkFullTurnAnimationId",
    "slowWalkCCWTurnAnimationId",
    "slowWalkCWTurnAnimationId",
    "runAnimationId",
    "runFullTurnAnimationId",
    "runCCWTurnAnimationId",
    "runCWTurnAnimationId",
    "walkFullTurnAnimationId",
    "walkCCWTurnAnimationId",
    "walkCWTurnAnimationId",
    "standingCCWTurn",
    "standingCWTurn",
];

/**
 * Pull every non-negative seq id out of a single BasType into a fresh
 * array. Order matches `BAS_SEQ_FIELDS`; duplicates within a single BAS
 * are preserved (caller dedupes across the full collection).
 */
export function collectBasSeqIds(bas: BasType530Data | null | undefined): number[] {
    if (!bas) return [];
    const out: number[] = [];
    for (const field of BAS_SEQ_FIELDS) {
        const v = bas[field];
        if (typeof v === "number" && v >= 0) out.push(v);
    }
    return out;
}

/**
 * Walk a BasType cache (e.g. `ActorDefinition.basCache530`) and return the
 * deduped union of every seq id referenced by any entry. The returned
 * array is sorted ascending so successive calls (across reloads) produce
 * stable ordering for diagnostics.
 */
export function collectAllBasSeqIds(
    basCache: Map<number, BasType530Data> | null | undefined,
): number[] {
    if (!basCache || basCache.size === 0) return [];
    const seen = new Set<number>();
    basCache.forEach((bas) => {
        for (const field of BAS_SEQ_FIELDS) {
            const v = bas[field];
            if (typeof v === "number" && v >= 0) seen.add(v);
        }
    });
    const arr: number[] = [];
    seen.forEach((v) => arr.push(v));
    arr.sort((a, b) => a - b);
    return arr;
}
