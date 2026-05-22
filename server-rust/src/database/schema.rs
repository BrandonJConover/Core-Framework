//! Database schema definitions and models.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

use super::DatabasePool;

/// Player database record.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct PlayerRecord {
    pub id: i64,
    pub username: String,
    pub password_hash: String,
    pub email: Option<String>,
    pub creation_date: i64,
    pub last_login: Option<i64>,
    pub login_ip: Option<String>,
    pub banned: bool,
    pub muted: bool,
    pub group_id: i32,
    pub combat_style: i32,
    pub x: i32,
    pub y: i32,
    pub fatigue: i32,
    pub appearance_hair: i32,
    pub appearance_top: i32,
    pub appearance_bottom: i32,
    pub appearance_skin: i32,
    pub appearance_head: i32,
    pub appearance_body: i32,
    pub male: bool,
    pub skull: i32,
    pub online: bool,
}

impl Default for PlayerRecord {
    fn default() -> Self {
        Self {
            id: 0,
            username: String::new(),
            password_hash: String::new(),
            email: None,
            creation_date: 0,
            last_login: None,
            login_ip: None,
            banned: false,
            muted: false,
            group_id: 10, // Regular user
            combat_style: 0,
            x: 122,
            y: 647, // Lumbridge spawn
            fatigue: 0,
            appearance_hair: 2,
            appearance_top: 8,
            appearance_bottom: 14,
            appearance_skin: 0,
            appearance_head: 1,
            appearance_body: 2,
            male: true,
            skull: 0,
            online: false,
        }
    }
}

/// Player skills database record.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct SkillsRecord {
    pub player_id: i64,
    pub attack_xp: i32,
    pub defense_xp: i32,
    pub strength_xp: i32,
    pub hits_xp: i32,
    pub ranged_xp: i32,
    pub prayer_xp: i32,
    pub magic_xp: i32,
    pub cooking_xp: i32,
    pub woodcutting_xp: i32,
    pub fletching_xp: i32,
    pub fishing_xp: i32,
    pub firemaking_xp: i32,
    pub crafting_xp: i32,
    pub smithing_xp: i32,
    pub mining_xp: i32,
    pub herblaw_xp: i32,
    pub agility_xp: i32,
    pub thieving_xp: i32,
    pub attack_cur: i32,
    pub defense_cur: i32,
    pub strength_cur: i32,
    pub hits_cur: i32,
    pub ranged_cur: i32,
    pub prayer_cur: i32,
    pub magic_cur: i32,
}

impl Default for SkillsRecord {
    fn default() -> Self {
        Self {
            player_id: 0,
            attack_xp: 0,
            defense_xp: 0,
            strength_xp: 0,
            hits_xp: 1154, // Level 10 hits
            ranged_xp: 0,
            prayer_xp: 0,
            magic_xp: 0,
            cooking_xp: 0,
            woodcutting_xp: 0,
            fletching_xp: 0,
            fishing_xp: 0,
            firemaking_xp: 0,
            crafting_xp: 0,
            smithing_xp: 0,
            mining_xp: 0,
            herblaw_xp: 0,
            agility_xp: 0,
            thieving_xp: 0,
            attack_cur: 1,
            defense_cur: 1,
            strength_cur: 1,
            hits_cur: 10,
            ranged_cur: 1,
            prayer_cur: 1,
            magic_cur: 1,
        }
    }
}

/// Inventory item database record.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct InventoryRecord {
    pub id: i64,
    pub player_id: i64,
    pub slot: i32,
    pub item_id: i32,
    pub amount: i32,
    pub equipped: bool,
    pub noted: bool,
}

/// Bank item database record.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct BankRecord {
    pub id: i64,
    pub player_id: i64,
    pub slot: i32,
    pub item_id: i32,
    pub amount: i32,
}

/// Friend list database record.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct FriendRecord {
    pub id: i64,
    pub player_id: i64,
    pub friend_id: i64,
    pub friend_name: String,
}

/// Ignore list database record.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct IgnoreRecord {
    pub id: i64,
    pub player_id: i64,
    pub ignored_id: i64,
    pub ignored_name: String,
}

/// Quest progress database record.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct QuestRecord {
    pub id: i64,
    pub player_id: i64,
    pub quest_id: i32,
    pub stage: i32,
    pub completed: bool,
}

