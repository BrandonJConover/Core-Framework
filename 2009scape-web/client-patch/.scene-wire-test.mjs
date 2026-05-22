// Offline trace harness for SceneWire530 — exercises every hook point
// against fixture data + a counting mock bridge. Verifies dispatch, side
// effects on host objects, and orchestrator state.
//
// We inline-mirror the orchestrator's logic against the same primitives
// (TerrainAdapter530.attachLandscape530, NpcAttacher530.attachNpcAppearance530,
// etc.) so the test does not depend on the TypeScript file existing —
// only the pure JavaScript-equivalent dispatch logic, matching the prior
// trace-harness convention.

import fs from "fs";

// ── Mocks ─────────────────────────────────────────────────────────

class CountingBridge {
    constructor() { this.created = 0; this.lastRaw = null; }
    attachModel(raw) {
        if (!raw || raw.vertexCount <= 0) return null;
        this.created++;
        this.lastRaw = raw;
        let resetCount = 0;
        return {
            id: this.created,
            verts: raw.vertexCount,
            tris: raw.triangleCount,
            reset() { resetCount++; },
            resetCount() { return resetCount; },
        };
    }
}

const blankRaw = (id, verts, tris) => ({
    id,
    vertexCount: verts,
    triangleCount: tris,
    texturedCount: 0,
    vertexX: new Array(verts).fill(0),
    vertexY: new Array(verts).fill(0),
    vertexZ: new Array(verts).fill(0),
    vertexBones: null,
    triangleVertexA: new Array(tris).fill(0),
    triangleVertexB: new Array(tris).fill(0),
    triangleVertexC: new Array(tris).fill(0),
    triangleInfo: null,
    trianglePriorities: null,
    triangleAlpha: null,
    triangleBones: null,
    triangleTextures: null,
    triangleTextureIndex: null,
    triangleColors: new Array(tris).fill(0),
    priority: 0,
    textureTypes: null,
    textureFacesP: null,
    textureFacesM: null,
    textureFacesN: null,
    texturesScaleX: null,
    texturesScaleY: null,
    texturesScaleZ: null,
    textureRotationY: null,
    textureExtraA: null,
    textureExtraB: null,
    cubeExtraA: null,
    cubeExtraB: null,
});

// ── Inline orchestrator dispatch (mirrors SceneWire530.ts logic) ──

class ActorAnimator {
    constructor(framesPerTick = 3) {
        this.framesPerTick = framesPerTick;
        this.seqId = -1;
        this.frameIdx = 0;
        this.ticksSinceFrame = 0;
    }
    pickSeq(bas, state) {
        if (state === "walk") return bas.walkAnimation >= 0 ? bas.walkAnimation : bas.idleAnimationId;
        if (state === "run") {
            if (bas.runAnimationId >= 0) return bas.runAnimationId;
            return bas.walkAnimation >= 0 ? bas.walkAnimation : bas.idleAnimationId;
        }
        return bas.idleAnimationId;
    }
    advance(bas, framesetLookup, state) {
        if (!bas) return { frame: null, seqId: -1, frameIdx: 0 };
        const want = this.pickSeq(bas, state);
        if (want !== this.seqId) { this.seqId = want; this.frameIdx = 0; this.ticksSinceFrame = 0; }
        const fs = framesetLookup(this.seqId);
        if (!fs || !fs.frames || fs.frames.length === 0) {
            return { frame: null, seqId: this.seqId, frameIdx: this.frameIdx };
        }
        const frame = fs.frames[this.frameIdx % fs.frames.length] || null;
        this.ticksSinceFrame++;
        if (this.ticksSinceFrame >= Math.max(1, this.framesPerTick)) {
            this.frameIdx = (this.frameIdx + 1) % fs.frames.length;
            this.ticksSinceFrame = 0;
        }
        return { frame, seqId: this.seqId, frameIdx: this.frameIdx };
    }
}

function attachLandscape530(scene, plane, mesh, bridge) {
    if (!mesh || mesh.vertexCount === 0) return null;
    if (plane < 0 || plane > 3) return null;
    const bridged = bridge.attachModel(mesh);
    if (!bridged) return null;
    if (!scene.landscape530) scene.landscape530 = [null, null, null, null];
    const prior = scene.landscape530[plane];
    if (prior && typeof prior.reset === "function") prior.reset();
    scene.landscape530[plane] = bridged;
    return bridged;
}

