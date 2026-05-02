//! GET /api/character/{username} — public character profile.
//!
//! Port of `CharacterEndpoint.java`. Resolution order matches Java:
//!   1. Online lookup via the session manager — preferred because we get
//!      live state (current/max levels, current XP) without a DB hop.
//!   2. Offline DB lookup — pulls the player row + skill rows, computes
//!      levels from xp.
//!
//! Privacy: banned accounts return 404 (not "this account is banned") to
//! avoid leaking ban status. Admin-invisible players are filtered out on
//! the online path — gated on a future Player.invisible flag, see comment.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde_json::{json, Value};
use tracing::warn;

use crate::api::ApiState;
use crate::database::{schema::SkillsRecord, DatabasePool};
use crate::game::player::SkillId;

use super::error_response;

/// Skills surfaced in the response, in display order. Matches the Java
/// `SURFACED_SKILLS` list one-for-one. Names match Java's `Skill.name()`
/// (uppercase enum identifiers) so the response shape is identical.
const SURFACED_SKILLS: &[(SkillId, &str)] = &[
    (SkillId::Attack, "ATTACK"),
    (SkillId::Defence, "DEFENSE"),
    (SkillId::Strength, "STRENGTH"),
    (SkillId::Hits, "HITS"),
    (SkillId::Ranged, "RANGED"),
    (SkillId::Prayer, "PRAYER"),
    (SkillId::Magic, "MAGIC"),
    (SkillId::Cooking, "COOKING"),
    (SkillId::Woodcutting, "WOODCUTTING"),
    (SkillId::Fletching, "FLETCHING"),
    (SkillId::Fishing, "FISHING"),
    (SkillId::Firemaking, "FIREMAKING"),
    (SkillId::Crafting, "CRAFTING"),
    (SkillId::Smithing, "SMITHING"),
    (SkillId::Mining, "MINING"),
    (SkillId::Herblore, "HERBLAW"), // Java enum name is HERBLAW; Rust uses Herblore
    (SkillId::Agility, "AGILITY"),
    (SkillId::Thieving, "THIEVING"),
];

pub async fn get_character(
    State(state): State<ApiState>,
    Path(username): Path<String>,
) -> (StatusCode, Json<Value>) {
    if username.trim().is_empty() {
        return error_response(StatusCode::BAD_REQUEST, "missing username");
    }
    let canonical = super::auth::canonicalize_username(&username, 12);
    if canonical.is_empty() {
        return error_response(StatusCode::NOT_FOUND, "no such character");
    }

    // Online lookup first.
    if let Some(profile) = try_online_profile(&state, &canonical).await {
        return (StatusCode::OK, Json(profile));
    }

    // Offline path requires the DB.
    let pool = match state.db_pool.as_ref() {
        Some(p) => p,
        None => return error_response(StatusCode::NOT_FOUND, "no such character"),
    };

    match offline_profile(pool, &canonical).await {
        Ok(Some(profile)) => (StatusCode::OK, Json(profile)),
        Ok(None) => error_response(StatusCode::NOT_FOUND, "no such character"),
        Err(e) => {
            warn!("character DB lookup failed for {}: {}", canonical, e);
            error_response(StatusCode::SERVICE_UNAVAILABLE, "database lookup failed")
        }
    }
}

/// Fetch a live profile from the session manager + Player. Returns `None`
/// if the player isn't online (so callers fall back to the offline path).
async fn try_online_profile(state: &ApiState, canonical: &str) -> Option<Value> {
    let server = state.server.read().await;
    let session = server.sessions.get_session_by_username(canonical)?;
    drop(server);

    let s = session.read().await;
    let player_arc = s.player.as_ref()?.clone();
    drop(s);

    let p = player_arc.read().await;
    // TODO: filter admin-invisible players once Player tracks the flag.

    let mut total_level: u32 = 0;
    let mut skills_json = serde_json::Map::new();
    for (id, name) in SURFACED_SKILLS.iter() {
        let level = p.skills.level(*id) as u32;
        let xp = p.skills.experience(*id) as u32;
        total_level = total_level.saturating_add(level);
        skills_json.insert(
            (*name).into(),
            json!({
                "level": level,
                "xp": xp,
            }),
        );
    }

    Some(json!({
        "username": p.username,
        "combatLevel": p.combat_level,
        "totalLevel": total_level,
        // Live Player doesn't carry a group id today; default to PLAYER.
        // Orchestrator can wire group_id through Player and read it here.
        "rank": "PLAYER",
        "online": true,
        "creationDate": 0,
        "skills": Value::Object(skills_json),
    }))
}

