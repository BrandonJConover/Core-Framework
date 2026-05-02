# Plan: 530 web client — P4 PlayerAppearance530 → Scene render wire

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. The data-side port (PlayerAppearance530.ts, parseAppearanceMask, composeAppearanceModel, mergeRawModels, applyAppearanceMask) shipped with offline gates green — see `2009scape-web/client-patch/.player-appearance-trace.txt`. This plan wires that compositor's output into the Scene render path so every player on screen actually shows their wardrobe + equipment.

## Goal

When the `PLAYER_INFO` packet's APPEARANCE mask updates a player, run `applyAppearanceMask` to produce the composite `RawModel530Data`, bridge it through `Model530Bridge`, and attach it as the visible model for that player. After this lands, the local player + every nearby remote player render with their actual gender / kit / equipped weapon / dye colours instead of the default placeholder.

## Why this matters

P3b puts terrain on the screen. P4 puts *characters* on the screen. Together they're the visible-rendering closure: world geometry + animated avatars. Both depend on the same `Model530Bridge` plumbing, so this plan is the structural twin of P3b — different data path, same wire.

## Scope (files you may edit)

- `2009scape-web/client-patch/osrs/scene/PlayerAvatarAttacher530.ts` — **new** thin glue file. Bridges a `RawModel530Data` (output of `composeAppearanceModel`) into `Model530Bridge` and stores it on the `Player` record's renderable slot.
- `2009scape-web/client-patch/osrs/PacketHandler530.ts` — at the APPEARANCE-mask call site (where `applyAppearanceMask` already runs per the data-side port), invoke the new attacher with the player ref + the composed model.
- `2009scape-web/client-patch/osrs/scene/Scene.ts` — add `attachPlayerModel530(player, bridgedModel)` if the existing per-player render slot doesn't already accept the bridge's output. Don't refactor existing player-draw logic.

## Out of scope (do NOT touch)

