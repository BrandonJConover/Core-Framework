//! Sliding-window per-key rate limiter.
//!
//! Port of `RateLimiter.java`. The semantic is the same: each (key, window)
//! pair tracks a count and a window-start timestamp. When elapsed time
//! crosses the window threshold, the counter resets to 1; otherwise we
//! increment until we hit the cap, after which `allow()` returns false.
//!
//! Concurrency: `dashmap::DashMap` gives us shard-locked lookups so concurrent
//! login attempts from different IPs don't contend on a single bucket. The
//! per-bucket increment is `parking_lot::Mutex`-protected; that's the same
//! granularity as Java's `synchronized(b)`.
//!
//! Memory: ~64 bytes per active key. For very high cardinality, swap the
//! map for an LRU/TTL-eviction store (e.g. `moka`); for the brute-force
//! defense use case this is fine.

use axum::http::HeaderMap;
use dashmap::DashMap;
use parking_lot::Mutex;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

/// One bucket per identity. Mutex-guarded for atomic increment.
struct Bucket {
    inner: Mutex<BucketState>,
}

#[derive(Default)]
struct BucketState {
    window_start_ms: u64,
    count: u32,
}

pub struct RateLimiter {
    window_ms: u64,
    max_requests: u32,
    buckets: DashMap<String, Bucket>,
    rejected_total: AtomicU64,
}

impl RateLimiter {
    /// Build a limiter with `max_requests` allowed per `window_ms`-millisecond
    /// sliding window per key.
    pub fn new(window_ms: u64, max_requests: u32) -> Self {
        assert!(window_ms > 0, "window_ms must be > 0");
        assert!(max_requests > 0, "max_requests must be > 0");
        Self {
            window_ms,
            max_requests,
            buckets: DashMap::new(),
            rejected_total: AtomicU64::new(0),
        }
    }

    /// Charge one request against `key`. Returns true if allowed, false if
    /// rate-limited.
    pub fn allow(&self, key: &str) -> bool {
        let now = current_ms();
        let bucket = self
            .buckets
            .entry(key.to_string())
            .or_insert_with(|| Bucket {
                inner: Mutex::new(BucketState::default()),
            });
        let mut state = bucket.inner.lock();

        if now.saturating_sub(state.window_start_ms) >= self.window_ms {
            // Window rolled over: reset.
            state.window_start_ms = now;
            state.count = 1;
            return true;
        }
        if state.count < self.max_requests {
            state.count += 1;
            return true;
        }
        self.rejected_total.fetch_add(1, Ordering::Relaxed);
        false
    }

    /// Best-effort estimate of milliseconds until `key`'s window rolls over.
    /// Returns 0 if the caller has never been seen.
    pub fn retry_after_ms(&self, key: &str) -> u64 {
        let bucket = match self.buckets.get(key) {
            Some(b) => b,
            None => return 0,
        };
        let state = bucket.inner.lock();
        let elapsed = current_ms().saturating_sub(state.window_start_ms);
        self.window_ms.saturating_sub(elapsed)
    }

    /// Cumulative count of requests rejected since process start. Used by
    /// /metrics-style endpoints to surface abuse pressure.
    pub fn rejected_total(&self) -> u64 {
        self.rejected_total.load(Ordering::Relaxed)
    }
}

fn current_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Extract a caller identity from request metadata, preferring forwarded
/// headers over the raw socket address. Mirrors Java's `RateLimiter.identify`.
///
/// Trust model: only honor `X-Forwarded-For` if your axum app is behind a
/// reverse proxy that sets it correctly (nginx + a known IP, etc). Pass the
/// proxy IP allowlist outside this function — for the common nginx-on-loopback
/// case the leftmost X-Forwarded-For entry is the original client.
pub fn identify(headers: &HeaderMap, socket_addr: Option<SocketAddr>) -> String {
    if let Some(fwd) = headers.get("x-forwarded-for").and_then(|v| v.to_str().ok()) {
        let trimmed = fwd.trim();
        if !trimmed.is_empty() {
            // X-Forwarded-For: client, proxy1, proxy2 — first entry is the
            // original client.
            let leftmost = trimmed.split(',').next().unwrap_or(trimmed).trim();
            if !leftmost.is_empty() {
                return leftmost.to_string();
            }
        }
    }
    socket_addr
        .map(|a| a.ip().to_string())
        .unwrap_or_else(|| "unknown".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_under_limit_then_blocks() {
        let limiter = RateLimiter::new(60_000, 3);
        assert!(limiter.allow("ip-a"));
        assert!(limiter.allow("ip-a"));
        assert!(limiter.allow("ip-a"));
        assert!(!limiter.allow("ip-a"));
        assert!(limiter.rejected_total() >= 1);
    }

    #[test]
    fn separate_keys_dont_interfere() {
        let limiter = RateLimiter::new(60_000, 1);
        assert!(limiter.allow("ip-a"));
        assert!(!limiter.allow("ip-a"));
        assert!(limiter.allow("ip-b"));
    }
}
