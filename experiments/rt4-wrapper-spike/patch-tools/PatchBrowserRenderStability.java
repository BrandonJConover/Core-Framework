import javassist.ClassPool;
import javassist.CtClass;
import javassist.CtMethod;

public final class PatchBrowserRenderStability {
    private PatchBrowserRenderStability() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            throw new IllegalArgumentException("usage: PatchBrowserRenderStability <client-jar> <output-dir>");
        }

        ClassPool pool = new ClassPool(true);
        pool.insertClassPath(args[0]);

        CtClass displayMode = pool.get("rt4.DisplayMode");
        for (CtMethod method : displayMode.getDeclaredMethods("setWindowMode")) {
            CtClass[] params = method.getParameterTypes();
            if (params.length == 4) {
                method.insertBefore(browserModeNormalize4());
            } else if (params.length == 6) {
                method.insertBefore(browserModeNormalize6());
            }
        }
        CtMethod getDisplayModes = displayMode.getDeclaredMethod("getDisplayModes");
        getDisplayModes.insertBefore(browserDisplayModes());
        displayMode.writeFile(args[1]);

        CtClass gameShell = pool.get("rt4.GameShell");
        CtMethod blackFillMargins = gameShell.getDeclaredMethod("method2704");
        blackFillMargins.insertBefore(
            "if (rt4.GameShell.isBrowserWrapper()) {\n" +
            "  return;\n" +
            "}\n"
        );
        gameShell.writeFile(args[1]);

        CtClass preferences = pool.get("rt4.Preferences");
        CtMethod read = preferences.getDeclaredMethod("read");
        read.insertAfter(
            "if (rt4.GameShell.isBrowserWrapper()) {\n" +
            "  if (rt4.Preferences.windowMode > 0) { rt4.Preferences.windowMode = 2; }\n" +
            "  rt4.Preferences.antiAliasingMode = 0;\n" +
            "  rt4.Preferences.highDetailLighting = false;\n" +
            "  rt4.Preferences.highDetailTextures = false;\n" +
            "  rt4.Preferences.hdr = false;\n" +
            "}\n"
        );
        CtMethod decode = preferences.getDeclaredMethod("decode");
        decode.insertAfter(
            "if (rt4.GameShell.isBrowserWrapper()) {\n" +
            "  if (rt4.Preferences.windowMode > 0) { rt4.Preferences.windowMode = 2; }\n" +
            "  rt4.Preferences.antiAliasingMode = 0;\n" +
            "  rt4.Preferences.highDetailLighting = false;\n" +
            "  rt4.Preferences.highDetailTextures = false;\n" +
            "  rt4.Preferences.hdr = false;\n" +
            "}\n"
        );
        preferences.writeFile(args[1]);
    }

    private static String browserModeNormalize4() {
        return
            "if (rt4.GameShell.isBrowserWrapper()) {\n" +
            "  if ($2 > 0) { $2 = 2; }\n" +
            "  $1 = false;\n" +
            "  rt4.DisplayMode.start_GLRenderer = false;\n" +
            "  rt4.Preferences.highDetailLighting = false;\n" +
            "  rt4.Preferences.highDetailTextures = false;\n" +
            "  rt4.Preferences.hdr = false;\n" +
            "  if (rt4.GlRenderer.enabled) { rt4.GlRenderer.quit(); }\n" +
            "}\n";
    }

    private static String browserModeNormalize6() {
        return
            "if (rt4.GameShell.isBrowserWrapper()) {\n" +
            "  if ($2 > 0) { $2 = 2; }\n" +
            "  $1 = false;\n" +
            "  $3 = false;\n" +
            "  rt4.DisplayMode.start_GLRenderer = false;\n" +
            "  rt4.Preferences.highDetailLighting = false;\n" +
            "  rt4.Preferences.highDetailTextures = false;\n" +
            "  rt4.Preferences.hdr = false;\n" +
            "  if (rt4.GlRenderer.enabled) { rt4.GlRenderer.quit(); }\n" +
            "}\n";
    }

    private static String browserDisplayModes() {
        return
            "if (rt4.GameShell.isBrowserWrapper()) {\n" +
            "  int width = rt4.GameShell.getBrowserViewportWidth();\n" +
            "  int height = rt4.GameShell.getBrowserViewportHeight();\n" +
            "  if (width <= 0) { width = 765; }\n" +
            "  if (height <= 0) { height = 503; }\n" +
            "  rt4.DisplayMode fixed = new rt4.DisplayMode();\n" +
            "  fixed.width = 765;\n" +
            "  fixed.height = 503;\n" +
            "  fixed.bitDepth = 32;\n" +
            "  fixed.refreshRate = 60;\n" +
            "  rt4.DisplayMode browser = new rt4.DisplayMode();\n" +
            "  browser.width = width;\n" +
            "  browser.height = height;\n" +
            "  browser.bitDepth = 32;\n" +
            "  browser.refreshRate = 60;\n" +
            "  return new rt4.DisplayMode[] { fixed, browser };\n" +
            "}\n";
    }
}
