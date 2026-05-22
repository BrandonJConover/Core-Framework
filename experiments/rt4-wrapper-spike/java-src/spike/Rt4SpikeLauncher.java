package spike;

import rt4.client;

public final class Rt4SpikeLauncher {
    private Rt4SpikeLauncher() {
    }

    public static void main(String[] args) {
        System.out.println("[Rt4SpikeLauncher] starting");
        System.out.println("[Rt4SpikeLauncher] args=" + String.join(" ", args));
        Thread.setDefaultUncaughtExceptionHandler((thread, throwable) -> {
            System.err.println("[Rt4SpikeLauncher] uncaught in " + thread.getName() + ": " + throwable.getClass().getName() + ": " + throwable.getMessage());
            throwable.printStackTrace(System.err);
        });
        System.setProperty("rt4.browser.websocket", "true");
        System.setProperty("rt4.browser.websocket.singleByteWrites", "false");
        System.setSecurityManager(new SecurityManager() {
            @Override
            public void checkPermission(java.security.Permission permission) {
            }

            @Override
            public void checkExit(int status) {
                throw new ExitTrappedException(status);
            }
        });

        try {
            client.main(args);
            System.out.println("[Rt4SpikeLauncher] rt4.client.main returned");
        } catch (ExitTrappedException e) {
            System.err.println("[Rt4SpikeLauncher] intercepted System.exit(" + e.status + ")");
            e.printStackTrace(System.err);
            throw new RuntimeException(e);
        } catch (Throwable t) {
            System.err.println("[Rt4SpikeLauncher] uncaught " + t.getClass().getName() + ": " + t.getMessage());
            t.printStackTrace(System.err);
            throw new RuntimeException(t);
        } finally {
            System.setSecurityManager(null);
        }
    }

    private static final class ExitTrappedException extends SecurityException {
        private final int status;

        private ExitTrappedException(int status) {
            super("System.exit(" + status + ")");
            this.status = status;
        }
    }
}
