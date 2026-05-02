//! HTTP endpoint handlers for the modern client REST API.
//!
//! Each submodule mirrors one Java endpoint class. They all take `State<ApiState>`
//! and return `(StatusCode, Json<Value>)` so axum's response machinery handles
//! content-type and content-length automatically — no equivalent of the Java
//! `JsonHandler` is required.

pub mod auth;
pub mod character;
pub mod players;
pub mod status;

use axum::http::StatusCode;
use axum::Json;
use serde_json::{json, Value};

/// Canonical error shape: `{"error":"...","status":N}`. Mirrors Java's
/// `JsonHandler.error()`.
pub(crate) fn error_response(status: StatusCode, message: &str) -> (StatusCode, Json<Value>) {
    (
        status,
        Json(json!({
            "error": message,
            "status": status.as_u16(),
        })),
    )
}
