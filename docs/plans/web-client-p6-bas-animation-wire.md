# Plan: 530 web client — P6 BAS animation driver wire

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. **Pickup gate:** P4 (player avatar wire) and P5 (NPC wire) both shipped — actors must be visible (T-posing is fine) before this phase has a model to animate. Confirm via `[PlayerAvatar530]` / `[NpcAppearance530]` console lines.

## Goal

Drive per-tick skeletal animation on the bridged P4/P5 actor models. Today they T-pose. After this lands, walking/idle/attack frames pulse on every actor in view, sourced from the existing `BasType530` + `AnimFrameset530` data ports.

This is the structural sibling of [Tier 9 BAS skeletons](web-client-tier9-bas-skeletons.md) — but scoped narrower: **wire only**, not the decoder ports (those shipped). Tier 9's plan covered AnimBase / AnimFrame / Frameset decoders + the apply pipeline. P6 narrows to "we have decoders + frames + bridged actor models; connect them per render tick".

## Why now

Three frames-of-motion sit in cache today (BasType, AnimFrameset, plus the per-actor `basId` field on NpcType / PlayerAppearance) but nothing runs them. P6 closes that loop.

## Scope (files you may edit)

- `2009scape-web/client-patch/osrs/scene/ActorAnimator530.ts` — **new**: per-actor animation state machine. Tracks current frame index + accumulated tick time; selects the right frameset (idle / walk / run / attack) based on actor state.
- `2009scape-web/client-patch/osrs/media/renderable/Skinning530.ts` — **new** (or take Tier 9's stub if it shipped): `applyFrame(model, frame, transformedVerts: Float32Array)` — runs the per-bone transforms onto a pre-allocated vert buffer.
- `2009scape-web/client-patch/osrs/Game.ts` — per-render-tick: walk visible actors, compute the new vertex buffer for each, hand to the bridge.
- `2009scape-web/client-patch/osrs/media/renderable/Model530Bridge.ts` — **read-only audit**: confirm the bridge exposes a "swap vertex buffer for this frame" entry point; if not, document the gap and *stop*. Don't modify the bridge in this plan.

## Out of scope (do NOT touch)

- BAS / AnimFrame decoders — already shipped.
- Lip-sync / facial / scaling / alpha frame types (rt4 transform types 3 / 5).
- Inter-frame interpolation — stepped frames only for v1.
- Music / SFX timing tied to animation.
- iOS port.

## Reference

| What | Source |
|---|---|
| `BasType530` | `2009scape-web/client-patch/osrs/cache/def/BasType530.ts` — exposes `walkSeqId`, `idleSeqId`, `runSeqId`, etc. |
| `AnimFrameset530` | `2009scape-web/client-patch/osrs/cache/def/AnimFrameset530.ts` — the per-actor frame array. |
| Frame application math | rt4 `Model.method606` / `method607` — port the rotation matrix path, not the GL helpers. Same approach Tier 9 plan documented. |
| Sin/cos LUT | rt4 `Model.SINE` / `COSINE` — pre-build as `Float32Array(2048)` constants on boot. |
| Tier 9 plan body | [`web-client-tier9-bas-skeletons.md`](web-client-tier9-bas-skeletons.md) — re-read; that plan and this one collide unless P6 narrows to wire-only. |

## Implementation

### 1. `ActorAnimator530.ts`

Per-actor (player + NPC) animator. Lives on `actor.animator530` (where `actor` is the player or NPC record).

```ts
import type { BasType530Data } from '../cache/def/BasType530';
import type { AnimFrameset530Data } from '../cache/def/AnimFrameset530';

export class ActorAnimator530 {
    public seqId: number = -1;
    public frameIdx: number = 0;
    public ticksSinceFrame: number = 0;

    /// Pick the right frameset id given the actor's current movement state.
    /// `state` is one of: 'idle' | 'walk' | 'run' | 'attack' | 'death'.
    pickSeq(bas: BasType530Data, state: string): number {
        switch (state) {
            case 'walk': return bas.walkSeqId ?? bas.idleSeqId ?? -1;
            case 'run':  return bas.runSeqId  ?? bas.walkSeqId ?? -1;
            case 'attack':
            case 'death':
            case 'idle':
            default:     return bas.idleSeqId ?? -1;
        }
    }

    /// Advance one render tick. Returns the frame to apply, or null if no
    /// animation is set / data missing.
    advance(bas: BasType530Data | null,
            framesetLookup: (id: number) => AnimFrameset530Data | null,
            state: string): { frame: any | null; framesetId: number } {
        if (!bas) return { frame: null, framesetId: -1 };
        const wantSeq = this.pickSeq(bas, state);
        if (wantSeq !== this.seqId) {
            this.seqId = wantSeq;
            this.frameIdx = 0;
            this.ticksSinceFrame = 0;
        }
        const fs = framesetLookup(this.seqId);
        if (!fs || !fs.frames || fs.frames.length === 0) {
            return { frame: null, framesetId: this.seqId };
        }
        // Stepped frames only — advance every ~3 ticks (~150ms at 50ms tick).
        this.ticksSinceFrame++;
        if (this.ticksSinceFrame >= 3) {
            this.frameIdx = (this.frameIdx + 1) % fs.frames.length;
            this.ticksSinceFrame = 0;
        }
        return { frame: fs.frames[this.frameIdx], framesetId: this.seqId };
    }
}
```

### 2. `Skinning530.applyFrame`

Mirror Tier 9's plan §4 verbatim. Three transform types: 0 (origin), 1 (translate), 2 (rotate). Skip 3/4/5/6 in v1 (log once and continue).

The output is a `Float32Array` of length `3 * model.vertCount` — the renderer reads from this in place of the static `vertX/vertY/vertZ` arrays.

### 3. Per-tick driver in `Game.ts`

```ts
// In whatever method advances the per-render-tick state (search for the
// existing per-frame entity walk):
for (const player of [game.localPlayer, ...game.remotePlayers]) {
    if (!player.appearanceModel530) continue;
    if (!player.animator530) player.animator530 = new ActorAnimator530();
    const bas = BasType530.cache.get(player.basId);
    const state = player.movementState ?? 'idle';   // engine already tracks this
    const { frame } = player.animator530.advance(bas, framesetLookup, state);
    if (frame) {
        Skinning530.applyFrame(
            player.appearanceModel530.rawModel,
            frame,
            player.transformedVerts ??= new Float32Array(player.appearanceModel530.rawModel.vertCount * 3),
        );
        player.appearanceModel530.swapVertBuffer?.(player.transformedVerts);
    }
}
// Same loop for NPCs.
```

If `swapVertBuffer` doesn't exist on `Model530Bridge`, the read-only audit in *Scope* should produce a `[Bridge] no vert-swap entry point — animation gated on bridge update` log + a `STOP` of this plan.

### 4. Frame-rate budget

Tier 9's budget applies: ≤2ms apply path on a desktop browser for 50 actors × 30 bones. Add a profile gate the same way Tier 9 specified.

## Verification gates

1. `cp` patch → client for all touched files.
2. `cd 2009scape-web/client && npx tsc --noEmit` clean (modulo pako).
3. Trace harness `2009scape-web/client-patch/.bas-animation-test.mjs`:
   - Hand-rolls a 4-bone fixture `BasType530Data` + a 3-frame `AnimFrameset530Data` (each frame translates one bone by a known dx).
   - Hand-rolls a 4-vert `RawModel530Data` (one vert per bone).
   - Inline-mirrors `ActorAnimator530.advance` + `Skinning530.applyFrame`.
   - Asserts: after 3 advance calls, vertex 0 has translated by the expected dx; after 6 calls, frameIdx loops back to 0.
   - Writes trace to `2009scape-web/client-patch/.bas-animation-trace.txt` with `[Animator530] frames advanced, vert delta=N expected=N`.
4. `node .bas-animation-test.mjs` exits 0 with the marker line.

Optional Gate 5: live client — `[Animator530] tick` log fires per visible actor (gated to once / second to avoid log flood).

## Acceptance criteria

1. Gates 1-4 pass.
2. Live client (when reachable) shows actors animating: idle breathing, walking arm/leg motion. Frame budget stays under 16 ms total per render tick.
3. `docs/web-client-plan.md` gains `- [x] P6: BAS animator wired to bridged actors` with commit SHA.
4. **Do not commit.**

## Out of scope clarifications

- **No interpolation between frames.** Stepped only.
- **No type 3/4/5/6 transforms.** Log + skip.
- **Don't refactor Tier 9's plan** — P6 supersedes Tier 9's per-tick wire-up section. The decoder ports Tier 9 covers are still authoritative.
- **Don't tie animation to BAS audio events.** That hook is Tier 5d / 8 territory.
- **Don't handle attack-cycle alignment with combat damage.** That's a server-driven concern; the animator just plays the seq id the engine sets.

## Commit guidance

Three commits:

1. `2009scape-web: p6 — Skinning530.applyFrame (3 transform types)`
2. `2009scape-web: p6 — ActorAnimator530 per-actor state machine`
3. `2009scape-web: p6 — wire animator into per-render-tick loop`

Push nothing.
