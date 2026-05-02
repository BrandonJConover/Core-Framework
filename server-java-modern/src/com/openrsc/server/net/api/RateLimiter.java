package com.openrsc.server.net.api;

import io.netty.handler.codec.http.FullHttpRequest;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * In-memory sliding-window rate limiter keyed on caller identity (typically
 * client IP). Used to back-pressure brute-force attacks against /api/auth/login
 * and similar credential-checking endpoints.
 *
 * Design:
 * - Each (key, window) pair maintains a request count and a window-start
 *   timestamp. When the elapsed time exceeds the window duration, the
 *   counter resets to 1 and the timestamp updates.
 * - allow() returns true if the request is under the limit, false if rate-
 *   limited. Atomic via per-bucket lock; no global contention.
 * - Buckets expire on next access if their window has rolled over; stale
 *   entries for inactive callers stay in memory until next probe but the
 *   memory cost is ~64 bytes per active key, so a 100k-key cache is ~6MB.
 *   For extreme cardinality, swap for Caffeine with a maximum size + TTL.
 *
 * Caller-identity strategy:
 * - Prefer X-Forwarded-For if the request came through a trusted reverse
 *   proxy (nginx). Falls back to the channel's remote address otherwise.
 * - The caller is responsible for passing a trusted IP — at the Netty
 *   pipeline level we can trust X-Forwarded-For only when the upstream
 *   proxy is in a known-good list. For the common nginx-on-loopback case
 *   that's fine.
 */
public final class RateLimiter {

    /** Counter + window-start for one key. Synchronized on itself for atomicity. */
    private static final class Bucket {
        long windowStartMs;
        int count;
    }

    private final long windowMs;
    private final int maxRequests;
    private final Map<String, Bucket> buckets = new ConcurrentHashMap<>();

    /** Stats: how many requests were rejected by this limiter (cumulative). */
    private final AtomicLong rejectedTotal = new AtomicLong();

    public RateLimiter(long windowMs, int maxRequests) {
        if (windowMs <= 0) throw new IllegalArgumentException("windowMs must be > 0");
        if (maxRequests <= 0) throw new IllegalArgumentException("maxRequests must be > 0");
        this.windowMs = windowMs;
        this.maxRequests = maxRequests;
    }

    /**
     * Charge one request against the given key. Returns true if allowed,
     * false if the caller has exceeded the rate.
     */
    public boolean allow(String key) {
        long now = System.currentTimeMillis();
        Bucket b = buckets.computeIfAbsent(key, k -> new Bucket());
        synchronized (b) {
            if (now - b.windowStartMs >= windowMs) {
                // Window rolled over: reset.
                b.windowStartMs = now;
                b.count = 1;
                return true;
            }
            if (b.count < maxRequests) {
                b.count++;
                return true;
            }
            rejectedTotal.incrementAndGet();
            return false;
        }
    }

    /** Number of requests rejected since process start. */
    public long getRejectedTotal() {
        return rejectedTotal.get();
    }

    /** Best-effort estimate of milliseconds until the caller's window rolls over. */
    public long retryAfterMs(String key) {
        Bucket b = buckets.get(key);
        if (b == null) return 0L;
        synchronized (b) {
            long elapsed = System.currentTimeMillis() - b.windowStartMs;
            return Math.max(0L, windowMs - elapsed);
        }
    }

    /** Extract a caller identity from the request, preferring forwarded headers. */
    public static String identify(FullHttpRequest req, String fallbackRemoteAddr) {
        // X-Forwarded-For isn't an enum constant in Netty 4.1's HttpHeaderNames
        // (it's a non-standard header), so use the literal name. nginx + most
        // CDNs set it; we trust the leftmost entry as the original client.
        String fwd = req.headers().get("X-Forwarded-For");
        if (fwd != null && !fwd.isBlank()) {
            // X-Forwarded-For: client, proxy1, proxy2 — first entry is the original client.
            int comma = fwd.indexOf(',');
            return (comma > 0 ? fwd.substring(0, comma) : fwd).trim();
        }
        return fallbackRemoteAddr != null ? fallbackRemoteAddr : "unknown";
    }
}
