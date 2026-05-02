//! Authentication endpoints — login, register, refresh, whoami.
//!
//! Port of `AuthEndpoint.java`, `RegisterEndpoint.java`, `RefreshEndpoint.java`,
//! `WhoamiEndpoint.java`. Response shapes (JSON keys, status codes) match the
//! Java implementation exactly so existing clients work against either backend.

use axum::{
    body::Bytes,
    extract::{ConnectInfo, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use serde::{de::DeserializeOwned, Deserialize};
use serde_json::{json, Value};
use std::net::SocketAddr;
use tracing::warn;

use crate::api::jwt::DEFAULT_LIFETIME_MS;
use crate::api::rate_limit::identify;
use crate::api::ApiState;
use crate::database::DatabasePool;

use super::error_response;

const BEARER_PREFIX: &str = "Bearer ";

// --- Request DTOs ---------------------------------------------------------

#[derive(Deserialize)]
pub struct LoginRequest {
    username: Option<String>,
    password: Option<String>,
}

#[derive(Deserialize)]
pub struct RegisterRequest {
    username: Option<String>,
    password: Option<String>,
    email: Option<String>,
}

// --- Endpoints ------------------------------------------------------------

/// POST /api/auth/login. Rate-limited 10/60s/IP. Returns 200 with a JWT or
/// the canonical error shape on failure.
///
/// Folds "no such user" + "wrong password" into a single 401 — mirrors Java
/// to prevent username enumeration via timing/response differences.
pub async fn post_login(
    State(state): State<ApiState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    body: Bytes,
) -> (StatusCode, Json<Value>) {
    // Rate-limit before parsing the body — reject brute-force as cheaply as
    // possible.
    let identity = identify(&headers, Some(addr));
    if !state.login_limiter.allow(&identity) {
        let retry_secs = (state.login_limiter.retry_after_ms(&identity) + 999) / 1000;
        let mut resp = error_response(
            StatusCode::TOO_MANY_REQUESTS,
            "too many login attempts, slow down",
        );
        // Surface the retry-after via the JSON body (axum tuple responses
        // don't let us easily attach a header without a custom IntoResponse;
        // body field keeps the contract simple and observable).
        if let Value::Object(ref mut m) = *resp.1 {
            m.insert("retryAfterSeconds".into(), json!(retry_secs.max(1)));
        }
        return resp;
    }

    let req: LoginRequest = match parse_json_body(&body) {
        Ok(r) => r,
        Err(resp) => return resp,
    };
    let username = match req.username.as_deref().map(str::trim) {
        Some(s) if !s.is_empty() => s,
        _ => {
            return error_response(
                StatusCode::BAD_REQUEST,
                "username and password are required",
            )
        }
    };
    let password = match req.password.as_deref() {
        Some(s) if !s.is_empty() => s,
        _ => {
            return error_response(
                StatusCode::BAD_REQUEST,
                "username and password are required",
            )
        }
    };

    let canonical = canonicalize_username(username, 12);
    if canonical.is_empty() {
        return error_response(StatusCode::UNAUTHORIZED, "invalid credentials");
    }

    // Database lookup.
    let pool = match state.db_pool.as_ref() {
        Some(p) => p,
        None => {
            return error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                "database lookup failed",
            )
        }
    };

    let record = match fetch_player_by_username(pool, &canonical).await {
        Ok(r) => r,
        Err(e) => {
            warn!("login DB lookup failed for {}: {}", canonical, e);
            return error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                "database lookup failed",
            );
        }
    };

    let Some(record) = record else {
        // Fold no-such-user into the same 401 as wrong-password.
        return error_response(StatusCode::UNAUTHORIZED, "invalid credentials");
    };

    if !verify_password(password, &record.password_hash) {
        return error_response(StatusCode::UNAUTHORIZED, "invalid credentials");
    }
    if record.banned {
        return error_response(StatusCode::FORBIDDEN, "account is banned");
    }

    let token = state.jwt.generate_token(&canonical);
    let body = json!({
        "token": token,
        "username": canonical,
        "expiresIn": DEFAULT_LIFETIME_MS / 1000,
    });
    (StatusCode::OK, Json(body))
}

