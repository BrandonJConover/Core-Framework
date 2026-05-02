// NpcAttacher530 — bridges a freshly composed NpcAppearance530 mesh
// onto an Npc record's renderable slot. Idempotent: when called twice
// for the same NPC the prior bridged model is `reset()` cleanly before
// the new one takes its place, so we don't leak the bridge's vertex
// buffers when an NPC morphs (NpcType change via NPC_INFO mask).
//
// Scope: glue only. Does NOT import the live Model530Bridge — instead
// the bridge is passed in by the caller. That keeps this file
// trace-harness-friendly (the test plugs in a fake bridge) and
// preserves the avoid-list constraint that we don't modify
// Model530Bridge.ts itself in this phase.

import type { RawModel530Data } from "../cache/def/RawModel530";

/** Minimal interface required from the bridge — exactly what
 *  Model530Bridge.attachModel returns, plus a `reset()` for cleanup. */
export interface BridgedAppearanceModel {
    reset?: () => void;
    /** Anything else the renderer pulls out (geometry, AABB, etc.). */
    [key: string]: any;
}

export interface AppearanceBridge {
    attachModel(rawMesh: RawModel530Data): BridgedAppearanceModel | null;
}

/** Slot the renderer reads from. We add it as a sidecar property on
 *  the Npc record rather than modifying its declared shape so the
 *  legacy 377 renderable stays the fallback. */
export interface NpcAvatarHost {
    appearanceModel530?: BridgedAppearanceModel | null;
}

/**
 * Attach a freshly composed NPC mesh to `npc.appearanceModel530`,
 * resetting any previous bridged model first. No-op when `mesh` is
 * null or empty.
 *
 * Returns the new bridged model (for callers that want to log /
 * profile / inspect it) or null when nothing was attached.
 */
export function attachNpcAppearance530(
    npc: NpcAvatarHost,
    mesh: RawModel530Data | null,
    bridge: AppearanceBridge,
): BridgedAppearanceModel | null {
    if (!mesh || mesh.vertexCount === 0) return null;
    const bridged = bridge.attachModel(mesh);
    if (!bridged) return null;
    if (npc.appearanceModel530 && typeof npc.appearanceModel530.reset === "function") {
        npc.appearanceModel530.reset();
    }
    npc.appearanceModel530 = bridged;
    return bridged;
}
