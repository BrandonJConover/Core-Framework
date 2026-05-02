//! GET /api/status (and the /healthz alias).
//!
//! Port of `StatusEndpoint.java`. Public, unauthenticated, always cheap —
//! reads only volatile counters, never touches the DB or the tick loop.

use axum::{extract::State, http::StatusCode, Json};
use serde_json::{json, Value};

use crate::api::ApiState;

/// Build the status payload. Field names match the Java response exactly so
/// existing launcher / web clients keep parsing without changes.
pub async fn get_status(State(state): State<ApiState>) -> (StatusCode, Json<Value>) {
    let server = state.server.read().await;

    // Uptime: ServerState exposes a `start_time: Instant` and `tick_count: u64`,
    // both public. We read them under a single lock to keep them consistent.
    let uptime_ms = server.start_time.elapsed().as_millis() as u64;
    let current_tick = server.tick_count;

    // Player count: derive from the session manager's logged-in count. The
    // game-state HashMap of players is private; the SessionManager view is
    // what's exposed and mirrors the Java `World.getPlayers().size()` count.
    let player_count = server.sessions.logged_in_count();

    // Server is "up" if the tick loop hasn't been told to shut down. When
    // `shutting_down` flips true, the next status hit will reflect it.
    let up = !server.shutting_down;

    drop(server);

    let body = json!({
        "up": up,
        "name": state.server_name,
        "playerCount": player_count,
        "playerLimit": state.player_limit,
        "uptimeMs": uptime_ms,
        // Java surfaces the last-tick wall-clock duration in ms; we don't
        // record per-tick duration in ServerState today, so report 0. If the
        // orchestrator wants a real value, add a `last_tick_duration_ms`
        // field to ServerState and wire it here.
        "lastTickMs": 0,
        "currentTick": current_tick,
    });

    (StatusCode::OK, Json(body))
}
