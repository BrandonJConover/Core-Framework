//! Database abstraction layer.
//! Provides async database operations for player data, world state, and game logs.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// Database configuration.
#[derive(Debug, Clone)]
pub struct DatabaseConfig {
    /// Database host.
    pub host: String,
    /// Database port.
    pub port: u16,
    /// Database name.
    pub database: String,
    /// Username.
    pub username: String,
    /// Password (should be loaded from environment).
    pub password: String,
    /// Maximum connections in pool.
    pub max_connections: u32,
    /// Connection timeout in seconds.
    pub connection_timeout: u64,
    /// Idle timeout in seconds.
    pub idle_timeout: u64,
}

impl Default for DatabaseConfig {
    fn default() -> Self {
        Self {
            host: "localhost".to_string(),
            port: 3306,
            database: "openrsc".to_string(),
            username: "openrsc".to_string(),
            password: String::new(),
            max_connections: 10,
            connection_timeout: 30,
            idle_timeout: 300,
        }
    }
}

/// Player data stored in database.
#[derive(Debug, Clone)]
pub struct PlayerData {
    /// Player ID.
    pub id: u64,
    /// Username.
    pub username: String,
    /// Password hash.
    pub password_hash: String,
    /// Email address.
    pub email: Option<String>,
    /// Creation timestamp.
    pub created_at: u64,
    /// Last login timestamp.
    pub last_login: u64,
    /// Total play time in seconds.
    pub play_time: u64,
    /// X coordinate.
    pub x: u16,
    /// Y coordinate.
    pub y: u16,
    /// Combat level.
    pub combat_level: u8,
    /// Total level.
    pub total_level: u16,
    /// Skill levels (skill_id -> level).
    pub skills: HashMap<u8, u8>,
    /// Skill experience (skill_id -> xp).
    pub experience: HashMap<u8, u32>,
    /// Bank items (item_id -> amount).
    pub bank: HashMap<u32, u32>,
    /// Inventory items.
    pub inventory: Vec<(u32, u32)>,
    /// Equipment slots.
    pub equipment: HashMap<u8, u32>,
    /// Quest states (quest_id -> stage).
    pub quests: HashMap<u16, u8>,
    /// Player settings/flags.
    pub settings: HashMap<String, String>,
    /// Is player banned.
    pub banned: bool,
    /// Is player muted.
    pub muted: bool,
    /// Player group/rank.
    pub group_id: u8,
}

impl Default for PlayerData {
    fn default() -> Self {
        Self {
            id: 0,
            username: String::new(),
            password_hash: String::new(),
            email: None,
            created_at: 0,
            last_login: 0,
            play_time: 0,
            x: 122,
            y: 647,
            combat_level: 3,
            total_level: 27,
            skills: HashMap::new(),
            experience: HashMap::new(),
            bank: HashMap::new(),
            inventory: Vec::new(),
            equipment: HashMap::new(),
            quests: HashMap::new(),
            settings: HashMap::new(),
            banned: false,
            muted: false,
            group_id: 0,
        }
    }
}

/// Game log entry.
#[derive(Debug, Clone)]
pub struct GameLog {
    /// Log ID.
    pub id: u64,
    /// Timestamp.
    pub timestamp: u64,
    /// Log type.
    pub log_type: LogType,
    /// Player ID (if applicable).
    pub player_id: Option<u64>,
    /// Secondary player ID (for trades, combat, etc).
    pub target_id: Option<u64>,
    /// Item ID (if applicable).
    pub item_id: Option<u32>,
    /// Item amount.
    pub amount: Option<u32>,
    /// X coordinate.
    pub x: Option<u16>,
    /// Y coordinate.
    pub y: Option<u16>,
    /// Additional data as JSON.
    pub data: Option<String>,
}

/// Types of game logs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LogType {
    /// Player logged in.
    Login,
    /// Player logged out.
    Logout,
    /// Player chat message.
    Chat,
    /// Private message.
    PrivateMessage,
    /// Trade completed.
    Trade,
    /// Duel completed.
    Duel,
    /// Player killed.
    Kill,
    /// Player died.
    Death,
    /// Item dropped.
    Drop,
    /// Item picked up.
    Pickup,
    /// Shop transaction.
    Shop,
    /// Bank transaction.
    Bank,
    /// Command used.
    Command,
    /// Report submitted.
    Report,
    /// Generic action.
    Action,
}

