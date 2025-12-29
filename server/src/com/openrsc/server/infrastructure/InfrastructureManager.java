package com.openrsc.server.infrastructure;

import com.openrsc.server.infrastructure.cache.RedisCache;
import com.openrsc.server.infrastructure.cache.SessionStore;
import com.openrsc.server.infrastructure.discovery.ServiceDiscovery;
import com.openrsc.server.infrastructure.http.HealthCheckServer;
import com.openrsc.server.infrastructure.metrics.GameMetrics;
import com.openrsc.server.infrastructure.serialization.MessagePackSerializer;
import com.openrsc.server.infrastructure.tracing.OpenTelemetryConfig;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Map;

/**
 * Central manager for all modern infrastructure components.
 * Handles initialization, lifecycle, and coordination of infrastructure services.
 */
public class InfrastructureManager implements AutoCloseable {
    private static final Logger LOGGER = LogManager.getLogger(InfrastructureManager.class);

    private final InfrastructureConfig config;

    // Infrastructure components
    private RedisCache redisCache;
    private SessionStore sessionStore;
    private GameMetrics metrics;
    private OpenTelemetryConfig tracing;
    private ServiceDiscovery serviceDiscovery;
    private HealthCheckServer healthServer;
    private MessagePackSerializer messagePackSerializer;

    private volatile boolean initialized = false;

    public InfrastructureManager(InfrastructureConfig config) {
        this.config = config;
    }

    /**
     * Initializes all enabled infrastructure components.
     */
    public void initialize() {
        LOGGER.info("Initializing infrastructure components...");

        // Initialize metrics first (used by other components)
        if (config.metricsEnabled()) {
            try {
                metrics = new GameMetrics(config.worldName());
                LOGGER.info("✓ Metrics initialized");
            } catch (Exception e) {
                LOGGER.error("✗ Failed to initialize metrics: {}", e.getMessage());
            }
        }

        // Initialize Redis cache
        if (config.redisEnabled()) {
            try {
                redisCache = new RedisCache(config.redisConfig());
                sessionStore = new SessionStore(redisCache, config.sessionTtlSeconds());
                LOGGER.info("✓ Redis cache initialized");
            } catch (Exception e) {
                LOGGER.error("✗ Failed to initialize Redis: {}", e.getMessage());
            }
        }

        // Initialize OpenTelemetry tracing
        if (config.tracingEnabled()) {
            try {
                tracing = new OpenTelemetryConfig(config.tracingConfig());
                LOGGER.info("✓ OpenTelemetry tracing initialized");
            } catch (Exception e) {
                LOGGER.error("✗ Failed to initialize OpenTelemetry: {}", e.getMessage());
            }
        }

        // Initialize service discovery
        if (config.serviceDiscoveryEnabled()) {
            try {
                serviceDiscovery = new ServiceDiscovery(config.serviceDiscoveryConfig());
                LOGGER.info("✓ Service discovery initialized");
            } catch (Exception e) {
                LOGGER.error("✗ Failed to initialize service discovery: {}", e.getMessage());
            }
        }

        // Initialize MessagePack serializer
        messagePackSerializer = new MessagePackSerializer();
        LOGGER.info("✓ MessagePack serializer initialized");

        // Initialize health check server (should be last)
        if (config.healthServerEnabled()) {
            try {
                healthServer = new HealthCheckServer(config.healthServerConfig(), metrics);
                setupHealthChecks();
                healthServer.start();
                LOGGER.info("✓ Health server started on port {}", config.healthServerConfig().port());
            } catch (Exception e) {
                LOGGER.error("✗ Failed to start health server: {}", e.getMessage());
            }
        }

        initialized = true;
        LOGGER.info("Infrastructure initialization complete");
    }

    /**
     * Registers the server with service discovery.
     */
    public void registerServer(int gamePort, Map<String, String> metadata) {
        if (serviceDiscovery != null) {
            serviceDiscovery.register(gamePort, metadata);
        }
    }

    private void setupHealthChecks() {
        // Redis health check
        if (redisCache != null) {
            healthServer.registerHealthCheck("redis", () ->
                redisCache.healthCheck()
                    ? HealthCheckServer.HealthCheck.healthy(Map.of("connected", true))
                    : HealthCheckServer.HealthCheck.unhealthy("Redis connection failed")
            );
        }

        // Service discovery health check
        if (serviceDiscovery != null) {
            healthServer.registerHealthCheck("consul", () ->
                serviceDiscovery.isRegistered()
                    ? HealthCheckServer.HealthCheck.healthy(Map.of("registered", true))
                    : HealthCheckServer.HealthCheck.unhealthy("Not registered with Consul")
            );
        }
    }

    // Getters for infrastructure components

    public RedisCache getRedisCache() {
        return redisCache;
    }

    public SessionStore getSessionStore() {
        return sessionStore;
    }

    public GameMetrics getMetrics() {
        return metrics;
    }

