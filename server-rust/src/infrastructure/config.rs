use serde::{Deserialize, Serialize};
use anyhow::Result;
use std::path::Path;

/// Main server configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub world_name: String,
    pub server_port: u16,
    pub quic_port: u16,
    pub max_players: u32,

    pub redis: RedisConfig,
    pub metrics: MetricsConfig,
    pub tracing: TracingConfig,
    pub discovery: DiscoveryConfig,
    pub security: SecurityConfig,
}

impl ServerConfig {
    /// Load configuration from file or environment.
    pub fn load() -> Result<Self> {
        let config = config::Config::builder()
            .add_source(config::File::with_name("config/server").required(false))
            .add_source(config::Environment::with_prefix("OPENRSC").separator("__"))
            .set_default("world_name", "world-1")?
            .set_default("server_port", 43594)?
            .set_default("quic_port", 43595)?
            .set_default("max_players", 2000)?
            .set_default("redis.enabled", false)?
            .set_default("redis.url", "redis://localhost:6379")?
            .set_default("redis.pool_size", 10)?
            .set_default("redis.key_prefix", "openrsc:")?
            .set_default("metrics.enabled", true)?
            .set_default("metrics.prometheus_port", 9090)?
            .set_default("tracing.enabled", false)?
            .set_default("tracing.otlp_endpoint", "http://localhost:4317")?
            .set_default("discovery.enabled", false)?
            .set_default("discovery.provider", "consul")?
            .set_default("discovery.consul_url", "http://localhost:8500")?
            .set_default("security.password_iterations", 100000)?
            .build()?;

        Ok(config.try_deserialize()?)
    }

    /// Load configuration from a specific file.
    pub fn load_from_file<P: AsRef<Path>>(path: P) -> Result<Self> {
        let config = config::Config::builder()
            .add_source(config::File::from(path.as_ref().to_path_buf()))
            .add_source(config::Environment::with_prefix("OPENRSC").separator("__"))
            .build()?;

        Ok(config.try_deserialize()?)
    }
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            world_name: "world-1".to_string(),
            server_port: 43594,
            quic_port: 43595,
            max_players: 2000,
            redis: RedisConfig::default(),
            metrics: MetricsConfig::default(),
            tracing: TracingConfig::default(),
            discovery: DiscoveryConfig::default(),
            security: SecurityConfig::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RedisConfig {
    pub enabled: bool,
    pub url: String,
    pub pool_size: u32,
    pub key_prefix: String,
    pub session_ttl_seconds: u64,
    pub default_ttl_seconds: u64,
}

impl Default for RedisConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            url: "redis://localhost:6379".to_string(),
            pool_size: 10,
            key_prefix: "openrsc:".to_string(),
            session_ttl_seconds: 3600,
            default_ttl_seconds: 300,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricsConfig {
    pub enabled: bool,
    pub prometheus_port: u16,
    pub health_port: u16,
}

impl Default for MetricsConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            prometheus_port: 9090,
            health_port: 8080,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TracingConfig {
    pub enabled: bool,
    pub otlp_endpoint: String,
    pub service_name: String,
    pub sample_rate: f64,
}

impl Default for TracingConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            otlp_endpoint: "http://localhost:4317".to_string(),
            service_name: "openrsc-server".to_string(),
            sample_rate: 1.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiscoveryConfig {
    pub enabled: bool,
    pub provider: String,
    pub consul_url: String,
    pub etcd_endpoints: Vec<String>,
    pub service_name: String,
    pub health_check_interval_seconds: u64,
}

impl Default for DiscoveryConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            provider: "consul".to_string(),
            consul_url: "http://localhost:8500".to_string(),
            etcd_endpoints: vec!["http://localhost:2379".to_string()],
            service_name: "openrsc-server".to_string(),
            health_check_interval_seconds: 10,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityConfig {
    pub password_iterations: u32,
    pub session_secret: String,
    pub rate_limit_requests: u32,
    pub rate_limit_window_seconds: u64,
}

impl Default for SecurityConfig {
    fn default() -> Self {
        Self {
            password_iterations: 100000,
            session_secret: String::new(),
            rate_limit_requests: 100,
            rate_limit_window_seconds: 60,
        }
    }
}