impl LogType {
    /// Get string representation.
    pub fn as_str(&self) -> &'static str {
        match self {
            LogType::Login => "login",
            LogType::Logout => "logout",
            LogType::Chat => "chat",
            LogType::PrivateMessage => "pm",
            LogType::Trade => "trade",
            LogType::Duel => "duel",
            LogType::Kill => "kill",
            LogType::Death => "death",
            LogType::Drop => "drop",
            LogType::Pickup => "pickup",
            LogType::Shop => "shop",
            LogType::Bank => "bank",
            LogType::Command => "command",
            LogType::Report => "report",
            LogType::Action => "action",
        }
    }
}

/// Query result for player lookups.
#[derive(Debug)]
pub enum PlayerLookupResult {
    /// Player found.
    Found(PlayerData),
    /// Player not found.
    NotFound,
    /// Database error.
    Error(String),
}

/// Database operation result.
pub type DbResult<T> = Result<T, DbError>;

/// Database error types.
#[derive(Debug, Clone)]
pub enum DbError {
    /// Connection failed.
    ConnectionFailed(String),
    /// Query failed.
    QueryFailed(String),
    /// Data not found.
    NotFound,
    /// Duplicate entry.
    DuplicateEntry(String),
    /// Constraint violation.
    ConstraintViolation(String),
    /// Timeout.
    Timeout,
    /// Pool exhausted.
    PoolExhausted,
    /// Serialization error.
    SerializationError(String),
}

impl std::fmt::Display for DbError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DbError::ConnectionFailed(msg) => write!(f, "Connection failed: {}", msg),
            DbError::QueryFailed(msg) => write!(f, "Query failed: {}", msg),
            DbError::NotFound => write!(f, "Data not found"),
            DbError::DuplicateEntry(msg) => write!(f, "Duplicate entry: {}", msg),
            DbError::ConstraintViolation(msg) => write!(f, "Constraint violation: {}", msg),
            DbError::Timeout => write!(f, "Database timeout"),
            DbError::PoolExhausted => write!(f, "Connection pool exhausted"),
            DbError::SerializationError(msg) => write!(f, "Serialization error: {}", msg),
        }
    }
}

impl std::error::Error for DbError {}

/// Database connection state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionState {
    /// Not connected.
    Disconnected,
    /// Connecting.
    Connecting,
    /// Connected and ready.
    Connected,
    /// Connection failed.
    Failed,
}

/// Database manager for game operations.
#[derive(Debug)]
pub struct DatabaseManager {
    /// Configuration.
    config: DatabaseConfig,
    /// Connection state.
    state: Arc<RwLock<ConnectionState>>,
    /// Cached player data.
    player_cache: Arc<RwLock<HashMap<u64, (PlayerData, Instant)>>>,
    /// Cache TTL.
    cache_ttl: Duration,
    /// Statistics.
    stats: Arc<RwLock<DbStats>>,
}

/// Database statistics.
#[derive(Debug, Default)]
pub struct DbStats {
    /// Total queries executed.
    pub queries_total: u64,
    /// Successful queries.
    pub queries_success: u64,
    /// Failed queries.
    pub queries_failed: u64,
    /// Cache hits.
    pub cache_hits: u64,
    /// Cache misses.
    pub cache_misses: u64,
    /// Average query time in microseconds.
    pub avg_query_time_us: u64,
}

impl DatabaseManager {
    /// Create a new database manager.
    pub fn new(config: DatabaseConfig) -> Self {
        Self {
            config,
            state: Arc::new(RwLock::new(ConnectionState::Disconnected)),
            player_cache: Arc::new(RwLock::new(HashMap::new())),
            cache_ttl: Duration::from_secs(300),
            stats: Arc::new(RwLock::new(DbStats::default())),
        }
    }

