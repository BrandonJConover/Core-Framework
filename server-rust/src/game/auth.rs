//! Authentication and session management.
//! Handles player login, registration, password hashing, and session tokens.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// Authentication configuration.
#[derive(Debug, Clone)]
pub struct AuthConfig {
    /// Session timeout in seconds.
    pub session_timeout: u64,
    /// Maximum failed login attempts before lockout.
    pub max_failed_attempts: u32,
    /// Lockout duration in seconds.
    pub lockout_duration: u64,
    /// Minimum password length.
    pub min_password_length: usize,
    /// Maximum password length.
    pub max_password_length: usize,
    /// Require email verification.
    pub require_email_verification: bool,
    /// Allow multiple sessions per account.
    pub allow_multiple_sessions: bool,
}

impl Default for AuthConfig {
    fn default() -> Self {
        Self {
            session_timeout: 3600, // 1 hour
            max_failed_attempts: 5,
            lockout_duration: 900, // 15 minutes
            min_password_length: 4,
            max_password_length: 20,
            require_email_verification: false,
            allow_multiple_sessions: false,
        }
    }
}

/// Login result.
#[derive(Debug, Clone)]
pub enum LoginResult {
    /// Login successful.
    Success(Session),
    /// Invalid username or password.
    InvalidCredentials,
    /// Account is banned.
    AccountBanned,
    /// Account is locked out.
    AccountLocked(u64), // Seconds remaining
    /// Account requires email verification.
    RequiresVerification,
    /// Already logged in.
    AlreadyLoggedIn,
    /// Server is full.
    ServerFull,
    /// Client version mismatch.
    VersionMismatch,
    /// Database error.
    DatabaseError(String),
}

/// Registration result.
#[derive(Debug, Clone)]
pub enum RegisterResult {
    /// Registration successful.
    Success(u64), // Player ID
    /// Username already taken.
    UsernameTaken,
    /// Invalid username format.
    InvalidUsername(String),
    /// Invalid password.
    InvalidPassword(String),
    /// Invalid email.
    InvalidEmail(String),
    /// Registration disabled.
    RegistrationDisabled,
    /// Database error.
    DatabaseError(String),
}

/// Password validation result.
#[derive(Debug, Clone)]
pub enum PasswordValidation {
    /// Password is valid.
    Valid,
    /// Password is too short.
    TooShort(usize), // Minimum required
    /// Password is too long.
    TooLong(usize), // Maximum allowed
    /// Password contains invalid characters.
    InvalidCharacters,
}

/// Username validation result.
#[derive(Debug, Clone)]
pub enum UsernameValidation {
    /// Username is valid.
    Valid,
    /// Username is too short.
    TooShort,
    /// Username is too long.
    TooLong,
    /// Username contains invalid characters.
    InvalidCharacters,
    /// Username is reserved.
    Reserved,
}

/// Player session.
#[derive(Debug, Clone)]
pub struct Session {
    /// Session token.
    pub token: String,
    /// Player ID.
    pub player_id: u64,
    /// Username.
    pub username: String,
    /// IP address.
    pub ip_address: String,
    /// Creation time.
    pub created_at: Instant,
    /// Last activity time.
    pub last_activity: Instant,
    /// Client version.
    pub client_version: u32,
    /// Is reconnection.
    pub is_reconnect: bool,
}

impl Session {
    /// Create a new session.
    pub fn new(player_id: u64, username: String, ip_address: String, client_version: u32) -> Self {
        let token = generate_session_token();
        let now = Instant::now();

        Self {
            token,
            player_id,
            username,
            ip_address,
            created_at: now,
            last_activity: now,
            client_version,
            is_reconnect: false,
        }
    }

    /// Update last activity.
    pub fn touch(&mut self) {
        self.last_activity = Instant::now();
    }

    /// Check if session is expired.
    pub fn is_expired(&self, timeout: Duration) -> bool {
        self.last_activity.elapsed() > timeout
    }

    /// Get session age in seconds.
    pub fn age_seconds(&self) -> u64 {
        self.created_at.elapsed().as_secs()
    }

