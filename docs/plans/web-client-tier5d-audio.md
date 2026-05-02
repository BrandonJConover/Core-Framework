# Plan: 530 web client — Tier 5d audio (SoundBank + 2 opcodes)

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. This plan is independent of Tier 6/7/8 — it can run in parallel with any of them.

## Goal

Wire up the two server-side audio opcodes (`SOUND_AREA = 97`, `SYNTH_SOUND = 172`) and the minimal `SoundBank` + `SoundPlayer` plumbing they need so:

1. Spell casts, eat ticks, and other one-shot SFX play through the browser's `AudioContext`.
2. Looping area-tagged ambient SFX (campfire crackle, river bubbling) start when the player walks into range and stop when they leave.
3. `Preferences.muteSfx` (we'll wire a checkbox later) cleanly silences both paths.

After this lands the dispatcher's handled-opcode count rises by 2 to 91/97 (assuming 5a-c shipped). It's small but deliberately self-contained — no widget system, no rasterizer, no protocol changes.

## Why this matters

Sound is a strong "feels alive" signal that takes minutes of work to ship and has no dependency on other tiers. Doing it now also unblocks `SOUND_AREA` which currently advances the byte stream wrong (rt4 reads 5 bytes; we drop it via the default branch which reads `size` bytes — usually fine, but if a future opcode rides on a particular zone-update bundle the audio packet's extra bytes can mis-align it).

## Scope (files you may edit)

- `2009scape-web/client-patch/osrs/PacketHandler530.ts` — 2 new `case` branches (97, 172).
- `2009scape-web/client-patch/osrs/sound/SoundBank.ts` — new file: idx14 (SFX track) lookup.
- `2009scape-web/client-patch/osrs/sound/SoundPlayer.ts` — new file: web-audio playback controller.
- `2009scape-web/client-patch/osrs/sound/AudioContextHolder.ts` — new file: lazy `new AudioContext()` (Safari needs first user gesture before .resume()).
- `2009scape-web/client-patch/osrs/Game.ts` — boot the bank, attach the player to `SoundPlayer.tick()`.
- `2009scape-web/client-patch/osrs/util/Preferences.ts` — add `muteSfx: boolean`, `ambientSoundsVolume: number` (0..255 to match rt4).

## Out of scope (do NOT touch)

- Music streaming (rt4 `MidiPlayer`/`MusicTrack` — separate tier).
- Speech / TTS.
- Spatial audio / panning — keep it stereo-mono for now.
- Volume sliders / settings UI.
- iOS native client.

## Reference (rt4-client)

| File | Role | Notes |
|---|---|---|
| `Protocol.java:361-383` | `SOUND_AREA` parse + queue | Adds an entry to `SoundPlayer.ids/loops/delays/positions` arrays. Per-tick scan culls entries the player walks out of range of. |
| `Protocol.java:2032-2041` | `SYNTH_SOUND` parse | One-shot: `g2 trackId, g1 volume, g2 delay`. |
| `Sound.java` | The decoded SFX sample (PCM-ish from idx14). | Tier 1 implementation can ignore everything except the raw sample bytes — modern browsers can decode AIFF / WAV directly via `AudioContext.decodeAudioData()`. |
| `SoundBank.java` | Cache of decoded `Sound` instances. | Mirror as a `Map<number, AudioBuffer>` in TS. |
| `SoundPlayer.java` | Active-sound queue with cull-on-distance + delay. | This is the chunk we port most carefully. |
| `SoundPcmStream.java` | Mixer / output pipeline. | Skip — `AudioContext` IS our mixer. |

## Implementation

### 1. `AudioContextHolder.ts`

```ts
export class AudioContextHolder {
    private static ctx: AudioContext | null = null;
    private static unlocked = false;

    static get(): AudioContext | null {
        if (!this.ctx && typeof AudioContext !== 'undefined') {
            this.ctx = new AudioContext();
        }
        return this.ctx;
    }

    /** Call from the first user pointer event. Required for Safari. */
    static unlock(): void {
        const ctx = this.get();
        if (!ctx || this.unlocked) return;
        ctx.resume().catch(() => {});
        this.unlocked = true;
    }
}
```

In `GameShell.ts`'s pointer-event handler (or wherever the first canvas-tap lives) call `AudioContextHolder.unlock()`. Don't add a second listener; piggyback an existing one.

### 2. `SoundBank.ts`

```ts
import { Js5Cache } from '../Js5Cache';
import { AudioContextHolder } from './AudioContextHolder';

export class SoundBank {
    private static cache = new Map<number, AudioBuffer>();
    private static missing = new Set<number>();
    private static js5: Js5Cache | null = null;

    static attach(js5: Js5Cache) { this.js5 = js5; }

    static async getBuffer(trackId: number): Promise<AudioBuffer | null> {
        if (this.cache.has(trackId)) return this.cache.get(trackId)!;
        if (this.missing.has(trackId) || !this.js5) return null;

        // idx14 holds SFX in 530. Verify against the cache layout your project
        // is shipping; some 530 dumps put SFX in idx14, others in idx15.
        const raw = await this.js5.getGroupBytes(14, trackId);
        const ctx = AudioContextHolder.get();
        if (!raw || !ctx) {
            this.missing.add(trackId);
            return null;
        }

        try {
            // decodeAudioData wants a fresh ArrayBuffer copy
            const ab = raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength) as ArrayBuffer;
            const buf = await ctx.decodeAudioData(ab);
            this.cache.set(trackId, buf);
            return buf;
        } catch (e) {
            this.missing.add(trackId);
            return null;
        }
    }
}
```

If `decodeAudioData` rejects every track in the cache, the format is probably 8-bit μ-law / RuneScape's custom container. In that case the implementer should add a one-time decoder before `decodeAudioData` (look for `Sound.decode()` in rt4 — it returns 16-bit signed PCM at 22050 Hz; build a `Float32Array`, normalise to [-1, 1], wrap in an `AudioBuffer.copyToChannel`).

Don't ship the custom decoder unless `decodeAudioData` actually fails on real cache data — most 530 caches ship WAV-compatible blobs.

### 3. `SoundPlayer.ts`

Two queues:

```ts
interface ActiveSound {
    trackId: number;
    loopsRemaining: number;     // -1 for one-shot
    delayUntil: number;         // performance.now() + delay*ms
    chunkX: number;             // for area sounds (range-cull)
    chunkZ: number;
    range: number;              // chunks
    source: AudioBufferSourceNode | null;
}

export class SoundPlayer {
    private static queue: ActiveSound[] = [];
    private static maxConcurrent = 50;

    static play(volume: number, trackId: number, delayMs: number) {
        if (Preferences.muteSfx) return;
        if (this.queue.length >= this.maxConcurrent) return;
        this.queue.push({
            trackId, loopsRemaining: 0,
            delayUntil: performance.now() + delayMs,
            chunkX: -1, chunkZ: -1, range: 0,
            source: null,
        });
    }

    static playArea(trackId: number, chunkX: number, chunkZ: number,
                    range: number, loops: number, delayMs: number) {
        if (Preferences.muteSfx) return;
        if (this.queue.length >= this.maxConcurrent) return;
        this.queue.push({
            trackId, loopsRemaining: loops,
            delayUntil: performance.now() + delayMs,
            chunkX, chunkZ, range,
            source: null,
        });
    }

    /** Call once per render tick from Game.ts. */
    static tick(playerChunkX: number, playerChunkZ: number) {
        const now = performance.now();
        const ctx = AudioContextHolder.get();
        if (!ctx) return;

        for (let i = this.queue.length - 1; i >= 0; i--) {
            const s = this.queue[i];

            // Range-cull area sounds
            if (s.chunkX >= 0) {
                const r = s.range + 1;
                if (Math.abs(s.chunkX - playerChunkX) > r ||
                    Math.abs(s.chunkZ - playerChunkZ) > r) {
                    if (s.source) try { s.source.stop(); } catch {}
                    this.queue.splice(i, 1);
                    continue;
                }
            }

            if (now < s.delayUntil) continue;
            if (s.source) continue;   // already playing

            // Lazy fire: load buffer + start.
            SoundBank.getBuffer(s.trackId).then(buf => {
                if (!buf || !ctx) return;
                const node = ctx.createBufferSource();
                node.buffer = buf;
                node.loop = s.loopsRemaining > 0;
                node.connect(ctx.destination);
                node.start();
                s.source = node;
                if (!node.loop) {
                    node.onended = () => {
                        const idx = this.queue.indexOf(s);
                        if (idx >= 0) this.queue.splice(idx, 1);
                    };
                }
            });
        }
    }
}
```

### 4. Preferences

```ts
// Preferences.ts (existing? if not, create)
export class Preferences {
    static muteSfx = false;
    static ambientSoundsVolume = 192;   // 0..255
}
```

### 5. Wire the two opcodes

```ts
case 97: {  // SOUND_AREA  (rt4 Protocol.java:361-383)
    const local15 = this.g1(buf);
    const chunkX = game.chunkX + ((local15 >> 4) & 0x7);
    const chunkZ = game.chunkY + (local15 & 0x7);
    let trackId = this.g2(buf);
    if (trackId === 65535) trackId = -1;
    const local31 = this.g1(buf);
    const range = (local31 >> 4) & 0xf;
    const loops = local31 & 0x7;
    const delay = this.g1(buf);
    if (chunkX >= 0 && chunkZ >= 0 && chunkX < 104 && chunkZ < 104 && trackId >= 0) {
        SoundPlayer.playArea(trackId, chunkX, chunkZ, range, loops, delay * 20);
    }
    return true;
}

case 172: {  // SYNTH_SOUND  (rt4 Protocol.java:2032-2041)
    let trackId = this.g2(buf);
    const volume = this.g1(buf);
    if (trackId === 65535) trackId = -1;
    const delay = this.g2(buf);
    if (trackId >= 0) SoundPlayer.play(volume, trackId, delay * 20);
    return true;
}
```

`delay * 20` because rt4 stores delay in ticks at 50ms each → milliseconds. Same scale rt4 uses internally.

### 6. Hook `SoundPlayer.tick()` into Game.ts

In whatever per-frame method advances character animations, call `SoundPlayer.tick(playerChunkX, playerChunkZ)` once. Cheap — most frames have an empty queue.

## Self-test

```bash
cd 2009scape-web
cp -R client-patch/osrs/. client/osrs/
./scripts/set-client-server.sh 10.8.0.1
cd client && rm -rf dist .cache && npm run build 2>&1 | tail -5
```

Smoke: load Lumbridge in a browser, eat food. The eat-tick SFX should play. Walk into Edgeville bank — the sword-on-shield clinking ambient should kick in within a tick of crossing the boundary.

If you hear nothing:

1. Check `AudioContextHolder.get()?.state` — must be `running`. Often Safari leaves it in `suspended`; `unlock()` fixes that on first user gesture.
2. Console-log `SoundBank.getBuffer(N)` for one known trackId to see if decode is succeeding. If `decodeAudioData` rejects, the cache is in the custom RS PCM container — implement the `Sound.decode()` port from rt4 first.

## Acceptance criteria

1. Two cases handled in `PacketHandler530.dispatch`; opcode count rises by 2.
2. `SoundBank` + `SoundPlayer` + `AudioContextHolder` files compile.
3. Build is green.
4. SFX audibly plays in Playwright (or browser) when eating food on a live server, and at least one ambient sound activates near a known emitter (campfire / forge / fountain).
5. Mute switch (`Preferences.muteSfx = true`) silences both queues immediately.
6. Plan checklist in `docs/web-client-plan.md` Tier 5d ticked with commit SHA.

## Out of scope clarifications

- **Don't add a settings UI.** `Preferences.muteSfx` is just a field for now.
- **Don't port music** — that's MIDI and a separate tier.
- **Don't add 3D positional / panning** — flat stereo only.
- **Don't optimise** — the queue scan is O(N) on N≤50, fine.

## Commit guidance

One commit, message `2009scape-web: tier5d — SoundBank + SOUND_AREA/SYNTH_SOUND`. Push nothing.
