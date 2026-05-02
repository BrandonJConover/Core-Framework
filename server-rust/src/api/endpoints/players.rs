//! GET /api/players/online — public listing of currently logged-in players.
//!
//! Port of `OnlinePlayersEndpoint.java`. Public, unauthenticated. Exposes only
//! username + combat level — no location, no equipment, no IP. Mirrors Java's
//! privacy posture exactly.

use axum::{extract::State, http::StatusCode, Json};
use serde_json::{json, Value};

use crate::api::ApiState;
use crate::session::SessionState;

/// Build the online-players payload. Iterates the session manager (the
/// authoritative source for "who's currently logged in"), pulls each
/// session's attached player Arc, and emits a `{username, combatLevel}`
/// object per logged-in session.
///
/// Java version filters out admin-invisible players via
/// `Player.stateIsInvisible()`. The Rust `Player` struct doesn't track an
/// `invisible` flag yet — orchestrator can add one and gate filtering here
/// behind it. For now nobody is "invisible" so all logged-in players show.
pub async fn get_online(State(state): State<ApiState>) -> (StatusCode, Json<Value>) {
    let server = state.server.read().await;
    let sessions = server.sessions.all_sessions();
    drop(server); // release the ServerState lock asap; per-session locks come next

    let mut entries: Vec<Value> = Vec::new();
    for session in sessions {
        let s = session.read().await;
        if s.state != SessionState::LoggedIn {
            continue;
        }
        let Some(ref player_arc) = s.player else {
            continue;
        };
        let p = player_arc.read().await;
        // TODO: honor an `invisible` flag once Player carries one.
        entries.push(json!({
            "username": p.username,
            "combatLevel": p.combat_level,
        }));
    }

    let body = json!({
        "count": entries.len(),
        "players": entries,
    });
    (StatusCode::OK, Json(body))
}
