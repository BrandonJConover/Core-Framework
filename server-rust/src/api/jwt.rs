//! Minimal HS256 JWT issuer + verifier.
//!
//! Port of `JwtUtil.java`. We deliberately do NOT pull in the `jsonwebtoken`
//! crate — HS256 is small enough to roll on top of `hmac` + `sha2` + `base64`,
//! all of which are already in `Cargo.toml`. If we ever need RS256 / EdDSA /
//! key rotation, swap in `jsonwebtoken` at that point; for the symmetric
//! single-issuer single-verifier case, a custom impl is ~120 lines and avoids
//! a dependency.
//!
//! # Token shape
//!
//!   header  : {"alg":"HS256","typ":"JWT"}
//!   payload : {"iss":"<server-name>","sub":"<username>","iat":<unix-s>,"exp":<unix-s>}
//!   signature : base64url(HMAC-SHA256(secret, base64url(header) + "." + base64url(payload)))
//!
//! Exact wire compatibility with Java's `auth0/java-jwt`: the Java side issues
//! tokens with the same claim set. A token issued by either side can be
//! verified by the other as long as the secret file is shared.
//!
//! # Secret persistence
//!
//! Secret is loaded from `.jwt-secret` in the cwd, or generated and written
//! with mode 0600 if missing. Survives restarts so 24-hour tokens stay valid
//! across normal server bounces. Delete the file to force-rotate.

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use hmac::{Hmac, Mac};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};
use tracing::{info, warn};

type HmacSha256 = Hmac<Sha256>;

/// Default JWT lifetime in milliseconds (24 hours). Mirrors Java's
/// `JwtUtil.DEFAULT_LIFETIME_MS`.
pub const DEFAULT_LIFETIME_MS: u64 = 24 * 60 * 60 * 1000;

/// Default file the signing secret is persisted to. Relative to cwd; matches
/// Java's `JwtUtil.DEFAULT_SECRET_PATH`. Must be in `.gitignore`.
pub const DEFAULT_SECRET_PATH: &str = ".jwt-secret";

/// Decoded claim set surfaced to endpoints. Hides the raw bytes.
#[derive(Debug, Clone)]
pub struct Claims {
    pub username: String,
    pub issued_at_ms: u64,
    pub expires_at_ms: u64,
}

/// HMAC-SHA256 JWT issuer + verifier. Cheap to share — no per-token state.
pub struct JwtUtil {
    secret: Vec<u8>,
    issuer: String,
}

#[derive(Serialize, Deserialize)]
struct Header {
    alg: String,
    typ: String,
}

#[derive(Serialize, Deserialize)]
struct Payload {
    iss: String,
    sub: String,
    iat: u64,
    exp: u64,
}

impl JwtUtil {
    /// Build with the default secret path (`.jwt-secret`).
    pub fn with_default_secret_path(issuer: impl Into<String>) -> Self {
        Self::new(issuer, PathBuf::from(DEFAULT_SECRET_PATH))
    }

    /// Build with a custom secret path. The file is created on first run if
    /// missing; restrictive POSIX perms (0600) are applied best-effort.
    pub fn new(issuer: impl Into<String>, secret_path: PathBuf) -> Self {
        let secret = load_or_create_secret(&secret_path);
        Self {
            secret,
            issuer: issuer.into(),
        }
    }

    /// Issue a token with the default 24-hour lifetime.
    pub fn generate_token(&self, username: &str) -> String {
        self.generate_token_with_lifetime(username, DEFAULT_LIFETIME_MS)
    }

    /// Issue a token with a custom lifetime in milliseconds.
    pub fn generate_token_with_lifetime(&self, username: &str, lifetime_ms: u64) -> String {
        let now_ms = current_time_ms();
        let header = Header {
            alg: "HS256".to_string(),
            typ: "JWT".to_string(),
        };
        let payload = Payload {
            iss: self.issuer.clone(),
            sub: username.to_string(),
            iat: now_ms / 1000,
            exp: (now_ms + lifetime_ms) / 1000,
        };

        // Hand-rolling JSON would be cheaper but serde_json keeps key order
        // deterministic enough for our purposes and matches the auth0 lib's
        // output precisely (order: header alg/typ, payload iss/sub/iat/exp).
        let header_b64 = b64url(&serde_json::to_vec(&header).expect("header serializes"));
        let payload_b64 = b64url(&serde_json::to_vec(&payload).expect("payload serializes"));

        let signing_input = format!("{}.{}", header_b64, payload_b64);
        let signature = sign(&self.secret, signing_input.as_bytes());
        let signature_b64 = b64url(&signature);

        format!("{}.{}", signing_input, signature_b64)
    }

