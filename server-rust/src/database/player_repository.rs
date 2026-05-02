//! Player repository for database operations.

use super::schema::*;
use super::DatabasePool;
use anyhow::{Context, Result};
use sqlx::{Row};
use tracing::{debug, info};

/// Repository for player data operations.
pub struct PlayerRepository {
    pool: DatabasePool,
}

impl PlayerRepository {
    /// Create a new player repository.
    pub fn new(pool: DatabasePool) -> Self {
        Self { pool }
    }

    /// Find a player by username.
    pub async fn find_by_username(&self, username: &str) -> Result<Option<PlayerRecord>> {
        let query = "SELECT * FROM players WHERE username = ?";

        match &self.pool {
            DatabasePool::MySql(pool) => {
                let result = sqlx::query_as::<_, PlayerRecord>(query)
                    .bind(username)
                    .fetch_optional(pool)
                    .await
                    .context("Failed to find player by username")?;
                Ok(result)
            }
            DatabasePool::Sqlite(pool) => {
                let result = sqlx::query_as::<_, PlayerRecord>(query)
                    .bind(username)
                    .fetch_optional(pool)
                    .await
                    .context("Failed to find player by username")?;
                Ok(result)
            }
        }
    }

    /// Find a player by ID.
    pub async fn find_by_id(&self, id: i64) -> Result<Option<PlayerRecord>> {
        let query = "SELECT * FROM players WHERE id = ?";

        match &self.pool {
            DatabasePool::MySql(pool) => {
                let result = sqlx::query_as::<_, PlayerRecord>(query)
                    .bind(id)
                    .fetch_optional(pool)
                    .await
                    .context("Failed to find player by ID")?;
                Ok(result)
            }
            DatabasePool::Sqlite(pool) => {
                let result = sqlx::query_as::<_, PlayerRecord>(query)
                    .bind(id)
                    .fetch_optional(pool)
                    .await
                    .context("Failed to find player by ID")?;
                Ok(result)
            }
        }
    }