    /// Get idle time in seconds.
    pub fn idle_seconds(&self) -> u64 {
        self.last_activity.elapsed().as_secs()
    }
}

/// Failed login tracking.
#[derive(Debug, Clone)]
struct FailedLogin {
    /// Number of failed attempts.
    attempts: u32,
    /// First failed attempt time.
    first_attempt: Instant,
    /// Last failed attempt time.
    last_attempt: Instant,
    /// Lockout until (if locked).
    locked_until: Option<Instant>,
}

impl FailedLogin {
    fn new() -> Self {
        let now = Instant::now();
        Self {
            attempts: 1,
            first_attempt: now,
            last_attempt: now,
            locked_until: None,
        }
    }

    fn increment(&mut self) {
        self.attempts += 1;
        self.last_attempt = Instant::now();
    }

    fn is_locked(&self) -> bool {
        if let Some(until) = self.locked_until {
            Instant::now() < until
        } else {
            false
        }
    }

    fn lock(&mut self, duration: Duration) {
        self.locked_until = Some(Instant::now() + duration);
    }

    fn seconds_remaining(&self) -> u64 {
        if let Some(until) = self.locked_until {
            let now = Instant::now();
            if now < until {
                return (until - now).as_secs();
            }
        }
        0
    }
}

/// Generate a random session token.
fn generate_session_token() -> String {
    use std::fmt::Write;
    let mut token = String::with_capacity(64);
    for _ in 0..32 {
        let byte: u8 = rand::random();
        write!(token, "{:02x}", byte).unwrap();
    }
    token
}

