package com.openrsc.server.net.api;

import com.openrsc.server.Server;
import com.openrsc.server.model.entity.player.Player;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpResponseStatus;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * GET /api/players/online — public listing of currently logged-in players.
 *
 * Response:
 *   {"count": N, "players": [{"username": "x", "combatLevel": N}, ...]}
 *
 * Privacy:
 * - Players that have toggled their invisible state via admin command
 *   (Player.stateIsInvisible()) are filtered out — the in-game scene
 *   already hides them, so the API does too.
 * - The response intentionally exposes minimal data (username + combat
 *   level). Location, equipped items, IP, etc. are NOT exposed here —
 *   per-character details belong on a separate /api/character/{name}
 *   endpoint that can apply finer-grained checks.
 *
 * No authentication required — this is the data a launcher / web home
 * page would render to show "X players online right now". If you want
 * to gate it behind auth later, add the same Bearer-header check used
 * in WhoamiEndpoint.
 */
public final class OnlinePlayersEndpoint {

    private final Server server;

    public OnlinePlayersEndpoint(Server server) {
        this.server = server;
    }

    public FullHttpResponse handle() {
        if (server.getWorld() == null) {
            // Server is mid-startup or mid-shutdown.
            Map<String, Object> empty = new LinkedHashMap<>();
            empty.put("count", 0);
            empty.put("players", List.of());
            return JsonHandler.json(HttpResponseStatus.OK, empty);
        }

        List<Map<String, Object>> list = new ArrayList<>();
        for (Player p : server.getWorld().getPlayers()) {
            if (p == null) continue;
            if (p.stateIsInvisible()) continue;  // honor admin-invisible toggle
            Map<String, Object> entry = new LinkedHashMap<>();
            entry.put("username", p.getUsername());
            entry.put("combatLevel", p.getCombatLevel());
            list.add(entry);
        }

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("count", list.size());
        body.put("players", list);
        return JsonHandler.json(HttpResponseStatus.OK, body);
    }
}
