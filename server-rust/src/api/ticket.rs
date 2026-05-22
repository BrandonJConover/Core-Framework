//! One-shot login tickets for the launcher → game-client handoff.
//!
//! Mirror of `server-java-modern/.../GameLoginTicketService.java`. The web
//! launcher authenticates over HTTPS via `/api/auth/login`, then asks
//! `/api/auth/game-ticket` for a short-lived ticket. The browser stuffs that
//! ticket into the password slot of the regular RSC LOGIN packet; the game
//! server consumes it during login, bypassing the bcrypt check without
//! teaching the C client a new auth protocol.
//!
//! Wire format: `"t" + 16 random alphanumeric chars`. The "t" prefix tells the
//! login handler to take the ticket path instead of bcrypt-verify.

use dashmap::DashMap;
use rand::distributions::{Alphanumeric, DistString};
use std::sync::Arc;
use std::time::{Duration, Instant};

/// Default ticket TTL — matches Java's `DEFAULT_LIFETIME_MS` (10 min).
pub const DEFAULT_LIFETIME: Duration = Duration::from_secs(10 * 60);

/// Wire prefix that marks a string as a ticket rather than a bcrypt password.
pub const TICKET_PREFIX: &str = "t";

const TOKEN_LEN: usize = 16;

#[derive(Debug, Clone)]
struct TicketRecord {
    username: String,
    expires_at: Instant,
}

/// Concurrent, lock-free ticket store. Cheap to clone (`Arc` inside).
#[derive(Clone)]
pub struct LoginTicketService {
    inner: Arc<DashMap<String, TicketRecord>>,
    lifetime: Duration,
}

impl LoginTicketService {
    pub fn new() -> Self {
        Self::with_lifetime(DEFAULT_LIFETIME)
    }

    pub fn with_lifetime(lifetime: Duration) -> Self {
        Self {
            inner: Arc::new(DashMap::new()),
            lifetime,
        }
    }

    /// Issue a one-shot ticket for `username`. Returns the wire-format string
    /// (with the `"t"` prefix) ready to be returned over HTTP.
    pub fn issue(&self, username: &str) -> String {
        self.purge_expired();
        let raw = Alphanumeric.sample_string(&mut rand::thread_rng(), TOKEN_LEN);
        let expires_at = Instant::now() + self.lifetime;
        self.inner.insert(
            raw.clone(),
            TicketRecord {
                username: username.to_string(),
                expires_at,
            },
        );
        format!("{TICKET_PREFIX}{raw}")
    }

    /// Validate-and-remove a ticket. Returns true exactly once per issuance:
    /// the second `consume` of the same ticket fails. Username must match
    /// the original `issue` call.
    pub fn consume(&self, username: &str, password: &str) -> bool {
        let Some(raw) = strip_prefix(password) else {
            return false;
        };
        // Inspect first; only remove on a successful match. Removing
        // unconditionally would let a wrong-user attempt silently burn the
        // ticket and lock out the real owner.
        let valid = match self.inner.get(raw) {
            Some(rec) => rec.expires_at >= Instant::now() && rec.username == username,
            None => false,
        };
        if valid {
            self.inner.remove(raw);
            true
        } else {
            false
        }
    }

    /// Read-only check (does NOT consume). Useful for health-check endpoints
    /// that want to verify a ticket is still live without burning it.
    pub fn is_valid(&self, username: &str, password: &str) -> bool {
        let Some(raw) = strip_prefix(password) else {
            return false;
        };
        let Some(record) = self.inner.get(raw) else {
            return false;
        };
        record.expires_at >= Instant::now() && record.username == username
    }

    /// Lifetime that newly-issued tickets advertise to the launcher.
    pub fn lifetime_secs(&self) -> u64 {
        self.lifetime.as_secs()
    }

    fn purge_expired(&self) {
        let now = Instant::now();
        self.inner.retain(|_, record| record.expires_at >= now);
    }
}

impl Default for LoginTicketService {
    fn default() -> Self {
        Self::new()
    }
}

fn strip_prefix(password: &str) -> Option<&str> {
    let raw = password.strip_prefix(TICKET_PREFIX)?.trim();
    if raw.is_empty() {
        None
    } else {
        Some(raw)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let svc = LoginTicketService::new();
        let ticket = svc.issue("alice");
        assert!(ticket.starts_with(TICKET_PREFIX));
        assert!(svc.is_valid("alice", &ticket));
        assert!(svc.consume("alice", &ticket));
        // One-shot: second consume fails.
        assert!(!svc.consume("alice", &ticket));
    }

    #[test]
    fn wrong_username_rejected() {
        let svc = LoginTicketService::new();
        let ticket = svc.issue("alice");
        assert!(!svc.consume("bob", &ticket));
        // Original ticket still valid for alice — wrong-user attempt didn't burn it.
        assert!(svc.consume("alice", &ticket));
    }

    #[test]
    fn rejects_non_prefixed() {
        let svc = LoginTicketService::new();
        let ticket = svc.issue("alice");
        let no_prefix = ticket.strip_prefix(TICKET_PREFIX).unwrap();
        assert!(!svc.consume("alice", no_prefix));
    }

    #[test]
    fn expired_ticket_rejected() {
        let svc = LoginTicketService::with_lifetime(Duration::from_millis(1));
        let ticket = svc.issue("alice");
        std::thread::sleep(Duration::from_millis(10));
        assert!(!svc.consume("alice", &ticket));
    }
}