/// Pull the offline profile straight from the DB. Returns `Ok(None)` when
/// the username has no row (caller will 404). Banned accounts are also
/// surfaced as `Ok(None)` to mirror Java's "hide banned behind 404" rule.
async fn offline_profile(
    pool: &DatabasePool,
    canonical: &str,
) -> Result<Option<Value>, sqlx::Error> {
    use sqlx::Row;

    // Pull the columns we need for the profile in a single query — we don't
    // need the full PlayerRecord (no appearance, no equipment, etc).
    let q = "SELECT id, group_id, banned, creation_date FROM players WHERE username = ?";
    let row_opt = match pool {
        DatabasePool::MySql(p) => sqlx::query(q).bind(canonical).fetch_optional(p).await?,
        DatabasePool::Sqlite(p) => sqlx::query(q).bind(canonical).fetch_optional(p).await?,
    };
    let Some(row) = row_opt else {
        return Ok(None);
    };

    let player_id: i64 = row.get("id");
    let group_id: i32 = row.get("group_id");
    let banned: bool = row.get("banned");
    let creation_date: i64 = row.get("creation_date");

    if banned {
        return Ok(None); // 404 path, hide banned status
    }

    // Skills row — may be absent for thin/new accounts; treat that as default.
    let skills = fetch_skills(pool, player_id).await?;

    let (skills_json, total_level, combat_level) = build_skill_block(skills);

    Ok(Some(json!({
        "username": canonical,
        "combatLevel": combat_level,
        "totalLevel": total_level,
        "rank": rank_label(group_id),
        "online": false,
        "creationDate": creation_date,
        "skills": skills_json,
    })))
}

async fn fetch_skills(
    pool: &DatabasePool,
    player_id: i64,
) -> Result<Option<SkillsRecord>, sqlx::Error> {
    let q = "SELECT * FROM player_skills WHERE player_id = ?";
    match pool {
        DatabasePool::MySql(p) => {
            sqlx::query_as::<_, SkillsRecord>(q)
                .bind(player_id)
                .fetch_optional(p)
                .await
        }
        DatabasePool::Sqlite(p) => {
            sqlx::query_as::<_, SkillsRecord>(q)
                .bind(player_id)
                .fetch_optional(p)
                .await
        }
    }
}

/// Compute the `skills` block, total level, and combat level from a
/// `SkillsRecord` (or defaults if `None`). XP -> level uses the same curve
/// as Rust's in-game `Skills::level_for_experience`, but we recompute it
/// inline to avoid coupling to a private fn.
fn build_skill_block(skills: Option<SkillsRecord>) -> (Value, u32, u32) {
    let s = skills.unwrap_or_default();
    let mut total: u32 = 0;
    let mut out = serde_json::Map::new();

    let xp_for = |id: SkillId| -> i32 {
        match id {
            SkillId::Attack => s.attack_xp,
            SkillId::Defence => s.defense_xp,
            SkillId::Strength => s.strength_xp,
            SkillId::Hits => s.hits_xp,
            SkillId::Ranged => s.ranged_xp,
            SkillId::Prayer => s.prayer_xp,
            SkillId::Magic => s.magic_xp,
            SkillId::Cooking => s.cooking_xp,
            SkillId::Woodcutting => s.woodcutting_xp,
            SkillId::Fletching => s.fletching_xp,
            SkillId::Fishing => s.fishing_xp,
            SkillId::Firemaking => s.firemaking_xp,
            SkillId::Crafting => s.crafting_xp,
            SkillId::Smithing => s.smithing_xp,
            SkillId::Mining => s.mining_xp,
            SkillId::Herblore => s.herblaw_xp,
            SkillId::Agility => s.agility_xp,
            SkillId::Thieving => s.thieving_xp,
        }
    };

    for (id, name) in SURFACED_SKILLS.iter() {
        let xp_raw = xp_for(*id).max(0) as u32;
        // RSC minimum: Hits is level 10 (xp 1154) by default. Java explicitly
        // bumps level to 10 if id == HITS && xp < 4616; we mirror that.
        let mut level = level_for_experience(xp_raw);
        if matches!(id, SkillId::Hits) && xp_raw < 4616 {
            level = level.max(10);
        }
        total = total.saturating_add(level as u32);
        out.insert(
            (*name).into(),
            json!({
                "level": level,
                "xp": xp_raw,
            }),
        );
    }

    let combat = combat_level(&s);
    (Value::Object(out), total, combat)
}

