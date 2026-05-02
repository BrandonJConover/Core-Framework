//! Server state module — central hub connecting game state, sessions, and tick loop.

use crate::database::player_repository::PlayerRepository;
use crate::game::{GameState, Player, Entity, EntityId, Position};
use crate::game::appearance::build_appearance_data;
use crate::game::equipment::Equipment as CanonicalEquipment;
use crate::game::game_object::ObjectType;
use crate::game::item::ItemId;
use crate::game::state_updater::{
    GameObjectSnapshot, GameStateUpdater, GroundItemSnapshot, KnownEntityList, NpcSnapshot,
    PlayerSnapshot,
};
use crate::protocol::{Packet, PacketBuilder, PacketReader};
use crate::protocol::opcodes::{OpcodeIn, OpcodeOut};
use crate::protocol::packets::{LoginRequest, LoginResponse};
use crate::session::{Session, SessionManager, SessionState};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

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
    /// Optional player repository — None means accept-all auth + no persistence
    /// (handy for the connection-storm bench). Some(repo) routes login through
    /// bcrypt verification and persists position/skills on logout + auto-save.
    pub players: Option<Arc<PlayerRepository>>,
    /// Per-session entity tracking lists for the full GameStateUpdater pipeline.
    ///
    /// Keyed by session id. Lazily created on first tick and removed on logout.
    /// Each value is (known_players, known_npcs) so the updater can diff what
    /// the client already knows about vs what's now in view.
    pub known_lists: HashMap<u64, (KnownEntityList, KnownEntityList)>,
}

impl ServerState {
    pub fn new() -> Self {
        let game = GameState::new(1); // 1 tick per cycle
        Self {
            sessions: SessionManager::new(),
            game,
            tick_count: 0,
            start_time: Instant::now(),
            shutting_down: false,
            players: None,
            known_lists: HashMap::new(),
        }
    }

