# Plan: 530 web client — Tier 7 widget/Component port skeleton

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. This is a structural port — not full feature work. Goal is a *skeleton* the renderer and Tier 5c handlers can target.

## Goal

Create a minimal `Component` + `InterfaceList` port from `reference/rt4-client` that's good enough to:

1. Decode a 530 widget definition from idx3.
2. Hold the open-modal stack so the bank/quest/options interfaces can mount.
3. Replay the `Game.interfaceUpdates` flight recorder built in Tier 5c onto loaded components.

It does **not** need to render those components. That's a follow-up tier (Tier 7b — widget renderer). The win this tier delivers is "all Tier 5c data lands on a real object tree we can later draw".

## Why this can wait until now

Until Tier 5a/5b are in, the world doesn't stay in sync, and rendering UI on top of a broken world is the wrong order of operations. Tier 5c left a flight recorder of every IF_* update; Tier 7 hooks that recorder up to a real component tree.

## Scope (files you may edit)

- `2009scape-web/client-patch/osrs/cache/def/Component.ts` — new file.
- `2009scape-web/client-patch/osrs/InterfaceList.ts` — new file.
- `2009scape-web/client-patch/osrs/cache/def/ComponentLoader.ts` — new file (decodes idx3 entries).
- `2009scape-web/client-patch/osrs/Game.ts` — load on boot, replay flight recorder.
- `2009scape-web/client-patch/osrs/PacketHandler530.ts` — switch the Tier 5c branches from "record only" to "record + apply via `InterfaceList`". Do **not** delete the recorder; it stays as a debug trail.

## Out of scope (do NOT touch)

- The renderer (`Scene.ts`).
- ScriptRunner / CS2 — Tier 7b.
- BAS skeletons — Tier 8.
- Audio.

## Reference (rt4-client)

| File | Purpose | Notes |
|---|---|---|
| `Component.java` | The big component struct (50+ fields) | Most fields are passive containers. Port the type, parameters, position, size, color, and child fields first. |
| `ComponentPointer.java` | Long-keyed (interfaceId<<32 \| childId) lookup | Ports as a `Map<bigint, Component>`. |
| `InterfaceList.java` | Top-level "loaded interfaces" registry, plus the modal-open stack | The "modal-open stack" is a small tree: parent component + child substitutions. |
| `Js5.java` (idx3) | Where component bytes come from | We already have `Js5Cache.getNamedFileBytes(3, ...)` working. |

## Implementation

### 1. `Component.ts` minimal viable shape

```ts
export class Component {
    public id: number = 0;
    public type: number = 0;          // 0=container, 3=rect, 4=text, 5=sprite, 6=model, 9=line, 10=item-list
    public buttonType: number = 0;
    public contentType: number = 0;
    public x: number = 0;
    public y: number = 0;
    public width: number = 0;
    public height: number = 0;
    public parentId: number = -1;
    public childIds: number[] = [];

    // Type-specific:
    public text: string | null = null;
    public colour: number = 0;
    public sprite: number = -1;
    public modelId: number = -1;
    public scrollPos: number = 0;
    public hidden: boolean = false;

    // Decode from a 530 idx3 buffer. Only support enough fields to round-trip
    // bank/options/quest interfaces — everything else can be stubbed.
    static decode(buf: Buffer): Component {
        const c = new Component();
        // ... port decode loop from rt4 Component.java; copy line-by-line and
        //     leave a // (rt4 Component.java:NNN) comment on each step.
        return c;
    }
}
```

Skip animations/seqs/CS2 hooks. They can be added later. The MVP should compile-and-decode without crashing for every component byte sequence in idx3.

### 2. `InterfaceList.ts`

