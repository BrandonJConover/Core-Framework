package com.openrsc.server.net.api;

import com.openrsc.server.Server;
import com.openrsc.server.database.GameDatabaseException;
import com.openrsc.server.util.rsc.DataConversions;
import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpResponseStatus;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * POST /api/auth/register — create an account from a JSON request.
 *
 * Mirrors the validation rules in CharacterCreateRequest (the binary
 * protocol's REGISTER_ACCOUNT path) so accounts created via JSON behave
 * identically to ones made through the desktop client. The password is
 * hashed with the same {@code DataConversions.hashPassword} the rest of
 * the server uses, so the account works in both flows.
 *
 * Request:
 *   {"username": "x", "password": "x", "email": "x@y.z" (optional)}
 *
 * Success (201):
 *   {"playerId": 42, "username": "x", "token": "eyJ..."}
 *   — issues a JWT immediately so the client can proceed to authed calls
 *     without a separate /api/auth/login round-trip.
 *
 * Failures:
 *   400 — missing fields, bad password length, malformed email
 *   409 — username already taken
 *   429 — rate-limited (registrations per IP)
 *   503 — registration disabled OR database write failed
 *
 * Rate limiting:
 *   Backed by the same RateLimiter machinery as login. Default budget is
 *   the more conservative 3 registrations per 60 minutes per IP — a real
 *   user creating an account a few times in a session is fine; bots
 *   sweeping for usernames hit the wall fast.
 */
public final class RegisterEndpoint {

    /** Min/max password length, matching CharacterCreateRequest. */
    private static final int MIN_PASS_LEN = 4;
    private static final int MAX_PASS_LEN = 20;

    /** Username max length matches the binary protocol's 12-char cap. */
    private static final int MAX_USERNAME_LEN = 12;

    private final Server server;
    private final JwtUtil jwt;
    private final RateLimiter limiter;

    public RegisterEndpoint(Server server, JwtUtil jwt, RateLimiter limiter) {
        this.server = server;
        this.jwt = jwt;
        this.limiter = limiter;
    }

    public FullHttpResponse handle(FullHttpRequest request) {
        // Per-IP rate limit before any work — registration is a write path,
        // doubly important not to thrash the DB on abuse.
        String fallback = request.headers().get(ApiServer.INTERNAL_REMOTE_ADDR_HEADER);
        String identity = RateLimiter.identify(request, fallback);
        if (!limiter.allow(identity)) {
            long retryMs = limiter.retryAfterMs(identity);
            FullHttpResponse resp = JsonHandler.error(HttpResponseStatus.TOO_MANY_REQUESTS,
                "too many registration attempts");
            resp.headers().set("Retry-After", Math.max(1L, (retryMs + 999L) / 1000L));
            return resp;
        }

        RegisterRequest req;
        try {
            req = JsonHandler.parse(request, RegisterRequest.class);
        } catch (Exception e) {
            return JsonHandler.error(HttpResponseStatus.BAD_REQUEST, "malformed JSON body");
        }
        if (req == null || req.username == null || req.password == null
            || req.username.isBlank() || req.password.isBlank()) {
            return JsonHandler.error(HttpResponseStatus.BAD_REQUEST,
                "username and password are required");
        }
        if (req.password.length() < MIN_PASS_LEN || req.password.length() > MAX_PASS_LEN) {
            return JsonHandler.error(HttpResponseStatus.BAD_REQUEST,
                "password must be between " + MIN_PASS_LEN + " and " + MAX_PASS_LEN + " characters");
        }

        String canonical = DataConversions.normalize(req.username, MAX_USERNAME_LEN);
        if (canonical == null || canonical.isEmpty()) {
            return JsonHandler.error(HttpResponseStatus.BAD_REQUEST, "invalid username");
        }

        // Email is required only if the server is configured for it.
        String email = req.email != null ? req.email.trim() : "";
        if (server.getConfig().WANT_EMAIL) {
            if (!DataConversions.isValidEmailAddress(email)) {
                return JsonHandler.error(HttpResponseStatus.BAD_REQUEST,
                    "valid email is required");
            }
        }

        try {
            if (server.getDatabase().playerExists(canonical)) {
                return JsonHandler.error(HttpResponseStatus.CONFLICT, "username already taken");
            }

            // Optional config-gated registration limit (per IP per N hours).
            // CharacterCreateRequest applies a similar check; we mirror it.
            String ip = identity;
            if (server.getConfig().WANT_REGISTRATION_LIMIT
                && !ip.equals("127.0.0.1")
                && server.getDatabase().checkRecentlyRegistered(ip, /*minutes*/ 60)) {
                return JsonHandler.error(HttpResponseStatus.TOO_MANY_REQUESTS,
                    "this IP has registered too recently");
            }

            String hashed = DataConversions.hashPassword(req.password, null);
            int playerId = server.getDatabase().createPlayer(
                canonical, email, hashed, System.currentTimeMillis() / 1000, ip);
            if (playerId == -1) {
                return JsonHandler.error(HttpResponseStatus.SERVICE_UNAVAILABLE,
                    "could not create account");
            }

            // Issue an auth token immediately so the caller doesn't need a
            // round-trip through /api/auth/login.
            String token = jwt.generateToken(canonical);

            Map<String, Object> body = new LinkedHashMap<>();
            body.put("playerId", playerId);
            body.put("username", canonical);
            body.put("token", token);
            body.put("expiresIn", JwtUtil.DEFAULT_LIFETIME_MS / 1000L);
            return JsonHandler.json(HttpResponseStatus.CREATED, body);
        } catch (GameDatabaseException dbEx) {
            return JsonHandler.error(HttpResponseStatus.SERVICE_UNAVAILABLE,
                "database write failed");
        }
    }

    /** Jackson DTO for the request body. */
    public static final class RegisterRequest {
        public String username;
        public String password;
        public String email;
    }
}