    /// Create a new player.
    pub async fn create(&self, player: &PlayerRecord) -> Result<i64> {
        let query = r#"
            INSERT INTO players (
                username, password_hash, email, creation_date, group_id,
                x, y, appearance_hair, appearance_top, appearance_bottom,
                appearance_skin, appearance_head, appearance_body, male
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        "#;

        match &self.pool {
            DatabasePool::MySql(pool) => {
                let result = sqlx::query(query)
                    .bind(&player.username)
                    .bind(&player.password_hash)
                    .bind(&player.email)
                    .bind(player.creation_date)
                    .bind(player.group_id)
                    .bind(player.x)
                    .bind(player.y)
                    .bind(player.appearance_hair)
                    .bind(player.appearance_top)
                    .bind(player.appearance_bottom)
                    .bind(player.appearance_skin)
                    .bind(player.appearance_head)
                    .bind(player.appearance_body)
                    .bind(player.male)
                    .execute(pool)
                    .await
                    .context("Failed to create player")?;

                info!("Created player: {}", player.username);
                Ok(result.last_insert_id() as i64)
            }
            DatabasePool::Sqlite(pool) => {
                let result = sqlx::query(query)
                    .bind(&player.username)
                    .bind(&player.password_hash)
                    .bind(&player.email)
                    .bind(player.creation_date)
                    .bind(player.group_id)
                    .bind(player.x)
                    .bind(player.y)
                    .bind(player.appearance_hair)
                    .bind(player.appearance_top)
                    .bind(player.appearance_bottom)
                    .bind(player.appearance_skin)
                    .bind(player.appearance_head)
                    .bind(player.appearance_body)
                    .bind(player.male)
                    .execute(pool)
                    .await
                    .context("Failed to create player")?;

                info!("Created player: {}", player.username);
                Ok(result.last_insert_rowid())
            }
        }
    }

    /// Update player position.
    pub async fn update_position(&self, player_id: i64, x: i32, y: i32) -> Result<()> {
        let query = "UPDATE players SET x = ?, y = ? WHERE id = ?";

        match &self.pool {
            DatabasePool::MySql(pool) => {
                sqlx::query(query)
                    .bind(x)
                    .bind(y)
                    .bind(player_id)
                    .execute(pool)
                    .await
                    .context("Failed to update player position")?;
            }
            DatabasePool::Sqlite(pool) => {
                sqlx::query(query)
                    .bind(x)
                    .bind(y)
                    .bind(player_id)
                    .execute(pool)
                    .await
                    .context("Failed to update player position")?;
            }
        }

        debug!("Updated position for player {}: ({}, {})", player_id, x, y);
        Ok(())
    }

    /// Update player position by username.
    ///
    /// The in-memory Player carries username but not the DB primary key, so
    /// the logout path uses this convenience that does a WHERE username = ?.
    /// Costs an indexed lookup; fine for logout/auto-save (not per-tick).
    pub async fn update_position_by_username(&self, username: &str, x: i32, y: i32) -> Result<()> {
        let query = "UPDATE players SET x = ?, y = ? WHERE username = ?";
        match &self.pool {
            DatabasePool::MySql(pool) => {
                sqlx::query(query).bind(x).bind(y).bind(username).execute(pool).await
                    .context("update_position_by_username (mysql)")?;
            }
            DatabasePool::Sqlite(pool) => {
                sqlx::query(query).bind(x).bind(y).bind(username).execute(pool).await
                    .context("update_position_by_username (sqlite)")?;
            }
        }
        Ok(())
    }

    /// Update player online status.
    pub async fn set_online(&self, player_id: i64, online: bool) -> Result<()> {
        let query = "UPDATE players SET online = ?, last_login = ? WHERE id = ?";
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        match &self.pool {
            DatabasePool::MySql(pool) => {
                sqlx::query(query)
                    .bind(online)
                    .bind(if online { Some(now) } else { None })
                    .bind(player_id)
                    .execute(pool)
                    .await
                    .context("Failed to update online status")?;
            }
            DatabasePool::Sqlite(pool) => {
                sqlx::query(query)
                    .bind(online)
                    .bind(if online { Some(now) } else { None })
                    .bind(player_id)
                    .execute(pool)
                    .await
                    .context("Failed to update online status")?;
            }
        }

        debug!("Set player {} online status to {}", player_id, online);
        Ok(())
    }

    /// Get player skills.
    pub async fn get_skills(&self, player_id: i64) -> Result<Option<SkillsRecord>> {
        let query = "SELECT * FROM player_skills WHERE player_id = ?";

        match &self.pool {
            DatabasePool::MySql(pool) => {
                let result = sqlx::query_as::<_, SkillsRecord>(query)
                    .bind(player_id)
                    .fetch_optional(pool)
                    .await
                    .context("Failed to get player skills")?;
                Ok(result)
            }
            DatabasePool::Sqlite(pool) => {
                let result = sqlx::query_as::<_, SkillsRecord>(query)
                    .bind(player_id)
                    .fetch_optional(pool)
                    .await
                    .context("Failed to get player skills")?;
                Ok(result)
            }
        }
    }

    /// Save player skills.
    pub async fn save_skills(&self, skills: &SkillsRecord) -> Result<()> {
        let query = r#"
            INSERT OR REPLACE INTO player_skills (
                player_id, attack_xp, defense_xp, strength_xp, hits_xp,
                ranged_xp, prayer_xp, magic_xp, cooking_xp, woodcutting_xp,
                fletching_xp, fishing_xp, firemaking_xp, crafting_xp,
                smithing_xp, mining_xp, herblaw_xp, agility_xp, thieving_xp,
                attack_cur, defense_cur, strength_cur, hits_cur,
                ranged_cur, prayer_cur, magic_cur
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        "#;

        match &self.pool {
            DatabasePool::MySql(pool) => {
                sqlx::query(query)
                    .bind(skills.player_id)
                    .bind(skills.attack_xp)
                    .bind(skills.defense_xp)
                    .bind(skills.strength_xp)
                    .bind(skills.hits_xp)
                    .bind(skills.ranged_xp)
                    .bind(skills.prayer_xp)
                    .bind(skills.magic_xp)
                    .bind(skills.cooking_xp)
                    .bind(skills.woodcutting_xp)
                    .bind(skills.fletching_xp)
                    .bind(skills.fishing_xp)
                    .bind(skills.firemaking_xp)
                    .bind(skills.crafting_xp)
                    .bind(skills.smithing_xp)
                    .bind(skills.mining_xp)
                    .bind(skills.herblaw_xp)
                    .bind(skills.agility_xp)
                    .bind(skills.thieving_xp)
                    .bind(skills.attack_cur)
                    .bind(skills.defense_cur)
                    .bind(skills.strength_cur)
                    .bind(skills.hits_cur)
                    .bind(skills.ranged_cur)
                    .bind(skills.prayer_cur)
                    .bind(skills.magic_cur)
                    .execute(pool)
                    .await
                    .context("Failed to save player skills")?;
            }
            DatabasePool::Sqlite(pool) => {
                sqlx::query(query)
                    .bind(skills.player_id)
                    .bind(skills.attack_xp)
                    .bind(skills.defense_xp)
                    .bind(skills.strength_xp)
                    .bind(skills.hits_xp)
                    .bind(skills.ranged_xp)
                    .bind(skills.prayer_xp)
                    .bind(skills.magic_xp)
                    .bind(skills.cooking_xp)
                    .bind(skills.woodcutting_xp)
                    .bind(skills.fletching_xp)
                    .bind(skills.fishing_xp)
                    .bind(skills.firemaking_xp)
                    .bind(skills.crafting_xp)
                    .bind(skills.smithing_xp)
                    .bind(skills.mining_xp)
                    .bind(skills.herblaw_xp)
                    .bind(skills.agility_xp)
                    .bind(skills.thieving_xp)
                    .bind(skills.attack_cur)
                    .bind(skills.defense_cur)
                    .bind(skills.strength_cur)
                    .bind(skills.hits_cur)
                    .bind(skills.ranged_cur)
                    .bind(skills.prayer_cur)
                    .bind(skills.magic_cur)
                    .execute(pool)
                    .await
                    .context("Failed to save player skills")?;
            }
        }

        debug!("Saved skills for player {}", skills.player_id);
        Ok(())
    }

    /// Get player inventory.
    pub async fn get_inventory(&self, player_id: i64) -> Result<Vec<InventoryRecord>> {
        let query = "SELECT * FROM player_inventory WHERE player_id = ? ORDER BY slot";

        match &self.pool {
            DatabasePool::MySql(pool) => {
                let result = sqlx::query_as::<_, InventoryRecord>(query)
                    .bind(player_id)
                    .fetch_all(pool)
                    .await
                    .context("Failed to get player inventory")?;
                Ok(result)
            }
            DatabasePool::Sqlite(pool) => {
                let result = sqlx::query_as::<_, InventoryRecord>(query)
                    .bind(player_id)
                    .fetch_all(pool)
                    .await
                    .context("Failed to get player inventory")?;
                Ok(result)
            }
        }
    }

    /// Get player bank.
    pub async fn get_bank(&self, player_id: i64) -> Result<Vec<BankRecord>> {
        let query = "SELECT * FROM player_bank WHERE player_id = ? ORDER BY slot";

        match &self.pool {
            DatabasePool::MySql(pool) => {
                let result = sqlx::query_as::<_, BankRecord>(query)
                    .bind(player_id)
                    .fetch_all(pool)
                    .await
                    .context("Failed to get player bank")?;
                Ok(result)
            }
            DatabasePool::Sqlite(pool) => {
                let result = sqlx::query_as::<_, BankRecord>(query)
                    .bind(player_id)
                    .fetch_all(pool)
                    .await
                    .context("Failed to get player bank")?;
                Ok(result)
            }
        }
    }

    /// Check if username exists.
    pub async fn username_exists(&self, username: &str) -> Result<bool> {
        let query = "SELECT COUNT(*) as count FROM players WHERE username = ?";

        match &self.pool {
            DatabasePool::MySql(pool) => {
                let row = sqlx::query(query)
                    .bind(username)
                    .fetch_one(pool)
                    .await
                    .context("Failed to check username existence")?;
                let count: i64 = row.get("count");
                Ok(count > 0)
            }
            DatabasePool::Sqlite(pool) => {
                let row = sqlx::query(query)
                    .bind(username)
                    .fetch_one(pool)
                    .await
                    .context("Failed to check username existence")?;
                let count: i64 = row.get("count");
                Ok(count > 0)
            }
        }
    }

    /// Ban a player.
    pub async fn ban_player(&self, player_id: i64, banned: bool) -> Result<()> {
        let query = "UPDATE players SET banned = ? WHERE id = ?";

        match &self.pool {
            DatabasePool::MySql(pool) => {
                sqlx::query(query)
                    .bind(banned)
                    .bind(player_id)
                    .execute(pool)
                    .await
                    .context("Failed to ban player")?;
            }
            DatabasePool::Sqlite(pool) => {
                sqlx::query(query)
                    .bind(banned)
                    .bind(player_id)
                    .execute(pool)
                    .await
                    .context("Failed to ban player")?;
            }
        }

        info!("Player {} ban status set to {}", player_id, banned);
        Ok(())
    }
}