```ts
import { Component } from './cache/def/Component';

export class InterfaceList {
    static byKey: Map<bigint, Component> = new Map();
    static loadedInterfaces: Set<number> = new Set();
    static openModalStack: { parentInterfaceId: number; rootCompId: number }[] = [];

    static componentKey(interfaceId: number, childId: number): bigint {
        return (BigInt(interfaceId) << 32n) | BigInt(childId);
    }

    static get(interfaceId: number, childId: number): Component | null {
        return this.byKey.get(this.componentKey(interfaceId, childId)) ?? null;
    }

    static put(c: Component) {
        const interfaceId = c.id >>> 16;
        const childId = c.id & 0xffff;
        this.byKey.set(this.componentKey(interfaceId, childId), c);
        this.loadedInterfaces.add(interfaceId);
    }

    static loadInterface(js5: Js5Cache, interfaceId: number): Promise<void> {
        // For each child idx3 group → Component.decode → put.
    }

    static openModal(parentInterfaceId: number, rootCompId: number) {
        this.openModalStack.push({ parentInterfaceId, rootCompId });
    }
    static closeAll() { this.openModalStack = []; }
}
```

### 3. Boot integration in `Game.ts`

Don't pre-load all interfaces. Lazy-load in `InterfaceList.loadInterface(js5, id)` the first time an `IF_*` packet references the id. Hook this from PacketHandler530's interface branches:

```ts
case 48: {  // IF_SETTEXT2 — was Tier 5c "record only"
    const compId = this.g4(buf);
    const text = this.gjstr(buf);
    game.recordIfUpdate('IF_SETTEXT2', compId, { text });   // keep flight recorder
    const interfaceId = compId >>> 16;
    const childId = compId & 0xffff;
    if (!InterfaceList.loadedInterfaces.has(interfaceId)) {
        await InterfaceList.loadInterface(game.js5Cache, interfaceId);
    }
    const c = InterfaceList.get(interfaceId, childId);
    if (c) c.text = text;
    return true;
}
```

Apply the same expansion to all 7 Tier 5c branches.

### 4. Replay the flight recorder

After `InterfaceList` is wired, on first call to any apply-path replay any pre-existing entries in `game.interfaceUpdates` so we don't lose state captured before the component tree existed:

```ts
private static replayedRecorder = false;
static maybeReplayRecorder(game: any) {
    if (this.replayedRecorder) return;
    this.replayedRecorder = true;
    for (const u of game.interfaceUpdates) {
        // Re-dispatch via the apply path. Be careful — the recorder's
        // payload shape is whatever we put in there; map back to the
        // matching apply-call here.
    }
}
```

### 5. Self-test

Standard build path:

```bash
cd 2009scape-web
cp -R client-patch/osrs/. client/osrs/
./scripts/set-client-server.sh 10.8.0.1
cd client && rm -rf dist .cache && npm run build 2>&1 | tail -5
```

Build green is the bar. Walking around without hitting any modal interface should still work as before (we haven't added rendering). Opening a bank should populate `InterfaceList.byKey` with bank components; verify by `console.log([...InterfaceList.byKey.keys()].length)` after triggering a bank server-side.

## Acceptance criteria

1. `Component.decode` handles every byte sequence in 530 idx3 without throwing (verified by walking all groups in `Js5DatIndex` capacity range).
2. `InterfaceList` populates lazily from packet hits.
3. Tier 5c branches now apply state to the component tree, while still recording the flight log.
4. Build is green.
5. Plan checklist in `docs/web-client-plan.md` Tier 7 ticked with commit SHAs.

## Out of scope clarifications

- **Do not** render components yet. (`Scene.ts` untouched.)
- **Do not** port CS2 — leave hooks as `// TODO ScriptRunner (Tier 7b)`.
- **Do not** decode the full Component field set — minimum viable subset only. Adding a field later is cheap; adding a buggy decode for an unused field is not.

## Commit guidance

Two commits: `2009scape-web: tier7 — Component + InterfaceList skeleton`, then `2009scape-web: tier7 — wire IF_* handlers into component tree`. Push nothing.
