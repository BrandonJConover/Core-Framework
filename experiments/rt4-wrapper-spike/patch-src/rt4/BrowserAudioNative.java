package rt4;

public final class BrowserAudioNative {
    private BrowserAudioNative() {
    }

    public static native boolean init(int sampleRate, boolean stereo);

    public static native int getQueuedFrames(int channel);

    public static native void write(int channel, int[] samples, int length);

    public static native void close(int channel);
}