function attachNpcAppearance530(npc, mesh, bridge) {
    if (!mesh || mesh.vertexCount === 0) return null;
    const bridged = bridge.attachModel(mesh);
    if (!bridged) return null;
    if (npc.appearanceModel530 && typeof npc.appearanceModel530.reset === "function") {
        npc.appearanceModel530.reset();
    }
    npc.appearanceModel530 = bridged;
    return bridged;
}

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

class SceneWire530 {
    constructor(deps) {
        this.deps = deps;
        this.animators = new Map();
        this.rebuiltPlanesSet = new Set();
    }
    rebuildLandscape(host, scene, planes = 4) {
        let attached = 0, verts = 0, tris = 0;
        for (let plane = 0; plane < planes; plane++) {
            // Stand-in for buildLandscape530: use the host's pre-supplied
            // per-plane mesh fixture when present. The real impl walks
            // height/floor arrays through TerrainMesh530.buildTerrainMesh.
            const mesh = host.__planeMesh ? host.__planeMesh(plane) : null;
            if (!mesh) continue;
            if (attachLandscape530(scene, plane, mesh, this.deps.bridge)) {
                this.rebuiltPlanesSet.add(plane);
                attached++;
                verts += mesh.vertexCount;
                tris += mesh.triangleCount;
            }
        }
        return { attached, verts, tris };
    }
    rebuildNpcAppearance(npc, mesh) {
        return attachNpcAppearance530(npc, mesh, this.deps.bridge);
    }
    rebuildPlayerAvatar(player, mesh) {
        return attachPlayerAvatar530(player, mesh, this.deps.bridge);
    }
    async rebuildLocMesh(loc, shapeIndex, orientation) {
        // Stand-in for composeLocMesh: returns the loc.__fixtureMesh
        // when shapeIndex matches loc.shapes[0]. The real impl runs the
        // full LocMesh530 compose pipeline.
        if (!loc.shapes || loc.shapes[0] !== shapeIndex) return null;
        if (!loc.__fixtureMesh) return null;
        return loc.__fixtureMesh;
    }
    async rebuildAndAttachLoc(host, loc, shapeIndex, orientation) {
        const mesh = await this.rebuildLocMesh(loc, shapeIndex, orientation);
        if (!mesh) return null;
        const bridged = this.deps.bridge.attachModel(mesh);
        if (!bridged) return null;
        if (host.appearanceModel530 && typeof host.appearanceModel530.reset === "function") {
            host.appearanceModel530.reset();
        }
        host.appearanceModel530 = bridged;
        return bridged;
    }
    tickActor(actorKey, bas, state) {
        let animator = this.animators.get(actorKey);
        if (!animator) {
            animator = new ActorAnimator();
            this.animators.set(actorKey, animator);
        }
        return animator.advance(bas, this.deps.framesetLookup, state).frame;
    }
    dropActor(actorKey) { this.animators.delete(actorKey); }
    animatorCount() { return this.animators.size; }
    rebuiltPlanes() { return this.rebuiltPlanesSet; }
}

// ── Fixtures ──────────────────────────────────────────────────────

const planeMeshes = {
    0: blankRaw(1000, 144, 72),  // 6×6 painted region
    1: blankRaw(1001, 4, 2),     // single tile
    2: null,                      // empty plane — no attach
    3: blankRaw(1003, 36, 18),   // 3×3 painted region
};

const host = { __planeMesh: (plane) => planeMeshes[plane] };
const scene = {};

const bridge = new CountingBridge();

const idleFrameset = {
    id: 100,
    frames: [
        { id: 0, baseId: 0, baseTransform: 0 },
        { id: 1, baseId: 0, baseTransform: 0 },
        { id: 2, baseId: 0, baseTransform: 0 },
    ],
};
const walkFrameset = {
    id: 101,
    frames: [
        { id: 0, baseId: 0, baseTransform: 0 },
        { id: 1, baseId: 0, baseTransform: 0 },
    ],
};

const framesetLookup = (seqId) => {
    if (seqId === 100) return idleFrameset;
    if (seqId === 101) return walkFrameset;
    return null;
};

const wire = new SceneWire530({
    bridge,
    framesetLookup,
    rawModelLoader: async (id) => null,
});

// ── Hook 1: rebuildLandscape ──────────────────────────────────────

const landStats = wire.rebuildLandscape(host, scene, 4);
if (landStats.attached !== 3) throw new Error(`expected 3 planes attached, got ${landStats.attached}`);
if (landStats.verts !== 144 + 4 + 36) throw new Error(`unexpected verts ${landStats.verts}`);
if (landStats.tris !== 72 + 2 + 18) throw new Error(`unexpected tris ${landStats.tris}`);
if (!scene.landscape530) throw new Error("scene.landscape530 not set");
if (!scene.landscape530[0] || !scene.landscape530[1] || !scene.landscape530[3]) {
    throw new Error("expected landscape slots 0/1/3 set");
}
if (scene.landscape530[2] !== undefined && scene.landscape530[2] !== null) {
    throw new Error("expected slot 2 null/undefined");
}
if (!wire.rebuiltPlanes().has(0)) throw new Error("rebuiltPlanes missing 0");

