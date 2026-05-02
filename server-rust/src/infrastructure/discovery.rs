use anyhow::Result;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;
use tracing::{info, warn};

use super::config::DiscoveryConfig;

/// Service discovery provider abstraction.
pub struct ServiceDiscovery {
    provider: Box<dyn ServiceDiscoveryProvider>,
    config: DiscoveryConfig,
    registered: AtomicBool,
    service_id: Option<String>,
}

impl ServiceDiscovery {
    pub async fn new(config: &DiscoveryConfig) -> Result<Self> {
        let provider: Box<dyn ServiceDiscoveryProvider> = match config.provider.as_str() {
            "consul" => Box::new(ConsulProvider::new(&config.consul_url).await?),
            "etcd" => Box::new(EtcdProvider::new(&config.etcd_endpoints).await?),
            _ => return Err(anyhow::anyhow!("Unknown discovery provider: {}", config.provider)),
        };

        Ok(Self {
            provider,
            config: config.clone(),
            registered: AtomicBool::new(false),
            service_id: None,
        })
    }

    /// Register this service instance.
    pub async fn register(&mut self, port: u16, metadata: HashMap<String, String>) -> Result<()> {
        let service_id = format!(
            "{}-{}-{}",
            self.config.service_name,
            hostname::get()?.to_string_lossy(),
            uuid::Uuid::new_v4()
        );

        let registration = ServiceRegistration {
            id: service_id.clone(),
            name: self.config.service_name.clone(),
            address: local_ip()?,
            port,
            tags: vec!["game".to_string(), "openrsc".to_string()],
            metadata,
            health_check_interval: Duration::from_secs(self.config.health_check_interval_seconds),
        };

        self.provider.register(&registration).await?;
        self.service_id = Some(service_id.clone());
        self.registered.store(true, Ordering::Relaxed);

        info!("Registered with service discovery as {}", service_id);
        Ok(())
    }

    /// Deregister this service instance.
    pub async fn deregister(&mut self) -> Result<()> {
        if let Some(ref service_id) = self.service_id {
            self.provider.deregister(service_id).await?;
            self.registered.store(false, Ordering::Relaxed);
            info!("Deregistered from service discovery");
        }
        Ok(())
    }

    /// Discover other service instances.
    pub async fn discover(&self, service_name: &str) -> Result<Vec<ServiceInstance>> {
        self.provider.discover(service_name).await
    }

    /// Check if registered.
    pub fn is_registered(&self) -> bool {
        self.registered.load(Ordering::Relaxed)
    }
}

/// Service registration details.
#[derive(Debug, Clone)]
pub struct ServiceRegistration {
    pub id: String,
    pub name: String,
    pub address: String,
    pub port: u16,
    pub tags: Vec<String>,
    pub metadata: HashMap<String, String>,
    pub health_check_interval: Duration,
}

/// Discovered service instance.
#[derive(Debug, Clone)]
pub struct ServiceInstance {
    pub id: String,
    pub name: String,
    pub address: String,
    pub port: u16,
    pub tags: Vec<String>,
    pub metadata: HashMap<String, String>,
    pub healthy: bool,
}

/// Trait for service discovery providers.
#[async_trait::async_trait]
pub trait ServiceDiscoveryProvider: Send + Sync {
    async fn register(&self, registration: &ServiceRegistration) -> Result<()>;
    async fn deregister(&self, service_id: &str) -> Result<()>;
    async fn discover(&self, service_name: &str) -> Result<Vec<ServiceInstance>>;
    fn provider_name(&self) -> &str;
}

/// Consul service discovery provider.
pub struct ConsulProvider {
    base_url: String,
    client: reqwest::Client,
}

impl ConsulProvider {
    pub async fn new(base_url: &str) -> Result<Self> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()?;

        Ok(Self {
            base_url: base_url.to_string(),
            client,
        })
    }
}

#[async_trait::async_trait]
impl ServiceDiscoveryProvider for ConsulProvider {
    async fn register(&self, registration: &ServiceRegistration) -> Result<()> {
        let payload = serde_json::json!({
            "ID": registration.id,
            "Name": registration.name,
            "Address": registration.address,
            "Port": registration.port,
            "Tags": registration.tags,
            "Meta": registration.metadata,
            "Check": {
                "HTTP": format!("http://{}:{}/health", registration.address, registration.port + 1000),
                "Interval": format!("{}s", registration.health_check_interval.as_secs()),
                "DeregisterCriticalServiceAfter": "1m"
            }
        });

        self.client
            .put(&format!("{}/v1/agent/service/register", self.base_url))
            .json(&payload)
            .send()
            .await?
            .error_for_status()?;

        Ok(())
    }