/// POST /api/auth/register. Rate-limited 3/hour/IP. Issues a JWT immediately
/// on success so the client doesn't need a separate /login round-trip.
pub async fn post_register(
    State(state): State<ApiState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    body: Bytes,
) -> (StatusCode, Json<Value>) {
    let identity = identify(&headers, Some(addr));
    if !state.register_limiter.allow(&identity) {
        let retry_secs = (state.register_limiter.retry_after_ms(&identity) + 999) / 1000;
        let mut resp = error_response(
            StatusCode::TOO_MANY_REQUESTS,
            "too many registration attempts",
        );
        if let Value::Object(ref mut m) = *resp.1 {
            m.insert("retryAfterSeconds".into(), json!(retry_secs.max(1)));
        }
        return resp;
    }

    let req: RegisterRequest = match parse_json_body(&body) {
        Ok(r) => r,
        Err(resp) => return resp,
    };
    let username = match req.username.as_deref().map(str::trim) {
        Some(s) if !s.is_empty() => s,
        _ => {
            return error_response(
                StatusCode::BAD_REQUEST,
                "username and password are required",
            )
        }
    };
    let password = match req.password.as_deref() {
        Some(s) if !s.is_empty() => s,
        _ => {
            return error_response(
                StatusCode::BAD_REQUEST,
                "username and password are required",
            )
        }
    };
    // Length bounds match `RegisterEndpoint.MIN_PASS_LEN` / `MAX_PASS_LEN`.
    if password.len() < 4 || password.len() > 20 {
        return error_response(
            StatusCode::BAD_REQUEST,
            "password must be between 4 and 20 characters",
        );
    }

    let canonical = canonicalize_username(username, 12);
    if canonical.is_empty() {
        return error_response(StatusCode::BAD_REQUEST, "invalid username");
    }

    let pool = match state.db_pool.as_ref() {
        Some(p) => p,
        None => {
            return error_response(StatusCode::SERVICE_UNAVAILABLE, "database write failed")
        }
    };

    // Username conflict check.
    match fetch_player_by_username(pool, &canonical).await {
        Ok(Some(_)) => {
            return error_response(StatusCode::CONFLICT, "username already taken");
        }
        Ok(None) => {}
        Err(e) => {
            warn!("register DB lookup failed: {}", e);
            return error_response(StatusCode::SERVICE_UNAVAILABLE, "database write failed");
        }
    }

    // Hash password with bcrypt at the same cost factor the Java side uses
    // (DEFAULT_COST = 10). Using bcrypt here means accounts created via this
    // endpoint can be verified by the Java server too.
    let hashed = match bcrypt::hash(password, bcrypt::DEFAULT_COST) {
        Ok(h) => h,
        Err(e) => {
            warn!("bcrypt hash failed: {}", e);
            return error_response(StatusCode::SERVICE_UNAVAILABLE, "could not create account");
        }
    };
    let email = req.email.as_deref().map(str::trim).unwrap_or("").to_string();

    let player_id = match insert_player(pool, &canonical, &hashed, &email, &identity).await {
        Ok(id) => id,
        Err(e) => {
            warn!("register DB insert failed: {}", e);
            return error_response(StatusCode::SERVICE_UNAVAILABLE, "could not create account");
        }
    };

    let token = state.jwt.generate_token(&canonical);
    let body = json!({
        "playerId": player_id,
        "username": canonical,
        "token": token,
        "expiresIn": DEFAULT_LIFETIME_MS / 1000,
    });
    (StatusCode::CREATED, Json(body))
}

