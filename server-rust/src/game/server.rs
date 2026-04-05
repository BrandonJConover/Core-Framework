//! Server state module — central hub connecting game state, sessions, and tick loop.

use crate::game::{GameState, Player, World, Entity, EntityId, Position};
use crate::protocol::{Packet, PacketBuilder, PacketReader};
use crate::protocol::opcodes::{OpcodeIn, OpcodeOut};
use crate::protocol::packets::{LoginRequest, LoginResponse};
use crate::session::{Session, SessionManager, SessionState};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{mpsc, RwLock};
use tracing::{debug, error, info, warn};

/// Tick duration in milliseconds (640ms = RSC game tick).
pub const TICK_DURATION_MS: u64 = 640;

/// Maximum players per server.
pub const MAX_PLAYERS: usize = 2000;

/// Idle timeout before disconnecting (5 minutes).
pub const IDLE_TIMEOUT: Duration = Duration::from_secs(300);

/// Auto-save interval (30 seconds).
pub const AUTO_SAVE_INTERVAL: u64 = 47; // ~30 seconds in ticks (30000 / 640)

/// Shared server state accessible from network handlers and game loop.
pub struct ServerState {
    pub sessions: SessionManager,
    pub game: GameState,
    pub tick_count: u64,
    pub start_time: Instant,
    pub shutting_down: bool,
}

impl ServerState {
    pub fn new() -> Self {
        let mut game = GameState::new(1); // 1 tick per cycle
        Self {
            sessions: SessionManager::new(),
            game,
            tick_count: 0,
            start_time: Instant::now(),
            shutting_down: false,
        }
    }

    /// Initialize game state (worlds, NPC spawns, etc.)
    pub async fn initialize(&mut self) -> anyhow::Result<()> {
        self.game.initialize().await?;
        info!("Server state initialized");
        Ok(())
    }

    /// Process a single game tick. Called every 640ms.
    pub async fn tick(&mut self) {
        self.tick_count += 1;
        let tick_start = Instant::now();

        // Phase 1: Process session timeouts
        let timed_out = self.sessions.process_timeouts().await;
        for session_id in timed_out {
            debug!("Session {} timed out", session_id);
        }

        // Phase 2: Update game state (worlds, NPCs, timers)
        self.game.tick().await;

        // Phase 3: Send entity updates to all logged-in sessions
        self.send_entity_updates().await;

        // Phase 4: Auto-save
        if self.tick_count % AUTO_SAVE_INTERVAL == 0 {
            self.auto_save().await;
        }

        // Track tick duration
        let tick_duration = tick_start.elapsed();
        if tick_duration.as_millis() > TICK_DURATION_MS as u128 {
            warn!(
                "Tick {} took {}ms (exceeds {}ms budget)",
                self.tick_count,
                tick_duration.as_millis(),
                TICK_DURATION_MS
            );
        }
    }

