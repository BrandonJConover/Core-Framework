mod database;
mod game;
mod infrastructure;
mod network;
mod protocol;
mod security;
mod session;

use anyhow::Result;
use tracing::{info, Level};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use infrastructure::InfrastructureManager;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "openrsc_server=debug,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    info!("Starting OpenRSC Rust Server v{}", env!("CARGO_PKG_VERSION"));

    // Load configuration
    let config = infrastructure::config::ServerConfig::load()?;
    info!("Configuration loaded for world: {}", config.world_name);

    // Initialize infrastructure
    let mut infrastructure = InfrastructureManager::new(config.clone());
    infrastructure.initialize().await?;

    info!("Infrastructure initialized successfully");

    // Start network listeners
    let network_handle = tokio::spawn(async move {
        network::start_server(&config).await
    });

    // Wait for shutdown signal
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {
            info!("Shutdown signal received");
        }
        result = network_handle => {
            if let Err(e) = result {
                tracing::error!("Network server error: {}", e);
            }
        }
    }

    // Cleanup
    infrastructure.shutdown().await?;
    info!("Server shutdown complete");

    Ok(())
}
