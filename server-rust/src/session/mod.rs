//! Session management module for player connections.
//! Handles connection lifecycle, authentication, and session state.

pub mod handler;

use crate::game::player::Player;
use crate::protocol::{Packet, PacketBuilder};
use crate::protocol::opcodes::OpcodeOut;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{mpsc, RwLock};
use tracing::{info, warn};

/// Session state enumeration.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionState {
    /// Initial connection, awaiting login.
    Connected,
    /// Login request received, authenticating.
    Authenticating,
    /// Successfully logged in and playing.
    LoggedIn,
    /// Disconnecting (graceful logout).
    Disconnecting,
    /// Disconnected (connection closed).
    Disconnected,
}

/// Player session representing an active connection.
pub struct Session {
    /// Unique session ID.
    pub id: u64,
    /// Client socket address.
    pub address: SocketAddr,
    /// Current session state.
    pub state: SessionState,
    /// Associated player (if logged in).
    pub player: Option<Arc<RwLock<Player>>>,
    /// Outgoing packet channel.
    pub tx: mpsc::Sender<Packet>,
    /// Session creation time.
    pub created_at: Instant,
    /// Last activity time.
    pub last_activity: Instant,
    /// Last ping time.
    pub last_ping: Instant,
    /// Client version.
    pub client_version: u32,
    /// Whether client is using custom client.
    pub custom_client: bool,
}

impl Session {
    /// Create a new session.
    pub fn new(id: u64, address: SocketAddr, tx: mpsc::Sender<Packet>) -> Self {
        let now = Instant::now();
        Self {
            id,
            address,
            state: SessionState::Connected,
            player: None,
            tx,
            created_at: now,
            last_activity: now,
            last_ping: now,
            client_version: 0,
            custom_client: false,
        }
    }

    /// Update last activity time.
    pub fn touch(&mut self) {
        self.last_activity = Instant::now();
    }

    /// Check if session has timed out.
    pub fn is_timed_out(&self, timeout: Duration) -> bool {
        self.last_activity.elapsed() > timeout
    }

    /// Check if session needs a ping.
    pub fn needs_ping(&self, interval: Duration) -> bool {
        self.last_ping.elapsed() > interval
    }

    /// Send a packet to this session.
    pub async fn send(&self, packet: Packet) -> bool {
        self.tx.send(packet).await.is_ok()
    }

    /// Send a server message.
    pub async fn message(&self, text: &str) {
        let packet = PacketBuilder::new(OpcodeOut::ServerMessage.into())
            .write_string(text)
            .build();
        let _ = self.send(packet).await;
    }

    /// Disconnect this session.
    pub fn disconnect(&mut self) {
        self.state = SessionState::Disconnecting;
    }

    /// Get session duration.
    pub fn duration(&self) -> Duration {
        self.created_at.elapsed()
    }

    /// Get idle time.
    pub fn idle_time(&self) -> Duration {
        self.last_activity.elapsed()
    }
}

/// Session manager for all active sessions.
pub struct SessionManager {
    sessions: HashMap<u64, Arc<RwLock<Session>>>,
    sessions_by_address: HashMap<SocketAddr, u64>,
    sessions_by_username: HashMap<String, u64>,
    next_session_id: u64,
    connection_timeout: Duration,
    ping_interval: Duration,
    max_sessions_per_ip: u32,
}

impl SessionManager {
    /// Create a new session manager.
    pub fn new() -> Self {
        Self {
            sessions: HashMap::new(),
            sessions_by_address: HashMap::new(),
            sessions_by_username: HashMap::new(),
            next_session_id: 1,
            connection_timeout: Duration::from_secs(60),
            ping_interval: Duration::from_secs(15),
            max_sessions_per_ip: 5,
        }
    }

