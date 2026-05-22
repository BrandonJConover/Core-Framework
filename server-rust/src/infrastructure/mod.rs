pub mod cache;
pub mod config;
pub mod discovery;
pub mod http;
pub mod metrics;
pub mod serialization;
pub mod tracing_config;

use anyhow::Result;
use tracing::info;

use self::cache::RedisCache;
use self::config::ServerConfig;
use self::discovery::ServiceDiscovery;
use self::metrics::MetricsCollector;
use self::serialization::SerializerFactory;
use self::tracing_config::TracingConfig;

/// Central manager for all infrastructure components.
/// Provides unified lifecycle management and health monitoring.
pub struct InfrastructureManager {
    config: ServerConfig,
    redis: Option<RedisCache>,
    metrics: Option<MetricsCollector>,
    discovery: Option<ServiceDiscovery>,
    serializers: SerializerFactory,
    initialized: bool,
}

impl InfrastructureManager {
    pub fn new(config: ServerConfig) -> Self {
        Self {
            config,
            redis: None,
            metrics: None,
            discovery: None,
            serializers: SerializerFactory::new(),
            initialized: false,
        }
    }

    /// Initialize all infrastructure components.
    pub async fn initialize(&mut self) -> Result<()> {
        info!("Initializing infrastructure components...");

        // Initialize metrics first (used by other components)
        if self.config.metrics.enabled {
            match MetricsCollector::new(&self.config.metrics).await {
                Ok(metrics) => {
                    self.metrics = Some(metrics);
                    info!("✓ Metrics collector initialized");
                }
                Err(e) => {
                    tracing::warn!("✗ Failed to initialize metrics: {}", e);
                }
            }
        }

        // Initialize Redis
        if self.config.redis.enabled {
            match RedisCache::new(&self.config.redis).await {
                Ok(cache) => {
                    self.redis = Some(cache);
                    info!("✓ Redis cache initialized");
                }
                Err(e) => {
                    tracing::warn!("✗ Failed to initialize Redis: {}", e);
                }
            }
        }

        // Initialize OpenTelemetry tracing
        if self.config.tracing.enabled {
            match TracingConfig::initialize(&self.config.tracing) {
                Ok(_) => {
                    info!("✓ OpenTelemetry tracing initialized");
                }
                Err(e) => {
                    tracing::warn!("✗ Failed to initialize tracing: {}", e);
                }
            }
        }

        // Initialize service discovery
        if self.config.discovery.enabled {
            match ServiceDiscovery::new(&self.config.discovery).await {
                Ok(discovery) => {
                    self.discovery = Some(discovery);
                    info!("✓ Service discovery initialized");
                }
                Err(e) => {
                    tracing::warn!("✗ Failed to initialize service discovery: {}", e);
                }
            }
        }

        self.initialized = true;
        info!("Infrastructure initialization complete");
        Ok(())
    }

    /// Shutdown all infrastructure components.
    pub async fn shutdown(&mut self) -> Result<()> {
        info!("Shutting down infrastructure...");

        // Deregister from service discovery
        if let Some(ref mut discovery) = self.discovery {
            discovery.deregister().await?;
        }

        // Close Redis connections
        if let Some(ref mut redis) = self.redis {
            redis.close().await?;
        }

        self.initialized = false;
        info!("Infrastructure shutdown complete");
        Ok(())
    }

    // Getters
    pub fn redis(&self) -> Option<&RedisCache> {
        self.redis.as_ref()
    }

    pub fn metrics(&self) -> Option<&MetricsCollector> {
        self.metrics.as_ref()
    }

    pub fn discovery(&self) -> Option<&ServiceDiscovery> {
        self.discovery.as_ref()
    }

    pub fn serializers(&self) -> &SerializerFactory {
        &self.serializers
    }

    pub fn is_healthy(&self) -> bool {
        self.initialized
            && self
                .redis
                .as_ref()
                .map(|r| r.is_connected())
                .unwrap_or(true)
    }

    /// Get health status for all components.
    pub fn health_status(&self) -> HealthStatus {
        HealthStatus {
            healthy: self.is_healthy(),
            components: vec![
                ComponentHealth {
                    name: "redis".to_string(),
                    healthy: self
                        .redis
                        .as_ref()
                        .map(|r| r.is_connected())
                        .unwrap_or(true),
                    status: if self.redis.is_some() {
                        "connected"
                    } else {
                        "disabled"
                    }
                    .to_string(),
                },
                ComponentHealth {
                    name: "metrics".to_string(),
                    healthy: self.metrics.is_some(),
                    status: if self.metrics.is_some() {
                        "enabled"
                    } else {
                        "disabled"
                    }
                    .to_string(),
                },
                ComponentHealth {
                    name: "discovery".to_string(),
                    healthy: self
                        .discovery
                        .as_ref()
                        .map(|d| d.is_registered())
                        .unwrap_or(true),
                    status: if self.discovery.is_some() {
                        "registered"
                    } else {
                        "disabled"
                    }
                    .to_string(),
                },
            ],
            timestamp: chrono::Utc::now(),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct HealthStatus {
    pub healthy: bool,
    pub components: Vec<ComponentHealth>,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ComponentHealth {
    pub name: String,
    pub healthy: bool,
    pub status: String,
}
