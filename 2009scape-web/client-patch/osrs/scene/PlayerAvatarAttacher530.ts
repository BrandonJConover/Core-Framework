// PlayerAvatarAttacher530 — bridges a freshly composed PlayerAppearance
// mesh onto the player's render slot. Idempotent: calling twice for the
// same player resets the prior bridged model cleanly before swapping in
// the new one, matching the structural pattern in NpcAttacher530.
//
// Bridge is passed in by the caller (rather than imported from
// Model530Bridge) so this file stays trace-harness-friendly and does
// not need to know about the avoid-listed Model530Bridge module.

import type { RawModel530Data } from "../cache/def/RawModel530";

export interface BridgedAppearanceModel {
    reset?: () => void;
    [key: string]: any;
}

export interface AppearanceBridge {
    attachModel(rawMesh: RawModel530Data): BridgedAppearanceModel | null;
}

/** Slot the renderer reads from. Sidecar property — does not modify
 *  the legacy 377 Player render path. */
export interface PlayerAvatarHost {
    appearanceModel530?: BridgedAppearanceModel | null;
}

/**
 * Attach a freshly composed appearance mesh to `player.appearanceModel530`.
 * Resets any previous bridged model first; no-op when `mesh` is null
 * or empty. Returns the new bridged model (or null when nothing was
 * attached).
 */
export function attachPlayerAvatar530(
    player: PlayerAvatarHost,
    mesh: RawModel530Data | null,
    bridge: AppearanceBridge,
): BridgedAppearanceModel | null {
    if (!mesh || mesh.vertexCount === 0) return null;
    const bridged = bridge.attachModel(mesh);
    if (!bridged) return null;
    if (player.appearanceModel530 && typeof player.appearanceModel530.reset === "function") {
        player.appearanceModel530.reset();
    }
    player.appearanceModel530 = bridged;
    return bridged;
}
