use anyhow::Result;
use metrics::{counter, gauge, histogram, describe_counter, describe_gauge, describe_histogram};
use metrics_exporter_prometheus::PrometheusBuilder;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

use super::config::MetricsConfig;

/// Game metrics collector using the metrics crate.
pub struct MetricsCollector {
    start_time: Instant,
    players_online: AtomicU64,
    npcs_active: AtomicU64,
}

impl MetricsCollector {
    pub async fn new(config: &MetricsConfig) -> Result<Self> {
        // Initialize Prometheus exporter
        let builder = PrometheusBuilder::new();
        builder
            .with_http_listener(([0, 0, 0, 0], config.prometheus_port))
            .install()?;

        // Register metric descriptions
        Self::register_metrics();

        Ok(Self {
            start_time: Instant::now(),
            players_online: AtomicU64::new(0),
            npcs_active: AtomicU64::new(0),
        })
    }

    fn register_metrics() {
        // Counters
        describe_counter!("openrsc_packets_received_total", "Total packets received");
        describe_counter!("openrsc_packets_sent_total", "Total packets sent");
        describe_counter!("openrsc_login_attempts_total", "Total login attempts");
        describe_counter!("openrsc_login_successes_total", "Successful logins");
        describe_counter!("openrsc_login_failures_total", "Failed logins");
        describe_counter!("openrsc_db_queries_total", "Database queries executed");
        describe_counter!("openrsc_combat_encounters_total", "Combat encounters");

        // Gauges
        describe_gauge!("openrsc_players_online", "Players currently online");
        describe_gauge!("openrsc_npcs_active", "Active NPCs");
        describe_gauge!("openrsc_connections_active", "Active connections");
        describe_gauge!("openrsc_events_queued", "Events in queue");
        describe_gauge!("openrsc_tick_late_ms", "Game tick lateness in ms");

        // Histograms
        describe_histogram!("openrsc_packet_processing_seconds", "Packet processing time");
        describe_histogram!("openrsc_game_tick_seconds", "Game tick duration");
        describe_histogram!("openrsc_db_query_seconds", "Database query duration");
        describe_histogram!("openrsc_login_processing_seconds", "Login processing time");
        describe_histogram!("openrsc_packet_size_bytes", "Packet sizes");
    }

    // Counter methods
    pub fn record_packet_received(&self, opcode: &str, size: usize) {
        counter!("openrsc_packets_received_total").increment(1);
        counter!("openrsc_packets_received_by_opcode_total", "opcode" => opcode.to_string()).increment(1);
        histogram!("openrsc_packet_size_bytes", "direction" => "received").record(size as f64);
    }

    pub fn record_packet_sent(&self, opcode: &str, size: usize) {
        counter!("openrsc_packets_sent_total").increment(1);
        counter!("openrsc_packets_sent_by_opcode_total", "opcode" => opcode.to_string()).increment(1);
        histogram!("openrsc_packet_size_bytes", "direction" => "sent").record(size as f64);
    }

    pub fn record_login_attempt(&self, success: bool, reason: Option<&str>) {
        counter!("openrsc_login_attempts_total").increment(1);
        if success {
            counter!("openrsc_login_successes_total").increment(1);
        } else {
            counter!("openrsc_login_failures_total").increment(1);
            if let Some(r) = reason {
                counter!("openrsc_login_failures_by_reason_total", "reason" => r.to_string()).increment(1);
            }
        }
    }

    pub fn record_db_query(&self, query_type: &str) {
        counter!("openrsc_db_queries_total").increment(1);
        counter!("openrsc_db_queries_by_type_total", "type" => query_type.to_string()).increment(1);
    }

    pub fn record_combat_encounter(&self, combat_type: &str) {
        counter!("openrsc_combat_encounters_total").increment(1);
        counter!("openrsc_combat_by_type_total", "type" => combat_type.to_string()).increment(1);
    }

    // Gauge methods
    pub fn set_players_online(&self, count: u64) {
        self.players_online.store(count, Ordering::Relaxed);
        gauge!("openrsc_players_online").set(count as f64);
    }

    pub fn set_npcs_active(&self, count: u64) {
        self.npcs_active.store(count, Ordering::Relaxed);
        gauge!("openrsc_npcs_active").set(count as f64);
    }

    pub fn set_connections_active(&self, count: u64) {
        gauge!("openrsc_connections_active").set(count as f64);
    }

    pub fn set_events_queued(&self, count: u64) {
        gauge!("openrsc_events_queued").set(count as f64);
    }

    pub fn set_tick_late_ms(&self, ms: i64) {
        gauge!("openrsc_tick_late_ms").set(ms as f64);
    }

    // Timer methods
    pub fn time_packet_processing<F, T>(&self, opcode: &str, f: F) -> T
    where
        F: FnOnce() -> T,
    {
        let start = Instant::now();
        let result = f();
        let duration = start.elapsed();

        histogram!("openrsc_packet_processing_seconds").record(duration.as_secs_f64());
        histogram!("openrsc_packet_processing_by_opcode_seconds", "opcode" => opcode.to_string())
            .record(duration.as_secs_f64());

        result
    }

    pub fn time_game_tick<F, T>(&self, f: F) -> T
    where
        F: FnOnce() -> T,
    {
        let start = Instant::now();
        let result = f();
        histogram!("openrsc_game_tick_seconds").record(start.elapsed().as_secs_f64());
        result
    }

    pub fn time_db_query<F, T>(&self, query_type: &str, f: F) -> T
    where
        F: FnOnce() -> T,
    {
        let start = Instant::now();
        let result = f();
        let duration = start.elapsed();

        histogram!("openrsc_db_query_seconds").record(duration.as_secs_f64());
        histogram!("openrsc_db_query_by_type_seconds", "type" => query_type.to_string())
            .record(duration.as_secs_f64());

        result
    }

    pub fn time_login<F, T>(&self, f: F) -> T
    where
        F: FnOnce() -> T,
    {
        let start = Instant::now();
        let result = f();
        histogram!("openrsc_login_processing_seconds").record(start.elapsed().as_secs_f64());
        result
    }

    // Utility methods
    pub fn uptime_seconds(&self) -> u64 {
        self.start_time.elapsed().as_secs()
    }

    pub fn players_online(&self) -> u64 {
        self.players_online.load(Ordering::Relaxed)
    }
}

/// Timer guard for automatic timing.
pub struct TimerGuard<'a> {
    start: Instant,
    histogram_name: &'a str,
    labels: Vec<(&'a str, String)>,
}

impl<'a> TimerGuard<'a> {
    pub fn new(histogram_name: &'a str) -> Self {
        Self {
            start: Instant::now(),
            histogram_name,
            labels: Vec::new(),
        }
    }

    pub fn with_label(mut self, key: &'a str, value: impl Into<String>) -> Self {
        self.labels.push((key, value.into()));
        self
    }
}

impl Drop for TimerGuard<'_> {
    fn drop(&mut self) {
        let duration = self.start.elapsed().as_secs_f64();
        let name = self.histogram_name.clone();
        histogram!(name).record(duration);
    }
}