/// POST /api/auth/refresh. Requires a still-valid Bearer token; reissues a
/// fresh one with a 24h lifetime. Mirrors Java's `RefreshEndpoint`.
pub async fn post_refresh(
    State(state): State<ApiState>,
    headers: HeaderMap,
) -> (StatusCode, Json<Value>) {
    let token = match extract_bearer(&headers) {
        Ok(t) => t,
        Err(resp) => return resp,
    };
    let claims = match state.jwt.verify(&token) {
        Some(c) => c,
        None => {
            return error_response(
                StatusCode::UNAUTHORIZED,
                "invalid or expired token (login again)",
            )
        }
    };

    let new_token = state.jwt.generate_token(&claims.username);
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let new_expires_at = (now_ms + DEFAULT_LIFETIME_MS) / 1000;

    let body = json!({
        "token": new_token,
        "username": claims.username,
        "expiresIn": DEFAULT_LIFETIME_MS / 1000,
        "expiresAt": new_expires_at,
    });
    (StatusCode::OK, Json(body))
}

/// GET /api/auth/whoami. Verifies a Bearer token and echoes back the claims.
pub async fn get_whoami(
    State(state): State<ApiState>,
    headers: HeaderMap,
) -> (StatusCode, Json<Value>) {
    let token = match extract_bearer(&headers) {
        Ok(t) => t,
        Err(resp) => return resp,
    };
    let claims = match state.jwt.verify(&token) {
        Some(c) => c,
        None => return error_response(StatusCode::UNAUTHORIZED, "invalid or expired token"),
    };

    let body = json!({
        "username": claims.username,
        "expiresAt": claims.expires_at_ms / 1000,
        "issuedAt": claims.issued_at_ms / 1000,
    });
    (StatusCode::OK, Json(body))
}

// --- Helpers --------------------------------------------------------------

/// Parse a JSON request body. Returns a 400 error response on empty body or
/// malformed JSON. Mirrors Java's `JsonHandler.parse` + the catch-all error
/// path in each endpoint.
fn parse_json_body<T: DeserializeOwned>(
    body: &Bytes,
) -> Result<T, (StatusCode, Json<Value>)> {
    if body.is_empty() {
        return Err(error_response(StatusCode::BAD_REQUEST, "malformed JSON body"));
    }
    serde_json::from_slice::<T>(body)
        .map_err(|_| error_response(StatusCode::BAD_REQUEST, "malformed JSON body"))
}

/// Pull the bearer token out of the Authorization header. Returns the raw
/// token on success, or a pre-built 401 response on the various malformed
/// cases (mirrors Java's WhoamiEndpoint header handling).
fn extract_bearer(headers: &HeaderMap) -> Result<String, (StatusCode, Json<Value>)> {
    let header = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .ok_or_else(|| {
            error_response(
                StatusCode::UNAUTHORIZED,
                "missing or malformed Authorization header (expected: Bearer <token>)",
            )
        })?;
    if !header.starts_with(BEARER_PREFIX) {
        return Err(error_response(
            StatusCode::UNAUTHORIZED,
            "missing or malformed Authorization header (expected: Bearer <token>)",
        ));
    }
    let token = header[BEARER_PREFIX.len()..].trim().to_string();
    if token.is_empty() {
        return Err(error_response(
            StatusCode::UNAUTHORIZED,
            "empty bearer token",
        ));
    }
    Ok(token)
}

/// Lowercase + sanitise a username to the canonical form. Mirrors Java's
/// `DataConversions.normalize(s, len)`:
///   - take the first `len` chars; pad to `len` with spaces if shorter
///   - replace any non-[a-zA-Z0-9] with '_'
///   - collapse runs of whitespace + underscores into a single '_'
///   - strip leading/trailing underscores by converting to space
///   - lowercase, trim
///
/// `pub(super)` so other endpoint modules (character lookup) can reuse it.
pub(super) fn canonicalize_username(s: &str, len: usize) -> String {
    // Step 1: addCharacters
    let mut padded = String::with_capacity(len);
    let chars: Vec<char> = s.chars().collect();
    for j in 0..len {
        if j >= chars.len() {
            padded.push(' ');
        } else {
            let c = chars[j];
            if c.is_ascii_alphanumeric() {
                padded.push(c);
            } else {
                padded.push('_');
            }
        }
    }

    // Step 2: collapse [\s_]+ -> _
    let mut collapsed = String::with_capacity(padded.len());
    let mut prev_underscoreable = false;
    for c in padded.chars() {
        let is_underscoreable = c == '_' || c.is_whitespace();
        if is_underscoreable {
            if !prev_underscoreable {
                collapsed.push('_');
            }
        } else {
            collapsed.push(c);
        }
        prev_underscoreable = is_underscoreable;
    }

    // Step 3: trim, then convert leading/trailing '_' to ' '
    let mut buf: Vec<char> = collapsed.trim().chars().collect();
    if let Some(first) = buf.first_mut() {
        if *first == '_' {
            *first = ' ';
        }
    }
    if let Some(last) = buf.last_mut() {
        if *last == '_' {
            *last = ' ';
        }
    }

    // Step 4: lowercase + trim
    buf.iter()
        .collect::<String>()
        .to_lowercase()
        .trim()
        .to_string()
}

