package com.openrsc.server.infrastructure.discovery;

import io.etcd.jetcd.*;
import io.etcd.jetcd.lease.LeaseGrantResponse;
import io.etcd.jetcd.lease.LeaseKeepAliveResponse;
import io.etcd.jetcd.options.GetOption;
import io.etcd.jetcd.options.PutOption;
import io.grpc.stub.StreamObserver;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;

/**
 * etcd-based service discovery implementation.
 * Uses lease-based registration with automatic keep-alive.
 */
public class EtcdServiceDiscovery implements AutoCloseable {
    private static final Logger LOGGER = LogManager.getLogger(EtcdServiceDiscovery.class);

    private static final String SERVICE_PREFIX = "/services/";
    private static final String CONFIG_PREFIX = "/config/";

    private final Client client;
    private final EtcdSettings settings;
    private final Map<String, Long> registeredLeases = new ConcurrentHashMap<>();
    private final Map<String, CloseableClient> keepAliveClients = new ConcurrentHashMap<>();

    public EtcdServiceDiscovery(EtcdSettings settings) {
        this.settings = settings;
        this.client = Client.builder()
            .endpoints(settings.getEndpoints().toArray(new String[0]))
            .build();

        LOGGER.info("Connected to etcd at {}", settings.getEndpoints());
    }

    /**
     * Registers a service with etcd using a lease.
     */
    public CompletableFuture<String> registerService(ServiceRegistration registration) {
        String serviceKey = SERVICE_PREFIX + registration.serviceName() + "/" + registration.serviceId();

        return client.getLeaseClient()
            .grant(settings.getLeaseTtlSeconds())
            .thenCompose(leaseResponse -> {
                long leaseId = leaseResponse.getID();
                registeredLeases.put(registration.serviceId(), leaseId);

                // Start keep-alive
                startKeepAlive(registration.serviceId(), leaseId);

                // Register service data
                String serviceData = buildServiceData(registration);
                ByteSequence key = ByteSequence.from(serviceKey, StandardCharsets.UTF_8);
                ByteSequence value = ByteSequence.from(serviceData, StandardCharsets.UTF_8);

                PutOption putOption = PutOption.builder()
                    .withLeaseId(leaseId)
                    .build();

                return client.getKVClient().put(key, value, putOption)
                    .thenApply(putResponse -> {
                        LOGGER.info("Registered service {} with etcd (lease {})",
                            registration.serviceId(), leaseId);
                        return registration.serviceId();
                    });
            });
    }

    /**
     * Deregisters a service from etcd.
     */
    public CompletableFuture<Void> deregisterService(String serviceId) {
        Long leaseId = registeredLeases.remove(serviceId);
        if (leaseId != null) {
            // Stop keep-alive
            CloseableClient keepAlive = keepAliveClients.remove(serviceId);
            if (keepAlive != null) {
                keepAlive.close();
            }

            // Revoke lease (this also deletes the key)
            return client.getLeaseClient().revoke(leaseId)
                .thenAccept(response -> LOGGER.info("Deregistered service {} from etcd", serviceId));
        }
        return CompletableFuture.completedFuture(null);
    }

    /**
     * Discovers services by name.
     */
    public CompletableFuture<List<ServiceInstance>> discoverServices(String serviceName) {
        String prefix = SERVICE_PREFIX + serviceName + "/";
        ByteSequence prefixKey = ByteSequence.from(prefix, StandardCharsets.UTF_8);

        GetOption getOption = GetOption.builder()
            .isPrefix(true)
            .build();

        return client.getKVClient().get(prefixKey, getOption)
            .thenApply(getResponse -> {
                List<ServiceInstance> instances = new ArrayList<>();
                for (var kv : getResponse.getKvs()) {
                    String data = kv.getValue().toString(StandardCharsets.UTF_8);
                    parseServiceData(data).ifPresent(instances::add);
                }
                return instances;
            });
    }

    /**
     * Gets a configuration value.
     */
    public CompletableFuture<Optional<String>> getConfig(String key) {
        ByteSequence configKey = ByteSequence.from(CONFIG_PREFIX + key, StandardCharsets.UTF_8);

        return client.getKVClient().get(configKey)
            .thenApply(getResponse -> {
                if (getResponse.getKvs().isEmpty()) {
                    return Optional.empty();
                }
                return Optional.of(getResponse.getKvs().get(0).getValue().toString(StandardCharsets.UTF_8));
            });
    }

    /**
     * Sets a configuration value.
     */
    public CompletableFuture<Void> setConfig(String key, String value) {
        ByteSequence configKey = ByteSequence.from(CONFIG_PREFIX + key, StandardCharsets.UTF_8);
        ByteSequence configValue = ByteSequence.from(value, StandardCharsets.UTF_8);

        return client.getKVClient().put(configKey, configValue)
            .thenAccept(response -> LOGGER.debug("Set config {} = {}", key, value));
    }

