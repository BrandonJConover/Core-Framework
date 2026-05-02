package com.openrsc.server.net.api;

import com.openrsc.server.Server;
import com.openrsc.server.database.GameDatabaseException;
import com.openrsc.server.database.struct.PlayerLoginData;
import com.openrsc.server.util.rsc.DataConversions;
import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpResponseStatus;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * POST /api/auth/login — exchange username/password for a JWT.
 *
 * Request body (JSON):
 *   {"username": "x", "password": "x"}
 *
 * Success response (200):
 *   {"token": "eyJ0eXAiOiJKV1Q...", "username": "x", "expiresIn": 86400}
 *
 * Failure responses:
 *   400 Bad Request   — body missing / not JSON / missing required fields
 *   401 Unauthorized  — wrong credentials OR username doesn't exist
 *                       (folded together to prevent username enumeration)
 *   403 Forbidden     — account is banned
 *   503 Service Unavailable — database error during lookup
 *
 * Modern clients send the returned token as `Authorization: Bearer <token>`
 * on subsequent API requests. JwtUtil.verifyAndGetUsername() validates and
 * returns the canonical username.
 *
 * NOTE: This endpoint does NOT establish a game-protocol session. It only
 * authenticates for the JSON REST API. To actually log in to the game
 * world, the client still uses the binary login flow on TCP/WS. The JWT
 * is for non-tick-path features: profile lookup, server status, future
 * launcher integration. A future phase will allow JWT to seed a game
 * session directly.
 */
public final class AuthEndpoint {

    private final Server server;
    private final JwtUtil jwt;
    private final RateLimiter limiter;

    public AuthEndpoint(Server server, JwtUtil jwt, RateLimiter limiter) {
        this.server = server;
        this.jwt = jwt;
        this.limiter = limiter;
    }

    public FullHttpResponse handle(FullHttpRequest request) {
        // Rate-limit by caller IP first — anti-brute-force. Cheaper than parsing
        // a body, returns 429 with Retry-After hint so well-behaved clients can
        // back off without frustrating users typing slowly.
        String fallback = request.headers().get(ApiServer.INTERNAL_REMOTE_ADDR_HEADER);
        String identity = RateLimiter.identify(request, fallback);
        if (!limiter.allow(identity)) {
            long retryMs = limiter.retryAfterMs(identity);
            FullHttpResponse resp = JsonHandler.error(HttpResponseStatus.TOO_MANY_REQUESTS,
                "too many login attempts, slow down");
            resp.headers().set("Retry-After", Math.max(1L, (retryMs + 999L) / 1000L));
            return resp;
        }

        // Parse the body first; bad JSON -> 400.
        LoginRequest req;
        try {
            req = JsonHandler.parse(request, LoginRequest.class);
        } catch (Exception e) {
            return JsonHandler.error(HttpResponseStatus.BAD_REQUEST, "malformed JSON body");
        }
        if (req == null || req.username == null || req.password == null
            || req.username.isBlank() || req.password.isBlank()) {
            return JsonHandler.error(HttpResponseStatus.BAD_REQUEST,
                "username and password are required");
        }

        // Canonicalise the username the same way the binary login path does
        // (lowercased, collapsed whitespace) so callers can submit either form.
        String canonical = DataConversions.normalize(req.username, 12);
        if (canonical == null || canonical.isEmpty()) {
            return JsonHandler.error(HttpResponseStatus.UNAUTHORIZED, "invalid credentials");
        }

        PlayerLoginData loginData;
        try {
            loginData = server.getDatabase().getPlayerLoginData(canonical);
        } catch (GameDatabaseException e) {
            return JsonHandler.error(HttpResponseStatus.SERVICE_UNAVAILABLE,
                "database lookup failed");
        }

        // Fold "no such user" + "wrong password" into a single 401 so a caller
        // can't enumerate usernames by probing this endpoint.
        if (loginData == null) {
            return JsonHandler.error(HttpResponseStatus.UNAUTHORIZED, "invalid credentials");
        }
        if (!DataConversions.checkPassword(req.password, loginData.salt, loginData.password)) {
            return JsonHandler.error(HttpResponseStatus.UNAUTHORIZED, "invalid credentials");
        }
        if (loginData.banned > 0) {
            return JsonHandler.error(HttpResponseStatus.FORBIDDEN, "account is banned");
        }

        String token = jwt.generateToken(canonical);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("token", token);
        body.put("username", canonical);
        body.put("expiresIn", JwtUtil.DEFAULT_LIFETIME_MS / 1000L); // seconds
        return JsonHandler.json(HttpResponseStatus.OK, body);
    }

    /** Jackson DTO for the request body. */
    public static final class LoginRequest {
        public String username;
        public String password;
    }
}
