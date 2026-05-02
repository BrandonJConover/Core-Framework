# Plan: 530 web client — Tier 5c interface plumbing (drain-only)

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. This is a deliberately *defensive* tier — its only job is to keep the byte stream aligned when the server sends interface-management packets that we can't yet act on. Do **not** try to render anything new.

## Goal

Decode 7 widget/interface-system opcodes that today corrupt our buffer alignment because we either drop them or guess their length. After this lands, the dispatcher's "Parsed N packet(s), M remaining" log line stays at `M = 0` even after bank/options/quest interactions on the server.

The actual *acting on* these packets (changing visible UI) happens in **Tier 7**. We're laying alignment groundwork.

## Why this matters even without rendering

Several of these packets are var-short (length encoded in the header), but a few are fixed-length. If we read the wrong number of bytes, every subsequent packet in the same TCP frame is misaligned, and the renderer/state-update packets we already handle correctly start parsing garbage. The cost of skipping them defensively (with `consumeKnown`) is zero; the cost of getting the lengths wrong is hours of cascading bugs.

## Scope (files you may edit)

- `2009scape-web/client-patch/osrs/PacketHandler530.ts` — 7 new `case` branches.
- `2009scape-web/client-patch/osrs/Game.ts` — add `interfaceUpdates` recorder (see below) so a future Tier 7 implementer has a flight recorder of the last 50 IF_* events.
- `2009scape-web/client-patch/README.md` — update deferred bullet only if it mentions Tier 5c.

## Out of scope (do NOT touch)

- `Component.ts`, `InterfaceList.ts` (Tier 7).
- Renderer.
- Existing handlers' byte-read counts.

## Reference (rt4-client)

| Opcode | Name | rt4 file:line | Body shape |
|---|---|---|---|
| 2 | `IF_SETCOLOUR` | `Protocol.java:1737-1767` | `g4` (interfaceId<<16 \| childId), `g2` (rgb15) — fixed 6 bytes |
| 9 | `WIDGETSTRUCT_SETTING` | `Protocol.java:1319-1340ish` | varies, see body |
| 48 | `IF_SETTEXT2` | `Protocol.java:1212-1219` | `g4` (compId), `gjstr` text — var-short |
| 123 | `IF_SETTEXT3` | `Protocol.java:1078-1098ish` | `g4` (compId), `g4` (?), `gjstr` — var-short |
| 176 | `SWITCH_WIDGET` | `Protocol.java:1694-1736` | several `g2`/`g4` reads — fixed-ish, check rt4 carefully |
| 207 | `INTERFACE_ANIMATE_ROTATE` | `Protocol.java:1432+` | `g4` compId, `g2` seqId — fixed |
| 209 | `GAME_FRAME_UNK` | `Protocol.java:1768+` | unknown payload; rt4 just reads `g2` — fixed 2 bytes |
| 220 | `IF_SETSCROLLPOS` | `Protocol.java:1099+` | `g4` compId, `g2` scrollPos — fixed 6 bytes |

For each, **read it before porting**. Names with `g1add`/`g2add`/`ig2`/`g4` etc. all matter — copy them character-for-character and add a comment with the rt4 line.

## Implementation

### 1. Interface event recorder (flight recorder)

In `Game.ts`:

```ts
public interfaceUpdates: { kind: string; compId: number; payload: any; at: number }[] = [];
public recordIfUpdate(kind: string, compId: number, payload: any) {
    this.interfaceUpdates.push({ kind, compId, payload, at: performance.now() });
    if (this.interfaceUpdates.length > 50) this.interfaceUpdates.shift();
}
```

Tier 7 will replay this against the actual `Component` tree once the widget system lands. For now, it doubles as a debug log: `console.table(game.interfaceUpdates)` after a bank interaction lets a developer spot bursts.

### 2. Branches

```ts
case 2: {  // IF_SETCOLOUR (rt4 Protocol.java:1737)
    const compId = this.g4(buf);
    const colour15 = this.g2(buf);
    game.recordIfUpdate('IF_SETCOLOUR', compId, { colour15 });
    return true;
}

case 220: {  // IF_SETSCROLLPOS (rt4 Protocol.java:1099)
    const compId = this.g4(buf);
    const pos = this.g2(buf);
    game.recordIfUpdate('IF_SETSCROLLPOS', compId, { pos });
    return true;
}

case 207: {  // INTERFACE_ANIMATE_ROTATE (rt4 Protocol.java:1432)
    const compId = this.g4(buf);
    const seqId = this.g2(buf);
    game.recordIfUpdate('INTERFACE_ANIMATE_ROTATE', compId, { seqId });
    return true;
}

case 209: {  // GAME_FRAME_UNK (rt4 Protocol.java:1768)
    const value = this.g2(buf);
    game.recordIfUpdate('GAME_FRAME_UNK', 0, { value });
    return true;
}
```

For the var-short ones (48, 123) the dispatcher needs a `size` argument. If `dispatch(opcode530: number, buf: Buffer, size: number, game: any)` is the entry signature today (it is — see `static dispatch` in `PacketHandler530`), each var-short branch must consume exactly `size` bytes via:

```ts
case 48: {  // IF_SETTEXT2 (rt4 Protocol.java:1212)
    const start = buf.currentPosition;
    const compId = this.g4(buf);
    const text = this.gjstr(buf);
    game.recordIfUpdate('IF_SETTEXT2', compId, { text });
    // Defensive: align if rt4 read more than us
    if (buf.currentPosition - start < size) buf.currentPosition = start + size;
    return true;
}
```

For 9 and 176, the rt4 body has loops (multiple `g2`/`g4` per loop iteration, with the loop count derived from `size`). Implement those as `while (buf.currentPosition - start < size)`. The flight recorder should record one event per parsed sub-record.

### 3. Self-test

```bash
cd 2009scape-web
cp -R client-patch/osrs/. client/osrs/
./scripts/set-client-server.sh 10.8.0.1
cd client && rm -rf dist .cache && npm run build 2>&1 | tail -5
```

`BUILD SUCCEEDED`. To smoke-test alignment, follow the workflow in `2009scape-web/client-patch/README.md` (Local → Hetzner login path) and look for `Parsed N packet(s), 0 remaining` in the dev console. If you ever see `> 0 remaining` after the dispatcher catches up, your byte-counts are wrong.

## Acceptance criteria

1. Dispatcher's handled-opcode count rises by 7 → 89 of 97.
2. `Game.interfaceUpdates` ring buffer present with `recordIfUpdate` helper.
3. Build is green.
4. Plan checklist in `docs/web-client-plan.md` Tier 5c ticked with commit SHAs.

## Out of scope clarifications

- **Do not** wire any of these to a UI element. Recording only.
- **Do not** create `Component.ts` / `InterfaceList.ts` / `ScriptRunner.ts`. Tier 7.
- **Do not** decode huffman / cs2 bodies in opcode 9 if they're present — read raw bytes into a `Uint8Array` payload.

## Commit guidance

Single commit is fine for this tier; message: `2009scape-web: tier5c — drain-only interface opcodes`. Push nothing.