/// Standard RSC combat formula. Same as `Player::calculate_combat_level`.
/// Inlined here so we don't need to construct a full `Player`.
fn combat_level(s: &SkillsRecord) -> u32 {
    let lvl = |xp: i32, hits_min: bool| -> f64 {
        let mut l = level_for_experience(xp.max(0) as u32) as f64;
        if hits_min && l < 10.0 {
            l = 10.0;
        }
        l
    };
    let attack = lvl(s.attack_xp, false);
    let strength = lvl(s.strength_xp, false);
    let defense = lvl(s.defense_xp, false);
    let hits = lvl(s.hits_xp, true);
    let ranged = lvl(s.ranged_xp, false);
    let prayer = lvl(s.prayer_xp, false);
    let magic = lvl(s.magic_xp, false);

    let base = (defense + hits + (prayer / 8.0)) / 4.0;
    let melee = (attack + strength) * 0.25;
    let range = ranged * 0.375;
    let mage = magic * 0.375;

    (base + melee.max(range).max(mage)) as u32
}

const EXPERIENCE_TABLE: [u32; 99] = [
    0, 83, 174, 276, 388, 512, 650, 801, 969, 1154, 1358, 1584, 1833, 2107, 2411, 2746, 3115,
    3523, 3973, 4470, 5018, 5624, 6291, 7028, 7842, 8740, 9730, 10824, 12031, 13363, 14833,
    16456, 18247, 20224, 22406, 24815, 27473, 30408, 33648, 37224, 41171, 45529, 50339, 55649,
    61512, 67983, 75127, 83014, 91721, 101333, 111945, 123660, 136594, 150872, 166636, 184040,
    203254, 224466, 247886, 273742, 302288, 333804, 368599, 407015, 449428, 496254, 547953,
    605032, 668051, 737627, 814445, 899257, 992895, 1096278, 1210421, 1336443, 1475581,
    1629200, 1798808, 1986068, 2192818, 2421087, 2673114, 2951373, 3258594, 3597792, 3972294,
    4385776, 4842295, 5346332, 5902831, 6517253, 7195629, 7944614, 8771558, 9684577, 10692629,
    11805606, 13034431,
];

fn level_for_experience(exp: u32) -> u8 {
    for (level, &required) in EXPERIENCE_TABLE.iter().enumerate() {
        if exp < required {
            return level as u8;
        }
    }
    99
}

/// Rank label matching Java's `rankLabel(int groupId)`. Group IDs come from
/// `com.openrsc.server.model.entity.player.Group`:
///   OWNER=0, DEV=1, ADMIN=2, SUPER_MOD=3, MOD=4, EVENT=8, default=10 (PLAYER)
fn rank_label(group_id: i32) -> &'static str {
    match group_id {
        0 | 2 => "ADMIN",
        3 | 4 => "MOD",
        1 => "DEV",
        8 => "EVENT",
        _ => "PLAYER",
    }
}