/// bcrypt-verify the supplied password against the stored hash. Returns
/// false on any error (malformed hash, wrong password, etc.).
fn verify_password(password: &str, hash: &str) -> bool {
    bcrypt::verify(password, hash).unwrap_or(false)
}

/// Internal slim view of `players.username, password_hash, banned` — only
/// what the auth flow needs. Avoids loading the full `PlayerRecord`'s many
/// columns just to check credentials.
struct AuthRecord {
    password_hash: String,
    banned: bool,
}

async fn fetch_player_by_username(
    pool: &DatabasePool,
    username: &str,
) -> Result<Option<AuthRecord>, sqlx::Error> {
    use sqlx::Row;
    let q = "SELECT password_hash, banned FROM players WHERE username = ?";
    match pool {
        DatabasePool::MySql(pool) => {
            let row = sqlx::query(q)
                .bind(username)
                .fetch_optional(pool)
                .await?;
            Ok(row.map(|r| AuthRecord {
                password_hash: r.get("password_hash"),
                banned: r.get("banned"),
            }))
        }
        DatabasePool::Sqlite(pool) => {
            let row = sqlx::query(q)
                .bind(username)
                .fetch_optional(pool)
                .await?;
            Ok(row.map(|r| AuthRecord {
                password_hash: r.get("password_hash"),
                banned: r.get("banned"),
            }))
        }
    }
}

async fn insert_player(
    pool: &DatabasePool,
    username: &str,
    password_hash: &str,
    email: &str,
    login_ip: &str,
) -> Result<i64, sqlx::Error> {
    let creation_date = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let q = "INSERT INTO players (username, password_hash, email, creation_date, login_ip) \
             VALUES (?, ?, ?, ?, ?)";
    match pool {
        DatabasePool::MySql(pool) => {
            let res = sqlx::query(q)
                .bind(username)
                .bind(password_hash)
                .bind(if email.is_empty() { None } else { Some(email) })
                .bind(creation_date)
                .bind(login_ip)
                .execute(pool)
                .await?;
            Ok(res.last_insert_id() as i64)
        }
        DatabasePool::Sqlite(pool) => {
            let res = sqlx::query(q)
                .bind(username)
                .bind(password_hash)
                .bind(if email.is_empty() { None } else { Some(email) })
                .bind(creation_date)
                .bind(login_ip)
                .execute(pool)
                .await?;
            Ok(res.last_insert_rowid())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonicalize_basic() {
        assert_eq!(canonicalize_username("Alice", 12), "alice");
        assert_eq!(canonicalize_username("BOB", 12), "bob");
    }

    #[test]
    fn canonicalize_replaces_specials() {
        // '!' is not alphanumeric -> becomes '_', then collapsed/trimmed
        assert_eq!(canonicalize_username("a!b", 12), "a_b");
    }

    #[test]
    fn canonicalize_truncates() {
        assert_eq!(
            canonicalize_username("ABCDEFGHIJKLMNOP", 12),
            "abcdefghijkl"
        );
    }

    #[test]
    fn canonicalize_empty() {
        assert_eq!(canonicalize_username("", 12), "");
    }
}