    /**
     * Watches for service changes.
     */
    public Watch.Watcher watchServices(String serviceName, ServiceChangeListener listener) {
        String prefix = SERVICE_PREFIX + serviceName + "/";
        ByteSequence prefixKey = ByteSequence.from(prefix, StandardCharsets.UTF_8);

        return client.getWatchClient().watch(prefixKey,
            io.etcd.jetcd.options.WatchOption.builder().isPrefix(true).build(),
            watchResponse -> {
                for (var event : watchResponse.getEvents()) {
                    String key = event.getKeyValue().getKey().toString(StandardCharsets.UTF_8);
                    String serviceId = key.substring(prefix.length());

                    switch (event.getEventType()) {
                        case PUT -> {
                            String data = event.getKeyValue().getValue().toString(StandardCharsets.UTF_8);
                            parseServiceData(data).ifPresent(instance ->
                                listener.onServiceAdded(serviceId, instance));
                        }
                        case DELETE -> listener.onServiceRemoved(serviceId);
                    }
                }
            });
    }

    private void startKeepAlive(String serviceId, long leaseId) {
        StreamObserver<LeaseKeepAliveResponse> observer = new StreamObserver<>() {
            @Override
            public void onNext(LeaseKeepAliveResponse response) {
                LOGGER.trace("Lease {} renewed, TTL: {}", leaseId, response.getTTL());
            }

            @Override
            public void onError(Throwable t) {
                LOGGER.error("Lease keep-alive error for service {}", serviceId, t);
            }

            @Override
            public void onCompleted() {
                LOGGER.debug("Lease keep-alive completed for service {}", serviceId);
            }
        };

        CloseableClient keepAlive = client.getLeaseClient().keepAlive(leaseId, observer);
        keepAliveClients.put(serviceId, keepAlive);
    }

    private String buildServiceData(ServiceRegistration registration) {
        // Simple JSON format
        return String.format(
            "{\"id\":\"%s\",\"name\":\"%s\",\"address\":\"%s\",\"port\":%d,\"tags\":%s,\"meta\":%s}",
            registration.serviceId(),
            registration.serviceName(),
            registration.address(),
            registration.port(),
            toJsonArray(registration.tags()),
            toJsonObject(registration.metadata())
        );
    }

    private Optional<ServiceInstance> parseServiceData(String data) {
        try {
            // Simple JSON parsing - in production use proper JSON library
            String id = extractJsonString(data, "id");
            String name = extractJsonString(data, "name");
            String address = extractJsonString(data, "address");
            int port = extractJsonInt(data, "port");

            return Optional.of(new ServiceInstance(id, name, address, port, List.of(), Map.of()));
        } catch (Exception e) {
            LOGGER.warn("Failed to parse service data: {}", data, e);
            return Optional.empty();
        }
    }

    private String extractJsonString(String json, String key) {
        int keyIndex = json.indexOf("\"" + key + "\":\"");
        if (keyIndex < 0) return "";
        int start = keyIndex + key.length() + 4;
        int end = json.indexOf("\"", start);
        return json.substring(start, end);
    }

    private int extractJsonInt(String json, String key) {
        int keyIndex = json.indexOf("\"" + key + "\":");
        if (keyIndex < 0) return 0;
        int start = keyIndex + key.length() + 3;
        int end = start;
        while (end < json.length() && Character.isDigit(json.charAt(end))) end++;
        return Integer.parseInt(json.substring(start, end));
    }

    private String toJsonArray(List<String> list) {
        if (list == null || list.isEmpty()) return "[]";
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < list.size(); i++) {
            if (i > 0) sb.append(",");
            sb.append("\"").append(list.get(i)).append("\"");
        }
        return sb.append("]").toString();
    }

    private String toJsonObject(Map<String, String> map) {
        if (map == null || map.isEmpty()) return "{}";
        StringBuilder sb = new StringBuilder("{");
        boolean first = true;
        for (var entry : map.entrySet()) {
            if (!first) sb.append(",");
            sb.append("\"").append(entry.getKey()).append("\":\"").append(entry.getValue()).append("\"");
            first = false;
        }
        return sb.append("}").toString();
    }

    @Override
    public void close() {
        keepAliveClients.values().forEach(CloseableClient::close);
        keepAliveClients.clear();
        registeredLeases.clear();
        client.close();
        LOGGER.info("etcd service discovery closed");
    }

    /**
     * Service registration record.
     */
    public record ServiceRegistration(
        String serviceId,
        String serviceName,
        String address,
        int port,
        List<String> tags,
        Map<String, String> metadata
    ) {}

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
     * Service change listener interface.
     */
    public interface ServiceChangeListener {
        void onServiceAdded(String serviceId, ServiceInstance instance);
        void onServiceRemoved(String serviceId);
    }

    /**
     * etcd settings.
     */
    public static class EtcdSettings {
        private List<String> endpoints = List.of("http://localhost:2379");
        private long leaseTtlSeconds = 30;

        public List<String> getEndpoints() { return endpoints; }
        public void setEndpoints(List<String> endpoints) { this.endpoints = endpoints; }

        public long getLeaseTtlSeconds() { return leaseTtlSeconds; }
        public void setLeaseTtlSeconds(long ttl) { this.leaseTtlSeconds = ttl; }
    }
}
