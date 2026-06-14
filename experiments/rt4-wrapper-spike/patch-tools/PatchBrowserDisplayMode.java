import javassist.ClassPool;
import javassist.CtClass;
import javassist.CtMethod;

public final class PatchBrowserDisplayMode {
    private PatchBrowserDisplayMode() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            throw new IllegalArgumentException("usage: PatchBrowserDisplayMode <client-jar> <output-dir>");
        }

        ClassPool pool = new ClassPool(true);
        pool.insertClassPath(args[0]);
        CtClass displayMode = pool.get("rt4.DisplayMode");

        for (CtMethod method : displayMode.getDeclaredMethods("setWindowMode")) {
            CtClass[] params = method.getParameterTypes();
            if (params.length == 4) {
                method.insertBefore(browserSetWindowModeBody("$2", "-1", "$3", "$4"));
            } else if (params.length == 6) {
                method.insertBefore(browserSetWindowModeBody("$2", "$4", "$5", "$6"));
            }
        }

        CtMethod getWindowMode = displayMode.getDeclaredMethod("getWindowMode");
        getWindowMode.insertBefore(
            "if (rt4.GameShell.isBrowserWrapper()) {\n" +
            "  int mode = rt4.Preferences.windowMode;\n" +
            "  if (mode < 0) { mode = 0; }\n" +
            "  if (mode > 3) { mode = 2; }\n" +
            "  if (mode == 3) { return 2; }\n" +
            "  return mode;\n" +
            "}\n"
        );

        displayMode.writeFile(args[1]);
    }

    private static String browserSetWindowModeBody(String modeExpr, String aaExpr, String widthExpr, String heightExpr) {
        return
            "if (rt4.GameShell.isBrowserWrapper()) {\n" +
            "  aLong89 = 0L;\n" +
            "  int requestedMode = " + modeExpr + ";\n" +
            "  if (requestedMode < 0) { requestedMode = 0; }\n" +
            "  if (requestedMode > 3) { requestedMode = 2; }\n" +
            "  if (requestedMode == 3) { requestedMode = 2; }\n" +
            "  int aa = " + aaExpr + ";\n" +
            "  if (aa >= 0) { rt4.Preferences.antiAliasingMode = aa; }\n" +
            "  rt4.Preferences.windowMode = requestedMode;\n" +
            "  rt4.Preferences.favoriteWorlds = 0;\n" +
            "  resizable = requestedMode == 2;\n" +
            "  resizableSD = rt4.GameShell.isBrowserResizable() || requestedMode == 2;\n" +
            "  if (rt4.GlRenderer.enabled) { rt4.GlRenderer.quit(); }\n" +
            "  start_GLRenderer = false;\n" +
            "  rt4.GameShell.fullScreenFrame = null;\n" +
            "  int browserWidth = rt4.GameShell.getBrowserViewportWidth();\n" +
            "  int browserHeight = rt4.GameShell.getBrowserViewportHeight();\n" +
            "  if (browserWidth <= 0) { browserWidth = 765; }\n" +
            "  if (browserHeight <= 0) { browserHeight = 503; }\n" +
            "  rt4.GameShell.frameWidth = browserWidth;\n" +
            "  rt4.GameShell.frameHeight = browserHeight;\n" +
            "  if (resizableSD) {\n" +
            "    rt4.GameShell.canvasWidth = browserWidth;\n" +
            "    rt4.GameShell.canvasHeight = browserHeight;\n" +
            "    rt4.GameShell.leftMargin = 0;\n" +
            "    rt4.GameShell.topMargin = 0;\n" +
            "  } else {\n" +
            "    rt4.GameShell.canvasWidth = 765;\n" +
            "    rt4.GameShell.canvasHeight = 503;\n" +
            "    rt4.GameShell.leftMargin = (browserWidth - 765) / 2;\n" +
            "    rt4.GameShell.topMargin = 0;\n" +
            "  }\n" +
            "  if (rt4.GameShell.canvas != null) {\n" +
            "    rt4.GameShell.canvas.setSize(rt4.GameShell.canvasWidth, rt4.GameShell.canvasHeight);\n" +
            "    rt4.GameShell.canvas.setLocation(rt4.GameShell.leftMargin, rt4.GameShell.topMargin);\n" +
            "  }\n" +
            "  rt4.GameShell.recreateBrowserFrameBuffer();\n" +
            "  rt4.Preferences.write(rt4.GameShell.signLink);\n" +
            "  if (rt4.InterfaceList.topLevelInterface != -1) { rt4.InterfaceList.method3712(true); }\n" +
            "  if (rt4.Protocol.socket != null && (rt4.client.gameState == 30 || rt4.client.gameState == 25)) { rt4.ClientProt.sendWindowDetails(); }\n" +
            "  for (int i = 0; i < 100; i++) { rt4.InterfaceList.aBooleanArray100[i] = true; }\n" +
            "  rt4.GameShell.fullRedraw = true;\n" +
            "  plugin.PluginRepository.reloadPlugins();\n" +
            "  if (rt4.GameShell.isBrowserDebug()) { System.out.println(\"[DisplayMode] Accepted browser display mode \" + requestedMode + \" using software framebuffer.\"); }\n" +
            "  return;\n" +
            "}\n";
    }
}
