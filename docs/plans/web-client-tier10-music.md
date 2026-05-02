# Plan: 530 web client — Tier 10 music streaming (MIDI → WebAudio)

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. This plan is **independent** of every other tier and can run in parallel with anything else.

## Goal

Play the right region's background music when the player walks into it, fade between tracks as zones change, and respect a `Preferences.musicMuted` mute switch. After this lands, Lumbridge plays "Harmony", deserts play "Desert Voyage", etc.

The 530 cache stores music as MIDI files in idx6 (verify against your specific 530 cache layout — some dumps put music in idx14). MIDI cannot stream directly through `AudioContext.decodeAudioData()`, so the implementation needs a soft-synth or a build-time conversion.

## Why now

Music is the single biggest "atmosphere" upgrade that's still trivially additive. Everything else in the rev-530 backlog (Tiers 5/6/7/8/9) is one form of "renderer / state" — music doesn't conflict with any of them and can ship in parallel.

## Why this is two paths

There are two ways to play MIDI in a browser; each has trade-offs. Pick **path A** for MVP unless your 530 cache has unusual MIDI files.

### Path A — Build-time conversion to OGG (recommended for v1)

1. At build time (`npm run build` hook or one-shot CLI), iterate the music idx, extract MIDI files, convert each to OGG using FluidSynth + a small General MIDI soundfont (~5 MB).
2. Ship the OGGs alongside `dist/`.
3. At runtime, `AudioContextHolder.decodeAudioData()` plays them like any sound effect.

**Pros:** trivial runtime, ~50ms latency to start, deterministic playback.
**Cons:** ~30 MB of OGG payload (vs ~3 MB of MIDI), no per-instrument volume control, locked to one soundfont.

### Path B — Runtime soft-synth (defer)

