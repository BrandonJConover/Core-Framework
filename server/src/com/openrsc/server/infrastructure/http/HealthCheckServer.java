package com.openrsc.server.infrastructure.http;

import com.openrsc.server.infrastructure.metrics.GameMetrics;
import io.javalin.Javalin;
import io.javalin.http.Context;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.ThreadMXBean;
import java.time.Duration;
import java.time.Instant;
import java.util.*;
import java.util.function.Supplier;

/**
 * HTTP server for health checks, metrics, and admin endpoints.
 * Uses Javalin for lightweight HTTP serving.
 */
public class HealthCheckServer implements AutoCloseable {
    private static final Logger LOGGER = LogManager.getLogger(HealthCheckServer.class);

    private final Javalin app;
    private final int port;
    private final Instant startTime;
    private final Map<String, Supplier<HealthCheck>> healthChecks;
    private final GameMetrics metrics;
    private final String apiKey;

    private Supplier<Integer> playersOnlineSupplier = () -> 0;
    private Supplier<Integer> npcsActiveSupplier = () -> 0;
    private Supplier<Integer> worldNumberSupplier = () -> 1;
    private Supplier<Boolean> isReadySupplier = () -> true;

    public HealthCheckServer(HealthServerConfig config, GameMetrics metrics) {
        this.port = config.port();
        this.startTime = Instant.now();
        this.healthChecks = new LinkedHashMap<>();
        this.metrics = metrics;
        this.apiKey = config.adminApiKey();

        this.app = Javalin.create(javalinConfig -> {
            javalinConfig.showJavalinBanner = false;
            javalinConfig.http.defaultContentType = "application/json";
        });

        setupRoutes();
    }

    private void setupRoutes() {
        // Health check endpoints
        app.get("/health", this::handleHealth);
        app.get("/health/live", this::handleLiveness);
        app.get("/health/ready", this::handleReadiness);
        app.get("/health/startup", this::handleStartup);

        // Metrics endpoint (Prometheus format)
        app.get("/metrics", this::handleMetrics);

        // Server info endpoint
        app.get("/api/v1/server/info", this::handleServerInfo);
        app.get("/api/v1/server/status", this::handleServerStatus);

        // Admin endpoints (require API key)
        app.before("/api/v1/admin/*", this::validateApiKey);
        app.post("/api/v1/admin/gc", this::handleForceGc);
        app.get("/api/v1/admin/memory", this::handleMemoryStats);
        app.get("/api/v1/admin/threads", this::handleThreadStats);
    }

    /**
     * Starts the HTTP server.
     */
    public void start() {
        app.start(port);
        LOGGER.info("Health check server started on port {}", port);
    }

    /**
     * Registers a health check.
     */
    public void registerHealthCheck(String name, Supplier<HealthCheck> check) {
        healthChecks.put(name, check);
    }

    /**
     * Sets the players online supplier.
     */
    public void setPlayersOnlineSupplier(Supplier<Integer> supplier) {
        this.playersOnlineSupplier = supplier;
    }

    /**
     * Sets the NPCs active supplier.
     */
    public void setNpcsActiveSupplier(Supplier<Integer> supplier) {
        this.npcsActiveSupplier = supplier;
    }

    /**
     * Sets the world number supplier.
     */
    public void setWorldNumberSupplier(Supplier<Integer> supplier) {
        this.worldNumberSupplier = supplier;
    }

    /**
     * Sets the readiness supplier.
     */
    public void setIsReadySupplier(Supplier<Boolean> supplier) {
        this.isReadySupplier = supplier;
    }

    private void handleHealth(Context ctx) {
        Map<String, Object> response = new LinkedHashMap<>();
        boolean allHealthy = true;
        Map<String, Object> checks = new LinkedHashMap<>();

        for (Map.Entry<String, Supplier<HealthCheck>> entry : healthChecks.entrySet()) {
            try {
                HealthCheck check = entry.getValue().get();
                checks.put(entry.getKey(), Map.of(
                    "status", check.healthy() ? "UP" : "DOWN",
                    "details", check.details()
                ));
                if (!check.healthy()) {
                    allHealthy = false;
                }
            } catch (Exception e) {
                checks.put(entry.getKey(), Map.of(
                    "status", "DOWN",
                    "error", e.getMessage()
                ));
                allHealthy = false;
            }
        }

        response.put("status", allHealthy ? "UP" : "DOWN");
        response.put("uptime", Duration.between(startTime, Instant.now()).toString());
        response.put("checks", checks);

        ctx.status(allHealthy ? 200 : 503);
        ctx.json(response);
    }

    private void handleLiveness(Context ctx) {
        ctx.json(Map.of(
            "status", "UP",
            "timestamp", Instant.now().toString()
        ));
    }

    private void handleReadiness(Context ctx) {
        boolean ready = isReadySupplier.get();
        ctx.status(ready ? 200 : 503);
        ctx.json(Map.of(
            "status", ready ? "READY" : "NOT_READY",
            "timestamp", Instant.now().toString()
        ));
    }

