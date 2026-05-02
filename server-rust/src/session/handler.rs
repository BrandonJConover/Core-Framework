//! Packet handler module for processing incoming packets.

use crate::game::GameState;
use crate::protocol::{Packet, PacketReader};
use crate::protocol::opcodes::OpcodeIn;
use crate::protocol::packets::{LoginRequest, LoginResponse, ChatMessage, WalkToPoint};
use crate::session::{Session, SessionState};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// Packet handler result.
pub enum HandleResult {
    /// Continue processing.
    Continue,
    /// Disconnect the session.
    Disconnect,
    /// Error occurred.
    Error(String),
}

/// Handle an incoming packet.
pub async fn handle_packet(
    session: Arc<RwLock<Session>>,
    packet: Packet,
    game_state: Arc<RwLock<GameState>>,
) -> HandleResult {
    let opcode = OpcodeIn::from(packet.opcode);

    debug!("Handling packet {:?} from session {}", opcode, {
        let s = session.read().await;
        s.id
    });

    match opcode {
        OpcodeIn::Login => handle_login(session, packet, game_state).await,
        OpcodeIn::Logout => handle_logout(session).await,
        OpcodeIn::Ping => handle_ping(session).await,
        OpcodeIn::WalkToPoint => handle_walk(session, packet).await,
        OpcodeIn::PublicChat => handle_chat(session, packet, game_state).await,
        OpcodeIn::Command => handle_command(session, packet, game_state).await,
        _ => {
            // Check if session is logged in for most opcodes
            let session = session.read().await;
            if session.state != SessionState::LoggedIn {
                warn!("Received opcode {:?} from non-logged-in session", opcode);
                return HandleResult::Disconnect;
            }
            HandleResult::Continue
        }
    }
}

/// Handle login request.
async fn handle_login(
    session: Arc<RwLock<Session>>,
    packet: Packet,
    game_state: Arc<RwLock<GameState>>,
) -> HandleResult {
    let login_request = match LoginRequest::decode(&packet) {
        Ok(req) => req,
        Err(e) => {
            warn!("Failed to decode login request: {}", e);
            return HandleResult::Disconnect;
        }
    };

    info!("Login attempt for user: {}", login_request.username);

    // Update session state
    {
        let mut session = session.write().await;
        session.state = SessionState::Authenticating;
        session.client_version = login_request.client_version;
        session.touch();
    }

    // TODO: Authenticate against database
    // For now, accept all logins

    // Check if already logged in
    // let game = game_state.read().await;
    // ... check for existing session

    // Create player
    let session_id = {
        let session = session.read().await;
        session.id
    };

    let player = crate::game::player::Player::new(session_id, login_request.username.clone());

    // Register player with game state
    {
        let mut game = game_state.write().await;
        game.register_player(player).await;
    }

    // Update session
    {
        let mut session = session.write().await;
        session.state = SessionState::LoggedIn;

        // Send login success
        let response = LoginResponse::Success.encode();
        let _ = session.send(response).await;

        // Send welcome message
        session.message("Welcome to OpenRSC!").await;
    }

    info!("User {} logged in successfully", login_request.username);
    HandleResult::Continue
}

/// Handle logout request.
async fn handle_logout(session: Arc<RwLock<Session>>) -> HandleResult {
    let session_id = {
        let mut session = session.write().await;
        session.state = SessionState::Disconnecting;
        session.id
    };

    info!("Session {} logging out", session_id);
    HandleResult::Disconnect
}

/// Handle ping packet.
async fn handle_ping(session: Arc<RwLock<Session>>) -> HandleResult {
    let mut session = session.write().await;
    session.last_ping = std::time::Instant::now();
    session.touch();
    HandleResult::Continue
}

/// Handle walk to point.
async fn handle_walk(session: Arc<RwLock<Session>>, packet: Packet) -> HandleResult {
    let walk = match WalkToPoint::decode(&packet) {
        Ok(w) => w,
        Err(e) => {
            warn!("Failed to decode walk packet: {}", e);
            return HandleResult::Continue;
        }
    };

    let session = session.read().await;
    if session.state != SessionState::LoggedIn {
        return HandleResult::Continue;
    }

    // Update player position
    if let Some(ref player) = session.player {
        let mut player = player.write().await;
        player.position.x = walk.start_x as i32;
        player.position.y = walk.start_y as i32;

        // Process waypoints
        let mut x = walk.start_x as i32;
        let mut y = walk.start_y as i32;
        for (dx, dy) in walk.waypoints {
            x += dx as i32;
            y += dy as i32;
        }
        player.position.x = x;
        player.position.y = y;
    }

    HandleResult::Continue
}

/// Handle public chat.
async fn handle_chat(
    session: Arc<RwLock<Session>>,
    packet: Packet,
    game_state: Arc<RwLock<GameState>>,
) -> HandleResult {
    let chat = match ChatMessage::decode(&packet) {
        Ok(c) => c,
        Err(e) => {
            warn!("Failed to decode chat message: {}", e);
            return HandleResult::Continue;
        }
    };

    let (session_id, username) = {
        let session = session.read().await;
        if session.state != SessionState::LoggedIn {
            return HandleResult::Continue;
        }

        let username = if let Some(ref player) = session.player {
            player.read().await.username.clone()
        } else {
            return HandleResult::Continue;
        };

        (session.id, username)
    };

    info!("{}: {}", username, chat.message);

    // TODO: Broadcast to nearby players
    // For now, just echo back
    {
        let session = session.read().await;
        session.message(&format!("{}: {}", username, chat.message)).await;
    }

    HandleResult::Continue
}

/// Handle command.
async fn handle_command(
    session: Arc<RwLock<Session>>,
    packet: Packet,
    game_state: Arc<RwLock<GameState>>,
) -> HandleResult {
    let mut reader = PacketReader::new(&packet);
    let command = match reader.read_string() {
        Ok(c) => c,
        Err(e) => {
            warn!("Failed to read command: {}", e);
            return HandleResult::Continue;
        }
    };

    let session = session.read().await;
    if session.state != SessionState::LoggedIn {
        return HandleResult::Continue;
    }

    info!("Command from session {}: {}", session.id, command);

    // Parse command
    let parts: Vec<&str> = command.split_whitespace().collect();
    if parts.is_empty() {
        return HandleResult::Continue;
    }

    match parts[0].to_lowercase().as_str() {
        "online" => {
            let game = game_state.read().await;
            let count = game.online_count();
            session.message(&format!("Players online: {}", count)).await;
        }
        "pos" | "position" => {
            if let Some(ref player) = session.player {
                let player = player.read().await;
                session.message(&format!("Position: ({}, {})", player.position.x, player.position.y)).await;
            }
        }
        "help" => {
            session.message("Available commands: ::online, ::pos, ::help").await;
        }
        _ => {
            session.message(&format!("Unknown command: {}", parts[0])).await;
        }
    }

    HandleResult::Continue
}
