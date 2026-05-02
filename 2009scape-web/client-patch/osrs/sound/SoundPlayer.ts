import { Preferences } from "../util/Preferences";
import { AudioContextHolder } from "./AudioContextHolder";
import { SoundBank } from "./SoundBank";

interface ActiveSound {
    trackId: number;
    loopsRemaining: number;
    delayUntil: number;
    chunkX: number;
    chunkZ: number;
    range: number;
    volume: number;
    source: AudioBufferSourceNode | null;
    gain: GainNode | null;
    loading: boolean;
}

export class SoundPlayer {
    public static volume: number = 0;
    private static queue: ActiveSound[] = [];
    private static maxConcurrent: number = 50;

    public static setVolume(level: number) {
        SoundPlayer.volume = level;
    }

    public static getVolume(): number {
        return SoundPlayer.volume;
    }

    public static play(volume: number, trackId: number, delayTicks: number) {
        if (Preferences.muteSfx || trackId < 0 || volume <= 0) return;
        if (this.queue.length >= this.maxConcurrent) return;
        this.queue.push({
            trackId,
            loopsRemaining: 0,
            delayUntil: this.now() + delayTicks * 20,
            chunkX: -1,
            chunkZ: -1,
            range: 0,
            volume,
            source: null,
            gain: null,
            loading: false
        });
    }

    public static playArea(trackId: number, chunkX: number, chunkZ: number, range: number, loops: number, delayTicks: number) {
        if (Preferences.muteSfx || Preferences.ambientSoundsVolume === 0 || trackId < 0 || loops <= 0) return;
        if (this.queue.length >= this.maxConcurrent) return;
        this.queue.push({
            trackId,
            loopsRemaining: loops,
            delayUntil: this.now() + delayTicks * 20,
            chunkX,
            chunkZ,
            range,
            volume: Preferences.ambientSoundsVolume,
            source: null,
            gain: null,
            loading: false
        });
    }

    public static tick(playerChunkX: number, playerChunkZ: number) {
        const ctx = AudioContextHolder.get();
        if (!ctx || Preferences.muteSfx) return;
        const now = this.now();
        for (let i = this.queue.length - 1; i >= 0; i--) {
            const s = this.queue[i];
            if (s.chunkX >= 0) {
                const r = s.range + 1;
                if (Math.abs(s.chunkX - playerChunkX) > r || Math.abs(s.chunkZ - playerChunkZ) > r) {
                    this.stopSound(s);
                    this.queue.splice(i, 1);
                    continue;
                }
            }
            if (now < s.delayUntil || s.source || s.loading) continue;
            s.loading = true;
            SoundBank.getBuffer(s.trackId).then(buf => {
                s.loading = false;
                if (!buf || this.queue.indexOf(s) < 0) return;
                const node = ctx.createBufferSource();
                const gain = ctx.createGain();
                node.buffer = buf;
                node.loop = s.loopsRemaining > 0;
                gain.gain.value = this.volumeScale(s.volume);
                node.connect(gain);
                gain.connect(ctx.destination);
                node.onended = () => {
                    const idx = this.queue.indexOf(s);
                    if (idx >= 0) this.queue.splice(idx, 1);
                };
                s.source = node;
                s.gain = gain;
                node.start();
            }).catch(() => {
                s.loading = false;
                const idx = this.queue.indexOf(s);
                if (idx >= 0) this.queue.splice(idx, 1);
            });
        }
    }

    public constructor(stream: any, level: number, delay: number) {
        // Compatibility shim for old translated Java call sites.
    }

    public run() {}

    public getDecibels(level: number): number {
        switch ((level)) {
        case 1: return -80.0;
        case 2: return -70.0;
        case 3: return -60.0;
        case 4: return -50.0;
        case 5: return -40.0;
        case 6: return -30.0;
        case 7: return -20.0;
        case 8: return -10.0;
        case 9: return -0.0;
        case 10: return 6.0;
        default: return 0.0;
        }
    }

    private static stopSound(s: ActiveSound) {
        if (s.source) {
            try { s.source.stop(); } catch (e) {}
            s.source = null;
        }
        if (s.gain) {
            try { s.gain.disconnect(); } catch (e) {}
            s.gain = null;
        }
    }

    private static volumeScale(volume: number): number {
        const clientScale = Math.max(0, 4 - SoundPlayer.volume) / 4;
        return Math.max(0, Math.min(1, (volume / 255) * clientScale));
    }

    private static now(): number {
        return typeof performance !== "undefined" && performance.now ? performance.now() : Date.now();
    }
}
