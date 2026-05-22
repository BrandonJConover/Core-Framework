//! Axum router that wires every endpoint module together.
//!
//! Mirror of Java's `ApiServer.buildRouter()`. Routes are intentionally
//! enumerated here so the API surface is grep-able from one file.

use axum::{
    routing::{get, post},
    Router,
};

use super::endpoints;
use super::ApiState;

/// Build the axum router with all API routes. Stateful — captures `ApiState`.
pub fn build_router(state: ApiState) -> Router {
    Router::new()
        // Status / health
        .route("/api/status", get(endpoints::status::get_status))
        .route("/healthz", get(endpoints::status::get_status))
        // Auth
        .route("/api/auth/login", post(endpoints::auth::post_login))
        .route("/api/auth/register", post(endpoints::auth::post_register))
        .route("/api/auth/refresh", post(endpoints::auth::post_refresh))
        .route("/api/auth/whoami", get(endpoints::auth::get_whoami))
        .route(
            "/api/auth/game-ticket",
            post(endpoints::auth::post_game_ticket),
        )
        // Players
        .route("/api/players/online", get(endpoints::players::get_online))
        // Character — axum 0.7 path-param syntax is `:name`, not `{name}`.
        // Wire format for clients is identical (HTTP path); just the route
        // string changes.
        .route(
            "/api/character/:username",
            get(endpoints::character::get_character),
        )
        .with_state(state)
}
