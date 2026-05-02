import { Js5Cache } from "../Js5Cache";
import { AudioContextHolder } from "./AudioContextHolder";

export class SoundBank {
    private static cache: Map<number, AudioBuffer> = new Map<number, AudioBuffer>();
    private static missing: Set<number> = new Set<number>();
    private static js5: Js5Cache | null = null;

    static attach(js5: Js5Cache) {
        this.js5 = js5;
    }

    static async getBuffer(trackId: number): Promise<AudioBuffer | null> {
        if (this.cache.has(trackId)) return this.cache.get(trackId)!;
        if (this.missing.has(trackId) || !this.js5) return null;

        const raw = await this.js5.getGroupBytes(14, trackId);
        const ctx = AudioContextHolder.get();
        if (!raw || !ctx) {
            this.missing.add(trackId);
            return null;
        }

        try {
            const ab = raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength) as ArrayBuffer;
            const decoded = await ctx.decodeAudioData(ab);
            this.cache.set(trackId, decoded);
            return decoded;
        } catch (e) {
            const fallback = this.decodeUnsignedPcm(ctx, raw);
            if (fallback) {
                this.cache.set(trackId, fallback);
                return fallback;
            }
            this.missing.add(trackId);
            return null;
        }
    }

    private static decodeUnsignedPcm(ctx: AudioContext, raw: Uint8Array): AudioBuffer | null {
        if (!raw || raw.byteLength === 0) return null;
        const sampleRate = 22050;
        const buffer = ctx.createBuffer(1, raw.byteLength, sampleRate);
        const channel = buffer.getChannelData(0);
        for (let i = 0; i < raw.byteLength; i++) {
            channel[i] = ((raw[i] & 0xFF) - 128) / 128;
        }
        return buffer;
    }
}
