package com.openrsc.server.infrastructure.discovery;

import com.orbitz.consul.Consul;
import com.orbitz.consul.AgentClient;
import com.orbitz.consul.HealthClient;
import com.orbitz.consul.KeyValueClient;
import com.orbitz.consul.model.agent.ImmutableRegistration;
import com.orbitz.consul.model.agent.Registration;
import com.orbitz.consul.model.health.ServiceHealth;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.net.InetAddress;
import java.util.*;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Service discovery abstraction supporting Consul.
 * Enables multi-server deployments with automatic registration and discovery.
 */
public class ServiceDiscovery implements AutoCloseable {
    private static final Logger LOGGER = LogManager.getLogger(ServiceDiscovery.class);

    private final Consul consul;
    private final AgentClient agentClient;
    private final HealthClient healthClient;
    private final KeyValueClient kvClient;
    private final ServiceDiscoveryConfig config;
    private final ScheduledExecutorService scheduler;
    private String serviceId;
    private volatile boolean registered = false;

    public ServiceDiscovery(ServiceDiscoveryConfig config) {
        this.config = config;

        Consul.Builder builder = Consul.builder()
            .withUrl(config.consulAddress());

        if (config.aclToken() != null && !config.aclToken().isEmpty()) {
            builder.withAclToken(config.aclToken());
        }

        this.consul = builder.build();
        this.agentClient = consul.agentClient();
        this.healthClient = consul.healthClient();
        this.kvClient = consul.keyValueClient();
        this.scheduler = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "ServiceDiscovery-HealthCheck");
            t.setDaemon(true);
            return t;
        });

        LOGGER.info("Service discovery initialized - Consul at {}", config.consulAddress());
    }

    /**
     * Registers this server instance with Consul.
     */
    public void register(int port, Map<String, String> metadata) {
        try {
            String address = getLocalAddress();
            this.serviceId = config.serviceName() + "-" + address + "-" + port;

            List<String> tags = new ArrayList<>(config.tags());
            tags.add("world:" + config.worldNumber());
            tags.add("version:" + config.version());

            Registration.RegCheck httpCheck = Registration.RegCheck.http(
                "http://" + address + ":" + config.healthPort() + config.healthPath(),
                config.healthCheckIntervalSeconds(),
                config.healthCheckTimeoutSeconds()
            );

            Registration registration = ImmutableRegistration.builder()
                .id(serviceId)
                .name(config.serviceName())
                .address(address)
                .port(port)
                .tags(tags)
                .meta(metadata)
                .check(httpCheck)
                .build();

            agentClient.register(registration);
            registered = true;

            LOGGER.info("Registered service {} at {}:{}", serviceId, address, port);

            // Schedule periodic health updates
            if (config.enableTtlCheck()) {
                scheduler.scheduleAtFixedRate(
                    this::sendHealthPulse,
                    0,
                    config.healthCheckIntervalSeconds() / 2,
                    TimeUnit.SECONDS
                );
            }
        } catch (Exception e) {
            LOGGER.error("Failed to register with Consul: {}", e.getMessage());
        }
    }

    /**
     * Deregisters this server instance from Consul.
     */
    public void deregister() {
        if (registered && serviceId != null) {
            try {
                agentClient.deregister(serviceId);
                registered = false;
                LOGGER.info("Deregistered service {}", serviceId);
            } catch (Exception e) {
                LOGGER.warn("Failed to deregister from Consul: {}", e.getMessage());
            }
        }
    }

    /**
     * Discovers healthy instances of a service.
     */
    public List<ServiceInstance> discoverService(String serviceName) {
        try {
            List<ServiceHealth> healthyServices = healthClient
                .getHealthyServiceInstances(serviceName)
                .getResponse();

            return healthyServices.stream()
                .map(sh -> new ServiceInstance(
                    sh.getService().getId(),
                    sh.getService().getService(),
                    sh.getService().getAddress(),
                    sh.getService().getPort(),
                    sh.getService().getTags(),
                    sh.getService().getMeta()
                ))
                .toList();
        } catch (Exception e) {
            LOGGER.warn("Failed to discover service {}: {}", serviceName, e.getMessage());
            return List.of();
        }
    }

    /**
     * Gets all game server instances.
     */
    public List<ServiceInstance> discoverGameServers() {
        return discoverService(config.serviceName());
    }

    /**
     * Gets a value from the KV store.
     */
    public Optional<String> getKV(String key) {
        try {
            return kvClient.getValueAsString(config.keyPrefix() + key);
        } catch (Exception e) {
            LOGGER.warn("Failed to get KV {}: {}", key, e.getMessage());
            return Optional.empty();
        }
    }

    /**
     * Sets a value in the KV store.
     */
    public boolean setKV(String key, String value) {
        try {
            return kvClient.putValue(config.keyPrefix() + key, value);
        } catch (Exception e) {
            LOGGER.warn("Failed to set KV {}: {}", key, e.getMessage());
            return false;
        }
    }

    /**
     * Deletes a key from the KV store.
     */
    public void deleteKV(String key) {
        try {
            kvClient.deleteKey(config.keyPrefix() + key);
        } catch (Exception e) {
            LOGGER.warn("Failed to delete KV {}: {}", key, e.getMessage());
        }
    }

    /**
     * Acquires a distributed lock.
     */
    public Optional<String> acquireLock(String lockName, int ttlSeconds) {
        String sessionId = createSession(lockName, ttlSeconds);
        if (sessionId == null) return Optional.empty();

        String lockKey = config.keyPrefix() + "locks/" + lockName;
        try {
            boolean acquired = kvClient.acquireLock(lockKey, sessionId);
            if (acquired) {
                LOGGER.debug("Acquired lock: {}", lockName);
                return Optional.of(sessionId);
            }
        } catch (Exception e) {
            LOGGER.warn("Failed to acquire lock {}: {}", lockName, e.getMessage());
        }
        return Optional.empty();
    }

    /**
     * Releases a distributed lock.
     */
    public void releaseLock(String lockName, String sessionId) {
        String lockKey = config.keyPrefix() + "locks/" + lockName;
        try {
            kvClient.releaseLock(lockKey, sessionId);
            LOGGER.debug("Released lock: {}", lockName);
        } catch (Exception e) {
            LOGGER.warn("Failed to release lock {}: {}", lockName, e.getMessage());
        }
    }

    private String createSession(String name, int ttlSeconds) {
        try {
            return consul.sessionClient().createSession(
                com.orbitz.consul.model.session.ImmutableSession.builder()
                    .name(name)
                    .ttl(ttlSeconds + "s")
                    .lockDelay("0s")
                    .build()
            ).getId();
        } catch (Exception e) {
            LOGGER.warn("Failed to create session: {}", e.getMessage());
            return null;
        }
    }

    private void sendHealthPulse() {
        try {
            if (registered && serviceId != null) {
                agentClient.pass(serviceId);
            }
        } catch (Exception e) {
            LOGGER.warn("Failed to send health pulse: {}", e.getMessage());
        }
    }

    private String getLocalAddress() {
        try {
            return InetAddress.getLocalHost().getHostAddress();
        } catch (Exception e) {
            return "127.0.0.1";
        }
    }

    public boolean isRegistered() {
        return registered;
    }

    @Override
    public void close() {
        scheduler.shutdown();
        deregister();
        consul.destroy();
    }

    /**
     * Service instance record.
     */
    public record ServiceInstance(
        String id,
        String name,
        String address,
        int port,
        List<String> tags,
        Map<String, String> metadata
    ) {}

    /**
     * Service discovery configuration.
     */
    public record ServiceDiscoveryConfig(
        String consulAddress,
        String aclToken,
        String serviceName,
        String version,
        int worldNumber,
        List<String> tags,
        String keyPrefix,
        int healthPort,
        String healthPath,
        int healthCheckIntervalSeconds,
        int healthCheckTimeoutSeconds,
        boolean enableTtlCheck
    ) {
        public static ServiceDiscoveryConfig defaults() {
            return new ServiceDiscoveryConfig(
                "http://localhost:8500",
                null,
                "openrsc-server",
                "2.0.0",
                1,
                List.of("game", "openrsc"),
                "openrsc/",
                8080,
                "/health",
                10,
                5,
                true
            );
        }
    }
}