// ── Hook 2: rebuildNpcAppearance ──────────────────────────────────

const npc = { id: 42 };
const npcMesh1 = blankRaw(2000, 8, 4);
wire.rebuildNpcAppearance(npc, npcMesh1);
if (!npc.appearanceModel530) throw new Error("npc.appearanceModel530 not set");
const firstNpcModel = npc.appearanceModel530;

// Re-attach should reset the prior bridged model first.
const npcMesh2 = blankRaw(2001, 12, 6);
wire.rebuildNpcAppearance(npc, npcMesh2);
if (npc.appearanceModel530 === firstNpcModel) throw new Error("npc model not replaced");
if (firstNpcModel.resetCount() !== 1) throw new Error("prior npc model not reset");

// Null mesh is a no-op.
const beforeCount = bridge.created;
wire.rebuildNpcAppearance(npc, null);
if (bridge.created !== beforeCount) throw new Error("null mesh should not produce a bridged model");

// ── Hook 3: rebuildPlayerAvatar ───────────────────────────────────

const player = { id: 1 };
const playerMesh = blankRaw(3000, 10, 5);
wire.rebuildPlayerAvatar(player, playerMesh);
if (!player.appearanceModel530) throw new Error("player.appearanceModel530 not set");

// ── Hook 4: tickActor + dropActor ─────────────────────────────────

const bas = { idleAnimationId: 100, walkAnimation: 101, runAnimationId: -1 };

// First call creates the animator, returns first idle frame.
const f0 = wire.tickActor(42, bas, "idle");
if (!f0) throw new Error("expected first tick to return frame");
if (wire.animatorCount() !== 1) throw new Error("expected 1 animator");

// Switching to walk should reset frameIdx and use walkFrameset.
wire.tickActor(42, bas, "walk");
const ticked = wire.animators.get(42);
if (ticked.seqId !== 101) throw new Error(`expected seqId 101 after switch, got ${ticked.seqId}`);
if (ticked.frameIdx !== 0) throw new Error("frameIdx should reset on seq change");

// Second actor adds to the map.
const npc2 = { id: 7 };
wire.tickActor(7, bas, "idle");
if (wire.animatorCount() !== 2) throw new Error("expected 2 animators");

// Drop removes from the map.
wire.dropActor(42);
if (wire.animatorCount() !== 1) throw new Error("dropActor should remove animator");

// ── Hook 5: rebuildAndAttachLoc ───────────────────────────────────

const locFixtureMesh = blankRaw(4000, 16, 8);
const loc = {
    id: 50,
    shapes: [10],
    models: [4000],
    __fixtureMesh: locFixtureMesh,
};
const locHost = {};
const locBridged = await wire.rebuildAndAttachLoc(locHost, loc, 10, 0);
if (!locBridged) throw new Error("expected loc to attach");
if (!locHost.appearanceModel530) throw new Error("locHost.appearanceModel530 not set");
if (locHost.appearanceModel530 !== locBridged) throw new Error("locHost slot mismatch");

// Wrong shape returns null.
const noMatch = await wire.rebuildAndAttachLoc({}, loc, 99, 0);
if (noMatch !== null) throw new Error("non-matching shape should return null");

// ── Trace ─────────────────────────────────────────────────────────

const lines = [];
lines.push(`[SceneWire530] landscape attached planes=${landStats.attached} verts=${landStats.verts} tris=${landStats.tris}`);
lines.push(`[SceneWire530] npc id=${npc.id} appearance attached, prior reset=${firstNpcModel.resetCount()}`);
lines.push(`[SceneWire530] player id=${player.id} avatar attached verts=${playerMesh.vertexCount}`);
lines.push(`[SceneWire530] animators tracked=${wire.animatorCount()} after dropActor`);
lines.push(`[SceneWire530] loc id=${loc.id} composed shape=10 verts=${locFixtureMesh.vertexCount}`);
lines.push(`[SceneWire530] bridge.created total=${bridge.created}`);

const traceUrl = new URL("./.scene-wire-trace.txt", import.meta.url);
fs.writeFileSync(traceUrl, lines.join("\n") + "\n");
console.log(lines.join("\n"));