- `PlayerAppearance530.ts` itself — frozen by P3a-of-the-player-port's offline gates.
- `Model.ts`, `Model530.ts`, `Model530Animator.ts`, `Model530Bridge.ts`.
- NPC appearance (separate plan; same shape, different lookup path).
- Animation / skin (BAS — that's Tier 9, see `docs/plans/web-client-tier9-bas-skeletons.md`).
- Lighting / texture passes.
- iOS port.

## Reference

| What | Source |
|---|---|
| `PlayerAppearance530.applyAppearanceMask` | `2009scape-web/client-patch/osrs/media/renderable/PlayerAppearance530.ts` |
| Existing `parseAppearanceMask` byte format | same file — confirmed by the data-side trace `decode OK: gender=0 basId=42 idk=7 obj=1 empty=4` |
| APPEARANCE-mask call site | `2009scape-web/client-patch/osrs/PacketHandler530.ts` — search for `applyAppearanceMask` usage. |
| Per-player renderable slot | `Player` model's renderable field (on the legacy `Player.ts` or its 530 sibling). Read its existing setter; if it already accepts a bridged Model, the new attacher just calls it. |
| `Model530Bridge` API | `2009scape-web/client-patch/osrs/media/renderable/Model530Bridge.ts` |

## Implementation

### 1. `PlayerAvatarAttacher530.ts` (new)

```ts
import type { RawModel530Data } from '../cache/def/RawModel530';
import { Model530Bridge } from '../media/renderable/Model530Bridge';

/// Attaches a freshly composed appearance mesh to a player's render slot.
/// Idempotent — replaces the prior bridged model and resets it cleanly so
/// we don't leak the old one's resources.
export function attachPlayerAvatar530(player: any, mesh: RawModel530Data): void {
    if (!mesh || mesh.vertCount === 0) return;
    const bridged = Model530Bridge.attachModel(mesh);   // verify API — match what TerrainMesh530's wire used in P3b
    if (player.appearanceModel530?.reset) player.appearanceModel530.reset();
    player.appearanceModel530 = bridged;
}

/// Convenience: full path from raw mask bytes to an attached model.
/// Used by PacketHandler530's APPEARANCE branch.
export async function applyAndAttachAppearance530(
    player: any,
    maskBytes: Uint8Array,
    idkLookup: any,
    objLookup: any,
    rawModelLoader: any,
): Promise<void> {
    const { applyAppearanceMask } = await import('../media/renderable/PlayerAppearance530');
    const mesh = await applyAppearanceMask(player, maskBytes, idkLookup, objLookup, rawModelLoader);
    if (mesh) attachPlayerAvatar530(player, mesh);
}
```

### 2. PacketHandler530 hook-up

Find the APPEARANCE-mask branch in `PacketHandler530.ts`'s PLAYER_INFO loop. Today it likely calls `applyAppearanceMask` and either updates a 377-style `Player.updateAppearance()` shim or stops there. Replace the trailing call with `applyAndAttachAppearance530(player, maskBytes, ...)` so the bridged model also lands on `player.appearanceModel530`.

Keep the legacy 377 shim alive for now — it's still what the renderer reads if `appearanceModel530` is absent. Once Scene.ts learns to prefer the 530 model when present (Step 3 below), the shim becomes redundant; that retirement is a follow-up plan.

### 3. Scene.ts — prefer 530 model when present

Locate the per-player draw site. It currently walks `Player`'s legacy renderable. Add a one-line precedence check:

```ts
const renderable = player.appearanceModel530 ?? player.legacyRenderable;
```

That's the entire change. Don't refactor the surrounding draw logic.

### 4. Quick browser smoke

After implementation, the dev console should emit one of:

- `[PlayerAvatar530] attached gender=0 verts=N` per APPEARANCE-mask update.

(Add the log inside `attachPlayerAvatar530`; gate on a per-player `.lastVertCount` so it only fires when the mesh actually changed.)

If something looks wrong (player invisible, T-pose, etc.) check whether `appearanceModel530` is being set — if so, the issue is on the bridge / Scene draw side, not data. Don't fix data; that's the data-side port's job, not this plan.

## Verification gates

1. `cp 2009scape-web/client-patch/osrs/scene/PlayerAvatarAttacher530.ts 2009scape-web/client/osrs/scene/PlayerAvatarAttacher530.ts` and `cp` the patched `PacketHandler530.ts` and `Scene.ts`.
2. `cd 2009scape-web/client && npx tsc --noEmit` shows no new errors beyond the pre-existing pako warning.
3. Trace harness `2009scape-web/client-patch/.player-avatar-wire-test.mjs`:
   - hand-rolls a fixture `player` object with no `appearanceModel530` slot
   - hand-rolls fixture mask bytes (the same shape `.player-appearance-test.mjs` uses)
   - inline-mirrors `attachPlayerAvatar530` (faking `Model530Bridge.attachModel` to return its input + a `reset()` method)
   - asserts: after the call, `player.appearanceModel530` is non-null
   - calls again with a *different* mask (different equipped weapon) and asserts the new bridged ref differs from the prior; calls `prior.reset()` was invoked exactly once
   - writes the trace to `2009scape-web/client-patch/.player-avatar-wire-trace.txt` with line `[PlayerAvatar530] attached + replaced ok` plus a vertex-delta line
4. `node 2009scape-web/client-patch/.player-avatar-wire-test.mjs` exits 0 with the marker line present.

Optional Gate 5 (browser): if the live server's reachable, run the standard local-dev workflow and confirm a `[PlayerAvatar530] attached` log fires within 5s of login.

## Acceptance criteria

1. Gates 1-4 pass.
2. `[PlayerAvatar530] attached gender=N verts=M` appears at least once in the dev console when running against a live server, within 5s of login.
3. `docs/web-client-plan.md` gets a new line under "Renderer plan (Tier 6)": `- [x] P4: PlayerAppearance530 wired into Scene` with the commit SHA.
4. **Do not commit.**

## Out of scope clarifications

- **No animation.** Static T-pose composite is acceptable for this plan; BAS skeletons (Tier 9) is a separate plan.
- **No NPC equivalent.** NPCs use ActorDefinition's idle model directly; they don't need a compositor. Wire them in a sister plan.
- **No retirement of the legacy `Player.updateAppearance()` shim.** Keep it as fallback; retirement is its own plan once we trust the 530 path in production.
- **Don't bake the appearance mesh into a vertex buffer object (VBO) yet.** The bridge stores it; the renderer can still re-traverse per frame. VBO caching is a perf plan for later.

## Commit guidance

`2009scape-web: p4 — wire PlayerAppearance530 composite into Scene`. Push nothing.