    async fn deregister(&self, service_id: &str) -> Result<()> {
        self.client
            .put(&format!("{}/v1/agent/service/deregister/{}", self.base_url, service_id))
            .send()
            .await?
            .error_for_status()?;

        Ok(())
    }

    async fn discover(&self, service_name: &str) -> Result<Vec<ServiceInstance>> {
        let response: Vec<serde_json::Value> = self.client
            .get(&format!("{}/v1/health/service/{}?passing=true", self.base_url, service_name))
            .send()
            .await?
            .json()
            .await?;

        let instances = response
            .iter()
            .filter_map(|entry| {
                let service = entry.get("Service")?;
                Some(ServiceInstance {
                    id: service.get("ID")?.as_str()?.to_string(),
                    name: service.get("Service")?.as_str()?.to_string(),
                    address: service.get("Address")?.as_str()?.to_string(),
                    port: service.get("Port")?.as_u64()? as u16,
                    tags: service
                        .get("Tags")?
                        .as_array()?
                        .iter()
                        .filter_map(|t| t.as_str().map(String::from))
                        .collect(),
                    metadata: HashMap::new(),
                    healthy: true,
                })
            })
            .collect();

        Ok(instances)
    }

    fn provider_name(&self) -> &str {
        "consul"
    }
}

/// etcd service discovery provider.
pub struct EtcdProvider {
    client: etcd_client::Client,
}

impl EtcdProvider {
    pub async fn new(endpoints: &[String]) -> Result<Self> {
        let client = etcd_client::Client::connect(endpoints, None).await?;
        Ok(Self { client })
    }
}

#[async_trait::async_trait]
impl ServiceDiscoveryProvider for EtcdProvider {
    async fn register(&self, registration: &ServiceRegistration) -> Result<()> {
        let mut client = self.client.clone();

        // Create lease
        let lease = client.lease_grant(30, None).await?;
        let lease_id = lease.id();

        // Register service
        let key = format!("/services/{}/{}", registration.name, registration.id);
        let value = serde_json::to_string(&serde_json::json!({
            "id": registration.id,
            "name": registration.name,
            "address": registration.address,
            "port": registration.port,
            "tags": registration.tags,
            "metadata": registration.metadata
        }))?;

        let options = etcd_client::PutOptions::new().with_lease(lease_id);
        client.put(key, value, Some(options)).await?;

        // Start keep-alive (in real implementation, this would be a background task)
        let (mut keeper, _stream) = client.lease_keep_alive(lease_id).await?;
        keeper.keep_alive().await?;

        Ok(())
    }

    async fn deregister(&self, service_id: &str) -> Result<()> {
        let mut client = self.client.clone();
        let key = format!("/services/*/{}", service_id);
        client.delete(key, None).await?;
        Ok(())
    }

    async fn discover(&self, service_name: &str) -> Result<Vec<ServiceInstance>> {
        let mut client = self.client.clone();
        let prefix = format!("/services/{}/", service_name);
        let options = etcd_client::GetOptions::new().with_prefix();

        let response = client.get(prefix, Some(options)).await?;

        let instances = response
            .kvs()
            .iter()
            .filter_map(|kv| {
                let value: serde_json::Value = serde_json::from_slice(kv.value()).ok()?;
                Some(ServiceInstance {
                    id: value.get("id")?.as_str()?.to_string(),
                    name: value.get("name")?.as_str()?.to_string(),
                    address: value.get("address")?.as_str()?.to_string(),
                    port: value.get("port")?.as_u64()? as u16,
                    tags: value
                        .get("tags")?
                        .as_array()?
                        .iter()
                        .filter_map(|t| t.as_str().map(String::from))
                        .collect(),
                    metadata: HashMap::new(),
                    healthy: true,
                })
            })
            .collect();

        Ok(instances)
    }

    fn provider_name(&self) -> &str {
        "etcd"
    }
}

fn local_ip() -> Result<String> {
    let socket = std::net::UdpSocket::bind("0.0.0.0:0")?;
    socket.connect("8.8.8.8:80")?;
    Ok(socket.local_addr()?.ip().to_string())
}
