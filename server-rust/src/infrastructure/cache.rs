use anyhow::Result;
use deadpool_redis::{Config, Pool, Runtime};
use redis::AsyncCommands;
use serde::{de::DeserializeOwned, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use tracing::debug;

use super::config::RedisConfig;

/// Redis cache with connection pooling and common operations.
pub struct RedisCache {
    pool: Pool,
    key_prefix: String,
    default_ttl: u64,
    connected: AtomicBool,
}

impl RedisCache {
    /// Creates a new Redis cache with the given configuration.
    pub async fn new(config: &RedisConfig) -> Result<Self> {
        let cfg = Config::from_url(&config.url);
        let pool = cfg.create_pool(Some(Runtime::Tokio1))?;

        // Test connection
        let mut conn = pool.get().await?;
        let _: String = redis::cmd("PING").query_async(&mut *conn).await?;

        Ok(Self {
            pool,
            key_prefix: config.key_prefix.clone(),
            default_ttl: config.default_ttl_seconds,
            connected: AtomicBool::new(true),
        })
    }

    /// Gets a value from cache.
    pub async fn get<T: DeserializeOwned>(&self, key: &str) -> Result<Option<T>> {
        let mut conn = self.pool.get().await?;
        let full_key = self.prefix_key(key);

        let value: Option<String> = conn.get(&full_key).await?;
        match value {
            Some(json) => Ok(Some(serde_json::from_str(&json)?)),
            None => Ok(None),
        }
    }

    /// Sets a value in cache with default TTL.
    pub async fn set<T: Serialize>(&self, key: &str, value: &T) -> Result<()> {
        self.set_with_ttl(key, value, self.default_ttl).await
    }

    /// Sets a value in cache with specific TTL.
    pub async fn set_with_ttl<T: Serialize>(&self, key: &str, value: &T, ttl_seconds: u64) -> Result<()> {
        let mut conn = self.pool.get().await?;
        let full_key = self.prefix_key(key);
        let json = serde_json::to_string(value)?;

        if ttl_seconds > 0 {
            conn.set_ex::<_, _, ()>(&full_key, json, ttl_seconds).await?;
        } else {
            conn.set::<_, _, ()>(&full_key, json).await?;
        }

        Ok(())
    }

    /// Deletes a key from cache.
    pub async fn delete(&self, key: &str) -> Result<bool> {
        let mut conn = self.pool.get().await?;
        let full_key = self.prefix_key(key);
        let result: i64 = conn.del(&full_key).await?;
        Ok(result > 0)
    }

    /// Checks if a key exists.
    pub async fn exists(&self, key: &str) -> Result<bool> {
        let mut conn = self.pool.get().await?;
        let full_key = self.prefix_key(key);
        Ok(conn.exists(&full_key).await?)
    }

    /// Sets a key only if it doesn't exist (atomic).
    pub async fn set_nx<T: Serialize>(&self, key: &str, value: &T, ttl_seconds: u64) -> Result<bool> {
        let mut conn = self.pool.get().await?;
        let full_key = self.prefix_key(key);
        let json = serde_json::to_string(value)?;

        let result: bool = conn.set_nx(&full_key, &json).await?;
        if result && ttl_seconds > 0 {
            conn.expire::<_, ()>(&full_key, ttl_seconds as i64).await?;
        }
        Ok(result)
    }

    /// Increments a counter.
    pub async fn incr(&self, key: &str) -> Result<i64> {
        let mut conn = self.pool.get().await?;
        let full_key = self.prefix_key(key);
        Ok(conn.incr(&full_key, 1i64).await?)
    }

    // ==================== LEADERBOARD OPERATIONS ====================

    /// Updates a player's score in a leaderboard.
    pub async fn leaderboard_update(&self, board: &str, member: &str, score: f64) -> Result<()> {
        let mut conn = self.pool.get().await?;
        let key = self.prefix_key(&format!("leaderboard:{}", board));
        conn.zadd::<_, _, _, ()>(&key, member, score).await?;
        Ok(())
    }

    /// Gets top N entries from a leaderboard.
    pub async fn leaderboard_top(&self, board: &str, count: isize) -> Result<Vec<LeaderboardEntry>> {
        let mut conn = self.pool.get().await?;
        let key = self.prefix_key(&format!("leaderboard:{}", board));

        let results: Vec<(String, f64)> = conn.zrevrange_withscores(&key, 0, count - 1).await?;

        Ok(results
            .into_iter()
            .enumerate()
            .map(|(rank, (member, score))| LeaderboardEntry {
                member,
                score,
                rank: rank + 1,
            })
            .collect())
    }

    /// Gets a player's rank in a leaderboard (1-indexed).
    pub async fn leaderboard_rank(&self, board: &str, member: &str) -> Result<Option<usize>> {
        let mut conn = self.pool.get().await?;
        let key = self.prefix_key(&format!("leaderboard:{}", board));

        let rank: Option<isize> = conn.zrevrank(&key, member).await?;
        Ok(rank.map(|r| r as usize + 1))
    }

    // ==================== RATE LIMITING ====================

    /// Checks rate limit. Returns true if under limit, false if exceeded.
    pub async fn check_rate_limit(&self, key: &str, max_requests: u32, window_seconds: u64) -> Result<bool> {
        let mut conn = self.pool.get().await?;
        let full_key = self.prefix_key(&format!("ratelimit:{}", key));

        let current: i64 = conn.incr(&full_key, 1i64).await?;
        if current == 1 {
            conn.expire::<_, ()>(&full_key, window_seconds as i64).await?;
        }

        Ok(current <= max_requests as i64)
    }

    /// Gets remaining rate limit quota.
    pub async fn rate_limit_remaining(&self, key: &str, max_requests: u32) -> Result<u32> {
        let mut conn = self.pool.get().await?;
        let full_key = self.prefix_key(&format!("ratelimit:{}", key));

        let current: Option<i64> = conn.get(&full_key).await?;
        match current {
            Some(count) => Ok((max_requests as i64 - count).max(0) as u32),
            None => Ok(max_requests),
        }
    }

    // ==================== ONLINE PLAYER TRACKING ====================

    /// Sets a player as online on a server.
    pub async fn set_player_online(&self, username: &str, server_id: &str) -> Result<()> {
        let mut conn = self.pool.get().await?;
        let all_key = self.prefix_key("online:all");
        let servers_key = self.prefix_key("online:servers");

        conn.sadd::<_, _, ()>(&all_key, username).await?;
        conn.hset::<_, _, _, ()>(&servers_key, username, server_id).await?;
        Ok(())
    }

    /// Sets a player as offline.
    pub async fn set_player_offline(&self, username: &str) -> Result<()> {
        let mut conn = self.pool.get().await?;
        let all_key = self.prefix_key("online:all");
        let servers_key = self.prefix_key("online:servers");

        conn.srem::<_, _, ()>(&all_key, username).await?;
        conn.hdel::<_, _, ()>(&servers_key, username).await?;
        Ok(())
    }

    /// Checks if a player is online.
    pub async fn is_player_online(&self, username: &str) -> Result<bool> {
        let mut conn = self.pool.get().await?;
        let all_key = self.prefix_key("online:all");
        Ok(conn.sismember(&all_key, username).await?)
    }

    /// Gets the count of online players.
    pub async fn online_count(&self) -> Result<u64> {
        let mut conn = self.pool.get().await?;
        let all_key = self.prefix_key("online:all");
        Ok(conn.scard(&all_key).await?)
    }

    // ==================== PUB/SUB ====================

    /// Publishes a message to a channel.
    pub async fn publish(&self, channel: &str, message: &str) -> Result<u64> {
        let mut conn = self.pool.get().await?;
        let full_channel = self.prefix_key(channel);
        Ok(conn.publish(&full_channel, message).await?)
    }

    // ==================== UTILITIES ====================

    pub fn is_connected(&self) -> bool {
        self.connected.load(Ordering::Relaxed)
    }

    pub async fn health_check(&self) -> bool {
        match self.pool.get().await {
            Ok(mut conn) => {
                let result: Result<String, _> = redis::cmd("PING").query_async(&mut *conn).await;
                let healthy = result.is_ok();
                self.connected.store(healthy, Ordering::Relaxed);
                healthy
            }
            Err(_) => {
                self.connected.store(false, Ordering::Relaxed);
                false
            }
        }
    }

    pub async fn close(&mut self) -> Result<()> {
        self.connected.store(false, Ordering::Relaxed);
        debug!("Redis connection pool closed");
        Ok(())
    }

    fn prefix_key(&self, key: &str) -> String {
        format!("{}{}", self.key_prefix, key)
    }
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct LeaderboardEntry {
    pub member: String,
    pub score: f64,
    pub rank: usize,
}