/// Player settings database record.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct SettingsRecord {
    pub player_id: i64,
    pub camera_auto: bool,
    pub one_mouse_button: bool,
    pub sound_off: bool,
    pub block_chat: bool,
    pub block_private: bool,
    pub block_trade: bool,
    pub block_duel: bool,
}

impl Default for SettingsRecord {
    fn default() -> Self {
        Self {
            player_id: 0,
            camera_auto: true,
            one_mouse_button: false,
            sound_off: false,
            block_chat: false,
            block_private: false,
            block_trade: false,
            block_duel: false,
        }
    }
}

/// Login log database record.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct LoginLogRecord {
    pub id: i64,
    pub player_id: i64,
    pub login_time: i64,
    pub logout_time: Option<i64>,
    pub ip_address: String,
}

/// Chat log database record.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct ChatLogRecord {
    pub id: i64,
    pub player_id: i64,
    pub timestamp: i64,
    pub message_type: i32,
    pub message: String,
    pub recipient_id: Option<i64>,
}

/// Trade log database record.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct TradeLogRecord {
    pub id: i64,
    pub player1_id: i64,
    pub player2_id: i64,
    pub timestamp: i64,
    pub items1: String, // JSON array of items
    pub items2: String, // JSON array of items
}

/// NPC kill log database record.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct NpcKillRecord {
    pub id: i64,
    pub player_id: i64,
    pub npc_id: i32,
    pub timestamp: i64,
    pub x: i32,
    pub y: i32,
}

/// Drop log database record.
#[derive(Debug, Clone, FromRow, Serialize, Deserialize)]
pub struct DropLogRecord {
    pub id: i64,
    pub player_id: i64,
    pub npc_id: i32,
    pub item_id: i32,
    pub amount: i32,
    pub timestamp: i64,
}

/// SQL statements for schema creation.
pub mod sql {
    pub const CREATE_PLAYERS_TABLE: &str = r#"
        CREATE TABLE IF NOT EXISTS players (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username VARCHAR(12) NOT NULL UNIQUE,
            password_hash VARCHAR(255) NOT NULL,
            email VARCHAR(255),
            creation_date BIGINT NOT NULL,
            last_login BIGINT,
            login_ip VARCHAR(45),
            banned BOOLEAN DEFAULT FALSE,
            muted BOOLEAN DEFAULT FALSE,
            group_id INTEGER DEFAULT 10,
            combat_style INTEGER DEFAULT 0,
            x INTEGER DEFAULT 122,
            y INTEGER DEFAULT 647,
            fatigue INTEGER DEFAULT 0,
            appearance_hair INTEGER DEFAULT 2,
            appearance_top INTEGER DEFAULT 8,
            appearance_bottom INTEGER DEFAULT 14,
            appearance_skin INTEGER DEFAULT 0,
            appearance_head INTEGER DEFAULT 1,
            appearance_body INTEGER DEFAULT 2,
            male BOOLEAN DEFAULT TRUE,
            skull INTEGER DEFAULT 0,
            online BOOLEAN DEFAULT FALSE
        )
    "#;

    pub const CREATE_SKILLS_TABLE: &str = r#"
        CREATE TABLE IF NOT EXISTS player_skills (
            player_id INTEGER PRIMARY KEY,
            attack_xp INTEGER DEFAULT 0,
            defense_xp INTEGER DEFAULT 0,
            strength_xp INTEGER DEFAULT 0,
            hits_xp INTEGER DEFAULT 1154,
            ranged_xp INTEGER DEFAULT 0,
            prayer_xp INTEGER DEFAULT 0,
            magic_xp INTEGER DEFAULT 0,
            cooking_xp INTEGER DEFAULT 0,
            woodcutting_xp INTEGER DEFAULT 0,
            fletching_xp INTEGER DEFAULT 0,
            fishing_xp INTEGER DEFAULT 0,
            firemaking_xp INTEGER DEFAULT 0,
            crafting_xp INTEGER DEFAULT 0,
            smithing_xp INTEGER DEFAULT 0,
            mining_xp INTEGER DEFAULT 0,
            herblaw_xp INTEGER DEFAULT 0,
            agility_xp INTEGER DEFAULT 0,
            thieving_xp INTEGER DEFAULT 0,
            attack_cur INTEGER DEFAULT 1,
            defense_cur INTEGER DEFAULT 1,
            strength_cur INTEGER DEFAULT 1,
            hits_cur INTEGER DEFAULT 10,
            ranged_cur INTEGER DEFAULT 1,
            prayer_cur INTEGER DEFAULT 1,
            magic_cur INTEGER DEFAULT 1,
            FOREIGN KEY (player_id) REFERENCES players(id)
        )
    "#;