    private void handleStartup(Context ctx) {
        ctx.json(Map.of(
            "status", "STARTED",
            "startTime", startTime.toString(),
            "uptime", Duration.between(startTime, Instant.now()).toString()
        ));
    }

    private void handleMetrics(Context ctx) {
        ctx.contentType("text/plain; version=0.0.4; charset=utf-8");
        ctx.result(metrics != null ? metrics.scrape() : "# No metrics available\n");
    }

    private void handleServerInfo(Context ctx) {
        Runtime runtime = Runtime.getRuntime();
        MemoryMXBean memoryBean = ManagementFactory.getMemoryMXBean();

        ctx.json(Map.of(
            "name", "OpenRSC Server",
            "version", "2.0.0",
            "javaVersion", System.getProperty("java.version"),
            "osName", System.getProperty("os.name"),
            "osVersion", System.getProperty("os.version"),
            "processors", runtime.availableProcessors(),
            "startTime", startTime.toString(),
            "uptime", Duration.between(startTime, Instant.now()).toString(),
            "memory", Map.of(
                "heap", Map.of(
                    "used", memoryBean.getHeapMemoryUsage().getUsed(),
                    "max", memoryBean.getHeapMemoryUsage().getMax()
                ),
                "nonHeap", Map.of(
                    "used", memoryBean.getNonHeapMemoryUsage().getUsed()
                )
            )
        ));
    }

    private void handleServerStatus(Context ctx) {
        ctx.json(Map.of(
            "online", true,
            "worldNumber", worldNumberSupplier.get(),
            "playersOnline", playersOnlineSupplier.get(),
            "npcsActive", npcsActiveSupplier.get(),
            "uptime", Duration.between(startTime, Instant.now()).toString(),
            "timestamp", Instant.now().toString()
        ));
    }

    private void validateApiKey(Context ctx) {
        if (apiKey == null || apiKey.isEmpty()) {
            ctx.status(403).json(Map.of("error", "Admin API disabled"));
            return;
        }

        String providedKey = ctx.header("X-Api-Key");
        if (providedKey == null || !providedKey.equals(apiKey)) {
            ctx.status(401).json(Map.of("error", "Invalid API key"));
        }
    }

    private void handleForceGc(Context ctx) {
        long before = Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory();
        System.gc();
        long after = Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory();

        ctx.json(Map.of(
            "memoryBefore", before,
            "memoryAfter", after,
            "memoryFreed", before - after,
            "timestamp", Instant.now().toString()
        ));
    }

    private void handleMemoryStats(Context ctx) {
        MemoryMXBean memoryBean = ManagementFactory.getMemoryMXBean();
        Runtime runtime = Runtime.getRuntime();

        ctx.json(Map.of(
            "heap", Map.of(
                "init", memoryBean.getHeapMemoryUsage().getInit(),
                "used", memoryBean.getHeapMemoryUsage().getUsed(),
                "committed", memoryBean.getHeapMemoryUsage().getCommitted(),
                "max", memoryBean.getHeapMemoryUsage().getMax()
            ),
            "nonHeap", Map.of(
                "init", memoryBean.getNonHeapMemoryUsage().getInit(),
                "used", memoryBean.getNonHeapMemoryUsage().getUsed(),
                "committed", memoryBean.getNonHeapMemoryUsage().getCommitted()
            ),
            "runtime", Map.of(
                "totalMemory", runtime.totalMemory(),
                "freeMemory", runtime.freeMemory(),
                "maxMemory", runtime.maxMemory()
            ),
            "timestamp", Instant.now().toString()
        ));
    }

    private void handleThreadStats(Context ctx) {
        ThreadMXBean threadBean = ManagementFactory.getThreadMXBean();

        ctx.json(Map.of(
            "threadCount", threadBean.getThreadCount(),
            "peakThreadCount", threadBean.getPeakThreadCount(),
            "totalStartedThreadCount", threadBean.getTotalStartedThreadCount(),
            "daemonThreadCount", threadBean.getDaemonThreadCount(),
            "deadlockedThreads", threadBean.findDeadlockedThreads() != null
                ? threadBean.findDeadlockedThreads().length : 0,
            "timestamp", Instant.now().toString()
        ));
    }

    @Override
    public void close() {
        app.stop();
        LOGGER.info("Health check server stopped");
    }

    /**
     * Health check result.
     */
    public record HealthCheck(boolean healthy, Map<String, Object> details) {
        public static HealthCheck up() {
            return new HealthCheck(true, Map.of());
        }

        public static HealthCheck up(Map<String, Object> details) {
            return new HealthCheck(true, details);
        }

        public static HealthCheck down(String reason) {
            return new HealthCheck(false, Map.of("reason", reason));
        }
    }

    /**
     * Health server configuration.
     */
    public record HealthServerConfig(
        int port,
        String adminApiKey
    ) {
        public static HealthServerConfig defaults() {
            return new HealthServerConfig(8080, null);
        }
    }
}