    /// Handle an incoming packet from a session.
    pub async fn handle_packet(&mut self, session_id: u64, packet: Packet) -> HandleResult {
        let opcode = OpcodeIn::from(packet.opcode);

        // Get session
        let session = match self.sessions.get_session(session_id) {
            Some(s) => s,
            None => {
                warn!("Packet from unknown session {}", session_id);
                return HandleResult::Disconnect;
            }
        };

        let session_state = {
            let s = session.read().await;
            s.state
        };

        match opcode {
            OpcodeIn::Login => self.handle_login(session, packet).await,
            OpcodeIn::Logout => self.handle_logout(session).await,
            OpcodeIn::Ping => {
                let mut s = session.write().await;
                s.last_ping = Instant::now();
                s.touch();
                HandleResult::Continue
            }
            OpcodeIn::WalkToPoint | OpcodeIn::WalkToEntity => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_walk(session, packet).await
            }
            OpcodeIn::PublicChat => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_chat(session, packet).await
            }
            OpcodeIn::Command => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_command(session, packet).await
            }
            OpcodeIn::PrivateMessage => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_private_message(session, packet).await
            }
            OpcodeIn::AttackNpc | OpcodeIn::AttackPlayer => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                // TODO: combat handling
                HandleResult::Continue
            }
            _ => {
                if session_state != SessionState::LoggedIn {
                    warn!("Opcode {:?} from non-logged-in session", opcode);
                    return HandleResult::Disconnect;
                }
                debug!("Unhandled opcode {:?}", opcode);
                HandleResult::Continue
            }
        }
    }

    /// Handle login request.
    async fn handle_login(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let login_request = match LoginRequest::decode(&packet) {
            Ok(req) => req,
            Err(e) => {
                warn!("Failed to decode login: {}", e);
                return HandleResult::Disconnect;
            }
        };

        info!("Login attempt: {}", login_request.username);

        // Update session to authenticating
        {
            let mut s = session.write().await;
            s.state = SessionState::Authenticating;
            s.client_version = login_request.client_version;
            s.touch();
        }

        // Check if already logged in
        if self.sessions.is_logged_in(&login_request.username) {
            let s = session.read().await;
            let _ = s.send(LoginResponse::AlreadyLoggedIn.encode()).await;
            return HandleResult::Disconnect;
        }

        // TODO: Authenticate against database
        // For now, accept all logins

        // Create player
        let session_id = {
            let s = session.read().await;
            s.id
        };

        let player = Player::new(session_id, login_request.username.clone());
        let player_arc = Arc::new(RwLock::new(player));

        // Register player in game state
        self.game.register_player_arc(session_id, player_arc.clone()).await;

        // Register username in session manager
        self.sessions.register_username(session_id, login_request.username.clone());

        // Update session
        {
            let mut s = session.write().await;
            s.state = SessionState::LoggedIn;
            s.player = Some(player_arc.clone());

            // Send login success response (raw byte, not framed)
            let _ = s.send(LoginResponse::Success.encode()).await;
        }

        // Send initial game state packets
        self.send_initial_packets(session, player_arc).await;

        info!("User {} logged in successfully", login_request.username);
        HandleResult::Continue
    }

    /// Send initial packets after login.
    async fn send_initial_packets(
        &self,
        session: Arc<RwLock<Session>>,
        player: Arc<RwLock<Player>>,
    ) {
        let s = session.read().await;
        let p = player.read().await;

        // Send world info
        let world_info = PacketBuilder::new(OpcodeOut::WorldInfo.into())
            .write_short(p.position.x as u16)  // player x
            .write_short(p.position.y as u16)  // player y
            .write_short(16)                    // plane/height
            .write_short(2304)                  // wilderness boundary
            .write_short(1)                     // is_members
            .build();
        let _ = s.send(world_info).await;

        // Send player stats
        let stats_packet = build_stats_packet(&p);
        let _ = s.send(stats_packet).await;

        // Send inventory
        let inv_packet = build_inventory_packet(&p);
        let _ = s.send(inv_packet).await;

        // Send equipment
        let equip_packet = build_equipment_packet(&p);
        let _ = s.send(equip_packet).await;

        // Send player settings
        let settings_packet = build_settings_packet(&p);
        let _ = s.send(settings_packet).await;

        // Send welcome message
        s.message("Welcome to OpenRSC!").await;
    }

    /// Handle logout request.
    async fn handle_logout(&mut self, session: Arc<RwLock<Session>>) -> HandleResult {
        let (session_id, player_id) = {
            let mut s = session.write().await;
            let player_id = s.player.as_ref().map(|p| {
                // We can't await inside this closure, so return the session_id as player_id
                s.id
            });
            s.state = SessionState::Disconnecting;
            (s.id, player_id)
        };

        // Save player data before removing
        if let Some(pid) = player_id {
            // TODO: Save to database
            self.game.unregister_player(pid).await;
        }

        info!("Session {} logged out", session_id);
        HandleResult::Disconnect
    }

    /// Handle walk packet.
    async fn handle_walk(
        &self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = PacketReader::new(&packet);
        let start_x = match reader.read_short() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let start_y = match reader.read_short() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };

        // Read waypoints
        let mut waypoints = Vec::new();
        while reader.has_remaining() {
            if let (Ok(dx), Ok(dy)) = (reader.read_sbyte(), reader.read_sbyte()) {
                waypoints.push((dx, dy));
            } else {
                break;
            }
        }

        let s = session.read().await;
        if let Some(ref player) = s.player {
            let mut p = player.write().await;

            // Clear any current action
            p.walking_queue.clear();

            // Set starting position
            p.walking_queue.push(Position::new(start_x as i32, start_y as i32));

            // Add waypoints
            let mut x = start_x as i32;
            let mut y = start_y as i32;
            for (dx, dy) in waypoints {
                x += dx as i32;
                y += dy as i32;
                p.walking_queue.push(Position::new(x, y));
            }
        }

        HandleResult::Continue
    }

    /// Handle public chat.
    async fn handle_chat(
        &self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = PacketReader::new(&packet);
        let message = match reader.read_string() {
            Ok(m) => m,
            Err(_) => return HandleResult::Continue,
        };

        let (session_id, username) = {
            let s = session.read().await;
            let username = if let Some(ref player) = s.player {
                player.read().await.username.clone()
            } else {
                return HandleResult::Continue;
            };
            (s.id, username)
        };

        info!("{}: {}", username, message);

        // Broadcast to nearby players
        // For now, broadcast to all logged-in sessions
        let chat_packet = PacketBuilder::new(OpcodeOut::ChatMessage.into())
            .write_short(session_id as u16)
            .write_string(&message)
            .build();
        self.sessions.broadcast(chat_packet).await;

        HandleResult::Continue
    }

    /// Handle private message.
    async fn handle_private_message(
        &self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = PacketReader::new(&packet);
        let target = match reader.read_string() {
            Ok(t) => t,
            Err(_) => return HandleResult::Continue,
        };
        let message = match reader.read_string() {
            Ok(m) => m,
            Err(_) => return HandleResult::Continue,
        };

        let sender = {
            let s = session.read().await;
            if let Some(ref player) = s.player {
                player.read().await.username.clone()
            } else {
                return HandleResult::Continue;
            }
        };

        // Find target session
        if let Some(target_session) = self.sessions.get_session_by_username(&target) {
            let ts = target_session.read().await;
            let pm_packet = PacketBuilder::new(OpcodeOut::PrivateMessage.into())
                .write_string(&sender)
                .write_string(&message)
                .build();
            let _ = ts.send(pm_packet).await;
        } else {
            let s = session.read().await;
            s.message(&format!("{} is not online", target)).await;
        }

        HandleResult::Continue
    }

    /// Handle command.
    async fn handle_command(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = PacketReader::new(&packet);
        let command = match reader.read_string() {
            Ok(c) => c,
            Err(_) => return HandleResult::Continue,
        };

        let parts: Vec<&str> = command.split_whitespace().collect();
        if parts.is_empty() {
            return HandleResult::Continue;
        }

        let s = session.read().await;

        match parts[0].to_lowercase().as_str() {
            "online" => {
                let count = self.game.online_count();
                s.message(&format!("Players online: {}", count)).await;
            }
            "pos" | "position" => {
                if let Some(ref player) = s.player {
                    let p = player.read().await;
                    s.message(&format!(
                        "Position: ({}, {}) Wilderness: {}",
                        p.position.x,
                        p.position.y,
                        p.position.wilderness_level()
                    )).await;
                }
            }
            "uptime" => {
                let uptime = self.start_time.elapsed();
                let hours = uptime.as_secs() / 3600;
                let minutes = (uptime.as_secs() % 3600) / 60;
                let seconds = uptime.as_secs() % 60;
                s.message(&format!("Uptime: {}h {}m {}s", hours, minutes, seconds)).await;
            }
            "tick" => {
                s.message(&format!("Current tick: {}", self.tick_count)).await;
            }
            "help" => {
                s.message("Commands: ::online, ::pos, ::uptime, ::tick, ::help").await;
            }
            _ => {
                s.message(&format!("Unknown command: {}", parts[0])).await;
            }
        }

        HandleResult::Continue
    }

    /// Send entity updates to all logged-in sessions.
    async fn send_entity_updates(&self) {
        // For each logged-in session, send position updates for nearby entities
        for session in self.sessions.all_sessions() {
            let s = session.read().await;
            if s.state != SessionState::LoggedIn {
                continue;
            }

            if let Some(ref player) = s.player {
                let p = player.read().await;
                // TODO: Send bit-packed player/NPC coordinate updates
                // TODO: Send appearance updates for new entities in view
                // TODO: Send ground item updates
                // TODO: Send game object updates
            }
        }
    }

    /// Auto-save all players.
    async fn auto_save(&self) {
        debug!("Auto-saving {} players...", self.game.online_count());
        // TODO: Save all player data to database
    }
}

