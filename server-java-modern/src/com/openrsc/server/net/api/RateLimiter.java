package com.openrsc.server.net.api;

import io.netty.handler.codec.http.FullHttpRequest;

import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
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

    /** Evict stale buckets when the map exceeds this many keys. */
    private static final int EVICT_THRESHOLD = 50_000;
    /** Minimum gap between eviction sweeps, ms. */
    private static final long EVICT_INTERVAL_MS = 60_000L;
    private final AtomicLong lastSweepMs = new AtomicLong();

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
        maybeEvict(now);
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

    /**
     * Opportunistically drop buckets whose window has long since rolled over,
     * so a caller rotating through many source IPs can't grow the map without
     * bound. Runs at most once per {@link #EVICT_INTERVAL_MS} and only once the
     * map is large enough to be worth sweeping.
     */
    private void maybeEvict(long now) {
        if (buckets.size() < EVICT_THRESHOLD) return;
        long last = lastSweepMs.get();
        if (now - last < EVICT_INTERVAL_MS) return;
        if (!lastSweepMs.compareAndSet(last, now)) return; // another thread is sweeping
        buckets.entrySet().removeIf(e -> {
            Bucket b = e.getValue();
            synchronized (b) {
                return now - b.windowStartMs >= windowMs;
            }
        });
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

    /**
     * IPs of reverse proxies we trust to set X-Forwarded-For. Only when the
     * direct TCP peer (fallbackRemoteAddr) is one of these do we consult XFF.
     * Defaults to loopback (the nginx/Caddy-on-localhost topology this repo
     * documents); override with -Dopenrsc.trustedProxies=ip1,ip2,...
     */
    private static final Set<String> TRUSTED_PROXIES = parseTrustedProxies(
        System.getProperty("openrsc.trustedProxies", "127.0.0.1,::1,0:0:0:0:0:0:0:1"));

    private static Set<String> parseTrustedProxies(String csv) {
        Set<String> set = new LinkedHashSet<>();
        for (String s : csv.split(",")) {
            String t = s.trim();
            if (!t.isEmpty()) set.add(t);
        }
        return set;
    }

    private static boolean isTrustedProxy(String ip) {
        return ip != null && TRUSTED_PROXIES.contains(ip.trim());
    }

    /**
     * Extract a caller identity from the request.
     *
     * X-Forwarded-For is client-controlled and must NOT be trusted unless the
     * request actually arrived from one of our reverse proxies. Trusting it
     * unconditionally (the previous behaviour) let any client defeat every
     * per-IP limit by sending a random/rotating XFF header.
     *
     * When the direct peer is a trusted proxy we walk XFF right-to-left and
     * return the first hop that is not itself a trusted proxy — that is the
     * real client that connected to our edge. nginx's
     * $proxy_add_x_forwarded_for APPENDS the connecting client, so the
     * rightmost non-proxy entry is authoritative and the leftmost (which a
     * client can pre-populate) is not.
     */
    public static String identify(FullHttpRequest req, String fallbackRemoteAddr) {
        // Direct peer not a trusted proxy: ignore XFF entirely, use the socket peer.
        if (!isTrustedProxy(fallbackRemoteAddr)) {
            return fallbackRemoteAddr != null ? fallbackRemoteAddr : "unknown";
        }

        String fwd = req.headers().get("X-Forwarded-For");
        if (fwd != null && !fwd.isBlank()) {
            String[] hops = fwd.split(",");
            for (int i = hops.length - 1; i >= 0; i--) {
                String hop = hops[i].trim();
                if (!hop.isEmpty() && !isTrustedProxy(hop)) {
                    return hop;
                }
            }
            // All hops were trusted proxies — fall back to the leftmost entry.
            String leftmost = hops.length > 0 ? hops[0].trim() : "";
            if (!leftmost.isEmpty()) return leftmost;
        }
        return fallbackRemoteAddr != null ? fallbackRemoteAddr : "unknown";
    }
}