    public OpenTelemetryConfig getTracing() {
        return tracing;
    }

    public ServiceDiscovery getServiceDiscovery() {
        return serviceDiscovery;
    }

    public HealthCheckServer getHealthServer() {
        return healthServer;
    }

    public MessagePackSerializer getMessagePackSerializer() {
        return messagePackSerializer;
    }

    public boolean isInitialized() {
        return initialized;
    }

    @Override
    public void close() {
        LOGGER.info("Shutting down infrastructure components...");

        // Deregister from service discovery first
        if (serviceDiscovery != null) {
            try {
                serviceDiscovery.close();
            } catch (Exception e) {
                LOGGER.warn("Error closing service discovery: {}", e.getMessage());
            }
        }

        // Stop health server
        if (healthServer != null) {
            try {
                healthServer.close();
            } catch (Exception e) {
                LOGGER.warn("Error closing health server: {}", e.getMessage());
            }
        }

        // Close tracing
        if (tracing != null) {
            try {
                tracing.close();
            } catch (Exception e) {
                LOGGER.warn("Error closing tracing: {}", e.getMessage());
            }
        }

        // Close Redis
        if (redisCache != null) {
            try {
                redisCache.close();
            } catch (Exception e) {
                LOGGER.warn("Error closing Redis: {}", e.getMessage());
            }
        }

        // Close metrics
        if (metrics != null) {
            metrics.close();
        }

        initialized = false;
        LOGGER.info("Infrastructure shutdown complete");
    }

    /**
     * Infrastructure configuration builder.
     */
    public record InfrastructureConfig(
        String worldName,
        boolean redisEnabled,
        RedisCache.RedisCacheConfig redisConfig,
        int sessionTtlSeconds,
        boolean metricsEnabled,
        boolean tracingEnabled,
        OpenTelemetryConfig.TracingConfig tracingConfig,
        boolean serviceDiscoveryEnabled,
        ServiceDiscovery.ServiceDiscoveryConfig serviceDiscoveryConfig,
        boolean healthServerEnabled,
        HealthCheckServer.HealthServerConfig healthServerConfig
    ) {
        public static InfrastructureConfig defaults() {
            return new InfrastructureConfig(
                "world-1",
                false, RedisCache.RedisCacheConfig.defaults(), 3600,
                true,
                false, OpenTelemetryConfig.TracingConfig.defaults(),
                false, ServiceDiscovery.ServiceDiscoveryConfig.defaults(),
                true, HealthCheckServer.HealthServerConfig.defaults()
            );
        }

        public static Builder builder() {
            return new Builder();
        }

        public static class Builder {
            private String worldName = "world-1";
            private boolean redisEnabled = false;
            private RedisCache.RedisCacheConfig redisConfig = RedisCache.RedisCacheConfig.defaults();
            private int sessionTtlSeconds = 3600;
            private boolean metricsEnabled = true;
            private boolean tracingEnabled = false;
            private OpenTelemetryConfig.TracingConfig tracingConfig = OpenTelemetryConfig.TracingConfig.defaults();
            private boolean serviceDiscoveryEnabled = false;
            private ServiceDiscovery.ServiceDiscoveryConfig serviceDiscoveryConfig = ServiceDiscovery.ServiceDiscoveryConfig.defaults();
            private boolean healthServerEnabled = true;
            private HealthCheckServer.HealthServerConfig healthServerConfig = HealthCheckServer.HealthServerConfig.defaults();

            public Builder worldName(String worldName) {
                this.worldName = worldName;
                return this;
            }

            public Builder enableRedis(RedisCache.RedisCacheConfig config) {
                this.redisEnabled = true;
                this.redisConfig = config;
                return this;
            }

            public Builder sessionTtlSeconds(int seconds) {
                this.sessionTtlSeconds = seconds;
                return this;
            }

            public Builder enableMetrics(boolean enabled) {
                this.metricsEnabled = enabled;
                return this;
            }

            public Builder enableTracing(OpenTelemetryConfig.TracingConfig config) {
                this.tracingEnabled = true;
                this.tracingConfig = config;
                return this;
            }

            public Builder enableServiceDiscovery(ServiceDiscovery.ServiceDiscoveryConfig config) {
                this.serviceDiscoveryEnabled = true;
                this.serviceDiscoveryConfig = config;
                return this;
            }

            public Builder enableHealthServer(HealthCheckServer.HealthServerConfig config) {
                this.healthServerEnabled = true;
                this.healthServerConfig = config;
                return this;
            }

            public InfrastructureConfig build() {
                return new InfrastructureConfig(
                    worldName,
                    redisEnabled, redisConfig, sessionTtlSeconds,
                    metricsEnabled,
                    tracingEnabled, tracingConfig,
                    serviceDiscoveryEnabled, serviceDiscoveryConfig,
                    healthServerEnabled, healthServerConfig
                );
            }
        }
    }
}