/// Simple password hashing (in production, use bcrypt/argon2).
pub fn hash_password(password: &str) -> String {
    // This is a placeholder - in production use proper password hashing
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    password.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

/// Verify password against hash.
pub fn verify_password(password: &str, hash: &str) -> bool {
    hash_password(password) == hash
}

/// Authentication manager.
#[derive(Debug)]
pub struct AuthManager {
    /// Configuration.
    config: AuthConfig,
    /// Active sessions by token.
    sessions: Arc<RwLock<HashMap<String, Session>>>,
    /// Sessions by player ID (for duplicate checking).
    player_sessions: Arc<RwLock<HashMap<u64, String>>>,
    /// Failed login tracking by IP.
    failed_logins: Arc<RwLock<HashMap<String, FailedLogin>>>,
    /// Reserved usernames.
    reserved_names: Vec<String>,
}

impl AuthManager {
    /// Create a new auth manager.
    pub fn new(config: AuthConfig) -> Self {
        Self {
            config,
            sessions: Arc::new(RwLock::new(HashMap::new())),
            player_sessions: Arc::new(RwLock::new(HashMap::new())),
            failed_logins: Arc::new(RwLock::new(HashMap::new())),
            reserved_names: vec![
                "admin".to_string(),
                "moderator".to_string(),
                "mod".to_string(),
                "system".to_string(),
                "server".to_string(),
                "jagex".to_string(),
                "andrew".to_string(),
            ],
        }
    }

    /// Validate username format.
    pub fn validate_username(&self, username: &str) -> UsernameValidation {
        if username.len() < 1 {
            return UsernameValidation::TooShort;
        }
        if username.len() > 12 {
            return UsernameValidation::TooLong;
        }

        // Check for valid characters (alphanumeric and underscore)
        if !username
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == ' ')
        {
            return UsernameValidation::InvalidCharacters;
        }

        // Check reserved names
        let lower = username.to_lowercase();
        if self.reserved_names.iter().any(|r| lower.contains(r)) {
            return UsernameValidation::Reserved;
        }

        UsernameValidation::Valid
    }

    /// Validate password.
    pub fn validate_password(&self, password: &str) -> PasswordValidation {
        if password.len() < self.config.min_password_length {
            return PasswordValidation::TooShort(self.config.min_password_length);
        }
        if password.len() > self.config.max_password_length {
            return PasswordValidation::TooLong(self.config.max_password_length);
        }

        // Check for printable ASCII characters only
        if !password.chars().all(|c| c.is_ascii_graphic() || c == ' ') {
            return PasswordValidation::InvalidCharacters;
        }

        PasswordValidation::Valid
    }

    /// Check if IP is locked out.
    pub async fn is_locked_out(&self, ip: &str) -> Option<u64> {
        let failed = self.failed_logins.read().await;
        if let Some(info) = failed.get(ip) {
            if info.is_locked() {
                return Some(info.seconds_remaining());
            }
        }
        None
    }

    /// Record failed login attempt.
    pub async fn record_failed_login(&self, ip: &str) {
        let mut failed = self.failed_logins.write().await;

        if let Some(info) = failed.get_mut(ip) {
            info.increment();
            if info.attempts >= self.config.max_failed_attempts {
                info.lock(Duration::from_secs(self.config.lockout_duration));
                warn!(
                    "IP {} locked out after {} failed attempts",
                    ip, info.attempts
                );
            }
        } else {
            failed.insert(ip.to_string(), FailedLogin::new());
        }
    }

    /// Clear failed login attempts for IP.
    pub async fn clear_failed_logins(&self, ip: &str) {
        let mut failed = self.failed_logins.write().await;
        failed.remove(ip);
    }

    /// Create a new session.
    pub async fn create_session(
        &self,
        player_id: u64,
        username: String,
        ip_address: String,
        client_version: u32,
    ) -> Result<Session, &'static str> {
        // Check for existing session
        if !self.config.allow_multiple_sessions {
            let player_sessions = self.player_sessions.read().await;
            if player_sessions.contains_key(&player_id) {
                return Err("Player already has an active session");
            }
        }

        let session = Session::new(player_id, username, ip_address, client_version);
        let token = session.token.clone();

        // Store session
        {
            let mut sessions = self.sessions.write().await;
            sessions.insert(token.clone(), session.clone());
        }

        // Track player session
        {
            let mut player_sessions = self.player_sessions.write().await;
            player_sessions.insert(player_id, token);
        }

        info!(
            "Created session for player {} (ID: {})",
            session.username, player_id
        );

        Ok(session)
    }

    /// Get session by token.
    pub async fn get_session(&self, token: &str) -> Option<Session> {
        let sessions = self.sessions.read().await;
        sessions.get(token).cloned()
    }

    /// Get session by player ID.
    pub async fn get_session_by_player(&self, player_id: u64) -> Option<Session> {
        let player_sessions = self.player_sessions.read().await;
        if let Some(token) = player_sessions.get(&player_id) {
            let sessions = self.sessions.read().await;
            return sessions.get(token).cloned();
        }
        None
    }

    /// Update session activity.
    pub async fn touch_session(&self, token: &str) -> bool {
        let mut sessions = self.sessions.write().await;
        if let Some(session) = sessions.get_mut(token) {
            session.touch();
            return true;
        }
        false
    }

    /// Validate session token.
    pub async fn validate_session(&self, token: &str) -> bool {
        let sessions = self.sessions.read().await;
        if let Some(session) = sessions.get(token) {
            let timeout = Duration::from_secs(self.config.session_timeout);
            return !session.is_expired(timeout);
        }
        false
    }

    /// Destroy session.
    pub async fn destroy_session(&self, token: &str) -> bool {
        let mut sessions = self.sessions.write().await;
        if let Some(session) = sessions.remove(token) {
            // Remove from player sessions
            let mut player_sessions = self.player_sessions.write().await;
            player_sessions.remove(&session.player_id);

            info!(
                "Destroyed session for player {} (ID: {})",
                session.username, session.player_id
            );
            return true;
        }
        false
    }

    /// Destroy session by player ID.
    pub async fn destroy_session_by_player(&self, player_id: u64) -> bool {
        let token = {
            let player_sessions = self.player_sessions.read().await;
            player_sessions.get(&player_id).cloned()
        };

        if let Some(token) = token {
            return self.destroy_session(&token).await;
        }
        false
    }

    /// Get active session count.
    pub async fn active_session_count(&self) -> usize {
        let sessions = self.sessions.read().await;
        sessions.len()
    }

    /// Cleanup expired sessions.
    pub async fn cleanup_expired_sessions(&self) -> usize {
        let timeout = Duration::from_secs(self.config.session_timeout);
        let mut removed = 0;

        let expired_tokens: Vec<String> = {
            let sessions = self.sessions.read().await;
            sessions
                .iter()
                .filter(|(_, s)| s.is_expired(timeout))
                .map(|(t, _)| t.clone())
                .collect()
        };

        for token in expired_tokens {
            if self.destroy_session(&token).await {
                removed += 1;
            }
        }

        if removed > 0 {
            debug!("Cleaned up {} expired sessions", removed);
        }

        // Also cleanup old failed login entries
        {
            let mut failed = self.failed_logins.write().await;
            let lockout_duration = Duration::from_secs(self.config.lockout_duration * 2);
            failed.retain(|_, info| info.last_attempt.elapsed() < lockout_duration);
        }

        removed
    }

    /// Get all active sessions.
    pub async fn get_all_sessions(&self) -> Vec<Session> {
        let sessions = self.sessions.read().await;
        sessions.values().cloned().collect()
    }

    /// Check if player is online.
    pub async fn is_player_online(&self, player_id: u64) -> bool {
        let player_sessions = self.player_sessions.read().await;
        player_sessions.contains_key(&player_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_password_hashing() {
        let password = "testpassword123";
        let hash = hash_password(password);

        assert!(verify_password(password, &hash));
        assert!(!verify_password("wrongpassword", &hash));
    }

    #[test]
    fn test_session_token_generation() {
        let token1 = generate_session_token();
        let token2 = generate_session_token();

        assert_eq!(token1.len(), 64);
        assert_eq!(token2.len(), 64);
        assert_ne!(token1, token2);
    }

    #[tokio::test]
    async fn test_session_management() {
        let config = AuthConfig::default();
        let manager = AuthManager::new(config);

        // Create session
        let session = manager
            .create_session(1, "testuser".to_string(), "127.0.0.1".to_string(), 235)
            .await
            .unwrap();

        assert!(manager.validate_session(&session.token).await);
        assert!(manager.is_player_online(1).await);
        assert_eq!(manager.active_session_count().await, 1);

        // Destroy session
        assert!(manager.destroy_session(&session.token).await);
        assert!(!manager.validate_session(&session.token).await);
        assert!(!manager.is_player_online(1).await);
    }

    #[tokio::test]
    async fn test_failed_login_lockout() {
        let mut config = AuthConfig::default();
        config.max_failed_attempts = 3;
        config.lockout_duration = 60;
        let manager = AuthManager::new(config);

        let ip = "192.168.1.1";

        // Should not be locked initially
        assert!(manager.is_locked_out(ip).await.is_none());

        // Record failed attempts
        for _ in 0..3 {
            manager.record_failed_login(ip).await;
        }

        // Should now be locked
        assert!(manager.is_locked_out(ip).await.is_some());
    }

    #[test]
    fn test_username_validation() {
        let config = AuthConfig::default();
        let manager = AuthManager::new(config);

        assert!(matches!(
            manager.validate_username("validname"),
            UsernameValidation::Valid
        ));
        assert!(matches!(
            manager.validate_username(""),
            UsernameValidation::TooShort
        ));
        assert!(matches!(
            manager.validate_username("thisisaverylongusername"),
            UsernameValidation::TooLong
        ));
        assert!(matches!(
            manager.validate_username("admin123"),
            UsernameValidation::Reserved
        ));
    }

    #[test]
    fn test_password_validation() {
        let config = AuthConfig::default();
        let manager = AuthManager::new(config);

        assert!(matches!(
            manager.validate_password("validpass"),
            PasswordValidation::Valid
        ));
        assert!(matches!(
            manager.validate_password("ab"),
            PasswordValidation::TooShort(_)
        ));
    }
}
