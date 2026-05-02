mod database;
mod game;
mod infrastructure;
mod network;
mod protocol;
mod security;
mod session;

use anyhow::Result;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tracing::{error, info};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use game::server::{ServerState, TICK_DURATION_MS};
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

    // Initialize infrastructure (metrics, redis, tracing, discovery)
    let mut infrastructure = InfrastructureManager::new(config.clone());
    infrastructure.initialize().await?;
    info!("Infrastructure initialized");

    // Create shared server state
    let server_state = Arc::new(RwLock::new(ServerState::new()));
    {
        let mut state = server_state.write().await;
        state.initialize().await?;
    }
    info!("Game state initialized");

    // Spawn game tick loop
    let tick_state = server_state.clone();
    let tick_handle = tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_millis(TICK_DURATION_MS));
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

        loop {
            interval.tick().await;

            let shutting_down = {
                let mut state = tick_state.write().await;
                state.tick().await;
                state.shutting_down
            };

            if shutting_down {
                info!("Game loop shutting down");
                break;
            }
        }
    });

    // Start network listeners (blocks until shutdown)
    let network_state = server_state.clone();
    let network_handle = tokio::spawn(async move {
        network::start_server(&config, network_state).await
    });

    // Wait for shutdown signal
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {
            info!("Shutdown signal received");
        }
        result = network_handle => {
            if let Err(e) = result {
                error!("Network server error: {}", e);
            }
        }
    }

    // Signal game loop to stop
    {
        let mut state = server_state.write().await;
        state.shutting_down = true;
    }

    // Wait for game loop to finish
    let _ = tick_handle.await;

    // Cleanup infrastructure
    infrastructure.shutdown().await?;
    info!("Server shutdown complete");

    Ok(())
}