    /// Configure timeouts.
    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.connection_timeout = timeout;
        self
    }

    /// Configure ping interval.
    pub fn with_ping_interval(mut self, interval: Duration) -> Self {
        self.ping_interval = interval;
        self
    }

    /// Configure max sessions per IP.
    pub fn with_max_sessions_per_ip(mut self, max: u32) -> Self {
        self.max_sessions_per_ip = max;
        self
    }

    /// Create a new session for a connection.
    pub async fn create_session(
        &mut self,
        address: SocketAddr,
        tx: mpsc::Sender<Packet>,
    ) -> Option<Arc<RwLock<Session>>> {
        // Check max sessions per IP
        let ip = address.ip();
        let count = self.sessions_by_address
            .keys()
            .filter(|addr| addr.ip() == ip)
            .count();

        if count >= self.max_sessions_per_ip as usize {
            warn!("Max sessions per IP reached for {}", ip);
            return None;
        }

        let session_id = self.next_session_id;
        self.next_session_id += 1;

        let session = Session::new(session_id, address, tx);
        let session = Arc::new(RwLock::new(session));

        self.sessions.insert(session_id, session.clone());
        self.sessions_by_address.insert(address, session_id);

        info!("Created session {} for {}", session_id, address);
        Some(session)
    }

    /// Remove a session.
    pub async fn remove_session(&mut self, session_id: u64) {
        if let Some(session) = self.sessions.remove(&session_id) {
            let session = session.read().await;

            // Remove from address lookup
            self.sessions_by_address.remove(&session.address);

            // Remove from username lookup if logged in
            if let Some(ref player) = session.player {
                let player = player.read().await;
                self.sessions_by_username.remove(&player.username);
            }

            info!("Removed session {} for {}", session_id, session.address);
        }
    }

    /// Get a session by ID.
    pub fn get_session(&self, session_id: u64) -> Option<Arc<RwLock<Session>>> {
        self.sessions.get(&session_id).cloned()
    }

    /// Get a session by address.
    pub fn get_session_by_address(&self, address: &SocketAddr) -> Option<Arc<RwLock<Session>>> {
        self.sessions_by_address
            .get(address)
            .and_then(|id| self.sessions.get(id))
            .cloned()
    }

    /// Get a session by username.
    pub fn get_session_by_username(&self, username: &str) -> Option<Arc<RwLock<Session>>> {
        self.sessions_by_username
            .get(username)
            .and_then(|id| self.sessions.get(id))
            .cloned()
    }

    /// Check if a username is logged in.
    pub fn is_logged_in(&self, username: &str) -> bool {
        self.sessions_by_username.contains_key(username)
    }

    /// Register a username for a session.
    pub fn register_username(&mut self, session_id: u64, username: String) {
        self.sessions_by_username.insert(username, session_id);
    }

    /// Get session count.
    pub fn session_count(&self) -> usize {
        self.sessions.len()
    }

    /// Get logged in count.
    pub fn logged_in_count(&self) -> usize {
        self.sessions_by_username.len()
    }

    /// Process session timeouts.
    pub async fn process_timeouts(&mut self) -> Vec<u64> {
        let mut timed_out = Vec::new();

        for (&id, session) in &self.sessions {
            let session = session.read().await;
            if session.is_timed_out(self.connection_timeout) {
                timed_out.push(id);
            }
        }

        for id in &timed_out {
            self.remove_session(*id).await;
        }

        timed_out
    }

    /// Broadcast a packet to all logged-in sessions.
    pub async fn broadcast(&self, packet: Packet) {
        for session in self.sessions.values() {
            let session = session.read().await;
            if session.state == SessionState::LoggedIn {
                let _ = session.send(packet.clone()).await;
            }
        }
    }

    /// Broadcast a message to all logged-in sessions.
    pub async fn broadcast_message(&self, message: &str) {
        let packet = PacketBuilder::new(OpcodeOut::ServerMessage.into())
            .write_string(message)
            .build();
        self.broadcast(packet).await;
    }

    /// Get all sessions.
    pub fn all_sessions(&self) -> Vec<Arc<RwLock<Session>>> {
        self.sessions.values().cloned().collect()
    }
}

impl Default for SessionManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_session_creation() {
        let mut manager = SessionManager::new();
        let (tx, _rx) = mpsc::channel(10);
        let addr: SocketAddr = "127.0.0.1:12345".parse().unwrap();

        let session = manager.create_session(addr, tx).await;
        assert!(session.is_some());
        assert_eq!(manager.session_count(), 1);
    }

    #[tokio::test]
    async fn test_session_timeout() {
        let session = Session::new(
            1,
            "127.0.0.1:12345".parse().unwrap(),
            mpsc::channel(10).0,
        );

        assert!(!session.is_timed_out(Duration::from_secs(60)));
    }
}
