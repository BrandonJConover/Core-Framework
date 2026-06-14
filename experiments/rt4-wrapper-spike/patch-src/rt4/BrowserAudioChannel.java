package rt4;

import java.awt.Component;

public final class BrowserAudioChannel extends AudioChannel {
    private final int channel;
    private int capacity;

    public BrowserAudioChannel(int channel) {
        this.channel = channel;
        this.capacity = 4096;
    }

    public void init(Component component) throws Exception {
        if (!BrowserAudioNative.init(AudioChannel.sampleRate, AudioChannel.stereo)) {
            throw new IllegalStateException("Browser audio native bridge is unavailable");
        }
    }

    public void open(int capacity) {
        this.capacity = Math.max(1024, Math.min(16384, capacity));
    }

    protected int getBufferSize() {
        int queued = BrowserAudioNative.getQueuedFrames(this.channel);
        if (queued < 0) {
            return 0;
        }
        return Math.min(this.capacity, queued);
    }

    protected void write() {
        BrowserAudioNative.write(this.channel, this.samples, AudioChannel.stereo ? 512 : 256);
    }

    protected void close() {
        BrowserAudioNative.close(this.channel);
    }

    protected void flush() {
        BrowserAudioNative.close(this.channel);
    }
}