/// Result of handling a packet.
#[derive(Debug)]
pub enum HandleResult {
    Continue,
    Disconnect,
}

// --- Packet building helpers ---

fn build_stats_packet(player: &Player) -> Packet {
    let mut builder = PacketBuilder::new(OpcodeOut::PlayerStats.into());

    // Current levels (18 skills)
    for skill_id in 0..18u8 {
        let skill = skill_from_id(skill_id);
        builder = builder.write_byte(player.skills.current_level(skill));
    }
    // Base levels
    for skill_id in 0..18u8 {
        let skill = skill_from_id(skill_id);
        builder = builder.write_byte(player.skills.level(skill));
    }
    // Experience
    for skill_id in 0..18u8 {
        let skill = skill_from_id(skill_id);
        builder = builder.write_int(player.skills.experience(skill));
    }

    builder.build()
}

fn build_inventory_packet(player: &Player) -> Packet {
    let mut builder = PacketBuilder::new(OpcodeOut::PlayerInventory.into());

    let items: Vec<_> = player.inventory.items()
        .iter()
        .filter_map(|s| s.as_ref())
        .collect();

    builder = builder.write_byte(items.len() as u8);

    for item in items {
        builder = builder.write_short(item.id as u16);
        builder = builder.write_byte(0); // wielded
        builder = builder.write_byte(if item.noted { 1 } else { 0 });
        if item.amount > 0 {
            builder = builder.write_int(item.amount);
        }
    }

    builder.build()
}

