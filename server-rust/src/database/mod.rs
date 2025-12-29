//! Database module for player data persistence.
//! Supports MySQL/MariaDB and SQLite backends.

pub mod player_repository;
pub mod schema;

use anyhow::{Context, Result};
use sqlx::{mysql::MySqlPoolOptions, sqlite::SqlitePoolOptions, Pool, MySql, Sqlite};
use std::time::Duration;
use tracing::{info, warn};

/// Database connection type.
#[derive(Debug, Clone)]
pub enum DatabaseType {
    MySql,
    Sqlite,
}

impl From<&str> for DatabaseType {
    fn from(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "mysql" | "mariadb" => DatabaseType::MySql,
            "sqlite" | "sqlite3" => DatabaseType::Sqlite,
            _ => {
                warn!("Unknown database type '{}', defaulting to SQLite", s);
                DatabaseType::Sqlite
            }
        }
    }
}

/// Database configuration.
#[derive(Debug, Clone)]
pub struct DatabaseConfig {
    pub db_type: DatabaseType,
    pub host: String,
    pub port: u16,
    pub database: String,
    pub username: String,
    pub password: String,
    pub max_connections: u32,
    pub min_connections: u32,
    pub connect_timeout: Duration,
    pub idle_timeout: Duration,
}

impl Default for DatabaseConfig {
    fn default() -> Self {
        Self {
            db_type: DatabaseType::Sqlite,
            host: "localhost".to_string(),
            port: 3306,
            database: "openrsc".to_string(),
            username: "root".to_string(),
            password: String::new(),
            max_connections: 10,
            min_connections: 1,
            connect_timeout: Duration::from_secs(30),
            idle_timeout: Duration::from_secs(600),
        }
    }
}

impl DatabaseConfig {
    /// Build MySQL connection URL.
    pub fn mysql_url(&self) -> String {
        format!(
            "mysql://{}:{}@{}:{}/{}",
            self.username, self.password, self.host, self.port, self.database
        )
    }

    /// Build SQLite connection URL.
    pub fn sqlite_url(&self) -> String {
        format!("sqlite://{}?mode=rwc", self.database)
    }
}

/// Database connection pool.
#[derive(Clone)]
pub enum DatabasePool {
    MySql(Pool<MySql>),
    Sqlite(Pool<Sqlite>),
}

impl DatabasePool {
    /// Create a new database connection pool.
    pub async fn new(config: &DatabaseConfig) -> Result<Self> {
        match config.db_type {
            DatabaseType::MySql => {
                let pool = MySqlPoolOptions::new()
                    .max_connections(config.max_connections)
                    .min_connections(config.min_connections)
                    .acquire_timeout(config.connect_timeout)
                    .idle_timeout(config.idle_timeout)
                    .connect(&config.mysql_url())
                    .await
                    .context("Failed to connect to MySQL database")?;

                info!("Connected to MySQL database");
                Ok(DatabasePool::MySql(pool))
            }
            DatabaseType::Sqlite => {
                let pool = SqlitePoolOptions::new()
                    .max_connections(config.max_connections)
                    .min_connections(config.min_connections)
                    .acquire_timeout(config.connect_timeout)
                    .idle_timeout(config.idle_timeout)
                    .connect(&config.sqlite_url())
                    .await
                    .context("Failed to connect to SQLite database")?;

                info!("Connected to SQLite database");
                Ok(DatabasePool::Sqlite(pool))
            }
        }
    }

    /// Check if the database is connected.
    pub async fn is_connected(&self) -> bool {
        match self {
            DatabasePool::MySql(pool) => pool.acquire().await.is_ok(),
            DatabasePool::Sqlite(pool) => pool.acquire().await.is_ok(),
        }
    }

    /// Close the database connection pool.
    pub async fn close(&self) {
        match self {
            DatabasePool::MySql(pool) => pool.close().await,
            DatabasePool::Sqlite(pool) => pool.close().await,
        }
    }

    /// Get pool statistics.
    pub fn stats(&self) -> PoolStats {
        match self {
            DatabasePool::MySql(pool) => PoolStats {
                size: pool.size(),
                idle: pool.num_idle(),
            },
            DatabasePool::Sqlite(pool) => PoolStats {
                size: pool.size(),
                idle: pool.num_idle(),
            },
        }
    }
}

/// Pool statistics.
#[derive(Debug)]
pub struct PoolStats {
    pub size: u32,
    pub idle: usize,
}

/// Database transaction wrapper.
pub struct Transaction<'a> {
    inner: TransactionInner<'a>,
}

enum TransactionInner<'a> {
    MySql(sqlx::Transaction<'a, MySql>),
    Sqlite(sqlx::Transaction<'a, Sqlite>),
}

impl<'a> Transaction<'a> {
    /// Commit the transaction.
    pub async fn commit(self) -> Result<()> {
        match self.inner {
            TransactionInner::MySql(tx) => tx.commit().await?,
            TransactionInner::Sqlite(tx) => tx.commit().await?,
        }
        Ok(())
    }

    /// Rollback the transaction.
    pub async fn rollback(self) -> Result<()> {
        match self.inner {
            TransactionInner::MySql(tx) => tx.rollback().await?,
            TransactionInner::Sqlite(tx) => tx.rollback().await?,
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_database_config_default() {
        let config = DatabaseConfig::default();
        assert!(matches!(config.db_type, DatabaseType::Sqlite));
        assert_eq!(config.max_connections, 10);
    }

    #[test]
    fn test_database_type_from_str() {
        assert!(matches!(DatabaseType::from("mysql"), DatabaseType::MySql));
        assert!(matches!(DatabaseType::from("MariaDB"), DatabaseType::MySql));
        assert!(matches!(DatabaseType::from("sqlite"), DatabaseType::Sqlite));
        assert!(matches!(DatabaseType::from("unknown"), DatabaseType::Sqlite));
    }
}
