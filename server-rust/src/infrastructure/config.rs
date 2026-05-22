use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::Path;

fn default_ws_port() -> u16 {
    43494
}
fn default_max_sessions_per_ip() -> u32 {
    5
}

/// Main server configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    pub world_name: String,
    pub server_port: u16,
    /// HTTP API port. Defaults to Java-compatible 43595, but can be moved for
    /// side-by-side Java-vs-Rust local smoke testing.
    pub api_port: u16,
    pub quic_port: u16,
    /// WebSocket port (default 43494). Caddy proxies `/rsc-ws` and
    /// `/rsc21-ws` to this port. Set to 0 to disable the WS listener.
    #[serde(default = "default_ws_port")]
    pub ws_port: u16,
    pub max_players: u32,
    /// Per-IP session cap. Default 5 keeps a public deployment safe; bump
    /// during local benchmarking (when all conn_storm sessions share 127.0.0.1).
    #[serde(default = "default_max_sessions_per_ip")]
    pub max_sessions_per_ip: u32,

    pub redis: RedisConfig,
    pub metrics: MetricsConfig,
    pub tracing: TracingConfig,
    pub discovery: DiscoveryConfig,
    pub security: SecurityConfig,
    pub database: DatabaseSection,
}

/// Database section for ServerConfig.
///
/// `enabled = false` means the server runs in accept-all auth mode with no
/// persistence — handy for benchmarking the protocol/tick path. When true,
/// the SQLite/MySQL pool is wired into the ServerState and login goes
/// through bcrypt verification.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DatabaseSection {
    pub enabled: bool,
    pub kind: String,        // "sqlite" or "mysql"
    pub sqlite_path: String, // e.g. "openrsc.db"
    pub host: String,
    pub port: u16,
    pub database: String,
    pub username: String,
    pub password: String,
}

impl Default for DatabaseSection {
    fn default() -> Self {
        Self {
            enabled: false,
            kind: "sqlite".to_string(),
            sqlite_path: "openrsc.db".to_string(),
            host: "localhost".to_string(),
            port: 3306,
            database: "openrsc".to_string(),
            username: "root".to_string(),
            password: String::new(),
        }
    }
}

impl ServerConfig {
    /// Load configuration from file or environment.
    ///
    /// Starts from `ServerConfig::default()` so any field added to a sub-struct
    /// is automatically defaulted; file/env sources overlay on top.
    pub fn load() -> Result<Self> {
        let defaults = config::Config::try_from(&Self::default())?;
        let config = config::Config::builder()
            .add_source(defaults)
            .add_source(config::File::with_name("config/server").required(false))
            .add_source(config::Environment::with_prefix("OPENRSC").separator("__"))
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
            api_port: 43595,
            quic_port: 43595,
            ws_port: default_ws_port(),
            max_players: 2000,
            max_sessions_per_ip: default_max_sessions_per_ip(),
            redis: RedisConfig::default(),
            metrics: MetricsConfig::default(),
            tracing: TracingConfig::default(),
            discovery: DiscoveryConfig::default(),
            security: SecurityConfig::default(),
            database: DatabaseSection::default(),
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