    /// Attach a player repository (enables DB-backed auth + persistence).
    pub fn with_players(mut self, repo: Arc<PlayerRepository>) -> Self {
        self.players = Some(repo);
        self
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
                // Combat is intentionally unimplemented in this revision — the
                // Rust port is targeted at protocol+tick benchmarking, not
                // gameplay parity. Java server remains authoritative for combat.
                debug!("attack opcode {:?} dropped (combat not implemented)", opcode);
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

        // DB-backed auth when a repository is attached. With no repo,
        // fall through to accept-all (bench / smoke-test mode).
        if let Some(ref repo) = self.players {
            match repo.find_by_username(&login_request.username).await {
                Ok(Some(record)) => {
                    if record.banned {
                        let s = session.read().await;
                        let _ = s.send(LoginResponse::AccountDisabled.encode()).await;
                        return HandleResult::Disconnect;
                    }
                    if !verify_password(&login_request.password, &record.password_hash) {
                        let s = session.read().await;
                        let _ = s.send(LoginResponse::InvalidCredentials.encode()).await;
                        return HandleResult::Disconnect;
                    }
                }
                Ok(None) => {
                    // Account-create-on-first-login is intentionally OFF when a
                    // repo is attached — registration is a separate flow.
                    let s = session.read().await;
                    let _ = s.send(LoginResponse::InvalidCredentials.encode()).await;
                    return HandleResult::Disconnect;
                }
                Err(e) => {
                    warn!("DB lookup failed for {}: {}", login_request.username, e);
                    let s = session.read().await;
                    let _ = s.send(LoginResponse::LoginServerOffline.encode()).await;
                    return HandleResult::Disconnect;
                }
            }
        }

        // Create in-memory Player. When DB is wired we should rehydrate from
        // record (position, skills, inventory, etc.); leaving that for the
        // next pass — for now the player starts at the default Lumbridge spawn.
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

        // Save player data before removing.
        if let Some(pid) = player_id {
            if let Some(ref repo) = self.players {
                // Best-effort save: a failed write logs and disconnects, but
                // doesn't tear down the server. Only position is persisted in
                // this revision; skills/inventory writeback are next.
                if let Some(player_arc) = self.game.get_player(pid) {
                    let p = player_arc.read().await;
                    if let Err(e) = repo
                        .update_position_by_username(&p.username, p.position.x, p.position.y)
                        .await
                    {
                        warn!("Failed to persist position for {}: {}", p.username, e);
                    }
                }
            }
            self.game.unregister_player(pid).await;
        }

        // Purge per-session entity tracking lists so they don't leak memory for
        // players who never log back in.
        self.known_lists.remove(&session_id);

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
    ///
    /// Uses [`GameStateUpdater::generate_updates`] to produce the full RSC
    /// binary update stream per session — player positions/appearances, NPC
    /// positions/appearances, game-objects, and ground-items — exactly as the
    /// Java server's `GameStateUpdater.updatePlayers` does.
    ///
    /// Pipeline:
    ///   0. Acquire a single read lock on the world, snapshot all NPCs,
    ///      game-objects, and ground-items, then release the lock.
    ///   1. Collect a [`PlayerSnapshot`] (with full appearance data) for every
    ///      online player (one read pass).
    ///   2. For each session, retrieve (or lazily create) its per-session
    ///      [`KnownEntityList`] pair, filter objects/items by view distance,
    ///      call `generate_updates`, convert the returned packets, and send.
    async fn send_entity_updates(&mut self) {
        // ------------------------------------------------------------------
        // Pass 0: collect world-level snapshots under a single read lock.
        // ------------------------------------------------------------------
        let (all_npcs, all_objects, all_ground_items) =
            if let Some(world_arc) = self.game.get_world("Main World") {
                let world = world_arc.read().await;

                // NPC snapshots — indexed sequentially for client npc_index.
                let npcs: Vec<NpcSnapshot> = world
                    .npcs
                    .iter()
                    .enumerate()
                    .map(|(idx, (entity_id, npc))| NpcSnapshot {
                        entity_id: *entity_id,
                        npc_index: idx as u16,
                        def_id: npc.definition_id,
                        position: npc.position,
                        // world::Npc has no direction; default South.
                        direction: npc.direction,
                        moved_this_tick: npc.moved_this_tick,
                        removed: npc.is_dead(),
                    })
                    .collect();

                // Game-object snapshots (all objects in world).
                let objects: Vec<GameObjectSnapshot> = world
                    .game_objects
                    .values()
                    .filter(|obj| obj.active)
                    .map(|obj| GameObjectSnapshot {
                        // world::GameObject uses `id` where state_updater
                        // expects `def_id`; they carry the same definition id.
                        def_id: obj.id,
                        position: obj.position,
                        // world::GameObject has no ObjectDirection; default 0.
                        direction: 0,
                        // world::GameObject has no ObjectType; default Scenery.
                        object_type: ObjectType::Scenery,
                    })
                    .collect();

                // Ground-item snapshots — position comes from the map key.
                let ground_items: Vec<GroundItemSnapshot> = world
                    .ground_items
                    .iter()
                    .flat_map(|(pos, items)| {
                        items.iter().map(move |item| GroundItemSnapshot {
                            // world::GroundItem.item_id is u32; ItemId is a
                            // newtype wrapper around u32.
                            item_id: ItemId(item.item_id),
                            amount: item.amount,
                            position: *pos,
                        })
                    })
                    .collect();

                (npcs, objects, ground_items)
            } else {
                (Vec::new(), Vec::new(), Vec::new())
            };

        // ------------------------------------------------------------------
        // Pass 1: build a snapshot of every online player (with appearance).
        // ------------------------------------------------------------------
        let sessions = self.sessions.all_sessions();
        let mut all_players: Vec<PlayerSnapshot> = Vec::with_capacity(sessions.len());
        for session in &sessions {
            let s = session.read().await;
            if s.state != SessionState::LoggedIn {
                continue;
            }
            if let Some(ref pa) = s.player {
                let p = pa.read().await;
                // Build the full appearance blob (username, equipment,
                // colours, skull, clan tag) — sent once per new observer.
                let appearance_data = if p.appearance_changed {
                    // Player uses its own local Equipment type; the canonical
                    // Equipment (expected by build_appearance_data) is separate.
                    // Stub with an empty canonical Equipment until the two types
                    // are unified — all colours/gender/skull still encode correctly.
                    let stub_equip = CanonicalEquipment::new();
                    build_appearance_data(&p.username, &p.appearance, &stub_equip, 0, 0)
                } else {
                    Vec::new()
                };
                all_players.push(PlayerSnapshot {
                    entity_id: EntityId(p.id),
                    player_index: p.player_index,
                    position: p.position,
                    direction: p.direction,
                    moved_this_tick: !p.walking_queue.is_empty(),
                    appearance_changed: p.appearance_changed,
                    appearance_data,
                });
            }
        }

        // ------------------------------------------------------------------
        // Pass 2: per-session update generation + send.
        // ------------------------------------------------------------------
        const VIEW_RADIUS: i32 = 16;
        for session in &sessions {
            // Capture session metadata under a short read lock.
            let captured = {
                let s = session.read().await;
                if s.state != SessionState::LoggedIn {
                    continue;
                }
                match s.player {
                    Some(ref pa) => {
                        let p = pa.read().await;
                        Some((s.id, EntityId(p.id), p.position))
                    }
                    None => None,
                }
            };

            let (session_id, player_id, player_pos) = match captured {
                Some(x) => x,
                None => continue,
            };

            // Filter objects and ground items to this player's view area.
            let nearby_objects: Vec<GameObjectSnapshot> = all_objects
                .iter()
                .filter(|o| {
                    (o.position.x - player_pos.x).abs() <= VIEW_RADIUS
                        && (o.position.y - player_pos.y).abs() <= VIEW_RADIUS
                })
                .cloned()
                .collect();

            let nearby_ground_items: Vec<GroundItemSnapshot> = all_ground_items
                .iter()
                .filter(|g| {
                    (g.position.x - player_pos.x).abs() <= VIEW_RADIUS
                        && (g.position.y - player_pos.y).abs() <= VIEW_RADIUS
                })
                .cloned()
                .collect();

            // Lazily create known-entity lists for this session.
            let (kp, kn) = self
                .known_lists
                .entry(session_id)
                .or_insert_with(|| {
                    (KnownEntityList::for_players(), KnownEntityList::for_npcs())
                });

            // Generate the full outbound update packet set for this player.
            let game_packets = GameStateUpdater::generate_updates(
                player_id,
                player_pos,
                kp,
                kn,
                &all_players,
                &all_npcs,
                &nearby_objects,
                &nearby_ground_items,
            );

            // Re-acquire session lock to send (short-lived, after known_lists
            // borrow ends so the borrow checker is satisfied).
            let s = session.read().await;
            for gp in game_packets {
                let wire = Packet::new(gp.opcode, gp.payload);
                let _ = s.send(wire).await;
            }

            // Clear appearance_changed so we don't re-send the blob next tick.
            if let Some(ref pa) = s.player {
                if let Ok(mut p) = pa.try_write() {
                    p.appearance_changed = false;
                }
            }
        }
    }

    /// Auto-save all players.
    ///
    /// Persistence is deferred (see handle_logout). For benchmarking we still
    /// emit the debug counter so tick-rate dashboards can see the auto-save
    /// boundary; once a DB layer is wired this will iterate online players
    /// and persist each one.
    async fn auto_save(&self) {
        debug!("Auto-save tick (deferred): {} players online", self.game.online_count());
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
    use crate::game::player::EquipmentSlot;
    const SLOTS: [EquipmentSlot; 10] = [
        EquipmentSlot::Head, EquipmentSlot::Cape, EquipmentSlot::Amulet,
        EquipmentSlot::Weapon, EquipmentSlot::Body, EquipmentSlot::Shield,
        EquipmentSlot::Legs, EquipmentSlot::Gloves, EquipmentSlot::Boots,
        EquipmentSlot::Ring,
    ];

    let equipped: Vec<(u8, &crate::game::player::Item)> = SLOTS
        .iter()
        .enumerate()
        .filter_map(|(idx, slot)| player.equipment.get(*slot).map(|i| (idx as u8, i)))
        .collect();

    let mut builder = PacketBuilder::new(OpcodeOut::SEND_EQUIPMENT.into())
        .write_byte(equipped.len() as u8);
    for (slot_idx, item) in equipped {
        builder = builder
            .write_byte(slot_idx)
            .write_short(item.id as u16)
            .write_int(item.amount);
    }
    builder.build()
}

fn build_settings_packet(player: &Player) -> Packet {
    PacketBuilder::new(OpcodeOut::SEND_GAME_SETTINGS.into())
        .write_byte(if player.settings.camera_auto { 1 } else { 0 })
        .write_byte(if player.settings.one_mouse_button { 1 } else { 0 })
        .write_byte(if player.settings.sound_off { 1 } else { 0 })
        .build()
}

/// Verify a plain-text password against a bcrypt hash.
///
/// The Rust port assumes bcrypt-only password hashes. Java accounts created
/// after the bcrypt migration (~2018) work; legacy SHA-512(salt + MD5(plain))
/// accounts do NOT — those need to be re-hashed via the Java server's login
/// flow first. Returning false on any decode error is intentional (a malformed
/// hash should fail closed, not panic the tick loop).
pub fn verify_password(plain: &str, stored_hash: &str) -> bool {
    bcrypt::verify(plain, stored_hash).unwrap_or(false)
}

/// Hash a plain-text password with the same work factor as the Java server (10).
/// Used by the registration path / admin tooling, not by login.
pub fn hash_password(plain: &str) -> anyhow::Result<String> {
    Ok(bcrypt::hash(plain, 10)?)
}

/// Build a bit-packed SEND_PLAYER_COORDS for the local player only.
///
/// Mirrors the modern (Payload177+) layout from GameStateUpdater.updatePlayers:
///   (x, 11) (y, 13) (sprite, 4) (local_count=0, 8)
/// where `sprite` is the direction ordinal (Direction enum order matches the
/// Java sprite-int convention: N=0, NE=1, E=2, SE=3, S=4, SW=5, W=6, NW=7).
fn build_player_coords_packet(player: &Player) -> Packet {
    use crate::protocol::BitWriter;
    let mut bw = BitWriter::new();
    bw.write_bits(player.position.x, 11);
    bw.write_bits(player.position.y, 13);
    bw.write_bits(player.direction as i32, 4);
    bw.write_bits(0, 8); // local_players count — view-area not implemented
    bw.build_packet(OpcodeOut::SEND_PLAYER_COORDS.into())
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
