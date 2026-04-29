package com.openrsc.server.net.api;

import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpHeaderNames;
import io.netty.handler.codec.http.HttpResponseStatus;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * GET /api/auth/whoami — verifies the bearer token and returns its subject.
 *
 * Header:  Authorization: Bearer <token>
 *
 * Success (200):
 *   {"username": "x", "expiresAt": <unix-seconds>, "issuedAt": <unix-seconds>}
 *
 * Failures:
 *   401 — missing/malformed Authorization header, or token failed verify
 *         (bad signature, expired, wrong issuer, server restarted since issue).
 *
 * This endpoint also serves as the canonical example of how future
 * authenticated endpoints should pull the calling player's username:
 * extract the bearer header, verify with JwtUtil, short-circuit to 401
 * on null. The resulting {@code username} can then be used to look up
 * the live {@code Player}, character data, etc.
 */
public final class WhoamiEndpoint {

    private static final String BEARER_PREFIX = "Bearer ";

    private final JwtUtil jwt;

    public WhoamiEndpoint(JwtUtil jwt) {
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
                "invalid or expired token");
        }
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("username", claims.username());
        body.put("expiresAt", claims.expiresAtMs() / 1000L);  // unix seconds
        body.put("issuedAt", claims.issuedAtMs() / 1000L);
        return JsonHandler.json(HttpResponseStatus.OK, body);
    }
}
