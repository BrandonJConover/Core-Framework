export class AudioContextHolder {
    private static ctx: AudioContext | null = null;
    private static unlocked: boolean = false;

    static get(): AudioContext | null {
        const ctor = (globalThis as any).AudioContext || (globalThis as any).webkitAudioContext;
        if (!this.ctx && ctor) {
            this.ctx = new ctor();
        }
        return this.ctx;
    }

    static unlock(): void {
        const ctx = this.get();
        if (!ctx || this.unlocked) return;
        if (ctx.resume) ctx.resume().catch(() => {});
        this.unlocked = true;
    }
}
