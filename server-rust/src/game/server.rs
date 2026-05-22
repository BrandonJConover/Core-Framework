//! Server state module — central hub connecting game state, sessions, and tick loop.

use crate::api::ticket::LoginTicketService;
use crate::database::player_repository::PlayerRepository;
use crate::database::schema::{
    BankRecord, InventoryRecord, PlayerRecord, SettingsRecord, SkillsRecord,
};
use crate::game::bank::BankError;
use crate::game::bank_handler::{BankHandler, BankHandlerError, BankItemAmountRequest};
use crate::game::combat::CombatStyle;
use crate::game::combat_event::{CombatManager, CombatType, Combatant, RoundResult};
use crate::game::content::runtime::{ContentRuntimePlan, ContentRuntimeSink};
use crate::game::content::{ContentEvent, ContentRegistry};
use crate::game::entity::Direction;
use crate::game::item::ItemRepository;
use crate::game::player::SkillId;
use crate::game::prayer::{PrayerId, PrayerState};
use crate::game::shop_handler::{ShopHandler, ShopHandlerError, ShopItemAmountRequest};
use crate::game::world::MovementCollisionPolicy;
use crate::game::{Entity, EntityId, GameState, Player, Position, World};
use crate::protocol::opcodes::{OpcodeIn, OpcodeOut};
use crate::protocol::packets::{LoginRequest, LoginResponse};
use crate::protocol::{Packet, PacketBuilder, PacketReader};
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
    /// Optional player repository — None means accept-all auth + no persistence
    /// (handy for the connection-storm bench). Some(repo) routes login through
    /// bcrypt verification and persists position/skills on logout + auto-save.
    pub players: Option<Arc<PlayerRepository>>,
    /// All active combat encounters. Resolved each tick after entity updates.
    pub combat: CombatManager,
    /// Bank interface session tracker and packet helpers.
    pub bank: BankHandler,
    /// Shop interface session tracker and packet helpers.
    pub shop: ShopHandler,
    /// Compiled Rust content trigger registry.
    pub content: ContentRegistry,
    /// One-shot ticket store shared with the HTTP API. The LOGIN packet
    /// handler consumes a ticket here when the password starts with "t".
    pub tickets: LoginTicketService,
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
            players: None,
            combat: CombatManager::new(),
            bank: BankHandler::new(),
            shop: ShopHandler::with_default_shops(ItemRepository::new()),
            content: crate::game::content::default_content_registry(),
            tickets: LoginTicketService::new(),
        }
    }

    /// Attach a player repository (enables DB-backed auth + persistence).
    pub fn with_players(mut self, repo: Arc<PlayerRepository>) -> Self {
        self.players = Some(repo);
        self
    }

    /// Share an existing ticket service (so the HTTP API and the LOGIN
    /// handler operate on the same store). The orchestrator should call this
    /// after `ApiState::new()` to point both layers at one instance.
    pub fn with_tickets(mut self, tickets: LoginTicketService) -> Self {
        self.tickets = tickets;
        self
    }

    /// Override the per-IP session cap. Pass-through to the SessionManager.
    pub fn with_max_sessions_per_ip(mut self, max: u32) -> Self {
        self.sessions = self.sessions.with_max_sessions_per_ip(max);
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

        // Phase 2a: NPC aggression scan. For each idle, alive NPC within
        // wander_radius+aggro_extra of any logged-in player, start an
        // encounter. Skips NPCs already in combat. Aggro range hard-coded at
        // 4 tiles to match the player attack range; tune per-NPC later by
        // pulling this from NpcDef.
        self.run_npc_aggro_scan().await;

        // Phase 2b: Resolve combat rounds. Encounters whose round timer
        // matured this tick produce hits; we apply them before the streaming
        // sweep so HP/death state is current when we snapshot players/NPCs.
        let round_results = self.combat.process_tick(self.tick_count);
        for r in round_results {
            self.apply_round_result(r).await;
        }

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
        // Get session
        let session = match self.sessions.get_session(session_id) {
            Some(s) => s,
            None => {
                warn!("Packet from unknown session {}", session_id);
                return HandleResult::Disconnect;
            }
        };

        let (session_state, protocol_version) = {
            let s = session.read().await;
            (s.state, s.protocol_version())
        };

        // Wire bytes must be decoded via the session's protocol-version table,
        // not the enum ordinal table. v235 has conflict bytes whose meaning
        // depends on login state, packet length, and duel state; pass the
        // context we currently have and default unknown bytes to heartbeat.
        let opcode = crate::protocol::legacy::decode_opcode_with_context(
            protocol_version,
            packet.opcode,
            session_state == SessionState::LoggedIn,
            packet.payload.len(),
            false,
        )
        .unwrap_or(OpcodeIn::HEARTBEAT);

        // The custom desktop client sends a tiny pre-login opcode 19 packet to
        // request server configuration before the real RSA login packet. v177
        // also uses opcode 19 for relogin, so distinguish by payload length as
        // Java RSCConnectionHandler does.
        if session_state != SessionState::LoggedIn
            && packet.opcode == 19
            && packet.payload.len() < 2
        {
            let s = session.read().await;
            let _ = s.send(build_server_configs_packet()).await;
            return HandleResult::Continue;
        }

        match opcode {
            OpcodeIn::Login => self.handle_login(session, packet).await,
            OpcodeIn::Logout | OpcodeIn::CONFIRM_LOGOUT => self.handle_logout(session).await,
            OpcodeIn::REGISTER_ACCOUNT => self.handle_register(session, packet).await,
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
            OpcodeIn::AttackNpc => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_attack_npc(session, packet).await
            }
            OpcodeIn::AttackPlayer => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_attack_player(session, packet).await
            }
            OpcodeIn::PLAYER_APPEARANCE_CHANGE => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_appearance_change(session, packet).await
            }
            OpcodeIn::GROUND_ITEM_TAKE => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_ground_item_take(session, packet).await
            }
            OpcodeIn::ITEM_DROP => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_item_drop(session, packet).await
            }
            OpcodeIn::ITEM_EQUIP_FROM_INVENTORY => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_item_equip(session, packet).await
            }
            OpcodeIn::ITEM_UNEQUIP_FROM_INVENTORY => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_item_unequip(session, packet).await
            }
            OpcodeIn::ITEM_USE_ITEM => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_item_use_item(session, packet).await
            }
            OpcodeIn::USE_ITEM_ON_SCENERY => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_item_use_on_scenery(session, packet).await
            }
            OpcodeIn::NPC_USE_ITEM => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_item_use_on_npc(session, packet).await
            }
            OpcodeIn::QUESTION_DIALOG_ANSWER => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_question_dialog_answer(session, packet).await
            }
            OpcodeIn::NPC_TALK_TO => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_npc_talk(session, packet).await
            }
            OpcodeIn::NPC_COMMAND => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_npc_command(session, packet).await
            }
            OpcodeIn::OBJECT_COMMAND | OpcodeIn::OBJECT_COMMAND2 => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_object_command(session, packet, opcode).await
            }
            OpcodeIn::INTERACT_WITH_BOUNDARY | OpcodeIn::INTERACT_WITH_BOUNDARY2 => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_boundary_command(session, packet, opcode).await
            }
            OpcodeIn::COMBAT_STYLE_CHANGED => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_combat_style(session, packet).await
            }
            OpcodeIn::PRIVACY_SETTINGS_CHANGED => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_privacy_settings(session, packet).await
            }
            OpcodeIn::GAME_SETTINGS_CHANGED => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_game_settings(session, packet).await
            }
            OpcodeIn::PRAYER_ACTIVATED | OpcodeIn::PRAYER_DEACTIVATED => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_prayer_toggle(session, packet, opcode).await
            }
            OpcodeIn::BANK_DEPOSIT => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_bank_deposit(session, packet).await
            }
            OpcodeIn::BANK_WITHDRAW => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_bank_withdraw(session, packet).await
            }
            OpcodeIn::BANK_CLOSE => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_bank_close(session).await
            }
            OpcodeIn::SHOP_BUY => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_shop_buy(session, packet).await
            }
            OpcodeIn::SHOP_SELL => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_shop_sell(session, packet).await
            }
            OpcodeIn::SHOP_CLOSE => {
                if session_state != SessionState::LoggedIn {
                    return HandleResult::Continue;
                }
                self.handle_shop_close(session).await
            }
            OpcodeIn::BLINK => {
                // Heartbeat-like keep-alive, just touch the session.
                let mut s = session.write().await;
                s.touch();
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

        // DB-backed auth + rehydration. Clone the Arc so we don't hold a borrow
        // across the await chain; the Arc refcount increment is cheap.
        let player_data: Option<(
            PlayerRecord,
            Option<SkillsRecord>,
            Vec<InventoryRecord>,
            Vec<BankRecord>,
            Option<SettingsRecord>,
        )> = if let Some(repo) = self.players.clone() {
            match repo.find_by_username(&login_request.username).await {
                Ok(Some(record)) => {
                    if record.banned {
                        let s = session.read().await;
                        let _ = s.send(LoginResponse::AccountDisabled.encode()).await;
                        return HandleResult::Disconnect;
                    }
                    // Two auth paths:
                    //   "t..." → one-shot launcher ticket; consume it,
                    //            skip bcrypt entirely. Bypasses the
                    //            in-canvas password prompt for web clients.
                    //   else   → bcrypt verify against stored hash.
                    // Mirrors Java GameLoginTicketService.PASSWORD_PREFIX.
                    let auth_ok = if login_request
                        .password
                        .starts_with(crate::api::ticket::TICKET_PREFIX)
                    {
                        self.tickets
                            .consume(&login_request.username, &login_request.password)
                    } else {
                        verify_password(&login_request.password, &record.password_hash)
                    };
                    if !auth_ok {
                        let s = session.read().await;
                        let _ = s.send(LoginResponse::InvalidCredentials.encode()).await;
                        return HandleResult::Disconnect;
                    }
                    let skills = repo.get_skills(record.id).await.ok().flatten();
                    let inventory = repo.get_inventory(record.id).await.unwrap_or_else(|e| {
                        warn!(
                            "Failed to load inventory for {}: {}",
                            login_request.username, e
                        );
                        Vec::new()
                    });
                    let bank = repo.get_bank(record.id).await.unwrap_or_else(|e| {
                        warn!("Failed to load bank for {}: {}", login_request.username, e);
                        Vec::new()
                    });
                    let settings = repo.get_settings(record.id).await.ok().flatten();
                    Some((record, skills, inventory, bank, settings))
                }
                Ok(None) => {
                    // Registration is a separate flow; accept-on-first-login is OFF.
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
        } else {
            None // no repo → accept-all bench/smoke mode
        };

        let session_id = {
            let s = session.read().await;
            s.id
        };

        let mut player = Player::new(session_id, login_request.username.clone());

        // Rehydrate saved state from DB when available.
        if let Some((ref record, ref skills_opt, ref inventory, ref bank, ref settings)) =
            player_data
        {
            player.db_id = Some(record.id);
            player.position = Position::new(record.x, record.y);
            player.fatigue = record.fatigue as u32;
            player.appearance = crate::game::player::Appearance {
                is_male: record.male,
                head_sprite: record.appearance_head as u8,
                body_sprite: record.appearance_body as u8,
                hair_colour: record.appearance_hair as u8,
                top_colour: record.appearance_top as u8,
                trouser_colour: record.appearance_bottom as u8,
                skin_colour: record.appearance_skin as u8,
            };
            // If the DB row already has an appearance, the player isn't in
            // first-time creation — skip the appearance prompt.
            player.appearance_changed = false;
            if let Some(ref sr) = skills_opt {
                apply_skills_from_db(&mut player.skills, sr);
                player.prayer =
                    PrayerState::new(player.skills.current_level(SkillId::Prayer) as u32);
                player.calculate_combat_level();
            }
            player.combat_style = combat_style_from_wire(record.combat_style as u8)
                .unwrap_or(CombatStyle::Controlled);
            apply_inventory_from_db(&mut player.inventory, inventory);
            apply_bank_from_db(&mut player.bank, bank);
            if let Some(settings) = settings {
                apply_settings_from_db(&mut player.settings, settings);
            }
        }
        let player_arc = Arc::new(RwLock::new(player));

        // Register player in game state
        self.game
            .register_player_arc(session_id, player_arc.clone())
            .await;

        // Register username in session manager
        self.sessions
            .register_username(session_id, login_request.username.clone());

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
            .write_short(p.position.x as u16) // player x
            .write_short(p.position.y as u16) // player y
            .write_short(16) // plane/height
            .write_short(2304) // wilderness boundary
            .write_short(1) // is_members
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

        // Send active prayer flags.
        let prayers_packet = build_prayers_active_packet(&p.prayer);
        let _ = s.send(prayers_packet).await;

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

        // Persist and remove player.
        if let Some(pid) = player_id {
            if let Some(repo) = self.players.clone() {
                if let Some(player_arc) = self.game.get_player(pid) {
                    let p = player_arc.read().await;
                    if let Err(e) = repo
                        .update_position_by_username(&p.username, p.position.x, p.position.y)
                        .await
                    {
                        warn!("Failed to persist position for {}: {}", p.username, e);
                    }
                    if let Some(db_id) = p.db_id {
                        let sr = build_skills_record(db_id, &p);
                        if let Err(e) = repo.save_skills(&sr).await {
                            warn!("Failed to persist skills for {}: {}", p.username, e);
                        }
                        let inventory = build_inventory_records(db_id, &p);
                        if let Err(e) = repo.save_inventory(db_id, &inventory).await {
                            warn!("Failed to persist inventory for {}: {}", p.username, e);
                        }
                        let bank = build_bank_records(db_id, &p);
                        if let Err(e) = repo.save_bank(db_id, &bank).await {
                            warn!("Failed to persist bank for {}: {}", p.username, e);
                        }
                        if let Err(e) = repo
                            .update_combat_style(db_id, combat_style_to_wire(p.combat_style) as i32)
                            .await
                        {
                            warn!("Failed to persist combat style for {}: {}", p.username, e);
                        }
                        let settings = build_settings_record(db_id, &p);
                        if let Err(e) = repo.save_settings(&settings).await {
                            warn!("Failed to persist settings for {}: {}", p.username, e);
                        }
                        let a = &p.appearance;
                        if let Err(e) = repo
                            .update_appearance(
                                db_id,
                                a.hair_colour,
                                a.top_colour,
                                a.trouser_colour,
                                a.skin_colour,
                                a.head_sprite,
                                a.body_sprite,
                                a.is_male,
                            )
                            .await
                        {
                            warn!("Failed to persist appearance for {}: {}", p.username, e);
                        }
                    }
                }
            }
            // Force-end any combat encounter referencing this player so the
            // CombatManager doesn't keep ticking against a stale entity_id.
            self.combat.force_end(&EntityId(pid));
            self.bank.on_logout(pid);
            self.shop.on_logout(pid);
            self.game.unregister_player(pid).await;
        }

        info!("Session {} logged out", session_id);
        HandleResult::Disconnect
    }

    /// Handle walk packet.
    async fn handle_walk(&self, session: Arc<RwLock<Session>>, packet: Packet) -> HandleResult {
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
            let mut walk_queue = Vec::with_capacity(waypoints.len() + 1);
            walk_queue.push(Position::new(start_x as i32, start_y as i32));

            // Client deltas are offsets from the packet origin, not cumulative.
            let sx = start_x as i32;
            let sy = start_y as i32;
            for (dx, dy) in waypoints {
                walk_queue.push(Position::new(sx + dx as i32, sy + dy as i32));
            }

            if let Some(world) = self.game.get_world("main") {
                let world = world.read().await;
                walk_queue = collision_checked_walk_queue(
                    &world,
                    self.movement_collision_policy(),
                    walk_queue,
                );
            }

            let mut p = player.write().await;

            // Clear any current action
            p.walking_queue.clear();
            p.walking_queue.extend(walk_queue);
        }

        HandleResult::Continue
    }

    fn movement_collision_policy(&self) -> MovementCollisionPolicy {
        if self.game.java_locs_dir.is_some() {
            MovementCollisionPolicy::JavaLocs
        } else {
            MovementCollisionPolicy::SeededRuntimeOnly
        }
    }

    /// Handle public chat.
    ///
    /// Modern clients render public chat via SEND_UPDATE_PLAYERS type-1
    /// entries inside the per-tick view bundle, not as a free-floating
    /// SEND_SERVER_MESSAGE broadcast. We queue the message on the player and
    /// `send_entity_updates` drains the queue, emitting a type-1 entry to
    /// every viewer within the 16-tile view area (including the sender, so
    /// they see their own chat bubble).
    async fn handle_chat(&self, session: Arc<RwLock<Session>>, packet: Packet) -> HandleResult {
        let mut reader = PacketReader::new(&packet);
        let message = match reader.read_string() {
            Ok(m) => m,
            Err(_) => return HandleResult::Continue,
        };

        let s = session.read().await;
        let player_arc = match &s.player {
            Some(p) => p.clone(),
            None => return HandleResult::Continue,
        };
        drop(s);

        let mut p = player_arc.write().await;
        info!("{}: {}", p.username, message);
        p.pending_chat.push(message);

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
                    ))
                    .await;
                }
            }
            "uptime" => {
                let uptime = self.start_time.elapsed();
                let hours = uptime.as_secs() / 3600;
                let minutes = (uptime.as_secs() % 3600) / 60;
                let seconds = uptime.as_secs() % 60;
                s.message(&format!("Uptime: {}h {}m {}s", hours, minutes, seconds))
                    .await;
            }
            "tick" => {
                s.message(&format!("Current tick: {}", self.tick_count))
                    .await;
            }
            "bank" => {
                if let Some(ref player) = s.player {
                    let p = player.read().await;
                    match self.bank.open_bank(p.id, &p.bank) {
                        Ok(packets) => {
                            for packet in packets {
                                let _ = s.send(packet).await;
                            }
                        }
                        Err(e) => {
                            s.message(&e.to_string()).await;
                        }
                    }
                }
            }
            "shop" => {
                let shop_id = parts
                    .get(1)
                    .and_then(|raw| raw.parse::<u32>().ok())
                    .unwrap_or(2);
                if let Some(ref player) = s.player {
                    let p = player.read().await;
                    match self.shop.open_shop(p.id, shop_id, self.tick_count) {
                        Ok(packets) => {
                            for packet in packets {
                                let _ = s.send(packet).await;
                            }
                        }
                        Err(e) => {
                            s.message(&e.to_string()).await;
                        }
                    }
                }
            }
            "help" => {
                s.message("Commands: ::online, ::pos, ::uptime, ::tick, ::bank, ::shop, ::help")
                    .await;
            }
            _ => {
                s.message(&format!("Unknown command: {}", parts[0])).await;
            }
        }

        HandleResult::Continue
    }

    /// Handle PLAYER_APPEARANCE_CHANGE (10-byte custom packet).
    /// Layout: headRestrictions(1) headType(1) bodyType(1) mustEqual2(1)
    ///         hairColour(1) topColour(1) trouserColour(1) skinColour(1)
    ///         ironmanMode(1) isOneXp(1)
    async fn handle_appearance_change(
        &self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = crate::protocol::PacketReader::new(&packet);
        let head_restrictions = match reader.read_byte() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let head_type = match reader.read_byte() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let body_type = match reader.read_byte() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let must_equal_2 = match reader.read_byte() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        if must_equal_2 != 2 {
            debug!(
                "appearance change: mustEqual2 was {} (expected 2)",
                must_equal_2
            );
            return HandleResult::Continue;
        }
        let hair_colour = match reader.read_byte() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let top_colour = match reader.read_byte() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let trouser_colour = match reader.read_byte() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let skin_colour = match reader.read_byte() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        // ironman_mode and is_one_xp (custom fields) — read and discard for now.
        let _ = reader.read_byte();
        let _ = reader.read_byte();

        let s = session.read().await;
        if let Some(ref player_arc) = s.player {
            let mut p = player_arc.write().await;
            p.appearance = crate::game::player::Appearance {
                is_male: head_restrictions == 1,
                head_sprite: head_type + 1,
                body_sprite: body_type + 1,
                hair_colour,
                top_colour,
                trouser_colour,
                skin_colour,
            };
            p.appearance_changed = true;
            debug!(
                "Appearance set for {} (male={})",
                p.username, p.appearance.is_male
            );
        }
        HandleResult::Continue
    }

    /// Handle GROUND_ITEM_TAKE — pick up an item from the world.
    /// Packet: x(short) y(short) item_id(short)
    async fn handle_ground_item_take(
        &self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = crate::protocol::PacketReader::new(&packet);
        let x = match reader.read_short() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let y = match reader.read_short() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let item_id = match reader.read_short() {
            Ok(v) => v as u32,
            Err(_) => return HandleResult::Continue,
        };

        let (player_arc, username) = {
            let s = session.read().await;
            let arc = match s.player.as_ref() {
                Some(p) => p.clone(),
                None => return HandleResult::Continue,
            };
            let u = arc.read().await.username.clone();
            (arc, u)
        };

        // Pull item from world.
        let taken_item = if let Some(world) = self.game.get_world("main") {
            let mut w = world.write().await;
            let pos = crate::game::entity::Position::new(x as i32, y as i32);
            w.pickup_item(pos, item_id)
        } else {
            None
        };

        if let Some(gi) = taken_item {
            let mut p = player_arc.write().await;
            let item = crate::game::player::Item::new(gi.item_id, gi.amount);
            if !p.inventory.add(item) {
                // Inventory full — put it back.
                if let Some(world) = self.game.get_world("main") {
                    let mut w = world.write().await;
                    let pos = crate::game::entity::Position::new(x as i32, y as i32);
                    w.drop_item(pos, gi);
                }
                let s = session.read().await;
                s.message("Your inventory is full.").await;
            } else {
                debug!("{} picked up item {} at ({},{})", username, item_id, x, y);
                let inv_packet = build_inventory_packet(&p);
                let s = session.read().await;
                let _ = s.send(inv_packet).await;
            }
        }
        HandleResult::Continue
    }

    /// Handle ITEM_DROP — drop an inventory slot onto the ground.
    /// Packet: slot_index(short)
    async fn handle_item_drop(
        &self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = crate::protocol::PacketReader::new(&packet);
        let slot = match reader.read_short() {
            Ok(v) => v as usize,
            Err(_) => return HandleResult::Continue,
        };

        let (player_arc, pos) = {
            let s = session.read().await;
            let arc = match s.player.as_ref() {
                Some(p) => p.clone(),
                None => return HandleResult::Continue,
            };
            let p = arc.read().await;
            (arc.clone(), p.position)
        };

        let dropped_item = {
            let mut p = player_arc.write().await;
            p.inventory.take_slot(slot)
        };

        if let Some(item) = dropped_item {
            let item_id = item.id;
            if let Some(world) = self.game.get_world("main") {
                let mut w = world.write().await;
                w.drop_item(
                    pos,
                    crate::game::world::GroundItem::new(item.id, item.amount),
                );
            }
            let p = player_arc.read().await;
            let inv_packet = build_inventory_packet(&p);
            let s = session.read().await;
            let _ = s.send(inv_packet).await;
            debug!("Player dropped item {} at ({},{})", item_id, pos.x, pos.y);
        }
        HandleResult::Continue
    }

    /// Handle ITEM_EQUIP_FROM_INVENTORY — equip item from a specific inventory slot.
    /// Packet: slot_index(short)
    async fn handle_item_equip(
        &self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = crate::protocol::PacketReader::new(&packet);
        let slot = match reader.read_short() {
            Ok(v) => v as usize,
            Err(_) => return HandleResult::Continue,
        };

        let player_arc = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(p) => p.clone(),
                None => return HandleResult::Continue,
            }
        };

        let inv_packet = {
            let mut p = player_arc.write().await;
            // Toggle the slot's `wielded` flag. If another inventory slot is
            // already wielded in a clashing equipment slot we'd un-wield it
            // here — but until the item def loader is wired we can't tell
            // which slot a given item id occupies, so we just allow at most
            // one wielded weapon at a time as a best-effort.
            let item_id = if let Some(Some(item)) = p.inventory.items().get(slot) {
                Some(item.id)
            } else {
                None
            };
            if let Some(_id) = item_id {
                // Un-wield any other slot first (single-weapon assumption).
                p.inventory.unwield_all();
                p.inventory.set_wielded(slot, true);
            }
            build_inventory_packet(&p)
        };
        let s = session.read().await;
        let _ = s.send(inv_packet).await;
        HandleResult::Continue
    }

    /// Handle ITEM_UNEQUIP_FROM_INVENTORY — un-equip a worn item back to inventory.
    /// Packet: slot_index(short)
    async fn handle_item_unequip(
        &self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = crate::protocol::PacketReader::new(&packet);
        let slot = match reader.read_short() {
            Ok(v) => v as usize,
            Err(_) => return HandleResult::Continue,
        };

        let player_arc = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(p) => p.clone(),
                None => return HandleResult::Continue,
            }
        };

        let inv_packet = {
            let mut p = player_arc.write().await;
            p.inventory.set_wielded(slot, false);
            build_inventory_packet(&p)
        };
        let s = session.read().await;
        let _ = s.send(inv_packet).await;
        HandleResult::Continue
    }

    /// Handle BANK_DEPOSIT — move item from inventory into an open bank.
    async fn handle_bank_deposit(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let request = match BankItemAmountRequest::parse(&packet) {
            Ok(request) => request,
            Err(_) => return HandleResult::Continue,
        };

        let player_arc = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(p) => p.clone(),
                None => return HandleResult::Continue,
            }
        };

        let (inv_packet, bank_packet, close_packets, message) = {
            let mut p = player_arc.write().await;
            if let Err(e) = self
                .bank
                .handle_deposit(p.id, request.item_id, request.amount)
            {
                match e {
                    BankHandlerError::BankClosed => (None, None, self.bank.close_bank(p.id), None),
                    _ => (None, None, Vec::new(), bank_handler_error_message(&e)),
                }
            } else if request.amount == 0 {
                (None, None, Vec::new(), None)
            } else {
                let amount = request.amount.min(p.inventory.count(request.item_id.0));
                if amount == 0 {
                    (None, None, Vec::new(), None)
                } else {
                    match p.bank.deposit(request.item_id, amount) {
                        Ok(()) => {
                            let removed = p.inventory.remove_amount(request.item_id.0, amount);
                            if removed < amount {
                                let _ = p.bank.withdraw(request.item_id, amount - removed);
                            }
                            let slot = p
                                .bank
                                .bank
                                .items()
                                .iter()
                                .position(|item| item.item_id == request.item_id.0)
                                .unwrap_or(0)
                                .min(u8::MAX as usize) as u8;
                            (
                                Some(build_inventory_packet(&p)),
                                Some(self.bank.build_update(
                                    slot,
                                    request.item_id,
                                    p.bank.count(request.item_id),
                                )),
                                Vec::new(),
                                None,
                            )
                        }
                        Err(e) => (
                            None,
                            None,
                            Vec::new(),
                            bank_error_message(&e).map(str::to_string),
                        ),
                    }
                }
            }
        };

        let s = session.read().await;
        if let Some(message) = message {
            s.message(&message).await;
        }
        if let Some(packet) = inv_packet {
            let _ = s.send(packet).await;
        }
        if let Some(packet) = bank_packet {
            let _ = s.send(packet).await;
        }
        for packet in close_packets {
            let _ = s.send(packet).await;
        }
        HandleResult::Continue
    }

    /// Handle BANK_WITHDRAW — move item from an open bank into inventory.
    async fn handle_bank_withdraw(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let request = match BankItemAmountRequest::parse(&packet) {
            Ok(request) => request,
            Err(_) => return HandleResult::Continue,
        };

        let player_arc = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(p) => p.clone(),
                None => return HandleResult::Continue,
            }
        };

        let (inv_packet, bank_packet, close_packets, message) = {
            let mut p = player_arc.write().await;
            if let Err(e) = self
                .bank
                .handle_withdraw(p.id, request.item_id, request.amount)
            {
                match e {
                    BankHandlerError::BankClosed => (None, None, self.bank.close_bank(p.id), None),
                    _ => (None, None, Vec::new(), bank_handler_error_message(&e)),
                }
            } else if request.amount == 0 {
                (None, None, Vec::new(), None)
            } else {
                let amount = request.amount.min(p.bank.count(request.item_id));
                if amount == 0 {
                    (None, None, Vec::new(), None)
                } else {
                    let old_slot = p
                        .bank
                        .bank
                        .items()
                        .iter()
                        .position(|item| item.item_id == request.item_id.0)
                        .unwrap_or(0)
                        .min(u8::MAX as usize) as u8;
                    match p.bank.withdraw(request.item_id, amount) {
                        Ok(withdrawn) => {
                            if p.inventory
                                .add(crate::game::player::Item::new(request.item_id.0, withdrawn))
                            {
                                (
                                    Some(build_inventory_packet(&p)),
                                    Some(self.bank.build_update(
                                        old_slot,
                                        request.item_id,
                                        p.bank.count(request.item_id),
                                    )),
                                    Vec::new(),
                                    None,
                                )
                            } else {
                                let _ = p.bank.deposit(request.item_id, withdrawn);
                                (
                                    None,
                                    None,
                                    Vec::new(),
                                    Some("You don't have room to hold everything!".to_string()),
                                )
                            }
                        }
                        Err(e) => (
                            None,
                            None,
                            Vec::new(),
                            bank_error_message(&e).map(str::to_string),
                        ),
                    }
                }
            }
        };

        let s = session.read().await;
        if let Some(message) = message {
            s.message(&message).await;
        }
        if let Some(packet) = inv_packet {
            let _ = s.send(packet).await;
        }
        if let Some(packet) = bank_packet {
            let _ = s.send(packet).await;
        }
        for packet in close_packets {
            let _ = s.send(packet).await;
        }
        HandleResult::Continue
    }

    /// Handle BANK_CLOSE — close the temporary bank interface session.
    async fn handle_bank_close(&mut self, session: Arc<RwLock<Session>>) -> HandleResult {
        let player_id = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(p) => p.read().await.id,
                None => return HandleResult::Continue,
            }
        };
        let packets = self.bank.close_bank(player_id);
        let s = session.read().await;
        for packet in packets {
            let _ = s.send(packet).await;
        }
        HandleResult::Continue
    }

    /// Handle SHOP_BUY — move coins/items through the currently-open shop.
    async fn handle_shop_buy(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let request = match ShopItemAmountRequest::parse(&packet) {
            Ok(request) => request,
            Err(_) => return HandleResult::Continue,
        };

        let player_arc = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(p) => p.clone(),
                None => return HandleResult::Continue,
            }
        };

        let (inventory_packet, shop_packets, close_packets, message) = {
            let mut p = player_arc.write().await;
            match self
                .shop
                .handle_buy_request_with_inventory(p.id, request, &mut p.inventory)
            {
                Ok(result) => (
                    result.inventory_changed.then(|| build_inventory_packet(&p)),
                    result.packets,
                    Vec::new(),
                    result.message,
                ),
                Err(ShopHandlerError::NoOpenShop) => {
                    (None, Vec::new(), self.shop.close_shop(p.id), None)
                }
                Err(e) => (None, Vec::new(), Vec::new(), shop_handler_error_message(&e)),
            }
        };

        let s = session.read().await;
        if let Some(message) = message {
            s.message(&message).await;
        }
        if let Some(packet) = inventory_packet {
            let _ = s.send(packet).await;
        }
        for packet in shop_packets {
            let _ = s.send(packet).await;
        }
        for packet in close_packets {
            let _ = s.send(packet).await;
        }
        HandleResult::Continue
    }

    /// Handle SHOP_SELL — sell player inventory into the currently-open shop.
    async fn handle_shop_sell(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let request = match ShopItemAmountRequest::parse(&packet) {
            Ok(request) => request,
            Err(_) => return HandleResult::Continue,
        };

        let player_arc = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(p) => p.clone(),
                None => return HandleResult::Continue,
            }
        };

        let (inventory_packet, shop_packets, close_packets, message) = {
            let mut p = player_arc.write().await;
            match self
                .shop
                .handle_sell_request_with_inventory(p.id, request, &mut p.inventory)
            {
                Ok(result) => (
                    result.inventory_changed.then(|| build_inventory_packet(&p)),
                    result.packets,
                    Vec::new(),
                    result.message,
                ),
                Err(ShopHandlerError::NoOpenShop) => {
                    (None, Vec::new(), self.shop.close_shop(p.id), None)
                }
                Err(e) => (None, Vec::new(), Vec::new(), shop_handler_error_message(&e)),
            }
        };

        let s = session.read().await;
        if let Some(message) = message {
            s.message(&message).await;
        }
        if let Some(packet) = inventory_packet {
            let _ = s.send(packet).await;
        }
        for packet in shop_packets {
            let _ = s.send(packet).await;
        }
        for packet in close_packets {
            let _ = s.send(packet).await;
        }
        HandleResult::Continue
    }

    /// Handle SHOP_CLOSE — close the temporary shop interface session.
    async fn handle_shop_close(&mut self, session: Arc<RwLock<Session>>) -> HandleResult {
        let player_id = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(p) => p.read().await.id,
                None => return HandleResult::Continue,
            }
        };
        let packets = self.shop.close_shop(player_id);
        let s = session.read().await;
        for packet in packets {
            let _ = s.send(packet).await;
        }
        HandleResult::Continue
    }

    async fn player_and_npc_definition(
        &self,
        session: &Arc<RwLock<Session>>,
        npc_index: u16,
    ) -> Option<(u64, u32)> {
        let player_arc = {
            let s = session.read().await;
            s.player.as_ref()?.clone()
        };
        let player_id = player_arc.read().await.id;
        let world = self.game.get_world("main")?;
        let npc_definition_id = {
            let w = world.read().await;
            w.npcs
                .values()
                .find(|n| n.npc_index == npc_index && !n.removed)
                .map(|n| n.definition_id)?
        };
        Some((player_id, npc_definition_id))
    }

    async fn item_on_item_event(
        &self,
        session: &Arc<RwLock<Session>>,
        request: ItemOnItemRequest,
    ) -> Option<ContentEvent> {
        let player_arc = {
            let s = session.read().await;
            s.player.as_ref()?.clone()
        };
        let player = player_arc.read().await;
        let item_id = player
            .inventory
            .items()
            .get(request.item_slot)
            .and_then(|item| item.as_ref())
            .map(|item| item.id)?;
        let target_item_id = player
            .inventory
            .items()
            .get(request.target_slot)
            .and_then(|item| item.as_ref())
            .map(|item| item.id)?;

        Some(ContentEvent::UseItemOnItem {
            player_id: player.id,
            item_id,
            item_slot: request.item_slot,
            target_item_id,
            target_slot: request.target_slot,
        })
    }

    async fn item_on_object_event(
        &self,
        session: &Arc<RwLock<Session>>,
        request: ItemOnObjectRequest,
    ) -> Option<ContentEvent> {
        let player_arc = {
            let s = session.read().await;
            s.player.as_ref()?.clone()
        };
        let (player_id, item_id) = {
            let player = player_arc.read().await;
            let item_id = player
                .inventory
                .items()
                .get(request.item_slot)
                .and_then(|item| item.as_ref())
                .map(|item| item.id)?;
            (player.id, item_id)
        };

        let world = self.game.get_world("main")?;
        let object_id = {
            let w = world.read().await;
            w.game_objects
                .get(&request.position)
                .filter(|obj| obj.obj_type != 1)
                .map(|obj| obj.id)?
        };

        Some(ContentEvent::UseItemOnObject {
            player_id,
            item_id,
            item_slot: request.item_slot,
            object_id,
            position: request.position,
        })
    }

    async fn item_on_npc_event(
        &self,
        session: &Arc<RwLock<Session>>,
        request: ItemOnNpcRequest,
    ) -> Option<ContentEvent> {
        let player_arc = {
            let s = session.read().await;
            s.player.as_ref()?.clone()
        };
        let (player_id, item_id) = {
            let player = player_arc.read().await;
            let item_id = player
                .inventory
                .items()
                .get(request.item_slot)
                .and_then(|item| item.as_ref())
                .map(|item| item.id)?;
            (player.id, item_id)
        };

        let world = self.game.get_world("main")?;
        let npc_id = {
            let w = world.read().await;
            w.npcs
                .values()
                .find(|npc| npc.npc_index == request.npc_index && !npc.removed)
                .map(|npc| npc.definition_id)?
        };

        Some(ContentEvent::UseItemOnNpc {
            player_id,
            item_id,
            item_slot: request.item_slot,
            npc_id,
            npc_index: request.npc_index,
        })
    }

    async fn apply_content_plan(
        &mut self,
        session: Arc<RwLock<Session>>,
        plan: ContentRuntimePlan,
    ) -> bool {
        if plan.is_empty() {
            return false;
        }

        let player_arc = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(player) => player.clone(),
                None => return true,
            }
        };

        let (messages, packets, error_message) = {
            let mut player = player_arc.write().await;
            let mut sink =
                LiveContentRuntimeSink::new(&mut player, &mut self.shop, self.tick_count);
            let error_message = plan.apply_to(&mut sink).err().map(|e| e.to_string());
            (sink.messages, sink.packets, error_message)
        };

        let s = session.read().await;
        for message in messages {
            s.message(&message).await;
        }
        for packet in packets {
            let _ = s.send(packet).await;
        }
        if let Some(message) = error_message {
            warn!("{}", message);
            s.message("Nothing interesting happens.").await;
        }
        true
    }

    /// Handle ITEM_USE_ITEM — use one inventory item on another.
    /// Packet: item_slot(short) target_slot(short)
    async fn handle_item_use_item(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let request = match ItemOnItemRequest::parse(&packet) {
            Ok(request) => request,
            Err(_) => return HandleResult::Continue,
        };
        let Some(event) = self.item_on_item_event(&session, request).await else {
            return HandleResult::Continue;
        };
        let plan = ContentRuntimePlan::from_event(&self.content, &event);
        let _ = self.apply_content_plan(session, plan).await;

        HandleResult::Continue
    }

    /// Handle USE_ITEM_ON_SCENERY — use an inventory item on a scenery object.
    /// Packet: x(short) y(short) item_slot(short)
    async fn handle_item_use_on_scenery(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let request = match ItemOnObjectRequest::parse_scenery(&packet) {
            Ok(request) => request,
            Err(_) => return HandleResult::Continue,
        };
        let Some(event) = self.item_on_object_event(&session, request).await else {
            return HandleResult::Continue;
        };
        let plan = ContentRuntimePlan::from_event(&self.content, &event);
        let _ = self.apply_content_plan(session, plan).await;

        HandleResult::Continue
    }

    /// Handle NPC_USE_ITEM — use an inventory item on an NPC.
    /// Packet: server_npc_index(short) item_slot(short)
    async fn handle_item_use_on_npc(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let request = match ItemOnNpcRequest::parse(&packet) {
            Ok(request) => request,
            Err(_) => return HandleResult::Continue,
        };
        let Some(event) = self.item_on_npc_event(&session, request).await else {
            return HandleResult::Continue;
        };
        let plan = ContentRuntimePlan::from_event(&self.content, &event);
        let _ = self.apply_content_plan(session, plan).await;

        HandleResult::Continue
    }

    /// Handle QUESTION_DIALOG_ANSWER — player selected a dialogue/menu option.
    /// Packet: option(byte as signed Java readByte)
    async fn handle_question_dialog_answer(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let request = match DialogueAnswerRequest::parse(&packet) {
            Ok(request) => request,
            Err(_) => return HandleResult::Continue,
        };
        let player_id = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(player) => player.read().await.id,
                None => return HandleResult::Continue,
            }
        };
        let event = ContentEvent::DialogueAnswer {
            player_id,
            option: request.option,
        };
        let plan = ContentRuntimePlan::from_event(&self.content, &event);
        let _ = self.apply_content_plan(session, plan).await;

        HandleResult::Continue
    }

    /// Handle NPC_TALK_TO — initiate dialogue with an NPC.
    /// Packet: server_npc_index(short)
    async fn handle_npc_talk(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = crate::protocol::PacketReader::new(&packet);
        let npc_index = match reader.read_short() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };

        let Some((player_id, npc_definition_id)) =
            self.player_and_npc_definition(&session, npc_index).await
        else {
            return HandleResult::Continue;
        };

        let event = ContentEvent::TalkNpc {
            player_id,
            npc_id: npc_definition_id,
            npc_index,
        };
        let plan = ContentRuntimePlan::from_event(&self.content, &event);
        if self.apply_content_plan(session.clone(), plan).await {
            return HandleResult::Continue;
        }

        // Dialogues are not implemented yet — acknowledge with a system message.
        let s = session.read().await;
        s.message(&format!("NPC {} says: Hello adventurer!", npc_index))
            .await;
        HandleResult::Continue
    }

    /// Handle NPC_COMMAND — primary command on an NPC. Java bankers expose
    /// command1 "Bank", which opens the bank interface.
    /// Packet: server_npc_index(short)
    async fn handle_npc_command(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        const BANKER_NPC_IDS: &[u32] = &[95, 224, 268, 540, 617];

        let mut reader = crate::protocol::PacketReader::new(&packet);
        let npc_index = match reader.read_short() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };

        let Some((player_id, npc_definition_id)) =
            self.player_and_npc_definition(&session, npc_index).await
        else {
            return HandleResult::Continue;
        };

        let event = ContentEvent::NpcCommand {
            player_id,
            npc_id: npc_definition_id,
            command: 0,
        };
        let plan = ContentRuntimePlan::from_event(&self.content, &event);
        if self.apply_content_plan(session.clone(), plan).await {
            return HandleResult::Continue;
        }

        if !BANKER_NPC_IDS.contains(&npc_definition_id) {
            debug!(
                "NPC command ignored for non-banker npc_index={} definition_id={}",
                npc_index, npc_definition_id
            );
            return HandleResult::Continue;
        }

        let s = session.read().await;
        let Some(ref player) = s.player else {
            return HandleResult::Continue;
        };

        let p = player.read().await;
        match self.bank.open_bank(p.id, &p.bank) {
            Ok(packets) => {
                for packet in packets {
                    let _ = s.send(packet).await;
                }
            }
            Err(e) => {
                s.message(&e.to_string()).await;
            }
        }

        HandleResult::Continue
    }

    /// Handle OBJECT_COMMAND / OBJECT_COMMAND2 — interact with a world object.
    /// Packet: x(short) y(short)
    async fn handle_object_command(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
        opcode: OpcodeIn,
    ) -> HandleResult {
        const BANK_OBJECT_IDS: &[u32] = &[64, 942];

        let mut reader = crate::protocol::PacketReader::new(&packet);
        let x = match reader.read_short() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let y = match reader.read_short() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let position = Position::new(x as i32, y as i32);
        let world = match self.game.get_world("main") {
            Some(w) => w,
            None => return HandleResult::Continue,
        };
        let object_id = {
            let w = world.read().await;
            w.game_objects.get(&position).map(|obj| obj.id)
        };

        let Some(object_id) = object_id else {
            debug!("Object command ignored at empty tile ({},{})", x, y);
            return HandleResult::Continue;
        };

        let player_id = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(player) => player.read().await.id,
                None => return HandleResult::Continue,
            }
        };
        let event = ContentEvent::UseObject {
            player_id,
            object_id,
            position,
            command: object_command_index(opcode),
        };
        let plan = ContentRuntimePlan::from_event(&self.content, &event);
        if self.apply_content_plan(session.clone(), plan).await {
            return HandleResult::Continue;
        }

        if !BANK_OBJECT_IDS.contains(&object_id) {
            debug!(
                "Object command ignored for non-bank object id={} at ({},{})",
                object_id, x, y
            );
            return HandleResult::Continue;
        }

        let s = session.read().await;
        let Some(ref player) = s.player else {
            return HandleResult::Continue;
        };

        let p = player.read().await;
        match self.bank.open_bank(p.id, &p.bank) {
            Ok(packets) => {
                for packet in packets {
                    let _ = s.send(packet).await;
                }
            }
            Err(e) => {
                s.message(&e.to_string()).await;
            }
        }

        HandleResult::Continue
    }

    /// Handle INTERACT_WITH_BOUNDARY / INTERACT_WITH_BOUNDARY2 — interact with
    /// a wall/boundary object and route compiled content triggers.
    /// Packet: x(short) y(short) direction(byte)
    async fn handle_boundary_command(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
        opcode: OpcodeIn,
    ) -> HandleResult {
        let mut reader = crate::protocol::PacketReader::new(&packet);
        let x = match reader.read_short() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let y = match reader.read_short() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let direction = match reader.read_byte() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let position = Position::new(x as i32, y as i32);
        let world = match self.game.get_world("main") {
            Some(w) => w,
            None => return HandleResult::Continue,
        };
        let boundary_id = {
            let w = world.read().await;
            w.game_objects
                .get(&position)
                .filter(|obj| obj.obj_type == 1 && obj.direction == direction)
                .map(|obj| obj.id)
        };

        let Some(boundary_id) = boundary_id else {
            debug!(
                "Boundary command ignored at ({},{}) direction={}",
                x, y, direction
            );
            return HandleResult::Continue;
        };

        let player_id = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(player) => player.read().await.id,
                None => return HandleResult::Continue,
            }
        };
        let event = ContentEvent::UseBoundary {
            player_id,
            boundary_id,
            position,
            command: boundary_command_index(opcode),
        };
        let plan = ContentRuntimePlan::from_event(&self.content, &event);
        let _ = self.apply_content_plan(session, plan).await;

        HandleResult::Continue
    }

    /// Handle COMBAT_STYLE_CHANGED — save the player's selected combat style.
    /// Packet: style(byte)  0=controlled 1=aggressive 2=accurate 3=defensive
    async fn handle_combat_style(
        &self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = crate::protocol::PacketReader::new(&packet);
        let style_byte = match reader.read_byte() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };
        let Some(style) = combat_style_from_wire(style_byte) else {
            debug!("Invalid combat style {}", style_byte);
            return HandleResult::Continue;
        };

        let s = session.read().await;
        if let Some(ref player_arc) = s.player {
            {
                let mut p = player_arc.write().await;
                p.combat_style = style;
            }
            let packet = build_combat_style_packet(style_byte);
            let _ = s.send(packet).await;
        }
        HandleResult::Continue
    }

    /// Handle GAME_SETTINGS_CHANGED.
    /// Java v177 sends two bytes: setting index, value.
    async fn handle_game_settings(
        &self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let request = match GameSettingsRequest::parse(&packet) {
            Ok(request) => request,
            Err(()) => return HandleResult::Continue,
        };

        let player_arc = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(p) => p.clone(),
                None => return HandleResult::Continue,
            }
        };

        let mut p = player_arc.write().await;
        let enabled = request.value != 0;
        match request.index {
            0 => p.settings.camera_auto = enabled,
            2 => p.settings.one_mouse_button = enabled,
            3 => p.settings.sound_off = enabled,
            _ => return HandleResult::Continue,
        }
        let packet = build_settings_packet(&p);
        drop(p);
        let s = session.read().await;
        let _ = s.send(packet).await;
        HandleResult::Continue
    }

    /// Handle PRIVACY_SETTINGS_CHANGED.
    /// Custom Java clients send four bytes:
    /// block_chat, block_private, block_trade, block_duel.
    async fn handle_privacy_settings(
        &self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let request = match PrivacySettingsRequest::parse(&packet) {
            Ok(request) => request,
            Err(()) => return HandleResult::Continue,
        };

        let player_arc = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(p) => p.clone(),
                None => return HandleResult::Continue,
            }
        };

        let mut p = player_arc.write().await;
        p.settings.block_chat = request.block_chat;
        p.settings.block_private = request.block_private;
        p.settings.block_trade = request.block_trade;
        p.settings.block_duel = request.block_duel;

        HandleResult::Continue
    }

    /// Handle PRAYER_ACTIVATED / PRAYER_DEACTIVATED.
    /// Java custom clients send one byte: prayer_id.
    async fn handle_prayer_toggle(
        &self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
        opcode: OpcodeIn,
    ) -> HandleResult {
        let request = match PrayerToggleRequest::parse(&packet) {
            Ok(request) => request,
            Err(()) => return HandleResult::Continue,
        };

        let player_arc = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(p) => p.clone(),
                None => return HandleResult::Continue,
            }
        };

        let (packet, message) = {
            let mut p = player_arc.write().await;
            let player_level = p.skills.level(SkillId::Prayer) as u32;
            let current_prayer = p.skills.current_level(SkillId::Prayer) as u32;
            p.prayer.set_level(current_prayer);

            let mut message = None;
            let changed = match opcode {
                OpcodeIn::PRAYER_ACTIVATED => match p.prayer.activate(request.prayer, player_level)
                {
                    Ok(()) => true,
                    Err(e) => {
                        message = Some(e.to_string());
                        false
                    }
                },
                OpcodeIn::PRAYER_DEACTIVATED => p.prayer.deactivate(request.prayer),
                _ => false,
            };

            if changed {
                (Some(build_prayers_active_packet(&p.prayer)), None)
            } else {
                (None, message)
            }
        };

        let s = session.read().await;
        if let Some(message) = message {
            s.message(&message).await;
        }
        if let Some(packet) = packet {
            let _ = s.send(packet).await;
        }

        HandleResult::Continue
    }

    /// Handle NPC_ATTACK — start a melee encounter against an NPC.
    /// Packet payload: server_npc_index (short, big-endian, 12 valid bits).
    ///
    /// Resolves the npc_index → EntityId → live `Npc`, snapshots both sides
    /// into `Combatant` structs, then hands off to `CombatManager`. Once the
    /// encounter is registered, per-tick processing in `process_combat_round`
    /// drives hits, XP, and death.
    async fn handle_attack_npc(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = crate::protocol::PacketReader::new(&packet);
        let npc_index = match reader.read_short() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };

        let player_arc = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(p) => p.clone(),
                None => return HandleResult::Continue,
            }
        };

        // Snapshot the attacker.
        let (attacker_id, attacker_pos, attacker_combatant) = {
            let p = player_arc.read().await;
            let combatant = combatant_from_player(&p);
            (p.id, p.position, combatant)
        };

        // Resolve target NPC by wire index → entity id.
        let world = match self.game.get_world("main") {
            Some(w) => w,
            None => return HandleResult::Continue,
        };
        let (target_eid, defender_combatant, target_pos) = {
            let w = world.read().await;
            let target = w
                .npcs
                .iter()
                .find(|(_, n)| n.npc_index == npc_index && !n.removed);
            match target {
                Some((eid, npc)) => (*eid, combatant_from_npc(*eid, npc), npc.position),
                None => return HandleResult::Continue,
            }
        };

        // Range check (4 tiles is roughly RSC interaction range).
        if !attacker_pos.in_range(&target_pos, 4) {
            let s = session.read().await;
            s.message("That target is too far away.").await;
            return HandleResult::Continue;
        }

        // Don't double-engage if either side is already in combat.
        if self.combat.is_in_combat(&EntityId(attacker_id)) || self.combat.is_in_combat(&target_eid)
        {
            return HandleResult::Continue;
        }

        let enc_id = self.combat.start_combat(
            attacker_combatant,
            defender_combatant,
            CombatType::Melee,
            self.tick_count,
        );
        if enc_id != 0 {
            debug!(
                "Combat started: player {} vs NPC {:?}",
                attacker_id, target_eid
            );
        }
        HandleResult::Continue
    }

    /// Handle PLAYER_ATTACK — PvP. Same shape as `handle_attack_npc` but
    /// resolves the target via the player slot index. PvP is gated on the
    /// wilderness level (Java has the same check in `CombatHandler`).
    async fn handle_attack_player(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = crate::protocol::PacketReader::new(&packet);
        let player_index = match reader.read_short() {
            Ok(v) => v,
            Err(_) => return HandleResult::Continue,
        };

        let attacker_arc = {
            let s = session.read().await;
            match s.player.as_ref() {
                Some(p) => p.clone(),
                None => return HandleResult::Continue,
            }
        };
        let (attacker_id, attacker_pos, attacker_combatant) = {
            let p = attacker_arc.read().await;
            (p.id, p.position, combatant_from_player(&p))
        };

        // Resolve target player by slot index across all logged-in sessions.
        let mut target_arc: Option<Arc<RwLock<Player>>> = None;
        for s in self.sessions.all_sessions() {
            let read = s.read().await;
            if read.state != SessionState::LoggedIn {
                continue;
            }
            if let Some(ref p_arc) = read.player {
                let p = p_arc.read().await;
                if p.player_index == player_index {
                    target_arc = Some(p_arc.clone());
                    break;
                }
            }
        }
        let target_arc = match target_arc {
            Some(t) => t,
            None => return HandleResult::Continue,
        };

        let (target_id, target_pos, defender_combatant) = {
            let p = target_arc.read().await;
            (p.id, p.position, combatant_from_player(&p))
        };

        if attacker_id == target_id {
            return HandleResult::Continue; // can't attack self
        }
        if !attacker_pos.in_range(&target_pos, 4) {
            let s = session.read().await;
            s.message("That target is too far away.").await;
            return HandleResult::Continue;
        }

        // PvP only valid in wilderness, with combat-level gate.
        let wild = attacker_pos.wilderness_level();
        if wild == 0 {
            let s = session.read().await;
            s.message("You can only attack players in the wilderness.")
                .await;
            return HandleResult::Continue;
        }

        let _ = self.combat.start_combat(
            attacker_combatant,
            defender_combatant,
            CombatType::Melee,
            self.tick_count,
        );
        HandleResult::Continue
    }

    /// One pass per tick to start NPC→player encounters. Walks every alive,
    /// not-already-fighting NPC and starts combat against the first logged-in
    /// player within `AGGRO_RANGE` tiles. Self-contained — no aggro_priority
    /// bookkeeping yet (NpcDef will gate this once defs are loaded).
    async fn run_npc_aggro_scan(&mut self) {
        const AGGRO_RANGE: i32 = 4;

        // Snapshot logged-in players (id, position, in_combat).
        struct PSnap {
            id: u64,
            pos: Position,
            in_combat: bool,
        }
        let mut players: Vec<PSnap> = Vec::new();
        for s in self.sessions.all_sessions() {
            let read = s.read().await;
            if read.state != SessionState::LoggedIn {
                continue;
            }
            if let Some(ref p_arc) = read.player {
                let p = p_arc.read().await;
                let in_combat = self.combat.is_in_combat(&EntityId(p.id));
                players.push(PSnap {
                    id: p.id,
                    pos: p.position,
                    in_combat,
                });
            }
        }
        if players.is_empty() {
            return;
        }

        // Snapshot eligible NPCs: alive, not removed, not already in combat.
        struct NSnap {
            eid: EntityId,
            combatant: Combatant,
            pos: Position,
        }
        let mut candidates: Vec<NSnap> = Vec::new();
        if let Some(world) = self.game.get_world("main") {
            let w = world.read().await;
            for (eid, npc) in &w.npcs {
                if npc.removed || npc.in_combat {
                    continue;
                }
                if self.combat.is_in_combat(eid) {
                    continue;
                }
                candidates.push(NSnap {
                    eid: *eid,
                    combatant: combatant_from_npc(*eid, npc),
                    pos: npc.position,
                });
            }
        }

        // Match each NPC to a nearby non-combat player.
        for npc in candidates {
            let target = players.iter().find(|p| {
                !p.in_combat
                    && !self.combat.is_in_combat(&EntityId(p.id))
                    && npc.pos.in_range(&p.pos, AGGRO_RANGE)
            });
            let target = match target {
                Some(t) => t,
                None => continue,
            };

            // Pull a fresh combatant for the player.
            let p_arc = match self.game.get_player(target.id) {
                Some(a) => a,
                None => continue,
            };
            let player_combatant = {
                let p = p_arc.read().await;
                combatant_from_player(&p)
            };

            let enc = self.combat.start_combat(
                npc.combatant,
                player_combatant,
                CombatType::Melee,
                self.tick_count,
            );
            if enc != 0 {
                debug!(
                    "NPC {:?} aggroed player {} (enc={})",
                    npc.eid, target.id, enc
                );
            }
        }
    }

    /// Apply one round result: damage to live HP, XP to attacker, hit-splat
    /// packet to all viewers, death handling.
    async fn apply_round_result(&mut self, r: RoundResult) {
        let attacker_eid = r.attacker_id;
        let defender_eid = r.defender_id;
        debug!(
            "Round: {:?} -> {:?} dmg={} hp={}/{} died={}",
            attacker_eid,
            defender_eid,
            r.damage_dealt,
            r.defender_hp_remaining,
            r.defender_hp_max,
            r.defender_died,
        );

        // Push XP onto the live attacker (if it's a player). After awarding,
        // re-send the stats packet so the client's skill panel updates —
        // mirrors Java `ActionSender.sendStats(player)` after damage XP.
        if let Some(p_arc) = self.game.get_player(attacker_eid.0) {
            let stats_packet = {
                let mut p = p_arc.write().await;
                for (skill, xp) in &r.xp_awards {
                    p.add_experience(*skill, *xp);
                }
                build_stats_packet(&p)
            };
            if let Some(session) = self.sessions.get_session(attacker_eid.0) {
                let s = session.read().await;
                let _ = s.send(stats_packet).await;
            }
        }

        // Apply damage to the defender. Players are looked up by session id;
        // NPCs by entity id in the world map.
        let mut defender_died = r.defender_died;
        if let Some(p_arc) = self.game.get_player(defender_eid.0) {
            let stats_packet = {
                let mut p = p_arc.write().await;
                let cur = p.skills.current_level(SkillId::Hits);
                let new = cur.saturating_sub(r.damage_dealt as u8);
                p.skills.set_current_level(SkillId::Hits, new);
                defender_died = new == 0;
                let max = p.skills.level(SkillId::Hits);
                p.pending_hits.push((r.damage_dealt as u8, new, max));
                build_stats_packet(&p)
            };
            // Push the updated stats to the defender's session so their HP
            // bar reflects the new value. Without this the client UI never
            // changes during combat.
            if let Some(session) = self.sessions.get_session(defender_eid.0) {
                let s = session.read().await;
                let _ = s.send(stats_packet).await;
            }
        } else if let Some(world) = self.game.get_world("main") {
            let mut w = world.write().await;
            let world_tick = w.tick_count();
            if let Some(npc) = w.npcs.get_mut(&defender_eid) {
                npc.take_damage(r.damage_dealt);
                defender_died = npc.is_dead();
                npc.pending_hit = Some((
                    r.damage_dealt as u8,
                    npc.current_hits as u8,
                    npc.max_hits as u8,
                ));
                if defender_died {
                    npc.removed = true;
                    npc.death_tick = Some(world_tick);
                    npc.in_combat = false;
                }
            }
        }

        // Send a SEND_UPDATE_PLAYERS type-3 (or NPC equivalent) hit-splat to
        // every session that has either combatant in view. Layout for type-3:
        //   short index | byte 3 | byte damage | byte cur_hp | byte max_hp
        // We piggy-back the existing entity-update channel rather than a
        // standalone packet since clients only render hit splats from the
        // bundled update stream.
        for session in self.sessions.all_sessions() {
            let s = session.read().await;
            if s.state != SessionState::LoggedIn {
                continue;
            }
            let player_arc = match &s.player {
                Some(p) => p.clone(),
                None => continue,
            };
            drop(s);
            let p = player_arc.read().await;
            // We don't have view-range info handy here; let the next tick's
            // entity-update sweep deliver position deltas. For damage numbers
            // queue them on the defender player's pending_hits if we add that;
            // for NPCs the client renders damage from the NpcDamage opcode on
            // its own. For now the bookkeeping above is enough for tests.
            let _ = p;
        }

        if defender_died {
            debug!(
                "Combat: {:?} died (damage from {:?})",
                defender_eid, attacker_eid
            );
            // Player death: respawn at Lumbridge with full HP. Push the new
            // stats so the client redraws the (now-full) HP bar after respawn.
            if let Some(p_arc) = self.game.get_player(defender_eid.0) {
                let stats_packet = {
                    let mut p = p_arc.write().await;
                    p.position = Position::new(122, 647);
                    let max_hp = p.skills.level(SkillId::Hits);
                    p.skills.set_current_level(SkillId::Hits, max_hp);
                    build_stats_packet(&p)
                };
                if let Some(session) = self.sessions.get_session(defender_eid.0) {
                    let s = session.read().await;
                    let _ = s.send(stats_packet).await;
                    s.message("Oh dear, you are dead.").await;
                }
            }
        }
    }

    /// Send entity updates to all logged-in sessions.
    ///
    /// Per-tick sequence (mirrors GameStateUpdater.updatePlayers in Java):
    ///   1. Snapshot all player positions/indices.
    ///   2. For each logged-in session:
    ///      a. Build SEND_PLAYER_COORDS (opcode 191 on the custom/iOS generator):
    ///         x(11) y(13) sprite(4) knownCount(8)
    ///         per-known-player: needsUpdate(1) [+remove bits if leaving view]
    ///         per-new-player:   serverIndex(11) relX(6) relY(6) sprite(4)
    ///      b. Build SEND_UPDATE_PLAYERS (opcode 234) for any newly-visible
    ///         players carrying a type-5 appearance entry.
    ///      c. Update the player's local_players list.
    async fn send_entity_updates(&self) {
        // Step 1: collect a lightweight snapshot of every logged-in player.
        // We read all arcs once so we can compute relative offsets without
        // re-acquiring locks inside the per-session loop.
        #[derive(Clone)]
        struct PlayerSnap {
            session_id: u64,
            player_index: u16,
            position: Position,
            direction: Direction,
            username: String,
            combat_level: u32,
            pending_chat: Vec<String>,
            pending_hits: Vec<(u8, u8, u8)>,
            appearance: crate::game::player::Appearance,
            moved: bool,
        }

        let all_arcs = self.game.player_snapshots();
        let mut snaps: Vec<PlayerSnap> = Vec::with_capacity(all_arcs.len());
        for arc in &all_arcs {
            let p = arc.read().await;
            snaps.push(PlayerSnap {
                session_id: p.id,
                player_index: p.player_index,
                position: p.position,
                direction: p.direction,
                username: p.username.clone(),
                combat_level: p.combat_level,
                pending_chat: p.pending_chat.clone(),
                pending_hits: p.pending_hits.clone(),
                appearance: p.appearance.clone(),
                moved: p.moved_this_tick,
            });
        }

        // NPC snapshot: collected once per tick across all worlds. Each entry
        // captures only the protocol-relevant fields so the per-session loop
        // never needs the world write lock again.
        #[derive(Clone)]
        struct NpcSnap {
            entity_id: EntityId,
            npc_index: u16,
            definition_id: u32,
            position: Position,
            direction: Direction,
            removed: bool,
            moved: bool,
            pending_hit: Option<(u8, u8, u8)>,
        }
        let mut npc_snaps: Vec<NpcSnap> = Vec::new();
        // Per-tick game-object snapshot (scenery + boundary). Same shape as
        // NPC snap: copy out only what the per-session loop needs so we don't
        // hold the world lock across sends.
        #[derive(Clone)]
        struct ObjSnap {
            id: u32,
            position: Position,
            obj_type: u8,
            direction: u8,
            active: bool,
        }
        let mut obj_snaps: Vec<ObjSnap> = Vec::new();
        // Per-tick ground-item snapshot. One entry per (position, item_id);
        // a tile can hold multiple stacks at the same item_id only via
        // separate stackable rules, but the wire format keys delta updates
        // by id+offset so we flatten the list here.
        #[derive(Clone)]
        struct GroundSnap {
            position: Position,
            item_id: u32,
        }
        let mut gi_snaps: Vec<GroundSnap> = Vec::new();
        if let Some(world) = self.game.get_world("main") {
            let w = world.read().await;
            for (eid, npc) in &w.npcs {
                npc_snaps.push(NpcSnap {
                    entity_id: *eid,
                    npc_index: npc.npc_index,
                    definition_id: npc.definition_id,
                    position: npc.position,
                    direction: npc.direction,
                    removed: npc.removed,
                    moved: npc.moved_this_tick,
                    pending_hit: npc.pending_hit,
                });
            }
            for (pos, obj) in &w.game_objects {
                obj_snaps.push(ObjSnap {
                    id: obj.id,
                    position: *pos,
                    obj_type: obj.obj_type,
                    direction: obj.direction,
                    active: obj.active,
                });
            }
            for (pos, items) in &w.ground_items {
                for it in items {
                    gi_snaps.push(GroundSnap {
                        position: *pos,
                        item_id: it.item_id,
                    });
                }
            }
        }

        // Step 2: per-session update.
        for session in self.sessions.all_sessions() {
            let s = session.read().await;
            if s.state != SessionState::LoggedIn {
                continue;
            }
            let player_arc = match &s.player {
                Some(p) => p.clone(),
                None => continue,
            };
            drop(s);

            // Read own state.
            let (
                own_id,
                own_pos,
                own_dir,
                own_known,
                own_known_npcs,
                own_known_objs,
                own_known_gis,
            ) = {
                let p = player_arc.read().await;
                (
                    p.id,
                    p.position,
                    p.direction,
                    p.local_players.clone(),
                    p.local_npcs.clone(),
                    p.local_game_objects.clone(),
                    p.local_ground_items.clone(),
                )
            };

            // Build SEND_PLAYER_COORDS bit stream.
            let mut bw = crate::protocol::BitWriter::new();
            bw.write_bits(own_pos.x, 11);
            bw.write_bits(own_pos.y, 13);
            bw.write_bits(own_dir as i32, 4);
            bw.write_bits(own_known.len() as i32, 8);

            // Per-known-player entries: check if still in 16-tile view.
            let mut still_local: Vec<u64> = Vec::new();
            for known_id in &own_known {
                let snap = snaps.iter().find(|s| s.session_id == *known_id);
                let still_in_view = snap
                    .map(|s| own_pos.in_range(&s.position, 16))
                    .unwrap_or(false);
                if still_in_view {
                    let s = snap.unwrap();
                    if s.moved {
                        // moved: needsUpdate=1, typeBit=0 (movement), direction(3)
                        bw.write_bits(1, 1);
                        bw.write_bits(0, 1);
                        bw.write_bits(s.direction as i32 & 0x7, 3);
                    } else {
                        bw.write_bits(0, 1); // no update
                    }
                    still_local.push(*known_id);
                } else {
                    bw.write_bits(1, 1); // needs update
                    bw.write_bits(1, 1); // update type = sprite change / remove
                    bw.write_bits(3, 2); // animation 3 = remove
                }
            }

            // New-player entries: players in view not yet known.
            let mut new_players: Vec<&PlayerSnap> = Vec::new();
            for snap in &snaps {
                if snap.session_id == own_id {
                    continue; // skip self
                }
                if still_local.contains(&snap.session_id) {
                    continue; // already known
                }
                if !own_pos.in_range(&snap.position, 16) {
                    continue; // out of range
                }
                let rel_x = snap.position.x - own_pos.x;
                let rel_y = snap.position.y - own_pos.y;
                bw.write_bits(snap.player_index as i32, 11);
                bw.write_bits(rel_x, 6); // custom client: 6 bits (authentic: 5)
                bw.write_bits(rel_y, 6);
                bw.write_bits(snap.direction as i32, 4);
                new_players.push(snap);
                if still_local.len() + new_players.len() >= 255 {
                    break;
                }
            }

            let coords_packet = bw.build_packet(OpcodeOut::SEND_PLAYER_COORDS.wire());

            // Collect type-1 chat entries: any local player (including self)
            // who chatted this tick. We look up by session_id in `snaps` since
            // pending_chat was captured in the snapshot above.
            //
            // The custom-client type-1 layout is:
            //   short senderIndex | byte 1 | string icon | string message
            // We use an empty icon string for now (no rank icons).
            let mut chat_entries: Vec<(u16, &str, &str)> = Vec::new();
            // Type-2 damage entries — (sender_idx, damage, cur_hp, max_hp).
            // Mirrors Java GameStateUpdater.playersNeedingDamageUpdate; the
            // wire layout is `short index | byte 2 | byte dmg | byte cur | byte max`.
            let mut hit_entries: Vec<(u16, u8, u8, u8)> = Vec::new();
            let mut viewers: Vec<u64> = vec![own_id];
            viewers.extend(still_local.iter().copied());
            viewers.extend(new_players.iter().map(|s| s.session_id));
            for vid in &viewers {
                if let Some(s) = snaps.iter().find(|sn| sn.session_id == *vid) {
                    for msg in &s.pending_chat {
                        chat_entries.push((s.player_index, "", msg.as_str()));
                    }
                    for (dmg, cur, max) in &s.pending_hits {
                        hit_entries.push((s.player_index, *dmg, *cur, *max));
                    }
                }
            }

            // Build SEND_UPDATE_PLAYERS containing type-5 appearance entries
            // for new players + type-1 chat entries for anyone in view who
            // chatted. Skip the packet entirely if there's nothing to say.
            let appearance_packet =
                if new_players.is_empty() && chat_entries.is_empty() && hit_entries.is_empty() {
                    None
                } else {
                    let total = (new_players.len() + chat_entries.len() + hit_entries.len()) as u16;
                    let mut apb =
                        crate::protocol::PacketBuilder::new(OpcodeOut::SEND_UPDATE_PLAYERS.wire())
                            .write_short(total);
                    for snap in &new_players {
                        let a = &snap.appearance;
                        apb = apb
                            .write_short(snap.player_index as u16)
                            .write_byte(5) // type 5: appearance
                            .write_string(&snap.username)
                            .write_byte(0) // equipment count
                            .write_byte(a.hair_colour)
                            .write_byte(a.top_colour)
                            .write_byte(a.trouser_colour)
                            .write_byte(a.skin_colour)
                            .write_byte(snap.combat_level as u8)
                            .write_byte(0) // skull
                            .write_byte(0) // has clan
                            .write_byte(0) // invisible
                            .write_byte(0) // invulnerable
                            .write_byte(10) // group id (10 = PLAYER)
                            .write_string("");
                    }
                    apb = append_custom_v235_public_chat_entries(apb, &chat_entries);
                    for (idx, dmg, cur, max) in &hit_entries {
                        apb = apb
                            .write_short(*idx)
                            .write_byte(2) // type 2: damage
                            .write_byte(*dmg)
                            .write_byte(*cur)
                            .write_byte(*max);
                    }
                    Some(apb.build())
                };

            // Build SEND_NPC_COORDS bit stream. Layout (modern / custom):
            //   localCount(8) [+ per-known-npc bits] [+ per-new-npc entry]
            //   per-known: needsUpdate(1) + (notMoving(1) + remove(2)=3) when leaving
            //   per-new:   npcIndex(12) relX(6) relY(6) sprite(4) npcId(10)
            // For the minimal stationary-NPC case the per-known branch always
            // emits "no update" (1 bit per npc) until the NPC leaves the
            // 16-tile view.
            let mut nbw = crate::protocol::BitWriter::new();
            let mut still_local_npcs: Vec<EntityId> = Vec::new();
            // count placeholder (will rewrite via header when we know exact count is fine — we already know own_known_npcs.len())
            nbw.write_bits(own_known_npcs.len() as i32, 8);
            for known_eid in &own_known_npcs {
                let snap = npc_snaps.iter().find(|n| n.entity_id == *known_eid);
                let still_in_view = snap
                    .map(|n| !n.removed && own_pos.in_range(&n.position, 16))
                    .unwrap_or(false);
                if still_in_view {
                    let n = snap.unwrap();
                    if n.moved {
                        // moved this tick: needsUpdate=1, notMoving=0, dir(3)
                        nbw.write_bits(1, 1);
                        nbw.write_bits(0, 1);
                        nbw.write_bits(n.direction as i32 & 0x7, 3);
                    } else {
                        nbw.write_bits(0, 1); // no update
                    }
                    still_local_npcs.push(*known_eid);
                } else {
                    nbw.write_bits(1, 1); // needs update
                    nbw.write_bits(1, 1); // not moving
                    nbw.write_bits(3, 2); // remove (=3)
                }
            }
            let mut new_npcs: Vec<&NpcSnap> = Vec::new();
            for n in &npc_snaps {
                if n.removed {
                    continue;
                }
                if still_local_npcs.contains(&n.entity_id) {
                    continue;
                }
                if !own_pos.in_range(&n.position, 16) {
                    continue;
                }
                let rel_x = n.position.x - own_pos.x;
                let rel_y = n.position.y - own_pos.y;
                nbw.write_bits(n.npc_index as i32, 12);
                nbw.write_bits(rel_x, 6);
                nbw.write_bits(rel_y, 6);
                nbw.write_bits(n.direction as i32, 4);
                nbw.write_bits(n.definition_id as i32, 10);
                new_npcs.push(n);
                if still_local_npcs.len() + new_npcs.len() >= 255 {
                    break;
                }
            }
            let npc_coords_packet = nbw.build_packet(OpcodeOut::SEND_NPC_COORDS.wire());

            // Build SEND_UPDATE_NPC (104) for any NPC in view that took damage
            // this tick. Layout (mirrors Java GameStateUpdater lines 526-533):
            //   short count
            //   per entry: short npc_index | byte 2 | byte dmg | byte cur_hp | byte max_hp
            let npc_hit_entries: Vec<(u16, u8, u8, u8)> = npc_snaps
                .iter()
                .filter_map(|n| {
                    if !own_pos.in_range(&n.position, 16) {
                        return None;
                    }
                    n.pending_hit.map(|(d, c, m)| (n.npc_index, d, c, m))
                })
                .collect();
            let npc_update_packet = if npc_hit_entries.is_empty() {
                None
            } else {
                let mut b = crate::protocol::PacketBuilder::new(OpcodeOut::SEND_UPDATE_NPC.wire())
                    .write_short(npc_hit_entries.len() as u16);
                for (idx, dmg, cur, max) in &npc_hit_entries {
                    b = b
                        .write_short(*idx)
                        .write_byte(2)
                        .write_byte(*dmg)
                        .write_byte(*cur)
                        .write_byte(*max);
                }
                Some(b.build())
            };

            // Build SEND_SCENERY_HANDLER (48) + SEND_BOUNDARY_HANDLER (91)
            // delta packets. Layout per object (Payload235Generator):
            //   scenery:  id (short), dx (sbyte), dy (sbyte)
            //   boundary: id (short), dx (sbyte), dy (sbyte), dir (byte)
            // Removal is signalled by id = 60000 with the original offsets.
            // The packet is only sent when there are deltas — if nothing
            // changed we'd just be wasting a frame.
            let mut still_local_objs: Vec<Position> = Vec::new();
            let mut scenery_adds: Vec<&ObjSnap> = Vec::new();
            let mut scenery_removes: Vec<Position> = Vec::new();
            let mut boundary_adds: Vec<&ObjSnap> = Vec::new();
            let mut boundary_removes: Vec<(Position, u8)> = Vec::new();

            // Per-known-object: still in view? — keep, else mark for removal.
            for known_pos in &own_known_objs {
                let snap = obj_snaps.iter().find(|o| o.position == *known_pos);
                let still = snap
                    .map(|o| o.active && own_pos.in_range(&o.position, 16))
                    .unwrap_or(false);
                if still {
                    still_local_objs.push(*known_pos);
                } else {
                    if let Some(o) = snap {
                        if o.obj_type == 1 {
                            boundary_removes.push((*known_pos, o.direction));
                        } else {
                            scenery_removes.push(*known_pos);
                        }
                    } else {
                        // Object vanished from world (no snap entry).
                        scenery_removes.push(*known_pos);
                    }
                }
            }

            // New objects in view → add.
            for o in &obj_snaps {
                if !o.active {
                    continue;
                }
                if still_local_objs.contains(&o.position) {
                    continue;
                }
                if !own_pos.in_range(&o.position, 16) {
                    continue;
                }
                if o.obj_type == 1 {
                    boundary_adds.push(o);
                } else {
                    scenery_adds.push(o);
                }
            }

            let scenery_packet = if scenery_adds.is_empty() && scenery_removes.is_empty() {
                None
            } else {
                let mut b =
                    crate::protocol::PacketBuilder::new(OpcodeOut::SEND_SCENERY_HANDLER.wire());
                for o in &scenery_adds {
                    let dx = (o.position.x - own_pos.x) as i8 as u8;
                    let dy = (o.position.y - own_pos.y) as i8 as u8;
                    b = b.write_short(o.id as u16).write_byte(dx).write_byte(dy);
                }
                for pos in &scenery_removes {
                    let dx = (pos.x - own_pos.x) as i8 as u8;
                    let dy = (pos.y - own_pos.y) as i8 as u8;
                    b = b.write_short(60000).write_byte(dx).write_byte(dy);
                }
                Some(b.build())
            };

            let boundary_packet = if boundary_adds.is_empty() && boundary_removes.is_empty() {
                None
            } else {
                let mut b =
                    crate::protocol::PacketBuilder::new(OpcodeOut::SEND_BOUNDARY_HANDLER.wire());
                for o in &boundary_adds {
                    let dx = (o.position.x - own_pos.x) as i8 as u8;
                    let dy = (o.position.y - own_pos.y) as i8 as u8;
                    b = b
                        .write_short(o.id as u16)
                        .write_byte(dx)
                        .write_byte(dy)
                        .write_byte(o.direction);
                }
                for (pos, dir) in &boundary_removes {
                    let dx = (pos.x - own_pos.x) as i8 as u8;
                    let dy = (pos.y - own_pos.y) as i8 as u8;
                    b = b
                        .write_short(60000)
                        .write_byte(dx)
                        .write_byte(dy)
                        .write_byte(*dir);
                }
                Some(b.build())
            };

            // Build SEND_GROUND_ITEM_HANDLER (99) deltas. Layout per entry:
            //   add:            short(id)          | byte(dx) | byte(dy)
            //   remove in grid: short(id | 0x8000) | byte(dx) | byte(dy)
            //   clear tile:     byte(255)          | byte(dx) | byte(dy)
            let mut still_local_gis: Vec<(Position, u32)> = Vec::new();
            let mut gi_adds: Vec<&GroundSnap> = Vec::new();
            let mut gi_removes: Vec<(Position, u32)> = Vec::new();
            for (kpos, kid) in &own_known_gis {
                let still = gi_snaps.iter().any(|g| {
                    g.position == *kpos && g.item_id == *kid && own_pos.in_range(&g.position, 16)
                });
                if still {
                    still_local_gis.push((*kpos, *kid));
                } else {
                    gi_removes.push((*kpos, *kid));
                }
            }
            for g in &gi_snaps {
                if still_local_gis
                    .iter()
                    .any(|(p, id)| *p == g.position && *id == g.item_id)
                {
                    continue;
                }
                if !own_pos.in_range(&g.position, 16) {
                    continue;
                }
                gi_adds.push(g);
            }

            let gi_add_pairs: Vec<(Position, u32)> =
                gi_adds.iter().map(|g| (g.position, g.item_id)).collect();
            let ground_packet = build_ground_item_delta_packet(own_pos, &gi_add_pairs, &gi_removes);

            // Send all packets.
            let s = session.read().await;
            let _ = s.send(coords_packet).await;
            if let Some(ap) = appearance_packet {
                let _ = s.send(ap).await;
            }
            let _ = s.send(npc_coords_packet).await;
            if let Some(p) = npc_update_packet {
                let _ = s.send(p).await;
            }
            if let Some(p) = scenery_packet {
                let _ = s.send(p).await;
            }
            if let Some(p) = boundary_packet {
                let _ = s.send(p).await;
            }
            if let Some(p) = ground_packet {
                let _ = s.send(p).await;
            }
            drop(s);

            // Update the player's local lists.
            let new_obj_positions: Vec<Position> = scenery_adds
                .iter()
                .map(|o| o.position)
                .chain(boundary_adds.iter().map(|o| o.position))
                .collect();
            let mut p = player_arc.write().await;
            p.local_players = still_local;
            p.local_players
                .extend(new_players.iter().map(|s| s.session_id));
            p.local_npcs = still_local_npcs;
            p.local_npcs.extend(new_npcs.iter().map(|n| n.entity_id));
            p.local_game_objects = still_local_objs;
            p.local_game_objects.extend(new_obj_positions);
            p.local_ground_items = still_local_gis;
            p.local_ground_items.extend(gi_add_pairs);
        }

        // End-of-tick: clear every player's pending_chat / pending_hits and
        // every NPC's pending_hit so the same event doesn't replay next tick.
        // Done in a separate pass so the snapshot above kept the values
        // stable across all session loops.
        for arc in &all_arcs {
            let mut p = arc.write().await;
            p.pending_chat.clear();
            p.pending_hits.clear();
        }
        if let Some(world) = self.game.get_world("main") {
            let mut w = world.write().await;
            for (_, npc) in &mut w.npcs {
                npc.pending_hit = None;
            }
        }
    }

    /// Auto-save all online players' positions to the DB.
    ///
    /// Runs every AUTO_SAVE_INTERVAL ticks (~30 s). Only position is flushed
    /// here; skills/inventory writeback is a follow-on. If no repository is
    /// attached the call is a no-op (bench/smoke mode).
    async fn auto_save(&self) {
        let Some(repo) = self.players.clone() else {
            debug!(
                "Auto-save: no persistence (bench mode), {} online",
                self.game.online_count()
            );
            return;
        };

        let mut saved = 0usize;
        for session in self.sessions.all_sessions() {
            let s = session.read().await;
            if s.state != SessionState::LoggedIn {
                continue;
            }
            if let Some(ref player_arc) = s.player {
                let p = player_arc.read().await;
                let ok = repo
                    .update_position_by_username(&p.username, p.position.x, p.position.y)
                    .await
                    .map_err(|e| warn!("Auto-save position failed for {}: {}", p.username, e))
                    .is_ok();

                if ok {
                    if let Some(db_id) = p.db_id {
                        let sr = build_skills_record(db_id, &p);
                        if let Err(e) = repo.save_skills(&sr).await {
                            warn!("Auto-save skills failed for {}: {}", p.username, e);
                        }
                    }
                    saved += 1;
                }
            }
        }
        debug!("Auto-save: persisted {} player(s)", saved);
    }

    /// Handle account registration request (REGISTER_ACCOUNT opcode).
    ///
    /// Packet layout (v177+): version(i32) username(string) password(string).
    /// Response codes: 2=username taken, 3=invalid name, 14=disabled, 18=success.
    /// Connection is always dropped after the response — client re-connects to log in.
    async fn handle_register(
        &mut self,
        session: Arc<RwLock<Session>>,
        packet: Packet,
    ) -> HandleResult {
        let mut reader = PacketReader::new(&packet);
        let _version = reader.read_int().unwrap_or(0);
        let username = match reader.read_string() {
            Ok(u) => u,
            Err(_) => return HandleResult::Disconnect,
        };
        let password = match reader.read_string() {
            Ok(p) => p,
            Err(_) => return HandleResult::Disconnect,
        };

        let send_code = |code: u8| PacketBuilder::new(0).write_byte(code).build();

        if username.len() < 2 || username.len() > 12 || password.len() < 4 {
            let s = session.read().await;
            let _ = s.send(send_code(3)).await;
            return HandleResult::Disconnect;
        }

        let Some(repo) = self.players.clone() else {
            let s = session.read().await;
            let _ = s.send(send_code(14)).await; // registration disabled
            return HandleResult::Disconnect;
        };

        match repo.username_exists(&username).await {
            Ok(true) => {
                let s = session.read().await;
                let _ = s.send(send_code(2)).await; // username taken
                return HandleResult::Disconnect;
            }
            Err(e) => {
                warn!("DB error checking username {}: {}", username, e);
                let s = session.read().await;
                let _ = s.send(send_code(5)).await;
                return HandleResult::Disconnect;
            }
            Ok(false) => {}
        }

        let hash = match hash_password(&password) {
            Ok(h) => h,
            Err(e) => {
                warn!("Failed to hash password for {}: {}", username, e);
                let s = session.read().await;
                let _ = s.send(send_code(5)).await;
                return HandleResult::Disconnect;
            }
        };

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        let mut record = PlayerRecord::default();
        record.username = username.clone();
        record.password_hash = hash;
        record.creation_date = now;

        match repo.create(&record).await {
            Ok(player_id) => {
                let mut skills = SkillsRecord::default();
                skills.player_id = player_id;
                if let Err(e) = repo.save_skills(&skills).await {
                    warn!("Failed to seed skills for {}: {}", username, e);
                }
                info!("Account registered: {}", username);
                let s = session.read().await;
                let _ = s.send(send_code(18)).await; // success
                HandleResult::Disconnect
            }
            Err(e) => {
                warn!("Failed to create player {}: {}", username, e);
                let s = session.read().await;
                let _ = s.send(send_code(5)).await;
                HandleResult::Disconnect
            }
        }
    }
}

