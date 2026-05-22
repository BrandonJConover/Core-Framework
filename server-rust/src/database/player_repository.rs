//! Player repository for database operations.

use super::schema::*;
use super::DatabasePool;
use anyhow::{Context, Result};
use sqlx::Row;
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

    pub fn pool(&self) -> &DatabasePool {
        &self.pool
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
                sqlx::query(query)
                    .bind(x)
                    .bind(y)
                    .bind(username)
                    .execute(pool)
                    .await
                    .context("update_position_by_username (mysql)")?;
            }
            DatabasePool::Sqlite(pool) => {
                sqlx::query(query)
                    .bind(x)
                    .bind(y)
                    .bind(username)
                    .execute(pool)
                    .await
                    .context("update_position_by_username (sqlite)")?;
            }
        }
        Ok(())
    }

    /// Persist a player's full appearance row.
    pub async fn update_appearance(
        &self,
        player_id: i64,
        hair: u8,
        top: u8,
        bottom: u8,
        skin: u8,
        head: u8,
        body: u8,
        male: bool,
    ) -> Result<()> {
        let query = "UPDATE players SET appearance_hair = ?, appearance_top = ?, appearance_bottom = ?, appearance_skin = ?, appearance_head = ?, appearance_body = ?, male = ? WHERE id = ?";
        match &self.pool {
            DatabasePool::MySql(pool) => {
                sqlx::query(query)
                    .bind(hair as i32)
                    .bind(top as i32)
                    .bind(bottom as i32)
                    .bind(skin as i32)
                    .bind(head as i32)
                    .bind(body as i32)
                    .bind(male)
                    .bind(player_id)
                    .execute(pool)
                    .await
                    .context("update_appearance (mysql)")?;
            }
            DatabasePool::Sqlite(pool) => {
                sqlx::query(query)
                    .bind(hair as i32)
                    .bind(top as i32)
                    .bind(bottom as i32)
                    .bind(skin as i32)
                    .bind(head as i32)
                    .bind(body as i32)
                    .bind(male)
                    .bind(player_id)
                    .execute(pool)
                    .await
                    .context("update_appearance (sqlite)")?;
            }
        }
        Ok(())
    }

    /// Persist the selected combat style.
    pub async fn update_combat_style(&self, player_id: i64, combat_style: i32) -> Result<()> {
        let query = "UPDATE players SET combat_style = ? WHERE id = ?";
        match &self.pool {
            DatabasePool::MySql(pool) => {
                sqlx::query(query)
                    .bind(combat_style)
                    .bind(player_id)
                    .execute(pool)
                    .await
                    .context("update_combat_style (mysql)")?;
            }
            DatabasePool::Sqlite(pool) => {
                sqlx::query(query)
                    .bind(combat_style)
                    .bind(player_id)
                    .execute(pool)
                    .await
                    .context("update_combat_style (sqlite)")?;
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

    /// Replace a player's persisted inventory slots.
    pub async fn save_inventory(
        &self,
        player_id: i64,
        inventory: &[InventoryRecord],
    ) -> Result<()> {
        let delete_query = "DELETE FROM player_inventory WHERE player_id = ?";
        let insert_query = r#"
            INSERT INTO player_inventory (
                player_id, slot, item_id, amount, equipped, noted
            ) VALUES (?, ?, ?, ?, ?, ?)
        "#;

        match &self.pool {
            DatabasePool::MySql(pool) => {
                let mut tx = pool
                    .begin()
                    .await
                    .context("begin inventory transaction (mysql)")?;
                sqlx::query(delete_query)
                    .bind(player_id)
                    .execute(&mut *tx)
                    .await
                    .context("delete inventory (mysql)")?;
                for item in inventory {
                    sqlx::query(insert_query)
                        .bind(player_id)
                        .bind(item.slot)
                        .bind(item.item_id)
                        .bind(item.amount)
                        .bind(item.equipped)
                        .bind(item.noted)
                        .execute(&mut *tx)
                        .await
                        .context("insert inventory (mysql)")?;
                }
                tx.commit()
                    .await
                    .context("commit inventory transaction (mysql)")?;
            }
            DatabasePool::Sqlite(pool) => {
                let mut tx = pool
                    .begin()
                    .await
                    .context("begin inventory transaction (sqlite)")?;
                sqlx::query(delete_query)
                    .bind(player_id)
                    .execute(&mut *tx)
                    .await
                    .context("delete inventory (sqlite)")?;
                for item in inventory {
                    sqlx::query(insert_query)
                        .bind(player_id)
                        .bind(item.slot)
                        .bind(item.item_id)
                        .bind(item.amount)
                        .bind(item.equipped)
                        .bind(item.noted)
                        .execute(&mut *tx)
                        .await
                        .context("insert inventory (sqlite)")?;
                }
                tx.commit()
                    .await
                    .context("commit inventory transaction (sqlite)")?;
            }
        }

        debug!(
            "Saved {} inventory item(s) for player {}",
            inventory.len(),
            player_id
        );
        Ok(())
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

    /// Replace a player's persisted bank slots.
    pub async fn save_bank(&self, player_id: i64, bank: &[BankRecord]) -> Result<()> {
        let delete_query = "DELETE FROM player_bank WHERE player_id = ?";
        let insert_query = r#"
            INSERT INTO player_bank (
                player_id, slot, item_id, amount
            ) VALUES (?, ?, ?, ?)
        "#;

        match &self.pool {
            DatabasePool::MySql(pool) => {
                let mut tx = pool
                    .begin()
                    .await
                    .context("begin bank transaction (mysql)")?;
                sqlx::query(delete_query)
                    .bind(player_id)
                    .execute(&mut *tx)
                    .await
                    .context("delete bank (mysql)")?;
                for item in bank {
                    sqlx::query(insert_query)
                        .bind(player_id)
                        .bind(item.slot)
                        .bind(item.item_id)
                        .bind(item.amount)
                        .execute(&mut *tx)
                        .await
                        .context("insert bank (mysql)")?;
                }
                tx.commit()
                    .await
                    .context("commit bank transaction (mysql)")?;
            }
            DatabasePool::Sqlite(pool) => {
                let mut tx = pool
                    .begin()
                    .await
                    .context("begin bank transaction (sqlite)")?;
                sqlx::query(delete_query)
                    .bind(player_id)
                    .execute(&mut *tx)
                    .await
                    .context("delete bank (sqlite)")?;
                for item in bank {
                    sqlx::query(insert_query)
                        .bind(player_id)
                        .bind(item.slot)
                        .bind(item.item_id)
                        .bind(item.amount)
                        .execute(&mut *tx)
                        .await
                        .context("insert bank (sqlite)")?;
                }
                tx.commit()
                    .await
                    .context("commit bank transaction (sqlite)")?;
            }
        }

        debug!("Saved {} bank item(s) for player {}", bank.len(), player_id);
        Ok(())
    }

    /// Get player settings.
    pub async fn get_settings(&self, player_id: i64) -> Result<Option<SettingsRecord>> {
        let query = "SELECT * FROM player_settings WHERE player_id = ?";

        match &self.pool {
            DatabasePool::MySql(pool) => {
                let result = sqlx::query_as::<_, SettingsRecord>(query)
                    .bind(player_id)
                    .fetch_optional(pool)
                    .await
                    .context("Failed to get player settings")?;
                Ok(result)
            }
            DatabasePool::Sqlite(pool) => {
                let result = sqlx::query_as::<_, SettingsRecord>(query)
                    .bind(player_id)
                    .fetch_optional(pool)
                    .await
                    .context("Failed to get player settings")?;
                Ok(result)
            }
        }
    }

    /// Save player settings.
    pub async fn save_settings(&self, settings: &SettingsRecord) -> Result<()> {
        let query = r#"
            REPLACE INTO player_settings (
                player_id, camera_auto, one_mouse_button, sound_off,
                block_chat, block_private, block_trade, block_duel
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        "#;

        match &self.pool {
            DatabasePool::MySql(pool) => {
                sqlx::query(query)
                    .bind(settings.player_id)
                    .bind(settings.camera_auto)
                    .bind(settings.one_mouse_button)
                    .bind(settings.sound_off)
                    .bind(settings.block_chat)
                    .bind(settings.block_private)
                    .bind(settings.block_trade)
                    .bind(settings.block_duel)
                    .execute(pool)
                    .await
                    .context("save_settings (mysql)")?;
            }
            DatabasePool::Sqlite(pool) => {
                sqlx::query(query)
                    .bind(settings.player_id)
                    .bind(settings.camera_auto)
                    .bind(settings.one_mouse_button)
                    .bind(settings.sound_off)
                    .bind(settings.block_chat)
                    .bind(settings.block_private)
                    .bind(settings.block_trade)
                    .bind(settings.block_duel)
                    .execute(pool)
                    .await
                    .context("save_settings (sqlite)")?;
            }
        }
        Ok(())
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::database::schema::init_schema;
    use crate::database::DatabasePool;
    use sqlx::sqlite::SqlitePoolOptions;

    async fn sqlite_repo() -> PlayerRepository {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .unwrap();
        let pool = DatabasePool::Sqlite(pool);
        init_schema(&pool).await.unwrap();
        PlayerRepository::new(pool)
    }

    #[tokio::test]
    async fn saves_and_reloads_inventory_slots() {
        let repo = sqlite_repo().await;
        let mut player = PlayerRecord::default();
        player.username = "invpersist".to_string();
        player.password_hash = "hash".to_string();
        let player_id = repo.create(&player).await.unwrap();

        repo.save_inventory(
            player_id,
            &[
                InventoryRecord {
                    id: 0,
                    player_id,
                    slot: 4,
                    item_id: 10,
                    amount: 2,
                    equipped: false,
                    noted: false,
                },
                InventoryRecord {
                    id: 0,
                    player_id,
                    slot: 9,
                    item_id: 20,
                    amount: 1,
                    equipped: true,
                    noted: true,
                },
            ],
        )
        .await
        .unwrap();

        let inventory = repo.get_inventory(player_id).await.unwrap();
        assert_eq!(inventory.len(), 2);
        assert_eq!(inventory[0].slot, 4);
        assert_eq!(inventory[0].item_id, 10);
        assert_eq!(inventory[0].amount, 2);
        assert_eq!(inventory[1].slot, 9);
        assert!(inventory[1].equipped);
        assert!(inventory[1].noted);

        repo.save_inventory(
            player_id,
            &[InventoryRecord {
                id: 0,
                player_id,
                slot: 1,
                item_id: 30,
                amount: 5,
                equipped: false,
                noted: false,
            }],
        )
        .await
        .unwrap();

        let inventory = repo.get_inventory(player_id).await.unwrap();
        assert_eq!(inventory.len(), 1);
        assert_eq!(inventory[0].slot, 1);
        assert_eq!(inventory[0].item_id, 30);
        repo.pool().close().await;
    }

    #[tokio::test]
    async fn inventory_save_rolls_back_on_insert_failure() {
        let repo = sqlite_repo().await;
        let mut player = PlayerRecord::default();
        player.username = "invrollback".to_string();
        player.password_hash = "hash".to_string();
        let player_id = repo.create(&player).await.unwrap();

        repo.save_inventory(
            player_id,
            &[InventoryRecord {
                id: 0,
                player_id,
                slot: 2,
                item_id: 10,
                amount: 1,
                equipped: false,
                noted: false,
            }],
        )
        .await
        .unwrap();

        match repo.pool() {
            DatabasePool::Sqlite(pool) => {
                sqlx::query(
                    r#"
                    CREATE TRIGGER fail_inventory_sentinel
                    BEFORE INSERT ON player_inventory
                    WHEN NEW.item_id = 9999
                    BEGIN
                        SELECT RAISE(FAIL, 'sentinel inventory failure');
                    END
                    "#,
                )
                .execute(pool)
                .await
                .unwrap();
            }
            DatabasePool::MySql(_) => unreachable!(),
        }

        let result = repo
            .save_inventory(
                player_id,
                &[
                    InventoryRecord {
                        id: 0,
                        player_id,
                        slot: 3,
                        item_id: 20,
                        amount: 1,
                        equipped: false,
                        noted: false,
                    },
                    InventoryRecord {
                        id: 0,
                        player_id,
                        slot: 4,
                        item_id: 9999,
                        amount: 1,
                        equipped: false,
                        noted: false,
                    },
                ],
            )
            .await;

        assert!(result.is_err());
        let inventory = repo.get_inventory(player_id).await.unwrap();
        assert_eq!(inventory.len(), 1);
        assert_eq!(inventory[0].slot, 2);
        assert_eq!(inventory[0].item_id, 10);
        repo.pool().close().await;
    }

    #[tokio::test]
    async fn saves_and_reloads_bank_slots() {
        let repo = sqlite_repo().await;
        let mut player = PlayerRecord::default();
        player.username = "bankpersist".to_string();
        player.password_hash = "hash".to_string();
        let player_id = repo.create(&player).await.unwrap();

        repo.save_bank(
            player_id,
            &[
                BankRecord {
                    id: 0,
                    player_id,
                    slot: 0,
                    item_id: 10,
                    amount: 2,
                },
                BankRecord {
                    id: 0,
                    player_id,
                    slot: 3,
                    item_id: 20,
                    amount: 100,
                },
            ],
        )
        .await
        .unwrap();

        let bank = repo.get_bank(player_id).await.unwrap();
        assert_eq!(bank.len(), 2);
        assert_eq!(bank[0].slot, 0);
        assert_eq!(bank[0].item_id, 10);
        assert_eq!(bank[0].amount, 2);
        assert_eq!(bank[1].slot, 3);
        assert_eq!(bank[1].item_id, 20);
        assert_eq!(bank[1].amount, 100);

        repo.save_bank(
            player_id,
            &[BankRecord {
                id: 0,
                player_id,
                slot: 0,
                item_id: 30,
                amount: 5,
            }],
        )
        .await
        .unwrap();

        let bank = repo.get_bank(player_id).await.unwrap();
        assert_eq!(bank.len(), 1);
        assert_eq!(bank[0].item_id, 30);
        assert_eq!(bank[0].amount, 5);
        repo.pool().close().await;
    }

    #[tokio::test]
    async fn bank_save_rolls_back_on_insert_failure() {
        let repo = sqlite_repo().await;
        let mut player = PlayerRecord::default();
        player.username = "bankrollback".to_string();
        player.password_hash = "hash".to_string();
        let player_id = repo.create(&player).await.unwrap();

        repo.save_bank(
            player_id,
            &[BankRecord {
                id: 0,
                player_id,
                slot: 0,
                item_id: 10,
                amount: 1,
            }],
        )
        .await
        .unwrap();

        match repo.pool() {
            DatabasePool::Sqlite(pool) => {
                sqlx::query(
                    r#"
                    CREATE TRIGGER fail_bank_sentinel
                    BEFORE INSERT ON player_bank
                    WHEN NEW.item_id = 9999
                    BEGIN
                        SELECT RAISE(FAIL, 'sentinel bank failure');
                    END
                    "#,
                )
                .execute(pool)
                .await
                .unwrap();
            }
            DatabasePool::MySql(_) => unreachable!(),
        }

        let result = repo
            .save_bank(
                player_id,
                &[
                    BankRecord {
                        id: 0,
                        player_id,
                        slot: 0,
                        item_id: 20,
                        amount: 1,
                    },
                    BankRecord {
                        id: 0,
                        player_id,
                        slot: 1,
                        item_id: 9999,
                        amount: 1,
                    },
                ],
            )
            .await;

        assert!(result.is_err());
        let bank = repo.get_bank(player_id).await.unwrap();
        assert_eq!(bank.len(), 1);
        assert_eq!(bank[0].slot, 0);
        assert_eq!(bank[0].item_id, 10);
        repo.pool().close().await;
    }

    #[tokio::test]
    async fn saves_and_reloads_settings() {
        let repo = sqlite_repo().await;
        let mut player = PlayerRecord::default();
        player.username = "settingspersist".to_string();
        player.password_hash = "hash".to_string();
        let player_id = repo.create(&player).await.unwrap();

        let settings = SettingsRecord {
            player_id,
            camera_auto: true,
            one_mouse_button: true,
            sound_off: true,
            block_chat: true,
            block_private: false,
            block_trade: true,
            block_duel: false,
        };
        repo.save_settings(&settings).await.unwrap();

        let loaded = repo.get_settings(player_id).await.unwrap().unwrap();
        assert!(loaded.camera_auto);
        assert!(loaded.one_mouse_button);
        assert!(loaded.sound_off);
        assert!(loaded.block_chat);
        assert!(!loaded.block_private);
        assert!(loaded.block_trade);
        assert!(!loaded.block_duel);
        repo.pool().close().await;
    }
}
