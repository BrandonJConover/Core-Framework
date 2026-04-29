package com.openrsc.server.net.api;

import com.openrsc.server.Server;
import com.openrsc.server.constants.Skill;
import com.openrsc.server.model.entity.player.Player;
import com.openrsc.server.util.rsc.DataConversions;
import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpResponseStatus;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * GET /api/character/{username} — public character profile.
 *
 * Returns minimal public data for the named character. v1 only resolves
 * online players (uses World.getPlayer(usernameHash) lookup); a later
 * pass can hit the database directly to surface offline profiles too.
 *
 * Response shape (200):
 *   {
 *     "username": "x",
 *     "combatLevel": 3,
 *     "rank": "PLAYER",          // PLAYER / MOD / ADMIN / DEV
 *     "online": true,
 *     "skills": {
 *       "ATTACK":   {"level": 1, "xp": 0},
 *       "DEFENSE":  {"level": 1, "xp": 0},
 *       ...
 *     }
 *   }
 *
 * Failures:
 *   404 Not Found — username doesn't match any online player
 *
 * Privacy:
 *   - Invisible-mode admins are reported as 404 (consistent with the
 *     online-list endpoint hiding them).
 *   - Location, equipment, IP, last-login, banned status etc. are NOT
 *     exposed here. Add a separate authenticated endpoint if those are
 *     needed.
 */
public final class CharacterEndpoint {

    /** Skills surfaced in the response, in display order. Non-standard
     *  variant entries (PRAYGOOD/PRAYEVIL/GOODMAGIC/EVILMAGIC) are skipped
     *  because they're an internal split for divided-good-evil mode that
     *  most servers don't expose to the player. */
    private static final List<Skill> SURFACED_SKILLS = List.of(
        Skill.ATTACK, Skill.DEFENSE, Skill.STRENGTH, Skill.HITS,
        Skill.RANGED, Skill.PRAYER, Skill.MAGIC,
        Skill.COOKING, Skill.WOODCUTTING, Skill.FLETCHING, Skill.FISHING,
        Skill.FIREMAKING, Skill.CRAFTING, Skill.SMITHING, Skill.MINING,
        Skill.HERBLAW, Skill.AGILITY, Skill.THIEVING
    );

    private final Server server;

    public CharacterEndpoint(Server server) {
        this.server = server;
    }

    public FullHttpResponse handle(FullHttpRequest request, Map<String, String> pathParams) {
        String requested = pathParams.get("username");
        if (requested == null || requested.isBlank()) {
            return JsonHandler.error(HttpResponseStatus.BAD_REQUEST, "missing username");
        }

        String canonical = DataConversions.normalize(requested, 12);
        if (canonical == null || canonical.isEmpty()) {
            return JsonHandler.error(HttpResponseStatus.NOT_FOUND, "no such character");
        }

        if (server.getWorld() == null) {
            return JsonHandler.error(HttpResponseStatus.SERVICE_UNAVAILABLE, "world not ready");
        }

        long hash = DataConversions.usernameToHash(canonical);
        Player player = server.getWorld().getPlayer(hash);
        if (player == null || player.stateIsInvisible()) {
            return JsonHandler.error(HttpResponseStatus.NOT_FOUND, "no such character");
        }

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("username", player.getUsername());
        body.put("combatLevel", player.getCombatLevel());
        body.put("rank", rankLabel(player));
        body.put("online", true);

        Map<String, Map<String, Object>> skills = new LinkedHashMap<>();
        for (Skill s : SURFACED_SKILLS) {
            int id = s.id();
            if (id < 0) continue;
            Map<String, Object> entry = new LinkedHashMap<>();
            entry.put("level", player.getSkills().getMaxStat(id));
            entry.put("xp", player.getSkills().getExperience(id));
            skills.put(s.name(), entry);
        }
        body.put("skills", skills);

        return JsonHandler.json(HttpResponseStatus.OK, body);
    }

    private static String rankLabel(Player p) {
        if (p.isAdmin()) return "ADMIN";
        if (p.isMod()) return "MOD";
        if (p.isDev()) return "DEV";
        return "PLAYER";
    }
}
