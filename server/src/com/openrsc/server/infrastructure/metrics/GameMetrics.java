package com.openrsc.server.infrastructure.metrics;

import io.micrometer.core.instrument.*;
import io.micrometer.core.instrument.binder.jvm.*;
import io.micrometer.core.instrument.binder.system.*;
import io.micrometer.prometheus.PrometheusConfig;
import io.micrometer.prometheus.PrometheusMeterRegistry;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Supplier;

/**
 * Game server metrics collection using Micrometer and Prometheus.
 * Provides comprehensive monitoring of game server performance.
 */
public class GameMetrics {
    private static final Logger LOGGER = LogManager.getLogger(GameMetrics.class);

    private final PrometheusMeterRegistry registry;
    private final String worldName;

    // Counters
    private final Counter packetsReceived;
    private final Counter packetsSent;
    private final Counter loginAttempts;
    private final Counter loginSuccesses;
    private final Counter loginFailures;
    private final Counter dbQueriesTotal;
    private final Counter combatEncounters;
    private final Counter itemsDropped;
    private final Counter itemsPickedUp;

    // Timers
    private final Timer packetProcessingTime;
    private final Timer gameTickDuration;
    private final Timer dbQueryDuration;
    private final Timer loginProcessingTime;

    // Gauges
    private final AtomicInteger playersOnline = new AtomicInteger(0);
    private final AtomicInteger npcsActive = new AtomicInteger(0);
    private final AtomicInteger eventsQueued = new AtomicInteger(0);
    private final AtomicInteger activeConnections = new AtomicInteger(0);
    private final AtomicLong tickLateMs = new AtomicLong(0);

    // Distribution summaries
    private final DistributionSummary packetSizeReceived;
    private final DistributionSummary packetSizeSent;

    public GameMetrics(String worldName) {
        this.worldName = worldName;
        this.registry = new PrometheusMeterRegistry(PrometheusConfig.DEFAULT);

        // Add common tags
        registry.config().commonTags("world", worldName, "application", "openrsc-server");

        // Bind JVM metrics
        new JvmMemoryMetrics().bindTo(registry);
        new JvmGcMetrics().bindTo(registry);
        new JvmThreadMetrics().bindTo(registry);
        new ClassLoaderMetrics().bindTo(registry);
        new ProcessorMetrics().bindTo(registry);
        new UptimeMetrics().bindTo(registry);

        // Initialize counters
        packetsReceived = Counter.builder("openrsc_packets_received_total")
            .description("Total number of packets received from clients")
            .register(registry);

        packetsSent = Counter.builder("openrsc_packets_sent_total")
            .description("Total number of packets sent to clients")
            .register(registry);

        loginAttempts = Counter.builder("openrsc_login_attempts_total")
            .description("Total login attempts")
            .register(registry);

        loginSuccesses = Counter.builder("openrsc_login_successes_total")
            .description("Total successful logins")
            .register(registry);

        loginFailures = Counter.builder("openrsc_login_failures_total")
            .description("Total failed logins")
            .register(registry);

        dbQueriesTotal = Counter.builder("openrsc_db_queries_total")
            .description("Total database queries executed")
            .register(registry);

        combatEncounters = Counter.builder("openrsc_combat_encounters_total")
            .description("Total combat encounters initiated")
            .register(registry);

        itemsDropped = Counter.builder("openrsc_items_dropped_total")
            .description("Total items dropped by players")
            .register(registry);

        itemsPickedUp = Counter.builder("openrsc_items_picked_up_total")
            .description("Total items picked up by players")
            .register(registry);

        // Initialize timers
        packetProcessingTime = Timer.builder("openrsc_packet_processing_time")
            .description("Time to process packets")
            .publishPercentileHistogram()
            .register(registry);

        gameTickDuration = Timer.builder("openrsc_game_tick_duration")
            .description("Duration of game tick processing")
            .publishPercentileHistogram()
            .register(registry);

        dbQueryDuration = Timer.builder("openrsc_db_query_duration")
            .description("Duration of database queries")
            .publishPercentileHistogram()
            .register(registry);

        loginProcessingTime = Timer.builder("openrsc_login_processing_time")
            .description("Time to process login requests")
            .publishPercentileHistogram()
            .register(registry);

        // Initialize gauges
        Gauge.builder("openrsc_players_online", playersOnline, AtomicInteger::get)
            .description("Current number of players online")
            .register(registry);

        Gauge.builder("openrsc_npcs_active", npcsActive, AtomicInteger::get)
            .description("Current number of active NPCs")
            .register(registry);

        Gauge.builder("openrsc_events_queued", eventsQueued, AtomicInteger::get)
            .description("Current number of queued events")
            .register(registry);

        Gauge.builder("openrsc_active_connections", activeConnections, AtomicInteger::get)
            .description("Current number of active network connections")
            .register(registry);

        Gauge.builder("openrsc_tick_late_ms", tickLateMs, AtomicLong::get)
            .description("Milliseconds the last game tick was late")
            .register(registry);

        // Initialize distribution summaries
        packetSizeReceived = DistributionSummary.builder("openrsc_packet_size_received")
            .description("Size of received packets in bytes")
            .publishPercentileHistogram()
            .register(registry);

        packetSizeSent = DistributionSummary.builder("openrsc_packet_size_sent")
            .description("Size of sent packets in bytes")
            .publishPercentileHistogram()
            .register(registry);

        LOGGER.info("Game metrics initialized for world: {}", worldName);
    }