    pub const CREATE_INVENTORY_TABLE: &str = r#"
        CREATE TABLE IF NOT EXISTS player_inventory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id INTEGER NOT NULL,
            slot INTEGER NOT NULL,
            item_id INTEGER NOT NULL,
            amount INTEGER DEFAULT 1,
            equipped BOOLEAN DEFAULT FALSE,
            noted BOOLEAN DEFAULT FALSE,
            FOREIGN KEY (player_id) REFERENCES players(id)
        )
    "#;

    pub const CREATE_BANK_TABLE: &str = r#"
        CREATE TABLE IF NOT EXISTS player_bank (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id INTEGER NOT NULL,
            slot INTEGER NOT NULL,
            item_id INTEGER NOT NULL,
            amount INTEGER DEFAULT 1,
            FOREIGN KEY (player_id) REFERENCES players(id)
        )
    "#;

    pub const CREATE_FRIENDS_TABLE: &str = r#"
        CREATE TABLE IF NOT EXISTS player_friends (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id INTEGER NOT NULL,
            friend_id INTEGER NOT NULL,
            friend_name VARCHAR(12) NOT NULL,
            FOREIGN KEY (player_id) REFERENCES players(id)
        )
    "#;

    pub const CREATE_QUESTS_TABLE: &str = r#"
        CREATE TABLE IF NOT EXISTS player_quests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id INTEGER NOT NULL,
            quest_id INTEGER NOT NULL,
            stage INTEGER DEFAULT 0,
            completed BOOLEAN DEFAULT FALSE,
            FOREIGN KEY (player_id) REFERENCES players(id)
        )
    "#;

    pub const CREATE_SETTINGS_TABLE: &str = r#"
        CREATE TABLE IF NOT EXISTS player_settings (
            player_id INTEGER PRIMARY KEY,
            camera_auto BOOLEAN DEFAULT TRUE,
            one_mouse_button BOOLEAN DEFAULT FALSE,
            sound_off BOOLEAN DEFAULT FALSE,
            block_chat BOOLEAN DEFAULT FALSE,
            block_private BOOLEAN DEFAULT FALSE,
            block_trade BOOLEAN DEFAULT FALSE,
            block_duel BOOLEAN DEFAULT FALSE,
            FOREIGN KEY (player_id) REFERENCES players(id)
        )
    "#;
}

/// Run idempotent CREATE TABLE IF NOT EXISTS for every table the Rust port
/// uses. Safe to call on every boot — a no-op once the schema is in place.
///
/// MySQL note: the SQL is written in SQLite-leaning dialect (e.g.
/// `INTEGER PRIMARY KEY AUTOINCREMENT`). MySQL accepts most of it but real
/// MySQL deployments should run a migration tool (sqlx migrate, refinery)
/// against a hand-tuned schema instead. This initializer is intended for the
/// SQLite path used in dev/bench.
pub async fn init_schema(pool: &DatabasePool) -> Result<()> {
    let stmts = [
        sql::CREATE_PLAYERS_TABLE,
        sql::CREATE_SKILLS_TABLE,
        sql::CREATE_INVENTORY_TABLE,
        sql::CREATE_BANK_TABLE,
        sql::CREATE_FRIENDS_TABLE,
        sql::CREATE_QUESTS_TABLE,
        sql::CREATE_SETTINGS_TABLE,
    ];
    for stmt in stmts {
        match pool {
            DatabasePool::MySql(p) => sqlx::query(stmt)
                .execute(p)
                .await
                .map(|_| ())
                .context("schema init (mysql)")?,
            DatabasePool::Sqlite(p) => sqlx::query(stmt)
                .execute(p)
                .await
                .map(|_| ())
                .context("schema init (sqlite)")?,
        };
    }
    Ok(())
}
