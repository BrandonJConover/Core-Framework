package com.openrsc.server.net.api;

import com.openrsc.server.Server;
import com.openrsc.server.constants.Skill;
import com.openrsc.server.database.GameDatabaseException;
import com.openrsc.server.database.struct.PlayerData;
import com.openrsc.server.database.struct.PlayerExperience;
import com.openrsc.server.database.struct.PlayerLoginData;
import com.openrsc.server.model.entity.player.Group;
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
 * Resolution order:
 *   1. Online lookup via World.getPlayer(usernameHash). If found and not
 *      admin-invisible, returns full live profile.
 *   2. Otherwise, offline DB lookup. Pulls PlayerLoginData (id, group, ban
 *      flag), PlayerData (combat/total level, creation date), and the
 *      experience table. Levels are computed from xp via the server's
 *      configured experience curve.
 *
 * Response (200):
 *   {
 *     "username": "x",
 *     "combatLevel": 3,
 *     "totalLevel": 32,
 *     "rank": "PLAYER" | "MOD" | "ADMIN" | "DEV" | "EVENT",
 *     "online": true | false,
 *     "creationDate": <unix-seconds>,    // 0 if unknown
 *     "skills": {
 *       "ATTACK":   {"level": 1, "xp": 0},
 *       "DEFENSE":  {"level": 1, "xp": 0},
 *       ...
 *     }
 *   }
 *
 * Failures:
 *   404 — username doesn't resolve, the character was never created,
 *         or the live character is admin-invisible (consistent with
 *         /api/players/online filter).
 *   503 — database error during offline lookup.
 *
 * Privacy notes:
 *   - Banned accounts are hidden (404) instead of "this account is banned"
 *     to avoid public name-checking + ban-status leaks.
 *   - Location, equipment, IP, last-login etc. are NOT exposed here.
 */
public final class CharacterEndpoint {

    /** Skills surfaced in the response, in display order. Variant Pray/Magic
     *  splits (PRAYGOOD/PRAYEVIL/GOODMAGIC/EVILMAGIC) are an internal split
     *  for divided-good-evil mode and not exposed. */
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

        // Online path first — preferred because it has live state.
        long hash = DataConversions.usernameToHash(canonical);
        Player player = server.getWorld().getPlayer(hash);
        if (player != null && !player.stateIsInvisible()) {
            return JsonHandler.json(HttpResponseStatus.OK, buildOnlineProfile(player));
        }

        // Offline path — DB lookup.
        try {
            return offlineProfile(canonical);
        } catch (GameDatabaseException ex) {
            return JsonHandler.error(HttpResponseStatus.SERVICE_UNAVAILABLE,
                "database lookup failed");
        }
    }

    private Map<String, Object> buildOnlineProfile(Player player) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("username", player.getUsername());
        body.put("combatLevel", player.getCombatLevel());
        body.put("totalLevel", player.getSkills().getTotalLevel());
        body.put("rank", rankLabel(player.getGroupID()));
        body.put("online", true);
        body.put("creationDate", 0L);  // not stored on live Player; would require DB hop

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
        return body;
    }

    private FullHttpResponse offlineProfile(String canonical) throws GameDatabaseException {
        PlayerLoginData login = server.getDatabase().getPlayerLoginData(canonical);
        if (login == null) {
            return JsonHandler.error(HttpResponseStatus.NOT_FOUND, "no such character");
        }
        if (login.banned > 0) {
            // Hide banned accounts behind 404 to avoid leaking ban status.
            return JsonHandler.error(HttpResponseStatus.NOT_FOUND, "no such character");
        }

        PlayerData pdata;
        try {
            pdata = server.getDatabase().queryLoadPlayerData(canonical);
        } catch (GameDatabaseException ex) {
            // Brand-new accounts with no PlayerData row yet: treat as a thin profile.
            pdata = null;
        }

        PlayerExperience[] exps = server.getDatabase().queryLoadPlayerExperience(login.id);
        int playerLevelLimit = server.getConfig().PLAYER_LEVEL_LIMIT;

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("username", canonical);
        body.put("combatLevel", pdata != null ? pdata.combatLevel : 3);
        body.put("totalLevel", pdata != null ? pdata.totalLevel : SURFACED_SKILLS.size());
        body.put("rank", rankLabel(login.groupId));
        body.put("online", false);
        body.put("creationDate", pdata != null ? pdata.creationDate : 0L);

        // Build the per-skill block from the experience array. Skills not
        // present in the DB row default to {level:1, xp:0} (level 10 for
        // Hitpoints to match the live game's minimum).
        Map<Integer, Integer> xpById = new java.util.HashMap<>();
        if (exps != null) {
            for (PlayerExperience pe : exps) xpById.put(pe.skillId, pe.experience);
        }

        Map<String, Map<String, Object>> skills = new LinkedHashMap<>();
        for (Skill s : SURFACED_SKILLS) {
            int id = s.id();
            if (id < 0) continue;
            int xp = xpById.getOrDefault(id, 0);
            int level;
            if (id == Skill.HITS.id() && xp < 4616) {
                level = 10;  // RSC minimum for hitpoints
            } else {
                level = server.getConstants().getSkills()
                    .getLevelForExperience(xp, playerLevelLimit);
            }
            Map<String, Object> entry = new LinkedHashMap<>();
            entry.put("level", level);
            entry.put("xp", xp);
            skills.put(s.name(), entry);
        }
        body.put("skills", skills);

        return JsonHandler.json(HttpResponseStatus.OK, body);
    }

    private static String rankLabel(int groupId) {
        if (groupId == Group.OWNER || groupId == Group.ADMIN) return "ADMIN";
        if (groupId == Group.SUPER_MOD || groupId == Group.MOD) return "MOD";
        if (groupId == Group.DEV) return "DEV";
        if (groupId == Group.EVENT) return "EVENT";
        return "PLAYER";
    }
}