    // Counter methods
    public void recordPacketReceived(String opcode, int size) {
        packetsReceived.increment();
        packetSizeReceived.record(size);
        registry.counter("openrsc_packets_received_by_opcode_total", "opcode", opcode).increment();
    }

    public void recordPacketSent(String opcode, int size) {
        packetsSent.increment();
        packetSizeSent.record(size);
        registry.counter("openrsc_packets_sent_by_opcode_total", "opcode", opcode).increment();
    }

    public void recordLoginAttempt(boolean success, String reason) {
        loginAttempts.increment();
        if (success) {
            loginSuccesses.increment();
        } else {
            loginFailures.increment();
            registry.counter("openrsc_login_failures_by_reason_total", "reason", reason).increment();
        }
    }

    public void recordDbQuery(String queryType) {
        dbQueriesTotal.increment();
        registry.counter("openrsc_db_queries_by_type_total", "query_type", queryType).increment();
    }

    public void recordCombatEncounter(String combatType) {
        combatEncounters.increment();
        registry.counter("openrsc_combat_by_type_total", "type", combatType).increment();
    }

    public void recordItemDropped(int itemId) {
        itemsDropped.increment();
    }

    public void recordItemPickedUp(int itemId) {
        itemsPickedUp.increment();
    }

    // Timer methods
    public Timer.Sample startPacketProcessing() {
        return Timer.start(registry);
    }

    public void stopPacketProcessing(Timer.Sample sample, String opcode) {
        sample.stop(packetProcessingTime);
        sample.stop(registry.timer("openrsc_packet_processing_by_opcode", "opcode", opcode));
    }

    public Timer.Sample startGameTick() {
        return Timer.start(registry);
    }

    public void stopGameTick(Timer.Sample sample) {
        sample.stop(gameTickDuration);
    }

    public Timer.Sample startDbQuery() {
        return Timer.start(registry);
    }

    public void stopDbQuery(Timer.Sample sample, String queryType) {
        sample.stop(dbQueryDuration);
        sample.stop(registry.timer("openrsc_db_query_by_type", "query_type", queryType));
    }

    public Timer.Sample startLoginProcessing() {
        return Timer.start(registry);
    }

    public void stopLoginProcessing(Timer.Sample sample) {
        sample.stop(loginProcessingTime);
    }

    public <T> T timeOperation(String name, Supplier<T> operation) {
        return registry.timer("openrsc_operation_duration", "operation", name).record(operation);
    }

    public void timeOperation(String name, Runnable operation) {
        registry.timer("openrsc_operation_duration", "operation", name).record(operation);
    }

    // Gauge methods
    public void setPlayersOnline(int count) {
        playersOnline.set(count);
    }

    public void setNpcsActive(int count) {
        npcsActive.set(count);
    }

    public void setEventsQueued(int count) {
        eventsQueued.set(count);
    }

    public void setActiveConnections(int count) {
        activeConnections.set(count);
    }

    public void setTickLateMs(long ms) {
        tickLateMs.set(ms);
    }

    // Registry access
    public PrometheusMeterRegistry getRegistry() {
        return registry;
    }

    public String scrape() {
        return registry.scrape();
    }

    public void close() {
        registry.close();
    }
}