    /// Connect to the database.
    pub async fn connect(&self) -> DbResult<()> {
        let mut state = self.state.write().await;
        *state = ConnectionState::Connecting;

        // In a real implementation, this would establish the connection pool
        info!(
            "Connecting to database {}@{}:{}/{}",
            self.config.username, self.config.host, self.config.port, self.config.database
        );

        // Simulate connection
        *state = ConnectionState::Connected;
        info!("Database connected successfully");
        Ok(())
    }

    /// Disconnect from the database.
    pub async fn disconnect(&self) -> DbResult<()> {
        let mut state = self.state.write().await;
        *state = ConnectionState::Disconnected;
        info!("Database disconnected");
        Ok(())
    }

    /// Check if connected.
    pub async fn is_connected(&self) -> bool {
        let state = self.state.read().await;
        *state == ConnectionState::Connected
    }

    /// Get connection state.
    pub async fn connection_state(&self) -> ConnectionState {
        let state = self.state.read().await;
        *state
    }

    /// Load player by username.
    pub async fn load_player_by_username(&self, username: &str) -> DbResult<PlayerData> {
        let start = Instant::now();

        // Check cache first
        {
            let cache = self.player_cache.read().await;
            for (_, (data, cached_at)) in cache.iter() {
                if data.username.eq_ignore_ascii_case(username) {
                    if cached_at.elapsed() < self.cache_ttl {
                        let mut stats = self.stats.write().await;
                        stats.cache_hits += 1;
                        return Ok(data.clone());
                    }
                }
            }
        }

        let mut stats = self.stats.write().await;
        stats.cache_misses += 1;
        stats.queries_total += 1;

        // In a real implementation, this would query the database
        // For now, return not found
        stats.queries_success += 1;
        let elapsed = start.elapsed().as_micros() as u64;
        stats.avg_query_time_us = (stats.avg_query_time_us + elapsed) / 2;

        Err(DbError::NotFound)
    }

    /// Load player by ID.
    pub async fn load_player_by_id(&self, player_id: u64) -> DbResult<PlayerData> {
        // Check cache first
        {
            let cache = self.player_cache.read().await;
            if let Some((data, cached_at)) = cache.get(&player_id) {
                if cached_at.elapsed() < self.cache_ttl {
                    let mut stats = self.stats.write().await;
                    stats.cache_hits += 1;
                    return Ok(data.clone());
                }
            }
        }

        let mut stats = self.stats.write().await;
        stats.cache_misses += 1;
        stats.queries_total += 1;

        // In a real implementation, this would query the database
        Err(DbError::NotFound)
    }

    /// Save player data.
    pub async fn save_player(&self, data: &PlayerData) -> DbResult<()> {
        let start = Instant::now();

        let mut stats = self.stats.write().await;
        stats.queries_total += 1;

        // Update cache
        {
            let mut cache = self.player_cache.write().await;
            cache.insert(data.id, (data.clone(), Instant::now()));
        }

        // In a real implementation, this would update the database
        debug!("Saved player {} (ID: {})", data.username, data.id);

        stats.queries_success += 1;
        let elapsed = start.elapsed().as_micros() as u64;
        stats.avg_query_time_us = (stats.avg_query_time_us + elapsed) / 2;

        Ok(())
    }

    /// Create new player.
    pub async fn create_player(&self, username: &str, password_hash: &str) -> DbResult<u64> {
        let mut stats = self.stats.write().await;
        stats.queries_total += 1;

        // Check for duplicate username
        // In a real implementation, this would insert into the database
        let player_id = rand::random::<u64>();

        let data = PlayerData {
            id: player_id,
            username: username.to_string(),
            password_hash: password_hash.to_string(),
            created_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            ..Default::default()
        };

        // Cache the new player
        {
            let mut cache = self.player_cache.write().await;
            cache.insert(player_id, (data, Instant::now()));
        }

        stats.queries_success += 1;
        info!("Created new player {} (ID: {})", username, player_id);

        Ok(player_id)
    }