struct LiveContentRuntimeSink<'a> {
    player: &'a mut Player,
    shop: &'a mut ShopHandler,
    tick_count: u64,
    messages: Vec<String>,
    packets: Vec<Packet>,
}

impl<'a> LiveContentRuntimeSink<'a> {
    fn new(player: &'a mut Player, shop: &'a mut ShopHandler, tick_count: u64) -> Self {
        Self {
            player,
            shop,
            tick_count,
            messages: Vec::new(),
            packets: Vec::new(),
        }
    }

    fn ensure_player(&self, player_id: u64) -> Result<(), String> {
        if self.player.id == player_id {
            Ok(())
        } else {
            Err(format!(
                "content command targeted player {player_id}, active player is {}",
                self.player.id
            ))
        }
    }
}

impl ContentRuntimeSink for LiveContentRuntimeSink<'_> {
    fn send_message(&mut self, player_id: u64, text: &str) -> Result<(), String> {
        self.ensure_player(player_id)?;
        self.messages.push(text.to_string());
        Ok(())
    }

    fn open_shop(&mut self, player_id: u64, shop_id: u32) -> Result<(), String> {
        self.ensure_player(player_id)?;
        let packets = self
            .shop
            .open_shop(player_id, shop_id, self.tick_count)
            .map_err(|e| e.to_string())?;
        self.packets.extend(packets);
        Ok(())
    }

    fn start_dialogue(&mut self, player_id: u64, _dialogue_id: &str) -> Result<(), String> {
        self.ensure_player(player_id)
    }

    fn set_quest_stage(
        &mut self,
        player_id: u64,
        _quest_id: &str,
        _stage: i32,
    ) -> Result<(), String> {
        self.ensure_player(player_id)
    }

    fn add_inventory_item(
        &mut self,
        player_id: u64,
        item_id: u32,
        amount: u32,
    ) -> Result<(), String> {
        self.ensure_player(player_id)?;
        let item = if item_id == 10 {
            crate::game::player::Item::stackable(item_id, amount)
        } else {
            crate::game::player::Item::new(item_id, amount)
        };
        if !self.player.inventory.add(item) {
            return Err("inventory full".to_string());
        }
        self.packets.push(build_inventory_packet(self.player));
        Ok(())
    }

    fn remove_inventory_item(
        &mut self,
        player_id: u64,
        item_id: u32,
        amount: u32,
    ) -> Result<(), String> {
        self.ensure_player(player_id)?;
        if self.player.inventory.count(item_id) < amount {
            return Err(format!("missing inventory item {item_id} x {amount}"));
        }
        self.player.inventory.remove_amount(item_id, amount);
        self.packets.push(build_inventory_packet(self.player));
        Ok(())
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

    let items: Vec<_> = player
        .inventory
        .items()
        .iter()
        .filter_map(|s| s.as_ref())
        .collect();

    builder = builder.write_byte(items.len() as u8);

    for item in items {
        builder = builder.write_short(item.id as u16);
        builder = builder.write_byte(if item.wielded { 1 } else { 0 });
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
        EquipmentSlot::Head,
        EquipmentSlot::Cape,
        EquipmentSlot::Amulet,
        EquipmentSlot::Weapon,
        EquipmentSlot::Body,
        EquipmentSlot::Shield,
        EquipmentSlot::Legs,
        EquipmentSlot::Gloves,
        EquipmentSlot::Boots,
        EquipmentSlot::Ring,
    ];

    let equipped: Vec<(u8, &crate::game::player::Item)> = SLOTS
        .iter()
        .enumerate()
        .filter_map(|(idx, slot)| player.equipment.get(*slot).map(|i| (idx as u8, i)))
        .collect();

    let mut builder =
        PacketBuilder::new(OpcodeOut::SEND_EQUIPMENT.into()).write_byte(equipped.len() as u8);
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
        .write_byte(if player.settings.one_mouse_button {
            1
        } else {
            0
        })
        .write_byte(if player.settings.sound_off { 1 } else { 0 })
        .build()
}