Use [`spessasus/spessasynth_lib`](https://github.com/spessasus/spessasynth_lib) or `tonejs/midi`. Adds ~200 KB to the bundle, plays MIDI directly, supports soundfont swap. Heavier per-track CPU.

**Defer to a future Tier 10b** unless Path A's payload size is unacceptable.

## Scope (files you may edit — Path A)

- `2009scape-web/scripts/convert-music.sh` — new file: extracts the music idx, runs FluidSynth, emits OGGs into `client/public/music/`.
- `2009scape-web/client-patch/osrs/sound/MusicPlayer.ts` — new file: per-region track lookup + crossfade controller.
- `2009scape-web/client-patch/osrs/Game.ts` — call `MusicPlayer.tick(playerRegion)` once per render frame.
- `2009scape-web/client-patch/osrs/util/Preferences.ts` — add `musicMuted: boolean` (likely already added by Tier 5d audio plan; if so, just reuse it).
- `2009scape-web/client-patch/osrs/PacketHandler530.ts` — opcode for "set current music track" if the server emits one (search rt4 `Protocol.java` for `CURRENT_MUSIC` or similar; some 530 servers don't push this — region-driven music works fine without it).
- `docs/web-client-plan.md` — add Tier 10 checklist + tick when shipped.

## Out of scope (do NOT touch)

- The runtime soft-synth path (Tier 10b).
- iOS music — separate (`SoundManager.swift` is in the iOS avoid list).
- SFX (Tier 5d).
- Music volume slider / settings UI.

## Reference

| What | Source | Notes |
|---|---|---|
| Music idx in 530 | `Js5MasterIndex.java` ports tend to map idx6 → music. **Verify against your cache.** | `Js5DatIndex` capacity check should give you a count of ~150-200 tracks. |
| Region → track mapping | `reference/rt4-client/client/src/main/java/rt4/Region.java` (search `musicId`) | Each 8x8 region carries a `musicId`. Look it up in `Js5IndexMeta` for a name string ("harmony", "deserts", etc.). |
| FluidSynth | `apt install fluidsynth` (Linux) or `brew install fluid-synth` (macOS) | Plus a GM soundfont — `FluidR3_GM.sf2` is 140 MB but a curated 5 MB subset (`TimGM6mb.sf2`) is fine for MVP. |

## Implementation

### 1. `convert-music.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# Extract the music idx from the 530 cache, convert each MIDI to OGG, drop
# the OGGs into client/public/music/. Run once whenever the cache changes.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${ROOT}/2009scape/Server/data/cache"
OUT="${ROOT}/client/public/music"
SOUNDFONT="${ROOT}/scripts/TimGM6mb.sf2"
MUSIC_IDX=6   # verify

mkdir -p "$OUT"

# 1) Extract MIDI bytes — easiest path is to call into a tiny TS extractor
#    via node:
node "${ROOT}/scripts/extract-music.js" \
     --cache "$CACHE" --idx "$MUSIC_IDX" --out "${OUT}/midi"

# 2) FluidSynth render
for midi in "${OUT}/midi/"*.mid; do
    base="$(basename "$midi" .mid)"
    fluidsynth -F "${OUT}/${base}.wav" "$SOUNDFONT" "$midi"
    ffmpeg -y -i "${OUT}/${base}.wav" -c:a libvorbis -q:a 4 "${OUT}/${base}.ogg"
    rm "${OUT}/${base}.wav"
done

# 3) Emit a manifest the runtime can read
node "${ROOT}/scripts/build-music-manifest.js" --in "$OUT" --out "${OUT}/manifest.json"
```

`extract-music.js` is a 30-line script that uses the existing `Js5DatIndex` from the patch tree to walk the music idx and dump each group's bytes to `${OUT}/midi/${groupId}.mid`. Reuse `Js5Cache.ts` rather than reimplementing.

`build-music-manifest.js` produces `manifest.json` of shape:

```json
{
  "tracks": {
    "1": {"file": "1.ogg", "name": "harmony"},
    "2": {"file": "2.ogg", "name": "deserts"}
  }
}
```

### 2. `MusicPlayer.ts`

```ts
interface MusicTrack {
    file: string;
    name: string;
    buffer: AudioBuffer | null;
}

export class MusicPlayer {
    private static manifest: Record<number, MusicTrack> = {};
    private static currentSource: AudioBufferSourceNode | null = null;
    private static currentGain: GainNode | null = null;
    private static currentTrackId: number = -1;
    private static targetTrackId: number = -1;
    private static crossfadeUntil: number = 0;
    private static crossfadeDurationMs = 1500;

    static async load(): Promise<void> {
        const r = await fetch('/music/manifest.json');
        if (!r.ok) return;
        const json = await r.json();
        for (const [idStr, t] of Object.entries(json.tracks)) {
            this.manifest[Number(idStr)] = { ...(t as any), buffer: null };
        }
    }

    /** Per-tick: ensure the currently-playing track matches `regionTrackId`. */
    static tick(regionTrackId: number, isMuted: boolean) {
        if (isMuted) {
            this.fadeOutAndStop();
            return;
        }
        if (regionTrackId === this.currentTrackId) return;   // already playing
        if (regionTrackId === this.targetTrackId) return;    // already crossfading to it
        this.crossfadeTo(regionTrackId);
    }

    private static async crossfadeTo(trackId: number) {
        const ctx = AudioContextHolder.get();
        if (!ctx) return;
        const track = this.manifest[trackId];
        if (!track) return;

        // Lazy-load the buffer
        if (!track.buffer) {
            const r = await fetch(`/music/${track.file}`);
            const ab = await r.arrayBuffer();
            try { track.buffer = await ctx.decodeAudioData(ab); }
            catch { return; }
        }

        // Fade out current, then start new at gain 0 ramping to 1
        const now = ctx.currentTime;
        if (this.currentGain) {
            this.currentGain.gain.linearRampToValueAtTime(0, now + this.crossfadeDurationMs / 1000);
        }
        const oldSource = this.currentSource;
        if (oldSource) {
            setTimeout(() => { try { oldSource.stop(); } catch {} }, this.crossfadeDurationMs);
        }

        const gain = ctx.createGain();
        gain.gain.setValueAtTime(0, now);
        gain.gain.linearRampToValueAtTime(1, now + this.crossfadeDurationMs / 1000);
        gain.connect(ctx.destination);

        const src = ctx.createBufferSource();
        src.buffer = track.buffer;
        src.loop = true;
        src.connect(gain);
        src.start();

        this.currentSource = src;
        this.currentGain = gain;
        this.currentTrackId = trackId;
        this.targetTrackId = trackId;
    }

    private static fadeOutAndStop() {
        const ctx = AudioContextHolder.get();
        if (!ctx || !this.currentGain || !this.currentSource) return;
        const now = ctx.currentTime;
        this.currentGain.gain.linearRampToValueAtTime(0, now + 0.5);
        const old = this.currentSource;
        setTimeout(() => { try { old.stop(); } catch {} }, 600);
        this.currentSource = null;
        this.currentGain = null;
        this.currentTrackId = -1;
        this.targetTrackId = -1;
    }
}
```

### 3. Per-frame wire-up in `Game.ts`

```ts
// Boot:
MusicPlayer.load();

// Per render frame:
const region = Region.fromChunkXZ(player.chunkX, player.chunkY);
const trackId = region?.musicId ?? -1;
MusicPlayer.tick(trackId, Preferences.musicMuted);
```

`Region.musicId` lookup comes from the existing region map; if the region class doesn't carry it yet, walk the area-defs idx (15 or 17 in 530) to fetch it, or hard-code the major-region → track map for v1 from rt4 `Js5GlTextureProvider.java` (it has the same idx wire-up pattern).

### 4. Bundle config

`client/package.json` should run `convert-music.sh` as a `prebuild` step so Vite/Parcel sees the OGGs and copies them into `dist/`. Don't bake the conversion into hot reload — it's slow and only needs to run when the cache changes.

## Self-test

```bash
# One-time: generate OGGs (≈5 minutes, depending on machine)
cd 2009scape-web
./scripts/convert-music.sh

# Then standard build + serve:
cp -R client-patch/osrs/. client/osrs/
./scripts/set-client-server.sh 10.8.0.1
cd client && rm -rf dist .cache && npm run build
nohup npx serve dist -l tcp://127.0.0.1:8600 > /tmp/serve-2009.log 2>&1 & disown
```

Open the page in a browser. Music should kick in within 2 seconds of the world loading. Walk to a different region — the track should crossfade. Set `Preferences.musicMuted = true` in the console — current track should fade out.

## Acceptance criteria

1. `convert-music.sh` produces ≥30 OGG files (roughly the count of 530 music tracks).
2. The browser plays a track when the world loads.
3. Walking into a different musical region triggers a crossfade within 1.5 s.
4. `Preferences.musicMuted = true` fades the current track to silence within 600 ms.
5. Bundle size delta ≤ 35 MB (OGGs + manifest).
6. Build green.
7. Update `docs/web-client-plan.md` Tier 10 checklist with commit SHA inline.

## Out of scope clarifications

- **Don't ship a soft-synth.** Tier 10b.
- **Don't add a music volume slider** — `Preferences.musicMuted` boolean is enough for v1.
- **Don't persist last-played track** — region tells us what to play; persistence is a future setting.
- **Don't add fade-in on app launch** — the crossfade handles it (current track is null, target track ramps from 0).

## Commit guidance

Two commits:

1. `2009scape-web: tier10 — music conversion pipeline`
2. `2009scape-web: tier10 — MusicPlayer crossfade + per-frame driver`

Push nothing.
