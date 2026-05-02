# Plan: 530 web client — Tier 9 BAS skeletons + skin transforms

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. This is one of the harder ports — the BAS (animation) system has a tight contract with `RawModel530`. Read `reference/rt4-client/client/src/main/java/rt4/AnimFrame.java` end-to-end before writing a line of TS.

## Goal

Bring server-driven character animation to the rev-530 web client. Today actor BAS metadata decodes (`BasType530`), but no skeletal transform is ever applied — characters T-pose. After this lands, walking, attacking, eating, and gathering animations play on player + NPC models.

The work has three layers:

1. **AnimBase port** — the shared bone topology each animation pre-references.
2. **AnimFrame port** — per-frame transform deltas (translate / rotate / scale per bone).
3. **Frameset + apply pipeline** — for a given (entity, BAS, time) tuple, sample the right frame and push transforms into the model's vertex array.

## Why this can't slot before Tier 8

Animations move vertices around. If you turn them on before the rasterizer is verified (Tier 6) and textured (Tier 8), every "is the player walking?" question becomes ambiguous with "is the player on screen?" + "is the texture loading?". Order matters — defer until Tier 8 ships.

## Scope (files you may edit)

- `2009scape-web/client-patch/osrs/cache/def/AnimBase530.ts` — new (mirror `AnimBase.java`).
- `2009scape-web/client-patch/osrs/cache/def/AnimFrame530.ts` — new (mirror `AnimFrame.java`).
- `2009scape-web/client-patch/osrs/cache/def/AnimFrameset530.ts` — new (groups N frames per logical sequence).
- `2009scape-web/client-patch/osrs/media/renderable/Skinning530.ts` — new: applies a frame to an `RawModel530` vertex set; produces a transformed vertex array per-tick.
- `2009scape-web/client-patch/osrs/Game.ts` — per-tick: pick BAS frame for each visible actor, apply transform.
- `2009scape-web/client-patch/osrs/PacketHandler530.ts` — adds anim-id assignment from per-actor update masks (most of this is already there in NPC_INFO / PLAYER_INFO; this tier just makes the `npc.animation` field actually drive a skin transform).

## Out of scope (do NOT touch)

- The rasterizer. Skinning produces transformed verts — the rasterizer reads them as before.
- Lip-sync / facial anims (rt4 calls these `Speed` and `Recolour` — separate tier).
- Animated textures.
- iOS port.

## Reference (rt4-client)

| File | Role | Comment |
|---|---|---|
| `BasType.java` | Per-actor mapping: idle/run/walk/attack/etc. → frameset id. | Already ported as `BasType530`. |
| `AnimBase.java` | Bone topology shared by N frames in a frameset. | Decode the per-bone `types[]` and `labels[][]` arrays. |
| `AnimFrame.java` | Per-frame: list of (boneIndex, transformType, dx, dy, dz). | The decode loop is dense — port line-by-line, comments referencing rt4. |
| `AnimFrameset.java` | An array of `AnimFrame` plus loop / hold metadata. | Maps a "sequence id" → a list of frames. |
| `FrameBuffer.java` | Scratch space rt4 reuses for transforming. | Skip — TS port can use a per-frame `Float32Array` allocated on demand. |

## Implementation

### 1. `AnimBase530.ts`

Decode shape (rt4 `AnimBase.java`):

```ts
export class AnimBase530 {
    public id: number = 0;
    public length: number = 0;          // bone count
    public types: Int32Array = new Int32Array(0);    // transform type per bone
    public labels: Int32Array[] = [];                // child-bone indices per bone

    static decode(buf: Buffer, id: number): AnimBase530 {
        const a = new AnimBase530();
        a.id = id;
        a.length = buf.g1();
        a.types = new Int32Array(a.length);
        for (let i = 0; i < a.length; i++) a.types[i] = buf.g1();
        a.labels = new Array(a.length);
        for (let i = 0; i < a.length; i++) {
            const n = buf.g1();
            const arr = new Int32Array(n);
            for (let j = 0; j < n; j++) arr[j] = buf.g1();
            a.labels[i] = arr;
        }
        return a;
    }

    static async load(js5: Js5Cache, id: number): Promise<AnimBase530 | null> {
        const data = await js5.getFileBytes(/* idx0 */ 0, /* group */ 0, id);
        return data ? AnimBase530.decode(new Buffer(data), id) : null;
    }
}
```

Confirm idx for AnimBase — rt4 uses `Js5.OPEN_ANIM_BASE` which is idx 0 group 0 in 530, but verify against the cache layout the project ships.

### 2. `AnimFrame530.ts`

Hardest of the three. Port `AnimFrame.java` constructor verbatim. Key invariants:

- The frame has a 2-byte header followed by `headerLen` bytes of per-bone "attributes" (a packed bitmask of which transform components changed).
- Then for each bone whose attributes are non-zero, a sequence of signed shorts giving dx/dy/dz/etc.
- The `prevOriginIndex` chain is critical — get it wrong and frames stack on the wrong parent.