fn build_combat_style_packet(style: u8) -> Packet {
    PacketBuilder::new(OpcodeOut::SEND_COMBAT_STYLE.into())
        .write_byte(style)
        .build()
}

fn object_command_index(opcode: OpcodeIn) -> u8 {
    match opcode {
        OpcodeIn::OBJECT_COMMAND => 0,
        OpcodeIn::OBJECT_COMMAND2 => 1,
        _ => 0,
    }
}

fn boundary_command_index(opcode: OpcodeIn) -> u8 {
    match opcode {
        OpcodeIn::INTERACT_WITH_BOUNDARY => 0,
        OpcodeIn::INTERACT_WITH_BOUNDARY2 => 1,
        _ => 0,
    }
}

fn build_prayers_active_packet(prayer: &PrayerState) -> Packet {
    let mut builder = PacketBuilder::new(OpcodeOut::SEND_PRAYERS_ACTIVE.into());
    for id in 0..14 {
        let active = PrayerId::from_id(id)
            .map(|prayer_id| prayer.is_active(prayer_id))
            .unwrap_or(false);
        builder = builder.write_byte(if active { 1 } else { 0 });
    }
    builder.build()
}

fn build_server_configs_packet() -> Packet {
    let first_byte_configs: [u8; 39] = [
        0, // 3 player level limit
        0, // 4 spawn auction NPCs
        0, // 5 spawn ironman NPCs
        1, // 6 floating nametags
        0, // 7 clans
        0, // 8 kill feed
        0, // 9 fog toggle
        1, // 10 ground item toggle
        0, // 11 auto message switch
        0, // 12 batch progression
        1, // 13 side menu toggle
        1, // 14 inventory count toggle
        1, // 15 zoom view toggle
        1, // 16 menu combat style toggle
        1, // 17 fightmode selector toggle
        1, // 18 experience counter toggle
        1, // 19 experience drops toggle
        1, // 20 items on death menu
        1, // 21 show roof toggle
        0, // 22 hide IP
        1, // 23 remember
        0, // 24 global chat
        1, // 25 skill menus
        1, // 26 quest menus
        0, // 27 experience elixirs
        1, // 28 keyboard shortcuts
        1, // 29 custom banks
        0, // 30 bank pins
        0, // 31 bank notes
        0, // 32 cert deposit
        0, // 33 custom firemaking
        1, // 34 drop-x
        1, // 35 exp info
        0, // 36 woodcutting guild
        0, // 37 decanting
        0, // 38 certs to bank
        0, // 39 custom rank display
        1, // 40 right-click bank
        0, // 41 fixed overhead chat
    ];
    let middle_byte_configs: [u8; 2] = [
        1, // 43 members
        0, // 44 display logo sprite
    ];
    let final_byte_configs: [u8; 41] = [
        50, // 46 FPS
        0,  // 47 email
        0,  // 48 registration limit
        1,  // 49 allow resize
        1,  // 50 lenient contact details
        0,  // 51 fatigue
        0,  // 52 custom sprites
        1,  // 53 player commands
        0,  // 54 pets
        4,  // 55 max walking speed
        0,  // 56 unidentified herb names
        1,  // 57 quest started indicator
        0,  // 58 depletable fishing spots
        0,  // 59 improved item/object names
        0,  // 60 runecraft
        0,  // 61 custom landscape
        1,  // 62 equipment tab
        0,  // 63 bank presets
        0,  // 64 parties
        0,  // 65 extended mining rocks
        4,  // 66 steps per frame
        0,  // 67 left-click webs
        0,  // 68 NPC kill counters
        0,  // 69 custom UI
        0,  // 70 global friend
        0,  // 71 character creation mode
        1,  // 72 skilling exp rate
        0,  // 73 harvesting
        0,  // 74 hide login box
        0,  // 75 global friend chat
        1,  // 76 right-click trade
        0,  // 77 sleep feature
        0,  // 78 extended cats
        0,  // 79 certs as notes
        0,  // 80 openpk points
        1,  // 81 openpk points to gp ratio
        0,  // 82 openpk presets
        0,  // 83 underground flicker
        0,  // 84 disable minimap rotation
        1,  // 85 allow bearded ladies
        0,  // 86 pride month
    ];

    let mut builder = write_config_string(
        write_config_string(
            PacketBuilder::new(OpcodeOut::SEND_SERVER_CONFIGS.into()),
            "OpenRSC Rust",
        ),
        "OpenRSC Rust",
    );
    for value in first_byte_configs {
        builder = builder.write_byte(value);
    }
    builder = write_config_string(builder, "Welcome to OpenRSC Rust");
    for value in middle_byte_configs {
        builder = builder.write_byte(value);
    }
    builder = write_config_string(builder, "");
    for value in final_byte_configs {
        builder = builder.write_byte(value);
    }

    write_config_string(
        write_config_string(builder, "010001"),
        &server_rsa_modulus_hex(),
    )
    .build()
}

