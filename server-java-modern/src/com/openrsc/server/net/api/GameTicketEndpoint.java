package com.openrsc.server.net.api;

import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpHeaderNames;
import io.netty.handler.codec.http.HttpResponseStatus;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * POST /api/auth/game-ticket — exchange a valid bearer token for a short-lived
 * one-time game login ticket.
 *
 * The returned ticket is passed to the binary game client in place of the
 * account password so a modern launcher page can skip the legacy login UI.
 */
public final class GameTicketEndpoint {

    private static final String BEARER_PREFIX = "Bearer ";

    private final JwtUtil jwt;
    private final GameLoginTicketService ticketService;

    public GameTicketEndpoint(JwtUtil jwt, GameLoginTicketService ticketService) {
        this.jwt = jwt;
        this.ticketService = ticketService;
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
            return JsonHandler.error(HttpResponseStatus.UNAUTHORIZED, "invalid or expired token");
        }

        String gameTicket = ticketService.issuePasswordToken(claims.username());
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("ticket", gameTicket);
        body.put("username", claims.username());
        body.put("expiresIn", ticketService.expiresInSeconds());
        return JsonHandler.json(HttpResponseStatus.OK, body);
    }
}
