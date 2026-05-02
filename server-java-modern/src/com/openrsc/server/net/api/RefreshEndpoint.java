package com.openrsc.server.net.api;

import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpHeaderNames;
import io.netty.handler.codec.http.HttpResponseStatus;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * POST /api/auth/refresh — exchange a still-valid token for a fresh one.
 *
 * Required for long-lived clients (mobile apps backgrounded for hours,
 * desktop launchers running overnight) that would otherwise be forced to
 * re-prompt the user for credentials when the 24h JWT expires. Refresh
 * keeps the user signed in indefinitely as long as they hit the API at
 * least once per token lifetime.
 *
 * Header:  Authorization: Bearer <current-valid-token>
 *
 * Success (200):
 *   {"token": "<new-token>", "username": "x",
 *    "expiresIn": 86400, "expiresAt": <unix-seconds>}
 *
 * Failures:
 *   401 — missing/malformed Authorization, expired/invalid current token.
 *         There is no "refresh after expiry" sliding-window — once a token
 *         expires the user must log in again. This is intentional: a
 *         leaked-and-then-let-expire token can't be re-activated.
 *
 * Note: the new token's expiry is reset to NOW + 24h. There's no maximum
 * refresh chain length — a determined client can keep the session alive
 * forever. If you want hard session expiry (e.g. force re-auth weekly
 * regardless of activity), embed an "originally issued at" claim and
 * reject refresh once it's older than the cap.
 */
public final class RefreshEndpoint {

    private static final String BEARER_PREFIX = "Bearer ";

    private final JwtUtil jwt;

    public RefreshEndpoint(JwtUtil jwt) {
        this.jwt = jwt;
    }

    public FullHttpResponse handle(FullHttpRequest request) {
        String header = request.headers().get(HttpHeaderNames.AUTHORIZATION);
        if (header == null || !header.startsWith(BEARER_PREFIX)) {
            return JsonHandler.error(HttpResponseStatus.UNAUTHORIZED,
                "missing or malformed Authorization header (expected: Bearer <token>)");
        }
        String token = header.substring(BEARER_PREFIX.length()).trim();
        if (token.isEmpty()) {
            return JsonHandler.error(HttpResponseStatus.UNAUTHORIZED, "empty bearer token");
        }
        JwtUtil.Claims claims = jwt.verify(token);
        if (claims == null || claims.username() == null) {
            return JsonHandler.error(HttpResponseStatus.UNAUTHORIZED,
                "invalid or expired token (login again)");
        }

        // Issue a fresh token with the same subject and a new 24h window.
        String newToken = jwt.generateToken(claims.username());
        long newExpiresAt = (System.currentTimeMillis() + JwtUtil.DEFAULT_LIFETIME_MS) / 1000L;

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("token", newToken);
        body.put("username", claims.username());
        body.put("expiresIn", JwtUtil.DEFAULT_LIFETIME_MS / 1000L);
        body.put("expiresAt", newExpiresAt);
        return JsonHandler.json(HttpResponseStatus.OK, body);
    }
}