fn write_config_string(builder: PacketBuilder, value: &str) -> PacketBuilder {
    builder.write_bytes(value.as_bytes()).write_byte(10)
}

fn server_rsa_modulus_hex() -> String {
    let pem = include_str!("../../../server-java-modern/server.pem");
    match crate::protocol::rsa::RsaKey::from_pkcs8_pem(pem) {
        Ok(key) => even_hex(key.modulus().to_str_radix(16)),
        Err(e) => {
            warn!(
                "Failed to parse Java server RSA key for server configs: {}",
                e
            );
            "01".to_string()
        }
    }
}

fn even_hex(hex: String) -> String {
    if hex.len() % 2 == 0 {
        hex
    } else {
        format!("0{hex}")
    }
}

fn collision_checked_walk_queue(
    world: &World,
    policy: MovementCollisionPolicy,
    walk_queue: Vec<Position>,
) -> Vec<Position> {
    let mut checked = Vec::with_capacity(walk_queue.len());
    let mut iter = walk_queue.into_iter();
    let Some(mut from) = iter.next() else {
        return checked;
    };

    checked.push(from);

    for waypoint in iter {
        let mut cursor = from;
        while cursor != waypoint {
            let dx = (waypoint.x - cursor.x).signum();
            let dy = (waypoint.y - cursor.y).signum();
            let next = Position::with_plane(cursor.x + dx, cursor.y + dy, cursor.plane);

            if !world.can_move_with_collision(cursor, next, policy) {
                return checked;
            }

            cursor = next;
        }

        checked.push(waypoint);
        from = waypoint;
    }

    checked
}