    /// Delete player.
    pub async fn delete_player(&self, player_id: u64) -> DbResult<()> {
        let mut stats = self.stats.write().await;
        stats.queries_total += 1;

        // Remove from cache
        {
            let mut cache = self.player_cache.write().await;
            cache.remove(&player_id);
        }

        // In a real implementation, this would delete from the database
        stats.queries_success += 1;
        info!("Deleted player {}", player_id);

        Ok(())
    }

    /// Log a game event.
    pub async fn log_event(&self, log: GameLog) -> DbResult<()> {
        let mut stats = self.stats.write().await;
        stats.queries_total += 1;

        // In a real implementation, this would insert into a log table
        debug!(
            "Logged event: {:?} for player {:?}",
            log.log_type, log.player_id
        );

        stats.queries_success += 1;
        Ok(())
    }

    /// Update player login time.
    pub async fn update_login(&self, player_id: u64) -> DbResult<()> {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        // Update cache if present
        {
            let mut cache = self.player_cache.write().await;
            if let Some((data, _)) = cache.get_mut(&player_id) {
                data.last_login = timestamp;
            }
        }

        // In a real implementation, update the database
        Ok(())
    }

    /// Ban a player.
    pub async fn ban_player(&self, player_id: u64, reason: &str) -> DbResult<()> {
        let mut stats = self.stats.write().await;
        stats.queries_total += 1;

        // Update cache
        {
            let mut cache = self.player_cache.write().await;
            if let Some((data, _)) = cache.get_mut(&player_id) {
                data.banned = true;
            }
        }

        warn!("Banned player {} - Reason: {}", player_id, reason);
        stats.queries_success += 1;
        Ok(())
    }

    /// Unban a player.
    pub async fn unban_player(&self, player_id: u64) -> DbResult<()> {
        // Update cache
        {
            let mut cache = self.player_cache.write().await;
            if let Some((data, _)) = cache.get_mut(&player_id) {
                data.banned = false;
            }
        }

        info!("Unbanned player {}", player_id);
        Ok(())
    }

    /// Get database statistics.
    pub async fn get_stats(&self) -> DbStats {
        let stats = self.stats.read().await;
        DbStats {
            queries_total: stats.queries_total,
            queries_success: stats.queries_success,
            queries_failed: stats.queries_failed,
            cache_hits: stats.cache_hits,
            cache_misses: stats.cache_misses,
            avg_query_time_us: stats.avg_query_time_us,
        }
    }

    /// Clear player cache.
    pub async fn clear_cache(&self) {
        let mut cache = self.player_cache.write().await;
        cache.clear();
        info!("Player cache cleared");
    }

    /// Cleanup expired cache entries.
    pub async fn cleanup_cache(&self) {
        let mut cache = self.player_cache.write().await;
        let before = cache.len();
        cache.retain(|_, (_, cached_at)| cached_at.elapsed() < self.cache_ttl);
        let removed = before - cache.len();
        if removed > 0 {
            debug!("Cleaned up {} expired cache entries", removed);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_database_manager() {
        let config = DatabaseConfig::default();
        let manager = DatabaseManager::new(config);

        assert!(!manager.is_connected().await);
        assert!(manager.connect().await.is_ok());
        assert!(manager.is_connected().await);
        assert!(manager.disconnect().await.is_ok());
        assert!(!manager.is_connected().await);
    }

    #[tokio::test]
    async fn test_player_creation() {
        let config = DatabaseConfig::default();
        let manager = DatabaseManager::new(config);
        manager.connect().await.unwrap();

        let player_id = manager
            .create_player("testuser", "hashedpassword")
            .await
            .unwrap();
        assert!(player_id > 0);

        // Player should be in cache
        let loaded = manager.load_player_by_id(player_id).await;
        assert!(loaded.is_ok());
    }

    #[tokio::test]
    async fn test_stats() {
        let config = DatabaseConfig::default();
        let manager = DatabaseManager::new(config);
        manager.connect().await.unwrap();

        // Create a player to generate some stats
        manager
            .create_player("statstest", "password")
            .await
            .unwrap();

        let stats = manager.get_stats().await;
        assert!(stats.queries_total > 0);
    }
}
