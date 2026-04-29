package com.openrsc.server.net.api;

import com.openrsc.server.Server;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpResponseStatus;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * GET /api/status — public, unauthenticated. Returns minimal observability
 * data the launcher / web client home page can render without needing a
 * full game-protocol session.
 *
 * Reads only volatile counters from the running {@link Server} — never
 * touches the database, never blocks on the game tick. Safe to be hit
 * frequently (browser polling, monitoring probes).
 */
public final class StatusEndpoint {

    private final Server server;

    public StatusEndpoint(Server server) {
        this.server = server;
    }

    public FullHttpResponse handle() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("up", server.isRunning());
        body.put("name", server.getName());
        body.put("playerCount", server.getWorld() != null ? server.getWorld().getPlayers().size() : 0);
        body.put("playerLimit", server.getConfig().MAX_PLAYERS);
        // serverStartedTime is recorded with System.nanoTime() in Server.start();
        // diff against current nanoTime gives us a monotonic uptime independent
        // of any wall-clock-ish drift. 0 means the server hasn't started yet.
        long startedNs = server.getServerStartedTime();
        body.put("uptimeMs", startedNs == 0 ? 0L : (System.nanoTime() - startedNs) / 1_000_000L);
        body.put("lastTickMs", server.getLastTickDuration() / 1_000_000L);  // ns -> ms
        body.put("currentTick", server.getCurrentTick());
        return JsonHandler.json(HttpResponseStatus.OK, body);
    }
}