    /// Verify a token's signature, issuer, and expiry. Returns `None` on any
    /// failure — endpoints short-circuit to 401 without needing to know why.
    pub fn verify(&self, token: &str) -> Option<Claims> {
        let mut parts = token.splitn(3, '.');
        let header_b64 = parts.next()?;
        let payload_b64 = parts.next()?;
        let signature_b64 = parts.next()?;
        if parts.next().is_some() {
            return None; // more than three segments
        }

        // Verify signature first so we don't trust the payload until proven.
        let signing_input = format!("{}.{}", header_b64, payload_b64);
        let provided_sig = b64url_decode(signature_b64).ok()?;
        let mut mac = HmacSha256::new_from_slice(&self.secret).ok()?;
        mac.update(signing_input.as_bytes());
        // verify_slice is constant-time per `hmac` docs — safe against
        // timing oracles.
        mac.verify_slice(&provided_sig).ok()?;

        // Header check: must be HS256/JWT. Reject otherwise to avoid
        // alg-confusion attacks.
        let header_bytes = b64url_decode(header_b64).ok()?;
        let header: Header = serde_json::from_slice(&header_bytes).ok()?;
        if header.alg != "HS256" || header.typ != "JWT" {
            return None;
        }

        let payload_bytes = b64url_decode(payload_b64).ok()?;
        let payload: Payload = serde_json::from_slice(&payload_bytes).ok()?;

        // Issuer match — refuses tokens minted by a different server.
        if payload.iss != self.issuer {
            return None;
        }

        // Expiry check — exp is in unix seconds.
        let now_secs = current_time_ms() / 1000;
        if payload.exp <= now_secs {
            return None;
        }

        Some(Claims {
            username: payload.sub,
            issued_at_ms: payload.iat * 1000,
            expires_at_ms: payload.exp * 1000,
        })
    }

    /// Convenience: verify and return only the username (subject), or `None`.
    pub fn verify_and_get_username(&self, token: &str) -> Option<String> {
        self.verify(token).map(|c| c.username)
    }
}

fn b64url(bytes: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

fn b64url_decode(s: &str) -> Result<Vec<u8>, base64::DecodeError> {
    URL_SAFE_NO_PAD.decode(s)
}

fn sign(secret: &[u8], message: &[u8]) -> Vec<u8> {
    let mut mac = HmacSha256::new_from_slice(secret).expect("HMAC accepts any key length");
    mac.update(message);
    mac.finalize().into_bytes().to_vec()
}

fn current_time_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Load the persisted secret or write a fresh one. Mirrors Java's
/// `loadOrCreateSecret`. The file content is the hex-encoded 32-byte
/// secret; we store the bytes-as-hex (not raw bytes) so the file is
/// printable and matches the Java implementation byte-for-byte — meaning
/// a Java-issued token can be verified here and vice versa.
fn load_or_create_secret(path: &Path) -> Vec<u8> {
    if let Ok(content) = std::fs::read_to_string(path) {
        let trimmed = content.trim();
        if trimmed.len() >= 32 {
            info!("JwtUtil loaded persisted secret from {}", path.display());
            // Java treats the hex string AS the secret (passes the string
            // straight to Algorithm.HMAC256(String)). We must do the same:
            // hash the string bytes, not the decoded hex bytes. Otherwise
            // tokens won't cross-verify.
            return trimmed.as_bytes().to_vec();
        }
        warn!(
            "JwtUtil secret file {} is too short ({} chars); regenerating",
            path.display(),
            trimmed.len()
        );
    }

    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    let hex_secret: String = bytes.iter().map(|b| format!("{:02x}", b)).collect();

    if let Err(e) = std::fs::write(path, &hex_secret) {
        warn!(
            "JwtUtil could not persist secret to {}: {}; tokens will not survive restart this run",
            path.display(),
            e
        );
    } else {
        // Best-effort POSIX 0600. On non-Unix this no-ops.
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if let Ok(meta) = std::fs::metadata(path) {
                let mut perms = meta.permissions();
                perms.set_mode(0o600);
                let _ = std::fs::set_permissions(path, perms);
            }
        }
        info!(
            "JwtUtil generated new secret and wrote to {} (owner-only)",
            path.display()
        );
    }
    hex_secret.into_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn temp_secret_path() -> PathBuf {
        let mut p = std::env::temp_dir();
        p.push(format!(
            "openrsc-jwt-test-{}-{}.secret",
            std::process::id(),
            rand::random::<u32>()
        ));
        p
    }

    #[test]
    fn round_trip_token() {
        let path = temp_secret_path();
        let jwt = JwtUtil::new("test-issuer", path.clone());
        let token = jwt.generate_token("alice");
        let claims = jwt.verify(&token).expect("token must verify");
        assert_eq!(claims.username, "alice");
        assert!(claims.expires_at_ms > claims.issued_at_ms);
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn rejects_tampered_payload() {
        let path = temp_secret_path();
        let jwt = JwtUtil::new("test-issuer", path.clone());
        let token = jwt.generate_token("alice");
        // Flip a character in the payload section.
        let mut parts: Vec<&str> = token.split('.').collect();
        let bad_payload = format!("{}A", parts[1]);
        parts[1] = &bad_payload;
        let bad = parts.join(".");
        assert!(jwt.verify(&bad).is_none());
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn rejects_wrong_issuer() {
        let path = temp_secret_path();
        let jwt_a = JwtUtil::new("issuer-a", path.clone());
        let jwt_b = JwtUtil::new("issuer-b", path.clone());
        let token = jwt_a.generate_token("alice");
        // Both share the same secret file but the issuer claim doesn't match.
        assert!(jwt_b.verify(&token).is_none());
        let _ = std::fs::remove_file(path);
    }
}
