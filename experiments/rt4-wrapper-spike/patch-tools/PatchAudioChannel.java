import javassist.ClassPool;
import javassist.CtClass;
import javassist.CtMethod;

public final class PatchAudioChannel {
    private PatchAudioChannel() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            throw new IllegalArgumentException("usage: PatchAudioChannel <client-jar> <output-dir>");
        }

        ClassPool pool = new ClassPool(true);
        pool.insertClassPath(args[0]);
        CtClass audioChannel = pool.get("rt4.AudioChannel");
        CtMethod create = audioChannel.getDeclaredMethod("create");
        create.setBody(
            "{\n" +
            "  if (sampleRate == 0) { throw new IllegalStateException(); }\n" +
            "  if (Boolean.getBoolean(\"rt4.browser.websocket\")) {\n" +
            "    try {\n" +
            "      rt4.BrowserAudioChannel channel = new rt4.BrowserAudioChannel($4);\n" +
            "      channel.sampleRate2 = 1024;\n" +
            "      channel.samples = new int[(stereo ? 2 : 1) * 256];\n" +
            "      channel.init($3);\n" +
            "      channel.bufferCapacity = 4096;\n" +
            "      channel.open(channel.bufferCapacity);\n" +
            "      if (threadPriority > 0 && thread == null) {\n" +
            "        thread = new rt4.AudioThread();\n" +
            "        thread.signLink = $2;\n" +
            "        $2.startThread(threadPriority, thread);\n" +
            "      }\n" +
            "      if (thread != null) {\n" +
            "        if (thread.channels[$4] != null) { throw new IllegalArgumentException(); }\n" +
            "        thread.channels[$4] = channel;\n" +
            "      }\n" +
            "      return channel;\n" +
            "    } catch (Throwable t) {\n" +
            "      t.printStackTrace();\n" +
            "      return new rt4.AudioChannel();\n" +
            "    }\n" +
            "  }\n" +
            "  try {\n" +
            "    rt4.JavaAudioChannel channel = new rt4.JavaAudioChannel();\n" +
            "    channel.sampleRate2 = $1;\n" +
            "    channel.samples = new int[(stereo ? 2 : 1) * 256];\n" +
            "    channel.init($3);\n" +
            "    channel.bufferCapacity = ($1 & -1024) + 1024;\n" +
            "    if (channel.bufferCapacity > 16384) { channel.bufferCapacity = 16384; }\n" +
            "    channel.open(channel.bufferCapacity);\n" +
            "    if (threadPriority > 0 && thread == null) {\n" +
            "      thread = new rt4.AudioThread();\n" +
            "      thread.signLink = $2;\n" +
            "      $2.startThread(threadPriority, thread);\n" +
            "    }\n" +
            "    if (thread != null) {\n" +
            "      if (thread.channels[$4] != null) { throw new IllegalArgumentException(); }\n" +
            "      thread.channels[$4] = channel;\n" +
            "    }\n" +
            "    return channel;\n" +
            "  } catch (Throwable t) {\n" +
            "    t.printStackTrace();\n" +
            "    try {\n" +
            "      rt4.SignLinkAudioChannel channel = new rt4.SignLinkAudioChannel($2, $4);\n" +
            "      channel.samples = new int[(stereo ? 2 : 1) * 256];\n" +
            "      channel.sampleRate2 = $1;\n" +
            "      channel.init($3);\n" +
            "      channel.bufferCapacity = 16384;\n" +
            "      channel.open(channel.bufferCapacity);\n" +
            "      if (threadPriority > 0 && thread == null) {\n" +
            "        thread = new rt4.AudioThread();\n" +
            "        thread.signLink = $2;\n" +
            "        $2.startThread(threadPriority, thread);\n" +
            "      }\n" +
            "      if (thread != null) {\n" +
            "        if (thread.channels[$4] != null) { throw new IllegalArgumentException(); }\n" +
            "        thread.channels[$4] = channel;\n" +
            "      }\n" +
            "      return channel;\n" +
            "    } catch (Throwable fallback) {\n" +
            "      fallback.printStackTrace();\n" +
            "      return new rt4.AudioChannel();\n" +
            "    }\n" +
            "  }\n" +
            "}\n"
        );
        audioChannel.writeFile(args[1]);
    }
}