```ts
export class AnimFrame530 {
    public base: AnimBase530;
    public length: number = 0;       // count of *changed* bones
    public indices: Int32Array;      // bone idx per changed bone
    public x: Int32Array;
    public y: Int32Array;
    public z: Int32Array;
    public prevOriginIndices: Int32Array;
    public flags: Uint8Array;
    public transformsAlpha: boolean = false;
    public transformsColor: boolean = false;

    constructor(bytes: Uint8Array, base: AnimBase530) {
        this.base = base;
        // (rt4 AnimFrame.java:64-160) — port verbatim
    }
}
```

Make every non-trivial line a comment referencing the rt4 line number. This block will be the most reviewed in the entire tier.

### 3. `AnimFrameset530.ts`

```ts
export class AnimFrameset530 {
    public id: number = 0;
    public frames: AnimFrame530[] = [];

    static async load(js5: Js5Cache, id: number): Promise<AnimFrameset530 | null> {
        // idx for framesets in 530 (verify) → list of group children
    }
}
```

### 4. `Skinning530.ts`

The function the renderer actually calls each tick:

```ts
export function applyFrame(model: RawModel530, frame: AnimFrame530, into: Float32Array): void {
    // Initialise `into` with model.vertexX/Y/Z
    // For each bone in frame.length:
    //   look up base.types[boneIdx] → translate / rotate / scale
    //   walk model vertex labels mapping to find which verts this bone touches
    //   apply transform delta
    // (rt4 Model.method606 / method607 — port the rotation matrix path)
}
```

Three transform types to support:

1. **Origin (type 0)** — sets translation pivot for subsequent bones.
2. **Translate (type 1)** — adds `(x, y, z)` to all vertices labelled with this bone.
3. **Rotate (type 2)** — small-angle Euler about the current origin. Use `Math.sin/cos` against the lookup table angles in rt4's `Model.SINE/COSINE` — pre-build them as `Float32Array` constants.

Skip type 3 (scale) and type 5 (alpha) for this tier — they're rare and need extra buffer state.

### 5. Per-tick wire-up in `Game.ts`

```ts
// In the per-frame draw loop, before scene.render():
for (const npc of game.npcs530) {
    const bas = BasType530.cache.get(npc.basId);
    if (!bas) continue;
    const seqId = pickSequenceId(npc, bas);  // walking/idle/attack/etc.
    const frameset = AnimFrameset530.cache.get(seqId);
    if (!frameset) continue;
    const frame = frameset.frames[npc.animationFrameIdx % frameset.frames.length];
    applyFrame(npc.model, frame, npc.transformedVerts);
    npc.animationFrameIdx++;
}
```

`pickSequenceId(npc, bas)`: today our `BasType530` already exposes `walkSeqId`, `idleSeqId`, `runSeqId`, etc. Use whichever matches `npc.movementState`.

### 6. Frame-rate budgeting

We're going to apply transforms for ~50 actors per frame. Hot path: ~30 bones × 50 actors = 1500 transform applications per tick, on a 16ms budget. Rules:

- **Never allocate** in the per-tick path. `transformedVerts` is a per-actor pre-allocated `Float32Array`.
- `Math.sin/cos` lookup table — build a `Float32Array` of 2048 entries once on boot. Quantise input angle to 11-bit.
- Only re-apply if the frame index changed since last tick.

If profiler shows the apply is over 2ms per frame, write a `[Anim] slow apply: actor=X bones=Y took=Tms` and pause — don't keep optimising blind.

## Self-test

```bash
cd 2009scape-web
cp -R client-patch/osrs/. client/osrs/
./scripts/set-client-server.sh 10.8.0.1
cd client && rm -rf dist .cache && npm run build 2>&1 | tail -5
```

Smoke: log in, walk forward. The local player's leg/arm models should oscillate visibly with the walk. Stand still — should idle (subtle breathing animation). Cast a spell — cast frameset plays.

## Acceptance criteria

1. AnimBase / AnimFrame / AnimFrameset all decode every entry in their idx without throwing (verify via a startup sweep, log fail count).
2. Local player visibly animates when walking and when idle.
3. ≥3 NPCs animate within view (idle/walk).
4. Frame budget: per-tick apply ≤2ms on a desktop browser (log via `performance.now()` deltas; gate by `__animProfileEnabled`).
5. Build is green.
6. Tier 9 checklist in `docs/web-client-plan.md` ticked with commit SHAs.

## Out of scope clarifications

- **Don't add lip-sync / facial.** Separate tier.
- **Don't port type-3 scale / type-5 alpha** — log a `[Anim] skipped type=N` once per type and move on.
- **Don't try to interpolate between frames** — use stepped frames first; smoothing is a follow-up.
- **Don't ship without the profile gate** — it's our only safety net against the apply path quietly tanking the framerate.

## Commit guidance

Multi-commit:

1. `2009scape-web: tier9 — AnimBase530 + AnimFrame530 decoders`
2. `2009scape-web: tier9 — AnimFrameset530 + idx wire-up`
3. `2009scape-web: tier9 — Skinning530.applyFrame`
4. `2009scape-web: tier9 — per-tick anim driver in Game.ts`

Push nothing.
