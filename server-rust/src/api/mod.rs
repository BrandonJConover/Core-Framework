//! Modern client REST API.
//!
//! Port of `server-java-modern/src/com/openrsc/server/net/api/` to axum.
//!
//! # Routes
//!
//!   GET  /api/status              — public, server status snapshot
//!   GET  /healthz                 — alias for /api/status (for k8s/uptime probes)
//!   POST /api/auth/login          — username + password -> JWT (rate-limited 10/60s/IP)
//!   POST /api/auth/register       — create account -> JWT (rate-limited 3/hour/IP)
//!   POST /api/auth/refresh        — rotate JWT, requires valid current token
//!   GET  /api/auth/whoami         — verify Bearer token, return claims
//!   GET  /api/players/online      — public listing of currently logged-in players
//!   GET  /api/character/{username}— online or offline character profile lookup
//!
//! # Wiring
//!
//! Call `start_api_server(addr, state)` from main / an orchestrator. The
//! returned future runs the listener until the OS closes the socket. The
//! function does not return on its own under normal operation.
//!
//! Database access goes through the optional `db_pool` field on `ApiState`.
//! Endpoints that hit the DB (login, register, offline character lookup)
//! return 503 if the pool is `None`; the orchestrator is expected to plumb
//! one in when calling `ApiState::new`.

pub mod endpoints;
pub mod jwt;
pub mod rate_limit;
pub mod router;
pub mod ticket;

use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::info;

use crate::database::DatabasePool;
use crate::game::server::ServerState;

pub use jwt::JwtUtil;
pub use rate_limit::RateLimiter;
pub use ticket::LoginTicketService;

/// Default port for the modern client REST API.
///
/// Matches Java's `ApiServer.DEFAULT_PORT`. Reverse-proxied behind nginx in
/// production; raw socket for local dev. Bind on the loopback in production
/// so external traffic must come through the proxy (which sets X-Forwarded-For).
pub const DEFAULT_PORT: u16 = 43595;

/// Shared state passed to every endpoint via axum's `State` extractor.
///
/// Cloning is cheap — internals are all `Arc`-wrapped — so axum's idiomatic
/// `State<ApiState>` (which clones per request) is fine.
#[derive(Clone)]
pub struct ApiState {
    /// Live game state. Endpoints take a read lock for online lookups.
    pub server: Arc<RwLock<ServerState>>,

    /// Optional connection pool. `None` = DB endpoints will return 503.
    /// The orchestrator should set this before exposing the API publicly;
    /// `start_api_server` accepts a pre-built `ApiState` if you need more
    /// control.
    pub db_pool: Option<DatabasePool>,

    /// JWT issuer + verifier. Constructed on startup from the persisted
    /// secret in `.jwt-secret` (or freshly generated).
    pub jwt: Arc<JwtUtil>,

    /// Per-IP rate limiter for /api/auth/login. 10 requests / 60s.
    pub login_limiter: Arc<RateLimiter>,

    /// Per-IP rate limiter for /api/auth/register. 3 requests / 1h.
    pub register_limiter: Arc<RateLimiter>,

    /// Server name used as the JWT `iss` claim and surfaced in /api/status.
    pub server_name: String,

    /// Configured player cap (mirrors `ServerConfiguration.MAX_PLAYERS` in
    /// Java). Surfaced in /api/status.
    pub player_limit: usize,

    /// One-shot ticket store for the launcher → game-client handoff. Cloned
    /// (shared `Arc` inside) into `ServerState` so the LOGIN packet handler
    /// can consume tickets issued by `/api/auth/game-ticket`.
    pub tickets: LoginTicketService,
}

impl ApiState {
    /// Build a new `ApiState` with default rate-limit budgets, a fresh
    /// `JwtUtil`, and no database. Most callers should prefer the convenience
    /// constructors below or build the struct literally.
    pub fn new(
        server: Arc<RwLock<ServerState>>,
        db_pool: Option<DatabasePool>,
        server_name: impl Into<String>,
    ) -> Self {
        let server_name = server_name.into();
        Self {
            server,
            db_pool,
            // 10 logins / 60s and 3 registrations / 1h match the Java budgets
            // exactly. See ApiServer.buildRouter() for the rationale.
            login_limiter: Arc::new(RateLimiter::new(60_000, 10)),
            register_limiter: Arc::new(RateLimiter::new(60 * 60_000, 3)),
            jwt: Arc::new(JwtUtil::with_default_secret_path(server_name.clone())),
            server_name,
            // Mirror ServerState::MAX_PLAYERS. Orchestrator can override
            // by mutating the field after construction if it has a config.
            player_limit: crate::game::server::MAX_PLAYERS,
            tickets: LoginTicketService::new(),
        }
    }
}

/// Bind and serve the REST API on `addr`. Returns when the server stops
/// (process shutdown, listener error). Mirrors the Java `ApiServer.start()`.
///
/// This function constructs an `ApiState` with no DB pool. If you need a DB
/// (for login/register/offline character), build `ApiState` manually and call
/// `start_api_server_with_state`.
pub async fn start_api_server(
    addr: SocketAddr,
    state: Arc<RwLock<ServerState>>,
) -> anyhow::Result<()> {
    // Pull the server name from the state for the JWT `iss` claim.
    // Falls back to a static name if the state hasn't recorded one yet
    // (it doesn't expose a name field today; orchestrator can override).
    let server_name = "OpenRSC".to_string();
    let api_state = ApiState::new(state, None, server_name);
    start_api_server_with_state(addr, api_state).await
}

/// Like [`start_api_server`] but takes a pre-built `ApiState`. Use this
/// when wiring the database pool, custom rate-limit budgets, or a
/// non-default JWT secret path.
pub async fn start_api_server_with_state(addr: SocketAddr, state: ApiState) -> anyhow::Result<()> {
    let app = router::build_router(state);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    info!("API listener online on {}", addr);
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await?;
    Ok(())
}