fn build_equipment_packet(player: &Player) -> Packet {
    let builder = PacketBuilder::new(OpcodeOut::PlayerEquipment.into());
    // TODO: encode equipped items
    builder.build()
}

fn build_settings_packet(player: &Player) -> Packet {
    PacketBuilder::new(OpcodeOut::PlayerSettings.into())
        .write_byte(if player.settings.camera_auto { 1 } else { 0 })
        .write_byte(if player.settings.one_mouse_button { 1 } else { 0 })
        .write_byte(if player.settings.sound_off { 1 } else { 0 })
        .build()
}

fn skill_from_id(id: u8) -> crate::game::player::SkillId {
    use crate::game::player::SkillId;
    match id {
        0 => SkillId::Attack,
        1 => SkillId::Defence,
        2 => SkillId::Strength,
        3 => SkillId::Hits,
        4 => SkillId::Ranged,
        5 => SkillId::Prayer,
        6 => SkillId::Magic,
        7 => SkillId::Cooking,
        8 => SkillId::Woodcutting,
        9 => SkillId::Fletching,
        10 => SkillId::Fishing,
        11 => SkillId::Firemaking,
        12 => SkillId::Crafting,
        13 => SkillId::Smithing,
        14 => SkillId::Mining,
        15 => SkillId::Herblore,
        16 => SkillId::Agility,
        17 => SkillId::Thieving,
        _ => SkillId::Attack,
    }
}
