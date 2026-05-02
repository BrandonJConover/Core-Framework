import { Preferences } from "../util/Preferences";
import { AudioContextHolder } from "./AudioContextHolder";

interface MusicManifestTrack {
    file: string;
    name?: string;
}

interface MusicTrack extends MusicManifestTrack {
    buffer: AudioBuffer | null;
}

export class MusicPlayer {
    private static manifest: Map<number, MusicTrack> = new Map<number, MusicTrack>();
    private static manifestLoaded: boolean = false;
    private static manifestLoading: boolean = false;
    private static manifestMissing: boolean = false;

    private static currentSource: AudioBufferSourceNode | null = null;
    private static currentGain: GainNode | null = null;
    private static currentTrackId: number = -1;
    private static targetTrackId: number = -1;
    private static lastJingleAtMs: number = 0;
    private static readonly crossfadeSeconds = 1.5;

    static load(): void {
        if (this.manifestLoaded || this.manifestLoading || this.manifestMissing) return;
        this.manifestLoading = true;
        fetch("music/manifest.json")
            .then((r) => r.ok ? r.json() : null)
            .then((json) => {
                if (!json || !json.tracks) {
                    this.manifestMissing = true;
                    return;
                }
                for (const idStr of Object.keys(json.tracks)) {
                    const id = Number(idStr);
                    const track = json.tracks[idStr] as MusicManifestTrack;
                    if (!Number.isFinite(id) || !track || !track.file) continue;
                    this.manifest.set(id, { file: track.file, name: track.name, buffer: null });
                }
                this.manifestLoaded = true;
                if (this.manifest.size > 0) {
                    console.log("[Music] Loaded manifest with " + this.manifest.size + " track(s)");
                }
            })
            .catch(() => {
                this.manifestMissing = true;
            })
            .finally(() => {
                this.manifestLoading = false;
            });
    }

    static tick(): void {
        this.load();
        if (Preferences.musicMuted) {
            this.fadeOutAndStop(0.5);
        }
    }

    static playSong(trackId: number): void {
        this.load();
        if (trackId === 65535) trackId = -1;
        if (trackId < 0 || Preferences.musicMuted) {
            this.fadeOutAndStop(0.5);
            return;
        }
        if (trackId === this.currentTrackId || trackId === this.targetTrackId) return;
        this.crossfadeTo(trackId);
    }

    static playJingle(trackId: number, volume: number): void {
        this.load();
        if (trackId === 65535 || trackId < 0 || Preferences.musicMuted) return;
        // Some servers spam jingles during interface churn. Keep one-shot
        // playback from stacking aggressively over itself.
        const nowMs = Date.now();
        if (nowMs - this.lastJingleAtMs < 250) return;
        this.lastJingleAtMs = nowMs;
        this.playOneShot(trackId, Math.max(0, Math.min(1, volume / 255.0)));
    }

    private static async crossfadeTo(trackId: number): Promise<void> {
        this.targetTrackId = trackId;
        const ctx = AudioContextHolder.get();
        if (!ctx) return;
        const track = await this.getTrack(trackId);
        if (!track || !track.buffer || this.targetTrackId !== trackId) return;

        const now = ctx.currentTime;
        const oldSource = this.currentSource;
        if (this.currentGain) {
            try {
                this.currentGain.gain.cancelScheduledValues(now);
                this.currentGain.gain.setValueAtTime(this.currentGain.gain.value, now);
                this.currentGain.gain.linearRampToValueAtTime(0, now + this.crossfadeSeconds);
            } catch (_) {}
        }
        if (oldSource) {
            setTimeout(() => { try { oldSource.stop(); } catch (_) {} }, this.crossfadeSeconds * 1000 + 50);
        }

        const gain = ctx.createGain();
        gain.gain.setValueAtTime(0, now);
        gain.gain.linearRampToValueAtTime(1, now + this.crossfadeSeconds);
        gain.connect(ctx.destination);

        const source = ctx.createBufferSource();
        source.buffer = track.buffer;
        source.loop = true;
        source.connect(gain);
        source.start();

        this.currentSource = source;
        this.currentGain = gain;
        this.currentTrackId = trackId;
        this.targetTrackId = trackId;
    }

    private static async playOneShot(trackId: number, volume: number): Promise<void> {
        const ctx = AudioContextHolder.get();
        if (!ctx) return;
        const track = await this.getTrack(trackId);
        if (!track || !track.buffer) return;

        const gain = ctx.createGain();
        gain.gain.value = volume;
        gain.connect(ctx.destination);

        const source = ctx.createBufferSource();
        source.buffer = track.buffer;
        source.connect(gain);
        source.start();
        source.onended = () => {
            try { gain.disconnect(); } catch (_) {}
        };
    }

    private static async getTrack(trackId: number): Promise<MusicTrack | null> {
        const track = this.manifest.get(trackId);
        if (!track) return null;
        if (track.buffer) return track;

        const ctx = AudioContextHolder.get();
        if (!ctx) return null;
        try {
            const response = await fetch("music/" + encodeURIComponent(track.file));
            if (!response.ok) return null;
            const bytes = await response.arrayBuffer();
            track.buffer = await ctx.decodeAudioData(bytes);
            return track;
        } catch (_) {
            return null;
        }
    }

    private static fadeOutAndStop(seconds: number): void {
        const ctx = AudioContextHolder.get();
        if (!ctx || !this.currentGain || !this.currentSource) return;
        const source = this.currentSource;
        const gain = this.currentGain;
        const now = ctx.currentTime;
        try {
            gain.gain.cancelScheduledValues(now);
            gain.gain.setValueAtTime(gain.gain.value, now);
            gain.gain.linearRampToValueAtTime(0, now + seconds);
        } catch (_) {}
        setTimeout(() => {
            try { source.stop(); } catch (_) {}
            try { gain.disconnect(); } catch (_) {}
        }, seconds * 1000 + 50);
        this.currentSource = null;
        this.currentGain = null;
        this.currentTrackId = -1;
        this.targetTrackId = -1;
    }
}
