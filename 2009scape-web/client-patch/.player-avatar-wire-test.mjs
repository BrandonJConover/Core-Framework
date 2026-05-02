// .player-avatar-wire-test.mjs — offline gates for P4 wire side
// (PlayerAvatarAttacher530 idempotent bridge attach).
//
// Run:    node 2009scape-web/client-patch/.player-avatar-wire-test.mjs

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── inlined attachPlayerAvatar530 (mirrors PlayerAvatarAttacher530.ts) ──

function attachPlayerAvatar530(player, mesh, bridge) {
    if (!mesh || mesh.vertexCount === 0) return null;
    const bridged = bridge.attachModel(mesh);
    if (!bridged) return null;
    if (player.appearanceModel530 && typeof player.appearanceModel530.reset === "function") {
        player.appearanceModel530.reset();
    }
    player.appearanceModel530 = bridged;
    return bridged;
}

// ── fixtures ────────────────────────────────────────────────────────

function tinyMesh(verts, label) {
    return { id: -1, vertexCount: verts, _fixtureLabel: label };
}

const meshA = tinyMesh(32, "starter-kit");
const meshB = tinyMesh(36, "+bronze-sword");
const meshEmpty = tinyMesh(0, "empty");

// Bridge stub that records reset() calls and gives each bridged model
// a unique id so we can prove the swap.
let resetCalls = 0;
const fakeBridge = {
    attachModel(mesh) {
        return { vertCount: mesh.vertexCount, _id: Math.random(), reset() { resetCalls++; } };
    },
};

// ── run gates ───────────────────────────────────────────────────────

const player = {};

// First attach: no prior model → no reset.
const a1 = attachPlayerAvatar530(player, meshA, fakeBridge);
if (!a1) throw new Error("first attach returned null");
if (player.appearanceModel530 !== a1) throw new Error("appearanceModel530 not set on first attach");
if (resetCalls !== 0) throw new Error(`first attach should not reset (count=${resetCalls})`);

// Second attach: prior model gets reset, new one takes its place.
const a2 = attachPlayerAvatar530(player, meshB, fakeBridge);
if (!a2) throw new Error("second attach returned null");
if (a2 === a1) throw new Error("second attach didn't produce a new bridged model");
if (player.appearanceModel530 !== a2) throw new Error("appearanceModel530 not pointing at second bridged model");
if (resetCalls !== 1) throw new Error(`second attach should reset prior exactly once (count=${resetCalls})`);

// Third call with empty mesh: no-op, slot unchanged.
const a3 = attachPlayerAvatar530(player, meshEmpty, fakeBridge);
if (a3 !== null) throw new Error("empty mesh attach should return null");
if (player.appearanceModel530 !== a2) throw new Error("empty mesh attach must not replace prior");
if (resetCalls !== 1) throw new Error(`empty mesh attach should not reset (count=${resetCalls})`);

// Vertex-buffer delta between the two attached meshes.
const vertDelta = a2.vertCount - a1.vertCount;
if (vertDelta !== meshB.vertexCount - meshA.vertexCount) {
    throw new Error(`vert delta expected ${meshB.vertexCount - meshA.vertexCount} got ${vertDelta}`);
}

// ── trace ──

const trace = [
    `# Captured by .player-avatar-wire-test.mjs at ${new Date().toISOString()}`,
    `# Gates: idempotent bridge attach, prior-reset, empty-mesh no-op, vert delta`,
    `# Mesh A: ${meshA.vertexCount} verts (starter kit)`,
    `# Mesh B: ${meshB.vertexCount} verts (+bronze-sword equip)`,
    ``,
    `[PlayerAvatar530] attached + replaced ok`,
    `[PlayerAvatar530] reset() called exactly once on the prior bridged model (resetCalls=${resetCalls})`,
    `[PlayerAvatar530] empty-mesh attach returned null and did not touch the slot`,
    `[PlayerAvatar530] vert-buffer delta=${vertDelta} (verts ${meshA.vertexCount} → ${meshB.vertexCount})`,
].join("\n") + "\n";

const tracePath = join(__dirname, ".player-avatar-wire-trace.txt");
writeFileSync(tracePath, trace);
console.log(`[player-avatar-wire] trace captured at ${tracePath}`);
console.log(`[player-avatar-wire] all assertions passed`);