fn combat_style_from_wire(style: u8) -> Option<CombatStyle> {
    match style {
        0 => Some(CombatStyle::Controlled),
        1 => Some(CombatStyle::Aggressive),
        2 => Some(CombatStyle::Accurate),
        3 => Some(CombatStyle::Defensive),
        _ => None,
    }
}

fn combat_style_to_wire(style: CombatStyle) -> u8 {
    match style {
        CombatStyle::Controlled => 0,
        CombatStyle::Aggressive => 1,
        CombatStyle::Accurate => 2,
        CombatStyle::Defensive => 3,
    }
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

fn build_ground_item_delta_packet(
    origin: Position,
    adds: &[(Position, u32)],
    removes: &[(Position, u32)],
) -> Option<Packet> {
    if adds.is_empty() && removes.is_empty() {
        return None;
    }

    let mut builder = PacketBuilder::new(OpcodeOut::SEND_GROUND_ITEM_HANDLER.wire());
    for (pos, item_id) in adds {
        let dx = (pos.x - origin.x) as i8 as u8;
        let dy = (pos.y - origin.y) as i8 as u8;
        builder = builder
            .write_short(*item_id as u16)
            .write_byte(dx)
            .write_byte(dy);
    }
    for (pos, item_id) in removes {
        let dx = (pos.x - origin.x) as i8 as u8;
        let dy = (pos.y - origin.y) as i8 as u8;
        if origin.in_range(pos, 16) {
            builder = builder
                .write_short((*item_id as u16) | 0x8000)
                .write_byte(dx)
                .write_byte(dy);
        } else {
            builder = builder.write_byte(0xFF).write_byte(dx).write_byte(dy);
        }
    }

    Some(builder.build())
}

fn append_custom_v235_public_chat_entries(
    builder: PacketBuilder,
    entries: &[(u16, &str, &str)],
) -> PacketBuilder {
    if entries.is_empty() {
        return builder;
    }

    let payload = crate::game::state_updater::build_custom_v235_player_chat_update_payload(entries);
    builder.write_bytes(&payload[2..])
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct PrivacySettingsRequest {
    block_chat: bool,
    block_private: bool,
    block_trade: bool,
    block_duel: bool,
}

impl PrivacySettingsRequest {
    fn parse(packet: &Packet) -> Result<Self, ()> {
        let mut reader = PacketReader::new(packet);
        let block_chat = reader.read_byte().map_err(|_| ())? != 0;
        let block_private = reader.read_byte().map_err(|_| ())? != 0;
        let block_trade = reader.read_byte().map_err(|_| ())? != 0;
        let block_duel = reader.read_byte().map_err(|_| ())? != 0;

        if reader.remaining() != 0 {
            return Err(());
        }

        Ok(Self {
            block_chat,
            block_private,
            block_trade,
            block_duel,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct GameSettingsRequest {
    index: u8,
    value: u8,
}

impl GameSettingsRequest {
    fn parse(packet: &Packet) -> Result<Self, ()> {
        let mut reader = PacketReader::new(packet);
        let index = reader.read_byte().map_err(|_| ())?;
        let value = reader.read_byte().map_err(|_| ())?;

        if reader.remaining() != 0 {
            return Err(());
        }

        Ok(Self { index, value })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct PrayerToggleRequest {
    prayer: PrayerId,
}

impl PrayerToggleRequest {
    fn parse(packet: &Packet) -> Result<Self, ()> {
        let mut reader = PacketReader::new(packet);
        let prayer_id = reader.read_byte().map_err(|_| ())?;

        if reader.remaining() != 0 {
            return Err(());
        }

        Ok(Self {
            prayer: PrayerId::from_id(prayer_id).ok_or(())?,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ItemOnItemRequest {
    item_slot: usize,
    target_slot: usize,
}

impl ItemOnItemRequest {
    fn parse(packet: &Packet) -> Result<Self, ()> {
        let mut reader = PacketReader::new(packet);
        let item_slot = reader.read_short().map_err(|_| ())? as usize;
        let target_slot = reader.read_short().map_err(|_| ())? as usize;

        if reader.remaining() != 0 {
            return Err(());
        }

        Ok(Self {
            item_slot,
            target_slot,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ItemOnObjectRequest {
    position: Position,
    item_slot: usize,
}

impl ItemOnObjectRequest {
    fn parse_scenery(packet: &Packet) -> Result<Self, ()> {
        let mut reader = PacketReader::new(packet);
        let x = reader.read_short().map_err(|_| ())?;
        let y = reader.read_short().map_err(|_| ())?;
        let item_slot = reader.read_short().map_err(|_| ())? as usize;

        if reader.remaining() != 0 {
            return Err(());
        }

        Ok(Self {
            position: Position::new(x as i32, y as i32),
            item_slot,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ItemOnNpcRequest {
    npc_index: u16,
    item_slot: usize,
}

impl ItemOnNpcRequest {
    fn parse(packet: &Packet) -> Result<Self, ()> {
        let mut reader = PacketReader::new(packet);
        let npc_index = reader.read_short().map_err(|_| ())?;
        let item_slot = reader.read_short().map_err(|_| ())? as usize;

        if reader.remaining() != 0 {
            return Err(());
        }

        Ok(Self {
            npc_index,
            item_slot,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct DialogueAnswerRequest {
    option: i8,
}

impl DialogueAnswerRequest {
    fn parse(packet: &Packet) -> Result<Self, ()> {
        let mut reader = PacketReader::new(packet);
        let option = reader.read_byte().map_err(|_| ())? as i8;

        if reader.remaining() != 0 {
            return Err(());
        }

        Ok(Self { option })
    }
}

fn bank_handler_error_message(error: &BankHandlerError) -> Option<String> {
    match error {
        BankHandlerError::BankClosed => None,
        BankHandlerError::BankError(error) => bank_error_message(error).map(str::to_string),
        BankHandlerError::PinRequired => Some("Bank PIN verification required".to_string()),
        BankHandlerError::MalformedPacket => None,
    }
}

fn shop_handler_error_message(error: &ShopHandlerError) -> Option<String> {
    match error {
        ShopHandlerError::ShopNotFound
        | ShopHandlerError::NoOpenShop
        | ShopHandlerError::MalformedPacket => None,
        ShopHandlerError::Transaction(result) => match result {
            crate::game::shop::ShopResult::InsufficientFunds { .. } => {
                Some("You don't have enough coins.".to_string())
            }
            crate::game::shop::ShopResult::OutOfStock
            | crate::game::shop::ShopResult::InsufficientStock { .. } => {
                Some("The shop has run out of stock.".to_string())
            }
            crate::game::shop::ShopResult::WontBuy => {
                Some("The shop is not buying that item.".to_string())
            }
            crate::game::shop::ShopResult::InventoryFull => {
                Some("You don't have room to hold everything!".to_string())
            }
            crate::game::shop::ShopResult::Success | crate::game::shop::ShopResult::InvalidItem => {
                None
            }
        },
    }
}

fn bank_error_message(error: &BankError) -> Option<&'static str> {
    match error {
        BankError::BankFull | BankError::StackOverflow => {
            Some("You don't have room for that in your bank")
        }
        BankError::InvalidAmount | BankError::ItemNotFound => None,
        BankError::InsufficientAmount => Some("You don't have enough of that item"),
        BankError::InvalidSlot => None,
        BankError::BankClosed => None,
    }
}

#[cfg(test)]
mod packet_adapter_tests {
    use super::*;
    use crate::game::content::{ContentEffect, ContentTrigger, TriggerKind};
    use crate::game::world::GameObject;
    use std::path::PathBuf;

    struct ObjectCommandMessage;

    impl ContentTrigger for ObjectCommandMessage {
        fn name(&self) -> &'static str {
            "test_object_command_message"
        }

        fn kind(&self) -> TriggerKind {
            TriggerKind::UseObject
        }

        fn handle(&self, event: &ContentEvent) -> Vec<ContentEffect> {
            match event {
                ContentEvent::UseObject {
                    player_id,
                    object_id,
                    command,
                    ..
                } => vec![ContentEffect::message(
                    *player_id,
                    format!("object {object_id} command {command}"),
                )],
                _ => Vec::new(),
            }
        }
    }

    struct BoundaryCommandMessage;

    impl ContentTrigger for BoundaryCommandMessage {
        fn name(&self) -> &'static str {
            "test_boundary_command_message"
        }

        fn kind(&self) -> TriggerKind {
            TriggerKind::UseBoundary
        }

        fn handle(&self, event: &ContentEvent) -> Vec<ContentEffect> {
            match event {
                ContentEvent::UseBoundary {
                    player_id,
                    boundary_id,
                    command,
                    ..
                } => vec![ContentEffect::message(
                    *player_id,
                    format!("boundary {boundary_id} command {command}"),
                )],
                _ => Vec::new(),
            }
        }
    }

    struct ItemOnItemMessage;

    impl ContentTrigger for ItemOnItemMessage {
        fn name(&self) -> &'static str {
            "test_item_on_item_message"
        }

        fn kind(&self) -> TriggerKind {
            TriggerKind::UseItemOnItem
        }

        fn handle(&self, event: &ContentEvent) -> Vec<ContentEffect> {
            match event {
                ContentEvent::UseItemOnItem {
                    player_id,
                    item_id,
                    item_slot,
                    target_item_id,
                    target_slot,
                } => vec![ContentEffect::message(
                    *player_id,
                    format!(
                        "item {item_id} slot {item_slot} target {target_item_id} slot {target_slot}"
                    ),
                )],
                _ => Vec::new(),
            }
        }
    }

    struct ItemOnObjectMessage;

    impl ContentTrigger for ItemOnObjectMessage {
        fn name(&self) -> &'static str {
            "test_item_on_object_message"
        }

        fn kind(&self) -> TriggerKind {
            TriggerKind::UseItemOnObject
        }

        fn handle(&self, event: &ContentEvent) -> Vec<ContentEffect> {
            match event {
                ContentEvent::UseItemOnObject {
                    player_id,
                    item_id,
                    item_slot,
                    object_id,
                    position,
                } => vec![ContentEffect::message(
                    *player_id,
                    format!(
                        "item {item_id} slot {item_slot} object {object_id} at {},{}",
                        position.x, position.y
                    ),
                )],
                _ => Vec::new(),
            }
        }
    }

    struct ItemOnNpcMessage;

    impl ContentTrigger for ItemOnNpcMessage {
        fn name(&self) -> &'static str {
            "test_item_on_npc_message"
        }

        fn kind(&self) -> TriggerKind {
            TriggerKind::UseItemOnNpc
        }

        fn handle(&self, event: &ContentEvent) -> Vec<ContentEffect> {
            match event {
                ContentEvent::UseItemOnNpc {
                    player_id,
                    item_id,
                    item_slot,
                    npc_id,
                    npc_index,
                } => vec![ContentEffect::message(
                    *player_id,
                    format!("item {item_id} slot {item_slot} npc {npc_id} index {npc_index}"),
                )],
                _ => Vec::new(),
            }
        }
    }

    struct DialogueAnswerMessage;

    impl ContentTrigger for DialogueAnswerMessage {
        fn name(&self) -> &'static str {
            "test_dialogue_answer_message"
        }

        fn kind(&self) -> TriggerKind {
            TriggerKind::DialogueAnswer
        }

        fn handle(&self, event: &ContentEvent) -> Vec<ContentEffect> {
            match event {
                ContentEvent::DialogueAnswer { player_id, option } => vec![ContentEffect::message(
                    *player_id,
                    format!("dialogue option {option}"),
                )],
                _ => Vec::new(),
            }
        }
    }

    async fn logged_in_test_session(
        state: &mut ServerState,
    ) -> (tokio::sync::mpsc::Receiver<Packet>, Arc<RwLock<Player>>) {
        let (tx, rx) = tokio::sync::mpsc::channel(8);
        let session = state
            .sessions
            .create_session("127.0.0.1:12345".parse().unwrap(), tx)
            .await
            .unwrap();
        let player = Arc::new(RwLock::new(Player::new(1, "shopper".to_string())));
        {
            let mut s = session.write().await;
            s.state = SessionState::LoggedIn;
            s.client_version = 235;
            s.player = Some(player.clone());
        }
        (rx, player)
    }

    async fn registered_logged_in_test_session(
        state: &mut ServerState,
        port: u16,
        username: &str,
    ) -> (tokio::sync::mpsc::Receiver<Packet>, Arc<RwLock<Player>>) {
        let (tx, rx) = tokio::sync::mpsc::channel(8);
        let session = state
            .sessions
            .create_session(format!("127.0.0.1:{port}").parse().unwrap(), tx)
            .await
            .unwrap();
        let session_id = session.read().await.id;
        let player = Arc::new(RwLock::new(Player::new(session_id, username.to_string())));
        state
            .game
            .register_player_arc(session_id, player.clone())
            .await;
        {
            let mut s = session.write().await;
            s.state = SessionState::LoggedIn;
            s.client_version = 235;
            s.player = Some(player.clone());
        }
        (rx, player)
    }

    fn walk_to_point_packet(start_x: i32, start_y: i32, deltas: &[(i8, i8)]) -> Packet {
        let mut builder = PacketBuilder::new(187)
            .write_short(start_x as u16)
            .write_short(start_y as u16);
        for (dx, dy) in deltas {
            builder = builder.write_byte(*dx as u8).write_byte(*dy as u8);
        }
        builder.build()
    }

    #[test]
    fn parses_java_custom_privacy_payload() {
        let packet = Packet::new(64, vec![1, 0, 1, 0]);
        let request = PrivacySettingsRequest::parse(&packet).unwrap();

        assert!(request.block_chat);
        assert!(!request.block_private);
        assert!(request.block_trade);
        assert!(!request.block_duel);
    }

    #[test]
    fn rejects_malformed_privacy_payloads() {
        assert!(PrivacySettingsRequest::parse(&Packet::new(64, vec![1, 0, 1])).is_err());
        assert!(PrivacySettingsRequest::parse(&Packet::new(64, vec![1, 0, 1, 0, 1])).is_err());
    }

    #[test]
    fn parses_java_game_settings_payload() {
        let packet = Packet::new(213, vec![2, 1]);
        let request = GameSettingsRequest::parse(&packet).unwrap();

        assert_eq!(request.index, 2);
        assert_eq!(request.value, 1);
    }

    #[test]
    fn rejects_malformed_game_settings_payloads() {
        assert!(GameSettingsRequest::parse(&Packet::new(213, vec![1])).is_err());
        assert!(GameSettingsRequest::parse(&Packet::new(213, vec![1, 0, 1])).is_err());
    }

    #[test]
    fn parses_java_custom_prayer_payload() {
        let packet = Packet::new(60, vec![8]);
        let request = PrayerToggleRequest::parse(&packet).unwrap();

        assert_eq!(request.prayer, PrayerId::ProtectItems);
    }

    #[test]
    fn rejects_malformed_prayer_payloads() {
        assert!(PrayerToggleRequest::parse(&Packet::new(60, vec![])).is_err());
        assert!(PrayerToggleRequest::parse(&Packet::new(60, vec![1, 2])).is_err());
        assert!(PrayerToggleRequest::parse(&Packet::new(60, vec![99])).is_err());
    }

    #[test]
    fn parses_java_item_use_item_payload() {
        let packet = PacketBuilder::new(91).write_short(2).write_short(5).build();
        let request = ItemOnItemRequest::parse(&packet).unwrap();

        assert_eq!(
            request,
            ItemOnItemRequest {
                item_slot: 2,
                target_slot: 5
            }
        );
    }

    #[test]
    fn rejects_malformed_item_use_item_payloads() {
        assert!(ItemOnItemRequest::parse(&Packet::new(91, vec![0, 1])).is_err());
        assert!(ItemOnItemRequest::parse(&Packet::new(91, vec![0, 1, 0, 2, 0])).is_err());
    }

    #[test]
    fn parses_java_use_item_on_scenery_payload() {
        let packet = PacketBuilder::new(115)
            .write_short(111)
            .write_short(222)
            .write_short(3)
            .build();
        let request = ItemOnObjectRequest::parse_scenery(&packet).unwrap();

        assert_eq!(
            request,
            ItemOnObjectRequest {
                position: Position::new(111, 222),
                item_slot: 3
            }
        );
    }

    #[test]
    fn rejects_malformed_use_item_on_scenery_payloads() {
        assert!(ItemOnObjectRequest::parse_scenery(&Packet::new(115, vec![0, 1, 0, 2])).is_err());
        assert!(
            ItemOnObjectRequest::parse_scenery(&Packet::new(115, vec![0, 1, 0, 2, 0, 3, 0]))
                .is_err()
        );
    }

    #[test]
    fn parses_java_npc_use_item_payload() {
        let packet = PacketBuilder::new(135)
            .write_short(42)
            .write_short(3)
            .build();
        let request = ItemOnNpcRequest::parse(&packet).unwrap();

        assert_eq!(
            request,
            ItemOnNpcRequest {
                npc_index: 42,
                item_slot: 3
            }
        );
    }

    #[test]
    fn rejects_malformed_npc_use_item_payloads() {
        assert!(ItemOnNpcRequest::parse(&Packet::new(135, vec![0, 1])).is_err());
        assert!(ItemOnNpcRequest::parse(&Packet::new(135, vec![0, 1, 0, 2, 0])).is_err());
    }

    #[test]
    fn parses_java_question_dialog_answer_payload() {
        let request = DialogueAnswerRequest::parse(&Packet::new(116, vec![2])).unwrap();

        assert_eq!(request, DialogueAnswerRequest { option: 2 });
    }

    #[test]
    fn parses_java_cancel_question_dialog_answer_payload_as_signed_byte() {
        let request = DialogueAnswerRequest::parse(&Packet::new(116, vec![0xFF])).unwrap();

        assert_eq!(request, DialogueAnswerRequest { option: -1 });
    }

    #[test]
    fn rejects_malformed_question_dialog_answer_payloads() {
        assert!(DialogueAnswerRequest::parse(&Packet::new(116, vec![])).is_err());
        assert!(DialogueAnswerRequest::parse(&Packet::new(116, vec![1, 2])).is_err());
    }

    #[test]
    fn builds_java_custom_prayers_active_payload() {
        let mut prayer = PrayerState::new(40);
        prayer.activate(PrayerId::ProtectItems, 40).unwrap();
        prayer.activate(PrayerId::ProtectFromMissiles, 40).unwrap();

        let packet = build_prayers_active_packet(&prayer);

        assert_eq!(packet.opcode, OpcodeOut::SEND_PRAYERS_ACTIVE.wire());
        assert_eq!(packet.payload.len(), 14);
        assert_eq!(packet.payload[8], 1);
        assert_eq!(packet.payload[13], 1);
        assert!(packet
            .payload
            .iter()
            .enumerate()
            .all(|(idx, value)| (idx == 8 || idx == 13) || *value == 0));
    }

    #[test]
    fn builds_java_custom_ground_item_add_and_in_grid_remove_payload() {
        let origin = Position::new(100, 200);
        let packet = build_ground_item_delta_packet(
            origin,
            &[(Position::new(102, 198), 10)],
            &[(Position::new(99, 201), 20)],
        )
        .unwrap();

        assert_eq!(packet.opcode, OpcodeOut::SEND_GROUND_ITEM_HANDLER.wire());
        assert_eq!(
            packet.payload,
            vec![
                0x00, 0x0A, 0x02, 0xFE, // add item 10 at +2, -2
                0x80, 0x14, 0xFF, 0x01, // remove item 20 at -1, +1
            ]
        );
    }

    #[test]
    fn builds_java_custom_ground_item_clear_tile_payload_for_out_of_grid_remove() {
        let packet = build_ground_item_delta_packet(
            Position::new(100, 200),
            &[],
            &[(Position::new(117, 200), 20)],
        )
        .unwrap();

        assert_eq!(packet.opcode, OpcodeOut::SEND_GROUND_ITEM_HANDLER.wire());
        assert_eq!(packet.payload, vec![0xFF, 0x11, 0x00]);
    }

    #[tokio::test]
    async fn live_player_chat_update_uses_shared_java_custom_layout() {
        let mut state = ServerState::new();
        let (mut rx, player) =
            registered_logged_in_test_session(&mut state, 12346, "chatter").await;
        let player_index = {
            let mut p = player.write().await;
            p.pending_chat.push("hello".to_string());
            p.player_index
        };

        state.send_entity_updates().await;

        let coords_packet = rx.recv().await.unwrap();
        assert_eq!(coords_packet.opcode, OpcodeOut::SEND_PLAYER_COORDS.wire());
        let chat_packet = rx.recv().await.unwrap();
        let expected =
            crate::game::state_updater::build_custom_v235_player_chat_update_packet(&[(
                player_index,
                "",
                "hello",
            )]);

        assert_eq!(chat_packet.opcode, expected.opcode);
        assert_eq!(chat_packet.payload, expected.payload);
        assert!(player.read().await.pending_chat.is_empty());
    }

    #[test]
    fn maps_and_echoes_java_combat_style_payload() {
        assert_eq!(combat_style_from_wire(0), Some(CombatStyle::Controlled));
        assert_eq!(combat_style_from_wire(1), Some(CombatStyle::Aggressive));
        assert_eq!(combat_style_from_wire(2), Some(CombatStyle::Accurate));
        assert_eq!(combat_style_from_wire(3), Some(CombatStyle::Defensive));
        assert_eq!(combat_style_from_wire(4), None);
        assert_eq!(combat_style_to_wire(CombatStyle::Aggressive), 1);

        let packet = build_combat_style_packet(1);

        assert_eq!(packet.opcode, OpcodeOut::SEND_COMBAT_STYLE.wire());
        assert_eq!(packet.payload, vec![1]);
    }

    #[test]
    fn maps_bank_errors_to_java_style_messages() {
        assert_eq!(
            bank_error_message(&BankError::BankFull),
            Some("You don't have room for that in your bank")
        );
        assert_eq!(
            bank_error_message(&BankError::StackOverflow),
            Some("You don't have room for that in your bank")
        );
        assert_eq!(bank_error_message(&BankError::InvalidAmount), None);
        assert_eq!(bank_error_message(&BankError::ItemNotFound), None);
    }

    #[tokio::test]
    async fn live_walk_keeps_java_boundary_collision_opt_in() {
        let mut state = ServerState::new();
        state.game.java_locs_dir = None;
        state.initialize().await.unwrap();
        let (_rx, player) = logged_in_test_session(&mut state).await;
        {
            let mut p = player.write().await;
            p.position = Position::new(30, 30);
        }
        {
            let world = state.game.get_world("main").unwrap();
            let mut world = world.write().await;
            world.game_objects.insert(
                Position::new(30, 30),
                GameObject::new(1, Position::new(30, 30))
                    .with_type(1)
                    .with_direction(0),
            );
        }

        assert!(matches!(
            state
                .handle_packet(1, walk_to_point_packet(30, 30, &[(0, -1)]))
                .await,
            HandleResult::Continue
        ));

        let p = player.read().await;
        assert_eq!(
            p.walking_queue,
            vec![Position::new(30, 30), Position::new(30, 29)]
        );
    }

    #[tokio::test]
    async fn live_walk_uses_java_boundary_collision_when_locs_are_opted_in() {
        let mut state = ServerState::new();
        state.game.java_locs_dir = None;
        state.initialize().await.unwrap();
        state.game.java_locs_dir = Some(PathBuf::from("test-java-locs-enabled"));
        let (_rx, player) = logged_in_test_session(&mut state).await;
        {
            let mut p = player.write().await;
            p.position = Position::new(30, 30);
        }
        {
            let world = state.game.get_world("main").unwrap();
            let mut world = world.write().await;
            world.game_objects.insert(
                Position::new(30, 30),
                GameObject::new(1, Position::new(30, 30))
                    .with_type(1)
                    .with_direction(0),
            );
        }

        assert!(matches!(
            state
                .handle_packet(1, walk_to_point_packet(30, 30, &[(0, -1)]))
                .await,
            HandleResult::Continue
        ));

        let p = player.read().await;
        assert_eq!(p.walking_queue, vec![Position::new(30, 30)]);
    }

    #[tokio::test]
    async fn dispatches_shop_buy_to_live_handler() {
        let mut state = ServerState::new();
        let (mut rx, player) = logged_in_test_session(&mut state).await;
        {
            let mut p = player.write().await;
            assert!(p
                .inventory
                .add(crate::game::player::Item::stackable(10, 100)));
        }
        state.shop.open_shop(1, 2, 0).unwrap();

        let packet = PacketBuilder::new(236)
            .write_short(66)
            .write_short(10)
            .write_short(1)
            .build();

        assert!(matches!(
            state.handle_packet(1, packet).await,
            HandleResult::Continue
        ));

        let inventory_packet = rx.recv().await.unwrap();
        let shop_packet = rx.recv().await.unwrap();
        assert_eq!(inventory_packet.opcode, OpcodeOut::PlayerInventory.wire());
        assert_eq!(shop_packet.opcode, OpcodeOut::SEND_SHOP_OPEN.wire());
        let p = player.read().await;
        assert_eq!(p.inventory.count(66), 1);
        assert_eq!(p.inventory.count(10), 76);
        assert_eq!(state.shop.get_shop(2).unwrap().items()[0].amount, 4);
    }

    #[tokio::test]
    async fn dispatches_shop_sell_to_live_handler() {
        let mut state = ServerState::new();
        let (mut rx, player) = logged_in_test_session(&mut state).await;
        {
            let mut p = player.write().await;
            assert!(p.inventory.add(crate::game::player::Item::new(66, 2)));
        }
        state.shop.open_shop(1, 2, 0).unwrap();

        let packet = PacketBuilder::new(221)
            .write_short(66)
            .write_short(10)
            .write_short(1)
            .build();

        assert!(matches!(
            state.handle_packet(1, packet).await,
            HandleResult::Continue
        ));

        let inventory_packet = rx.recv().await.unwrap();
        let shop_packet = rx.recv().await.unwrap();
        assert_eq!(inventory_packet.opcode, OpcodeOut::PlayerInventory.wire());
        assert_eq!(shop_packet.opcode, OpcodeOut::SEND_SHOP_OPEN.wire());
        let p = player.read().await;
        assert_eq!(p.inventory.count(66), 1);
        assert_eq!(p.inventory.count(10), 14);
        assert_eq!(state.shop.get_shop(2).unwrap().items()[0].amount, 6);
    }

    #[tokio::test]
    async fn dispatches_shop_close_to_live_handler() {
        let mut state = ServerState::new();
        let (mut rx, _player) = logged_in_test_session(&mut state).await;
        state.shop.open_shop(1, 2, 0).unwrap();

        assert!(matches!(
            state.handle_packet(1, Packet::new(166, Vec::new())).await,
            HandleResult::Continue
        ));

        let close_packet = rx.recv().await.unwrap();
        assert_eq!(close_packet.opcode, OpcodeOut::CloseInterface.wire());
        assert!(!state.shop.has_shop_open(1));
    }

    #[tokio::test]
    async fn dispatches_npc_talk_to_compiled_content_runtime() {
        let mut state = ServerState::new();
        state.initialize().await.unwrap();
        let npc_index = {
            let world = state.game.get_world("main").unwrap();
            let mut world = world.write().await;
            let entity_id = world.spawn_npc_at(
                crate::game::content::beginner::GUIDE_STARTING_NPC_ID,
                Position::new(124, 647),
            );
            world.npcs.get(&entity_id).unwrap().npc_index
        };
        let (mut rx, _player) = logged_in_test_session(&mut state).await;

        let packet = PacketBuilder::new(153).write_short(npc_index).build();
        assert!(matches!(
            state.handle_packet(1, packet).await,
            HandleResult::Continue
        ));

        let message_packet = rx.recv().await.unwrap();
        assert_eq!(message_packet.opcode, OpcodeOut::ServerMessage.wire());
        assert_eq!(
            message_packet.payload,
            b"Welcome to the world of runescape\0".to_vec()
        );
    }

    #[tokio::test]
    async fn dispatches_npc_command_to_content_before_banker_fallback() {
        let mut state = ServerState::new();
        state.initialize().await.unwrap();
        let npc_index = {
            let world = state.game.get_world("main").unwrap();
            let mut world = world.write().await;
            let entity_id = world.spawn_npc_at(
                crate::game::content::beginner::GUIDE_STARTING_NPC_ID,
                Position::new(124, 647),
            );
            world.npcs.get(&entity_id).unwrap().npc_index
        };
        let (mut rx, _player) = logged_in_test_session(&mut state).await;

        let packet = PacketBuilder::new(202).write_short(npc_index).build();
        assert!(matches!(
            state.handle_packet(1, packet).await,
            HandleResult::Continue
        ));

        let message_packet = rx.recv().await.unwrap();
        assert_eq!(message_packet.opcode, OpcodeOut::ServerMessage.wire());
        assert_eq!(
            message_packet.payload,
            b"Speak to the guides and advisors on the island\0".to_vec()
        );
    }

    #[tokio::test]
    async fn dispatches_object_command_to_compiled_content_runtime_before_fallback() {
        let mut state = ServerState::new();
        state.initialize().await.unwrap();
        state.content = ContentRegistry::new();
        state.content.on_use_object(12345, 1, ObjectCommandMessage);
        {
            let world = state.game.get_world("main").unwrap();
            let mut world = world.write().await;
            world.game_objects.insert(
                Position::new(111, 222),
                GameObject::new(12345, Position::new(111, 222)),
            );
        }
        let (mut rx, _player) = logged_in_test_session(&mut state).await;

        let packet = PacketBuilder::new(79)
            .write_short(111)
            .write_short(222)
            .build();
        assert!(matches!(
            state.handle_packet(1, packet).await,
            HandleResult::Continue
        ));

        let message_packet = rx.recv().await.unwrap();
        assert_eq!(message_packet.opcode, OpcodeOut::ServerMessage.wire());
        assert_eq!(message_packet.payload, b"object 12345 command 1\0".to_vec());
    }

    #[tokio::test]
    async fn dispatches_boundary_command_to_compiled_content_runtime() {
        let mut state = ServerState::new();
        state.initialize().await.unwrap();
        state.content = ContentRegistry::new();
        state
            .content
            .on_use_boundary(2468, 1, BoundaryCommandMessage);
        {
            let world = state.game.get_world("main").unwrap();
            let mut world = world.write().await;
            world.game_objects.insert(
                Position::new(333, 444),
                GameObject::new(2468, Position::new(333, 444))
                    .with_type(1)
                    .with_direction(3),
            );
        }
        let (mut rx, _player) = logged_in_test_session(&mut state).await;

        let packet = PacketBuilder::new(127)
            .write_short(333)
            .write_short(444)
            .write_byte(3)
            .build();
        assert!(matches!(
            state.handle_packet(1, packet).await,
            HandleResult::Continue
        ));

        let message_packet = rx.recv().await.unwrap();
        assert_eq!(message_packet.opcode, OpcodeOut::ServerMessage.wire());
        assert_eq!(
            message_packet.payload,
            b"boundary 2468 command 1\0".to_vec()
        );
    }

    #[tokio::test]
    async fn dispatches_item_use_item_to_compiled_content_runtime() {
        let mut state = ServerState::new();
        state.initialize().await.unwrap();
        state.content = ContentRegistry::new();
        state
            .content
            .on_use_item_on_item(100, 200, ItemOnItemMessage);
        let (mut rx, player) = logged_in_test_session(&mut state).await;
        {
            let mut p = player.write().await;
            assert!(p
                .inventory
                .set_slot(2, crate::game::player::Item::new(100, 1)));
            assert!(p
                .inventory
                .set_slot(5, crate::game::player::Item::new(200, 1)));
        }

        let packet = PacketBuilder::new(91).write_short(2).write_short(5).build();
        assert!(matches!(
            state.handle_packet(1, packet).await,
            HandleResult::Continue
        ));

        let message_packet = rx.recv().await.unwrap();
        assert_eq!(message_packet.opcode, OpcodeOut::ServerMessage.wire());
        assert_eq!(
            message_packet.payload,
            b"item 100 slot 2 target 200 slot 5\0".to_vec()
        );
    }

    #[tokio::test]
    async fn dispatches_use_item_on_scenery_to_compiled_content_runtime() {
        let mut state = ServerState::new();
        state.initialize().await.unwrap();
        state.content = ContentRegistry::new();
        state
            .content
            .on_use_item_on_object(100, 12345, ItemOnObjectMessage);
        {
            let world = state.game.get_world("main").unwrap();
            let mut world = world.write().await;
            world.game_objects.insert(
                Position::new(111, 222),
                GameObject::new(12345, Position::new(111, 222)),
            );
        }
        let (mut rx, player) = logged_in_test_session(&mut state).await;
        {
            let mut p = player.write().await;
            assert!(p
                .inventory
                .set_slot(3, crate::game::player::Item::new(100, 1)));
        }

        let packet = PacketBuilder::new(115)
            .write_short(111)
            .write_short(222)
            .write_short(3)
            .build();
        assert!(matches!(
            state.handle_packet(1, packet).await,
            HandleResult::Continue
        ));

        let message_packet = rx.recv().await.unwrap();
        assert_eq!(message_packet.opcode, OpcodeOut::ServerMessage.wire());
        assert_eq!(
            message_packet.payload,
            b"item 100 slot 3 object 12345 at 111,222\0".to_vec()
        );
    }

    #[tokio::test]
    async fn dispatches_npc_use_item_to_compiled_content_runtime() {
        let mut state = ServerState::new();
        state.initialize().await.unwrap();
        state.content = ContentRegistry::new();
        state
            .content
            .on_use_item_on_npc(100, 54321, ItemOnNpcMessage);
        let npc_index = {
            let world = state.game.get_world("main").unwrap();
            let mut world = world.write().await;
            let entity_id = world.spawn_npc_at(54321, Position::new(124, 647));
            world.npcs.get(&entity_id).unwrap().npc_index
        };
        let (mut rx, player) = logged_in_test_session(&mut state).await;
        {
            let mut p = player.write().await;
            assert!(p
                .inventory
                .set_slot(3, crate::game::player::Item::new(100, 1)));
        }

        let packet = PacketBuilder::new(135)
            .write_short(npc_index)
            .write_short(3)
            .build();
        assert!(matches!(
            state.handle_packet(1, packet).await,
            HandleResult::Continue
        ));

        let message_packet = rx.recv().await.unwrap();
        assert_eq!(message_packet.opcode, OpcodeOut::ServerMessage.wire());
        assert_eq!(
            message_packet.payload,
            format!("item 100 slot 3 npc 54321 index {npc_index}\0").into_bytes()
        );
    }

    #[tokio::test]
    async fn dispatches_question_dialog_answer_to_compiled_content_runtime() {
        let mut state = ServerState::new();
        state.initialize().await.unwrap();
        state.content = ContentRegistry::new();
        state.content.on_dialogue_answer(DialogueAnswerMessage);
        let (mut rx, _player) = logged_in_test_session(&mut state).await;

        assert!(matches!(
            state.handle_packet(1, Packet::new(116, vec![2])).await,
            HandleResult::Continue
        ));

        let message_packet = rx.recv().await.unwrap();
        assert_eq!(message_packet.opcode, OpcodeOut::ServerMessage.wire());
        assert_eq!(message_packet.payload, b"dialogue option 2\0".to_vec());
    }

    #[tokio::test]
    async fn npc_command_still_opens_banker_when_content_does_not_handle_it() {
        let mut state = ServerState::new();
        state.initialize().await.unwrap();
        let npc_index = {
            let world = state.game.get_world("main").unwrap();
            let world = world.read().await;
            world
                .npcs
                .values()
                .find(|npc| npc.definition_id == 95)
                .unwrap()
                .npc_index
        };
        let (mut rx, _player) = logged_in_test_session(&mut state).await;

        let packet = PacketBuilder::new(202).write_short(npc_index).build();
        assert!(matches!(
            state.handle_packet(1, packet).await,
            HandleResult::Continue
        ));

        let bank_packet = rx.recv().await.unwrap();
        assert_eq!(bank_packet.opcode, OpcodeOut::SEND_BANK_OPEN.wire());
    }

    #[test]
    fn builds_java_custom_initial_server_configs_payload() {
        fn read_config_string(payload: &[u8], offset: &mut usize) -> String {
            let end = payload[*offset..]
                .iter()
                .position(|b| *b == 10)
                .map(|idx| *offset + idx)
                .expect("missing RSC string terminator");
            let value = String::from_utf8(payload[*offset..end].to_vec()).unwrap();
            *offset = end + 1;
            value
        }

        let packet = build_server_configs_packet();
        assert_eq!(packet.opcode, OpcodeOut::SEND_SERVER_CONFIGS.wire());

        let mut offset = 0usize;
        assert_eq!(
            read_config_string(&packet.payload, &mut offset),
            "OpenRSC Rust"
        );
        assert_eq!(
            read_config_string(&packet.payload, &mut offset),
            "OpenRSC Rust"
        );
        offset += 39;
        assert_eq!(
            read_config_string(&packet.payload, &mut offset),
            "Welcome to OpenRSC Rust"
        );
        offset += 2;
        assert_eq!(read_config_string(&packet.payload, &mut offset), "");
        offset += 41;
        assert_eq!(read_config_string(&packet.payload, &mut offset), "010001");
        let modulus = read_config_string(&packet.payload, &mut offset);

        assert_eq!(offset, packet.payload.len());
        assert!(!modulus.is_empty());
        assert_eq!(modulus.len() % 2, 0);
    }

    #[test]
    fn round_trips_inventory_records_without_losing_slots() {
        let mut player = Player::new(42, "persist".to_string());
        player
            .inventory
            .set_slot(3, crate::game::player::Item::new(10, 2));
        let mut equipped = crate::game::player::Item::new(20, 1);
        equipped.wielded = true;
        equipped.noted = true;
        player.inventory.set_slot(7, equipped);

        let records = build_inventory_records(99, &player);

        assert_eq!(records.len(), 2);
        assert_eq!(records[0].player_id, 99);
        assert_eq!(records[0].slot, 3);
        assert_eq!(records[0].item_id, 10);
        assert_eq!(records[0].amount, 2);
        assert_eq!(records[1].slot, 7);
        assert!(records[1].equipped);
        assert!(records[1].noted);

        let mut hydrated = crate::game::player::Inventory::new();
        apply_inventory_from_db(&mut hydrated, &records);

        assert_eq!(hydrated.items()[3].as_ref().unwrap().id, 10);
        assert_eq!(hydrated.items()[3].as_ref().unwrap().amount, 2);
        assert!(hydrated.items()[7].as_ref().unwrap().wielded);
        assert!(hydrated.items()[7].as_ref().unwrap().noted);
    }

    #[test]
    fn round_trips_bank_records_preserving_order() {
        let mut player = Player::new(42, "bankpersist".to_string());
        player
            .bank
            .deposit(crate::game::item::ItemId(10), 2)
            .unwrap();
        player
            .bank
            .deposit(crate::game::item::ItemId(20), 100)
            .unwrap();

        let records = build_bank_records(99, &player);

        assert_eq!(records.len(), 2);
        assert_eq!(records[0].player_id, 99);
        assert_eq!(records[0].slot, 0);
        assert_eq!(records[0].item_id, 10);
        assert_eq!(records[0].amount, 2);
        assert_eq!(records[1].slot, 1);
        assert_eq!(records[1].item_id, 20);
        assert_eq!(records[1].amount, 100);

        let mut hydrated = crate::game::bank_handler::PlayerBank::new(true);
        apply_bank_from_db(&mut hydrated, &records);

        let items = hydrated.items();
        assert_eq!(items.len(), 2);
        assert_eq!(items[0], (crate::game::item::ItemId(10), 2));
        assert_eq!(items[1], (crate::game::item::ItemId(20), 100));
    }
}

/// Apply a SkillsRecord from the DB onto an in-memory Skills container.
///
/// Combat skills (attack/def/str/hits/ranged/prayer/magic) have explicit
/// current-level columns in the DB; non-combat skills derive current from XP.
fn apply_skills_from_db(skills: &mut crate::game::skills::Skills, record: &SkillsRecord) {
    use crate::game::player::SkillId;
    // Combat — explicit current levels
    skills.set_skill_raw(
        SkillId::Attack,
        record.attack_xp as u32,
        record.attack_cur as u8,
    );
    skills.set_skill_raw(
        SkillId::Defence,
        record.defense_xp as u32,
        record.defense_cur as u8,
    );
    skills.set_skill_raw(
        SkillId::Strength,
        record.strength_xp as u32,
        record.strength_cur as u8,
    );
    skills.set_skill_raw(SkillId::Hits, record.hits_xp as u32, record.hits_cur as u8);
    skills.set_skill_raw(
        SkillId::Ranged,
        record.ranged_xp as u32,
        record.ranged_cur as u8,
    );
    skills.set_skill_raw(
        SkillId::Prayer,
        record.prayer_xp as u32,
        record.prayer_cur as u8,
    );
    skills.set_skill_raw(
        SkillId::Magic,
        record.magic_xp as u32,
        record.magic_cur as u8,
    );
    // Non-combat — current = base (derived from XP)
    skills.set_skill_xp(SkillId::Cooking, record.cooking_xp as u32);
    skills.set_skill_xp(SkillId::Woodcutting, record.woodcutting_xp as u32);
    skills.set_skill_xp(SkillId::Fletching, record.fletching_xp as u32);
    skills.set_skill_xp(SkillId::Fishing, record.fishing_xp as u32);
    skills.set_skill_xp(SkillId::Firemaking, record.firemaking_xp as u32);
    skills.set_skill_xp(SkillId::Crafting, record.crafting_xp as u32);
    skills.set_skill_xp(SkillId::Smithing, record.smithing_xp as u32);
    skills.set_skill_xp(SkillId::Mining, record.mining_xp as u32);
    skills.set_skill_xp(SkillId::Herblore, record.herblaw_xp as u32);
    skills.set_skill_xp(SkillId::Agility, record.agility_xp as u32);
    skills.set_skill_xp(SkillId::Thieving, record.thieving_xp as u32);
}

/// Serialize a Player's skill state into a SkillsRecord for DB persistence.
fn build_skills_record(db_id: i64, player: &Player) -> SkillsRecord {
    use crate::game::player::SkillId;
    let s = &player.skills;
    SkillsRecord {
        player_id: db_id,
        attack_xp: s.experience(SkillId::Attack) as i32,
        defense_xp: s.experience(SkillId::Defence) as i32,
        strength_xp: s.experience(SkillId::Strength) as i32,
        hits_xp: s.experience(SkillId::Hits) as i32,
        ranged_xp: s.experience(SkillId::Ranged) as i32,
        prayer_xp: s.experience(SkillId::Prayer) as i32,
        magic_xp: s.experience(SkillId::Magic) as i32,
        cooking_xp: s.experience(SkillId::Cooking) as i32,
        woodcutting_xp: s.experience(SkillId::Woodcutting) as i32,
        fletching_xp: s.experience(SkillId::Fletching) as i32,
        fishing_xp: s.experience(SkillId::Fishing) as i32,
        firemaking_xp: s.experience(SkillId::Firemaking) as i32,
        crafting_xp: s.experience(SkillId::Crafting) as i32,
        smithing_xp: s.experience(SkillId::Smithing) as i32,
        mining_xp: s.experience(SkillId::Mining) as i32,
        herblaw_xp: s.experience(SkillId::Herblore) as i32,
        agility_xp: s.experience(SkillId::Agility) as i32,
        thieving_xp: s.experience(SkillId::Thieving) as i32,
        attack_cur: s.current_level(SkillId::Attack) as i32,
        defense_cur: s.current_level(SkillId::Defence) as i32,
        strength_cur: s.current_level(SkillId::Strength) as i32,
        hits_cur: s.current_level(SkillId::Hits) as i32,
        ranged_cur: s.current_level(SkillId::Ranged) as i32,
        prayer_cur: s.current_level(SkillId::Prayer) as i32,
        magic_cur: s.current_level(SkillId::Magic) as i32,
    }
}

fn apply_inventory_from_db(
    inventory: &mut crate::game::player::Inventory,
    records: &[InventoryRecord],
) {
    for record in records {
        let mut item = crate::game::player::Item::new(record.item_id as u32, record.amount as u32);
        item.noted = record.noted;
        item.wielded = record.equipped;
        let _ = inventory.set_slot(record.slot as usize, item);
    }
}

fn build_inventory_records(db_id: i64, player: &Player) -> Vec<InventoryRecord> {
    player
        .inventory
        .items()
        .iter()
        .enumerate()
        .filter_map(|(slot, item)| {
            item.as_ref().map(|item| InventoryRecord {
                id: 0,
                player_id: db_id,
                slot: slot as i32,
                item_id: item.id as i32,
                amount: item.amount as i32,
                equipped: item.wielded,
                noted: item.noted,
            })
        })
        .collect()
}

fn apply_bank_from_db(bank: &mut crate::game::bank_handler::PlayerBank, records: &[BankRecord]) {
    for record in records {
        if record.amount <= 0 {
            continue;
        }
        let _ = bank
            .bank
            .deposit(record.item_id as u32, record.amount as u32);
    }
}

fn build_bank_records(db_id: i64, player: &Player) -> Vec<BankRecord> {
    player
        .bank
        .bank
        .items()
        .iter()
        .enumerate()
        .map(|(slot, item)| BankRecord {
            id: 0,
            player_id: db_id,
            slot: slot as i32,
            item_id: item.item_id as i32,
            amount: item.amount as i32,
        })
        .collect()
}

fn apply_settings_from_db(
    settings: &mut crate::game::player::PlayerSettings,
    record: &SettingsRecord,
) {
    settings.camera_auto = record.camera_auto;
    settings.one_mouse_button = record.one_mouse_button;
    settings.sound_off = record.sound_off;
    settings.block_chat = record.block_chat;
    settings.block_private = record.block_private;
    settings.block_trade = record.block_trade;
    settings.block_duel = record.block_duel;
}

fn build_settings_record(db_id: i64, player: &Player) -> SettingsRecord {
    SettingsRecord {
        player_id: db_id,
        camera_auto: player.settings.camera_auto,
        one_mouse_button: player.settings.one_mouse_button,
        sound_off: player.settings.sound_off,
        block_chat: player.settings.block_chat,
        block_private: player.settings.block_private,
        block_trade: player.settings.block_trade,
        block_duel: player.settings.block_duel,
    }
}

/// Snapshot a `Player` into a `Combatant` for the combat manager. Equipment
/// bonuses are zero for now — wire `Player::equipment.total_bonuses()` in
/// once equipment is fully wired.
fn combatant_from_player(p: &Player) -> Combatant {
    let s = &p.skills;
    let prayer_effects = crate::game::combat::PrayerEffects {
        attack_multiplier: 1.0 + p.prayer.attack_bonus() as f64 / 100.0,
        strength_multiplier: 1.0 + p.prayer.strength_bonus() as f64 / 100.0,
        defense_multiplier: 1.0 + p.prayer.defense_bonus() as f64 / 100.0,
        protect_item: p.prayer.has_protect_items(),
    };

    Combatant {
        entity_id: EntityId(p.id),
        is_npc: false,
        attack_level: s.current_level(SkillId::Attack) as u32,
        strength_level: s.current_level(SkillId::Strength) as u32,
        defense_level: s.current_level(SkillId::Defence) as u32,
        ranged_level: s.current_level(SkillId::Ranged) as u32,
        magic_level: s.current_level(SkillId::Magic) as u32,
        prayer_level: s.current_level(SkillId::Prayer) as u32,
        current_hp: s.current_level(SkillId::Hits) as u32,
        max_hp: s.level(SkillId::Hits) as u32,
        attack_bonus: 0,
        strength_bonus: 0,
        defense_bonus: 0,
        prayer_effects,
        combat_style: p.combat_style,
    }
}

/// Snapshot an `Npc` into a `Combatant`. Stats come from `npc_stats_for(def_id)`
/// — a tiny lookup until full NPC defs are loaded from the XML data files
/// (Java's `NPCDef.xml`).
fn combatant_from_npc(eid: EntityId, npc: &crate::game::world::Npc) -> Combatant {
    let (atk, str_, def) = npc_stats_for(npc.definition_id);
    Combatant {
        entity_id: eid,
        is_npc: true,
        attack_level: atk,
        strength_level: str_,
        defense_level: def,
        ranged_level: 1,
        magic_level: 1,
        prayer_level: 1,
        current_hp: npc.current_hits,
        max_hp: npc.max_hits,
        attack_bonus: 0,
        strength_bonus: 0,
        defense_bonus: 0,
        prayer_effects: Default::default(),
        combat_style: CombatStyle::Controlled,
    }
}

/// (attack, strength, defense) for known NPC defs. Anything missing falls
/// back to (1, 1, 1) so it slots in to combat without crashing. Numbers are
/// rough approximations of the Java NPCDef values; replace with a real loader
/// when world data is wired.
fn npc_stats_for(def_id: u32) -> (u32, u32, u32) {
    match def_id {
        1 => (3, 3, 1), // Man
        3 => (5, 5, 1), // Goblin
        5 => (1, 1, 1), // Chicken
        _ => (1, 1, 1),
    }
}
