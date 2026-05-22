mod api;
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
use tracing::{error, info, warn};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use api::{ApiState, LoginTicketService};
use database::player_repository::PlayerRepository;
use database::{schema, DatabaseConfig, DatabasePool, DatabaseType};
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

    info!(
        "Starting OpenRSC Rust Server v{}",
        env!("CARGO_PKG_VERSION")
    );

    // Load configuration
    let config = infrastructure::config::ServerConfig::load()?;
    info!("Configuration loaded for world: {}", config.world_name);

    // Initialize infrastructure (metrics, redis, tracing, discovery)
    let mut infrastructure = InfrastructureManager::new(config.clone());
    infrastructure.initialize().await?;
    info!("Infrastructure initialized");

    // Optionally bring up the DB pool + ensure schema exists.
    // When config.database.enabled = false (default), the server runs in
    // accept-all auth mode with no persistence — see ServerState::players.
    let player_repo: Option<Arc<PlayerRepository>> = if config.database.enabled {
        let db_cfg = DatabaseConfig {
            db_type: DatabaseType::from(config.database.kind.as_str()),
            host: config.database.host.clone(),
            port: config.database.port,
            database: if matches!(
                DatabaseType::from(config.database.kind.as_str()),
                DatabaseType::Sqlite
            ) {
                config.database.sqlite_path.clone()
            } else {
                config.database.database.clone()
            },
            username: config.database.username.clone(),
            password: config.database.password.clone(),
            ..DatabaseConfig::default()
        };
        match DatabasePool::new(&db_cfg).await {
            Ok(pool) => {
                if let Err(e) = schema::init_schema(&pool).await {
                    warn!(
                        "Schema init failed: {} — server will run without persistence",
                        e
                    );
                    None
                } else {
                    Some(Arc::new(PlayerRepository::new(pool)))
                }
            }
            Err(e) => {
                warn!(
                    "DB connect failed: {} — server will run without persistence",
                    e
                );
                None
            }
        }
    } else {
        info!("DB persistence disabled (config.database.enabled = false)");
        None
    };

    // One ticket service shared between the HTTP API (issues tickets) and
    // ServerState (consumes them in the LOGIN packet handler).
    let tickets = LoginTicketService::new();

    // Create shared server state, optionally with DB-backed auth + persistence.
    let mut initial_state = ServerState::new()
        .with_tickets(tickets.clone())
        .with_max_sessions_per_ip(config.max_sessions_per_ip);
    if let Some(repo) = player_repo.clone() {
        initial_state = initial_state.with_players(repo);
        info!("ServerState wired with DB-backed PlayerRepository");
    }
    let server_state = Arc::new(RwLock::new(initial_state));
    {
        let mut state = server_state.write().await;
        state.initialize().await?;
    }
    info!("Game state initialized");

    // Spawn HTTP API listener (login, register, game-ticket, status). The
    // ApiState shares the same LoginTicketService instance as ServerState so
    // tickets issued via /api/auth/game-ticket are consumable by the LOGIN
    // packet handler.
    let api_state = ApiState {
        server: server_state.clone(),
        db_pool: player_repo.as_ref().map(|r| r.pool().clone()),
        jwt: Arc::new(api::JwtUtil::with_default_secret_path(
            config.world_name.clone(),
        )),
        login_limiter: Arc::new(api::RateLimiter::new(60_000, 10)),
        register_limiter: Arc::new(api::RateLimiter::new(60 * 60_000, 3)),
        server_name: config.world_name.clone(),
        player_limit: game::server::MAX_PLAYERS,
        tickets: tickets.clone(),
    };
    let api_addr: std::net::SocketAddr = format!("0.0.0.0:{}", config.api_port).parse()?;
    tokio::spawn(async move {
        if let Err(e) = api::start_api_server_with_state(api_addr, api_state).await {
            error!("HTTP API server error: {}", e);
        }
    });

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
    let network_handle =
        tokio::spawn(async move { network::start_server(&config, network_state).await });

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
